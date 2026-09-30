#!/usr/bin/env bash
# Pick an agent or a tab without agents with fzf, and jump to it.
# Rows are grouped in tabs: local, one per enabled saved machine, then all; ←/→ switch.
# The agent or tab you are on is pinned as the header (not searchable); the rest
# follow by last visit (recorded by the visit-tracker plugin, local only), never-visited
# ones last by urgency, so the cursor starts on the previous session.
# Herdr cannot switch the client to another machine, so picking a remote row focuses it
# on that machine and you switch to the machine in the sidebar.
# Bound to prefix+a as a popup in config.toml.
# `agent-picker.sh --rows [machine]` only turns {agents,panes,workspaces,tabs,visits} JSON on
# stdin into "kind<TAB>id<TAB>preview-pane<TAB>machine<TAB>row" lines; kind is agent, tab or
# here (current).
set -euo pipefail

self=$(readlink -f "${BASH_SOURCE[0]}")
remote_timeout=${HERDR_PICKER_REMOTE_TIMEOUT:-6}

# stdin: JSON array of {machine, data}; $all adds a machine column.
rows() {
  jq -r --argjson all "$1" '
    def pad($n): if $n > length then . + (" " * ($n - length)) else . end;
    def rank: {blocked: 0, done: 1, working: 2, idle: 3, tab: 5}[.] // 4;
    def style: {blocked: ["●", "31"], done: ["●", "32"], working: ["●", "33"], idle: ["○", "2"], tab: ["▢", "2"]}[.] // ["?", "2"];
    def entries:
      .machine as $m
      | .data
      | (.workspaces | map({(.workspace_id): .label}) | add // {}) as $ws
      | (.tabs | map({(.tab_id): .label}) | add // {}) as $tabs
      | (.agents | map(.tab_id)) as $agent_tabs
      | .panes as $panes
      | (.visits // {}) as $visits
      | (.agents[]
          | {kind: "agent", id: .pane_id, pane: .pane_id, workspace_id, tab_id, here: .focused,
             visit: $visits[.pane_id],
             agent, state: .agent_status, title: .terminal_title_stripped}),
        (.tabs[] | .focused as $here | .tab_id as $t
          | select(any($agent_tabs[]; . == $t) | not)
          | ([$panes[] | select(.tab_id == $t)] | (map(select(.focused)) + .)[0]) as $p
          | select($p != null)
          | {kind: "tab", id: $t, pane: $p.pane_id, workspace_id: $p.workspace_id, tab_id: $t, here: $here,
             visit: ([$panes[] | select(.tab_id == $t) | $visits[.pane_id] // empty] | max),
             agent: "shell", state: "tab", title: $p.terminal_title_stripped})
      | . + {machine: $m, here: (.here and $m == "local"),
             where: "\($ws[.workspace_id] // .workspace_id) › \($tabs[.tab_id] // .tab_id)"};
    [.[] | entries]
    | sort_by(if .here then [0] elif .visit then [1, -.visit] else [2, (.state | rank)] end)
    | (map(.where | length) | max) as $w
    | (map(.agent | length) | max) as $a
    | (map(.machine | length) | max) as $mw
    | .[]
    | (.state | style) as [$icon, $color]
    | "\($icon) \(.state | pad(7))" as $status
    | (if $all then "\(.machine | pad($mw))  " else "" end) as $machine
    | "\(.where | pad($w))  \(.agent | pad($a))  \(.title // "")" as $rest
    | "\(if .here then "here" else .kind end)\t\(.id)\t\(.pane)\t\(.machine)\t"
      + "\u001b[\($color)m\($status)\u001b[0m  \($machine)\($rest)"
  '
}

# Visits file written by visit-tracker/track.sh, as a {pane_id: epoch} object.
visits() {
  local file=${HERDR_VISITS_FILE:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/visits.tsv}
  [[ -f "$file" ]] || { echo '{}'; return; }
  jq -Rn '[inputs | split("\t") | {(.[0]): (.[1] | tonumber)}] | add // {}' "$file"
}

# herdr against a machine label; "local" is the server this popup belongs to.
herdr_on() {
  local machine=$1
  shift
  if [[ "$machine" == local ]]; then
    herdr "$@"
  else
    herdr --machine "$machine" "$@"
  fi
}

# Write $dir/data.<machine>.json as {machine, data}, querying in parallel; remote calls time out.
fetch() {
  local machine=$1 dir=$2 kind pid failed=0
  local cmd=(herdr)
  [[ "$machine" == local ]] || cmd=(perl -e 'alarm shift; exec @ARGV' "$remote_timeout" herdr --machine "$machine")
  local pids=()
  for kind in agent pane workspace tab; do
    "${cmd[@]}" "$kind" list >"$dir/$machine.$kind" 2>/dev/null &
    pids+=("$!")
  done
  for pid in "${pids[@]}"; do wait "$pid" || failed=1; done
  ((failed == 0)) || return 1
  local visit_json='{}'
  [[ "$machine" == local ]] && visit_json=$(visits)
  jq -n --arg machine "$machine" --argjson visits "$visit_json" \
    --slurpfile agents "$dir/$machine.agent" --slurpfile panes "$dir/$machine.pane" \
    --slurpfile workspaces "$dir/$machine.workspace" --slurpfile tabs "$dir/$machine.tab" \
    '{machine: $machine, data: {agents: $agents[0].result.agents, panes: $panes[0].result.panes,
      workspaces: $workspaces[0].result.workspaces, tabs: $tabs[0].result.tabs, visits: $visits}}' \
    >"$dir/data.$machine.json"
}

# Tab bar for the border label, with tab index $2 highlighted and unreachable machines marked.
tab_bar() {
  local dir=$1 active=$2 i=0 name bar=""
  while IFS=$'\t' read -r name state; do
    if ((i == active)); then
      bar+=$'\e[7m'" $name "$'\e[0m'
    elif [[ "$state" == down ]]; then
      bar+=$'\e[31m'" $name ✗ "$'\e[0m'
    else
      bar+=" $name "
    fi
    bar+=" "
    i=$((i + 1))
  done <"$dir/tabs"
  printf ' %s ←/→ ' "$bar"
}

# fzf transform for ←/→: move the active tab by $2 (+1/-1) and reload its rows.
switch_tab() {
  local dir=$1 step=$2 count active name
  count=$(wc -l <"$dir/tabs" | tr -d ' ')
  active=$(( ($(cat "$dir/active") + step + count) % count ))
  echo "$active" >"$dir/active"
  name=$(sed -n "$((active + 1))p" "$dir/tabs" | cut -f1)
  printf 'reload(cat %q)+first+change-prompt(%s> )+change-border-label:%s' \
    "$dir/rows.$name" "$name" "$(tab_bar "$dir" "$active")"
}

case "${1:-}" in
  --rows)
    jq --arg machine "${2:-local}" '[{machine: $machine, data: .}]' | rows false
    exit 0
    ;;
  --switch)
    switch_tab "$2" "$3"
    exit 0
    ;;
  --preview)
    herdr_on "$2" pane read "$3" --lines 30
    exit 0
    ;;
