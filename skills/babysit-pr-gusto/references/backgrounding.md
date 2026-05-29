# Backgrounding the babysit loop

One tick (see orchestration.md) is the unit. Backgrounding = repeating ticks on a
cadence until every PR is green or escalated.

## Cadence

Match the interval to Buildkite build duration. In practice `buildkite/web` runs
roughly **20–40 min** (a live run took well over 15). Default **20 minutes**
(cron-friendly). Polling faster wastes ticks (the build won't have moved); much
slower just adds latency to fixes.

## Mode A — in-session `/loop` (default, recommended first)

```
/loop 20m babysit-pr-gusto 19475 19269
```

- The loop invocation is just the **interval + skill name + PR numbers** — nothing
  more. The tick logic AND the stop rule live in the skill (`SKILL.md` "How this
  skill runs" + `orchestration.md`), NOT in the loop prompt. Re-stating the tick
  logic in the cron prompt only lets it drift from the skill; a bare invocation is
  sufficient because the skill owns its own stop condition.
- Re-invokes the skill every 20 min while this session stays open.
- Each tick fans out fixers as background subagents, so the foreground chat is free.
- Best when you're at your desk and want to interrupt easily.
- Termination (owned by the skill): once all watched PRs are green or escalated, the
  skill emits a final summary and stops scheduling the next tick (`CronDelete` / no
  re-wake). The loop prompt does not need to encode this.

## Mode B — remote `/schedule` (set-and-forget)

Use when the loop should survive closing the laptop:

```
/schedule a routine "babysit PRs 19475 19269" every 20 minutes
```

- Runs remotely on cron. Heavier; use after the loop has earned trust.
- Same tick body. State lives in `tmp/babysit/<pr>.json` in the checkout the routine uses.

## Act only on COMPLETED failed builds

A `failed` triage state can include a build still running other jobs. Before a fixer
investigates, confirm the failing check's build has finished (the `investigating-builds`
"Post-Push Monitoring" workflow / `bktide` build state). Acting on an in-flight build
risks fixing a failure that the build itself will clear.

## Escalation & notification

- `pr-state.mjs` sets `escalated: true` when a PR accrues `ESCALATE_AFTER` (3)
  _consecutive non-progress_ attempts (its `strikes` count — `pushed`/`green` reset
  it; see state-schema.md) OR reaches `RETRIGGER_CAP` (2) `retriggered` attempts.
- Escalated/held PRs are NOT silently dropped from the watch args. The default is
  **kept in the list and reported every tick as "skipped — needs human"** (never
  re-fixed). An operator may explicitly remove a PR from the args if they want it off
  the watch list; that is the only way it leaves.
- A fixer that returns `paused` (couldn't verify a fix, cross-team edit, dirty/stale
  worktree) also surfaces immediately — do not keep spending CI cycles on a guess.
- A fixer that returns `retriggered` re-kicked CI for a non-PR failure (flake / infra);
  it counts toward the retrigger cap so a persistent "flake" eventually escalates.
- The tick report is the notification surface. In `/schedule` mode, include a one-line
  summary suitable for a push notification: "babysit: 1 green, 1 running, 1 needs human."
