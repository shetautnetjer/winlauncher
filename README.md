# winlauncher

Play Japanese Windows indie games on Linux, in English, offline.

- **Double-click an `.exe`** in your file manager and it runs under Wine, each game in
  its own isolated Wine prefix, started from its own folder.
- **In-game English for Unity games**, translated by a machine-translation server
  *you* run locally. No accounts, no cloud services, no telemetry.
- **Reversible and careful.** No root. Nothing in a game folder is touched unless you
  ask for translation, and then every replaced file is backed up and can be restored
  byte-for-byte.

Plain bash and Python 3, no other dependencies. Built for games you own: it ships no
game files, no translations and no third-party binaries.

## Requirements

- Linux with a desktop that reads freedesktop MIME settings (GNOME/Nautilus tested;
  KDE/Dolphin should work the same way).
- Wine (tested with Wine 10.0, WoW64 build). Proton/Steam are not used.
- `python3`, `xdg-utils`, `util-linux` (`flock`), `coreutils`. Optional: `zenity`
  for error dialogs, `x11-utils` for `--desktop` focus handling, `xvfb-run` for
  headless testing.

## Install

```bash
git clone <this repo> ~/tools/winlauncher
cd ~/tools/winlauncher
./install.sh                 # commands into ~/.local/bin, .exe handler registered and made default
./tests/verify-install.sh    # checks the registration, then a real-Wine self-test (opens no windows)
```

`./install.sh --no-default` registers the handler (it appears in *Open With*) without
changing your current default. `./uninstall.sh` reverses everything and puts your
previous `.exe` default back. Both are idempotent.

What install touches, and nothing else:

| Path | Change |
|---|---|
| `~/.local/bin/{winrun,wl-translate,wl-scan,wl-desktop}` | symlinks into the repo |
| `~/.local/share/applications/winlauncher.desktop` | the `.exe` handler |
| `~/.local/share/applications/mimeinfo.cache` | rebuilt by `update-desktop-database` |
| `~/.config/mimeapps.list` | three `.exe` MIME lines; previous values saved, original copied once to `mimeapps.list.winlauncher-backup-<time>` |

Uninstall keeps your Wine prefixes (`~/.local/share/winlauncher/prefixes/`), because
that's where games keep their saves.

## Double-click

After install, double-click a game's `.exe`. To check the setup:

1. `xdg-mime query default application/x-msdownload` prints `winlauncher.desktop`
   (also for `application/vnd.microsoft.portable-executable`).
2. In Nautilus: right-click the `.exe` → **Properties → Open With** shows
   *Run with Wine (winlauncher)*.
3. Without a file manager: `xdg-open "/path/to/Game.exe"`.
4. If your file manager still refuses, add an app-menu entry for that game:
   `wl-desktop add "/path/to/Game.exe"`. The entry launches by id, so spaces, brackets
   and Japanese characters in the path can't break it.

## winrun

```bash
winrun "/path/to/Game.exe" [args]   # run
winrun --info  "/path/to/Game.exe"  # id, prefix, log and config paths
winrun --dry-run "/path/to/Game.exe"
winrun --list                       # every game seen, with its last result
winrun --kill --id <id>             # stop a stuck game
winrun --winecfg --id <id>          # winecfg for that game's prefix
winrun --desktop [WxH] "/path/to/Game.exe"   # run inside a Wine virtual desktop window
```

- **One prefix per game:** `~/.local/share/winlauncher/prefixes/<id>`, where
  `id = sha256(absolute folder of the exe)[:16]`. Moving a game folder gives it a new
  prefix; copy the old one across to keep saves.
- **First run is offline-safe:** the prefix is built with `wineboot -i`. If wine-mono or
  wine-gecko aren't installed system-wide they are disabled, not downloaded. Wine's
  menu builder is disabled, so Wine adds no menu entries or file associations.
- **32-bit games:** on WoW64-only Wine builds every prefix is win64 and 32-bit games
  run through WoW64. The exe's bitness is logged on every run.
- **Every launch** runs from the exe's folder (many games load assets relative to it),
  sets `WINEDLLOVERRIDES=winhttp=n,b;winemenubuilder.exe=d` so a plugin loader in the
  game folder works, and forces a UTF-8 locale if the session has none (Wine converts
  filenames through the locale; a C locale breaks Japanese paths).
- **Logs:** `~/.local/state/winlauncher/games/<id>/last.log`, plus `prev.log`,
  `bootstrap.log` and a `runs.tsv` history.
- **Startup crashes are reported:** if a game exits with an error within 20 s, you get a
  dialog with the exit code, the last `err:` lines and the log path. winrun waits for
  the whole prefix, so launchers that hand off to the real game are timed correctly.
- **One instance per game.** A second double-click says it's already running.
- **Invisible window, or keyboard does nothing?** On some Wayland desktops a Wine
  window maps and renders but is never shown on top, or never gets keyboard focus, so
  WASD/arrows go to another window. `--desktop` runs the game inside one ordinary
  Wine virtual-desktop window, then raises it and gives it keyboard focus as soon as
  it appears (up to ~12 s). To make that the default for one game, put
  `WL_VIRTUALDESK=1` in its config (below). Focus handling needs `x11-utils`; without
  it, or without an X display, it is skipped and the game still runs.
- **Per-game settings** in `~/.config/winlauncher/games/<id>.conf` (bash):

  ```bash
  WL_LOCALE=ja_JP.UTF-8            # Shift-JIS engines (WolfRPG, older RPG Maker)
  WL_DLLOVERRIDES_EXTRA="d3d11=n"  # appended to the default overrides
  WL_EXTRA_ARGS=(-screen-fullscreen 0)
  WL_STARTUP_SECS=40
  WL_VIRTUALDESK=1                 # always use --desktop for this game
  WL_VIRTUALDESK_SIZE=1280x720
  ```

