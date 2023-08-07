export PATH=/opt/homebrew/bin:$PATH
export PATH=/opt/homebrew/Cellar/neovim:$PATH
export GOPATH="$HOME/go"
export PATH=$PATH:$GOPATH/bin
export NVM_DIR=~/.nvm
export SSH_AUTH_SOCK=~/Library/Group\ Containers/2BUA8C4S2C.com.1password/t/agent.sock
source $(brew --prefix nvm)/nvm.sh
source ~/.bash_profile
# source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/fzf-tab-completion/fzf-zsh-completion.sh
bindkey '^I' fzf_completion
# only for git
zstyle ':completion:*:*:git:*' fzf-search-display true
# or for everything
zstyle ':completion:*' fzf-search-display true

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh




# Git autocompletion
autoload -Uz compinit && compinit

export PATH="/opt/homebrew/opt/mysql-client/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/opt/mysql-client/lib/pkgconfig"
export LDFLAGS="-L/opt/homebrew/opt/mysql-client/lib"
export CPPFLAGS="-I/opt/homebrew/opt/mysql-client/include"


# Enables using dotfiles as a bare repo to source dot files and configs
alias config='/usr/bin/git --git-dir=$HOME/dotfiles/ --work-tree=$HOME'
export PATH="$HOME/scripts:$PATH"

PATH="$PATH:/Applications/WezTerm.app/Contents/MacOS"
export PATH


