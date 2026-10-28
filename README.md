# dotfiles

Config for zsh, tmux, Neovim, jj, starship, alacritty and Claude Code, linked into `~` with
[GNU Stow](https://www.gnu.org/software/stow/). Each top-level folder is a stow package that
mirrors its layout under `~`. The tmux scripts are inspired by
[ThePrimeagen's](https://github.com/ThePrimeagen/.dotfiles/blob/master/bin/.local/scripts/tmux-sessionizer).

## Install

On macOS:

```bash
git clone git@github.com:alif-mohdamir/dotfiles.git ~/projects/dotfiles
cd ~/projects/dotfiles
./install-with-brew.sh   # Homebrew, the CLI tools, oh-my-zsh and its plugins
./install.sh             # stow the packages and write ~/.claude/settings.json
peon-ping-setup          # sound packs and the hook script the Claude settings call
nvim                     # first launch installs plugins and treesitter parsers
```

Then add your jj identity (see below) and open a new shell. `install.sh` is safe to rerun.
The Neovim config needs Neovim 0.12 or newer.

On Linux, run `./install.sh`. It hands off to `install-on-linux.sh`, which downloads the
tools into `~/.local` and stows a smaller set of packages.

## Machine-local files

Anything specific to one machine goes in untracked files, since this repo is public:

| File                                   | Used for                                     |
| -------------------------------------- | -------------------------------------------- |
| `~/.zsh_profile_local`                 | Sourced by `.zshrc`: env vars, work paths    |
| `~/.config/jj/conf.d/user.toml`        | jj's `[user]` and `[signing]`                |
| `~/.tmux.local.conf`                   | Sourced at the end of `.tmux.conf`           |
| `~/.config/tmux-sessionizer/sources/`  | Executables that print extra sessionizer entries |
| `~/.claude/settings.machine.json`      | Merged over the shared Claude settings       |

An example `user.toml` that keeps your real email out of commits with GitHub's noreply
address (find yours under GitHub's email settings):

```toml
[user]
name = "Your Name"
email = "12345678+username@users.noreply.github.com"

[signing]
behavior = "own"
backend = "ssh"
key = "ssh-ed25519 AAAA..."
```

## Claude Code settings

`~/.claude/settings.json` is generated, not stowed. `claude-settings/generate.sh` merges
`claude-settings/settings.base.json` with `~/.claude/settings.machine.json`, if that file
exists. The machine file wins on conflicts, and an array in it replaces the base array
instead of extending it. Removing a key from the base file does not remove it from a
machine file that sets it.

The compound-engineering marketplace is pinned to a release tag in the base file. Bump
`ref` there to upgrade, then re-add the marketplace with the new tag. Linux boxes keep their
own `settings.json`, so `install-on-linux.sh` installs the plugin from that same `ref`
instead.

`bin/scripts/ce-sync` keeps a checkout's compound-engineering artifacts in `.ce/`, hidden
from git through `.git/info/exclude`, and syncs its learnings and plans with a private store
from the SessionStart, Stop and SessionEnd hooks. Deletes reach every machine, and when two
machines change the same file both versions are kept, with a message on screen naming the
file to merge. `install-on-linux.sh` adds those hooks to a box's own `settings.json`, replacing
any older ce-sync entries. The store commands are set per machine in
`~/.config/ce-sync/config`, as the script's header shows. Until that file exists, ce-sync
does nothing.

If `settings.json` was edited after it was generated, the generator stops and prints a diff
instead of overwriting it. Move the changes you want to keep into one of the two source
files, then run `claude-settings/generate.sh --force`. `peon-ping-setup` triggers this every
time by rewriting the hook paths from `~/` to full paths, and those edits are safe to discard.
