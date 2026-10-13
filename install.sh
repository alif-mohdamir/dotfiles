#!/bin/bash
#
DOTFILES=${DOTFILES:-$(cd "$(dirname "$0")" && pwd)}

# Remote dev boxes run this when they clone the repo, where the macOS set would overlay the box's own Claude and shell setup
if [[ $(uname -s) == Linux ]]; then
	exec "$DOTFILES/install-on-linux.sh"
fi

if [[ -z $STOW_FOLDERS ]]; then
	STOW_FOLDERS="bin,nvim,tmux,zsh,alacritty,starship,claude,jj"
fi

STOW_FOLDERS=$STOW_FOLDERS DOTFILES=$DOTFILES $DOTFILES/stow-dotfiles.sh
$DOTFILES/claude-settings/generate.sh

if [[ ! -f ~/.config/jj/conf.d/user.toml ]]; then
	echo "warning: create ~/.config/jj/conf.d/user.toml with a [user] name and email; they stay out of this public repo" >&2
fi
