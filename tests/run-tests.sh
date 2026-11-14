#!/usr/bin/env bash
# run-tests.sh — offline tests with a fake Wine. Safe anywhere: everything lives in a temp dir.
#   tests/run-tests.sh
set -u
REPO=$(cd -- "$(dirname -- "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf 'ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1" "$2"; fi; }

export HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_DATA_HOME="$T/home/.local/share" XDG_STATE_HOME="$T/home/.local/state"
export WL_DATA="$XDG_DATA_HOME/winlauncher" WL_STATE="$XDG_STATE_HOME/winlauncher" WL_CONF="$XDG_CONFIG_HOME/winlauncher"
mkdir -p "$HOME" "$T/fake"

# ---- fake wine: records argv, cwd, env; exit code from $FAKE_RC; "wineboot" makes system.reg
cat > "$T/fake/wine" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then echo wine-fake; exit 0; fi
if [ "${1:-}" = "winepath" ]; then echo 'Z:\fake\Game.exe'; exit 0; fi
if [ "${1:-}" = "wineboot" ]; then mkdir -p "$WINEPREFIX"; : > "$WINEPREFIX/system.reg"; echo boot >> "$FAKE_LOG.boot"; exit 0; fi
{ printf 'CWD=%s\n' "$PWD"; printf 'PREFIX=%s\n' "$WINEPREFIX"; printf 'OVR=%s\n' "$WINEDLLOVERRIDES"
  printf 'ARCH=%s\n' "$WINEARCH"; for a in "$@"; do printf 'ARG=%s\n' "$a"; done; } > "$FAKE_LOG"
[ -n "${FAKE_SLEEP:-}" ] && sleep "$FAKE_SLEEP"
[ "${FAKE_RC:-0}" != 0 ] && echo "err:module:import_dll Library FAKE.dll not found" >&2
exit "${FAKE_RC:-0}"
EOF
printf '#!/bin/sh\nexit 0\n' > "$T/fake/wineserver"
chmod +x "$T/fake/wine" "$T/fake/wineserver"
export WL_WINE="$T/fake/wine" WL_WINESERVER="$T/fake/wineserver" FAKE_LOG="$T/fake.log"

mkpe() { # mkpe <path> <x64|x86>: minimal PE header
    python3 - "$1" "$2" <<'PY'
import struct, sys
mach = 0x8664 if sys.argv[2] == "x64" else 0x14c
b = bytearray(0x400); b[0:2] = b"MZ"; struct.pack_into("<I", b, 0x3C, 0x80)
b[0x80:0x84] = b"PE\0\0"; struct.pack_into("<HH", b, 0x84, mach, 0); open(sys.argv[1], "wb").write(b)
PY
}

# ---- 1. awkward paths
WEIRD="$T/lib/Game [v1.2] (extracted)/テスト用フォルダ「試験」 \$HOME 'q' \"dq\""
mkdir -p "$WEIRD"; mkpe "$WEIRD/ゲーム 本編.exe" x64
"$REPO/bin/winrun" "$WEIRD/ゲーム 本編.exe" "arg with space" >/dev/null 2>&1; rc=$?
check "launch with CJK/brackets/quotes/\$ path exits 0" '[ $rc = 0 ]'
check "cwd is the exe folder" 'grep -qxF "CWD=$WEIRD" "$FAKE_LOG"'
check "exe passed intact" 'grep -qxF "ARG=$WEIRD/ゲーム 本編.exe" "$FAKE_LOG"'
check "game args passed intact" 'grep -qxF "ARG=arg with space" "$FAKE_LOG"'
check "winhttp override set" 'grep -q "^OVR=winhttp=n,b;winemenubuilder.exe=d$" "$FAKE_LOG"'
ID=$(printf '%s' "$WEIRD" | sha256sum | cut -c1-16)
check "prefix id = sha256(folder)[:16]" 'grep -qxF "PREFIX=$WL_DATA/prefixes/$ID" "$FAKE_LOG"'
check "prefix bootstrapped once" '[ -f "$WL_DATA/prefixes/$ID/.winlauncher-ready" ]'
"$REPO/bin/winrun" "$WEIRD/ゲーム 本編.exe" >/dev/null 2>&1
check "second run does not re-bootstrap" '[ "$(wc -l < "$FAKE_LOG.boot")" = 1 ]'
check "per-game log written" 'grep -q "^=== exit 0" "$WL_STATE/games/$ID/last.log"'
check "run history recorded" '[ "$(wc -l < "$WL_STATE/games/$ID/runs.tsv")" = 2 ]'
check "nothing written into game folder" '[ "$(ls -A "$WEIRD" | wc -l)" = 1 ]'

# ---- 2. --id relaunch, file:// URI
"$REPO/bin/winrun" --id "$ID" >/dev/null 2>&1
check "--id relaunch works" '[ $? = 0 ] && grep -qxF "CWD=$WEIRD" "$FAKE_LOG"'
URI="file://$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$WEIRD/ゲーム 本編.exe")"
"$REPO/bin/winrun" "$URI" >/dev/null 2>&1
check "file:// URI accepted" '[ $? = 0 ] && grep -qxF "CWD=$WEIRD" "$FAKE_LOG"'

