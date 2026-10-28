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
[[ $(hook hook-start "$tmp/case/a") == *CE_SYNC_PUT* ]] || fail "hook-start did not warn"
[[ -z $(hook hook-stop "$tmp/case/a") ]] || fail "hook-stop warned again"

begin "a hook that cannot reach the store says so on screen"
new_repo "$tmp/case/a"
cat >"$tmp/config" <<'EOF'
CE_SYNC_PULL='exit 4'
CE_SYNC_PUT='exit 4'
CE_SYNC_RM='exit 4'
EOF
out=$(hook hook-start "$tmp/case/a") || fail "hook-start exited $?"
[[ $(jq -r .systemMessage <<<"$out" 2>/dev/null) == *"could not reach"* ]] || fail "expected one systemMessage line, got '$out'"
[[ $(wc -l <<<"$out") -eq 1 ]] || fail "expected one line, got '$out'"

begin "a conflict and an override in one sync make one message"
two_machines
echo v0 >"$local_a/plans/p.md"
echo v0 >"$local_a/solutions/x.md"
on a
on b
echo from-a >"$local_a/plans/p.md"
rm "$local_a/solutions/x.md"
on a
echo from-b >"$local_b/plans/p.md"
echo edited >"$local_b/solutions/x.md"
out=$(CE_SYNC_HOST=b hook hook-start "$tmp/case/b")
msg=$(jq -r .systemMessage <<<"$out" 2>/dev/null)
[[ $msg == *p.md* && $msg == *x.md* && $(wc -l <<<"$out") -eq 1 ]] || fail "expected one message naming both files, got '$out'"

begin "a clean sync prints nothing"
two_machines
echo a >"$local_a/solutions/a.md"
out=$(hook hook-start "$tmp/case/a")
[[ -z $out ]] || fail "printed '$out'"

begin "a sync already running in the worktree makes a hook skip"
two_machines
echo a >"$local_a/solutions/a.md"
mkdir "$tmp/case/a/.git/ce-sync.lock"
hook hook-start "$tmp/case/a" >/dev/null || fail "hook-start exited $?"
assert_no_file "$tmp/calls"
touch -t 202001010000 "$tmp/case/a/.git/ce-sync.lock"
hook hook-start "$tmp/case/a" >/dev/null
assert_content "$store/solutions/a.md" a
assert_no_file "$tmp/case/a/.git/ce-sync.lock"

begin "hook-stop with nothing changed locally does not call the store"
two_machines
echo a >"$local_a/solutions/a.md"
hook hook-start "$tmp/case/a" >/dev/null
rm -f "$tmp/calls"
hook hook-stop "$tmp/case/a" >/dev/null
assert_no_file "$tmp/calls"
echo b >"$local_a/solutions/a.md"
hook hook-stop "$tmp/case/a" >/dev/null
assert_content "$store/solutions/a.md" b

begin "the box merge replaces old ce-sync hooks and keeps the box's own after them"
filter=$(dirname "$script")/../../claude-settings/merge-ce-sync-hooks.jq
base=$(dirname "$script")/../../claude-settings/settings.base.json
cat >"$tmp/case/settings.json" <<'EOF'
{"hooks": {"Stop": [
  {"matcher": "", "hooks": [{"type": "command", "command": "~/scripts/ce-sync hook-stop", "timeout": 120, "async": true}]},
  {"matcher": "", "hooks": [{"type": "command", "command": "box-status stop"}]}
]}, "other": 1}
EOF
merged=$(jq --slurpfile base "$base" -f "$filter" "$tmp/case/settings.json") || fail "merge failed"
stop=$(jq -c '[.hooks.Stop[].hooks[].command]' <<<"$merged")
[[ $stop == '["~/scripts/ce-sync hook-stop","box-status stop"]' ]] || fail "Stop hooks: $stop"
[[ $(jq '[.hooks.Stop[].hooks[] | select(.async)] | length' <<<"$merged") == 0 ]] || fail "Stop still async"
[[ $(jq -c '[.hooks.SessionEnd[].hooks[].command]' <<<"$merged") == '["~/scripts/ce-sync hook-stop"]' ]] ||
	fail "SessionEnd hooks: $(jq -c .hooks.SessionEnd <<<"$merged")"
[[ $(jq -c '[.hooks.SessionStart[].hooks[].command]' <<<"$merged") == '["~/scripts/ce-sync hook-start"]' ]] ||
	fail "SessionStart hooks: $(jq -c .hooks.SessionStart <<<"$merged")"
