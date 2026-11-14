#!/usr/bin/env bash
# uninstall.sh — reverse install.sh. Keeps Wine prefixes (they hold your saves) and logs.
#
#   ./uninstall.sh                 # remove commands, handler, per-game menu entries; restore .exe default
#   ./uninstall.sh --keep-entries  # same, but keep per-game menu entries made by wl-desktop
#
# Never touches game folders. Translation installs are per game: undo those with
#   wl-translate <game> --uninstall --apply   (run that BEFORE this script, while the command exists)
set -u
REPO=$(cd -- "$(dirname -- "$0")" && pwd)
BIN="$HOME/.local/bin"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/winlauncher"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/winlauncher"
DESKTOP_ID="winlauncher.desktop"
KEEP_ENTRIES=0; [ "${1:-}" = "--keep-entries" ] && KEEP_ENTRIES=1

if ls "$STATE"/translate/*.json >/dev/null 2>&1; then
    echo "note: wl-translate is still installed in these games (undo with wl-translate <folder> --uninstall --apply):"
    for m in "$STATE"/translate/*.json; do python3 -c 'import json,sys;print("  ",json.load(open(sys.argv[1]))["game"])' "$m"; done
fi

echo "restoring .exe default:"
python3 "$REPO/lib/mimeapps.py" restore "$DESKTOP_ID" "$STATE/mimeapps-previous.json"

rm -f -- "$APPS/$DESKTOP_ID" && echo "removed $APPS/$DESKTOP_ID"
if [ "$KEEP_ENTRIES" = 0 ]; then
    for f in "$APPS"/winlauncher-*.desktop; do [ -f "$f" ] && rm -f -- "$f" && echo "removed $f"; done
fi
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS"

for c in winrun wl-translate wl-scan wl-desktop; do
    link="$BIN/$c"
    if [ -L "$link" ] && [ "$(readlink -- "$link")" = "$REPO/bin/$c" ]; then rm -f -- "$link" && echo "removed $link"; fi
done
rm -f -- "$STATE/install.json"

echo
echo "kept (delete by hand if you are sure; prefixes contain game saves):"
echo "  prefixes: $DATA/prefixes  ($(du -sh "$DATA/prefixes" 2>/dev/null | cut -f1 || echo 0))"
echo "  logs:     $STATE/games"
echo "  mimeapps: $STATE/mimeapps-previous.json and ~/.config/mimeapps.list.winlauncher-backup-*"
