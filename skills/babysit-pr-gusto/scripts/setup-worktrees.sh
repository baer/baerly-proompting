#!/usr/bin/env bash
# setup-worktrees.sh — ensure a git worktree at .worktrees/<branch> for each PR.
#
# Usage: setup-worktrees.sh 19475 19269 15826
# Run from anywhere inside the target repo. Idempotent.
# - Adds .worktrees/ to .gitignore (and commits) if not already ignored.
# - Skips a branch that's currently checked out in the main working dir
#   (git forbids two checkouts of one branch) and tells the user to switch to main.
# - Runs `yarn install` in each new worktree.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

if ! git check-ignore -q .worktrees 2>/dev/null; then
  printf '\n.worktrees/\n' >> .gitignore
  git add .gitignore
  git commit -m "chore: ignore .worktrees" >/dev/null
  echo "ignored: .worktrees/"
fi

git fetch origin >/dev/null 2>&1 || true
current=$(git branch --show-current)

for pr in "$@"; do
  branch=$(gh pr view "$pr" --json headRefName --jq .headRefName)
  path=".worktrees/$branch"

  if git worktree list --porcelain | grep -qx "worktree $root/$path"; then
    echo "exists: $path (PR #$pr)"
    continue
  fi
  if [ "$current" = "$branch" ]; then
    echo "BLOCKED: branch '$branch' (PR #$pr) is checked out in the main dir."
    echo "         Switch this dir to main first:  git switch main"
    continue
  fi

  git fetch origin "$branch" >/dev/null 2>&1 || true
  git worktree add "$path" "$branch"
  echo "created: $path (PR #$pr)"
  ( cd "$path" && yarn install --silent ) || echo "warn: yarn install failed in $path"
done

echo "--- worktrees ---"
git worktree list
