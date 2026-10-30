#!/bin/bash
set -euo pipefail

# Box images are built under another user's home, and their goenv and pyenv shims still exec that home's tools
repair_stale_shims() {
	local tool root var shim stale
	for tool in goenv pyenv; do
		root=$HOME/.$tool
		[[ -d $root/shims ]] || continue
		stale=0
		while IFS= read -r shim; do
			if grep -o '/home/[^/"[:space:]]*' "$shim" | grep -qvxF "$HOME"; then
				stale=$((stale + 1))
			fi
		done < <(grep -rlF /home/ "$root/shims" || true)
		((stale)) || continue
		var=GOENV_ROOT
		[[ $tool == pyenv ]] && var=PYENV_ROOT
		if env "$var=$root" "$root/bin/$tool" rehash; then
			echo "repaired $stale stale $tool shims"
		else
			echo "warning: $tool rehash failed" >&2
		fi
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

PEON_VERSION=2.37.0

fetch_peon_source() {
	mkdir -p "$1" &&
		curl -fsSL "https://github.com/PeonPing/peon-ping/archive/refs/tags/v$PEON_VERSION.tar.gz" | tar -xz -C "$1" --strip-components=1
}

install_peon_ping() {
	local scratch=$1
	local work=$scratch/peon-ping dir=$HOME/.claude/hooks/peon-ping status=0
	# peon writes its VERSION early in its install, so only this marker proves a finished install
	[[ $(cat "$dir/.dotfiles-installed" 2>/dev/null) == "$PEON_VERSION" ]] && return 0
	fetch_peon_source "$work/src" || return 1
	if [[ -f $dir/config.json ]]; then cp "$dir/config.json" "$work/config.json" || return 1; fi
	# install.sh picks its platform from SSH variables, and on a box its linux branch exits for want of an audio player
	SSH_CONNECTION=${SSH_CONNECTION:-127.0.0.1 0 127.0.0.1 0} bash "$work/src/install.sh" --no-rc || status=$?
	if [[ -f $work/config.json ]] && ! cmp -s "$work/config.json" "$dir/config.json"; then
		cp "$work/config.json" "$dir/config.json" || return 1
	fi
	((status)) || echo "$PEON_VERSION" >"$dir/.dotfiles-installed" || status=$?
	return "$status"
}

fill_peon_title_script() {
	local dotfiles=$1 config=$HOME/.claude/hooks/peon-ping/config.json script new
	script="bash $(printf %q "$dotfiles/claude-settings/peon-title.sh")"
	[[ -n $(jq -r '.notification_title_script // "" | gsub("\\s"; "")' "$config") ]] && return 0
	new=$(mktemp "$config.XXXXXX") || return 1
	if ! { jq --arg s "$script" '.notification_title_script = $s' "$config" >"$new" && mv "$new" "$config"; }; then
		rm -f "$new"
		return 1
	fi
}

# Other writers of settings.json follow a symlink there, so the merge writes through it to the target
merge_box_settings() {
	local dotfiles=$1 link=$HOME/.claude/settings.json record=$HOME/.claude/.box-settings-applied.json previous settings out new_settings='' new_record=''
	mkdir -p "$HOME/.claude" || return 1
	[[ -s $link ]] || echo '{}' >"$link" || return 1
	settings=$(readlink -f "$link") || return 1
	# An empty slurp gives the filter a null record, which it treats as a first run
	if ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
		echo "warning: could not merge box settings; $settings and $record left as they were" >&2
		return 0
	fi
	previous=/dev/null
	jq -e 'type == "object"' "$record" >/dev/null 2>&1 && previous=$record
	out=$(mktemp "$HOME/.claude/.box-settings-merge.XXXXXX") || return 1
	if ! jq --slurpfile base "$dotfiles/claude-settings/settings.base.json" --slurpfile record "$previous" \
		-f "$dotfiles/claude-settings/merge-box-settings.jq" "$settings" >"$out"; then
		rm -f "$out"
		echo "warning: could not merge box settings; $settings and $record left as they were" >&2
		return 0
	fi
	if ! { new_settings=$(mktemp "$(dirname "$settings")/.settings.json.XXXXXX") &&
		new_record=$(mktemp "$record.XXXXXX") &&
		jq .settings "$out" >"$new_settings" &&
		jq .record "$out" >"$new_record" &&
		mv "$new_settings" "$settings" &&
		mv "$new_record" "$record"; }; then
		rm -f "$out" "$new_settings" "$new_record"
		return 1
	fi
	jq -r '.kept[] | "warning: kept box value: \(.)"' "$out" >&2
	rm -f "$out"
}

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
	if [[ ,$STOW_FOLDERS, == *,claude,* ]]; then
		move_aside_stow_conflicts "$DOTFILES/claude" || echo "warning: could not move files that block the claude package" >&2
	fi
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

# Before the merge, which puts back the hook order the peon install changes
install_peon_ping "$tmp" || echo "warning: peon-ping $PEON_VERSION not installed" >&2
if command -v jq >/dev/null; then
	fill_peon_title_script "$DOTFILES" || echo "warning: peon notification_title_script not set" >&2
	merge_box_settings "$DOTFILES" || echo "warning: box settings merge failed" >&2
else
	echo "warning: no jq; peon title and box settings not set up" >&2
fi

# No jj-init-all here: dev boxes pull their own clones only on an attached branch, and jj detaches HEAD on its first new commit
nvim --headless '+Lazy! restore' '+MasonToolsInstallSync' +qa
