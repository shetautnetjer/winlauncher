# DECISIONS.md (append-only; supersede, never edit)

## 2026-11-14T09:52Z: Launcher design
- System Wine, not Proton: Proton Experimental failed prefix upgrade on the original
  machine (missing nvngx_update.exe). Proton support is out of scope.
- One prefix per game, id = sha256(absolute exe folder)[:16], so titles never share
  DLLs or registry state and odd names never reach a filesystem path.
- All prefixes are win64: WoW64-only Wine builds cannot create win32 prefixes; 32-bit
  games run through WoW64.
- winemenubuilder disabled in every prefix so Wine never adds its own menu entries or
  file associations; wine-mono/gecko disabled at bootstrap unless installed locally,
  so first run never downloads.
- .desktop entries launch by id (winrun --id), not by path, so no Exec quoting of
  game paths is needed.

## 2026-11-14T09:52Z: Translation stack
- Layer A is the only automated route for Unity: in at least one tested title the
  dialogue was not recoverable as plain strings, so bulk extraction is not promised.
- FallbackEndpoint is always empty: XUnity's defaults point at Google.
- An existing BepInEx/XUnity installed by something else is left untouched; only the
  config is corrected (replacing a working plugin with another version adds risk).
- XUnity writes its config with a UTF-8 BOM; reads strip it and writes keep it.
  (Correction: the first version did not, and would have added a duplicate
  [Service] section; found by scanning a real library, now tested.)
- Third-party packages are downloaded by the user, never bundled.

## 2026-11-14T09:52Z: Public release preparation
- Personal paths, library-specific results and title names moved out of tracked
  files; status/, LOCAL-NOTES.md and pkgs/ are git-ignored.
- Defaults: packages in ~/.local/share/winlauncher/pkgs, library in $WL_LIBRARY or ~/Games.
- License proposed: MIT (pending maintainer confirmation).

## 2026-11-14T09:53Z: Published
- Maintainer chose: public repository github.com/shetautnetjer/winlauncher, MIT
  license (supersedes "pending maintainer confirmation" above).

## 2026-11-14T11:05Z: Wayland visibility and keyboard focus (--desktop)
- Observed on GNOME/Wayland: a Wine game window can map, report itself visible and
  render, yet never be raised/composited, and never become the focused window, so
  keystrokes go elsewhere. Evidence: focused window was an unrelated one; after the
  fix one synthetic Down arrow changed ~17% of the screen and Up ~4% (menu moved).
- Fix: `--desktop` (or WL_VIRTUALDESK=1 per game) runs the game inside a Wine virtual
  desktop window named wl-<id>; winrun polls up to ~12 s and calls bin/wl-focus,
  which raises it, sends _NET_ACTIVE_WINDOW and calls XSetInputFocus directly
  (mutter often ignores the polite request). Pure Python ctypes + xwininfo.
- Off by default: only enabled per game where the problem was seen (2 titles on the
  original machine). Correction to the agent report that "a plain double-click no
  longer swallows input": true only for games with WL_VIRTUALDESK=1.
- wl-focus exits 3 when it cannot apply (no DISPLAY, no xwininfo, no libX11) and
  winrun stops retrying; previously it raised and retried 24 times.
- The test helpers dl-sweep.sh (real library paths) and keyprobe.py (needs Pillow;
  deleted ~/Pictures/Screenshot.png before each capture, now parks and restores it)
  are lab tools, kept outside the repo.

## Unity 6 games need Wine >= 11.3 (pointer input), not Wine 10

Unity 6's Windows input backend calls `EnableMouseInPointer(TRUE)` and then reads
only `WM_POINTER*` messages. Wine before 11.3 exports those Win8 pointer APIs as
stubs returning `ERROR_CALL_NOT_IMPLEMENTED`, and never generates a pointer
message, so the game ignores the legacy `WM_MOUSE*` events Wine does deliver.

Evidence in the game's own Unity log:

    EnableMouseInPointer failed with the following error: Call not implemented.

On Unity 6000.2.x the symptom is a completely frozen cursor; on 6000.3.x the
cursor moves but clicks never register. Keyboard can appear dead too because the
UI never gets its first click.

Fix: upstream Wine implemented this in 11.3 (Feb 2026). A portable Wine 11.22
staging build lives in ~/aya/tools/wine-portable and is selected per game with
`WL_WINE=` in `~/.config/winlauncher/games/<id>.conf`; `find_wineserver` follows
`WL_WINE` so a 11.x client never pairs with a 10.x server. Verified on Femboy
Futa House: the failure line disappears from the log and clicks work.

Five titles in this library are Unity 6 and are configured this way:
MASSAGE MY EX-BULLY, Femboy Futa House, Sex Education Trainer,
Roommate Life with your Cute Former Labmate, GyakuTobatsu.

Not a click-capture problem: `WL_MOUSE_WARP=disable` (added earlier) is kept for
games that hold a relative-mouse grab, but it does not fix Unity 6 tiles - the
pointer moved freely there and clicks still never arrived.
