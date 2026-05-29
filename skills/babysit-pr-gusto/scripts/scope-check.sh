#!/usr/bin/env bash
# scope-check.sh — heuristic scope-creep check for a babysat PR.
#
# Usage: scope-check.sh <PR-number>
# Compares the PR's CLAIMED scope (project dirs named in the title/body, plus
# narrowing words like "pilot"/"only") against the ACTUAL diff footprint (project
# dirs touched vs the merge-base with main). Advisory: always exits 0 and prints a
# `verdict:` line (OK or REVIEW) that the orchestrator surfaces in the tick report
# BEFORE spending CI cycles greening a PR. Operates on branch refs, so it works even
# after the worktree has been removed.
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

pr="${1:-}"
[ -z "$pr" ] && { echo "usage: scope-check.sh <PR-number>" >&2; exit 1; }

meta=$(gh pr view "$pr" --json title,body,headRefName 2>/dev/null || true)
[ -z "$meta" ] && { echo "scope-check: could not load PR #$pr" >&2; exit 1; }
branch=$(printf '%s' "$meta" | jq -r .headRefName)
text=$(printf '%s' "$meta" | jq -r '.title + "\n" + (.body // "")')

# Project dirs (apps/X, libs/X) named anywhere in the title/body.
claimed=$(printf '%s' "$text" | grep -oE '(apps|libs)/[a-z0-9._-]+' | sort -u || true)

# Project dirs actually touched by the diff vs the merge-base with main.
base=$(git merge-base main "$branch")
files=$(git diff --name-only "$base".."$branch" || true)
touched=$(printf '%s' "$files" | grep -oE '^(apps|libs)/[a-z0-9._-]+' | sort -u || true)
nfiles=$(printf '%s\n' "$files" | grep -c . || true)

# Dirs touched but not named anywhere in the title/body.
if [ -n "$claimed" ]; then
  extra=$(comm -23 <(printf '%s\n' "$touched") <(printf '%s\n' "$claimed") | grep -v '^$' || true)
else
  extra="$touched"
fi
ntouched=$(printf '%s\n' "$touched" | grep -c . || true)
nextra=$(printf '%s\n' "$extra" | grep -c . || true)

# Narrowing language in the title/body ("pilot", "only", "just", "single", "sole").
narrowing=$(printf '%s' "$text" | grep -ioE '\b(pilot|only|just|single|sole)\b' | head -1 || true)

claimed_flat=$(printf '%s' "$claimed" | tr '\n' ' ')
touched_flat=$(printf '%s' "$touched" | tr '\n' ' ')
extra_flat=$(printf '%s' "$extra" | tr '\n' ' ')

echo "scope-check PR #$pr ($branch)"
echo "  claimed dirs (title/body): ${claimed_flat:-<none named>}"
echo "  diff touches ($ntouched dir(s), $nfiles file(s)): ${touched_flat:-<none>}"
echo "  not named in PR ($nextra): ${extra_flat:-<none>}"

# REVIEW when the diff sprawls beyond what the PR names — loudest when the PR uses
# narrowing language. Thresholds are heuristic and intentionally conservative
# (warn, never block): a human confirms intended scope before the PR is greened.
if [ "$nextra" -ge 2 ] || { [ -n "$narrowing" ] && [ "$nextra" -ge 1 ]; }; then
  echo "  verdict: REVIEW — diff touches $nextra project dir(s) not named in the PR title/body${narrowing:+ (narrowing word: $narrowing)}. Confirm intended scope before greening."
else
  echo "  verdict: OK — diff footprint aligns with the PR's stated scope."
fi
