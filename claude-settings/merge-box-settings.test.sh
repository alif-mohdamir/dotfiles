#!/bin/bash
# Tests for merge-box-settings.jq, run against small fixture files.
#
#   bash claude-settings/merge-box-settings.test.sh
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
filter=$here/merge-box-settings.jq
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
	rm -rf "${tmp:?}"/case
	mkdir -p "$tmp/case"
	echo null >"$tmp/case/none.json"
}

# merge <box> <base> <record> <name>: writes $tmp/case/<name>.settings.json, .record.json and .kept.json
merge() {
	local out=$tmp/case/$4
	jq --slurpfile base "$2" --slurpfile record "$3" -f "$filter" "$1" >"$out.json" || {
		fail "merge $4 failed"
		return 1
	}
	jq .settings "$out.json" >"$out.settings.json"
	jq .record "$out.json" >"$out.record.json"
	jq .kept "$out.json" >"$out.kept.json"
}

# check <file> <jq expression> <expected compact output>
check() {
	local got
	got=$(jq -c "$2" "$1")
	[[ $got == "$3" ]] || fail "$2 should be $3, is $got"
}

# with <name> <jq edit>: writes $tmp/case/<name>.json, the fixture base with that edit applied
with() {
	jq "$2" "$tmp/case/base.json" >"$tmp/case/$1.json"
}

fixtures() {
	cat >"$tmp/case/base.json" <<'EOF'
{
  "model": "opus",
  "effortLevel": "medium",
  "theme": "auto",
  "tui": "fullscreen",
  "apiKeyHelper": "base-helper",
  "env": {"FROM_BASE": "1"},
  "permissions": {"ask": ["Bash(push:*)", "Bash(merge:*)"], "defaultMode": "auto"},
  "enabledPlugins": {"compound-engineering@compound-engineering-plugin": true, "some-lsp@market": true},
  "hooks": {
    "Stop": [{"matcher": "", "hooks": [
      {"type": "command", "command": "~/.claude/hooks/peon-ping/peon.sh", "timeout": 10, "async": true},
      {"type": "command", "command": "~/scripts/ce-sync hook-stop", "timeout": 120}
    ]}],
    "SessionStart": [{"matcher": "", "hooks": [
      {"type": "command", "command": "~/scripts/ce-sync hook-start", "timeout": 60}
    ]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [
      {"type": "command", "command": "~/.claude/hooks/prefer-jj.sh", "timeout": 5}
    ]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [
      {"type": "command", "command": "~/.claude/hooks/peon-ping/peon.sh", "timeout": 10, "async": true}
    ]}]
  }
}
EOF
	cat >"$tmp/case/box.json" <<'EOF'
{
  "apiKeyHelper": "box-helper",
  "env": {"BOX_KEY": "1"},
  "idleCompaction": true,
  "hooks": {
    "Stop": [{"matcher": "", "hooks": [{"type": "command", "command": "/opt/box/bin/box-status stop"}]}],
    "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "/opt/box/bin/box-status start"}]}],
    "UserPromptSubmit": [
      {"matcher": "", "hooks": [{"type": "command", "command": "/opt/box/bin/box-status prompt"}]},
      {"matcher": "", "hooks": [{"type": "command", "command": "/opt/box/bin/box-status prompt-extra"}]}
    ]
  }
}
EOF
}

box_groups='[.hooks[][] | select(any(.hooks[]; .command | test("box-status")))]'

# Each event whose groups include box-status ones has them last, in the order the box had them.
box_groups_last() {
	local event
	for event in $(jq -r '.hooks | keys[]' "$tmp/case/box.json"); do
		jq -e --arg e "$event" --slurpfile box "$tmp/case/box.json" '
			($box[0].hooks[$e]) as $theirs
			| .hooks[$e][-($theirs | length):] == $theirs' "$1" >/dev/null ||
			fail "$event should end with the box's groups: $(jq -c --arg e "$event" '.hooks[$e]' "$1")"
	done
}

