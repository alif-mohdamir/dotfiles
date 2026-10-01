---
name: review-pr
description: Review a GitHub pull request using the gh CLI for both the diff and the PR description as context. Requires a PR number, URL, or branch as the argument. Orchestrates parallel sub-agents plus a validator, same pipeline as review-diff.
disable-model-invocation: true
allowed-tools: Agent AskUserQuestion Bash Read Grep Glob mcp__claude_ai_Atlassian_Rovo__getJiraIssue
---

# Review Pull Request

Orchestrate a code review of a GitHub PR via parallel sub-agents and a validator. Diff and
description come from `gh`. Bugs & Logic and Generalist always run; Security and Test
Coverage run only when triage detects signal.

**Read `~/.claude/review-pipeline.md` now** and run its stages against the diff below. This
file supplies only what is specific to reviewing a PR: resolving it, checking out its head,
and the overrides that follow from reading a tree other than the working copy.

`$ARGUMENTS` optionally names the PR: number, URL, or branch (`1234`, a PR URL,
`my-feature`). Empty resolves to the current branch's PR. If the **PR metadata** block below
prints `NO_PR_FOUND` (no argument and no current-branch PR, for example a detached HEAD),
**prompt** instead of aborting: run `gh pr list --limit 20`, then `AskUserQuestion` which PR
to review (one option per listed PR; the built-in free-text choice covers any other
number/URL/branch). Re-run **PR metadata** and **Diff** via Bash with the chosen ref, then
continue with it in place of `$ARGUMENTS`.

## PR metadata

One `gh pr view` call: description (context) plus the head/merge fields the checkout needs
(`number`, `headRefName`, `headRefOid`, `mergeStateStatus`).

```
!`gh pr view $ARGUMENTS --json number,title,author,baseRefName,headRefName,headRefOid,mergeable,mergeStateStatus,body --jq '"PR #\(.number): \(.title)\nAuthor: \(.author.login)\nBase: \(.baseRefName)  ←  Head: \(.headRefName) (\(.headRefOid))\nMergeable: \(.mergeable)  State: \(.mergeStateStatus)\n\nDescription:\n\(.body)"' 2>/dev/null || echo NO_PR_FOUND`
```

The description is the **change description** the pipeline's Triage and Aggregation stages
refer to.

## Linked tickets

Collect the tickets the PR links, from two sources:

- **GitHub issues**: the PR's `closingIssuesReferences`, plus any `github.com/.../issues/N`
  URL in the description. Fetch each with
  `gh issue view N --repo OWNER/REPO --json title,body,comments`.
- **Jira issues**: a key in a `*.atlassian.net/browse/KEY` URL, a key opening the PR title
  (`ABC-123: ...`), or a key on a description line that marks an issue link (`Resolves:`,
  `Fixes:`, `Closes:`, `Related:`). Ignore bare `ABC-123` tokens elsewhere: `SHA-256` and
  `UTF-8` match the same shape. Fetch each with an Atlassian `getJiraIssue` tool, such as
  `mcp__claude_ai_Atlassian_Rovo__getJiraIssue` (`fields: ["description", "comment"]`,
  `responseContentFormat: "markdown"`). If no such tool is in your tool list, skip the Jira
  keys and record which ones you skipped.

From each ticket's description and comments, pull out every instruction about this change
(where code or tests go, names, what to drop or keep), with its author and a link or comment
id. These are the pipeline's **recorded decisions**.

If nothing is linked, record `Recorded decisions: none linked` in triage. Record a failed
fetch or a skipped key in triage and continue. Do not treat that gap as a clean result.

## Diff

```
!`gh pr diff $ARGUMENTS 2>/dev/null || echo NO_PR_FOUND`
```

## VCS

Probed jj-first (colocated repos have both `.jj` and `.git`):

```
!`jj root >/dev/null 2>&1 && echo jj || echo git`
```

## Isolated checkout (review root)

Create this before the size gate so both slim and full paths read from it. Check the PR head
into an isolated worktree/workspace (per **VCS**) so reads never hit a diverged working
copy. The **review root** is its absolute path (`dir`); all Read/Grep/Glob/blame target it.
**Persistent**: reuse if it exists, create if not, never tear down. Set `repo` (the repo
root's directory name), `slug`, `dir` (`../.pr-review-$repo-$slug`), `number`, and
`headRefName` from **PR metadata** (forks: use `headRefOid` for `headRefName`). The `$repo`
segment disambiguates checkouts from different repos that land as siblings of the same
parent directory.

**git**:
```bash
repo=$(basename "$(git rev-parse --show-toplevel)")
slug=${headRefName//\//-}; dir="../.pr-review-$repo-$slug"
git fetch origin "pull/$number/head"
if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$dir" checkout --detach FETCH_HEAD          # reuse
else
  git worktree prune; rm -rf "$dir"                    # clear stale
  git worktree add --detach "$dir" FETCH_HEAD
fi
```

**jj**:
```bash
repo=$(basename "$(jj root)")
slug=${headRefName//\//-}; dir="../.pr-review-$repo-$slug"
jj git fetch
if jj workspace list | grep -q "^$slug:"; then
  jj -R "$dir" workspace update-stale 2>/dev/null      # de-stale
  jj -R "$dir" new "$headRefName@origin"               # jj snapshots into @; edit would let review-time writes amend the PR commit
else
  jj workspace add --name "$slug" -r "$headRefName@origin" "$dir"
fi
```

If creation fails, fall back to the working copy as review root and flag that reads reflect
it, not the PR head. Flag `mergeStateStatus` too (`CONFLICTING`/`DIRTY` means the head is
stale against base).

## Slim target

Launch the `review-slim` agent (`subagent_type: review-slim`) with the pruned PR diff, the
PR description, and the review root. Apply the **Overrides** below to it as well, format per
the pipeline's Aggregation stage, then stop. Do **not** invoke the `review-diff-slim` skill:
it recomputes a local branch diff against the working copy, not the PR head.

## Overrides

These apply to every sub-agent, the slim agent, and the validator. Pass them along verbatim.

- **Read from the review root**, never the user's working copy. All Read/Grep/Glob and all
  blame target it, and verification confirms each issue at the PR head.
- In a jj review root, `git` is blocked. Blame with `jj file annotate FILE` (no revset),
  never `git blame`.
- **The PR description is intent, not proof.** Verify behavior against the diff and source.
  A gap between what the diff does and what the description claims is itself a finding.

## Workspace persistence

Leave the isolated checkout in place, never tear it down. Later runs reuse and refresh it
per **Isolated checkout (review root)**. The `review-pr-clean` skill removes them.
