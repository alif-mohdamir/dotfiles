#!/bin/bash

# Change directory to dotfiles
pushd $DOTFILES

# Loop through each folder to stow
for folder in $(echo $STOW_FOLDERS | sed "s/,/ /g"); do
	echo "stow $folder"
	sow -D $folder
	stow $folder
done

# Change directory back to the previous location
popd
