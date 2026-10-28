# Replaces a box's ce-sync hooks with those in settings.base.json (passed as $base), ahead of the box's own,
# which its hook updater expects to stay last.
def ce_sync: (.command // "") | test("(^|/)ce-sync( |$)");
def keep(f): map(.hooks |= map(select(f))) | map(select(.hooks != []));

(.hooks // {} | with_entries(.value |= keep(ce_sync | not))) as $theirs
| .hooks = reduce ($base[0].hooks | to_entries[]) as $e ($theirs;
	($e.value | keep(ce_sync)) as $ours
	| if $ours == [] then . else .[$e.key] = $ours + (.[$e.key] // []) end)
| .hooks |= with_entries(select(.value != []))
