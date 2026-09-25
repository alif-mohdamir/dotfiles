---
name: review-wc-slim
description: Lightweight single-pass review of uncommitted working copy changes (jj/git). No parallel orchestration. Cheaper than review-wc; use for small diffs or fast reads.
disable-model-invocation: false
context: fork
agent: review-slim
allowed-tools: Bash Read Grep Glob
---

# Review Working Copy (slim)

Single-pass review of uncommitted changes, run as the `review-slim` agent — no parallel agents, no validator. Your `review-slim` instructions own the rubric: coverage areas, `[c:NN s:LVL]` scoring, the pre-existing filter, subsumption, and Suggestion verdicts. Don't restate them. This skill adds only the diff source, the no-op guard, the skip-noise list, and the output format below.

## Diff

Git branch covers staged + unstaged + untracked to match `jj diff`:

```
!`if [ -d .jj ]; then jj diff --no-pager; else git --no-pager diff HEAD; git ls-files --others --exclude-standard | while read -r f; do git --no-pager diff --no-index -- /dev/null "$f" || true; done; fi`
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
