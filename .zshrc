# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="juanghurtado"

plugins=(git command-not-found)

source $ZSH/oh-my-zsh.sh

# Aliases
alias upup="sudo apt-get update && sudo apt-get upgrade -y"
alias dcup='sudo docker compose up -d'
alias dcdn='sudo docker compose down'
alias dcl='sudo docker compose logs -f'
alias dcre='sudo docker compose up -d --force-recreate'
alias dcps='sudo docker compose ps'
alias dcpl='sudo docker compose pull'

# pipx
export PATH="$PATH:$HOME/.local/bin"
autoload -U bashcompinit
bashcompinit
