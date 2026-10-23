"""Run every standalone Lua/Python test without pytest or a KOReader install."""
import ast
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]


def main():
    luajit = shutil.which("luajit")
    if not luajit:
        print("ERROR: LuaJIT is required to run the complete test suite.", file=sys.stderr)
        return 1
    cases = [(str(path.relative_to(ROOT)), [luajit, str(path)])
             for path in sorted((ROOT / "tests").glob("test_*.lua"))]
    for path in sorted((ROOT / "tests").glob("test_*.py")):
        tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        functions = [node.name for node in tree.body
                     if isinstance(node, ast.FunctionDef) and node.name.startswith("test_")]
        if not functions:
            raise RuntimeError(f"No test functions found in {path}")
        for name in functions:
            # Each case starts in a separate process, just like Lua tests.
            command = [sys.executable, "-c",
                       "import runpy,sys; runpy.run_path(sys.argv[1])[sys.argv[2]]()",
                       str(path), name]
            cases.append((f"{path.relative_to(ROOT)}::{name}", command))
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    failures = []
    for name, command in cases:
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                                    capture_output=True, timeout=60)
            if result.returncode:
                failures.append(name)
                print(f"FAIL {name}\n{result.stdout}{result.stderr}", flush=True)
            else:
                print(f"PASS {name}", flush=True)
        except subprocess.TimeoutExpired:
            failures.append(name)
            print(f"FAIL {name}: timed out after 60 seconds", flush=True)
    sources = sorted(path for path in (ROOT / "AnkiFlashcards.koplugin").glob("*.lua")
                     if path.name != "configuration.lua")
    syntax = subprocess.run([luajit, "-e", "for path in io.lines() do assert(loadfile(path)) end"],
                            input="".join(str(path) + "\n" for path in sources),
                            cwd=ROOT, env=env, text=True, capture_output=True, timeout=60)
    if syntax.returncode:
        failures.append("Lua syntax")
        print(f"FAIL Lua syntax\n{syntax.stderr}", flush=True)
    else:
        print(f"PASS Lua syntax ({len(sources)} modules)", flush=True)
    failed_cases = sum(name in failures for name, _ in cases)
    print(f"\n{len(cases) - failed_cases}/{len(cases)} tests passed; "
          f"{failed_cases} failed; 0 skipped.", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
