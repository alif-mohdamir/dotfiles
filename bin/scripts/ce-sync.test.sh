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
CE_SYNC_HOST=\${CE_SYNC_HOST:-testhost}
EOF
}

# hook-start or hook-stop as Claude runs them, with the session's cwd in the JSON on stdin
hook() {
	printf '{"cwd":"%s"}' "$2" | CE_SYNC_CONFIG=$tmp/config "$script" "$1"
}

sync_in() {
	(cd "$1" && CE_SYNC_CONFIG=$tmp/config "$script" pull)
}

# Two clones of one repo on different machines, sharing the store at $tmp/case/store
two_machines() {
	new_repo "$tmp/case/a"
	new_repo "$tmp/case/b"
	write_config "$tmp/case/store"
	mkdir -p "$tmp/case/a/.ce/solutions" "$tmp/case/a/.ce/plans" "$tmp/case/b/.ce"
}

on() {
	local host=$1 dir=$tmp/case/$1
	(cd "$dir" && CE_SYNC_HOST=$host CE_SYNC_CONFIG=$tmp/config "$script" pull 2>"$tmp/stderr-$host")
}

store=$tmp/case/store/proj
local_a=$tmp/case/a/.ce
local_b=$tmp/case/b/.ce

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

begin "a new file on one machine reaches the other"
two_machines
echo learned >"$local_a/solutions/new.md"
on a
on b
assert_content "$local_b/solutions/new.md" learned

begin "both machines edit one plan, so both versions survive"
two_machines
echo v0 >"$local_a/plans/p.md"
on a
on b
echo from-a >"$local_a/plans/p.md"
echo from-b >"$local_b/plans/p.md"
on a
on b
on a
assert_content "$store/plans/p.md" from-a
assert_content "$store/plans/p.conflict-b.md" from-b
for d in "$local_a" "$local_b"; do
	assert_content "$d/plans/p.md" from-a
	assert_content "$d/plans/p.conflict-b.md" from-b
done
grep -q "p.md" "$tmp/stderr-b" || fail "b reported no merge notice: $(cat "$tmp/stderr-b")"

begin "a delete on one machine reaches the store and the other machine"
two_machines
echo stale >"$local_a/solutions/old.md"
on a
on b
rm "$local_a/solutions/old.md"
on a
assert_no_file "$store/solutions/old.md"
on b
assert_no_file "$local_b/solutions/old.md"

for order in "a b" "b a"; do
	begin "an edit beats a concurrent delete, syncing $order"
	two_machines
	echo v0 >"$local_a/solutions/x.md"
	on a
	on b
	rm "$local_a/solutions/x.md"
	echo edited >"$local_b/solutions/x.md"
	for h in $order; do on "$h"; done
	grep -q "x.md" "$tmp/stderr-a" "$tmp/stderr-b" || fail "no override notice"
	for h in $order; do on "$h"; done
	assert_content "$store/solutions/x.md" edited
	assert_content "$local_a/solutions/x.md" edited
	assert_content "$local_b/solutions/x.md" edited
done

begin "a fresh worktree pulls everything and deletes nothing"
two_machines
echo one >"$local_a/solutions/one.md"
echo two >"$local_a/plans/two.md"
on a
on b
assert_content "$local_b/solutions/one.md" one
assert_content "$local_b/plans/two.md" two
assert_file "$store/solutions/one.md"
assert_file "$store/plans/two.md"

begin "only solutions/ and plans/ sync"
two_machines
mkdir -p "$local_a/brainstorms" "$store/other"
echo idea >"$local_a/brainstorms/idea.md"
echo theirs >"$store/other/keep.md"
on a
on b
assert_no_file "$store/brainstorms/idea.md"
assert_no_file "$local_b/other/keep.md"
assert_content "$store/other/keep.md" theirs

begin "an unreachable store changes nothing once the record has files"
two_machines
echo kept >"$local_a/solutions/k.md"
on a
mv "$tmp/case/store" "$tmp/case/store-away"
echo changed >"$local_a/solutions/k.md"
on a
assert_content "$local_a/solutions/k.md" changed
assert_content "$tmp/case/store-away/proj/solutions/k.md" kept
[[ -s $tmp/stderr-a ]] || fail "no warning"
mv "$tmp/case/store-away" "$tmp/case/store"
rm "$store/.ce-sync"
on a
assert_content "$store/solutions/k.md" kept
[[ -s $tmp/stderr-a ]] || fail "no warning without the marker"

begin "deleting the last file still reaches the other machine"
two_machines
echo only >"$local_a/solutions/only.md"
on a
on b
rm "$local_a/solutions/only.md"
on a
on b
assert_no_file "$local_b/solutions/only.md"
[[ ! -s $tmp/stderr-b ]] || fail "unexpected warning: $(cat "$tmp/stderr-b")"

begin "a first sync puts the marker and downloads again before pushing"
two_machines
echo first >"$local_a/solutions/f.md"
on a
assert_file "$store/.ce-sync"
assert_content "$store/solutions/f.md" first
[[ $(head -1 "$tmp/calls") == pull && $(sed -n 2p "$tmp/calls") == put && $(sed -n 3p "$tmp/calls") == pull ]] ||
	fail "expected pull, put, pull first; got $(tr '\n' ' ' <"$tmp/calls")"
assert_no_file "$local_a/.ce-sync"

begin "a first sync pushes nothing if the marker never shows up"
two_machines
sed -i.bak "s|^CE_SYNC_PUT=.*|CE_SYNC_PUT='echo put >>$tmp/calls'|" "$tmp/config"
echo first >"$local_a/solutions/f.md"
on a
assert_no_file "$store/solutions/f.md"
[[ $(grep -c put "$tmp/calls") == 1 ]] || fail "expected only the marker put"

begin "the marker is never deleted"
two_machines
echo a >"$local_a/solutions/a.md"
on a
rm "$local_a/solutions/a.md"
on a
assert_file "$store/.ce-sync"

begin "a failed put is retried at the next sync"
two_machines
cp "$tmp/config" "$tmp/config.good"
sed -i.bak "s|^CE_SYNC_PUT='|CE_SYNC_PUT='case %p in *bad*) exit 1;; esac; |" "$tmp/config"
echo good >"$local_a/solutions/good.md"
echo bad >"$local_a/solutions/bad.md"
on a
assert_file "$store/solutions/good.md"
assert_no_file "$store/solutions/bad.md"
cp "$tmp/config.good" "$tmp/config"
on a
assert_content "$store/solutions/bad.md" bad

begin "a file git tracks is never synced"
two_machines
echo mine >"$local_a/solutions/t.md"
git -C "$tmp/case/a" add -f .ce/solutions/t.md
mkdir -p "$store/solutions"
echo theirs >"$store/solutions/t.md"
echo marker >"$store/.ce-sync"
on a
assert_content "$local_a/solutions/t.md" mine
assert_content "$store/solutions/t.md" theirs

begin "a config without per-file commands changes nothing"
two_machines
grep -v -e '^CE_SYNC_PUT=' -e '^CE_SYNC_RM=' "$tmp/config" >"$tmp/config.old"
mv "$tmp/config.old" "$tmp/config"
echo x >"$local_a/solutions/x.md"
on a
assert_no_file "$tmp/case/store/proj"
grep -q -i config "$tmp/stderr-a" || fail "no config warning: $(cat "$tmp/stderr-a")"

if ((failures)); then
	echo "$failures failure(s)"
	exit 1
fi
echo "all passed"
