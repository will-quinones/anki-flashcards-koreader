"""Run every Lua regression and native widget/TLS scenarios in an isolated Kobo process.

No hardware framebuffer, user collection, real API credentials or paid services.
Requires the device's SSH server and the Mac's openssl command.
"""
import argparse
import hashlib
import http.server
import io
import json
from pathlib import Path
import shlex
import shutil
import socket
import ssl
import subprocess
import tarfile
import tempfile
import threading
import time
import uuid
import urllib.parse

ROOT = Path(__file__).resolve().parents[2]


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        """Only synthetic catalog discovery, including the real TLS/fork path."""
        path = urllib.parse.urlsplit(self.path)
        provider = path.path.rsplit("/", 1)[-1]
        assert self.headers.get("Authorization") in (None, "Bearer synthetic", "Bearer synthetic-secret")
        assert self.headers.get("x-goog-api-key") in (None, "synthetic")
        query = urllib.parse.parse_qs(path.query)
        if provider == "gemini":
            data = {"models": [{"name": "models/gemini-synthetic", "supportedGenerationMethods": ["generateContent"]}]}
        elif provider == "openrouter":
            data = {"data": [{"id": "vendor/synthetic:free", "architecture": {"input_modalities": ["text"], "output_modalities": ["text"]}}]}
        elif provider == "dashscope":
            data = {"output": {"total": 1, "models": [{"model": "qwen-synthetic", "capabilities": ["TG"]}]}}
        elif provider == "openai":
            data = {"data": [{"id": "gpt-synthetic"}]}
        else:
            assert provider == "deepseek"
            data = {"data": [{"id": "deepseek-synthetic"}]}
        if query.get("slow"):
            time.sleep(2)
        raw = json.dumps(data).encode()
        try:
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            pass

    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        assert payload["stream"] is True
        assert self.headers["Authorization"] == "Bearer synthetic"
        prompt = payload["messages"][0]["content"]
        learning = "active-recall learning card" in prompt
        card = ({"question": "What is the synthetic fact?", "answer": "HIDDEN_ANSWER",
                 "explanation": "Synthetic explanation.", "evidence": "Synthetic evidence."}
                if learning else {"phrase": "action", "definition": "A synthetic test.",
                                  "ipa": "/əˈkʃən/", "synonyms": "", "text": "Take {{c1::action}} today."})
        raw = json.dumps(card, ensure_ascii=False)
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("Connection", "close")
        self.end_headers()
        def event(data):
            return "data: " + json.dumps(data) + "\n\n"

        reasoning = event({"id": "s" * 40, "object": "chat.completion.chunk", "created": 100,
                           "model": "synthetic", "system_fingerprint": "f" * 60,
                           "choices": [{"index": 0, "delta": {"content": None,
                                       "reasoning_content": "HIDDEN_REASONING " * 8}, "finish_reason": None}]})
        # A small visible card can have hundreds of kilobytes of SSE envelopes.
        reasoning_count = 262144 // len(reasoning) + 20
        frames = [": keep-alive\n\n",
                  event({"choices": [{"delta": {"role": "assistant", "content": ""},
                                       "finish_reason": None, "logprobs": None}]})]
        frames.extend(reasoning * min(20, reasoning_count - start) for start in range(0, reasoning_count, 20))
        frames.extend("data: " + json.dumps({"choices": [{"delta": {"content": raw[start:start + 16]}}]}) + "\n\n"
                      for start in range(0, len(raw), 16))
        frames.extend(["data: " + json.dumps({"choices": [{"delta": {}, "finish_reason": "stop"}]}) + "\n\n",
                       "data: " + json.dumps({"choices": [], "usage": {"total_tokens": 100}}) + "\n\n",
                       "data: [DONE]\n\n"])
        try:
            if self.path.endswith("/delayed"):
                time.sleep(23) # More than the former 20-second streaming timeout.
            for frame in frames:
                chunk = frame.encode()
                self.wfile.write(f"{len(chunk):X}\r\n".encode() + chunk + b"\r\n")
                self.wfile.flush()
                if not frame.startswith(reasoning):
                    time.sleep(0.18)
            self.wfile.write(b"0\r\n\r\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
            # Closing the modal deliberately kills its client connection.
            pass


def run(args):
    task = Path(tempfile.mkdtemp(prefix="anki-native-tests-"))
    remote = args.koreader.rstrip("/") + "/plugins/.anki-native-tests-" + uuid.uuid4().hex
    ssh = ["ssh", "-p", str(args.port), "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
           "-o", "StrictHostKeyChecking=yes", args.user + "@" + args.host]
    server = None
    staged = False
    try:
        subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-x509", "-sha256", "-nodes",
                        "-days", "1", "-subj", "/CN=localhost", "-keyout", str(task / "key.pem"),
                        "-out", str(task / "cert.pem")], check=True, capture_output=True)
        route = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        route.connect((args.host, args.port))
        address = route.getsockname()[0]
        route.close()
        server = http.server.ThreadingHTTPServer((address, 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(task / "cert.pem", task / "key.pem")
        server.socket = context.wrap_socket(server.socket, server_side=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()

        source = subprocess.check_output(["git", "ls-files", "-z", "AnkiFlashcards.koplugin/"], cwd=ROOT).decode().rstrip("\0").split("\0")
        assert all(Path(name).name != "configuration.lua" and not Path(name).name.startswith("anki_flashcards_settings.json") for name in source)
        tests = sorted(str(path.relative_to(ROOT)) for path in (ROOT / "tests").glob("test_*.lua"))
        support = [str(path.relative_to(ROOT)) for folder in (ROOT / "tests/support", ROOT / "tests/fixtures")
                   for path in folder.rglob("*") if path.is_file()]
        native = "tests/device/native_generation.lua"
        files = source + tests + support + [native]
        manifest = "".join(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() + "  " + name + "\n" for name in files)
        buffer = io.BytesIO()
        with tarfile.open(fileobj=buffer, mode="w:gz") as archive:
            for name in files:
                archive.add(ROOT / name, arcname=name, recursive=False)
            data = manifest.encode()
            item = tarfile.TarInfo("SHA256SUMS")
            item.size = len(data)
            archive.addfile(item, io.BytesIO(data))
        command = "set -eu\nmkdir " + shlex.quote(remote) + "\ntar -xzf - -C " + shlex.quote(remote)
        staged = True
        result = subprocess.run(ssh + [command], input=buffer.getvalue(), capture_output=True, timeout=45)
        if result.returncode:
            raise RuntimeError(result.stderr.decode(errors="replace"))
        print("Native test files transferred; verifying before execution.", flush=True)
        endpoint = "https://" + address + ":" + str(server.server_port) + "/mock"
        command = f"""set -eu
cd {shlex.quote(remote)}
sha256sum -c SHA256SUMS >/dev/null
count=0
for test in tests/test_*.lua; do
    if {shlex.quote(args.koreader + '/luajit')} "$test" >unit-output.log 2>&1; then
        count=$((count+1))
    else
        echo "DEVICE_UNIT_FAILED: $test"
        cat unit-output.log
        exit 1
    fi
done
test "$count" -eq {len(tests)}
echo "DEVICE_LUA_TESTS_PASS_$count"
cd {shlex.quote(args.koreader)}
{shlex.quote(args.koreader + '/luajit')} {shlex.quote(remote + '/' + native)} {shlex.quote(remote)} {shlex.quote(endpoint)}
"""
        result = subprocess.run(ssh + [command], capture_output=True, text=True, timeout=150)
        if result.returncode:
            print(result.stdout + result.stderr, flush=True)
            return result.returncode
        for line in result.stdout.splitlines():
            if "NATIVE_" in line or "DEVICE_LUA_TESTS_PASS_" in line:
                print(line, flush=True)
        expected = {"NATIVE_IN_PLACE_RENDER_PASS", "NATIVE_TRANSPORT_RETRY_PASS", "NATIVE_DELAYED_FIRST_BYTE_PASS", "NATIVE_AI_SETTINGS_PASS",
                    "NATIVE_LEARN_STREAMING_PASS", "NATIVE_CANCELLATION_PASS", "NATIVE_MODEL_CATALOG_PASS"}
        assert expected.issubset(set(result.stdout.splitlines()))
        return 0
    finally:
        if staged:
            # Only remove the unique directory created for this invocation.
            cleanup = subprocess.run(ssh + ["if [ -d " + shlex.quote(remote) + " ]; then rm -r " + shlex.quote(remote) + "; fi"],
                                     capture_output=True, timeout=20)
            if cleanup.returncode:
                raise RuntimeError("Could not remove the native test directory")
        if server:
            server.shutdown()
            server.server_close()
        shutil.rmtree(task)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=2222)
    parser.add_argument("--user", default="root")
    parser.add_argument("--koreader", default="/mnt/onboard/.adds/koreader")
    raise SystemExit(run(parser.parse_args()))
