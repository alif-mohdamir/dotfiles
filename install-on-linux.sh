#!/bin/bash
set -euo pipefail

DOTFILES=${DOTFILES:-$(cd "$(dirname "$0")" && pwd)}
login_path=$PATH
BIN=~/.local/bin
OPT=~/.local/opt
mkdir -p "$BIN" "$OPT"

case $(uname -m) in
aarch64 | arm64)
	nvim_arch=arm64 ts_arch=arm64 lazygit_arch=arm64 rg_target=aarch64-unknown-linux-gnu
	;;
x86_64)
	nvim_arch=x86_64 ts_arch=x64 lazygit_arch=x86_64 rg_target=x86_64-unknown-linux-musl
	;;
*)
	echo "unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac

packages=(git make gcc unzip curl tar gzip stow tmux ripgrep)
if command -v apt-get >/dev/null; then
	sudo apt-get update
	sudo apt-get install -y "${packages[@]}"
elif command -v dnf >/dev/null; then
	# One at a time so a package this distro lacks doesn't block the rest; ripgrep has a GitHub fallback below
	for p in "${packages[@]}"; do sudo dnf install -y "$p" || echo "dnf has no $p" >&2; done
else
	echo "no apt-get or dnf; install these yourself: ${packages[*]}" >&2
fi

command -v gh >/dev/null || { echo "gh is required to download releases" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

gh release download -R neovim/neovim stable -p "nvim-linux-$nvim_arch.tar.gz" -D "$tmp"
rm -rf "$OPT/nvim-linux-$nvim_arch"
tar -xzf "$tmp/nvim-linux-$nvim_arch.tar.gz" -C "$OPT"
ln -sfn "$OPT/nvim-linux-$nvim_arch/bin/nvim" "$BIN/nvim"

gh release download -R tree-sitter/tree-sitter -p "tree-sitter-linux-$ts_arch.gz" -D "$tmp"
gunzip -c "$tmp/tree-sitter-linux-$ts_arch.gz" >"$BIN/tree-sitter"
chmod +x "$BIN/tree-sitter"

gh release download -R jesseduffield/lazygit -p "lazygit_*_linux_$lazygit_arch.tar.gz" -D "$tmp"
tar -xzf "$tmp"/lazygit_*_linux_"$lazygit_arch".tar.gz -C "$BIN" lazygit

if ! command -v rg >/dev/null; then
	gh release download -R BurntSushi/ripgrep -p "ripgrep-*-$rg_target.tar.gz" -D "$tmp"
	tar -xzf "$tmp"/ripgrep-*-"$rg_target".tar.gz -C "$tmp"
	cp "$tmp"/ripgrep-*-"$rg_target"/rg "$BIN/rg"
fi

# Some boxes keep go behind goenv, which non-interactive shells leave off PATH
export PATH="$BIN:$HOME/.goenv/bin:$HOME/.goenv/shims:$HOME/go/bin:$PATH"
if command -v go >/dev/null; then
	go install golang.org/x/tools/cmd/goimports@latest
else
	echo "warning: no go on PATH; gopls, delve and goimports will not install" >&2
fi
command -v npm >/dev/null || echo "warning: no npm on PATH; ts_ls, pyright and markdownlint will not install" >&2

if command -v stow >/dev/null; then
	export STOW_FOLDERS=${STOW_FOLDERS:-nvim,tmux,bin} DOTFILES
	"$DOTFILES/stow-dotfiles.sh"
else
	echo "warning: no stow; dotfiles not linked" >&2
fi

nvim --headless '+Lazy! restore' '+MasonToolsInstallSync' +qa

case ":$login_path:" in
*":$BIN:"*) ;;
*) echo "add $BIN to PATH in your shell profile" >&2 ;;
esac
