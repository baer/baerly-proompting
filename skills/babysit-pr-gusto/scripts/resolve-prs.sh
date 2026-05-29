#!/usr/bin/env bash
# resolve-prs.sh — print the set of PR numbers to babysit, one per line.
#
# Usage:
#   resolve-prs.sh 19475 19269 15826   # explicit set
#   resolve-prs.sh                      # no args: all open authored PRs with a failing check
#
# Must be run inside the target git repo (uses gh, which infers the repo from cwd).
set -euo pipefail

if [ "$#" -gt 0 ]; then
  printf '%s\n' "$@"
  exit 0
fi

# A PR's statusCheckRollup mixes two shapes: commit-status checks expose `state`,
# check-runs expose `conclusion`. Match a FAILURE in either. Guard against PRs
# with no checks yet (statusCheckRollup can be null).
gh pr list --author "@me" --state open --limit 200 \
  --json number,statusCheckRollup \
  --jq '.[]
        | select(.statusCheckRollup != null)
        | select([.statusCheckRollup[]
            | select(.state=="FAILURE" or .conclusion=="FAILURE")] | length > 0)
        | .number' \
  || { echo "resolve-prs: gh pr list failed" >&2; exit 1; }