begin "a box keeps its own keys and hooks, gets base groups first and no tui"
fixtures
merge "$tmp/case/box.json" "$tmp/case/base.json" "$tmp/case/none.json" one
s=$tmp/case/one.settings.json
check "$s" .apiKeyHelper '"box-helper"'
check "$s" .env '{"BOX_KEY":"1","PEON_PLATFORM":"ssh"}'
check "$s" .idleCompaction true
check "$s" 'has("tui")' false
check "$s" .model '"opus"'
check "$s" '[.hooks.Stop[].hooks[].command]' '["~/.claude/hooks/peon-ping/peon.sh","~/scripts/ce-sync hook-stop","/opt/box/bin/box-status stop"]'
check "$s" '[.hooks.UserPromptSubmit[].hooks[].command]' '["~/.claude/hooks/peon-ping/peon.sh","/opt/box/bin/box-status prompt","/opt/box/bin/box-status prompt-extra"]'
check "$s" '[.hooks.PreToolUse[].hooks[].command]' '["~/.claude/hooks/prefer-jj.sh"]'
box_groups_last "$s"
check "$tmp/case/one.kept.json" . '[]'

begin "a box with its own PEON_PLATFORM keeps it"
fixtures
jq '.env.PEON_PLATFORM = "linux"' "$tmp/case/box.json" >"$tmp/case/box2.json"
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
check "$tmp/case/one.settings.json" .env.PEON_PLATFORM '"linux"'
check "$tmp/case/one.record.json" '[.. | strings | select(. == "PEON_PLATFORM" or . == "linux")]' '[]'

begin "a first run applies and records a box value that equals base"
fixtures
jq '.theme = "auto"' "$tmp/case/box.json" >"$tmp/case/box2.json"
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
check "$tmp/case/one.settings.json" .theme '"auto"'
check "$tmp/case/one.record.json" '[.values[] | select(.path == ["theme"]) | .value]' '["auto"]'
check "$tmp/case/one.kept.json" . '[]'

begin "a first run keeps a box value that differs from base, lists it and does not record it"
fixtures
jq '.effortLevel = "high"' "$tmp/case/box.json" >"$tmp/case/box2.json"
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
check "$tmp/case/one.settings.json" .effortLevel '"high"'
check "$tmp/case/one.kept.json" . '["effortLevel"]'
check "$tmp/case/one.record.json" '[.values[] | select(.path == ["effortLevel"])]' '[]'

begin "a rerun after base changes two keys keeps the one the box overrode"
fixtures
merge "$tmp/case/box.json" "$tmp/case/base.json" "$tmp/case/none.json" one
jq '.effortLevel = "high"' "$tmp/case/one.settings.json" >"$tmp/case/edited.json"
with base2 '.effortLevel = "low" | .theme = "dark"'
merge "$tmp/case/edited.json" "$tmp/case/base2.json" "$tmp/case/one.record.json" two
check "$tmp/case/two.settings.json" .theme '"dark"'
check "$tmp/case/two.settings.json" .effortLevel '"high"'
check "$tmp/case/two.kept.json" . '["effortLevel"]'

begin "a rerun after base drops a recorded key removes it from the box"
fixtures
merge "$tmp/case/box.json" "$tmp/case/base.json" "$tmp/case/none.json" one
with base2 'del(.model)'
merge "$tmp/case/one.settings.json" "$tmp/case/base2.json" "$tmp/case/one.record.json" two
check "$tmp/case/two.settings.json" 'has("model")' false
check "$tmp/case/two.record.json" '[.values[] | select(.path == ["model"])]' '[]'
check "$tmp/case/two.kept.json" . '[]'

