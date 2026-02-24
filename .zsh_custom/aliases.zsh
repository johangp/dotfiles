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
