"""Documentation payloads must remain compatible with the plugin schema."""
import json
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
        ["luajit", "-e", '''local p=dofile("AnkiFlashcards.koplugin/note_types.lua").model_params()
print(p.modelName); print(tostring(p.isCloze)); print(table.concat(p.inOrderFields,"\\t"))
print(p.css); print(p.cardTemplates[1].Name); print(p.cardTemplates[1].Front); print(p.cardTemplates[1].Back)'''],
        cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout.splitlines()
    template = model["cardTemplates"][0]
    assert output == [model["modelName"], "true", "\t".join(model["inOrderFields"]),
                      model["css"], template["Name"], template["Front"], template["Back"]]


def test_learning_payload_matches_runtime_schema():
    model = payload("create-learning-note-type.json")
    code = '''
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
