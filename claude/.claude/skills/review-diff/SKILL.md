---
name: review-diff
description: Review code changes on the current branch compared to a base (default trunk/origin/main). Detects jj vs git automatically. Pass an optional branch/bookmark as the argument to diff against instead.
disable-model-invocation: false
allowed-tools: Agent Bash Read Grep Glob
---

# Review Code Diff

Orchestrate a code review of the branch diff via parallel sub-agents and a validator. Bugs
& Logic and Generalist always run; Security and Test Coverage run only when triage detects
signal.

**Read `~/.claude/review-pipeline.md` now** and run its stages against the diff below. This
file supplies only what is specific to reviewing a branch diff.

## Diff

Capture the diff. `$ARGUMENTS`, if given, overrides the default base: a jj revset/bookmark
(`main@origin`, `my-feature`) or git revision (`origin/develop`, `feature-x`). Empty falls
back to `trunk()` / `origin/main`.

```
!`BASE="$ARGUMENTS"; if [ -d .jj ]; then jj diff --no-pager --from "fork_point(${BASE:-trunk()} | @-)" --to '@-'; else git --no-pager diff "${BASE:-origin/main}...HEAD"; fi`
```

## Slim target

Invoke the `review-diff-slim` skill and stop.

## Overrides

None. Reads target the current working copy, and no change description accompanies the
diff, so skip the parts of Triage and Aggregation that compare the diff against one.
