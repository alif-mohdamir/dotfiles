---
name: conventional-comments
description: Format PR review comments in the Conventional Comments format. Use when drafting any PR review comment, inline comment, pending review, or thread reply, including when turning review-pipeline findings into comments to post or hand over.
---

# Conventional Comments

When to post versus hand over a draft is set in `~/.claude/CLAUDE.md` ("Commits and pull
requests"); this skill covers only the comment text.

## Shape

```
**<label> (<decorations>):** <subject>

<discussion>
```

The subject is the finding in one sentence. The discussion, when needed, gives the reason,
the location if the comment isn't inline, and what to change. Put code changes in a GitHub
`suggestion` block when the fix is a direct replacement.

The bolded label counts as structure under the prose rules, the same as a heading. Bold
nothing else.

## Labels

| Label | Use for |
|-------|---------|
| `praise` | Something specific done well. Skip generic praise. |
| `nitpick` | A trivial, preference-based request. Always non-blocking. |
| `suggestion` | A proposed improvement. Say what to change and why it is better. |
| `issue` | A specific problem. Pair it with a `suggestion` block or a fix when you have one. |
| `todo` | A small, necessary change. |
| `question` | A real concern you can't resolve from the code. Never a rhetorical question. |
| `thought` | An idea the review raised. Non-blocking. |
| `chore` | A process task required before merge (changelog, generated code, ticket link). |
| `note` | Context the reader should know. Always non-blocking. |
| `typo` | A misspelling. |
| `polish` | Correct content that could be improved right away. |

Don't use `quibble`; it calls for humor, which the prose rules don't leave room for.

## Decorations

- `blocking`: the PR should not merge until this is resolved.
- `non-blocking`: the author may merge without addressing it.
- `if-minor`: address it only if the change turns out small.
- A topic decoration may follow, such as `security`, `a11y`, `perf`, `tests`, or
  `pre-existing`: `**issue (blocking, security):**`.

Mark `issue`, `suggestion`, `todo`, and `chore` with `blocking` or `non-blocking` every time,
so the author never has to guess which one you meant.

## Mapping review-pipeline buckets

The buckets come from the Aggregation stage of `~/.claude/review-pipeline.md`.

| Bucket | Comment |
|--------|---------|
| Critical | `issue (blocking)` |
| Important, a defect | `issue (blocking)` if you would request changes over it, else `issue (non-blocking)` |
| Important, an improvement | `suggestion (non-blocking)` |
| Suggestion, verdict `do` | `suggestion (non-blocking)`, or `nitpick` for preference |
| Suggestion, verdict `opportunistic` | `suggestion (if-minor)` |
| Suggestion, verdict `skip` | Don't post. |
| `[pre-existing]` high | `issue (non-blocking, pre-existing)`, saying it predates this PR |
| Positive observation | `praise`, only when it names something specific |

## Examples

```
**issue (blocking):** `parseLimit` returns 0 for an empty string, so `?limit=` disables pagination.

Return the default limit when the param is empty, and add a case for it in `parse_test.go`.
```

```
**nitpick (non-blocking):** `cfg` reads better as `config` here, matching the rest of the package.
```

```
**question (non-blocking):** Does the cache key need the environment ID? Two environments in one project would share entries as written.
```