# ---- 3. separate folders -> separate prefixes; x86 game
OTHER="$T/lib/Other Game"; mkdir -p "$OTHER"; mkpe "$OTHER/Game.exe" x86
"$REPO/bin/winrun" "$OTHER/Game.exe" >/dev/null 2>&1
ID2=$(printf '%s' "$OTHER" | sha256sum | cut -c1-16)
check "different game gets its own prefix" '[ "$ID2" != "$ID" ] && grep -qxF "PREFIX=$WL_DATA/prefixes/$ID2" "$FAKE_LOG"'
check "x86 exe detected" 'grep -q "^arch     x86" "$WL_STATE/games/$ID2/last.log"'

# ---- 4. startup crash reporting
FAKE_RC=3 "$REPO/bin/winrun" "$OTHER/Game.exe" >/dev/null 2>"$T/err"; rc=$?
check "startup crash -> exit 4" '[ $rc = 4 ]'
check "crash message names exit code" 'grep -q "stopped during startup (exit code 3" "$T/err"'
check "crash message quotes err: line" 'grep -q "err:module:import_dll" "$T/err"'
check "crash message gives log path" 'grep -qF "$WL_STATE/games/$ID2/last.log" "$T/err"'
FAKE_RC=3 WL_STARTUP_SECS=0 "$REPO/bin/winrun" "$OTHER/Game.exe" >/dev/null 2>&1; rc=$?
check "non-zero exit after startup window is passed through" '[ $rc = 3 ]'

# ---- 5. refusals
printf 'not a pe' > "$OTHER/fake.exe"
"$REPO/bin/winrun" "$OTHER/fake.exe" >/dev/null 2>"$T/err"
check "non-PE refused" 'grep -q "not a Windows program" "$T/err"'
"$REPO/bin/winrun" "$OTHER/missing.exe" >/dev/null 2>"$T/err"
check "missing file refused" 'grep -q "file not found" "$T/err"'

# ---- 6. single instance lock
FAKE_SLEEP=2 "$REPO/bin/winrun" "$OTHER/Game.exe" >/dev/null 2>&1 & sleep 0.5
"$REPO/bin/winrun" "$OTHER/Game.exe" >/dev/null 2>"$T/err"; rc=$?; wait
check "second launch while running is refused (exit 3)" '[ $rc = 3 ] && grep -q "already running" "$T/err"'

# ---- 7. per-game config
mkdir -p "$WL_CONF/games"; printf 'WL_DLLOVERRIDES_EXTRA="d3d11=n"\nWL_EXTRA_ARGS=(-screen-fullscreen 0)\n' > "$WL_CONF/games/$ID2.conf"
"$REPO/bin/winrun" "$OTHER/Game.exe" >/dev/null 2>&1
check "per-game overrides appended" 'grep -q "^OVR=winhttp=n,b;winemenubuilder.exe=d;d3d11=n$" "$FAKE_LOG"'
check "per-game extra args" 'grep -qx "ARG=-screen-fullscreen" "$FAKE_LOG"'

