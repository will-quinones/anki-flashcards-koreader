# Maintaining this fork

This repository is a customized KOReader plugin. The current behavior is
documented in README.md. LOCAL_CHANGES.md contains historical decisions;
older sections may describe menus that have since been retired.

## Preserve these product decisions

- Use one native Tools → Anki Flashcards tree: Configuración, Tarjetas and
  Estadísticas por libro. Do not restore the separate Anki Manage panel,
  selection-side My Cards buttons, note-type selectors or generation profiles.
- Selection and dictionary actions are Anki Vocab and Anki Learn. Preserve
  their registration IDs so existing KOReader button layouts keep working.
- Every existing highlight, including purple highlights and highlights with
  saved cards, opens KOReader's native actions. Do not intercept taps to call
  AI, open cards, add annotations or overwrite personal notes. Keep the native
  compact toolbar accessible through Editar subrayado for boundary editing.
- Annotation-list generation is Learn-only. Preserve pagination, fixed-width
  checkbox/action columns, native context and source validation.
- Vocab and Learn generation share a cancellable streaming modal. Closing, suspend and
  document teardown cancel work and pending retries. Never save partial output.
- Save is explicit. Sending to Anki and confirmed annotation batches may also
  persist cards. Do not restore automatic saving on preview or regeneration of
  an unsaved preview. Failed/cancelled regeneration keeps the previous card.
- Optional highlighting runs only after a successful explicit Save and only
  for multiword original selections. Manual highlighting still permits one word.
- Local deletion and remote Anki deletion remain distinct, confirmed actions.
  Do not delete Anki notes or book annotations as a side effect of local cleanup.
- Keep background sending outside the UI thread, stable card identities,
  atomic writes, reconciliation safeguards and stale-media rejection.
- Configuration uses settings_state.lua for normalization and migration.
  Private settings stay inside the plugin; cards/media/runtime stay under
  settings/ankiflashcards/. Never overwrite keys or drop migration support.

## Upstream integration

- origin is will-quinones/anki-flashcards-koreader; upstream is the author's
  lgallard/anki-flashcards-koreader repository.
- Review upstream changes on a separate maintenance branch. Fetch first;
  inspect each change and its dependencies before incorporating it. A clean
  textual merge does not establish compatibility with these product decisions.
- Adopt compatible fixes/features with provenance, adapting their UI and tests
  to this fork. Do not import release metadata as if it were a fork release.
- Record the reviewed upstream revision and any adaptations in UPSTREAM.md.
- Preserve regression intent when updating test fixtures. Fix missing mocks;
  do not skip tests or weaken persistence/cancellation/isolation checks.

## Validation and delivery

- Run `python3 tests/run_tests.py` before committing or publishing changes.
  All Lua/Python cases and Lua syntax checks must pass without skipped cases.
- Use test credentials and simulated services. Do not send cards, contact paid
  generation APIs or change real collections while running local tests.
- Native regressions run through `python3 tests/device/run_native.py --host <IP>`.
  They use offscreen buffers, a synthetic book and a temporary local TLS service;
  they must never initialize the hardware framebuffer or load real API keys.
- Keep configuration.lua, anki_flashcards_settings.json, their temporary files,
  and generated user data out of commits and deployment packages.
- Device installation and visual validation are separate tasks. Do not deploy
  or create automatic backups unless the user requests them.
