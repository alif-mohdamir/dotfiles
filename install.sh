#!/bin/bash
#
if [[ -z $STOW_FOLDERS ]]; then
	STOW_FOLDERS="bin,nvim,tmux,zsh,alacritty,starship"
fi

if [[ -z $DOTFILES ]]; then
	DOTFILES=~/projects/dotfiles
fi

STOW_FOLDERS=$STOW_FOLDERS DOTFILES=$DOTFILES $DOTFILES/stow-dotfiles.sh
