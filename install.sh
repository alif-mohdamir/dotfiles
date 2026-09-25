#!/bin/bash
#
if [[ -z $STOW_FOLDERS ]]; then
	STOW_FOLDERS="bin,nvim,tmux,zsh,alacritty,starship,claude,jj"
fi

if [[ -z $DOTFILES ]]; then
	DOTFILES=~/projects/dotfiles
fi

STOW_FOLDERS=$STOW_FOLDERS DOTFILES=$DOTFILES $DOTFILES/stow-dotfiles.sh
$DOTFILES/claude-settings/generate.sh

if [[ ! -f ~/.config/jj/conf.d/user.toml ]]; then
	echo "warning: create ~/.config/jj/conf.d/user.toml with a [user] name and email; they stay out of this public repo" >&2
fi