# ---- 7b. --desktop: virtual desktop + keyboard focus grab
printf '#!/bin/sh\necho "$1" >> "%s"\nexit 0\n' "$T/focus.log" > "$T/fake/focus"
printf '#!/bin/sh\nexit 3\n' > "$T/fake/nofocus"
chmod +x "$T/fake/focus" "$T/fake/nofocus"
WL_FOCUS="$T/fake/focus" "$REPO/bin/winrun" --desktop 1280x720 "$OTHER/Game.exe" >/dev/null 2>&1; rc=$?
check "--desktop exits 0" '[ $rc = 0 ]'
check "--desktop runs explorer /desktop=wl-<id>,WxH" 'grep -qx "ARG=explorer" "$FAKE_LOG" && grep -qxF "ARG=/desktop=wl-$ID2,1280x720" "$FAKE_LOG"'
check "--desktop passes the Windows path of the exe" 'grep -qxF "ARG=Z:\\fake\\Game.exe" "$FAKE_LOG"'
check "--desktop grabs focus for wl-<id>" 'grep -qx "wl-$ID2" "$T/focus.log"'
WL_FOCUS="$T/fake/nofocus" "$REPO/bin/winrun" --desktop "$OTHER/Game.exe" >/dev/null 2>&1; rc=$?
check "focus not possible: no retry storm, game still runs" '[ $rc = 0 ] && grep -qxF "ARG=/desktop=wl-$ID2,1920x1080" "$FAKE_LOG"'
"$REPO/bin/winrun" --info --desktop "$OTHER/Game.exe" > "$T/info" 2>&1
check "--info shows desktop mode" 'grep -q "^mode      virtual desktop" "$T/info"'
env -u DISPLAY python3 "$REPO/bin/wl-focus" x >/dev/null 2>&1; rc=$?
check "wl-focus without a display exits 3 (skip)" '[ $rc = 3 ]'

# ---- 8. mimeapps set/restore round trip
mkdir -p "$XDG_CONFIG_HOME"
cat > "$XDG_CONFIG_HOME/mimeapps.list" <<'EOF'
[Default Applications]
text/html=google-chrome.desktop
application/x-msdownload=steam-valve-native.desktop

[Added Associations]
application/x-msdownload=steam-valve-native.desktop;
EOF
cp "$XDG_CONFIG_HOME/mimeapps.list" "$T/mime.orig"
python3 "$REPO/lib/mimeapps.py" set winlauncher.desktop "$T/mstate.json" >/dev/null
check "default set for x-msdownload" 'grep -qx "application/x-msdownload=winlauncher.desktop" "$XDG_CONFIG_HOME/mimeapps.list"'
check "default set for portable-executable" 'grep -qx "application/vnd.microsoft.portable-executable=winlauncher.desktop" "$XDG_CONFIG_HOME/mimeapps.list"'
check "steam kept as added association" 'grep -qx "application/x-msdownload=winlauncher.desktop;steam-valve-native.desktop;" "$XDG_CONFIG_HOME/mimeapps.list"'
python3 "$REPO/lib/mimeapps.py" set winlauncher.desktop "$T/mstate.json" >/dev/null
check "set is idempotent (previous still steam)" 'grep -q "steam-valve-native" "$T/mstate.json"'
python3 "$REPO/lib/mimeapps.py" restore winlauncher.desktop "$T/mstate.json" >/dev/null
check "restore gives back the original file exactly" 'cmp -s "$T/mime.orig" "$XDG_CONFIG_HOME/mimeapps.list"'

