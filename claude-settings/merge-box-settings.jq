# Merges the allowlisted part of settings.base.json (passed as $base) into a box's own settings.json.
# $record holds what the previous run applied, or null on a first run. Emits {settings, record, kept}.

def allowlist: [
	["statusLine"], ["outputStyle"], ["permissions", "defaultMode"], ["skipAutoPermissionPrompt"],
	["skillOverrides"], ["effortLevel"], ["feedbackDrafts"], ["theme"], ["model"], ["extraKnownMarketplaces"],
	["enabledPlugins", "compound-engineering@compound-engineering-plugin"]
];
# Owned one entry at a time, so a box-only entry never freezes base's entries.
def list_allowlist: [["permissions", "ask"]];
# The box writes its own credentials into env and apiKeyHelper, and tui: fullscreen is untested there.
def excluded: [["env"], ["apiKeyHelper"], ["tui"]];

def owned: map(. as $p | select(any(excluded[]; . == $p[:length]) | not));
# {v: value} when the path is present, null when absent, so a stored null still counts as present.
def value_at($p):
	if ($p | length) == 1 then (if type == "object" and has($p[0]) then {v: .[$p[0]]} else null end)
	else (if type == "object" then .[$p[0]] else null end) | value_at($p[1:]) end;
def has_entry($e): any(.[]; . == $e);
def ce_sync: (.command // "") | test("(^|/)ce-sync( |$)");
def peon: (.command // "") | contains("/hooks/peon-ping/");

$base[0] as $b
| $record[0] as $r
| (allowlist | owned) as $paths
| (list_allowlist | owned) as $lists
| {settings: ., record: {values: [], lists: [], hooks: {}}, kept: []}

| reduce ($paths + ([$r.values[]?.path] - $paths))[] as $p (.;
	(.settings | value_at($p)) as $box
	| (if $paths | has_entry($p) then $b | value_at($p) else null end) as $new
	| ([$r.values[]? | select(.path == $p) | {v: .value}][0]) as $applied
	| if $box == $new or ($r == null and $box == null) or ($r != null and $box == $applied) then
		if $new == null then .settings |= delpaths([$p])
		else .settings |= setpath($p; $new.v) | .record.values += [{path: $p, value: $new.v}] end
	else .kept += [$p | join(".")] end)

| reduce ($lists + ([$r.lists[]?.path] - $lists))[] as $p (.;
	(.settings | value_at($p)) as $present
	| ($present.v // []) as $box
	| (if $lists | has_entry($p) then $b | value_at($p) | .v // [] else [] end) as $new
	| (if $r == null then null else [$r.lists[]? | select(.path == $p) | .entries][0] // [] end) as $applied
	| (reduce ($new + (($applied // []) - $new))[] as $e ({list: $box, entries: [], kept: []};
		($box | has_entry($e)) as $on
		| ($new | has_entry($e)) as $want
		| if $on == $want or ($applied == null and ($on | not)) or ($applied != null and $on == ($applied | has_entry($e))) then
			if $want then (if $on then . else .list += [$e] end) | .entries += [$e]
			else .list -= [$e] end
		else .kept += ["\($p | join(".")) \($e | tojson)"] end)) as $m
	| if $present != null or $m.list != [] then .settings |= setpath($p; $m.list) else . end
	| if $m.entries != [] then .record.lists += [{path: $p, entries: $m.entries}] else . end
	| .kept += $m.kept)

| ($b.hooks // {}) as $new
| ($r.hooks // {}) as $applied
| reduce (.settings.hooks // {} | to_entries[]) as $ev (. + {own: {}};
	reduce $ev.value[] as $g (.;
		if any(($applied[$ev.key] // [])[], ($new[$ev.key] // [])[]; . == $g) then .
		# peon's own installer writes absolute paths and base writes ~/, so only a ~/ group can be an edit worth naming
		elif any(($g.hooks // [])[]; peon) then
			if any(($g.hooks // [])[]; peon and (.command | startswith("~/"))) then .kept += ["hooks.\($ev.key) group removed: \($g | tojson)"] else . end
		else ($g | .hooks = ((.hooks // []) | map(select(ce_sync | not)))) as $k
			| if $k.hooks == [] then .kept += ["hooks.\($ev.key) group removed: \($g | tojson)"]
			else .own[$ev.key] += [$k] end
		end))
| .own as $own
| (reduce ($new | to_entries[]) as $e ($own; .[$e.key] = $e.value + (.[$e.key] // []))
	| with_entries(select(.value != []))) as $hooks
| if .settings.hooks != null or $hooks != {} then .settings.hooks = $hooks else . end
| .record.hooks = ($new | with_entries(select(.value != [])))
| del(.own)

# peon sends to the laptop relay only under SSH or with this set, and agent panes are not SSH sessions.
# It is the box's key from then on: never recorded, so never removed.
| .settings |= (if (.env | type) == "object" and (.env | has("PEON_PLATFORM")) then . else .env.PEON_PLATFORM = "ssh" end)
