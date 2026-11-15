#!/usr/bin/env bash
# Launch every game in the library once, for a fixed window, and record whether
# it actually stayed up. Liveness is judged by a *game* process (not the wrapper,
# not pgrep matching its own command line - that bug invalidated an earlier sweep).
#
#   ./batch-launch.sh [seconds] [filter]
#   -> /tmp/batch-launch.tsv
set -u
ROOT="$HOME/Downloads/games"
MAP="$HOME/tools/winlauncher/status/library-map.tsv"
W="$HOME/tools/winlauncher/bin/winrun"
SECS="${1:-20}"
FILTER="${2:-}"
OUT=/tmp/batch-launch.tsv
: > "$OUT"
printf 'n\tfolder\tengine\tarch\tresult\tdetail\n' >> "$OUT"

[ -f "$MAP" ] || { echo "no library map at $MAP" >&2; exit 1; }

alive_pid() {   # game process whose args mention this folder, excluding the wrapper
  ps -eo pid,comm,args --no-headers 2>/dev/null |
    awk -v d="$1" '$2 != "bash" && index($0, d) > 0 {print $1; exit}'
}

while IFS=$'\t' read -r n id folder exe; do
  [ "$n" = "n" ] && continue
  [ -n "$FILTER" ] && ! printf '%s' "$folder" | grep -qi -- "$FILTER" && continue
  gdir="$ROOT/$folder"; gexe="$gdir/$exe"
  [ -f "$gexe" ] || { printf '%s\t%s\t-\t-\tMISSING\t%s\n' "$n" "$folder" "$gexe" >>"$OUT"; continue; }

  info=$("$W" --info "$gexe" 2>&1)
  arch=$(printf '%s\n' "$info" | awk '/^arch/{print $2}')
  eng=$(python3 - "$gexe" <<'PY' 2>/dev/null
import sys; sys.path.insert(0, "/home/aya-hmw/tools/winlauncher/lib")
from pathlib import Path
from wlcommon import detect_engine
d = detect_engine(Path(sys.argv[1])); print(f"{d['engine']}")
PY
)

  "$W" --gui "$gexe" >>/tmp/batch-launch-run.log 2>&1 &
  wpid=$!
  sleep "$SECS"
  pid=$(alive_pid "$gdir")
  if [ -n "$pid" ]; then
    res=ALIVE; det="pid $pid after ${SECS}s"
  else
    res=EXITED
    det=$(grep -E '^(err:|wine: |Unhandled|Crash)' /tmp/batch-launch-run.log 2>/dev/null | grep -v fixme | tail -1 | cut -c1-90)
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$n" "$folder" "$eng" "$arch" "$res" "${det:--}" >>"$OUT"

  "$W" --kill --id "$id" >/dev/null 2>&1
  kill -TERM "$wpid" 2>/dev/null
  sleep 2
done < "$MAP"

echo "--- summary ---"
awk -F'\t' 'NR>1 {c[$5]++} END {for (k in c) printf "%-8s %d\n", k, c[k]}' "$OUT"
