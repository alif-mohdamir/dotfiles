# Replaces a box's ce-sync hooks with those in settings.base.json (passed as $base), ahead of the box's own,
# which its hook updater expects to stay last.
def ce_sync: .command | test("ce-sync");

(.hooks // {} | with_entries(.value |= (map(.hooks |= map(select(ce_sync | not))) | map(select(.hooks != []))))) as $theirs
| .hooks = reduce ($base[0].hooks | to_entries[]) as $e ($theirs;
	($e.value | map(.hooks |= map(select(ce_sync))) | map(select(.hooks != []))) as $ours
	| if $ours == [] then . else .[$e.key] = $ours + (.[$e.key] // []) end)
| .hooks |= with_entries(select(.value != []))
