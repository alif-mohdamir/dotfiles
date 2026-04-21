# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH
# zmodload zsh/zprof

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# User configuration
source ~/.zsh_profile
source ~/.zsh_profile_local

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME=""

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git gitfast zsh-autosuggestions tmux direnv kubectl jj)

source $ZSH/oh-my-zsh.sh

# Set up fzf key bindings and fuzzy completion
# This needs to occur after oh-my-zsh is sourced in order for key maps to be setup correctly
source <(fzf --zsh)

# fzf-tab: replace fzf's default completion with native zsh completions in fzf UI
# Sourced after fzf --zsh so it overrides fzf's Tab binding
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab/fzf-tab.plugin.zsh

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi
export EDITOR='nvim'
export VISUAL='nvim'

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"
eval "$(starship init zsh)"

[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ] && source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin:$PATH"
# zprof

# Remove isolated PR-review checkouts left by the /review-pr skill (.pr-review-* siblings).
# Run from inside the target repo. `pr-review-clean dry` previews without deleting.
pr-review-clean() {
  emulate -L zsh
  local DRY=0 root vcs found ws wsroot d
  case "$1" in dry|list|-n|--dry-run) DRY=1 ;; esac
  if jj root >/dev/null 2>&1; then
    root=$(jj root); vcs=jj
  elif root=$(git rev-parse --show-toplevel 2>/dev/null); then
    vcs=git
  else
    print -ru2 -- "Not inside a jj or git repo — cd into the repo first."; return 1
  fi
  found=0
  if [ "$vcs" = jj ]; then
    while IFS= read -r ws; do
      [ -n "$ws" ] || continue
      [ "$ws" = default ] && continue
      wsroot=$(jj -R "$root" workspace root --name "$ws" 2>/dev/null) || continue
      case "${wsroot:t}" in .pr-review-*) ;; *) continue ;; esac
      (( found += 1 ))
      if (( DRY )); then print -r -- "would remove (jj): $ws -> $wsroot"; continue; fi
      jj -R "$root" workspace forget "$ws" 2>/dev/null
      rm -rf "$wsroot"; print -r -- "removed jj workspace: $ws ($wsroot)"
    done < <(jj -R "$root" workspace list -T 'name ++ "\n"')
  else
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "${d:t}" in .pr-review-*) ;; *) continue ;; esac
      (( found += 1 ))
      if (( DRY )); then print -r -- "would remove (git): $d"; continue; fi
      git -C "$root" worktree remove --force "$d" 2>/dev/null || rm -rf "$d"
      print -r -- "removed git worktree: $d"
    done < <(git -C "$root" worktree list --porcelain | sed -n 's/^worktree //p')
    (( DRY )) || git -C "$root" worktree prune
  fi
  (( found )) || print -r -- "No .pr-review-* checkouts found for $root."
}