esac

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

machines=()
while IFS= read -r machine; do machines+=("$machine"); done < <(
  herdr machine list --json 2>/dev/null | jq -r '.[] | select(.enabled) | .label'
)

pids=()
for machine in local "${machines[@]}"; do
  fetch "$machine" "$dir" &
  pids+=("$!")
done
: >"$dir/tabs"
i=0
for machine in local "${machines[@]}"; do
  if wait "${pids[$i]}"; then
    printf '%s\tup\n' "$machine" >>"$dir/tabs"
    jq -s . "$dir/data.$machine.json" | rows false >"$dir/rows.$machine"
  else
    printf '%s\tdown\n' "$machine" >>"$dir/tabs"
    : >"$dir/rows.$machine"
  fi
  i=$((i + 1))
done
printf 'all\tup\n' >>"$dir/tabs"
data_files=()
for machine in local "${machines[@]}"; do
  [[ -f "$dir/data.$machine.json" ]] && data_files+=("$dir/data.$machine.json")
done
if ((${#data_files[@]})); then
  jq -s . "${data_files[@]}" | rows true >"$dir/rows.all"
else
  : >"$dir/rows.all"
fi

header=$(grep -m1 $'^here\t' "$dir/rows.local" | cut -f5- || true)
for file in "$dir"/rows.*; do
  grep -v $'^here\t' "$file" >"$file.tmp" || true
  mv "$file.tmp" "$file"
done

if [[ ! -s "$dir/rows.all" ]]; then
  echo "No other agents or tabs."
  sleep 2
  exit 0
fi

echo 0 >"$dir/active"
selection=$(fzf --ansi --delimiter=$'\t' --with-nth=5.. --no-sort --reverse \
  --prompt='local> ' --header="$header" \
  --border=top --border-label="$(tab_bar "$dir" 0)" --border-label-pos=2 \
  --bind "right:transform:$(printf '%q --switch %q 1' "$self" "$dir")" \
  --bind "left:transform:$(printf '%q --switch %q -1' "$self" "$dir")" \
  --preview="$(printf '%q --preview {4} {3}' "$self")" --preview-window='down,60%' \
  <"$dir/rows.local") || exit 0

IFS=$'\t' read -r kind id _ machine _ <<<"$selection"
if [[ "$kind" == "tab" ]]; then
  herdr_on "$machine" tab focus "$id" >/dev/null
else
  herdr_on "$machine" agent focus "$id" >/dev/null
fi
if [[ "$machine" != local ]]; then
  echo "Focused on $machine. Switch to $machine in the sidebar."
  sleep 1.5
fi
