# STATUS.md

Updated 2026-11-14T11:05Z.

**Stage:** built and installed on one machine (Ubuntu 26.04, Wine 10.0); offline
suite 59/59, real-Wine self-test 20/20; one real Unity Mono title launched and loaded
BepInEx + XUnity. `--desktop` + focus grab: keyboard input shown to reach a game on
GNOME/Wayland (arrow-key screen-diff test, 2026-11-14), on by config for 2 titles only. Published at github.com/shetautnetjer/winlauncher (MIT).

**Not yet verified:** a real double-click in Nautilus; a live endpoint call through
winrun; 32-bit Mono and IL2CPP installs on real games; other distros/file managers.

**Next action:** maintainer pushes `main` from his own terminal
(`git push -u origin main`; the GitHub repo exists and is still empty), then confirm
the CI run passes.
