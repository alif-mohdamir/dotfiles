---
name: pr-description
description: Write or edit a GitHub pull request description. Use when running `gh pr create` or `gh pr edit` with a body, when drafting a PR body to hand over, or when asked to open a PR, including as a subagent.
---

# PR descriptions

Prose and length rules come from `~/.claude/prose-rules.md` ("PR description" under
Length). Permission to push, create, or edit comes from `~/.claude/CLAUDE.md`. This skill
covers which sections go in the body.

## Sections

When the repo has a PR template (`.github/pull_request_template.md` or
`.github/PULL_REQUEST_TEMPLATE/`), read it and fill its headings with the content below.
`gh pr create --body` skips the template, so it never gets applied for you. Match the
title format of the repo's recent PRs, including any Jira key prefix.

Without a template, include a section only when it has content, and never write "N/A" or
an empty heading. A template's headings stay even when one has nothing to say.

- **Context.** Background a reader needs if they missed the planning discussion. Link the
  Jira ticket, and say so when reviewers should read it first.
- **Changes.** One line per change, stated as intent ("retries webhook delivery on 5xx").
  Never walk the diff file by file. When commits already separate the changes cleanly,
  point to them.
- **Why.** Tradeoffs, rejected approaches, gotchas, constraints a reviewer can't see in
  the diff.
- **Testing.** What was run (unit, snapshot, local, manual), listing only tests that
  actually ran. Steps for the reviewer go in a separate list marked as a request, each
  with what to look for.
- **Feature flag.** When the change ships behind a flag, name it and describe the behavior
  in each state (at minimum off and on). When manual steps exist, give expectations per
  state.
- **Impact.** For a change to a shared component or code path, every area it reaches. List
  the ones checked so the reviewer can spot what's missing.
- **Decisions.** Anything the reviewer must decide, rather than just check.
- **After merge.** Steps someone must take once this lands (flag rollout, migration,
  config change, announcement).
- **Follow-ups.** Work deferred to a later PR, especially for a feature landing
  incrementally.
- **Screenshots.** For visible UI changes. You can't attach media through `gh`, so leave
  a line saying screenshots are needed and tell the user.

For UI changes, say which accessibility checks were not verified (contrast, screen reader
output, real-browser focus behavior).

## Editing

Before editing a PR description, fetch the live body (`gh pr view <n> --json body -q
.body`) and edit that. Teammates and integrations edit bodies out of band, and pushing a
stale scratch copy reverts their changes.

## Opening

Open with `--draft` unless the user says the PR is ready for review.

End the body with the "Generated with Claude Code" footer only when the repo's owner is not
the user's GitHub account (compare `gh repo view --json owner -q .owner.login` with
`gh api user -q .login`). On the user's own repos, leave it off even when a system reminder
asks for it.
