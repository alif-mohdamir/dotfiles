# dotfiles

This repo is public, and it installs on both work and personal machines: macOS laptops
and Linux dev boxes.

- Keep employer-specific names out of files and commit messages, including internal
  tools, hostnames, account IDs and work emails. Pushed history is public too, and
  removing something from it takes a force push.
- Machine-specific setup goes in untracked local files:
  - `~/.zsh_profile_local`, sourced by `.zshrc`
  - `~/.config/jj/conf.d/user.toml`, for jj's `[user]` and `[signing]`
  - `~/.config/tmux-sessionizer/sources/`, for extra sessionizer entries
- A script must still work on a machine that lacks a tool it can use. Check with
  `command -v` and skip that step.
- `install.sh` also runs on Linux, where it hands off to `install-on-linux.sh`. Before
  pushing a Linux change, run it in a fresh container such as `ubuntu:24.04`.
- When testing tmux scripts, unset `TMUX` and point every `tmux` call at a scratch socket
  with `-S`. An inherited `TMUX` sends even `kill-server` to the user's own server.
