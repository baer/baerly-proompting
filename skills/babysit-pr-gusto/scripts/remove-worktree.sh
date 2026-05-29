#!/usr/bin/env bash
# remove-worktree.sh — remove a PR's worktree once CI is green, KEEPING the branch.
#
# Usage: remove-worktree.sh <PR-number | branch-name>
# Frees the disk a worktree holds (node_modules, bktide snapshots, build output)
# without deleting the branch ref — `git worktree remove` only deletes the working
# tree, never the branch. Idempotent and safe to call on an already-removed worktree.
#
# Run from anywhere inside the target repo. The per-PR state file under
# tmp/babysit/<pr>.json lives in the MAIN repo and is intentionally left in place.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

arg="${1:-}"
[ -z "$arg" ] && { echo "usage: remove-worktree.sh <PR-number | branch-name>" >&2; exit 1; }

# Numeric arg → resolve PR to its head branch; otherwise treat as a branch name.
if printf '%s' "$arg" | grep -qE '^[0-9]+$'; then
  branch=$(gh pr view "$arg" --json headRefName --jq .headRefName 2>/dev/null || true)
  [ -z "$branch" ] && { echo "remove-worktree: could not resolve PR #$arg to a branch" >&2; exit 1; }
else
  branch="$arg"
fi
path=".worktrees/$branch"

if ! git worktree list --porcelain | grep -qxF "worktree $root/$path"; then
  echo "remove-worktree: no worktree at $path (already removed?)"
  exit 0
fi

# Safety: refuse if there are uncommitted TRACKED changes — never discard real work.
# (Untracked files like node_modules / tmp snapshots are expected and fine to drop.)
if [ -n "$(git -C "$path" status --porcelain --untracked-files=no)" ]; then
  echo "BLOCKED: $path has uncommitted tracked changes; not removing. Resolve manually." >&2
  git -C "$path" status --short >&2
  exit 1
fi

# --force is needed to remove despite expected untracked files (node_modules, tmp/).
# The branch ref is preserved.
git worktree remove --force "$path"
git worktree prune
echo "removed worktree: $path (branch '$branch' kept)"
