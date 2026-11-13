#!/bin/bash
# SessionStart: warn when this machine's Claude settings are behind the dotfiles repo. Changes nothing.
# A hook's JSON systemMessage is shown to the user and kept out of Claude's context.
command -v jq >/dev/null || exit 0
self=$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null) || exit 0
dotfiles=$(cd "$(dirname "$self")/../../.." 2>/dev/null && pwd) || exit 0
[[ -f $dotfiles/claude-settings/settings.base.json ]] || exit 0

why=
if [[ $(uname -s) == Linux ]]; then
	INSTALL_ON_LINUX_FUNCTIONS_ONLY=1 source "$dotfiles/install-on-linux.sh" || exit 0
	# The installer turns these on for itself, and here a failed lookup must not end the hook
	set +eu +o pipefail
	unlinked=$(unlinked_claude_hooks "$dotfiles" | tr '\n' ' ')
	if [[ -n $unlinked ]]; then
		why="hooks not linked into ~/.claude/hooks: $unlinked"
	elif box_settings_stale "$dotfiles"; then
		why="~/.claude/settings.json is behind settings.base.json"
	fi
else
	why=$("$dotfiles/claude-settings/generate.sh" --check 2>/dev/null)
fi
[[ -n $why ]] || exit 0
jq -cn --arg m "Claude settings are stale: ${why% }. Run $dotfiles/install.sh" '{systemMessage: $m}'
