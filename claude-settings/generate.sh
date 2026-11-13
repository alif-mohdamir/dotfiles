#!/bin/bash
# Writes ~/.claude/settings.json from settings.base.json (shared, in this repo) merged with
# ~/.claude/settings.machine.json (per machine, untracked). Pass --force to overwrite local edits.
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)/settings.base.json"
MACHINE=~/.claude/settings.machine.json
OUT=~/.claude/settings.json
# Last generated output, used to tell our writes apart from edits made through /config
STAMP=~/.claude/.settings.generated.json

FORCE=0
[[ ${1:-} == --force ]] && FORCE=1

if [[ -f $MACHINE ]]; then
	# Nested objects merge key by key; arrays from the machine file replace the base arrays
	new=$(jq -s '.[0] * .[1]' "$BASE" "$MACHINE")
else
	new=$(jq . "$BASE")
fi

# Claude runs on when a hook's script is missing, so a gate registered here but never stowed would guard nothing
HOOKS_SRC="$(dirname "$BASE")/../claude/.claude/hooks"
missing=()
while IFS= read -r name; do
	if [[ -e $HOOKS_SRC/$name && ! -x ~/.claude/hooks/$name ]]; then
		missing+=("$name")
	fi
done < <(jq -r '[.hooks[]?[]?.hooks[]?.command // empty | capture("^~/\\.claude/hooks/(?<n>[^/ ]+)( |$)").n] | unique[]' <<<"$new")
if ((${#missing[@]})); then
	echo "$OUT not written: these hooks are registered but not linked into ~/.claude/hooks: ${missing[*]}" >&2
	echo "Run install.sh, or stow the claude package, then rerun." >&2
	exit 1
fi

# Older setups stowed settings.json as a symlink into the repo
[[ -L $OUT ]] && rm "$OUT"

if [[ -f $OUT && $FORCE == 0 ]]; then
	if [[ -f $STAMP ]]; then
		expected=$STAMP
	else
		expected=<(printf '%s\n' "$new")
	fi
	if ! diff -q <(jq -S . "$OUT") <(jq -S . "$expected") >/dev/null; then
		echo "$OUT has changes that would be lost:" >&2
		diff -u --label generated --label "$OUT" <(jq -S . "$expected") <(jq -S . "$OUT") >&2 || true
		echo "Move them into $BASE or $MACHINE, or rerun with --force." >&2
		exit 1
	fi
fi

printf '%s\n' "$new" >"$OUT"
cp "$OUT" "$STAMP"
echo "wrote $OUT"