# ---- 9. wl-translate on a fake Unity Mono game
G="$T/lib/Unity Game (extracted)/Unity Game"
mkdir -p "$G/Unity Game_Data/Managed"; mkpe "$G/Unity Game.exe" x64
: > "$G/Unity Game_Data/Managed/Assembly-CSharp.dll"; printf '2022.3.21f1\0' > "$G/Unity Game_Data/globalgamemanagers"
echo "original" > "$G/doorstop_config.ini"        # a pre-existing file that the zip overwrites
PK="$T/pkgs"; mkdir -p "$PK/a/BepInEx/core" "$PK/b/BepInEx/plugins/XUnity.AutoTranslator"
echo dll > "$PK/a/winhttp.dll"; echo cfg > "$PK/a/doorstop_config.ini"; echo core > "$PK/a/BepInEx/core/BepInEx.dll"
echo xu > "$PK/b/BepInEx/plugins/XUnity.AutoTranslator/XUnity.AutoTranslator.Plugin.Core.dll"
(cd "$PK/a" && python3 -m zipfile -c ../bepinex5_win_x64.zip winhttp.dll doorstop_config.ini BepInEx)
(cd "$PK/b" && python3 -m zipfile -c ../xuat_bepinex.zip BepInEx)
snap() { (cd "$G" && find . -type f -print0 | sort -z | xargs -0 sha256sum); }
snap > "$T/before"
"$REPO/bin/wl-translate" "$T/lib/Unity Game (extracted)" --pkgs "$PK" > "$T/out" 2>&1
check "dry run writes nothing" 'snap | cmp -s - "$T/before"'
check "dry run lists the overwrite + backup" 'grep -q "overwrite doorstop_config.ini" "$T/out"'
"$REPO/bin/wl-translate" "$T/lib/Unity Game (extracted)" --pkgs "$PK" --apply --endpoint http://127.0.0.1:9/x > "$T/out" 2>&1
check "apply installs plugin" '[ -f "$G/BepInEx/plugins/XUnity.AutoTranslator/XUnity.AutoTranslator.Plugin.Core.dll" ]'
check "apply backs up overwritten file" 'ls "$G"/doorstop_config.ini.wl-bak-* >/dev/null 2>&1 && grep -qx original "$G"/doorstop_config.ini.wl-bak-*'
CFG="$G/BepInEx/config/AutoTranslatorConfig.ini"
check "config: CustomTranslate, no fallback, ja->en, url" 'grep -qx "Endpoint=CustomTranslate" "$CFG" && grep -qx "FallbackEndpoint=" "$CFG" && grep -qx "FromLanguage=ja" "$CFG" && grep -qx "Language=en" "$CFG" && grep -qx "Url=http://127.0.0.1:9/x" "$CFG"'
check "apply prints uninstall command" 'grep -q -- "--uninstall --apply" "$T/out"'
"$REPO/bin/wl-translate" "$G" --pkgs "$PK" --apply --endpoint http://127.0.0.1:9/x > "$T/out" 2>&1
check "second apply is a no-op" 'grep -q "Nothing to do" "$T/out"'
# simulate XUnity rewriting its config + runtime files
printf '[Service]\nEndpoint=CustomTranslate\n[Custom]\nUrl=http://127.0.0.1:9/x\n[Extra]\nX=1\n' > "$CFG"
mkdir -p "$G/BepInEx/Translation/en/Text"; echo "あ=a" > "$G/BepInEx/Translation/en/Text/_AutoGeneratedTranslations.txt"
"$REPO/bin/wl-translate" "$G" --uninstall > "$T/out" 2>&1
check "uninstall dry run changes nothing" '[ -f "$G/winhttp.dll" ]'
"$REPO/bin/wl-translate" "$G" --uninstall --apply --remove-runtime-files > "$T/out" 2>&1
check "uninstall restores the game folder byte-for-byte" 'snap | cmp -s - "$T/before"'
check "generated translations kept in leftovers" 'find "$WL_STATE/translate-leftovers" -name _AutoGeneratedTranslations.txt | grep -q .'

