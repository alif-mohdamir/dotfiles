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

## Finding local repos

`$LOCAL_WORKSPACES` holds a space-separated list of directories that contain my repos.
Use it when a task spans repos rather than guessing paths.

- The shell is zsh: unquoted `$LOCAL_WORKSPACES` does not word-split. Use `${=LOCAL_WORKSPACES}`.
- Entries may contain a literal `~`; expand it (`${w/#\~/$HOME}`) before testing the path.
- Entries can overlap, so the same repo may appear more than once. Deduplicate before acting.
