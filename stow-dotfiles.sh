#!/bin/bash

# Change directory to dotfiles
pushd $DOTFILES

# Loop through each folder to stow
for folder in $(echo $STOW_FOLDERS | sed "s/,/ /g"); do
	echo "stow $folder"
	# stow creates the symlink to the parent directory of where the command is run if no --target is specified
	flags=""
	# ~/.claude also holds machine state and claude.ai-synced skills; linking whole dirs would write those into the repo
	[[ $folder == claude ]] && flags="--no-folding"
	stow -D --target ~ $folder
	stow $flags --target ~ $folder
	# Uncomment the line below to stow and import whatever differences are present in the target directory
	# stow --target ~ $folder --adopt
done

# Change directory back to the previous location
popd
