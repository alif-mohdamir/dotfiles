#!/bin/bash
# PreToolUse(Bash): gate git push, jj git push and gh pr create/edit/merge/ready/close.
# Interactive sessions get a prompt for each. An unattended run (CLAUDE_CODE_SESSION_ATTENDED=0, or
# that unset under an sdk-* entrypoint) may push branches with no open PR or with the user's own PR,
# open draft PRs and edit the user's PRs. It is denied merges, ready, close, the default branch and
# other people's PRs, and gets the interactive prompt (a deny when headless) when a lookup fails.
# Exit 0 with no output leaves the decision to the session's permission mode.

input=$(cat)
rough='(git|jj)[^;&|]*[[:space:]]push|gh[^;&|]*[[:space:]]pr[[:space:]]'

emit() {
	jq -nc --arg d "$1" --arg r "$2" \
		'{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
	exit 0
}

if ! command -v jq >/dev/null; then
	grep -qE "$rough" <<<"$input" &&
		echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"publish-gate: no jq to read the command, so it needs approval"}}'
	exit 0
fi

cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
dir=$(jq -r '.cwd // empty' <<<"$input")
[[ -z $cmd ]] && exit 0
[[ $cmd == *push* || $cmd == *gh* ]] || exit 0

unattended=0
case ${CLAUDE_CODE_SESSION_ATTENDED-} in
0) unattended=1 ;;
# Only an sdk entrypoint counts: the IDE and desktop entrypoints are interactive too
'') [[ ${CLAUDE_CODE_ENTRYPOINT-} == sdk-* ]] && unattended=1 ;;
esac

# Splits a command line into simple commands, each an array of words with quotes removed.
# Heredoc bodies are dropped first, so a PR body that mentions git push is not read as a command.
read -r -d '' tokenize <<'JQ'
def drop_heredocs:
	reduce split("\n")[] as $l ({out: [], held: [], until: []};
		if .until != [] then
			if ($l | sub("^\t+"; "")) == .until[0] then .until = .until[1:] | .held = [] | .out += [$l]
			else .held += [$l] end
		else .out += [$l]
			| .until = [$l | scan("(?<![<])<<-?[ \t]*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?")[0]]
		end)
	# An unterminated heredoc keeps its lines, so a stray << cannot hide the rest of the command
	| (.out + .held) | join("\n");

def unquote:
	if startswith("'") and length > 1 and endswith("'") then .[1:-1]
	elif startswith("\"") and length > 1 and endswith("\"") then .[1:-1] | gsub("\\\\(?<c>[\"\\\\$`])"; .c)
	elif startswith("\\") then .[1:]
	else . end;

# A redirect drops its target word, except a descriptor copy such as 2>&1
def flush: if .word != null then (if .skip then . else .cur += [.word] end) | .word = null | .skip = false else . end;

