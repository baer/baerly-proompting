---
name: babysit-pr-gusto
description: Babysit one or more Gusto PRs to green. Provisions a git worktree per PR, triages required checks, dispatches a single-iteration fix loop (investigate → fix → verify → push) per failing PR, and can run backgrounded on a /loop or /schedule cadence until every PR passes or escalates. Single-PR is just N=1.
---

# Babysit PR (Gusto)

Start an iterative CI debugging session. Systematically investigate and fix CI failures through a structured loop: investigate → fix → verify locally → push → check → iterate.

This command orchestrates the debugging loop. For all Buildkite interaction (fetching builds, reading logs, monitoring), use the [investigating-builds](investigating-builds/SKILL.md) skill workflows and tool hierarchy.

## Arguments

- **PR numbers** (zero or more): the PRs to babysit. With none, babysits every open
  authored PR that currently has a failing check (`scripts/resolve-prs.sh`).
- A Buildkite URL or single PR still works — that's the N=1 path.

## How this skill runs

This is an **orchestrator**. One invocation = one **tick** across all target PRs.
For the tick algorithm and the per-PR single-iteration **fixer contract**, follow
`references/orchestration.md`. For running ticks on a cadence, follow
`references/backgrounding.md`. For all Buildkite interaction, use the
`investigating-builds/SKILL.md` sub-skill and its tool hierarchy.

### Tick (top level)

1. `prs=$(scripts/resolve-prs.sh "$@")`
2. `scripts/setup-worktrees.sh $prs` (drop any BLOCKED PR; report it)
3. `scripts/triage-prs.sh $prs` → per-PR state
4. Persist each via `scripts/pr-state.mjs set <pr> status <state>`
5. For each PR now **green**: `scripts/remove-worktree.sh <pr>` to free its disk
   (deletes the worktree, KEEPS the branch and the `tmp/babysit/<pr>.json` record),
   then drop it from the watch
6. For each **failing, non-escalated** PR: `scripts/scope-check.sh <pr>` → put the
   verdict in the report; on a `REVIEW` verdict (diff sprawls beyond the dirs the PR
   names), surface it and prefer to pause for a human scope glance before greening
7. Fan out ONE fixer subagent per failing, non-escalated PR (parallel)
8. Persist results (`scripts/pr-state.mjs attempt …`) and print the tick report
9. If backgrounded and any PR is still failing/running and not escalated, the
   cadence (Mode A/B in backgrounding.md) schedules the next tick.

**Stop condition (owned by this skill, not the loop prompt).** A bare loop
invocation (`/loop <interval> babysit-pr-gusto <prs…>`) is sufficient because this
skill owns its own termination: when every watched PR is green or escalated, emit
the final summary and STOP scheduling the next tick (`CronDelete` / no re-wake).
Escalated/held PRs do NOT keep the loop alive — they stay in the watch list and are
reported each tick as "skipped — needs human," but they are not re-fixed and do not
count as "still failing." The tick logic and this stop rule live here and in
`references/orchestration.md` + `references/backgrounding.md`, never duplicated in
the loop prompt (which would only drift).

## Fixer sub-procedure (one PR, one iteration)

A fixer runs inside a single PR's worktree and does exactly ONE iteration, then
returns to the orchestrator. It does NOT loop waiting for the next build — the next
tick handles that. The steps below are that one iteration. The fixer is already
`cd`'d into `.worktrees/<branch>`, so a bare `git push` updates the correct PR.

(Steps are numbered from 2 for continuity with the original single-PR skill. "Step 1"
is implicit: the orchestrator has already handed you the PR number, branch, worktree
path, build, and prior attempts.)

## Step 2: Capture Initial State

Record the starting point:

- **Branch name**: Current git branch
- **PR number**: If applicable (`gh pr view --json number`)
- **Build number**: The failing build
- **Failure count**: Number of failed jobs

### Identify Required Checks

**CRITICAL**: Run `gh pr checks <PR-number>` to see which checks are **required for merge** and which are failing. This is the source of truth for whether the PR can merge — not your judgment about which pipelines "matter."

- A failure in any required check blocks the PR, period.
- Do not assume a passing pipeline (e.g. `web-pull-request`) compensates for a failing one (e.g. `web`). They test different things.
- Do not assume failures are "pre-existing" or "unrelated to this branch" without verification (see Step 4).

Announce to the user:

> "Investigating CI failure on `<branch>` (Build #<number>) — <N> failed job(s)."

Machine-readable per-PR state is maintained by the orchestrator via `scripts/pr-state.mjs` (see `references/state-schema.md`); the fixer does not keep its own tracking document.

## Step 3: Check Branch Freshness

