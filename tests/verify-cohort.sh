#!/usr/bin/env bash
# Verify a cohort end to end: launch each game, then look for evidence that it
# actually translated, not merely that a process exists.
#
# Evidence tiers (weakest to strongest):
#   loaded   - log says XUnity loaded into the Unity runtime
#   hooked   - a translation file in BepInEx/Translation/en/Text/ grew
#   served   - the local endpoint logged a request during this run
#
#   ./verify-cohort.sh <id-prefix> [id-prefix...]
set -u
ROOT="$HOME/Downloads/games"
MAP="$HOME/tools/winlauncher/status/library-map.tsv"
W="$HOME/tools/winlauncher/bin/winrun"
REQLOG="$HOME/aya/tools/gametl/requests.log"
SECS=30
OUT=/tmp/verify-cohort.tsv
: > "$OUT"
printf 'game\truntime\tloaded\ttranslated\tserved\tdetail\n' >> "$OUT"

for id in "$@"; do
  row=$(awk -F'\t' -v i="$id" 'index($2,i)==1' "$MAP")
  [ -z "$row" ] && { echo "$id not in map" >&2; continue; }
  folder=$(printf '%s' "$row" | cut -f3); rel=$(printf '%s' "$row" | cut -f4)
  exe="$ROOT/$folder/$rel"; gdir=$(dirname "$exe")
  [ -f "$exe" ] || { printf '%s\t-\t-\t-\t-\tmissing exe\n' "$folder" >>"$OUT"; continue; }
  log="$gdir/BepInEx/LogOutput.log"
  tdir="$gdir/BepInEx/Translation/en/Text"
  before_lines=$(cat "$tdir"/*.txt 2>/dev/null | wc -l)
  before_req=$(wc -l < "$REQLOG" 2>/dev/null || echo 0)
  rm -f "$log"

  "$W" --gui "$exe" >>/tmp/verify-cohort-run.log 2>&1 &
  wpid=$!
  sleep "$SECS"

  loaded=no; grep -q "Loaded XUnity.AutoTranslator" "$log" 2>/dev/null && loaded=yes
  after_lines=$(cat "$tdir"/*.txt 2>/dev/null | wc -l)
  trans=no; [ "${after_lines:-0}" -gt "${before_lines:-0}" ] && trans=yes
  after_req=$(wc -l < "$REQLOG" 2>/dev/null || echo 0)
  served=no; [ "${after_req:-0}" -gt "${before_req:-0}" ] && served=yes

  det="+$((after_lines - before_lines)) lines, +$((after_req - before_req)) requests"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$folder" "$(grep -oE 'Unity \[[^]]+\]' "$log" 2>/dev/null | head -1)" \
    "$loaded" "$trans" "$served" "$det" >>"$OUT"

  "$W" --kill --id "$id" >/dev/null 2>&1
  kill -TERM "$wpid" 2>/dev/null
  sleep 2
done

echo "--- results ---"
column -t -s $'\t' "$OUT"
