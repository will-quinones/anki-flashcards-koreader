# AnkiFlashcards fork

Read [AGENTS.md](AGENTS.md) before changing this repository. Its compatibility
rules apply to upstream updates, refactoring and test maintenance.

- [README.md](README.md): current behavior, native menus, configuration and installation.
- [LOCAL_CHANGES.md](LOCAL_CHANGES.md): local decisions and their history.
- [UPSTREAM.md](UPSTREAM.md): reviewed upstream revisions and integration decisions.

The plugin uses Lua 5.1/LuaJIT and KOReader's native widgets. Follow the existing
module style, four-space indentation and gettext for user-facing strings.
`scheduleIn` only defers work; it does not move blocking network I/O out of the
UI thread. Use the cancellable subprocess mechanisms for Vocab text generation
and automatic Anki delivery.

Configuration is optional and loaded through `pcall`; credentials remain
private and must never be committed, printed or overwritten during installation.
Use `settings_state.lua` for shared configuration rules and `storage_paths.lua`
for persistent data locations.

Run the complete standalone suite with:

```sh
python3 tests/run_tests.py
```

This checks every Lua/Python case and Lua syntax without device credentials.
Local tests do not establish physical e-ink rendering or device connectivity.