**IMPORTANT**: Before diving into failures, check if the branch is up to date with main. (If `scripts/setup-worktrees.sh` already fetched origin while provisioning the worktree, this is a freshness confirm rather than a first fetch.)

1. Check if branch is behind main:

   ```bash
   git fetch origin main
   git rev-list --count HEAD..origin/main
   ```

2. If behind by more than 0 commits:

   > "Your branch is <N> commits behind main. Recommend merging main first to rule out stale code issues."

   Ask user if they want to:
   - Merge main now (handle conflicts if needed)
   - Skip and investigate current failures
   - The failures might already be fixed in main

## Step 4: Investigate Failures

Triage (`scripts/triage-prs.sh`) already gave you the failing check names in the PR state — Step 4 is about reading the _logs_ for those checks via `investigating-builds`, not re-triaging.

Use the [investigating-builds](investigating-builds/SKILL.md) skill to investigate. The skill's tool hierarchy applies: `bktide snapshot` first, then other bktide commands, then MCP tools as fallback.

**Read logs cheaply — CI logs are huge and will blow your context.** From the snapshot, read `manifest.json` to find the failing step + exit code, then **grep** that step's `log.txt` for the error region (e.g. `grep -nE 'FAIL|Error:|✗|error TS[0-9]|exit (code )?[1-9]'`) and read only a small window around the hit (errors cluster near the end of a failed step). Never `Read`/`cat` a whole CI log into context — bktide writes logs to files so you grep them.

After gathering build data, identify failure patterns:

- Test failures (RSpec, Jest, pytest, etc.)
- Build/compilation errors
- Linting/type checking errors
- Infrastructure issues (Docker, dependencies)

### Never Dismiss Failures Without Proof

**CRITICAL**: Do not categorize any failure as "pre-existing," "unrelated to this branch," or "not blocking" without concrete evidence. Every failure in a required check is your problem to solve until proven otherwise.

To prove a failure is pre-existing, you must do **at least one** of:

- Show the same test/lint failure exists on the latest `main` build of the **same pipeline**
- Show with `git log` / `git diff origin/main` that the failing file was not modified on this branch AND the failure reproduces on main
- Show the failure is in a Trunk.io quarantined test (the CI log will say "quarantined")

If you cannot prove it, **treat it as a real failure and fix it**. The most common mistake is seeing a failure in code "you didn't touch" and assuming it's someone else's problem — but your branch may be behind main, or a transitive dependency you changed may have broken it.

Even when a failure IS provably pre-existing, tell the user clearly: "This failure exists on main too — it's not caused by this branch, but it IS blocking your PR. Here are options: [merge main / wait for upstream fix / investigate if branch staleness is the cause]."

## Step 5: Categorize and Plan Fixes

Group failures by type and plan the fix approach:

| Category                   | Signs                                                 | Verification Required                                     | Typical Fix                               |
| -------------------------- | ----------------------------------------------------- | --------------------------------------------------------- | ----------------------------------------- |
| **Stale branch**           | Tests pass on main                                    | **Must verify**: check same pipeline on main              | Merge main, resolve conflicts             |
| **Gemfile.lock issues**    | Checksum errors, missing gems                         | Visible in logs                                           | Regenerate from main                      |
| **Test failures**          | RSpec/Jest failures with stack traces                 | Run locally first                                         | Fix the test or code                      |
| **Type errors**            | Sorbet/TypeScript errors                              | Run type checker locally                                  | Fix type annotations                      |
| **Lint errors**            | Rubocop/ESLint failures                               | Run linter locally                                        | Auto-fix or manual fix                    |
| **Flaky tests**            | In Trunk quarantine, or passes locally multiple times | Check Trunk.io links in CI output                         | May need retry or quarantine              |
| **CODEOWNERS out of date** | `bin/codeownership validate` fails in CI              | **Cannot trust local validate** — see Common Fix Patterns | Regenerate in Docker or diff against main |

**Important**: "Stale branch" is only valid if you have actually verified the test passes on the latest main build of the same pipeline. Do not guess — check.

For each failure category, outline:

1. What needs to be fixed
2. Files likely involved
3. How to verify locally before pushing

## Step 6: Pre-Push Verification

**Before pushing any fix**, verify locally:

### For Ruby/Rails projects:

```bash
bin/rspec <spec_files>
bin/srb tc <modified_files>      # if using Sorbet
lefthook run pre-commit          # or: pre-commit run --files <modified_files>
```

### For JavaScript/TypeScript projects:

```bash
npm test -- <test_files>         # or: yarn test <test_files>
npx tsc --noEmit                 # if using TypeScript
npm run lint
```

### General:

```bash
# Run whatever CI runs locally if possible
# Check the failed job's command in the logs
```