begin "a rerun after base drops a hook group removes it and leaves the box's groups last"
fixtures
merge "$tmp/case/box.json" "$tmp/case/base.json" "$tmp/case/none.json" one
with base2 'del(.hooks.PreToolUse) | .hooks.Stop[0].hooks |= map(select(.command | test("ce-sync") | not))'
merge "$tmp/case/one.settings.json" "$tmp/case/base2.json" "$tmp/case/one.record.json" two
s=$tmp/case/two.settings.json
check "$s" '.hooks | has("PreToolUse")' false
check "$s" '[.hooks.Stop[].hooks[].command]' '["~/.claude/hooks/peon-ping/peon.sh","/opt/box/bin/box-status stop"]'
check "$s" "$box_groups" "$(jq -c "$box_groups" "$tmp/case/box.json")"
box_groups_last "$s"
check "$tmp/case/two.kept.json" . '[]'

begin "the box merge replaces old ce-sync hooks and keeps the box's own after them"
fixtures
cat >"$tmp/case/box2.json" <<'EOF'
{"hooks": {
  "Stop": [
    {"matcher": "", "hooks": [{"type": "command", "command": "~/scripts/ce-sync hook-stop", "timeout": 120, "async": true}]},
    {"matcher": "", "hooks": [{"type": "command", "command": "box-status stop"}]}
  ],
  "SessionStart": [
    {"matcher": "", "hooks": [{"type": "command", "command": "~/scripts/ce-sync hook-start", "timeout": 60}]}
  ]
}, "other": 1}
EOF
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
s=$tmp/case/one.settings.json
check "$s" '[.hooks.Stop[].hooks[].command]' '["~/.claude/hooks/peon-ping/peon.sh","~/scripts/ce-sync hook-stop","box-status stop"]'
check "$s" '[.hooks.Stop[].hooks[] | select(.async and (.command | test("ce-sync")))] | length' 0
check "$s" '[.hooks.SessionStart[].hooks[].command]' '["~/scripts/ce-sync hook-start"]'
check "$s" .other 1
for event in $(jq -r '.hooks | keys[]' "$tmp/case/base.json"); do
	jq -e --arg e "$event" --slurpfile base "$tmp/case/base.json" '
		all($base[0].hooks[$e][] as $g | [.hooks[$e][] | select(. == $g)] | length == 1; .)' "$s" >/dev/null ||
		fail "$event should hold each base group once: $(jq -c --arg e "$event" '.hooks[$e]' "$s")"
done

begin "peon's own installer groups are replaced by base's and the box's groups stay last"
fixtures
cat >"$tmp/case/box2.json" <<'EOF'
{"hooks": {
  "Stop": [
    {"matcher": "", "hooks": [{"type": "command", "command": "/opt/box/bin/box-status stop"}]},
    {"matcher": "", "hooks": [{"type": "command", "command": "/home/me/.claude/hooks/peon-ping/peon.sh", "timeout": 10, "async": true}]}
  ],
  "UserPromptSubmit": [
    {"matcher": "", "hooks": [{"type": "command", "command": "/opt/box/bin/box-status prompt"}]},
    {"matcher": "", "hooks": [{"type": "command", "command": "/opt/box/bin/box-status prompt-extra"}]},
    {"matcher": "", "hooks": [
      {"type": "command", "command": "/home/me/.claude/hooks/peon-ping/scripts/hook-handle-use.sh", "timeout": 5},
      {"type": "command", "command": "/home/me/.claude/hooks/peon-ping/scripts/hook-handle-rename.sh", "timeout": 5}
    ]}
  ]
}}
EOF
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
s=$tmp/case/one.settings.json
check "$s" '[.hooks.UserPromptSubmit[].hooks[].command]' '["~/.claude/hooks/peon-ping/peon.sh","/opt/box/bin/box-status prompt","/opt/box/bin/box-status prompt-extra"]'
check "$s" '[.hooks.Stop[].hooks[].command]' '["~/.claude/hooks/peon-ping/peon.sh","~/scripts/ce-sync hook-stop","/opt/box/bin/box-status stop"]'
check "$s" '[.. | .command? // empty | select(startswith("/home/"))]' '[]'
check "$tmp/case/one.kept.json" '[.[] | select(test("peon-ping"))] | length' 0

