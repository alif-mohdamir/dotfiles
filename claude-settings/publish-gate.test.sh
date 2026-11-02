#!/bin/bash
# Tests for claude/.claude/hooks/publish-gate.sh, with gh stubbed and git and jj wrapped so nothing is pushed.
#
#   bash claude-settings/publish-gate.test.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
hook=$here/../claude/.claude/hooks/publish-gate.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
current=
real_git=$(command -v git)
real_jj=$(command -v jj || true)

fail() {
	echo "FAIL [$current] $*"
	failures=$((failures + 1))
}

stubs=$tmp/stubs
state=$tmp/state
mkdir -p "$stubs"

# Answers from files in $state: viewer, default, prs/<branch> ("<number> <author>" lines), pr-<number>
# (author), current-pr (number), and gh-fail or unknown-repo to simulate a failed lookup.
cat >"$stubs/gh" <<'EOF'
#!/bin/bash
echo "gh $*" >>"$STATE/calls"
[[ -e $STATE/gh-fail ]] && { echo "error connecting to api.github.com" >&2; exit 1; }
case "$1 $2" in
"api user") cat "$STATE/viewer" ;;
"api graphql")
	head= owner= name=
	while (($#)); do
		case $1 in -f) case $2 in head=*) head=${2#head=} ;; owner=*) owner=${2#owner=} ;; name=*) name=${2#name=} ;; esac; shift ;; esac
		shift
	done
	[[ -e $STATE/unknown-repo ]] && { echo '{"data":{"viewer":{"login":"me"},"repository":null}}'; exit 0; }
	prs=$( (cat "$STATE/prs/$head" 2>/dev/null || true) | jq -R 'split(" ") | {number: (.[0] | tonumber), author: {login: .[1]}}' | jq -s .)
	jq -n --arg me "$(cat "$STATE/viewer")" --arg d "$(cat "$STATE/default")" --argjson prs "$prs" \
		'{data: {viewer: {login: $me}, repository: {defaultBranchRef: {name: $d}, pullRequests: {nodes: $prs}}}}'
	;;
"pr view")
	n=$3
	[[ $n == -* || -z $n ]] && n=$(cat "$STATE/current-pr")
	[[ -e $STATE/pr-$n ]] || { echo "no pull requests found" >&2; exit 1; }
	echo "$n $(cat "$STATE/pr-$n")"
	;;
