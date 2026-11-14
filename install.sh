#!/usr/bin/env bash
# install.sh — user-level install of winlauncher. No root, idempotent, reversible
# with ./uninstall.sh.
#
#   ./install.sh               # links commands, registers the .exe handler, makes it default
#   ./install.sh --no-default  # register the handler (shows in "Open With") but keep the
#                              # current default app for .exe
#
# What it changes (and nothing else):
#   ~/.local/bin/{winrun,wl-translate,wl-scan,wl-desktop}   symlinks into this repo
#   ~/.local/share/applications/winlauncher.desktop         the .exe handler
#   ~/.local/share/applications/mimeinfo.cache              rebuilt by update-desktop-database
#   ~/.config/mimeapps.list                                 3 .exe MIME lines (previous values
#                                                           saved, original copied once)
#   ~/.local/state/winlauncher/install.json                 what was done, for uninstall
set -eu
REPO=$(cd -- "$(dirname -- "$0")" && pwd)
BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/winlauncher"
DESKTOP_ID="winlauncher.desktop"
MAKE_DEFAULT=1
[ "${1:-}" = "--no-default" ] && MAKE_DEFAULT=0

say() { printf '%s\n' "$*"; }
need() { command -v "$1" >/dev/null 2>&1 || { say "missing: $1 ($2)"; MISSING=1; }; }
MISSING=0
need wine "the runtime (apt package wine)"
need python3 "for wl-translate / wl-scan"
need xdg-mime "xdg-utils, for registering the handler"
need flock "util-linux"
need sha256sum "coreutils"
[ "$MISSING" = 0 ] || { say "install aborted: dependencies missing"; exit 1; }
command -v zenity >/dev/null 2>&1 || say "note: zenity not found; startup errors will use notify-send only"

mkdir -p "$BIN" "$APPS" "$STATE"
chmod +x "$REPO"/bin/* "$REPO"/lib/mimeapps.py "$REPO"/uninstall.sh "$REPO"/tests/*.sh 2>/dev/null || true

for c in winrun wl-translate wl-scan wl-desktop; do
    target="$REPO/bin/$c"; link="$BIN/$c"
    if [ -L "$link" ] && [ "$(readlink -- "$link")" = "$target" ]; then
        say "ok      $link"
    elif [ -e "$link" ] || [ -L "$link" ]; then
        say "SKIP    $link exists and is not ours; leaving it (remove it yourself to use ours)"
    else
        ln -s -- "$target" "$link"; say "linked  $link -> $target"
    fi
done

# build + validate outside the applications dir (the validator wants a .desktop name)
tmpd=$(mktemp -d); tmp="$tmpd/$DESKTOP_ID"
sed "s|@WINRUN@|$BIN/winrun|g" "$REPO/share/winlauncher.desktop.in" > "$tmp"
if command -v desktop-file-validate >/dev/null 2>&1; then desktop-file-validate "$tmp"; fi
cp -f "$tmp" "$APPS/$DESKTOP_ID.part" && mv -f "$APPS/$DESKTOP_ID.part" "$APPS/$DESKTOP_ID"; rm -rf "$tmpd"
say "wrote   $APPS/$DESKTOP_ID"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" && say "rebuilt $APPS/mimeinfo.cache"

if [ "$MAKE_DEFAULT" = 1 ]; then
    say "default handler for .exe:"
    python3 "$REPO/lib/mimeapps.py" set "$DESKTOP_ID" "$STATE/mimeapps-previous.json"
fi

cat > "$STATE/install.json" <<EOF
{"repo": "$REPO", "installed": "$(date '+%F %T')", "made_default": $MAKE_DEFAULT,
 "bin": "$BIN", "desktop": "$APPS/$DESKTOP_ID"}
EOF

case ":$PATH:" in *":$BIN:"*) ;; *) say "note: $BIN is not on PATH in this shell; double-click still works (absolute path)";; esac
say ""
say "Check it:"
say "  xdg-mime query default application/vnd.microsoft.portable-executable   # expect $DESKTOP_ID"
say "  xdg-mime query default application/x-msdownload                        # expect $DESKTOP_ID"
say "  $REPO/tests/verify-install.sh"
