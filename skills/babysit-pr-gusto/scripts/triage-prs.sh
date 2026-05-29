#!/usr/bin/env bash
# triage-prs.sh — classify each PR's checks as failed/running/green/unknown.
#
# Usage: triage-prs.sh 19475 19269 15826
# Emits a single JSON array to stdout:
#   [{ "pr": 19475, "branch": "feature/holler", "state": "failed",
#      "failedChecks": [{"name":"buildkite/web","link":"https://..."}] }, ...]
#
# state precedence: any fail -> "failed"; else any pending -> "running";
#                   else no checks -> "unknown"; else "green".
set -euo pipefail

out="[]"
for pr in "$@"; do
  branch=$(gh pr view "$pr" --json headRefName --jq .headRefName 2>/dev/null || true)  # exits non-zero for bad PR number, unlike pr checks below
  if [ -z "$branch" ]; then
    out=$(printf '%s' "$out" | jq -c --argjson pr "$pr" '. + [{pr:$pr, branch:null, state:"unknown", failedChecks:[]}]')
    continue
  fi

  # gh pr checks exits non-zero when checks are failing/pending — don't let set -e abort.
  checks=$(gh pr checks "$pr" --json name,bucket,link 2>/dev/null || true)
  [ -z "$checks" ] && checks="[]"
  [ "$checks" = "null" ] && checks="[]"

  state=$(printf '%s' "$checks" | jq -r '
    if   any(.[]; .bucket=="fail")    then "failed"
    elif any(.[]; .bucket=="pending") then "running"
    elif length==0                    then "unknown"
    else "green" end')

  failed=$(printf '%s' "$checks" | jq -c '[.[] | select(.bucket=="fail") | {name, link}]')

  out=$(printf '%s' "$out" | jq -c \
    --argjson pr "$pr" --arg b "$branch" --arg s "$state" --argjson f "$failed" \
    '. + [{pr:$pr, branch:$b, state:$s, failedChecks:$f}]')
done
printf '%s\n' "$out"
