---
name: review-pr-clean
description: Remove the isolated PR-review checkouts (sibling ../.pr-review-* dirs) left behind by /review-pr — handles both git worktrees and jj workspaces, dropping the directory and its VCS registration. Pass "dry" to preview without deleting. Run from inside the target repo.
disable-model-invocation: true
allowed-tools: Bash
---

# Clean up /review-pr checkouts

`/review-pr` deliberately never tears down its isolated checkouts: each lives as a sibling directory `../.pr-review-<slug>` plus a registered git worktree or jj workspace. They accumulate. This removes all of them for the current repo, dropping **both** the directory and its VCS registration.

`$ARGUMENTS`: pass `dry` (or `list` / `-n`) to preview what would be removed without deleting. Empty = remove.

Both branches are driven off the VCS registry (`git worktree list` / `jj workspace list`) rather than a filesystem glob, and identify the skill's checkouts by the `.pr-review-` directory-name prefix so they never touch a worktree/workspace you created by hand.

Run this once via Bash from inside the target repo (it resolves the repo root and VCS itself), then report what was removed:

```bash
case "$ARGUMENTS" in dry|list|-n|--dry-run) DRY=1;; *) DRY=0;; esac
set -eu
if jj root >/dev/null 2>&1; then
  root=$(jj root); vcs=jj
elif root=$(git rev-parse --show-toplevel 2>/dev/null); then
  vcs=git
else
  echo "Not inside a jj or git repo — cd into the repo first."; exit 1
fi
found=0
if [ "$vcs" = jj ]; then
  # NB: don't name the path var `path` — in zsh it is tied to $PATH.
  while IFS= read -r ws; do
    [ -n "$ws" ] || continue
    if [ "$ws" = default ]; then continue; fi
    wsroot=$(jj -R "$root" workspace root --name "$ws" 2>/dev/null) || continue
    case "$(basename "$wsroot")" in .pr-review-*) ;; *) continue ;; esac
    found=$((found + 1))
    if [ "$DRY" = 1 ]; then echo "would remove (jj): $ws -> $wsroot"; continue; fi
    jj -R "$root" workspace forget "$ws" 2>/dev/null || true
    rm -rf "$wsroot"; echo "removed jj workspace: $ws ($wsroot)"
  done <<EOF
$(jj -R "$root" workspace list -T 'name ++ "\n"')
EOF
else
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    case "$(basename "$d")" in .pr-review-*) ;; *) continue ;; esac
    found=$((found + 1))
    if [ "$DRY" = 1 ]; then echo "would remove (git): $d"; continue; fi
    git -C "$root" worktree remove --force "$d" 2>/dev/null || rm -rf "$d"
    echo "removed git worktree: $d"
  done <<EOF
$(git -C "$root" worktree list --porcelain | sed -n 's/^worktree //p')
EOF
  if [ "$DRY" = 0 ]; then git -C "$root" worktree prune; fi
fi
if [ "$found" -eq 0 ]; then echo "No .pr-review-* checkouts found for $root."; fi
```

Report the list of removed (or would-remove) checkouts back to the user. Only act on directories whose basename starts with `.pr-review-`.

**Orphan note:** if a checkout's *directory* was deleted by hand but its registration remains:
- **git** — `git worktree list` still reports the path (with the prefix), so this cleans it, and the trailing `git worktree prune` mops up anything left.
- **jj** — `jj workspace root --name` errors once the directory is gone and the workspace name is just the branch slug (no `.pr-review-` marker), so an orphaned jj registration can't be safely identified here. It's harmless and jj de-stales it on next use; forget it explicitly with `jj workspace forget <name>` if needed.
