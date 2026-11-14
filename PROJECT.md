# PROJECT.md

## Purpose
Let English-speaking players run Japanese Windows indie games on Linux by
double-click, and read them in English using a translation server they run themselves.

## In scope
- `winrun`: per-game Wine prefix, working directory, DLL overrides, logs, crash report.
- File-manager registration (`install.sh` / `uninstall.sh`, `wl-desktop`).
- Layer A: `wl-translate` installs BepInEx + XUnity.AutoTranslator for Unity games and
  points them at a local `CustomTranslate` endpoint.
- `wl-scan`: read-only library inventory.
- Layer B plan for engines whose text is plain data (`docs/LAYER-B.md`).

## Out of scope (for now)
- A bundled translation server or model.
- Proton/Steam integration, DXVK management, game downloads or storefront support.
- Redistributing BepInEx, XUnity or any game content.

## Success checks
- Double-clicking an `.exe` starts it in its own prefix, from its own folder
  (`tests/verify-install.sh`).
- A startup crash produces a message with the exit code and log path.
- `wl-translate --apply` then `--uninstall --apply` leaves the game folder
  byte-identical (`tests/run-tests.sh`).
- No configuration written by this tool can send text to a cloud service.

## Map
| Role | Path |
|---|---|
| Launcher | `bin/winrun` |
| Translation installer | `bin/wl-translate` |
| Inventory | `bin/wl-scan`, `lib/wlcommon.py` |
| Menu entries | `bin/wl-desktop` |
| MIME default editing | `lib/mimeapps.py` |
| Install / uninstall | `install.sh`, `uninstall.sh`, `share/winlauncher.desktop.in` |
| Tests | `tests/run-tests.sh` (offline), `tests/verify-install.sh` (real machine) |
| Layer B plan | `docs/LAYER-B.md` |