[[ $(jq .other <<<"$merged") == 1 ]] || fail "lost other settings"

begin "a store command that reads stdin does not swallow the file list"
two_machines
sed -i.bak "s|^CE_SYNC_PUT='|CE_SYNC_PUT='cat >/dev/null; |" "$tmp/config"
for n in 1 2 3 4; do echo "$n" >"$local_a/solutions/f$n.md"; done
on a
for n in 1 2 3 4; do assert_content "$store/solutions/f$n.md" "$n"; done

bash5=$(command -v /opt/homebrew/bin/bash /usr/bin/bash 2>/dev/null | while read -r b; do "$b" -c 'shopt -q patsub_replacement' 2>/dev/null && echo "$b" && break; done)
if [[ -n $bash5 ]]; then
	begin "a path with & stays quoted under bash 5.2 and later"
	two_machines
	echo amp >"$local_a/solutions/a&b.md"
	(cd "$tmp/case/a" && CE_SYNC_CONFIG=$tmp/config "$bash5" "$script" pull 2>/dev/null)
	assert_content "$store/solutions/a&b.md" amp
fi

begin "a second conflict on one file keeps the first conflict copy"
two_machines
echo v0 >"$local_a/plans/p.md"
on a
on b
for round in 1 2; do
	echo "a$round" >"$local_a/plans/p.md"
	echo "b$round" >"$local_b/plans/p.md"
	on a
	on b
done
on a
assert_content "$store/plans/p.conflict-b.md" b1
assert_content "$store/plans/p.conflict-b-2.md" b2
assert_content "$local_a/plans/p.conflict-b.md" b1
[[ $(grep -c 'p.conflict-b.md$' "$tmp/case/b/.git/ce-sync-record") == 1 ]] || fail "record lists the first copy more than once"

begin "a conflict copy keeps a dotted folder name intact"
two_machines
mkdir -p "$local_a/solutions/v1.2"
echo v0 >"$local_a/solutions/v1.2/notes"
on a
on b
echo from-a >"$local_a/solutions/v1.2/notes"
echo from-b >"$local_b/solutions/v1.2/notes"
on a
on b
assert_content "$store/solutions/v1.2/notes.conflict-b" from-b

begin "the box merge keeps hooks without a command and lookalike commands"
cat >"$tmp/case/settings.json" <<'EOF'
{"hooks": {"Stop": [
  {"matcher": "", "hooks": [{"type": "prompt", "prompt": "check"}]},
  {"matcher": "", "hooks": [{"type": "command", "command": "/x/service-sync-notify"}]}
]}}
EOF
merged=$(jq --slurpfile base "$base" -f "$filter" "$tmp/case/settings.json") || fail "merge failed"
[[ $(jq -c '[.hooks.Stop[].hooks[] | .command // .type]' <<<"$merged") == '["~/scripts/ce-sync hook-stop","prompt","/x/service-sync-notify"]' ]] ||
	fail "Stop hooks: $(jq -c .hooks.Stop <<<"$merged")"
[[ $(jq --slurpfile base "$base" -f "$filter" <<<"$merged") == "$(jq . <<<"$merged")" ]] || fail "merge is not idempotent"

begin "a wiped .ce/ deletes nothing from the store"
two_machines
echo one >"$local_a/solutions/one.md"
echo two >"$local_a/plans/two.md"
on a
on b
rm -rf "$local_a"
mkdir -p "$local_a/solutions"
echo new >"$local_a/solutions/new.md"
on a
assert_content "$store/solutions/one.md" one
assert_content "$store/plans/two.md" two
grep -q "ce-sync-record" "$tmp/stderr-a" || fail "warning does not say how to start over: $(cat "$tmp/stderr-a")"
on b
assert_content "$local_b/solutions/one.md" one
rm "$tmp/case/a/.git/ce-sync-record"
on a
assert_content "$local_a/solutions/one.md" one
assert_content "$store/solutions/new.md" new

begin "deleting some synced files still propagates"
two_machines
echo one >"$local_a/solutions/one.md"
echo two >"$local_a/solutions/two.md"
on a
rm "$local_a/solutions/one.md"
on a
assert_no_file "$store/solutions/one.md"
assert_content "$store/solutions/two.md" two

if ((failures)); then
	echo "$failures failure(s)"
	exit 1
fi
echo "all passed"
