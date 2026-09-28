#!/usr/bin/env bash
# Pick an agent or a tab without agents with fzf, and jump to it.
# The agent or tab you are on is pinned as a cyan header (not searchable); the rest
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
      + if .here then "\u001b[36m\($status)  \($rest)\u001b[0m"
        else "\u001b[\($color)m\($status)\u001b[0m  \($rest)" end
  '
}

# Visits file written by visit-tracker/track.sh, as a {pane_id: epoch} object.
visits() {
  local file=${HERDR_VISITS_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/visits.tsv}
  [[ -f "$file" ]] || { echo '{}'; return; }
  jq -Rn '[inputs | split("\t") | {(.[0]): (.[1] | tonumber)}] | add // {}' "$file"
}

if [[ "${1:-}" == "--rows" ]]; then
  rows
  exit 0
fi

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

selection=$(fzf --ansi --delimiter=$'\t' --with-nth=4.. --no-sort --reverse \
  --prompt='agent> ' --header="$header" \
  --preview='herdr pane read {3} --lines 30' --preview-window='down,60%' \
  <<<"$list") || exit 0

IFS=$'\t' read -r kind id _ <<<"$selection"
if [[ "$kind" == "tab" ]]; then
  herdr tab focus "$id" >/dev/null
else
  herdr agent focus "$id" >/dev/null
fi
