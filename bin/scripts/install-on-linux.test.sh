#!/bin/bash
# Tests for install-on-linux.sh's shim repair and claude move-aside, run against a fake home.
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

if ((failures)); then
	echo "$failures failed"
	exit 1
fi
echo "all passed"
