#!/usr/bin/env bash
# Record a visit to a pane for the agent picker's "last visited" sort.
# Runs from Herdr focus event hooks; `track.sh <pane_id>` records that pane instead
# of asking Herdr which pane is focused.
# Visits file: one "pane_id<TAB>epoch" line per pane, most recent last.
set -euo pipefail

file=${HERDR_VISITS_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/visits.tsv}
herdr=${HERDR_BIN_PATH:-herdr}

pane=${1:-$("$herdr" pane list | jq -r '[.result.panes[] | select(.focused)][0].pane_id // empty')}
[[ -n "$pane" ]] || exit 0

mkdir -p "$(dirname "$file")"
exec 9>"$file.lock"
flock 9
{
  [[ -f "$file" ]] && awk -F'\t' -v p="$pane" '$1 != p' "$file"
  printf '%s\t%s\n' "$pane" "$(date +%s)"
} | tail -n 200 >"$file.tmp"
mv "$file.tmp" "$file"