drop_heredocs
| [scan("'[^']*'|\"(?:[^\"\\\\]|\\\\.)*\"|\\\\.|[0-9]*(?:&>>|&>|>>|>&|<&|>\\||<<<|<<-?|<>|>|<)(?:[0-9]+-?|-)?|&&|\\|\\||\\$\\(|[;&|()`\n]|[^ \t\n'\"\\\\;&|()`<>]+|[ \t]+|.")]
| reduce .[] as $t ({segs: [], cur: [], word: null, skip: false};
	if $t | test("^[ \t]+$") then flush
	elif $t | IN("&&", "||", "$(", ";", "&", "|", "(", ")", "`", "\n") then flush | .segs += [.cur] | .cur = [] | .skip = false
	elif $t | test("^[0-9]*(&>>|&>|>>|>&|<&|>\\||<<<|<<-?|<>|>|<)") then flush | .skip = ($t | test("[<>]&([0-9]+-?|-)$") | not)
	else .word = ((.word // "") + ($t | unquote)) end)
| flush
| .segs + [.cur]
| map(select(length > 0))
JQ

deny_reason=
ask_reason=

ask() { [[ -n $ask_reason ]] || ask_reason=$1; }
deny() { [[ -n $deny_reason ]] || deny_reason=$1; }

# github_repo <url>: prints host, owner and name on one line, for a GitHub-shaped remote URL
github_repo() {
	local u=${1%/} host owner name real
	u=${u%.git}
	if [[ $u =~ ^[a-z+]+://([^@/]+@)?([^/:]+)(:[0-9]+)?/([^/]+)/([^/]+)$ ]]; then
		host=${BASH_REMATCH[2]} owner=${BASH_REMATCH[4]} name=${BASH_REMATCH[5]}
	elif [[ $u =~ ^([^@/]+@)?([^/:]+):([^/]+)/([^/]+)$ ]]; then
		host=${BASH_REMATCH[2]} owner=${BASH_REMATCH[3]} name=${BASH_REMATCH[4]}
		# scp-style URLs often name an ssh config alias rather than the real host
		if command -v ssh >/dev/null; then
			real=$(ssh -G "$host" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')
			[[ -n $real ]] && host=$real
		fi
	else
		return 1
	fi
	echo "$host $owner $name"
}

# check_branch <remote url> <branch> <what>: applies the default-branch and PR-author rules to one push target
check_branch() {
	local url=$1 branch=$2 what=$3 repo host owner name out verdict
	repo=$(github_repo "$url") || {
		ask "$what: cannot tell which GitHub repo $url is, so this needs the user's approval"
		return
	}
	read -r host owner name <<<"$repo"
	command -v gh >/dev/null || {
		ask "$what: no gh to check the branch's PR, so this needs the user's approval"
		return
	}
	# shellcheck disable=SC2016 # the $ names are GraphQL variables
	out=$(gh api graphql --hostname "$host" -f owner="$owner" -f name="$name" -f head="$branch" -f query='
		query($owner: String!, $name: String!, $head: String!) {
			viewer { login }
			repository(owner: $owner, name: $name) {
				defaultBranchRef { name }
				pullRequests(headRefName: $head, states: OPEN, first: 20) { nodes { number author { login } } }
			}
		}' 2>&1)
	verdict=$(jq -r --arg b "$branch" --arg r "$owner/$name" '
		.data.viewer.login as $me
		| .data.repository as $repo
		| if $me == null or $repo == null then "ask"
		elif $b == $repo.defaultBranchRef.name then "deny \($b) is the default branch of \($r). Push a feature branch and open a draft PR instead."
		else [$repo.pullRequests.nodes[] | select(.author.login != $me) | "#\(.number) by \(.author.login // "a deleted account")"] as $others
			| if $others == [] then "ok"
			else "deny Branch \($b) of \($r) has an open PR by someone else (\($others | join(", "))). Ask the user before pushing to it, or push a new branch."
			end
		end' <<<"$out" 2>/dev/null)
	case $verdict in
	ok) ;;
	deny\ *) deny "${verdict#deny }" ;;
	*) ask "$what: could not look up the PR for $branch on $owner/$name ($(head -c 200 <<<"$out" | tr '\n' ' ')), so this needs the user's approval" ;;
	esac
}

git_in() { (cd "$dir" 2>/dev/null && env ${assigns[@]+"${assigns[@]}"} git "$@" 2>/dev/null); }

git_push() {
	local remote='' delete=0 refspecs=() a src dst cur url target targets=()
	while (($#)); do
		a=$1
		shift
		case $a in
		--) refspecs+=("$@") && break ;;
		--all | --mirror | --tags | --branches | --prune)
			ask "git push $a: pushes refs this hook cannot list, so it needs the user's approval"
			return
			;;
		-d | --delete) delete=1 ;;
		--repo=*) remote=${a#--repo=} ;;
		--repo) remote=$1 && shift ;;
		-o | --push-option | --receive-pack | --exec) shift ;;
		-*) ;;
		*) if [[ -z $remote ]]; then remote=$a; else refspecs+=("$a"); fi ;;
		esac
	done
	[[ -n $dir ]] || {
		ask "git push: cannot tell which directory it runs in, so it needs the user's approval"
		return
	}
	cur=$(git_in symbolic-ref --short -q HEAD)
	if ((${#refspecs[@]} == 0)); then
		target=$(git_in rev-parse --abbrev-ref --symbolic-full-name '@{push}') || target=''
		if [[ -n $target && (-z $remote || $target == "$remote"/*) ]]; then
			[[ -n $remote ]] || remote=${target%%/*}
			targets+=("${target#"$remote"/}")
		elif [[ -n $cur ]]; then
			[[ -n $remote ]] || remote=$(git_in config "branch.$cur.pushRemote" || git_in config remote.pushDefault || git_in config "branch.$cur.remote" || echo origin)
			targets+=("$cur")
		fi
	fi
	for a in ${refspecs[@]+"${refspecs[@]}"}; do
		a=${a#+}
		if [[ $a == *:* ]]; then src=${a%%:*} dst=${a#*:}; else src=$a dst=$a; fi
		((delete)) && dst=$src
		[[ $dst == HEAD || $dst == @ ]] && dst=$cur
		dst=${dst#refs/heads/}
		if [[ -z $dst || $dst == refs/* ]]; then
			ask "git push $a: the target is not a branch this hook can check, so it needs the user's approval"
			return
		fi
		targets+=("$dst")
	done
	if ((${#targets[@]} == 0)) || [[ -z $remote ]]; then
		ask "git push: cannot tell which branch it pushes, so it needs the user's approval"
		return
	fi
	url=$(git_in remote get-url --push "$remote") || url=$remote
	for target in "${targets[@]}"; do
		check_branch "$url" "$target" "git push to $target"
	done
}

jj_push() {
	local globals=() a out remote url branch found=0
	while (($#)) && [[ $1 != git ]]; do
		globals+=("$1")
		shift
	done
	shift 2
	for a in "$@"; do
		[[ $a == --dry-run ]] && return
	done
	if [[ -z $dir ]] || ! command -v jj >/dev/null; then
		ask "jj git push: cannot work out what it pushes here, so it needs the user's approval"
		return
	fi
	# The dry run lists the exact bookmarks, revsets and globs included; it creates no bookmark for -c
	out=$(cd "$dir" 2>/dev/null && env ${assigns[@]+"${assigns[@]}"} jj ${globals[@]+"${globals[@]}"} git push "$@" --dry-run 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g')
	remote=$(sed -n 's/^Changes to push to \([^:]*\):$/\1/p' <<<"$out" | head -1)
	[[ $out == *"Nothing changed."* && -z $remote ]] && return
	url=$(cd "$dir" && jj ${globals[@]+"${globals[@]}"} git remote list 2>/dev/null | awk -v r="$remote" '$1 == r { print $2; exit }')
	if [[ -z $remote || -z $url ]]; then
		ask "jj git push: the dry run did not say what it would push ($(head -c 200 <<<"$out" | tr '\n' ' ')), so it needs the user's approval"
		return
	fi
	while read -r branch; do
		found=1
		check_branch "$url" "$branch" "jj git push of $branch"
	done < <(sed -nE 's/^ *bookmark: ([^ ]+) \[.*/\1/p; s/^ *(Add|Move [a-z]+|Delete|Force push) bookmark ([^ ]+) .*/\2/p' <<<"$out")
	((found)) || ask "jj git push: the dry run listed no bookmarks this hook can read, so it needs the user's approval"
}

gh_pr_edit() {
	local sel='' repo='' a out me author number
	while (($#)); do
		a=$1
		shift
		case $a in
		-R | --repo) repo=$1 && shift ;;
		--repo=*) repo=${a#--repo=} ;;
		--remove-milestone | --*=*) ;;
		-*) shift ;;
		*) [[ -z $sel ]] && sel=$a ;;
		esac
	done
	if [[ -z $dir ]] || ! command -v gh >/dev/null; then
		ask "gh pr edit: no gh to check who opened the PR, so it needs the user's approval"
		return
	fi
	out=$(cd "$dir" 2>/dev/null && env ${assigns[@]+"${assigns[@]}"} gh pr view ${sel:+"$sel"} ${repo:+--repo "$repo"} --json number,author --jq '"\(.number) \(.author.login)"' 2>&1) &&
		me=$(gh api user --jq .login 2>&1)
	read -r number author <<<"$out"
	if [[ -z $author || -z $me || ! $number =~ ^[0-9]+$ ]]; then
		ask "gh pr edit: could not look up the PR's author ($(head -c 200 <<<"$out $me" | tr '\n' ' ')), so it needs the user's approval"
		return
	fi
	[[ $author == "$me" ]] || deny "PR #$number is by $author. An unattended run edits only the user's own PRs; ask the user first."
}

# subdir <path>: moves $dir the way cd would, or empties it when the path holds an unexpanded variable
subdir() {
	local w=$1
	[[ $w == \~ || $w == \~/* ]] && w=$HOME${w#\~}
	if [[ $w == *'$'* || $w == - ]]; then dir=
	elif [[ $w == /* ]]; then dir=$w
	elif [[ -n $dir ]]; then dir=$dir/$w; fi
}

# visit <depth> <words...>: classifies one simple command
visit() {
	local depth=$1 w a
	shift
	assigns=()
	while (($#)); do
		case $1 in
		env | sudo | command | builtin | exec | nohup | time)
			w=$1
			shift
			while [[ $1 == -* ]]; do
				[[ $w == env || $w == sudo ]] && [[ $1 == -u || $1 == -C || $1 == -g ]] && shift
				shift
			done
			;;
		'!' | '{' | '}' | then | do | else | elif | if | while | until) shift ;;
		*)
			[[ $1 =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || break
			assigns+=("$1")
			shift
			;;
		esac
	done
	(($#)) || return
	case ${1##*/} in
	cd | pushd) subdir "${2-$HOME}" ;;
	bash | sh | zsh | dash)
		shift
		while (($#)); do
			if [[ $1 == -*c* && $1 != --* ]]; then
				scan "$2" $((depth + 1))
				return
			fi
			shift
		done
		;;
	eval) shift && scan "$*" $((depth + 1)) ;;
	git)
		shift
		while (($#)); do
			case $1 in
			-C)
				subdir "$2"
				shift 2
				;;
			-c | --git-dir | --work-tree | --namespace | --exec-path) shift 2 ;;
			-*) shift ;;
			*) break ;;
			esac
		done
		[[ $1 == push ]] || return
		shift
		found "git push" || git_push "$@"
		;;
	jj)
		shift
		w=("$@")
		while (($#)); do
			case $1 in
			-R | --repository)
				subdir "$2"
				shift 2
				;;
			--at-op | --at-operation | --color | --config | --config-file | --config-toml | --when) shift 2 ;;
			-*) shift ;;
			*) break ;;
			esac
		done
		[[ $1 == git && $2 == push ]] || return
		found "jj git push" || jj_push "${w[@]}"
		;;
	gh)
		[[ $2 == pr ]] || return
		case $3 in
		create)
			found "gh pr create" && return
			for a in "${@:4}"; do
				[[ $a == -d || $a == --draft || $a == --draft=true ]] && return
			done
			deny "An unattended run opens only draft PRs: add --draft to gh pr create."
			;;
		edit) found "gh pr edit" || gh_pr_edit "${@:4}" ;;
		merge | ready | close) found "gh pr $3" || deny "An unattended run cannot run gh pr $3. Leave the PR as a draft for the user." ;;
		esac
		;;
	esac
}

# found <command>: in an interactive session, asks for it and succeeds; unattended, fails so the caller checks it
found() {
	((unattended)) && return 1
	ask "$1 publishes to the remote, so it needs your approval."
}

# scan <command> <depth>
scan() {
	local line words done=0
	if (($2 > 3)); then
		[[ $1 =~ $rough ]] && ask "The command nests shells too deep for this hook to read, so it needs approval."
		return
	fi
	while IFS= read -r -d '' line; do
		[[ -z $line ]] && done=1 && break
		eval "words=($line)"
		visit "$2" "${words[@]}"
	done < <(jq -nj --arg c "$1" '$c | '"$tokenize"' | (.[] | @sh, "\u0000"), "\u0000"' 2>/dev/null)
	((done)) || { [[ $1 =~ $rough ]] && ask "This hook could not read the command, so it needs approval."; }
}

scan "$cmd" 0
[[ -n $deny_reason ]] && emit deny "$deny_reason"
[[ -n $ask_reason ]] && emit ask "$ask_reason"
exit 0
