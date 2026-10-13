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

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# curl, not gh: dev boxes can run this when they clone the repo, before gh is signed in
download() { curl -fsSL "https://github.com/$1/releases/$2" -o "$tmp/$(basename "$2")"; }
latest_tag() { curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" | sed 's|.*/tag/||'; }

download neovim/neovim "download/stable/nvim-linux-$nvim_arch.tar.gz"
rm -rf "$OPT/nvim-linux-$nvim_arch"
tar -xzf "$tmp/nvim-linux-$nvim_arch.tar.gz" -C "$OPT"
ln -sfn "$OPT/nvim-linux-$nvim_arch/bin/nvim" "$BIN/nvim"

download tree-sitter/tree-sitter "latest/download/tree-sitter-linux-$ts_arch.gz"
gunzip -c "$tmp/tree-sitter-linux-$ts_arch.gz" >"$BIN/tree-sitter"
chmod +x "$BIN/tree-sitter"

lazygit_version=$(latest_tag jesseduffield/lazygit)
lazygit_file="lazygit_${lazygit_version#v}_linux_$lazygit_arch.tar.gz"
download jesseduffield/lazygit "download/$lazygit_version/$lazygit_file"
tar -xzf "$tmp/$lazygit_file" -C "$BIN" lazygit

if ! command -v rg >/dev/null; then
	rg_version=$(latest_tag BurntSushi/ripgrep)
	download BurntSushi/ripgrep "download/$rg_version/ripgrep-$rg_version-$rg_target.tar.gz"
	tar -xzf "$tmp/ripgrep-$rg_version-$rg_target.tar.gz" -C "$tmp"
	cp "$tmp/ripgrep-$rg_version-$rg_target/rg" "$BIN/rg"
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
	# Without it stow folds all of ~/.config into a link to the repo, and gh, jj and the rest then write into the clone
	mkdir -p ~/.config
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