## In-game English

### Translation endpoint (you provide it)

Translation goes through a local HTTP server that speaks XUnity.AutoTranslator's
`CustomTranslate` protocol:

```
GET http://127.0.0.1:8765/translate?from=ja&to=en&text=<url-encoded source>
→ 200 with the translation as the plain response body
```

Any server that answers that way works, for example a small wrapper around a local
LLM or a Japanese→English model, with a cache so repeated lines are instant. This repo
does not include one. Change the address with `--endpoint` or `WL_ENDPOINT`.

### Layer A: runtime replacement (Unity)

```bash
wl-translate "/path/to/game folder"            # dry run: lists every file it would create or overwrite
wl-translate "/path/to/game folder" --apply    # install
wl-translate "/path/to/game folder" --uninstall --apply [--remove-runtime-files]
```

It installs BepInEx + XUnity.AutoTranslator into the game folder and configures XUnity
for your endpoint:

- `[Service] Endpoint=CustomTranslate` and `FallbackEndpoint=` (empty), so XUnity can
  never fall back to a cloud translator. XUnity's own default config uses Google.
- `[Custom] Url=<your endpoint>`, `[General] FromLanguage=ja`, `Language=en`.
- An existing config keeps all its other settings; it is backed up first, and XUnity's
  UTF-8 byte-order mark is preserved.
- If BepInEx or XUnity is already installed by something else, those files are left
  alone and only the config is corrected. Mixing BepInEx 5 and 6 is refused.
- Every overwritten file is copied to `<file>.wl-bak-<time>` beside it. Every created
  file is recorded with its sha256 in `<game>/.winlauncher-translate.json`.
- Uninstall restores the backups and removes only files byte-identical to what it
  installed. Anything changed since, and (with `--remove-runtime-files`) BepInEx's logs
  and your generated translations, is *moved* to
  `~/.local/state/winlauncher/translate-leftovers/`, never deleted.

**Packages are not bundled.** Download them once into `~/.local/share/winlauncher/pkgs`
(or point `--pkgs` / `WL_PKGS` elsewhere). The dry run names any that are missing.

| Unity build | Packages |
|---|---|
| Mono, 64-bit | `BepInEx_win_x64_5.4.x.zip` + `XUnity.AutoTranslator-BepInEx-5.x.zip` |
| Mono, 32-bit | `BepInEx_win_x86_5.4.x.zip` + `XUnity.AutoTranslator-BepInEx-5.x.zip` |
| IL2CPP | `BepInEx-Unity.IL2CPP-win-x64-6.0.0-be.<N>.zip` + `XUnity.AutoTranslator-BepInEx-IL2CPP-<ver>.zip` |

Sources: [BepInEx releases](https://github.com/BepInEx/BepInEx/releases),
[BepInEx bleeding-edge builds](https://builds.bepinex.dev/projects/bepinex_be),
[XUnity.AutoTranslator releases](https://github.com/bbepis/XUnity.AutoTranslator/releases).

**IL2CPP caveat:** on a game's first start, BepInEx 6 builds interop assemblies and
downloads Unity base libraries for that Unity version from `unity.bepinex.dev`. That
first launch needs network once (or a pre-staged `BepInEx/unity-libs`); after that it
runs offline. Not yet verified end to end.

A harmless log warning you may see: `Could not hook 'TMP_Text_SetCharArray_Hook3'`.
Translation still works.

### Layer B: English written into the game files

For engines whose text is plain data (RPG Maker MV/MZ, Electron/NW.js, Godot, Flash,
WolfRPG), see [docs/LAYER-B.md](docs/LAYER-B.md): which can be done end to end with
free command-line tools, and where the catches are. Not automated yet.

## Library inventory

```bash
wl-scan ~/Games            # read-only table: engine, bitness, launcher and translation state per game
wl-scan ~/Games --write    # also writes status/STATUS.md and status/library-map.tsv (git-ignored)
```

It flags any XUnity config that points at a cloud translator. Its ids are winrun's
prefix ids. `WL_LIBRARY` sets the default folder.

## Tests

- `tests/run-tests.sh`: 59 offline checks with a fake Wine. They cover awkward paths
  (spaces, brackets, Japanese, quotes, `$`), working directory, prefix ids and
  isolation, crash reporting, the single-instance lock, `--desktop` mode and focus
  fallback, `mimeapps.list` set/restore
  byte-for-byte, and `wl-translate` dry run / apply / re-apply / byte-for-byte
  uninstall / existing-install protection / BOM configs / cloud-endpoint correction.
  Runs in CI.
- `tests/verify-install.sh`: on your machine after install. Checks the registration,
  then runs Wine's own `cmd.exe` (64- and 32-bit) from throwaway folders with tricky
  names, plus a truncated exe to prove crash reporting. Opens no windows.

## Known limits

- Graphics use Wine's built-in wined3d (OpenGL), not DXVK. Slow D3D11 titles may want
  DXVK copied into that one game's prefix; not automated.
- 32-bit Mono and IL2CPP installs are implemented and unit-tested, but not yet verified
  on a real game.
- Tested on Ubuntu 26.04 with GNOME. Reports from other distros and file managers are
  welcome.

## Legal

This tool launches and modifies games you already own, on your own machine. It doesn't
include or download game content, and it isn't affiliated with Wine, BepInEx, XUnity or
any game publisher. Some game licenses forbid modification; that's between you and the
license. BepInEx and XUnity.AutoTranslator are separate projects under their own
licenses, downloaded by you from their official pages.

## License

[MIT](LICENSE)