begin "a box peon group with an edited timeout is replaced by base's and named"
fixtures
merge "$tmp/case/box.json" "$tmp/case/base.json" "$tmp/case/none.json" one
jq '.hooks.UserPromptSubmit[0].hooks[0].timeout = 30' "$tmp/case/one.settings.json" >"$tmp/case/edited.json"
merge "$tmp/case/edited.json" "$tmp/case/base.json" "$tmp/case/one.record.json" two
s=$tmp/case/two.settings.json
check "$s" '[.hooks.UserPromptSubmit[].hooks[] | .timeout]' '[10,null,null]'
check "$tmp/case/two.kept.json" '[.[] | select(startswith("hooks.UserPromptSubmit") and test("30"))] | length' 1

begin "a hook group edited on the box survives a rerun"
fixtures
merge "$tmp/case/box.json" "$tmp/case/base.json" "$tmp/case/none.json" one
jq '.hooks.PreToolUse[0].hooks[0].timeout = 9' "$tmp/case/one.settings.json" >"$tmp/case/edited.json"
merge "$tmp/case/edited.json" "$tmp/case/base.json" "$tmp/case/one.record.json" two
check "$tmp/case/two.settings.json" '[.hooks.PreToolUse[].hooks[].timeout]' '[5,9]'

begin "permissions.ask is a union, and a box-only entry survives base adding and dropping entries"
fixtures
jq '.permissions.ask = ["Bash(box-only:*)", "Bash(push:*)"]' "$tmp/case/box.json" >"$tmp/case/box2.json"
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
check "$tmp/case/one.settings.json" .permissions.ask '["Bash(box-only:*)","Bash(push:*)","Bash(merge:*)"]'
check "$tmp/case/one.record.json" '.lists' '[{"path":["permissions","ask"],"entries":["Bash(push:*)","Bash(merge:*)"]}]'
with base2 '.permissions.ask = ["Bash(merge:*)", "Bash(new:*)"]'
merge "$tmp/case/one.settings.json" "$tmp/case/base2.json" "$tmp/case/one.record.json" two
check "$tmp/case/two.settings.json" .permissions.ask '["Bash(box-only:*)","Bash(merge:*)","Bash(new:*)"]'
check "$tmp/case/two.kept.json" . '[]'

begin "a base entry removed from the box's permissions.ask stays removed and is named"
fixtures
merge "$tmp/case/box.json" "$tmp/case/base.json" "$tmp/case/none.json" one
jq '.permissions.ask -= ["Bash(merge:*)"]' "$tmp/case/one.settings.json" >"$tmp/case/edited.json"
merge "$tmp/case/edited.json" "$tmp/case/base.json" "$tmp/case/one.record.json" two
check "$tmp/case/two.settings.json" .permissions.ask '["Bash(push:*)"]'
check "$tmp/case/two.kept.json" '[.[] | select(test("merge"))] | length' 1

begin "enabledPlugins takes only compound-engineering, and a box-enabled plugin stays"
fixtures
jq '.enabledPlugins = {"box-plugin@market": true}' "$tmp/case/box.json" >"$tmp/case/box2.json"
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
check "$tmp/case/one.settings.json" .enabledPlugins '{"box-plugin@market":true,"compound-engineering@compound-engineering-plugin":true}'

begin "enabledPlugins drops a base-removed plugin and keeps a box-enabled one"
fixtures
jq '.enabledPlugins = {"box-plugin@market": true}' "$tmp/case/box.json" >"$tmp/case/box2.json"
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
with base2 'del(.enabledPlugins["compound-engineering@compound-engineering-plugin"])'
merge "$tmp/case/one.settings.json" "$tmp/case/base2.json" "$tmp/case/one.record.json" two
check "$tmp/case/two.settings.json" .enabledPlugins '{"box-plugin@market":true}'

