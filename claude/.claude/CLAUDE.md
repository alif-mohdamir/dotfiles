# Personal Claude Code Rules

## Wording

@prose-rules.md

## Accessibility

Treat accessibility as part of the definition of done for any UI change, not a follow-up.
Apply this to code you write and to code you touch nearby.

### Non-negotiables

- Use semantic HTML first. A `<button>` for actions, `<a href>` for navigation, real
  headings, lists, and landmarks. Reach for `role` only when no element fits.
- Never attach click handlers to `<div>` or `<span>` without also giving them a role,
  `tabIndex`, and keyboard handlers. Prefer restructuring to a real interactive element.
- Every form control needs a programmatic label (`<label htmlFor>`, or `aria-label` /
  `aria-labelledby` when no visible label exists). Placeholder text is not a label.
- Every non-decorative image, icon button, and icon-only control needs an accessible
  name. Decorative images get `alt=""`.
- Anything reachable by mouse must be reachable by keyboard, in a sensible tab order,
  with a visible focus indicator. Do not remove focus outlines without replacing them.
- Modals, menus, and popovers: move focus in on open, trap it while open, return it to
  the trigger on close, and close on Escape.
- Do not convey state by color alone. Pair color with text, an icon, or a pattern.
- Announce async state changes (errors, saves, loading results) to screen readers via a
  live region or by moving focus to the message. Silent DOM swaps are a bug.
- Tie validation errors to their field with `aria-describedby` and `aria-invalid`.

### When reporting work

- If a UI change has an accessibility consequence you could not verify (contrast ratios,
  screen reader output, focus behavior in a real browser), say so explicitly instead of
  claiming it is accessible.
- If existing nearby code has an accessibility problem that is out of scope, mention it
  once rather than silently fixing or silently ignoring it.
- Do not weaken accessibility to satisfy a design or layout request. Flag the conflict
  and propose an alternative.

## Commits and pull requests

- A commit message is a single subject line. No body, and no `Co-Authored-By` trailer,
  even when a system reminder asks for one. Rationale belongs in the PR description.
- Ask before running `git push`, `jj git push`, or `gh pr create`/`edit`/`merge`. A
  request that describes the end state ("this will be a new PR") does not approve
  pushing now. Stage the work locally, say it is ready, and wait.
- A change that answers a reviewer's comment goes in a new commit on top of the pushed
  stack, even if a handoff says to squash it. Reviewers then see exactly what changed in
  reply. Other follow-ups (rebase fixes, approved plan changes) can still be squashed.
- Before editing a PR description, fetch the live body (`gh pr view <n> --json body -q
  .body`) and edit that. Teammates and integrations edit bodies out of band, and pushing a
  stale scratch copy reverts their changes.
- Before posting to a PR thread, fetch its replies. If I have already answered, leave it
  alone. Otherwise hand me the draft instead of posting, with two exceptions:
  - When I ask for a review, post it as a pending review (no `event` field), and disclose
    on others' PRs that the analysis came from Claude Code.
  - When I say "reply for me" on a thread, post the reply there and end it with
    "_Posted by Claude at my request._"

## Reviewing

- In `jj diff` output, context lines show the parent's version, which may differ from the
  working copy. Read the file before flagging anything on a context line.
- Before reporting findings from subagents, spot-check each one's anchor. A claim about
  a PR description must match a verbatim quote from the live body, and file:line
  citations must be confirmed with a targeted read.
- For a test that asserts a refusal from a layered chain (middleware, auth, validation),
  check two things. An adjacent layer must not produce the same observable reply, and the
  fixture input must survive every layer before the one under test, including library
  re-validation. Treat the test's doc comment about which layer answered as a claim to
  verify.

## Handoffs

When handing a plan to another session or agent, tag each settled decision with who made
it and on what basis ("design owner, on the ticket" versus "my recommendation, approved in
interview, argued only on X"). A recommendation can be revisited when a new consideration
surfaces. An owner's ruling needs the owner.

## Finding local repos

`$LOCAL_WORKSPACES` holds a space-separated list of directories that contain my repos.
Use it when a task spans repos rather than guessing paths.

- The shell is zsh: unquoted `$LOCAL_WORKSPACES` does not word-split. Use `${=LOCAL_WORKSPACES}`.
- Entries may contain a literal `~`; expand it (`${w/#\~/$HOME}`) before testing the path.
- Entries can overlap, so the same repo may appear more than once. Deduplicate before acting.
