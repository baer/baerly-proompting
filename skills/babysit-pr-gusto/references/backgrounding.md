# Backgrounding the babysit loop

One tick (see orchestration.md) is the unit. Backgrounding = repeating ticks on a
cadence until every PR is green or escalated.

## Cadence

Match the interval to Buildkite build duration (~10 min for `buildkite/web`).
Default **15 minutes**. Polling faster wastes ticks (the build won't have moved);
much slower just adds latency to fixes.

## Mode A — in-session `/loop` (default, recommended first)

```
/loop 15m babysit-pr-gusto 19475 19269 15826
```

- Re-invokes the skill every 15 min while this session stays open.
- Each tick fans out fixers as background subagents, so the foreground chat is free.
- Best when you're at your desk and want to interrupt easily.
- Termination: the skill should stop scheduling once `triage` shows all PRs green
  or escalated — emit a final summary and do not reschedule.

## Mode B — remote `/schedule` (set-and-forget)

Use when the loop should survive closing the laptop:

```
/schedule a routine "babysit PRs 19475 19269 15826" every 15 minutes
```

- Runs remotely on cron. Heavier; use after the loop has earned trust.
- Same tick body. State lives in `tmp/babysit/<pr>.json` in the checkout the routine uses.

## Act only on COMPLETED failed builds

A `failed` triage state can include a build still running other jobs. Before a fixer
investigates, confirm the failing check's build has finished (the `investigating-builds`
"Post-Push Monitoring" workflow / `bktide` build state). Acting on an in-flight build
risks fixing a failure that the build itself will clear.

## Escalation & notification

- After `ESCALATE_AFTER` (3) non-green attempts on a PR, `pr-state.mjs` sets
  `escalated: true`. The orchestrator then skips it and surfaces it in every tick
  report under "needs human."
- A fixer that returns `paused` (couldn't verify a fix) also surfaces immediately —
  do not keep spending CI cycles on a guess.
- The tick report is the notification surface. In `/schedule` mode, include a one-line
  summary suitable for a push notification: "babysit: 1 green, 1 running, 1 needs human."
