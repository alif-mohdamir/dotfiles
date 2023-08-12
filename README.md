# dotfiles

Few dot files for tmux, wezterm, and lazyvim config. Scripts inspired by scripts from [ThePrimeagen](https://github.com/ThePrimeagen/.dotfiles/blob/master/bin/.local/scripts/tmux-sessionizer)

1. [tmux install instructions](https://github.com/tmux/tmux/wiki/Installing)
2. [wezterm mac install instructions](https://wezfurlong.org/wezterm/install/macos.html)
    - (don't forget the `.zshrc` step) if you want `wezterm-spawner` to work
3. [lazyvim install](https://www.lazyvim.org/installation)
4. [oh-my-zsh install](https://github.com/ohmyzsh/ohmyzsh/wiki/Installing-ZSH)
5. [starship](https://starship.rs/#install-via-package-manager) install

You should be able to run `cfg.install.sh` to install most of the required dependencies with curl and brew

[Guide for using this repo as a bare repo](https://www.atlassian.com/git/tutorials/dotfiles)
Saving old configs as a backup
```
mkdir -p .config-backup && \
config checkout 2>&1 | egrep "\s+\." | awk '{print $1}' | \
xargs -I{} sh -c "mkdir -p .config-backup/\$(dirname "{}") && mv "{}" .config-backup/{}"
```
