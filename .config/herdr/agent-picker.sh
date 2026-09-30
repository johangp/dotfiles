#!/usr/bin/env bash
# Pick an agent or a tab without agents with fzf, and jump to it.
# Rows are grouped in tabs: local, one per enabled saved machine, then all; ←/→ switch.
# The agent or tab you are on is pinned as the header (not searchable); the rest
# follow by last visit (recorded by the visit-tracker plugin, local only), never-visited
# ones last by urgency, so the cursor starts on the previous session.
# Remote tabs open with the rows cached by the previous popup and reload once a fresh
# snapshot arrives. Herdr cannot switch the client to another machine, so picking a remote
# row focuses it on that machine and you switch to the machine in the sidebar.
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

# One `api snapshot` per machine as {machine, data}; remote calls time out.
snapshot() {
  local machine=$1 visit_json='{}' cmd=(herdr)
  if [[ "$machine" == local ]]; then
    visit_json=$(visits)
  else
    cmd=(perl -e 'alarm shift; exec @ARGV' "$remote_timeout" herdr --machine "$machine")
  fi
  "${cmd[@]}" api snapshot 2>/dev/null | jq -ce --arg machine "$machine" --argjson visits "$visit_json" \
    '{machine: $machine, data: (.result.snapshot | {agents, panes, workspaces, tabs, visits: $visits})}'
}

tabs() { printf '%s\n' local; cat "$dir/machines"; printf '%s\n' all; }

# Rebuild rows.<tab> for one machine and for all, dropping the pinned "here" row.
build_rows() {
  local machine=$1 files=() m
  if [[ -s "$dir/data.$machine.json" ]]; then
    jq -s . "$dir/data.$machine.json" | rows false | grep -v $'^here\t' >"$dir/rows.$machine.tmp" || true
  else
    : >"$dir/rows.$machine.tmp"
  fi
  mv "$dir/rows.$machine.tmp" "$dir/rows.$machine"
  until mkdir "$dir/lock" 2>/dev/null; do sleep 0.05; done
  while IFS= read -r m; do
    [[ -s "$dir/data.$m.json" ]] && files+=("$dir/data.$m.json")
  done < <(tabs | sed '$d')
  : >"$dir/rows.all.tmp"
  if ((${#files[@]})); then
    jq -s . "${files[@]}" | rows true | grep -v $'^here\t' >"$dir/rows.all.tmp" || true
  fi
  mv "$dir/rows.all.tmp" "$dir/rows.all"
  rmdir "$dir/lock"
}

# Tab bar for the border label; remote tabs show … while loading and ✗ when unreachable.
tab_bar() {
  local active i=0 name state mark bar=""
  active=$(cat "$dir/active")
  while IFS= read -r name; do
    state=$(cat "$dir/state.$name" 2>/dev/null || echo up)
    case "$state" in
      loading) mark=" …" ;;
      down) mark=" ✗" ;;
      *) mark="" ;;
    esac
    if ((i == active)); then
      bar+=$'\e[7m'" $name$mark "$'\e[0m'
    elif [[ "$state" == down ]]; then
      bar+=$'\e[31m'" $name$mark "$'\e[0m'
    else
      bar+=" $name$mark "
    fi
    bar+=" "
    i=$((i + 1))
  done < <(tabs)
  printf ' %s ←/→ ' "$bar"
}

active_name() { tabs | sed -n "$(($(cat "$dir/active") + 1))p"; }

# fzf transform for ←/→: move the active tab by $1 (+1/-1) and reload its rows.
switch_tab() {
  local count name
  count=$(tabs | wc -l | tr -d ' ')
  echo $((($(cat "$dir/active") + $1 + count) % count)) >"$dir/active"
  name=$(active_name)
  printf 'reload(cat %q)+first+change-prompt(%s> )+change-border-label:%s' \
    "$dir/rows.$name" "$name" "$(tab_bar)"
}

# Background: fresh remote snapshot, cached for the next popup, then pushed to fzf.
refresh() {
  local machine=$1 name action i
  if snapshot "$machine" >"$dir/data.$machine.new"; then
    mv "$dir/data.$machine.new" "$dir/data.$machine.json"
    cp "$dir/data.$machine.json" "$cache_dir/$machine.json"
    echo up >"$dir/state.$machine"
  else
    rm -f "$dir/data.$machine.new"
    echo down >"$dir/state.$machine"
  fi
  build_rows "$machine"
  for ((i = 0; i < 50; i++)); do [[ -S "$dir/fzf.sock" ]] && break; sleep 0.1; done
  name=$(active_name)
  action="change-border-label:$(tab_bar)"
  [[ "$name" == "$machine" || "$name" == all ]] && action="reload(cat $(printf '%q' "$dir/rows.$name"))+$action"
  curl -s --max-time 2 --unix-socket "$dir/fzf.sock" -X POST http://localhost -d "$action" >/dev/null 2>&1 || true
}

case "${1:-}" in
  --rows)
    jq --arg machine "${2:-local}" '[{machine: $machine, data: .}]' | rows false
    exit 0
    ;;
  --switch)
    dir=$2
    switch_tab "$3"
    exit 0
    ;;
  --preview)
    herdr_on "$2" pane read "$3" --lines 30
    exit 0
    ;;
esac

cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/herdr-picker
mkdir -p "$cache_dir"
dir=$(mktemp -d)
jobs_pids=()
cleanup() {
  if ((${#jobs_pids[@]})); then kill "${jobs_pids[@]}" 2>/dev/null || true; fi
  rm -rf "$dir"
}
trap cleanup EXIT

herdr machine list --json 2>/dev/null | jq -r '.[] | select(.enabled) | .label' >"$dir/machines" || : >"$dir/machines"
echo 0 >"$dir/active"

snapshot local >"$dir/data.local.json"
header=$(jq -s . "$dir/data.local.json" | rows false | grep -m1 $'^here\t' | cut -f5- || true)
build_rows local
while IFS= read -r machine; do
  if [[ -s "$cache_dir/$machine.json" ]]; then
    cp "$cache_dir/$machine.json" "$dir/data.$machine.json"
  fi
  echo loading >"$dir/state.$machine"
  build_rows "$machine"
  refresh "$machine" &
  jobs_pids+=("$!")
done <"$dir/machines"

selection=$(fzf --ansi --delimiter=$'\t' --with-nth=5.. --no-sort --reverse \
  --listen="$dir/fzf.sock" \
  --prompt='local> ' --header="$header" \
  --border=top --border-label="$(tab_bar)" --border-label-pos=2 \
  --bind "right:transform:$(printf '%q --switch %q 1' "$self" "$dir")" \
  --bind "left:transform:$(printf '%q --switch %q -1' "$self" "$dir")" \
  --preview="$(printf '%q --preview {4} {3}' "$self")" --preview-window='down,60%' \
  <"$dir/rows.local") || exit 0

IFS=$'\t' read -r kind id _ machine _ <<<"$selection"
[[ -n "${id:-}" ]] || exit 0
if [[ "$kind" == "tab" ]]; then
  herdr_on "$machine" tab focus "$id" >/dev/null
else
  herdr_on "$machine" agent focus "$id" >/dev/null
fi
if [[ "$machine" != local ]]; then
  echo "Focused on $machine. Switch to $machine in the sidebar."
  sleep 1.5
fi
