#!/bin/bash
set -euo pipefail

# Box images are built under another user's home, and their goenv and pyenv shims still exec that home's tools
repair_stale_shims() {
	local tool root shim stale
	for tool in goenv pyenv; do
		root=$HOME/.$tool
		[[ -d $root/shims ]] || continue
		stale=0
		for shim in "$root"/shims/*; do
			[[ -f $shim ]] || continue
			if grep -o '/home/[^/"[:space:]]*' "$shim" | grep -qvxF "$HOME"; then
				stale=$((stale + 1))
			fi
		done
		((stale)) || continue
		if [[ $tool == goenv ]]; then
			GOENV_ROOT=$root "$root/bin/goenv" rehash || echo "warning: goenv rehash failed" >&2
		else
			PYENV_ROOT=$root "$root/bin/pyenv" rehash || echo "warning: pyenv rehash failed" >&2
		fi
		echo "repaired $stale stale $tool shims"
	done
}

# stow refuses to link over a real file, and then links nothing from the package
move_aside_stow_conflicts() {
	local package=$1 rel target backup
	while IFS= read -r rel; do
		target=$HOME/${rel#./}
		[[ -f $target && ! -L $target ]] || continue
		backup=$target.box-default
		[[ -e $backup ]] && backup=$backup.$(date +%Y%m%d%H%M%S)
		mv "$target" "$backup"
		echo "warning: moved $target to $backup so stow can link it" >&2
	done < <(cd "$package" && find . -type f)
}

# The test sources this file for its functions alone
if [[ -n ${INSTALL_ON_LINUX_FUNCTIONS_ONLY:-} ]]; then return 0; fi

DOTFILES=${DOTFILES:-$(cd "$(dirname "$0")" && pwd)}
BIN=~/.local/bin
OPT=~/.local/opt
mkdir -p "$BIN" "$OPT"

case $(uname -m) in
aarch64 | arm64)
	nvim_arch=arm64 ts_arch=arm64 lazygit_arch=arm64 rust_target=aarch64-unknown-linux-gnu jj_target=aarch64-unknown-linux-musl
	;;
x86_64)
	nvim_arch=x86_64 ts_arch=x64 lazygit_arch=x86_64 rust_target=x86_64-unknown-linux-musl jj_target=x86_64-unknown-linux-musl
	;;
*)
	echo "unsupported architecture: $(uname -m)" >&2
	exit 1
	;;
esac

packages=(git make gcc unzip curl tar gzip stow tmux ripgrep fzf jq python3)
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
	download BurntSushi/ripgrep "download/$rg_version/ripgrep-$rg_version-$rust_target.tar.gz"
	tar -xzf "$tmp/ripgrep-$rg_version-$rust_target.tar.gz" -C "$tmp"
	cp "$tmp/ripgrep-$rg_version-$rust_target/rg" "$BIN/rg"
fi

jj_version=$(latest_tag jj-vcs/jj)
download jj-vcs/jj "download/$jj_version/jj-$jj_version-$jj_target.tar.gz"
tar -xzf "$tmp/jj-$jj_version-$jj_target.tar.gz" -C "$BIN" ./jj

delta_version=$(latest_tag dandavison/delta)
download dandavison/delta "download/$delta_version/delta-$delta_version-$rust_target.tar.gz"
tar -xzf "$tmp/delta-$delta_version-$rust_target.tar.gz" -C "$tmp"
cp "$tmp/delta-$delta_version-$rust_target/delta" "$BIN/delta"

repair_stale_shims

# Some boxes keep go behind goenv, which non-interactive shells leave off PATH
export PATH="$BIN:$HOME/.goenv/bin:$HOME/.goenv/shims:$HOME/go/bin:$PATH"
if command -v go >/dev/null; then
	go install golang.org/x/tools/cmd/goimports@latest
else
	echo "warning: no go on PATH; gopls, delve and goimports will not install" >&2
fi
# nvm's node is on PATH only in interactive shells, and Mason needs npm for ts_ls, pyright and markdownlint
if [[ -d ~/.nvm/versions/node ]]; then
	node_bin=$(find ~/.nvm/versions/node -mindepth 2 -maxdepth 2 -name bin -type d | sort -V | tail -1)
	export PATH="$node_bin:$PATH"
fi
command -v npm >/dev/null || echo "warning: no npm on PATH; ts_ls, pyright and markdownlint will not install" >&2

if command -v stow >/dev/null; then
	# Without it stow folds all of ~/.config into a link to the repo, and gh, jj and the rest then write into the clone
	mkdir -p ~/.config
	# Box images ship a starter nvim config; stow would keep it, and this repo's config would never load
	if [[ -d ~/.config/nvim && ! -L ~/.config/nvim && ! -e ~/.config/nvim.box-default ]]; then
		mv ~/.config/nvim ~/.config/nvim.box-default
	fi
	# Same for the box's ~/.tmux.conf, except stow refuses outright and the run carries on without the tmux package
	if [[ -f ~/.tmux.conf && ! -L ~/.tmux.conf && ! -e ~/.tmux.conf.box-default ]]; then
		mv ~/.tmux.conf ~/.tmux.conf.box-default
	fi
	export STOW_FOLDERS=${STOW_FOLDERS:-nvim,tmux,bin,jj,claude} DOTFILES
	[[ ,$STOW_FOLDERS, == *,claude,* ]] && move_aside_stow_conflicts "$DOTFILES/claude"
	"$DOTFILES/stow-dotfiles.sh"
else
	echo "warning: no stow; dotfiles not linked" >&2
fi

# Sourced from the box's own .zshrc, which carries the box's setup and stays in place
zshrc_line="[[ -f \"$DOTFILES/linux/zshrc\" ]] && source \"$DOTFILES/linux/zshrc\""
touch ~/.zshrc
grep -qxF "$zshrc_line" ~/.zshrc || printf '\n%s\n' "$zshrc_line" >>~/.zshrc

jj_user=~/.config/jj/conf.d/user.toml
if [[ ! -f $jj_user ]]; then
	git_name=$(git config --global user.name || true)
	git_email=$(git config --global user.email || true)
	if [[ -n $git_name && -n $git_email ]]; then
		mkdir -p "$(dirname "$jj_user")"
		printf '[user]\nname = "%s"\nemail = "%s"\n' "$git_name" "$git_email" >"$jj_user"
	else
		echo "warning: no git user.name/user.email; create $jj_user with a [user] name and email" >&2
	fi
fi

# Boxes keep their own ~/.claude/settings.json, so install the plugin into it rather than generating the file
base="$DOTFILES/claude-settings/settings.base.json"
if command -v claude >/dev/null && command -v jq >/dev/null; then
	ce_source=$(jq -r '.extraKnownMarketplaces["compound-engineering-plugin"].source | "\(.repo)#\(.ref)"' "$base")
	claude plugin marketplace add "$ce_source" &&
		claude plugin install compound-engineering@compound-engineering-plugin ||
		echo "warning: compound-engineering plugin not installed" >&2
else
	echo "warning: no claude or jq on PATH; compound-engineering plugin not installed" >&2
fi

settings=~/.claude/settings.json
if command -v jq >/dev/null; then
	[[ -f $settings ]] || { mkdir -p ~/.claude && echo '{}' >"$settings"; }
	merged=$(jq --slurpfile base "$base" -f "$DOTFILES/claude-settings/merge-ce-sync-hooks.jq" "$settings") &&
		printf '%s\n' "$merged" >"$settings"
else
	echo "warning: no jq; ce-sync hooks not added to $settings" >&2
fi

# No jj-init-all here: dev boxes pull their own clones only on an attached branch, and jj detaches HEAD on its first new commit
nvim --headless '+Lazy! restore' '+MasonToolsInstallSync' +qa
