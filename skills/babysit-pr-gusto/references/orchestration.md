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
   - **green** → already recorded by `pr-state.mjs set <pr> status green` in step 4;
     announce it's done; **free its disk with `remove-worktree.sh <pr>`** — this deletes
     the worktree (node_modules, snapshots, build output) but KEEPS the branch ref and
     the `tmp/babysit/<pr>.json` record; then stop babysitting it. If it ever regresses,
     step 2's `setup-worktrees.sh` re-provisions the worktree on demand.
   - **running** → skip this tick (nothing to do until the build completes).
   - **unknown** → report; do not act (no checks found — likely a draft or a stuck PR).
   - **escalated** (`escalated: true`, including a fixer that escalated this tick) →
     do NOT re-fix. Keep it in the watch list and report it as "skipped — needs human"
     every tick. (An operator may explicitly remove it; the default is keep-and-report,
     never silently drop it.)
   - **failed AND not escalated** → eligible for a fixer.
6. **Fan out**: dispatch ONE subagent per eligible PR, in parallel (Agent tool;
   see superpowers:dispatching-parallel-agents). Each subagent runs the
   single-iteration fixer contract below, scoped to that PR's worktree.
7. Collect subagent results, persist via `pr-state.mjs attempt …`, and print the
   tick report (table: PR | branch | state | iterations | strikes | escalated | note).

## Single-iteration fixer contract (one subagent, one PR)

The subagent is given: `pr`, `branch`, absolute worktree path, and the current
`pr-state.mjs get <pr>` JSON (so it knows what's already been tried). It returns
exactly one of three outcomes: **`pushed`** (forward fix), **`retriggered`** (CI
re-kicked for a non-PR failure), or **`paused`** (could not act safely; handed to
human). It must:

1. `cd` into the worktree. **Ensure a clean worktree (ACTION, not assumption):** run
   `git status --short`. In autonomous mode there should be NO leftover uncommitted
   changes from a prior tick (a paused fixer is required to leave the tree clean —
   see step 7). If leftover changes DO exist, do not blindly discard them: report
   the dirty state and stop (return `paused` with a "dirty worktree from prior tick"
   note) so a human can reconcile. Confirm it's on `<branch>`.
2. **Staleness pre-check.** If the branch is very far behind `origin/main` (hundreds+
   commits) OR `yarn install` / local verification cannot run in the worktree (e.g.
   `setup-worktrees.sh` printed an `ESCALATE:` line, or a legacy `.yarnrc.yml` breaks
   install), the fixer CANNOT honor its own "verify before push" gate. Do not attempt
   a fix it cannot verify: run `pr-state.mjs escalate <pr>` and return `paused` with a
   "needs human merge/strategy decision (branch too stale / uninstallable worktree)"
   note.
3. **Freshness check** (SKILL.md "Fixer sub-procedure"): if behind `origin/main` (but
   within a workable range per step 2), merge main first — for a stale PR this is often
   the entire fix. Resolve conflicts or escalate.
4. **Confirm the build is COMPLETE before diagnosing (ENFORCED).** Using the
   `investigating-builds` workflow / `bktide` build state, verify the failing check's
   build has actually concluded — a `failed` triage state can reflect a build still
   producing jobs. Do NOT act on an in-flight build (you may "fix" a failure the build
   itself will clear). Then investigate the latest failed build
   (`bktide snapshot <failed-check-link>`). Read prior `attempts` to avoid repeating a
   fix that already failed.
5. **Non-PR failure? Retrigger instead of editing code.** If the failure is NOT caused
   by this PR — a flaky test that passes on rerun, or a CI infra flake (spot-instance
   termination, SIGTERM / exit 143, "agent lost", a BROKEN cascade from another job) —
   do not edit code. Retrigger CI: `git commit --allow-empty -m "ci: retrigger build
(<reason>)"` then `git push`. Record `pr-state.mjs attempt <pr> <build> retriggered
"<reason>"` and return `retriggered`. CAP: do not retrigger the same PR
   indefinitely — `pr-state.mjs` auto-escalates after `RETRIGGER_CAP` (2) retriggers.
   A 3rd recurrence of the "same flake" means it is probably real and needs a human.
6. Otherwise apply ONE fix. Verify locally with the project's targeted commands
   (`yarn oxlint`/`eslint`/`tsc`/`test`/`vitest` per the target repo's AGENTS.md).
7. **Gate (before any autonomous push):**
   - **Never push a guess.** If the fix can't be verified locally or mechanically
     proven, do NOT push.
   - **Don't re-push a fix that already failed.** If the SAME failure you fixed last
     tick (a prior `pushed` attempt) has recurred — your push didn't take — do NOT
     re-push the same change. Run `pr-state.mjs escalate <pr>` and return `paused`.
   - **Cross-CODEOWNERS guard.** Before pushing autonomously, check whether the fix
     touches files OUTSIDE this PR's existing diff or in a different CODEOWNERS team's
     area (the target repo provides `bin/codeownership` — see its AGENTS.md "Social
     boundary: CODEOWNERS"). If so, do NOT auto-push: cross-team edits need
     human/owner buy-in.
   - In any of these cases, leave the worktree CLEAN: revert or stash the unverified
     edits (`git checkout -- .` or `git stash`) so the next tick starts from a clean
     state, then `pr-state.mjs attempt <pr> <build> paused "<hypothesis / reason>"`
     and return `paused`.
8. Otherwise commit + `git push` (the worktree tracks the PR branch, so a bare
   `git push` updates the right PR). Record `pr-state.mjs attempt <pr> <build> pushed
"<one-line summary>"` and return `pushed`.
9. NEVER `/trunk merge` — babysitting stops at green and hands back to the human.

The fixer does exactly one iteration and returns. It does NOT wait for the new
build — the next tick picks that up. This keeps each subagent short and bounded.

## Parallelism notes

- Each PR has its own worktree, so parallel fixers never touch shared files. Safe to fan out.
- Cap concurrency at the number of failing PRs (realistically ≤ a handful).
- One new build per PR per tick is the max useful work — the build is the bottleneck.

## Termination

A tick with no failing, non-escalated PRs is **terminal**: emit the final summary and
do NOT schedule another. Under `/loop`, omit the next wake-up (`CronDelete` / stop
scheduling); under `/schedule`, the routine can be disabled or left to no-op.
Escalated PRs do not keep the loop alive — they are handed to the human, not retried.
They stay in the watch list and are reported as "skipped — needs human" each tick
(default keep-and-report; an operator may remove them explicitly), but they do NOT
count as "still failing" for the purpose of keeping the loop scheduled.
