#!/bin/bash
#
if [[ -z $STOW_FOLDERS ]]; then
	STOW_FOLDERS="bin,nvim,tmux,zsh"
fi

if [[ -z $DOTFILES ]]; then
	DOTFILES=$HOME/projects/dotfiles
fi

STOW_FOLDERS=$STOW_FOLDERS DOTFILES=$DOTFILES $DOTFILES/install
