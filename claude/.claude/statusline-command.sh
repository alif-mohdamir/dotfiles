#!/usr/bin/env bash
# Claude Code status line — mirrors key Starship prompt elements

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
model=$(echo "$input" | jq -r '.model.display_name // ""')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Shorten the directory: replace $HOME with ~
home="$HOME"
short_dir="${cwd/#$home/~}"

# jj VCS info (--ignore-working-copy avoids expensive snapshotting on each call)
jj_info=""
if command -v jj >/dev/null 2>&1 && jj -R "$cwd" root >/dev/null 2>&1; then
  jj_flags=(--ignore-working-copy -R "$cwd" --no-pager)

  # Bookmark + dirty + unpushed in a single template evaluation
  jj_bookmark=$(jj "${jj_flags[@]}" log --no-graph -r @ -T 'bookmarks' 2>/dev/null | head -1 | tr -d '[:space:]')

  # Dirty check: compare @ tree against parent. Non-empty diff means uncommitted changes.
  jj_dirty=""
  if jj "${jj_flags[@]}" diff --summary 2>/dev/null | grep -q .; then
    jj_dirty="*"
  fi

  # Unpushed: check if any of our bookmarks are ahead of their remote tracking branch
  jj_unpushed=""
  if jj "${jj_flags[@]}" log --no-graph -r 'bookmarks() & mine() & remote_bookmarks()..@' 2>/dev/null | grep -q .; then
    jj_unpushed="↑"
  fi

  if [ -n "$jj_bookmark" ]; then
    jj_info="${jj_bookmark}${jj_dirty}${jj_unpushed}"
  else
    jj_info="(no bookmark)${jj_dirty}${jj_unpushed}"
  fi
fi

# Build the output
parts=""

# Directory
parts="${parts}$(printf '\033[34m%s\033[0m' "$short_dir")"

# jj info
if [ -n "$jj_info" ]; then
  parts="${parts} $(printf '\033[32m %s\033[0m' "$jj_info")"
fi

# Model
if [ -n "$model" ]; then
  parts="${parts} $(printf '\033[35m%s\033[0m' "$model")"
fi

# Context usage
if [ -n "$used" ]; then
  used_int=$(printf '%.0f' "$used")
  if [ "$used_int" -ge 80 ]; then
    color='\033[31m'  # red
  elif [ "$used_int" -ge 50 ]; then
    color='\033[33m'  # yellow
  else
    color='\033[36m'  # cyan
  fi
  # Progress bar: 10 chars wide
  bar_width=10
  filled=$(( used_int * bar_width / 100 ))
  empty=$(( bar_width - filled ))
  bar=$(printf '%0.s█' $(seq 1 $filled 2>/dev/null))
  bar="${bar}$(printf '%0.s░' $(seq 1 $empty 2>/dev/null))"
  parts="${parts} $(printf "${color}ctx:%s%% %s\033[0m" "$used_int" "$bar")"
fi

printf '%s' "$parts"