### When local verification diverges from CI

Some tools produce different results on macOS (local) vs Linux (CI Docker). Known examples:

- `bin/codeownership` (Rust binary via dotslash — macOS and Linux builds can disagree on generated output)
- Tools with platform-specific file globbing or sorting behavior

**If local verification passes but CI keeps failing on the same check:**

1. **Do not trust local results.** The CI environment (Linux/Docker) is the source of truth.
2. **Reproduce in the CI environment instead:**
   - Use `docker-compose run ci <command>` to run the same check in the same Docker image CI uses
   - Or diff the expected output: compare what main has in the file vs your branch, and check what main's CI produces
3. **If Docker reproduction isn't feasible**, diff your branch's file against `origin/main` and restore the main version if your branch shouldn't be changing it. Then verify that the file isn't being re-modified by a pre-commit hook or generate step.
4. **If you still can't reproduce or prove the fix**, tell the user. Present your best hypothesis — what you think is wrong, what you'd change, and why you can't verify it locally. Ask whether they want to spend a CI cycle testing it. Never push a hypothesis silently.

## Step 7: Push and hand off

**Gate check before pushing:** Can you explain with certainty why your change fixes the CI failure? If not — if it's a hypothesis you'd like to test — **stop and ask the user first.** Describe what you think is wrong, what you'd change, and why you can't verify it locally. Get explicit confirmation before pushing.

After local verification passes:

1. **Commit the fix** with a descriptive message referencing the build:

   ```
   Fix <failure type> from build #<number>

   <brief description of what was wrong and how it was fixed>
   ```

2. **Push the changes** (the fixer is already on `<branch>` in its worktree — a bare push is correct):

   ```bash
   git push
   ```

3. After pushing, confirm the new build has been enqueued/started (a quick check via `investigating-builds`), then proceed to Step 8 and return. Do NOT wait for the new build to finish — the next orchestrator tick re-triages it.

## Step 8: Record this attempt and return

Iteration across builds is the orchestrator's job (one fix per tick), not the
fixer's. Do not loop here waiting for a new build. Instead:

- If you pushed a fix you can stand behind: `scripts/pr-state.mjs attempt <pr> <build> pushed "<one-line summary>"` and return `pushed`.
- If the failure was NOT caused by this PR — a flaky test that passes on rerun, or a CI infra flake (spot-instance termination, SIGTERM / exit 143, "agent lost", BROKEN cascade) — do NOT edit code. Retrigger CI with an empty commit (`git commit --allow-empty -m "ci: retrigger build (<reason>)"` then `git push`), record `scripts/pr-state.mjs attempt <pr> <build> retriggered "<reason>"`, and return `retriggered`. (Cap: `pr-state.mjs` auto-escalates after 2 retriggers — a 3rd "flake" recurrence is probably real and needs a human.)
- If you could not verify a fix locally (never push a guess), or the fix touches another team's CODEOWNERS area, or the worktree is too stale to install/verify: **leave the worktree CLEAN** for the next tick — revert or stash your unverified edits (`git checkout -- .` or `git stash`) — then `scripts/pr-state.mjs attempt <pr> <build> paused "<hypothesis>"` and return `paused`.
- The next tick re-triages and, if still failing and not escalated, dispatches a fresh fixer.

