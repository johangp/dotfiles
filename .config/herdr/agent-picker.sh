#!/usr/bin/env bash
# Pick an agent (sorted by urgency) or a tab without agents with fzf, and jump to it.
# Bound to prefix+a as a popup in config.toml.
# `agent-picker.sh --rows` only turns {agents,panes,workspaces,tabs} JSON on stdin
# into "kind<TAB>id<TAB>preview-pane<TAB>row" lines.
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
    | [(.agents[] | select(.focused | not)
        | {kind: "agent", id: .pane_id, pane: .pane_id, workspace_id, tab_id,
           agent, state: .agent_status, title: .terminal_title_stripped}),
       (.tabs[] | select(.focused | not) | .tab_id as $t
        | select(any($agent_tabs[]; . == $t) | not)
        | ([$panes[] | select(.tab_id == $t)] | (map(select(.focused)) + .)[0]) as $p
        | select($p != null)
        | {kind: "tab", id: $t, pane: $p.pane_id, workspace_id: $p.workspace_id, tab_id: $t,
           agent: "shell", state: "tab", title: $p.terminal_title_stripped})]
    | map(. + {where: "\($ws[.workspace_id] // .workspace_id) › \($tabs[.tab_id] // .tab_id)"})
    | sort_by(.state | rank)
    | (map(.where | length) | max) as $w
    | (map(.agent | length) | max) as $a
    | .[]
    | (.state | style) as [$icon, $color]
    | "\(.kind)\t\(.id)\t\(.pane)\t\u001b[\($color)m\($icon) \(.state | pad(7))\u001b[0m  \(.where | pad($w))  \(.agent | pad($a))  \(.title // "")"
  '
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
  '{agents: $agents, panes: $panes, workspaces: $workspaces, tabs: $tabs}' | rows)

if [[ -z "$list" ]]; then
  echo "No other agents or tabs."
  sleep 2
  exit 0
fi

selection=$(fzf --ansi --delimiter=$'\t' --with-nth=4.. --no-sort --reverse \
  --prompt='agent> ' \
  --preview='herdr pane read {3} --lines 30' --preview-window='down,60%' \
  <<<"$list") || exit 0

IFS=$'\t' read -r kind id _ <<<"$selection"
if [[ "$kind" == "tab" ]]; then
  herdr tab focus "$id" >/dev/null
else
  herdr agent focus "$id" >/dev/null
fi
