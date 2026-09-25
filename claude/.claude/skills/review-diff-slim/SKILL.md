---
name: review-diff-slim
description: Lightweight single-pass review of branch changes vs a base (default trunk/origin/main) in jj/git. No parallel orchestration. Cheaper than review-diff; use for small branch diffs or fast reads. Pass an optional branch/bookmark as the argument to diff against instead.
disable-model-invocation: true
context: fork
agent: review-slim
allowed-tools: Bash Read Grep Glob
---

# Review Branch Diff (slim)

Single-pass review of branch changes vs a base, run as the `review-slim` agent — no parallel agents, no validator. Your `review-slim` instructions own the rubric: coverage areas, `[c:NN s:LVL]` scoring, the pre-existing filter, subsumption, and Suggestion verdicts. Don't restate them. This skill adds only the diff source, the no-op guard, the skip-noise list, and the output format below.

## Diff

Both branches exclude the working copy to match `git diff <base>...HEAD`. If an argument was provided (`$ARGUMENTS`), it overrides the default base — a jj revset/bookmark or a git revision. Empty falls back to `trunk()` / `origin/main`.

```
!`BASE="$ARGUMENTS"; if [ -d .jj ]; then jj diff --no-pager --from "fork_point(${BASE:-trunk()} | @-)" --to '@-'; else git --no-pager diff "${BASE:-origin/main}...HEAD"; fi`
```

## No-op guard

After capturing the diff, if it is empty, purely whitespace/comment-only, or touches only skip-noise paths → output the format block with all categories as "None." and Overall: "Trivial diff." Stop.

## Skip-noise

Strip these and list once as `Skipped: <path>`: `vendor/`, `node_modules/`, generated (`*.pb.go`, `*_generated.*`, `*.gen.go`, `dist/`, `build/`, `.next/`), lockfiles (`go.sum`, `yarn.lock`, `package-lock.json`, `pnpm-lock.yaml`, `Cargo.lock`, `Gemfile.lock`), minified, binary.

## Output

Aggregate findings into a single review. Map each `[c:NN s:LVL]` per matrix:

| Confidence | Severity | Bucket |
|------------|----------|--------|
| 76+ | high | **Critical** |
| 76+ | med | Important |
| 76+ | low | Suggestions |
| 51–75 | high | Important |
| 51–75 | med | Important |
| 51–75 | low | Suggestions |
| 26–50 | any | Suggestions |
| 0–25 | any | suppressed (unless `[pre-existing]` high → Important) |

1. **Critical** (must fix): per matrix.
2. **Important** (should fix): per matrix.
3. **Suggestions** (nice to have): per matrix — each marked with its `do` / `opportunistic` / `skip` verdict.
4. **Positive observations**: what's well done.

End with a brief overall assessment.