**Return tersely.** Your reply to the orchestrator is just the outcome (`pushed`/`retriggered`/`paused`), the build ref, and a one-line note. All detail — root cause, diff rationale, hypothesis — goes into the `pr-state.mjs` note and the commit message, never into the return value (it lands in the orchestrator's long-lived context).

## Final summary (orchestrator, after all ticks)

> Emitted by the orchestrator once every PR is green or escalated — NOT by the fixer (which returns after one iteration per Step 8). This complements the per-tick report defined in `references/orchestration.md`.

When CI finally passes (or all PRs are resolved), summarize:

```markdown
## CI Fix Session Summary

**Branch:** <branch-name>
**Started:** Build #<first-build> (<N> failures)
**Ended:** Build #<final-build> (passed / still failing)
**Iterations:** <count>

### Fixes Applied

1. <Fix 1 description>
2. <Fix 2 description>

### Patterns Encountered

- <Pattern 1 and how it was resolved>

### Lessons Learned

- <Any insights for future debugging>
```

## Common Fix Patterns

### CODEOWNERS Out of Date

**Symptom:** `CODEOWNERS out of date. Run 'codeowners generate' to update the CODEOWNERS file`

**Critical warning:** `bin/codeownership` uses a Rust binary (`bin/dotslash/codeownership`) downloaded via dotslash. The macOS and Linux binaries can produce **different CODEOWNERS output** for the same repo state. Running `bin/codeownership generate && bin/codeownership validate` locally (macOS) may pass, but CI (Linux Docker) may still fail. **Do not trust local generate/validate for this check.**

**Diagnosis:**

1. Check if your branch modifies `.github/CODEOWNERS` compared to main:
   ```bash
   git diff origin/main -- .github/CODEOWNERS
   ```
2. If your branch has CODEOWNERS changes you didn't intend (e.g., from a rebase where `generate` ran on macOS), that's the problem.

**Fix:**

```bash
# Restore CODEOWNERS from main (if your branch shouldn't change it)
git checkout origin/main -- .github/CODEOWNERS
git add .github/CODEOWNERS
git commit -m "Restore CODEOWNERS from main (macOS/Linux generate divergence)"
```

If your branch **does** need CODEOWNERS changes (e.g., you added a new directory with a `.codeowner` file):

```bash
# Generate in the CI Docker image to match what Linux produces
docker-compose run ci bin/codeownership generate
# Then commit the result
git add .github/CODEOWNERS
git commit -m "Regenerate CODEOWNERS in Docker for Linux parity"
```

**If Docker isn't available locally**, compare your CODEOWNERS diff against main line-by-line. Any lines removed that main has — and that correspond to directories still present in the repo — should be restored.

### Gemfile.lock Checksum Issues

**Symptom:** `Your lockfile has an empty CHECKSUMS entry for "<gem>"`

**Fix:**

```bash
rm Gemfile.lock
git checkout origin/main -- Gemfile.lock
bundle lock
bundle install  # verify
git add Gemfile.lock
git commit -m "Regenerate Gemfile.lock with proper checksums"
```

### Merge Conflicts Blocking Push

**Fix:**

```bash
git stash push -m "WIP changes"
git fetch origin main
git merge origin/main --no-edit
# Resolve conflicts
git add <conflicted-files>
git commit
git stash pop
# Resolve any conflicts from stash
```

### Test Matcher/Helper Changes Breaking Tests

**Diagnosis:** Compare with main to see what changed:

```bash
git diff origin/main -- spec/support/
git diff origin/main -- test/helpers/
```

**Fix:** Often need to restore original behavior for non-target tests while adding new behavior for new tests.

### Year Boundary Test Failures

**Symptom:** Tests involving dates fail around new year

**Fix:** Look for hardcoded years or date assumptions in tests.

## Guidelines

- **Every required-check failure is real until proven otherwise** — never report a PR as green or dismiss failures without running `gh pr checks` and verifying each failing check
- **Always verify locally** before pushing — saves CI cycles
- **Never push a guess** — every fix you push must be one you can explain with certainty, not a hypothesis. If you cannot reproduce the failure locally and cannot mechanically prove your change fixes it, **stop and ask the user**. Present your hypothesis clearly: what you think is wrong, what you'd change, and why you're not certain. Let the user decide whether to spend a CI cycle validating it. Pushing guesses wastes CI cycles (20+ minutes per build), pollutes git history, and erodes trust.
- **Don't auto-push across CODEOWNERS boundaries** — before pushing autonomously, check whether the fix touches files OUTSIDE this PR's existing diff or in a different CODEOWNERS team's area (the repo provides `bin/codeownership` — see the target repo's AGENTS.md "Social boundary: CODEOWNERS"). If so, do NOT auto-push: record `paused` and surface it to the human. Cross-team edits need human/owner buy-in.
- **Never expand the diff to chase green (scope guard)** — a fix may touch only files already in the PR's diff (or the file(s) the failure directly implicates). Never add new project dirs or mass-autofix to make CI pass (a 1-file rule change must not become a 200-file diff). Run `scripts/scope-check.sh <pr>` to flag a PR whose footprint already sprawls beyond what its title/description name (it cross-checks the PR title, body, and the diff, and is loudest when a narrowing word like "pilot"/"only" is present); if greening would require widening scope, pause and surface for a human scope decision.
- **Local pass ≠ CI pass** — some tools (notably `codeownership`) behave differently on macOS vs Linux. When local verification passes but CI fails, treat CI as the source of truth and reproduce in Docker.
- **One fix at a time** when possible — easier to identify what worked
- **Progress is tracked across ticks** by the orchestrator via `scripts/pr-state.mjs` state and the tick report — the fixer itself does not keep a multi-day log.
- **Know when to stop** — sometimes fresh eyes or a different approach is needed
- **Check main first** — the issue might already be fixed there, but verify by checking the actual pipeline, not by assuming
- **Never auto-merge.** This repo uses the Trunk.io merge queue. Babysitting stops at green and hands back to the human; never comment `/trunk merge` unless explicitly asked.
