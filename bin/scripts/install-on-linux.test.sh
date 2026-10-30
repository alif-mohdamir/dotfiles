#!/bin/bash
# Tests for install-on-linux.sh's functions and the peon title script, run against a fake home.
#
#   bash bin/scripts/install-on-linux.test.sh
set -uo pipefail

dotfiles=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
current=

INSTALL_ON_LINUX_FUNCTIONS_ONLY=1 source "$dotfiles/install-on-linux.sh"
set +e

fail() {
	echo "FAIL [$current] $*"
	failures=$((failures + 1))
}

begin() {
	current=$1
	rm -rf "${tmp:?}"/case
	# Not "home": the stale-shim check would read a path ending in /home/.goenv as another user's home
	mkdir -p "$tmp/case/me"
	export HOME=$tmp/case/me
}

# A goenv or pyenv install whose rehash records the root it was given
fake_tool() {
	local tool=$1 root_var=$2
	mkdir -p "$HOME/.$tool/bin" "$HOME/.$tool/shims"
	cat >"$HOME/.$tool/bin/$tool" <<EOF
#!/bin/bash
echo "$tool \$* $root_var=\$$root_var" >>"$tmp/case/calls"
EOF
	chmod +x "$HOME/.$tool/bin/$tool"
}

shim() {
	printf '#!/usr/bin/env bash\nexec "%s/libexec/x" exec "$@"\n' "$2" >"$HOME/$1"
}

calls() { cat "$tmp/case/calls" 2>/dev/null; }

begin "a goenv shim naming another home triggers a goenv rehash under this home"
fake_tool goenv GOENV_ROOT
shim .goenv/shims/go /home/other/.goenv
shim .goenv/shims/gofmt /home/other/.goenv
out=$(repair_stale_shims 2>&1) || fail "exited non-zero"
[[ $(calls) == "goenv rehash GOENV_ROOT=$HOME/.goenv" ]] || fail "calls were '$(calls)'"
[[ $out == *"2 stale goenv shims"* ]] || fail "output was '$out'"

begin "shims naming this home trigger no rehash"
fake_tool goenv GOENV_ROOT
fake_tool pyenv PYENV_ROOT
shim .goenv/shims/go "$HOME/.goenv"
shim .pyenv/shims/python "$HOME/.pyenv"
out=$(repair_stale_shims 2>&1) || fail "exited non-zero"
[[ -z $(calls) ]] || fail "calls were '$(calls)'"
[[ -z $out ]] || fail "output was '$out'"

begin "with no goenv or pyenv the repair prints nothing"
out=$(repair_stale_shims 2>&1) || fail "exited non-zero"
[[ -z $out ]] || fail "output was '$out'"

begin "a stale pyenv shim triggers only the pyenv rehash"
fake_tool goenv GOENV_ROOT
fake_tool pyenv PYENV_ROOT
shim .goenv/shims/go "$HOME/.goenv"
shim .pyenv/shims/python /home/other/.pyenv
repair_stale_shims >/dev/null 2>&1 || fail "exited non-zero"
[[ $(calls) == "pyenv rehash PYENV_ROOT=$HOME/.pyenv" ]] || fail "calls were '$(calls)'"

stow_claude() {
	move_aside_stow_conflicts "$dotfiles/claude" 2>"$tmp/case/stderr" || fail "move-aside exited non-zero"
	# Its exit status is popd's, so the assertions below check the links instead
	DOTFILES=$dotfiles STOW_FOLDERS=claude "$dotfiles/stow-dotfiles.sh" >/dev/null 2>&1
}

begin "a real CLAUDE.md moves to .box-default and the package links in its place"
mkdir -p "$HOME/.claude"
echo box >"$HOME/.claude/CLAUDE.md"
stow_claude
[[ $(cat "$HOME/.claude/CLAUDE.md.box-default" 2>/dev/null) == box ]] || fail "backup missing or wrong"
[[ $(readlink -f "$HOME/.claude/CLAUDE.md") == "$dotfiles/claude/.claude/CLAUDE.md" ]] || fail "CLAUDE.md not linked into the package"
grep -q "warning: .*CLAUDE.md" "$tmp/case/stderr" || fail "no warning: '$(cat "$tmp/case/stderr")'"

