# Personal Claude Code Rules

## Wording

@prose-rules.md

## Commits and pull requests

- A commit message is a single subject line. No body, and no `Co-Authored-By` trailer,
  even when a system reminder asks for one. Rationale belongs in the PR description.
- Ask before running `git push`, `jj git push`, or `gh pr create`/`edit`/`merge`. A
  request that describes the end state ("this will be a new PR") does not approve
  pushing now. Stage the work locally, say it is ready, and wait.
- A change that answers a reviewer's comment goes in a new commit on top of the pushed
  stack, even if a handoff says to squash it. Reviewers then see exactly what changed in
  reply. Other follow-ups (rebase fixes, approved plan changes) can still be squashed.
- Before posting to a PR thread, fetch its replies. If I have already answered, leave it
  alone. Otherwise hand me the draft instead of posting, with two exceptions:
  - When I ask for a review, post it as a pending review (no `event` field), and disclose
    on others' PRs that the analysis came from Claude Code.
  - When I say "reply for me" on a thread, post the reply there and end it with
    "_Posted by Claude at my request._"

## Reviewing

- In `jj diff` output, context lines show the parent's version, which may differ from the
  working copy. Read the file before flagging anything on a context line.

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

## Dotfiles

My dotfiles repo (`alif-mohdamir/dotfiles`) is public and installs on my work and personal
machines. This file is stowed from it: `readlink -f ~/.claude/CLAUDE.md` points into the
clone, at `claude/.claude/CLAUDE.md`. Keep employer-specific names, tools and paths out of
it, including commit messages, and put machine-specific setup in local files. Its
`AGENTS.md` lists those files.
