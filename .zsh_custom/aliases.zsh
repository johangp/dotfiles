# Agentic Engineering Workflow Setup
work() {
  local project_name=$1
  local project_dir=$2

  if [[ -z "$project_name" || -z "$project_dir" ]]; then
    echo "Usage: work <project_name> <project_dir>"
    return 1
  fi

  cd "$project_dir" || return 1

  if ! tmux has-session -t "$project_name" 2>/dev/null; then
    tmux new-session -d -s "$project_name" -n "Mission"
  fi

  tmux select-window -t "${project_name}:Mission"
  
  if [ -z "$TMUX" ]; then
    tmux attach-session -t "$project_name"
  else
    tmux switch-client -t "$project_name"
  fi
}

# Pomodoro Timer
# Converts durations like 25m, 5s, 1h to seconds for sleep
_pomo_to_seconds() {
  local input=$1
  local num=${input%[smh]}
  local unit=${input##*[0-9]}
  case $unit in
    s) echo $num ;;
    m) echo $((num * 60)) ;;
    h) echo $((num * 3600)) ;;
    *) echo $((num * 60)) ;;
  esac
}

pstart() {
  if [[ -f /tmp/.pomo_pid ]] && kill -0 "$(cat /tmp/.pomo_pid)" 2>/dev/null; then
    echo "⏳ A timer is already running! Use 'pstop' to cancel it first."
    return
  fi

  local duration=${1:-25m}
  local seconds=$(_pomo_to_seconds "$duration")
  (sleep "$seconds" && terminal-notifier -title "🍅 Pomodoro" -message "Focus session complete! Take a break." -sound default) &
  echo $! > /tmp/.pomo_pid
  echo "🍅 Pomodoro started for $duration. Running in the background..."
}

pbreak() {
  if [[ -f /tmp/.pomo_pid ]] && kill -0 "$(cat /tmp/.pomo_pid)" 2>/dev/null; then
    echo "⏳ A timer is already running! Use 'pstop' to cancel it first."
    return
  fi

  local duration=${1:-5m}
  local seconds=$(_pomo_to_seconds "$duration")
  (sleep "$seconds" && terminal-notifier -title "☕ Break Over" -message "Time to get back to work!" -sound default) &
  echo $! > /tmp/.pomo_pid
  echo "☕ Break started for $duration. Running in the background..."
}

pstop() {
  if [[ -f /tmp/.pomo_pid ]] && kill -0 "$(cat /tmp/.pomo_pid)" 2>/dev/null; then
    kill "$(cat /tmp/.pomo_pid)" 2>/dev/null
    rm -f /tmp/.pomo_pid
    echo "🛑 Timer stopped successfully."
  else
    rm -f /tmp/.pomo_pid
    echo "No timer is currently running."
  fi
}

alias vim="nvim"
alias lazygit='command lazygit -ucf "$HOME/dotfiles/.config/lazygit/config.yml"'
if command -v bat &> /dev/null; then
  alias cat='bat --paging=never'
else
  alias cat='batcat --paging=never'
fi
alias promote='$HOME/promote.sh'
alias pa='work automation ~/src/de-trust-platform-automation'
alias dp='work pipeline ~/src/DE-TrustStream-Data-Pipeline'
alias si='work infra ~/src/stream-infra'
alias tkill='tmux kill-session'
alias revtui='roborev tui'
