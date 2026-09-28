#!/usr/bin/env bash
# Pick a URL from the focused Herdr pane with fzf and open it in the browser.
# Bound to prefix+u as a popup in config.toml.
# `open-url.sh --list` only extracts URLs from stdin (newest first);
# `open-url.sh --open <url>` only opens a URL. Works on Linux and macOS.
set -euo pipefail

list_urls() {
  grep -oE "https?://[^][:space:]<>\"'\`()]+" \
    | sed -E 's/[.,;:!?]+$//' \
    | awk '{ line[NR] = $0 } END { for (i = NR; i > 0; i--) if (!seen[line[i]]++) print line[i] }'
}

open_url() {
  if command -v xdg-open >/dev/null; then
    setsid -f xdg-open "$1" >/dev/null 2>&1
  else
    open "$1"
  fi
}

if [[ "${1:-}" == "--open" ]]; then
  open_url "$2"
  exit 0
fi

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

open_url "$url"
