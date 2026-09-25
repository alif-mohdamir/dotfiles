#!/bin/bash
# PreToolUse(Bash): block git subcommands in a jj repo; exit 2 = block + feedback to Claude.
set -euo pipefail

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
cwd=$(jq -r '.cwd // empty' <<<"$input")
[[ -z "$cmd" || -z "$cwd" ]] && exit 0

(cd "$cwd" && jj workspace root >/dev/null 2>&1) || exit 0

blocked='(^|[;&|][[:space:]]*)git[[:space:]]+(commit|add|status|diff|log|push|pull|checkout|switch|branch|stash|rebase|merge|reset|restore|cherry-pick|tag|fetch|show|blame|describe)([[:space:]]|$)'

if [[ "$cmd" =~ $blocked ]]; then
  cat >&2 <<EOF
Blocked: this repo uses jj (found .jj). Use the jj equivalent.
Command: $cmd
If no direct jj equivalent exists (e.g. gh, git lfs, git config), ask the user.
EOF
  exit 2
fi
exit 0
