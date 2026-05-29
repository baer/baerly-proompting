# Orchestration: one tick across N PRs

A **tick** is one pass over every babysat PR. It is stateless except for the
`tmp/babysit/<pr>.json` files — re-running a tick is always safe.

## Tick algorithm

1. `prs=$(resolve-prs.sh "$@")` — explicit args, else all failing authored PRs.
2. `setup-worktrees.sh $prs` — ensure each has a `.worktrees/<branch>` workspace.
   If any PR is `BLOCKED` (its branch is checked out in the main dir), report it
   and drop it from this tick.
3. `triage-prs.sh $prs` — classify each PR.
4. For each PR, update `pr-state.mjs set <pr> status <state>`.
5. Partition:
   - **green** → already recorded by `pr-state.mjs set <pr> status green` in step 4; announce it's done; stop babysitting it.
   - **running** → skip this tick (nothing to do until the build completes).
   - **unknown** → report; do not act (no checks found — likely a draft or a stuck PR).
   - **failed AND not escalated** → eligible for a fixer.
6. **Fan out**: dispatch ONE subagent per eligible PR, in parallel (Agent tool;
   see superpowers:dispatching-parallel-agents). Each subagent runs the
   single-iteration fixer contract below, scoped to that PR's worktree.
7. Collect subagent results, persist via `pr-state.mjs attempt …`, and print the
   tick report (table: PR | branch | state | iterations | escalated | note).

## Single-iteration fixer contract (one subagent, one PR)

The subagent is given: `pr`, `branch`, absolute worktree path, and the current
`pr-state.mjs get <pr>` JSON (so it knows what's already been tried). It must:

1. `cd` into the worktree. Confirm it's on `<branch>` and clean.
2. **Freshness check** (SKILL.md "Fixer sub-procedure"): if behind `origin/main`,
   merge main first — for a stale PR this is often the entire fix. Resolve conflicts
   or escalate.
3. Investigate the latest failed build with the `investigating-builds` sub-skill
   (`bktide snapshot <failed-check-link>`). Read prior `attempts` to avoid repeating
   a fix that already failed.
4. Apply ONE fix. Verify locally with the project's targeted commands
   (`yarn oxlint`/`eslint`/`tsc`/`test`/`vitest` per the target repo's AGENTS.md).
5. **Gate (never push a guess):** if the fix can't be verified locally or
   mechanically proven, do NOT push. Write the hypothesis via
   `pr-state.mjs attempt <pr> <build> paused "<hypothesis>"`, then return `paused`.
6. Otherwise commit + `git push` (the worktree tracks the PR branch, so a bare
   `git push` updates the right PR). Return `pushed` with a one-line summary.
7. NEVER `/trunk merge` — babysitting stops at green and hands back to the human.

The fixer does exactly one iteration and returns. It does NOT wait for the new
build — the next tick picks that up. This keeps each subagent short and bounded.

## Parallelism notes

- Each PR has its own worktree, so parallel fixers never touch shared files. Safe to fan out.
- Cap concurrency at the number of failing PRs (realistically ≤ a handful).
- One new build per PR per tick is the max useful work — the build is the bottleneck.

## Termination

A tick with no failing, non-escalated PRs is **terminal**: emit the final summary and
do NOT schedule another. Under `/loop`, omit the next wake-up; under `/schedule`, the
routine can be disabled or left to no-op. Escalated PRs do not keep the loop alive —
they are handed to the human, not retried.
