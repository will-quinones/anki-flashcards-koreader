"""Documentation payloads must remain compatible with the plugin schema."""
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def payload(name):
    data = json.loads((ROOT / "anki" / name).read_text(encoding="utf-8"))
    assert data["action"] == "createModel" and data["version"] == 6
    return data["params"]


def test_vocabulary_payload_is_valid_cloze():
    model = payload("create-note-type.json")
    assert model["modelName"] == "KOReader Vocabulary" and model["isCloze"] is True
    assert model["inOrderFields"] == [
        "Phrase", "IPA", "Definition", "Synonyms", "Text", "Source",
        "ImageFront", "ImageBack", "Sound",
    ]
    assert len(model["cardTemplates"]) == 1
    assert "{{cloze:Text}}" in model["cardTemplates"][0]["Front"]
    assert "{{cloze:Text}}" in model["cardTemplates"][0]["Back"]
    output = subprocess.run(
        ["luajit", "-e", '''package.path="AnkiFlashcards.koplugin/?.lua;"..package.path
local p=dofile("AnkiFlashcards.koplugin/note_types.lua").model_params()
print(p.modelName); print(tostring(p.isCloze)); print(table.concat(p.inOrderFields,"\\t"))
print(p.css); print(p.cardTemplates[1].Name); print(p.cardTemplates[1].Front); print(p.cardTemplates[1].Back)'''],
        cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    template = model["cardTemplates"][0]
    assert output == [model["modelName"], "true", "\t".join(model["inOrderFields"]),
                      model["css"], template["Name"], template["Front"], template["Back"]]


def test_minimal_design_preserves_fields_and_answer_separation():
    for filename in ("create-note-type.json", "create-learning-note-type.json"):
        model = payload(filename)
        declared = set(model["inOrderFields"])
        template = model["cardTemplates"][0]
        for side in ("Front", "Back"):
            stack = []
            for token in re.findall(r"{{(.*?)}}", template[side]):
                name = token.lstrip("#^/").removeprefix("cloze:")
                assert name in declared, (filename, token)
                if token.startswith(("#", "^")):
                    stack.append(name)
                elif token.startswith("/"):
                    assert stack.pop() == name
            assert not stack
            assert "<script" not in template[side].lower()
        assert "url(" not in model["css"] and "@import" not in model["css"]
        assert "max-width:640px" in model["css"] and "max-width:480px" in model["css"]
        if model["isCloze"]:
            assert "{{Phrase}}" not in template["Front"]
            assert "{{Sound}}" in template["Back"]
        else:
            assert "{{Question}}" in template["Front"]
            for name in ("Answer", "Explanation", "SourceExcerpt", "SelectedText", "Context", "PluginID"):
                assert "{{" + name + "}}" not in template["Front"]
            assert "{{Answer}}" in template["Back"] and "{{SourceExcerpt}}" in template["Back"]
            assert "{{PluginID}}" not in template["Back"] and "{{Context}}" not in template["Back"]


def test_design_text_contrast_in_light_and_dark():
    css = payload("create-learning-note-type.json")["css"]

    def luminance(color):
        rgb = [int(color[i:i+2], 16) / 255 for i in (1, 3, 5)]
        rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
        return sum(a * b for a, b in zip(rgb, (0.2126, 0.7152, 0.0722)))

    for selector in (r"\.card", r"\.nightMode,\.night_mode"):
        block = re.search(selector + r"\{([^}]+)\}", css).group(1)
        colors = dict(re.findall(r"--(\w+):(#[0-9a-f]{6})", block))
        for fg, bg in (("fg", "bg"), ("muted", "bg"), ("accent", "bg"), ("accent", "soft")):
            values = sorted((luminance(colors[fg]), luminance(colors[bg])))
            assert (values[1] + 0.05) / (values[0] + 0.05) >= 4.5


def test_learning_payload_matches_runtime_schema():
    model = payload("create-learning-note-type.json")
    code = '''
package.path="AnkiFlashcards.koplugin/?.lua;"..package.path
local p = dofile("AnkiFlashcards.koplugin/learning_card.lua").model_params()
print(p.modelName)
print(tostring(p.isCloze))
print(table.concat(p.inOrderFields, "\\t"))
print(p.css)
print(p.cardTemplates[1].Name)
print(p.cardTemplates[1].Front)
print(p.cardTemplates[1].Back)
'''
    output = subprocess.run(
        ["luajit", "-e", code], cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    template = model["cardTemplates"][0]
    assert output == [
        model["modelName"], "false", "\t".join(model["inOrderFields"]),
        model["css"], template["Name"], template["Front"], template["Back"],
    ]
    assert model["isCloze"] is False and model["inOrderFields"][0] == "PluginID"
    assert len(model["cardTemplates"]) == 1
