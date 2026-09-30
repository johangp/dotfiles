#!/usr/bin/env bash
# Pick an agent or a tab without agents with fzf, and jump to it.
# Rows are grouped in picker tabs: agents, tabs without agents, then all; ←/→ switch.
# The agent or tab you are on is pinned as the header (not searchable); the rest
# follow by last visit (recorded by the visit-tracker plugin), never-visited ones
# last by urgency, so the cursor starts on the previous session.
# Bound to prefix+a as a popup in config.toml.
# `agent-picker.sh --rows` only turns {agents,panes,workspaces,tabs,visits} JSON on stdin
# into "kind<TAB>id<TAB>preview-pane<TAB>row" lines; kind is agent, tab or here (current).
set -euo pipefail

rows() {
  jq -r '
    def pad($n): if $n > length then . + (" " * ($n - length)) else . end;
    def rank: {blocked: 0, done: 1, working: 2, idle: 3, tab: 5}[.] // 4;
    def style: {blocked: ["●", "31"], done: ["●", "32"], working: ["●", "33"], idle: ["○", "2"], tab: ["▢", "2"]}[.] // ["?", "2"];
    (.workspaces | map({(.workspace_id): .label}) | add) as $ws
    | (.tabs | map({(.tab_id): .label}) | add) as $tabs
    | (.agents | map(.tab_id)) as $agent_tabs
    | .panes as $panes
    | (.visits // {}) as $visits
    | [(.agents[]
        | {kind: "agent", id: .pane_id, pane: .pane_id, workspace_id, tab_id, here: .focused,
           visit: $visits[.pane_id],
           agent, state: .agent_status, title: .terminal_title_stripped}),
       (.tabs[] | .focused as $here | .tab_id as $t
        | select(any($agent_tabs[]; . == $t) | not)
        | ([$panes[] | select(.tab_id == $t)] | (map(select(.focused)) + .)[0]) as $p
        | select($p != null)
        | {kind: "tab", id: $t, pane: $p.pane_id, workspace_id: $p.workspace_id, tab_id: $t, here: $here,
           visit: ([$panes[] | select(.tab_id == $t) | $visits[.pane_id] // empty] | max),
           agent: "shell", state: "tab", title: $p.terminal_title_stripped})]
    | map(. + {where: "\($ws[.workspace_id] // .workspace_id) › \($tabs[.tab_id] // .tab_id)"})
    | sort_by(if .here then [0] elif .visit then [1, -.visit] else [2, (.state | rank)] end)
    | (map(.where | length) | max) as $w
    | (map(.agent | length) | max) as $a
    | .[]
    | (.state | style) as [$icon, $color]
    | "\($icon) \(.state | pad(7))" as $status
    | "\(.where | pad($w))  \(.agent | pad($a))  \(.title // "")" as $rest
    | "\(if .here then "here" else .kind end)\t\(.id)\t\(.pane)\t"
      + "\u001b[\($color)m\($status)\u001b[0m  \($rest)"
  '
}

# Visits file written by visit-tracker/track.sh, as a {pane_id: epoch} object.
visits() {
  local file=${HERDR_VISITS_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/visits.tsv}
  [[ -f "$file" ]] || { echo '{}'; return; }
  jq -Rn '[inputs | split("\t") | {(.[0]): (.[1] | tonumber)}] | add // {}' "$file"
}

tab_names=(agents tabs all)

# Tab bar for the border label with tab index $1 highlighted.
tab_bar() {
  local i bar=""
  for i in "${!tab_names[@]}"; do
    if ((i == $1)); then
      bar+=$'\e[7m'" ${tab_names[i]} "$'\e[0m'
    else
      bar+=" ${tab_names[i]} "
    fi
    bar+=" "
  done
  printf ' %s←/→ ' "$bar"
}

# fzf transform for ←/→: move the active tab in $1 by $2 (+1/-1) and reload its rows.
switch_tab() {
  local dir=$1 count=${#tab_names[@]} active
  active=$((($(<"$dir/active") + $2 + count) % count))
  echo "$active" >"$dir/active"
  printf 'reload(cat %q)+first+change-prompt(%s> )+change-border-label:%s' \
    "$dir/${tab_names[active]}" "${tab_names[active]}" "$(tab_bar "$active")"
}

case "${1:-}" in
  --rows)
    rows
    exit 0
    ;;
  --switch)
    switch_tab "$2" "$3"
    exit 0
    ;;
esac

list=$(jq -n \
  --argjson agents "$(herdr agent list | jq '.result.agents')" \
  --argjson panes "$(herdr pane list | jq '.result.panes')" \
  --argjson workspaces "$(herdr workspace list | jq '.result.workspaces')" \
  --argjson tabs "$(herdr tab list | jq '.result.tabs')" \
  --argjson visits "$(visits)" \
  '{agents: $agents, panes: $panes, workspaces: $workspaces, tabs: $tabs, visits: $visits}' | rows)

header=""
if [[ "$list" == here$'\t'* ]]; then
  header=$(head -n1 <<<"$list" | cut -f4-)
  list=$(tail -n +2 <<<"$list")
fi

if [[ -z "$list" ]]; then
  echo "No other agents or tabs."
  sleep 2
  exit 0
fi

self=$(readlink -f "${BASH_SOURCE[0]}")
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
grep $'^agent\t' <<<"$list" >"$dir/agents" || true
grep $'^tab\t' <<<"$list" >"$dir/tabs" || true
printf '%s\n' "$list" >"$dir/all"
echo 0 >"$dir/active"

selection=$(fzf --ansi --delimiter=$'\t' --with-nth=4.. --no-sort --reverse \
  --prompt='agents> ' --header="$header" \
  --border=top --border-label="$(tab_bar 0)" --border-label-pos=2 \
  --bind "right:transform:$(printf '%q --switch %q 1' "$self" "$dir")" \
  --bind "left:transform:$(printf '%q --switch %q -1' "$self" "$dir")" \
  --preview='herdr pane read {3} --lines 30' --preview-window='down,60%' \
  <"$dir/agents") || exit 0

IFS=$'\t' read -r kind id _ <<<"$selection"
if [[ "$kind" == "tab" ]]; then
  herdr tab focus "$id" >/dev/null
else
  herdr agent focus "$id" >/dev/null
fi
