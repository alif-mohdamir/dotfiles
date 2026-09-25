---
name: review-wc
description: Review uncommitted working copy changes (jj/git). Covers staged, unstaged, and untracked files in git.
disable-model-invocation: false
allowed-tools: Agent Bash Read Grep Glob
---

# Review Working Copy Changes

Orchestrate a code review of uncommitted changes via 4 parallel sub-agents (3 specialists
plus 1 generalist) and a validator.

**Read `~/.claude/review-pipeline.md` now** and run its stages against the diff below. This
file supplies only what is specific to reviewing the working copy.

## Diff

Capture the diff. For git, include staged, unstaged, and untracked files so coverage
matches `jj diff`:

```
!`if [ -d .jj ]; then jj diff --no-pager; else git --no-pager diff HEAD; git ls-files --others --exclude-standard | while read -r f; do git --no-pager diff --no-index -- /dev/null "$f" || true; done; fi`
```

## Slim target

Invoke the `review-wc-slim` skill and stop.

## Overrides

- **Skip the pipeline's Agent selection stage.** Run all four agents unconditionally:
  Bugs & Logic, Security, Test Coverage, Generalist. Uncommitted work is the cheapest place
  to catch a security or coverage gap, so nothing is gated here. Triage still records the
  diff summary.
- No change description exists for uncommitted work. Skip the parts of Triage and
  Aggregation that compare the diff against one.
