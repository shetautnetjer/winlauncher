# Lab notes — machine-specific, do not publish to the public repo

This directory holds real folder names, per-game state and findings. It belongs
to the private repo only.

## Wine graphics driver on this host

- Wine chooses its graphics driver when the prefix's `wineserver` starts. A server
  still alive from an earlier X11 run makes `HKCU\Software\Wine\Drivers\Graphics=wayland`
  a no-op: the game silently stays XWayland. Kill the server first (launcher does).
- Native Wayland works for rendering on this box despite
  `waylanddrv:wayland_gl_drawable_create Failed to create EGL surface` in the log;
  gameplay has been observed with that error present.
- X11 renders reliably. Under XWayland an unfocused window ignores game input even
  when `XGetInputFocus` reports it — X focus is not Wayland activation.

## Recurring input symptom

Games report "controls not responsive" / "clicks do nothing". Distinguish three causes:
1. window not the active Wayland surface (XWayland) — clicks are delivered to the
   window under the pointer, but games using raw input ignore them while inactive;
2. the game is frozen — a Windows "Not Responding" dialog over a rendered frame
   (seen on Kaiju Princess 2 at the title, with Sentry 403 + `Curl error 23` in its
   Player.log: telemetry/HTTP stalls the main thread);
3. the game is inside a Wine virtual desktop and the inner window is not focused.

## Disproved fixes

- `WINEDLLOVERRIDES=wininet=d` aborts immediately:
  `unimplemented function wininet.dll.InternetCrackUrlW`.
- X11-level focus tools cannot make an XWayland surface the active Wayland window.

## Engine cohorts (from wl-scan)

- Unity Mono: BepInEx 5 + XUnity, local endpoint. Installed on 10 titles, one blocked
  by a read-only folder (`chmod u+w` needed).
- Unity IL2CPP: BepInEx 6 BE 793 + XUnity IL2CPP. Proven on one title
  (`ロード=Load`, `設定=Configuration` written by the running game).
- Non-Unity (Godot, RPG Maker MZ, Flash, WolfRPG, Electron): asset-level work, not started.
