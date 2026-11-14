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
