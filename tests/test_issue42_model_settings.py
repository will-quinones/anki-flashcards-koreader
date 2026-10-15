import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PLUGIN = ROOT / "AnkiFlashcards.koplugin"


def read(name: str) -> str:
    return (PLUGIN / name).read_text(encoding="utf-8")


def test_ai_provider_settings_expose_provider_model_fields():
    settings = read("settings_viewer.lua")

    for key in [
        "model",
        "image_model",
        "gemini_text_model",
        "gemini_image_model",
        "openai_model",
        "openai_image_model",
        "openrouter_model",
        "openrouter_image_model",
    ]:
        assert re.search(rf'key\s*=\s*"{key}"', settings)

    assert "Modelo de IA" in settings
    assert "Cuenta y modelo de IA" in settings


def test_image_generators_use_configurable_model_names():
    image_generator = read("image_generator.lua")

    assert 'config.image_model or "qwen-image-plus"' in image_generator
    assert 'config.gemini_image_model or "gemini-3.1-flash-image"' in image_generator
    assert 'config.openai_image_model or "gpt-image-1"' in image_generator
    assert 'config.openrouter_image_model or "google/gemini-3.1-flash-image-preview"' in image_generator


def test_configuration_sample_is_minimal_and_has_no_note_type_setting():
    sample = read("configuration.lua.sample")

    assert 'model = "qwen-plus"' in sample
    assert 'image_provider = "none"' in sample
    assert 'anki_model =' not in sample
    assert not re.search(r'model\s*=\s*"KOReader (Vocabulary|Learn)"', sample)


def test_legacy_custom_anki_model_migrates_without_overriding_text_model():
    settings = read("settings_viewer.lua")
    state = read("settings_state.lua")
    main = read("main.lua")
    manager = read("card_manager.lua")

    assert 'State.persistable(State.merge(base, Storage.load_anki_settings()))' in settings
    assert 'not saved.settings_version and not saved.anki_model' in state
    assert 'not saved_anki.settings_version and not saved_anki.anki_model' in main
    assert "saved_anki.anki_model = saved_anki.model" in main
    assert "saved_anki.model = nil" in main
    assert 'cfg.model = base and base.model or "qwen-plus"' in state
    assert 'SettingsState.merge(CONFIGURATION, CardStorage.load_anki_settings())' in main
    assert 'SettingsState.merge(base, CardStorage.load_anki_settings())' in manager
    assert 'clean.settings_version = 2' in state

    # Legacy `model` is an Anki note type, not a provider model. Do not
    # classify a user-defined note type with a hard-coded allowlist.
    migration = main.split("CONFIGURATION.anki = saved_anki", 1)[0]
    assert "Vocabulary" not in migration
    assert "English" not in migration
