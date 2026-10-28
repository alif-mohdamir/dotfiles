#!/bin/bash
# Tests for ce-sync, run against throwaway repos and a store made of local directories.
#
#   bash bin/scripts/ce-sync.test.sh
set -uo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/ce-sync
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
current=

fail() {
	echo "FAIL [$current] $*"
	failures=$((failures + 1))
}

assert_file() { [[ -f $1 ]] || fail "missing $1"; }
assert_no_file() { [[ ! -e $1 ]] || fail "unexpected $1"; }
assert_content() { [[ -f $1 && $(cat "$1") == "$2" ]] || fail "$1 should hold '$2', has '$(cat "$1" 2>/dev/null)'"; }

# A clone of https://example.com/me/proj.git, with one commit so worktrees can be added
new_repo() {
	git init -q "$1"
	git -C "$1" remote add origin https://example.com/me/proj.git
	git -C "$1" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m init
}

# The store is a directory per repo. Like the real one, a download of a folder with no files fails.
write_config() {
	local store=$1
	mkdir -p "$store"
	cat >"$tmp/config" <<EOF
CE_SYNC_PULL='echo pull >>$tmp/calls; [ -n "\$(find $store/%r -type f 2>/dev/null)" ] || exit 3; cp -R $store/%r/. %d/'
CE_SYNC_PUSH='echo push >>$tmp/calls; mkdir -p $store/%r && cp -R %d/. $store/%r/'
CE_SYNC_PUT='echo put >>$tmp/calls; mkdir -p "\$(dirname $store/%r/%p)" && cp %f $store/%r/%p'
CE_SYNC_RM='echo rm >>$tmp/calls; rm -f $store/%r/%p'
CE_SYNC_HOST=${2:-testhost}
EOF
}

# hook-start or hook-stop as Claude runs them, with the session's cwd in the JSON on stdin
hook() {
	printf '{"cwd":"%s"}' "$2" | CE_SYNC_CONFIG=$tmp/config "$script" "$1"
}

sync_in() {
	(cd "$1" && CE_SYNC_CONFIG=$tmp/config "$script" pull)
}

begin() {
	current=$1
	rm -rf "${tmp:?}"/case
	mkdir -p "$tmp/case"
	rm -f "$tmp/calls"
}

begin "init sets up a repo with no CE config"
new_repo "$tmp/case/a"
write_config "$tmp/case/store"
hook hook-start "$tmp/case/a" >/dev/null 2>&1
assert_content "$tmp/case/a/.compound-engineering/config.yaml" "docs_root: .ce"
grep -qxF /.ce/ "$tmp/case/a/.git/info/exclude" || fail ".ce/ not excluded"
grep -qxF /.compound-engineering/ "$tmp/case/a/.git/info/exclude" || fail ".compound-engineering/ not excluded"

begin "a repo that commits its CE config is left alone"
new_repo "$tmp/case/a"
mkdir -p "$tmp/case/a/.compound-engineering"
echo "docs_root: docs" >"$tmp/case/a/.compound-engineering/config.yaml"
git -C "$tmp/case/a" add .compound-engineering/config.yaml
write_config "$tmp/case/store"
out=$(hook hook-start "$tmp/case/a")
[[ $? == 0 && -z $out ]] || fail "hook should exit 0 silently, printed '$out'"
assert_no_file "$tmp/case/a/.ce"
assert_no_file "$tmp/calls"

begin "an untracked config naming another root is left alone"
new_repo "$tmp/case/a"
mkdir -p "$tmp/case/a/.compound-engineering"
echo "docs_root: notes" >"$tmp/case/a/.compound-engineering/config.yaml"
write_config "$tmp/case/store"
hook hook-start "$tmp/case/a" >/dev/null 2>&1
assert_no_file "$tmp/case/a/.ce"
assert_no_file "$tmp/calls"

begin "every worktree of a clone syncs with the folder named after origin"
new_repo "$tmp/case/a"
git -C "$tmp/case/a" worktree add -q "$tmp/case/a-wt" 2>/dev/null
write_config "$tmp/case/store"
mkdir -p "$tmp/case/a/.ce/solutions" "$tmp/case/a-wt/.ce/plans"
echo one >"$tmp/case/a/.ce/solutions/one.md"
echo two >"$tmp/case/a-wt/.ce/plans/two.md"
sync_in "$tmp/case/a" 2>/dev/null
sync_in "$tmp/case/a-wt" 2>/dev/null
assert_content "$tmp/case/store/proj/solutions/one.md" one
assert_content "$tmp/case/store/proj/plans/two.md" two

begin "without a config file every subcommand does nothing"
new_repo "$tmp/case/a"
for sub in pull push hook-start hook-stop; do
	out=$(cd "$tmp/case/a" && printf '{}' | CE_SYNC_CONFIG=$tmp/missing "$script" $sub 2>&1)
	[[ $? == 0 && -z $out ]] || fail "$sub should exit 0 silently, printed '$out'"
done
assert_no_file "$tmp/case/a/.ce"

begin "hooks exit 0 when the store fails"
new_repo "$tmp/case/a"
cat >"$tmp/config" <<'EOF'
CE_SYNC_PULL='exit 1'
CE_SYNC_PUSH='exit 1'
CE_SYNC_PUT='exit 1'
CE_SYNC_RM='exit 1'
EOF
mkdir -p "$tmp/case/a/.ce/solutions"
echo x >"$tmp/case/a/.ce/solutions/x.md"
hook hook-start "$tmp/case/a" >/dev/null 2>&1 || fail "hook-start exited $?"
echo y >"$tmp/case/a/.ce/solutions/x.md"
hook hook-stop "$tmp/case/a" >/dev/null 2>&1 || fail "hook-stop exited $?"

if ((failures)); then
	echo "$failures failure(s)"
	exit 1
fi
echo "all passed"
