# Per-PR Babysit State

One JSON file per PR at `<target-repo>/tmp/babysit/<pr>.json`. `tmp/` is gitignored
in the web repo, so state is local and never committed. Managed only via `pr-state.mjs`.

```json
{
  "pr": 19269,
  "branch": "stryker-pilot",
  "status": "failed",
  "iterations": 2,
  "strikes": 1,
  "lastBuild": "https://buildkite.com/gusto/web/builds/121885",
  "escalated": false,
  "attempts": [
    { "build": "121885", "outcome": "pushed", "note": "regenerated jest snapshots in apps/mcp" },
    {
      "build": "121990",
      "outcome": "paused",
      "note": "second failure differs; can't verify locally"
    }
  ]
}
```

- **status**: latest triage state (`failed` | `running` | `green` | `unknown`).
- **iterations**: count of completed fix attempts (== `attempts.length`).
- **strikes**: count of _consecutive non-progress_ attempts, recomputed from the full
  `attempts` array on every `attempt` call (this also migrates older state files that
  predate the field). A `green` or `pushed` outcome resets `strikes` to 0 (forward
  progress / a fix we stand behind); any other outcome (`paused`, `retriggered`)
  adds a strike. This is what drives escalation, NOT raw `iterations` — a PR that
  fixes a distinct issue every tick (`pushed`, `pushed`, …) never escalates.
- **escalated**: when `true`, the orchestrator skips this PR (does NOT re-fix it) and
  surfaces it to the human in every tick report as "needs human." Set automatically
  when `strikes >= ESCALATE_AFTER` (default 3) — i.e. three consecutive non-progress
  attempts — OR when the number of `retriggered` attempts reaches `RETRIGGER_CAP`
  (default 2; a recurring "flake" past the cap is probably real and needs a human).
  Can also be set manually via `escalate <pr>` by a fixer that hit a wall it cannot
  verify (never push a guess; uninstallable/too-stale branch; cross-team edit).
- **lastBuild**: the raw build identifier or URL passed to the most recent `attempt` (caller's choice).
- **attempts[].outcome**: `pushed` | `paused` | `retriggered`.
  - `pushed`: pushed a fix it can stand behind (forward progress — resets `strikes`).
  - `paused`: could not verify a fix locally, so left the worktree clean and surfaced
    the hypothesis to the human (never push a guess). Counts as a strike.
  - `retriggered`: the failure was NOT caused by this PR (a flaky test that passes on
    rerun, or a CI infra flake — spot-instance termination, SIGTERM/exit 143, agent
    lost, BROKEN cascade). No code fix was made; CI was retriggered (empty commit +
    push). Counts as a strike and toward the retrigger cap.

  A `green` result is recorded separately via `set <pr> status green`, not as an
  `attempt`. (When passed as an attempt outcome it still resets `strikes`.)
