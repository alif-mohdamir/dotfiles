#!/bin/bash

# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"

# Install tools
brew install tmux
brew install starship
brew install zsh
brew install fzf

brew install gh
brew install lazygit
brew install neovim
brew install ripgrep
brew install --cask font-jetbrains-mono-nerd-font
brew install stow

# Additional packages needed for fzf-tab-completion
brew install gawk grep gnu-sed coreutils

# Install oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# Install zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions

# Set up fzf key bindings and fuzzy completion
source <(fzf --zsh)
