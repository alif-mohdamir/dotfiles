#!/bin/bash
# Tests for generate.sh and claude/.claude/hooks/settings-stale.sh, run against a fake home.
#
#   bash claude-settings/generate.test.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
hooks=$here/../claude/.claude/hooks
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
current=

fail() {
	echo "FAIL [$current] $*"
	failures=$((failures + 1))
}

begin() {
	current=$1
	rm -rf "${tmp:?}"/home
	mkdir -p "$tmp/home/.claude/hooks"
	export HOME=$tmp/home
}

link_hooks() {
	local h
	for h in "$hooks"/*.sh; do ln -s "$h" "$HOME/.claude/hooks/$(basename "$h")"; done
}

generate() { bash "$here/generate.sh" "$@" 2>"$tmp/stderr"; }
# Through its link, as Claude runs it
stale_hook() { "$HOME/.claude/hooks/settings-stale.sh" </dev/null; }

begin "an unlinked hook stops the write, even with --force"
generate >/dev/null && fail "exited zero"
generate --force >/dev/null && fail "exited zero with --force"
[[ -e $HOME/.claude/settings.json ]] && fail "settings.json was written"
grep -q "publish-gate.sh" "$tmp/stderr" || fail "stderr did not name the hook: '$(cat "$tmp/stderr")'"

begin "--check names unlinked hooks and writes nothing"
out=$(generate --check) && fail "exited zero"
[[ $out == "hooks not linked into ~/.claude/hooks:"*publish-gate.sh* ]] || fail "printed '$out'"
[[ -z $(ls -A "$HOME/.claude" | grep -v '^hooks$') ]] || fail "wrote into ~/.claude: $(ls -A "$HOME/.claude")"

begin "--check is quiet after a generate and speaks up when a source changes"
link_hooks
out=$(generate --check) && fail "exited zero before the first generate"
[[ $out == *"is behind"* ]] || fail "printed '$out' before the first generate"
generate >/dev/null || fail "generate failed: $(cat "$tmp/stderr")"
out=$(generate --check) || fail "exited non-zero after a generate: '$out'"
[[ -z $out ]] || fail "printed '$out' after a generate"
echo '{"theme": "machine-choice"}' >"$HOME/.claude/settings.machine.json"
out=$(generate --check) && fail "exited zero after the machine file changed"
[[ $out == *"is behind"* ]] || fail "printed '$out' after the machine file changed"

begin "--check ignores an edit made to the live settings.json"
link_hooks
generate >/dev/null || fail "generate failed: $(cat "$tmp/stderr")"
jq '.model = "picked-in-session"' "$HOME/.claude/settings.json" >"$tmp/edited" && cp "$tmp/edited" "$HOME/.claude/settings.json"
generate --check >/dev/null || fail "reported a local edit as a stale base"

if [[ $(uname -s) != Linux ]]; then
	begin "the hook warns through systemMessage only while settings are behind"
	link_hooks
	msg=$(stale_hook | jq -r .systemMessage)
	[[ $msg == "Claude settings are stale: "*"is behind"*"/install.sh" ]] || fail "printed '$msg' before a generate"
	generate >/dev/null || fail "generate failed: $(cat "$tmp/stderr")"
	[[ -z $(stale_hook) ]] || fail "printed '$(stale_hook)' after a generate"
fi

if ((failures)); then
	echo "$failures failed"
	exit 1
fi
echo "all passed"
