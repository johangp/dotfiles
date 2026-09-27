#!/usr/bin/env bash
# Pick a URL from the focused Herdr pane with fzf and open it in the browser.
# Bound to prefix+u as a popup in config.toml.
# `open-url.sh --list` only extracts URLs from stdin (newest first).
set -euo pipefail

list_urls() {
  grep -oE "https?://[^][:space:]<>\"'\`()]+" \
    | sed -E 's/[.,;:!?]+$//' \
    | tac \
    | awk '!seen[$0]++'
}

if [[ "${1:-}" == "--list" ]]; then
  list_urls
  exit 0
fi

# The popup is not a pane, so the focused pane is the one behind it.
pane=$(herdr pane list | jq -r '[.result.panes[] | select(.focused)][0].pane_id // empty')
if [[ -z "$pane" ]]; then
  echo "No focused pane found." >&2
  sleep 2
  exit 1
fi

url=$(herdr pane read "$pane" --source recent-unwrapped --lines 1000 | list_urls \
  | fzf --prompt='open url> ' --no-sort --reverse) || exit 0

setsid -f xdg-open "$url" >/dev/null 2>&1