# ---- 10. foreign BepInEx is never overwritten; IL2CPP without packages is blocked
mkdir -p "$G/BepInEx/core"; echo theirs > "$G/BepInEx/core/BepInEx.dll"; echo theirs > "$G/winhttp.dll"
"$REPO/bin/wl-translate" "$G" --pkgs "$PK" --apply --endpoint http://127.0.0.1:9/x > "$T/out" 2>&1
check "foreign loader left untouched" 'grep -qx theirs "$G/BepInEx/core/BepInEx.dll" && grep -qx theirs "$G/winhttp.dll"'
check "XUnity still added next to foreign loader" '[ -f "$G/BepInEx/plugins/XUnity.AutoTranslator/XUnity.AutoTranslator.Plugin.Core.dll" ]'
I="$T/lib/IL Game"; mkdir -p "$I/IL Game_Data/il2cpp_data"; mkpe "$I/IL Game.exe" x64; : > "$I/GameAssembly.dll"
"$REPO/bin/wl-translate" "$I" --pkgs "$PK" > "$T/out" 2>&1; rc=$?
check "IL2CPP without staged packages is blocked with instructions" '[ $rc = 3 ] && grep -q "BepInEx-Unity.IL2CPP-win-x64" "$T/out"'

# ---- 10b. existing XUnity config saved with a UTF-8 BOM and pointing at a cloud service
B="$T/lib/Bom Game"; mkdir -p "$B/Bom Game_Data/Managed" "$B/BepInEx/config" "$B/BepInEx/plugins/XUnity.AutoTranslator"; mkpe "$B/Bom Game.exe" x64
: > "$B/BepInEx/plugins/XUnity.AutoTranslator/XUnity.AutoTranslator.Plugin.Core.dll"
: > "$B/Bom Game_Data/Managed/Assembly-CSharp.dll"
printf '\xef\xbb\xbf[Service]\nEndpoint=GoogleTranslateV2\nFallbackEndpoint=\n\n[General]\nLanguage=en\nFromLanguage=ja\n\n[Custom]\nUrl=\n' > "$B/BepInEx/config/AutoTranslatorConfig.ini"
"$REPO/bin/wl-scan" "$T/lib" > "$T/scan" 2>&1
check "scan reads BOM config and flags cloud endpoint" 'grep "GoogleTranslateV2" "$T/scan" | grep -q "NOT local"'
mkdir -p "$B/BepInEx/core"; echo theirs > "$B/BepInEx/core/BepInEx.dll"; echo theirs > "$B/winhttp.dll"
"$REPO/bin/wl-translate" "$B" --pkgs "$T/empty-pkgs" --apply --endpoint http://127.0.0.1:9/x > "$T/out" 2>&1
BC="$B/BepInEx/config/AutoTranslatorConfig.ini"
check "BOM config edited in place (one [Service] section)" '[ "$(grep -c "Service\]" "$BC")" = 1 ] && grep -qx "Endpoint=CustomTranslate" "$BC"'
check "BOM preserved" '[ "$(head -c3 "$BC" | od -An -tx1 | tr -d " ")" = efbbbf ]'
check "existing XUnity: only the config is touched" '[ ! -e "$B/winhttp.dll" ] || grep -q theirs "$B/winhttp.dll"; [ "$(find "$B" -name "*.wl-bak-*" | wc -l)" = 1 ]'
check "cloud endpoint config backed up first" 'grep -q GoogleTranslateV2 "$B"/BepInEx/config/AutoTranslatorConfig.ini.wl-bak-*'

# ---- 11. wl-scan
"$REPO/bin/wl-scan" "$T/lib" > "$T/scan" 2>&1
check "scan sees Unity Mono" 'grep -q "Unity Mono" "$T/scan"'
check "scan sees IL2CPP" 'grep -q "Unity IL2CPP" "$T/scan"'
check "scan shows launcher history" 'grep -q "FAILED\|ran (rc" "$T/scan"'

# ---- 12. syntax
for f in "$REPO"/bin/winrun "$REPO"/bin/wl-desktop "$REPO"/install.sh "$REPO"/uninstall.sh "$REPO"/tests/*.sh; do
    bash -n "$f" || bad "bash -n $f"
done
python3 -m py_compile "$REPO/bin/wl-translate" "$REPO/bin/wl-scan" "$REPO/lib/"*.py && ok "python compiles"

echo; echo "passed $PASS, failed $FAIL"
[ "$FAIL" = 0 ]