*) echo "unexpected gh $*" >&2; exit 1 ;;
esac
EOF
cat >"$stubs/git" <<EOF
#!/bin/bash
for a in "\$@"; do [[ \$a == push ]] && { echo "test git stub refuses to push" >&2; exit 1; }; done
exec "$real_git" "\$@"
EOF
cat >"$stubs/jj" <<EOF
#!/bin/bash
[[ " \$* " == *" push "* && " \$* " != *" --dry-run "* ]] && { echo "test jj stub refuses to push" >&2; exit 1; }
exec "$real_jj" "\$@"
EOF
chmod +x "$stubs"/*
export STATE=$state PATH=$stubs:$PATH

begin() {
	current=$1
	rm -rf "$state" "$tmp/repo"
	mkdir -p "$state/prs"
	echo me >"$state/viewer"
	echo main >"$state/default"
	git init -q -b main "$tmp/repo"
	git -C "$tmp/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
	git -C "$tmp/repo" remote add origin git@github.com:me/repo.git
	git -C "$tmp/repo" switch -q -c feature
	git -C "$tmp/repo" update-ref refs/remotes/origin/feature HEAD
	git -C "$tmp/repo" branch -q -u origin/feature
	mkdir -p "$tmp/repo/sub"
}

# decide <command> [env assignments...]: prints the decision (allow, ask, deny or none) and reason, tab-separated
decide() {
	local c=$1 out
	shift
	out=$(jq -nc --arg c "$c" --arg d "$tmp/repo" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}' |
		env -u CLAUDE_CODE_SESSION_ATTENDED -u CLAUDE_CODE_ENTRYPOINT "$@" bash "$hook")
	[[ -z $out ]] && echo none && return
	jq -r '.hookSpecificOutput | "\(.permissionDecision)\t\(.permissionDecisionReason)"' <<<"$out"
}

interactive=(CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=cli)
unattended=(CLAUDE_CODE_SESSION_ATTENDED=0 CLAUDE_CODE_ENTRYPOINT=sdk-cli)

# expect <decision> [reason substring] -- <command> [env...]
expect() {
	local want=$1 sub='' got
	shift
	[[ $1 != -- ]] && sub=$1 && shift
	shift
	got=$(decide "$@")
	[[ ${got%%$'\t'*} == "$want" ]] || fail "$1: want $want, got $got"
	[[ -z $sub || $got == *"$sub"* ]] || fail "$1: reason should mention '$sub', got $got"
}

begin "interactive sessions prompt for every publish command, alone or in a compound line"
for c in 'git push origin feature' 'cd sub && git push' 'jj git push' 'gh pr create --draft --title t' \
	'gh pr edit 3 --title t' 'gh pr merge 12' 'gh pr ready' 'gh pr close 4' 'git -C sub push' \
	"bash -c 'git push'" 'true; GH_REPO=a/b gh pr merge 1'; do
	expect ask -- "$c" "${interactive[@]}"
done
[[ -e $state/calls ]] && fail "an interactive session looked something up: $(cat "$state/calls")"

begin "commands that only mention push or gh pr pass through"
for c in 'git status' 'git log --grep push' 'echo "git push origin main"' 'gh pr view 3' 'gh pr list' 'grep -r "gh pr merge" .' \
	$'cat >body.md <<\'EOF\'\ngit push origin main\nEOF'; do
	expect none -- "$c" "${interactive[@]}"
	expect none -- "$c" "${unattended[@]}"
done

begin "R6: only a positive signal counts as unattended"
expect ask -- 'gh pr merge 1' CLAUDE_CODE_ENTRYPOINT=cli
expect ask -- 'gh pr merge 1'
expect ask -- 'gh pr merge 1' CLAUDE_CODE_ENTRYPOINT=claude-vscode
expect ask -- 'gh pr merge 1' CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_ENTRYPOINT=sdk-cli
expect ask -- 'gh pr merge 1' CLAUDE_CODE_SESSION_ATTENDED=yes CLAUDE_CODE_ENTRYPOINT=sdk-cli
expect deny -- 'gh pr merge 1' CLAUDE_CODE_ENTRYPOINT=sdk-cli
expect deny -- 'gh pr merge 1' CLAUDE_CODE_SESSION_ATTENDED=0 CLAUDE_CODE_ENTRYPOINT=cli

begin "unattended: a push to a branch with no PR, or the user's own PR, runs"
expect none -- 'git push origin HEAD:me/fix' "${unattended[@]}"
grep -q 'head=me/fix' "$state/calls" || fail "looked up the wrong branch: $(cat "$state/calls")"
echo "5 me" >"$state/prs/feature"
expect none -- 'git push' "${unattended[@]}"
expect none -- 'git add -A && git commit -m "fix; git push origin main" && git push -u origin feature' "${unattended[@]}"
expect none -- 'git push --force-with-lease origin +refs/heads/feature:refs/heads/feature 2>&1 | tail -3' "${unattended[@]}"

begin "unattended: a push to someone else's PR is denied with its number and author"
echo "7 alice" >"$state/prs/feature"
expect deny '#7 by alice' -- 'git push origin feature' "${unattended[@]}"
expect deny '#7 by alice' -- 'git push' "${unattended[@]}"
expect deny '#7 by alice' -- 'cd sub && git push origin HEAD' "${unattended[@]}"
expect deny '#7 by alice' -- 'git push origin --delete feature' "${unattended[@]}"
git -C "$tmp/repo" branch -q --unset-upstream
expect deny '#7 by alice' -- 'git push' "${unattended[@]}"
printf '8 me\n9 bob\n' >"$state/prs/other"
expect deny '#9 by bob' -- 'git push origin feature:other' "${unattended[@]}"

begin "unattended: a push to the default branch is denied"
expect deny 'default branch' -- 'git push origin main' "${unattended[@]}"
expect deny 'default branch' -- 'git push origin HEAD:refs/heads/main' "${unattended[@]}"
expect deny 'default branch' -- 'git push origin me/fix main' "${unattended[@]}"

begin "unattended: gh pr create needs --draft"
expect deny 'add --draft' -- 'gh pr create --title t --body-file b' "${unattended[@]}"
expect deny 'add --draft' -- 'gh pr create --title "x --draft" --body-file b' "${unattended[@]}"
expect none -- 'gh pr create --draft --title t --body-file b' "${unattended[@]}"
expect none -- 'gh pr create -d -t t -F b' "${unattended[@]}"

begin "unattended: merge, ready and close are denied"
expect deny 'gh pr merge' -- 'gh pr merge 12' "${unattended[@]}"
expect deny 'gh pr ready' -- 'gh pr ready' "${unattended[@]}"
expect deny 'gh pr close' -- 'gh pr close 4 --comment done' "${unattended[@]}"
expect deny 'gh pr merge' -- "git push origin me/fix && sh -c 'gh pr merge --squash'" "${unattended[@]}"

begin "unattended: gh pr edit only on the user's PRs"
echo me >"$state/pr-3"
echo alice >"$state/pr-4"
echo 3 >"$state/current-pr"
expect none -- 'gh pr edit 3 --title t' "${unattended[@]}"
expect none -- 'gh pr edit --add-label x' "${unattended[@]}"
expect deny 'PR #4 is by alice' -- 'gh pr edit 4 --body-file b' "${unattended[@]}"
expect deny 'PR #4 is by alice' -- 'gh pr edit --title t 4' "${unattended[@]}"

begin "R7: a failed lookup falls back to the prompt"
touch "$state/gh-fail"
expect ask 'could not look up' -- 'git push origin me/fix' "${unattended[@]}"
expect ask 'could not look up' -- 'gh pr edit 3' "${unattended[@]}"
rm "$state/gh-fail"
touch "$state/unknown-repo"
expect ask 'could not look up' -- 'git push origin me/fix' "${unattended[@]}"
rm "$state/unknown-repo"
git -C "$tmp/repo" remote set-url origin /srv/git/repo.git
expect ask 'which GitHub repo' -- 'git push origin me/fix' "${unattended[@]}"
expect ask -- 'git push --all origin' "${unattended[@]}"
# shellcheck disable=SC2016 # the variable must reach the hook unexpanded
expect ask -- 'cd "$OTHER" && git push origin me/fix' "${unattended[@]}"

begin "R7: with no gh on PATH, publish commands prompt"
mkdir -p "$tmp/nogh"
for t in jq git ssh awk sed head tr cat grep env bash; do
	ln -sf "$(PATH=$stubs:$PATH command -v "$t")" "$tmp/nogh/$t"
done
expect ask 'no gh' -- 'git push origin me/fix' PATH="$tmp/nogh" "${unattended[@]}"
expect ask 'no gh' -- 'gh pr edit 3' PATH="$tmp/nogh" "${unattended[@]}"
expect deny -- 'gh pr merge 3' PATH="$tmp/nogh" "${unattended[@]}"

begin "with no jq, publish commands prompt in either kind of session"
mkdir -p "$tmp/nojq"
for t in cat grep env bash; do ln -sf "$(command -v "$t")" "$tmp/nojq/$t"; done
expect ask 'no jq' -- 'git status && git push origin me/fix' PATH="$tmp/nojq" "${unattended[@]}"
expect ask 'no jq' -- 'gh pr merge 1' PATH="$tmp/nojq" "${interactive[@]}"
expect none -- 'ls' PATH="$tmp/nojq" "${interactive[@]}"

if [[ -n $real_jj ]]; then
	begin "unattended jj git push checks each bookmark the dry run lists"
	rm -rf "$tmp/repo"
	git init -q --bare "$tmp/remote.git"
	jj git init "$tmp/repo" >/dev/null 2>&1
	j() { jj -R "$tmp/repo" --config user.name=t --config user.email=t@t "$@" >/dev/null 2>&1; }
	j git remote add origin "$tmp/remote.git"
	j commit -m one
	j bookmark create main -r @-
	j git push -b main
	j commit -m two
	j bookmark create mine -r @-
	expect ask 'which GitHub repo' -- 'jj git push -b mine' "${unattended[@]}"
	j bookmark move main --to @-
	expect ask -- 'jj git push --all' "${interactive[@]}"
	expect none -- 'jj git push --dry-run -b main' "${unattended[@]}"
	# The dry run works from jj's record of the remote, so it lists the push without reaching GitHub
	j git remote set-url origin git@github.com:me/repo.git
	expect deny 'default branch' -- 'jj git push -b main' "${unattended[@]}"
	expect deny 'default branch' -- 'jj git push' "${unattended[@]}"
	expect none -- 'jj git push -b mine' "${unattended[@]}"
	echo "2 carol" >"$state/prs/mine"
	expect deny '#2 by carol' -- 'jj git push -b mine' "${unattended[@]}"
	expect none -- 'jj git push -c @-' "${unattended[@]}"
	j bookmark list | grep -q push- && fail "the dry run for -c left a bookmark behind"
else
	echo "skip: no jj, so the jj git push cases did not run"
fi

if ((failures)); then
	echo "$failures failure(s)"
	exit 1
fi
echo "all passed"
