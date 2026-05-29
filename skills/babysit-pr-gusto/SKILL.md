---
name: babysit-pr-gusto
description: Iterative CI babysitting loop for Gusto PRs — investigate Buildkite failures, apply fixes, verify locally, push, monitor, and repeat until green.
---

# Babysit PR (Gusto)

Start an iterative CI debugging session. Systematically investigate and fix CI failures through a structured loop: investigate → fix → verify locally → push → check → iterate.

This command orchestrates the debugging loop. For all Buildkite interaction (fetching builds, reading logs, monitoring), use the [investigating-builds](investigating-builds/SKILL.md) skill workflows and tool hierarchy.

## Arguments

- **URL** (optional): Buildkite build URL to start investigating
- If no URL provided, infer from current branch

## Step 1: Determine the Build

### If URL provided:

Use the [investigating-builds](investigating-builds/SKILL.md) skill's "Investigating a Build from URL" workflow — `bktide snapshot` parses any Buildkite URL automatically.

### If no URL provided:

1. Get the current git branch:
   ```bash
   git branch --show-current
   ```

2. Identify the pipeline:
   - Repository name often matches pipeline slug
   - Check `.buildkite/pipeline.yml` for pipeline hints

3. Use the [investigating-builds](investigating-builds/SKILL.md) skill's "Checking Current Branch/PR Status" workflow to find the latest build for this branch.

4. If no pipeline can be determined, ask the user for the Buildkite URL.

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

> "Starting CI fix session for branch `<branch>` (Build #<number>). I see <N> failed jobs. Let me investigate."

### Optional: Create Tracking Document

For complex or multi-day debugging sessions, offer to create a tracking document:

> "Would you like me to create a tracking document for this CI fix session? Useful for multi-day debugging or handoff."

If yes, create `docs/plans/ci-fix-<branch-slug>.md`:

```markdown
# CI Fix Workflow: <branch-name>

## Session: <YYYY-MM-DD>

### Initial State
- Branch: `<branch-name>`
- PR: #<pr-number>
- Latest failing build: <build-number> (<N> failures - <brief description>)

---

## Iteration 1: <Title>

**Build:** <number> (<status>)
**Failures:** <count> (<pattern description>)

**Root cause:**
<1-2 sentences explaining why this failed>

**Fix:**
<Code changes or commands>

**Verification:**
\`\`\`bash
<local verification commands>
\`\`\`

**Commit:** `<sha>` - "<message>"
**Next build:** <number>

---

## Summary of Issues Fixed

| Build | Issue | Root Cause | Fix |
|-------|-------|------------|-----|
| <num> | <issue> | <cause> | <fix> |

## Next Steps

- [ ] <remaining items if session ends before green>
```

## Step 3: Check Branch Freshness

**IMPORTANT**: Before diving into failures, check if the branch is up to date with main.

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

Use the [investigating-builds](investigating-builds/SKILL.md) skill to investigate. The skill's tool hierarchy applies: `bktide snapshot` first, then other bktide commands, then MCP tools as fallback.

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

| Category | Signs | Verification Required | Typical Fix |
|----------|-------|----------------------|-------------|
| **Stale branch** | Tests pass on main | **Must verify**: check same pipeline on main | Merge main, resolve conflicts |
| **Gemfile.lock issues** | Checksum errors, missing gems | Visible in logs | Regenerate from main |
| **Test failures** | RSpec/Jest failures with stack traces | Run locally first | Fix the test or code |
| **Type errors** | Sorbet/TypeScript errors | Run type checker locally | Fix type annotations |
| **Lint errors** | Rubocop/ESLint failures | Run linter locally | Auto-fix or manual fix |
| **Flaky tests** | In Trunk quarantine, or passes locally multiple times | Check Trunk.io links in CI output | May need retry or quarantine |
| **CODEOWNERS out of date** | `bin/codeownership validate` fails in CI | **Cannot trust local validate** — see Common Fix Patterns | Regenerate in Docker or diff against main |

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

## Step 7: Push and Monitor

**Gate check before pushing:** Can you explain with certainty why your change fixes the CI failure? If not — if it's a hypothesis you'd like to test — **stop and ask the user first.** Describe what you think is wrong, what you'd change, and why you can't verify it locally. Get explicit confirmation before pushing.

After local verification passes:

1. **Commit the fix** with a descriptive message referencing the build:
   ```
   Fix <failure type> from build #<number>

   <brief description of what was wrong and how it was fixed>
   ```

2. **Push the changes**:
   ```bash
   git push
   ```

3. **Monitor the new build** using the [investigating-builds](investigating-builds/SKILL.md) skill's "Post-Push Monitoring" workflow.

4. **Report status** when build completes:
   - If passed: Summarize what was fixed
   - If failed: Go to Step 8

## Step 8: Iterate if Still Failing

If the new build still has failures:

1. **Compare with previous build**:
   - Same failures? Fix didn't work
   - Different failures? Progress, but new issues
   - Fewer failures? Partial progress

2. **Document the iteration**:
   > "Build #<new> still failing with <N> failures (was <M>). <same/different> failure pattern."

3. **Return to Step 4** with the new build number

4. **Track iterations** — after 3+ iterations, consider:
   - Is there a deeper architectural issue?
   - Should we get another pair of eyes?
   - Is the branch too diverged from main?

## Step 9: Session Summary

When CI finally passes (or session ends), summarize:

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
- **Never push a guess** — every fix you push must be one you can explain with certainty, not a hypothesis. If you cannot reproduce the failure locally and cannot mechanically prove your change fixes it, **stop and ask the user**. Present your hypothesis clearly: what you think is wrong, what you'd change, and why you're not certain. Let the user decide whether to spend a CI cycle validating it. Pushing guesses wastes CI cycles (10+ minutes per build), pollutes git history, and erodes trust.
- **Local pass ≠ CI pass** — some tools (notably `codeownership`) behave differently on macOS vs Linux. When local verification passes but CI fails, treat CI as the source of truth and reproduce in Docker.
- **One fix at a time** when possible — easier to identify what worked
- **Document as you go** — helps if session spans multiple days
- **Know when to stop** — sometimes fresh eyes or a different approach is needed
- **Check main first** — the issue might already be fixed there, but verify by checking the actual pipeline, not by assuming
