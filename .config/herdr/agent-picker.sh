#!/usr/bin/env bash
# Pick an agent or a tab without agents with fzf, and jump to it.
# Rows are grouped in picker tabs: agents, tabs without agents, then all; h/l, ←/→ or Tab switch.
# Vim-style: opens in normal mode (j/k, g/G, ctrl-d/u, dd clears the filter, q/Esc quit);
# i edits the filter and / starts a new one; Esc or jk returns to normal mode.
# The agent or tab you are on is pinned as the header (not searchable); the rest
# follow by last visit (recorded by the visit-tracker plugin), never-visited ones
# last by urgency, so the cursor starts on the previous session.
# Bound to prefix+a as a popup in config.toml.
# `agent-picker.sh --rows` only turns {agents,panes,workspaces,tabs,visits} JSON on stdin
# into "kind<TAB>id<TAB>preview-pane<TAB>row" lines; kind is agent, tab or here (current).
set -euo pipefail
# Popups inherit the herdr server's PATH, which can miss user-installed herdr and fzf.
PATH="$HOME/.local/bin:$PATH"

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

# Tab bar for the border label with tab index $1 highlighted and the active filter $2.
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
  [[ -n "${2:-}" ]] && bar+="/$2  "
  printf ' %s ' "$bar"
}

# fzf transform for view switching: move the active tab in $1 by $2 (+1/-1) and reload its rows.
switch_tab() {
  local dir=$1 count=${#tab_names[@]} active
  active=$((($(<"$dir/active") + $2 + count) % count))
  echo "$active" >"$dir/active"
  printf 'reload(cat %q)+first+change-prompt(%s> )+change-border-label:%s' \
    "$dir/${tab_names[active]}" "${tab_names[active]}" "$(tab_bar "$active" "${FZF_QUERY:-}")"
}

now_ms() {
  local t=${EPOCHREALTIME//[.,]/}
  echo $((t / 1000))
}

# True when marker file $1 was written less than $2 ms ago.
recent() {
  local last
  last=$(cat "$1" 2>/dev/null || echo 0)
  (($(now_ms) - last < $2))
}

# fzf transform for vim-style keys: normal mode while the input is hidden, insert mode while shown.
key_action() {
  local dir=$1 key=$2 query=${FZF_QUERY:-} active
  active=$(<"$dir/active")
  if [[ "${FZF_INPUT_STATE:-}" == enabled ]]; then
    case "$key" in
      esc) printf 'hide-input+change-border-label:%s' "$(tab_bar "$active" "$query")" ;;
      left) echo backward-char ;;
      right) echo forward-char ;;
      ctrl-d) echo delete-char ;;
      ctrl-u) echo unix-line-discard ;;
      j) now_ms >"$dir/j"; echo 'put(j)' ;;
      k)
        if [[ "$query" == *j ]] && recent "$dir/j" 300; then
          touch "$dir/hide"
          echo backward-delete-char
        else
          echo 'put(k)'
        fi
        ;;
      *) printf 'put(%s)' "$key" ;;
    esac
    return
  fi
  case "$key" in
    j) echo down ;;
    k) echo up ;;
    g) echo first ;;
    G) echo last ;;
    ctrl-d) echo half-page-down ;;
    ctrl-u) echo half-page-up ;;
    h | left) switch_tab "$dir" -1 ;;
    l | right) switch_tab "$dir" 1 ;;
    i) echo show-input ;;
    /) printf 'show-input+clear-query+change-border-label:%s' "$(tab_bar "$active" "")" ;;
    d)
      if recent "$dir/d" 500; then
        rm -f "$dir/d"
        touch "$dir/hide"
        echo show-input+clear-query
      else
        now_ms >"$dir/d"
        echo ignore
      fi
      ;;
    q | esc) echo abort ;;
    *) echo ignore ;;
  esac
}

# Second transform after d and k: fzf drops query edits made in the same transform as hide-input.
hide_after_edit() {
  local dir=$1
  if [[ -f "$dir/hide" ]]; then
    rm -f "$dir/hide"
    printf 'hide-input+change-border-label:%s' "$(tab_bar "$(<"$dir/active")" "${FZF_QUERY:-}")"
  else
    echo ignore
  fi
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
  --key)
    key_action "$2" "$3"
    exit 0
    ;;
  --after)
    hide_after_edit "$2"
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

binds=()
for key in j k g G h l i q d / esc left right ctrl-d ctrl-u; do
  action="transform($(printf '%q --key %q %q' "$self" "$dir" "$key"))"
  [[ "$key" == d || "$key" == k ]] && action+="+transform($(printf '%q --after %q' "$self" "$dir"))"
  binds+=(--bind "$key:$action")
done
selection=$(fzf --ansi --delimiter=$'\t' --with-nth=4.. --no-sort --reverse --cycle --no-input \
  --prompt='agents> ' --header="$header" \
  --border=top --border-label="$(tab_bar 0)" --border-label-pos=2 \
  "${binds[@]}" \
  --bind "tab:transform:$(printf '%q --switch %q 1' "$self" "$dir")" \
  --bind "btab:transform:$(printf '%q --switch %q -1' "$self" "$dir")" \
  --preview='herdr pane read {3} --lines 30' --preview-window='down,60%' \
  <"$dir/agents") || exit 0

IFS=$'\t' read -r kind id _ <<<"$selection"
if [[ "$kind" == "tab" ]]; then
  herdr tab focus "$id" >/dev/null
else
  herdr agent focus "$id" >/dev/null
fi