begin "a key that leaves the allowlist is removed when the box still holds the recorded value"
fixtures
merge "$tmp/case/box.json" "$tmp/case/base.json" "$tmp/case/none.json" one
jq '.values += [{"path": ["retiredKey"], "value": "old"}]' "$tmp/case/one.record.json" >"$tmp/case/record2.json"
jq '.retiredKey = "old" | .otherRetired = "box"' "$tmp/case/one.settings.json" >"$tmp/case/box2.json"
jq '.values += [{"path": ["otherRetired"], "value": "old"}]' "$tmp/case/record2.json" >"$tmp/case/record3.json"
with base2 '.retiredKey = "old" | .otherRetired = "old"'
merge "$tmp/case/box2.json" "$tmp/case/base2.json" "$tmp/case/record3.json" two
check "$tmp/case/two.settings.json" 'has("retiredKey")' false
check "$tmp/case/two.settings.json" .otherRetired '"box"'
check "$tmp/case/two.record.json" '[.values[].path[0] | select(. == "retiredKey" or . == "otherRetired")]' '[]'

begin "the box merge keeps hooks without a command and lookalike commands"
fixtures
cat >"$tmp/case/box2.json" <<'EOF'
{"hooks": {"Stop": [
  {"matcher": "", "hooks": [{"type": "prompt", "prompt": "check"}]},
  {"matcher": "", "hooks": [{"type": "command", "command": "/x/service-sync-notify"}]},
  {"matcher": "", "hooks": [{"type": "command", "command": "/x/not-ce-sync hook-stop"}]}
]}}
EOF
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
check "$tmp/case/one.settings.json" '[.hooks.Stop[].hooks[] | .command // .type]' '["~/.claude/hooks/peon-ping/peon.sh","~/scripts/ce-sync hook-stop","prompt","/x/service-sync-notify","/x/not-ce-sync hook-stop"]'

begin "a rerun on its own output with its own record changes nothing"
fixtures
jq '.effortLevel = "high" | .permissions.ask = ["Bash(box-only:*)"] | .enabledPlugins = {"box-plugin@market": true}' \
	"$tmp/case/box.json" >"$tmp/case/box2.json"
merge "$tmp/case/box2.json" "$tmp/case/base.json" "$tmp/case/none.json" one
merge "$tmp/case/one.settings.json" "$tmp/case/base.json" "$tmp/case/one.record.json" two
cmp -s "$tmp/case/one.settings.json" "$tmp/case/two.settings.json" || fail "settings changed: $(diff "$tmp/case/one.settings.json" "$tmp/case/two.settings.json")"
cmp -s "$tmp/case/one.record.json" "$tmp/case/two.record.json" || fail "record changed: $(diff "$tmp/case/one.record.json" "$tmp/case/two.record.json")"

begin "the real base on a box-shaped file adds no tui, credentials or extra plugins"
fixtures
merge "$tmp/case/box.json" "$here/settings.base.json" "$tmp/case/none.json" one
s=$tmp/case/one.settings.json
check "$s" 'has("tui")' false
check "$s" .apiKeyHelper '"box-helper"'
check "$s" .env '{"BOX_KEY":"1","PEON_PLATFORM":"ssh"}'
check "$s" .idleCompaction true
check "$s" '.enabledPlugins | keys' '["compound-engineering@compound-engineering-plugin"]'
box_groups_last "$s"
check "$s" '[.hooks[][] | select(any(.hooks[]; .command | test("ce-sync")))] | length > 0' true
merge "$s" "$here/settings.base.json" "$tmp/case/one.record.json" two
cmp -s "$s" "$tmp/case/two.settings.json" || fail "a rerun changed settings"

if ((failures)); then
	echo "$failures failure(s)"
	exit 1
fi
echo "all passed"
