#!/usr/bin/env bash
# verify-install.sh — check a real install on this machine, using real Wine.
#
#   tests/verify-install.sh            # registration checks + Wine self-test (~1-3 min first time)
#   tests/verify-install.sh --no-wine  # registration checks only
#
# The Wine self-test uses Wine's own cmd.exe copied into a throwaway folder whose name
# has spaces, brackets and CJK, with its own data/state dirs under ~/.cache, so it does
# not create prefixes or logs among your real games. Nothing here opens a window.
set -u
REPO=$(cd -- "$(dirname -- "$0")/.." && pwd)
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf 'ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }

echo "== registration"
for c in winrun wl-translate wl-scan wl-desktop; do
    [ "$(readlink -- "$HOME/.local/bin/$c")" = "$REPO/bin/$c" ] && ok "~/.local/bin/$c linked" || bad "~/.local/bin/$c not linked to this repo"
done
f="$APPS/winlauncher.desktop"
[ -f "$f" ] && ok "handler entry exists" || bad "missing $f"
desktop-file-validate "$f" >/dev/null 2>&1 && ok "handler entry validates" || bad "desktop-file-validate $f" "$(desktop-file-validate "$f" 2>&1)"
for t in application/vnd.microsoft.portable-executable application/x-msdownload application/x-ms-dos-executable; do
    d=$(xdg-mime query default "$t" 2>/dev/null)
    [ "$d" = winlauncher.desktop ] && ok "xdg-mime default $t = $d" || bad "xdg-mime default $t = '${d:-unset}' (expected winlauncher.desktop)"
done
grep -q "winlauncher.desktop" "$APPS/mimeinfo.cache" 2>/dev/null && ok "mimeinfo.cache lists winlauncher" || bad "mimeinfo.cache does not list winlauncher (run update-desktop-database $APPS)"
if command -v gio >/dev/null; then
    g=$(gio mime application/x-msdownload 2>/dev/null | head -1)
    case "$g" in *winlauncher.desktop*) ok "gio (Nautilus) default: $g" ;; *) bad "gio default: $g" ;; esac
fi

[ "${1:-}" = "--no-wine" ] && { echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" = 0 ]; exit; }

echo "== Wine self-test (real wine, throwaway prefixes)"
ST="$HOME/.cache/winlauncher-selftest"; rm -rf -- "$ST"
export WL_DATA="$ST/data" WL_STATE="$ST/state" WL_CONF="$ST/conf"
WDIR=$(dirname -- "$(command -v wine)")
for base in /usr/lib/x86_64-linux-gnu/wine /usr/lib/wine /usr/lib64/wine "$WDIR/../lib/wine"; do
    [ -f "$base/x86_64-windows/cmd.exe" ] && { WLIB=$base; break; }
done
if [ -z "${WLIB:-}" ]; then bad "could not find Wine's cmd.exe to test with"; echo "passed $PASS, failed $FAIL"; exit 1; fi

G64="$ST/games/Selftest [テスト] (64-bit)"; G32="$ST/games/Selftest 「三十二」 (32-bit)"
mkdir -p "$G64" "$G32"
cp "$WLIB/x86_64-windows/cmd.exe" "$G64/テスト 64.exe"
[ -f "$WLIB/i386-windows/cmd.exe" ] && cp "$WLIB/i386-windows/cmd.exe" "$G32/Test32.exe"
head -c 2048 "$WLIB/x86_64-windows/cmd.exe" > "$G64/broken.exe"

t0=$(date +%s)
"$REPO/bin/winrun" "$G64/テスト 64.exe" /c "cd > cwd.txt" ; rc=$?
echo "      (first run incl. prefix creation: $(( $(date +%s) - t0 ))s)"
[ $rc = 0 ] && ok "64-bit exe ran, exit 0" || bad "64-bit exe exit $rc" "$(tail -5 "$WL_STATE"/games/*/last.log 2>/dev/null)"
[ -f "$G64/cwd.txt" ] && ok "working directory was the exe folder (cwd.txt landed there)" || bad "cwd.txt not in exe folder"
grep -q "Selftest \[" "$G64/cwd.txt" 2>/dev/null && ok "Windows side saw the folder: $(tr -d '\r' < "$G64/cwd.txt")" || bad "cwd.txt content: $(cat "$G64/cwd.txt" 2>/dev/null)"
ID64=$(printf '%s' "$G64" | sha256sum | cut -c1-16)
[ -f "$WL_DATA/prefixes/$ID64/system.reg" ] && ok "prefix created at prefixes/$ID64" || bad "no prefix for $ID64"
ls "$HOME/.local/share/applications"/wine-extension-* >/dev/null 2>&1 && bad "wine created wine-extension-* menu entries" || ok "no wine-extension-*.desktop clutter created"

if [ -f "$G32/Test32.exe" ]; then
    "$REPO/bin/winrun" "$G32/Test32.exe" /c "cd > cwd.txt"; rc=$?
    [ $rc = 0 ] && [ -f "$G32/cwd.txt" ] && ok "32-bit exe ran via WoW64 in its own prefix" || bad "32-bit exe exit $rc"
    ID32=$(printf '%s' "$G32" | sha256sum | cut -c1-16)
    [ "$ID32" != "$ID64" ] && [ -d "$WL_DATA/prefixes/$ID32" ] && ok "separate prefix per game folder" || bad "prefix not separate"
fi

"$REPO/bin/winrun" "$G64/broken.exe" 2>"$ST/err"; rc=$?
[ $rc = 4 ] && ok "broken exe reported as startup failure (exit 4)" || bad "broken exe exit $rc (expected 4)"
grep -q "stopped during startup" "$ST/err" && ok "failure message: $(head -1 "$ST/err")" || bad "no failure message" "$(cat "$ST/err")"

echo
echo "self-test data is in $ST (delete it any time: rm -rf \"$ST\")"
echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
