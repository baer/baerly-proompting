#!/usr/bin/env bash
# triage-prs.sh — classify each PR's checks as failed/running/green/unknown.
#
# Usage: triage-prs.sh 19475 19269 15826
# Emits a single JSON array to stdout:
#   [{ "pr": 19475, "branch": "feature/holler", "state": "failed",
#      "failedChecks": [{"name":"buildkite/web","link":"https://..."}],
#      "ignored": [{"name":"UI Tests: workbench","bucket":"pending"}] }, ...]
#
# IGNORED CHECKS: some checks gate on a human, not on anything the babysitter can
# fix or wait on — notably Chromatic's "UI Tests"/"UI Review" (manual visual-diff
# approval). These are EXCLUDED from the state classification: a PR green on every
# non-ignored check triages as "green" even while Chromatic is still pending. The
# excluded-but-not-passing checks are reported in `ignored` so a human knows a manual
# gate remains. Override the match (a case-insensitive regex over name+link) with
# BABYSIT_IGNORE_CHECKS; default matches "chromatic".
#
# state precedence (over NON-ignored checks): no checks at all -> "unknown";
#   else any fail -> "failed"; else any pending -> "running"; else "green".
set -euo pipefail

ignore="${BABYSIT_IGNORE_CHECKS:-chromatic}"

out="[]"
for pr in "$@"; do
  branch=$(gh pr view "$pr" --json headRefName --jq .headRefName 2>/dev/null || true)  # exits non-zero for bad PR number, unlike pr checks below
  if [ -z "$branch" ]; then
    out=$(printf '%s' "$out" | jq -c --argjson pr "$pr" '. + [{pr:$pr, branch:null, state:"unknown", failedChecks:[], ignored:[]}]')
    continue
  fi

  # gh pr checks exits non-zero when checks are failing/pending — don't let set -e abort.
  checks=$(gh pr checks "$pr" --json name,bucket,link 2>/dev/null || true)
  [ -z "$checks" ] && checks="[]"
  [ "$checks" = "null" ] && checks="[]"

  total=$(printf '%s' "$checks" | jq 'length')

  # Active = checks NOT matching the ignore regex (over name + link). State is
  # classified on these only.
  active=$(printf '%s' "$checks" | jq -c --arg ig "$ignore" \
    '[.[] | select((((.name // "") + " " + (.link // "")) | test($ig; "i")) | not)]')

  # Ignored-and-not-passing checks surface as manual gates (so they aren't lost).
  ignored=$(printf '%s' "$checks" | jq -c --arg ig "$ignore" \
    '[.[] | select(((.name // "") + " " + (.link // "")) | test($ig; "i")) | select(.bucket != "pass") | {name, bucket}]')

  state=$(printf '%s' "$active" | jq -r --argjson total "$total" '
    if   $total == 0                  then "unknown"
    elif any(.[]; .bucket=="fail")    then "failed"
    elif any(.[]; .bucket=="pending") then "running"
    else "green" end')

  failed=$(printf '%s' "$active" | jq -c '[.[] | select(.bucket=="fail") | {name, link}]')

  out=$(printf '%s' "$out" | jq -c \
    --argjson pr "$pr" --arg b "$branch" --arg s "$state" --argjson f "$failed" --argjson ig "$ignored" \
    '. + [{pr:$pr, branch:$b, state:$s, failedChecks:$f, ignored:$ig}]')
done
printf '%s\n' "$out"