begin "an existing .box-default is kept and the file moves to a timestamped backup"
mkdir -p "$HOME/.claude"
echo older >"$HOME/.claude/CLAUDE.md.box-default"
echo box >"$HOME/.claude/CLAUDE.md"
stow_claude
[[ $(cat "$HOME/.claude/CLAUDE.md.box-default") == older ]] || fail "existing backup overwritten"
stamped=("$HOME"/.claude/CLAUDE.md.box-default.*)
[[ ${#stamped[@]} == 1 && -f ${stamped[0]} && $(cat "${stamped[0]}") == box ]] || fail "no timestamped backup: ${stamped[*]}"
grep -q "warning: .*CLAUDE.md.box-default\." "$tmp/case/stderr" || fail "no warning: '$(cat "$tmp/case/stderr")'"
[[ -L $HOME/.claude/CLAUDE.md ]] || fail "CLAUDE.md not linked"

begin "a box-only skill survives and the package's skills link beside it"
mkdir -p "$HOME/.claude/skills/other-skill"
echo box >"$HOME/.claude/skills/other-skill/SKILL.md"
stow_claude
[[ -d $HOME/.claude/skills && ! -L $HOME/.claude/skills ]] || fail "skills is not a real directory"
[[ $(cat "$HOME/.claude/skills/other-skill/SKILL.md") == box ]] || fail "box skill lost"
[[ -L $HOME/.claude/skills/grill-me/SKILL.md ]] || fail "package skill not linked"

begin "settings.json is left as the box has it"
mkdir -p "$HOME/.claude"
echo '{"box":true}' >"$HOME/.claude/settings.json"
stow_claude
[[ -f $HOME/.claude/settings.json && ! -L $HOME/.claude/settings.json ]] || fail "settings.json replaced"
[[ $(cat "$HOME/.claude/settings.json") == '{"box":true}' ]] || fail "settings.json changed"
compgen -G "$HOME/.claude/settings.json.box-default*" >/dev/null && fail "settings.json moved aside"

title() { PEON_CWD=/src/myrepo bash "$dotfiles/claude-settings/peon-title.sh"; }

begin "the title names the box from the ce-sync config, then the directory"
mkdir -p "$HOME/.config/ce-sync"
printf 'CE_SYNC_PULL=true\nCE_SYNC_HOST=devbox\n' >"$HOME/.config/ce-sync/config"
[[ $(title) == "devbox myrepo" ]] || fail "title was '$(title)'"

begin "a quoted CE_SYNC_HOST loses its quotes"
mkdir -p "$HOME/.config/ce-sync"
echo 'CE_SYNC_HOST="devbox"' >"$HOME/.config/ce-sync/config"
[[ $(title) == "devbox myrepo" ]] || fail "title was '$(title)'"

begin "without the ce-sync config the title names the hostname"
[[ $(title) == "$(uname -n) myrepo" ]] || fail "title was '$(title)'"

begin "the title script reads the ce-sync config without running it"
mkdir -p "$HOME/.config/ce-sync"
cat >"$HOME/.config/ce-sync/config" <<EOF
\$(touch "$tmp/case/ran-line")
CE_SYNC_HOST=\$(touch "$tmp/case/ran-value")
EOF
title >/dev/null
[[ -e $tmp/case/ran-line || -e $tmp/case/ran-value ]] && fail "the config was executed"

settings_file() { cat "$HOME/.claude/settings.json"; }
record_file() { cat "$HOME/.claude/.box-settings-applied.json"; }

begin "an empty settings.json is merged as an empty object"
mkdir -p "$HOME/.claude"
: >"$HOME/.claude/settings.json"
merge_box_settings "$dotfiles" 2>/dev/null || fail "exited non-zero"
[[ $(jq -r '.env.PEON_PLATFORM' "$HOME/.claude/settings.json") == ssh ]] || fail "settings were '$(cat "$HOME/.claude/settings.json")'"

begin "a malformed settings.json is left byte-identical, with a warning"
mkdir -p "$HOME/.claude"
printf '{"box": tru' >"$HOME/.claude/settings.json"
merge_box_settings "$dotfiles" 2>"$tmp/case/stderr" || fail "exited non-zero"
[[ $(settings_file) == '{"box": tru' ]] || fail "settings.json changed: '$(settings_file)'"
[[ $(ls -A "$HOME/.claude") == settings.json ]] || fail "other files left in ~/.claude: $(ls -A "$HOME/.claude")"
grep -q "^warning: .*settings.json" "$tmp/case/stderr" || fail "no warning: '$(cat "$tmp/case/stderr")'"

begin "a second merge leaves settings.json and the record byte-identical"
mkdir -p "$HOME/.claude"
echo '{"apiKeyHelper": "box-helper", "effortLevel": "box-choice"}' >"$HOME/.claude/settings.json"
merge_box_settings "$dotfiles" 2>"$tmp/case/stderr" || fail "first merge exited non-zero"
[[ $(jq -r .apiKeyHelper "$HOME/.claude/settings.json") == box-helper ]] || fail "box key lost"
[[ $(jq -r .env.PEON_PLATFORM "$HOME/.claude/settings.json") == ssh ]] || fail "merge not applied"
grep -qx "warning: kept box value: effortLevel" "$tmp/case/stderr" || fail "kept key not reported: '$(cat "$tmp/case/stderr")'"
first_settings=$(settings_file) first_record=$(record_file)
merge_box_settings "$dotfiles" 2>/dev/null || fail "second merge exited non-zero"
[[ $(settings_file) == "$first_settings" ]] || fail "settings.json changed on the second run"
[[ $(record_file) == "$first_record" ]] || fail "record changed on the second run"

begin "a missing settings.json is created and merged"
merge_box_settings "$dotfiles" 2>/dev/null || fail "exited non-zero"
[[ $(jq -r .env.PEON_PLATFORM "$HOME/.claude/settings.json") == ssh ]] || fail "merge not applied: '$(settings_file)'"

begin "a symlinked settings.json is written through to its target"
mkdir -p "$HOME/.claude" "$tmp/case/elsewhere"
echo '{}' >"$tmp/case/elsewhere/settings.json"
ln -s "$tmp/case/elsewhere/settings.json" "$HOME/.claude/settings.json"
merge_box_settings "$dotfiles" 2>/dev/null || fail "exited non-zero"
[[ -L $HOME/.claude/settings.json ]] || fail "link replaced"
[[ $(jq -r .env.PEON_PLATFORM "$tmp/case/elsewhere/settings.json") == ssh ]] || fail "target not merged"

peon_dir() { echo "$HOME/.claude/hooks/peon-ping"; }

# A peon source whose install.sh records its arguments and SSH_CONNECTION, then writes a fresh install
fetch_peon_source() {
	mkdir -p "$1"
	cat >"$1/install.sh" <<'EOF'
#!/bin/bash
echo "install $* SSH_CONNECTION=${SSH_CONNECTION:-}" >>"$HOME/../calls"
dir=$HOME/.claude/hooks/peon-ping
mkdir -p "$dir"
echo '{"notification_title_script": ""}' >"$dir/config.json"
echo 2.37.0 >"$dir/VERSION"
touch "$dir/peon.sh"
EOF
}

begin "peon at the pinned version is not reinstalled"
mkdir -p "$(peon_dir)"
echo 2.37.0 >"$(peon_dir)/.dotfiles-installed"
install_peon_ping "$tmp/case/work" || fail "exited non-zero"
[[ -z $(calls) ]] || fail "calls were '$(calls)'"

begin "peon installs with no rc edits and an SSH platform when no SSH variables are set"
unset SSH_CONNECTION SSH_CLIENT
install_peon_ping "$tmp/case/work" || fail "exited non-zero"
[[ $(calls) == "install --no-rc SSH_CONNECTION="?* ]] || fail "calls were '$(calls)'"
[[ -f $(peon_dir)/peon.sh ]] || fail "peon.sh missing"

begin "an install that failed after writing VERSION is retried"
mkdir -p "$(peon_dir)"
echo 2.37.0 >"$(peon_dir)/VERSION"
install_peon_ping "$tmp/case/work" || fail "exited non-zero"
[[ -n $(calls) ]] || fail "install.sh not run"
[[ $(cat "$(peon_dir)/.dotfiles-installed") == 2.37.0 ]] || fail "finished install not marked"

begin "an older peon's config survives the reinstall"
mkdir -p "$(peon_dir)"
echo 2.30.0 >"$(peon_dir)/VERSION"
echo '{"volume": 0.3, "notification_title_script": "mine"}' >"$(peon_dir)/config.json"
install_peon_ping "$tmp/case/work" || fail "exited non-zero"
[[ -n $(calls) ]] || fail "install.sh not run"
[[ $(cat "$(peon_dir)/config.json") == '{"volume": 0.3, "notification_title_script": "mine"}' ]] || fail "config replaced: '$(cat "$(peon_dir)/config.json")'"

begin "an empty notification_title_script is pointed at the title script"
mkdir -p "$(peon_dir)"
echo '{"volume": 0.3, "notification_title_script": ""}' >"$(peon_dir)/config.json"
fill_peon_title_script "$dotfiles" || fail "exited non-zero"
[[ $(jq -r .notification_title_script "$(peon_dir)/config.json") == "bash $dotfiles/claude-settings/peon-title.sh" ]] || fail "config was '$(cat "$(peon_dir)/config.json")'"
[[ $(jq -r .volume "$(peon_dir)/config.json") == 0.3 ]] || fail "other keys lost"

begin "a set notification_title_script is left as it was"
mkdir -p "$(peon_dir)"
echo '{"notification_title_script": "echo mine"}' >"$(peon_dir)/config.json"
fill_peon_title_script "$dotfiles" || fail "exited non-zero"
[[ $(cat "$(peon_dir)/config.json") == '{"notification_title_script": "echo mine"}' ]] || fail "config changed: '$(cat "$(peon_dir)/config.json")'"

if ((failures)); then
	echo "$failures failed"
	exit 1
fi
echo "all passed"
