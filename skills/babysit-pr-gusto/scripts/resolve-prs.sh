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

gh pr list --author "@me" --state open \
  --json number,statusCheckRollup \
  --jq '.[]
        | select([.statusCheckRollup[]
            | select(.state=="FAILURE" or .conclusion=="FAILURE")] | length > 0)
        | .number'
