# Init
autoload -Uz compinit
compinit

# Prompt Theme
PROMPT='%F{green}%n@%m%f:%F{yellow}%~%f
%B%F{blue}>%f%b '
RPROMPT='%F{242}%D{%Y-%m-%d %H:%M:%S}%f'

# History Config
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_SPACE     # a command typed with a leading space is never recorded
setopt HIST_IGNORE_ALL_DUPS  # collapse duplicate commands to the most recent
setopt HIST_REDUCE_BLANKS    # tidy whitespace before saving
setopt EXTENDED_HISTORY      # record a timestamp per command
setopt SHARE_HISTORY         # concurrent shells share one live history

# Command Navigation
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' group-name ''

# Ctrl & Alt (5D/C & 5D/C) move by word/separator
backward-word-fine() { local WORDCHARS=''; zle backward-word; }
forward-word-fine()  { local WORDCHARS=''; zle forward-word; }
zle -N backward-word-fine
zle -N forward-word-fine
bindkey '^[[1;5D' backward-word-fine
bindkey '^[[1;5C' forward-word-fine
bindkey '^[[1;3D' backward-word-fine
bindkey '^[[1;3C' forward-word-fine
# Ctrl Bkspace & Del (^H & ^[[3;5~]]) delete whole words
backward-kill-word-fine() { local WORDCHARS=''; zle backward-kill-word; }
kill-word-fine()          { local WORDCHARS=''; zle kill-word; }
zle -N backward-kill-word-fine
zle -N kill-word-fine
bindkey '^[[3;5~' kill-word-fine            
bindkey '^H' backward-kill-word-fine   

# Aliases
alias upup="sudo apt-get update && sudo apt-get upgrade -y"
alias dcup='sudo docker compose up -d'
alias dcdn='sudo docker compose down'
alias dcl='sudo docker compose logs -f'
alias dcre='sudo docker compose up -d --force-recreate'
alias dcps='sudo docker compose ps'
alias dcpl='sudo docker compose pull'
alias ls='ls --color=auto'
alias la='ls -lA'

# Path
export PATH="$PATH:/opt/terraform:$HOME/.local/bin"

# Plugins
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
