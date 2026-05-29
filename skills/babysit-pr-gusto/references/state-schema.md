# Per-PR Babysit State

One JSON file per PR at `<target-repo>/tmp/babysit/<pr>.json`. `tmp/` is gitignored
in the web repo, so state is local and never committed. Managed only via `pr-state.js`.

```json
{
  "pr": 19269,
  "branch": "stryker-pilot",
  "status": "failed",
  "iterations": 2,
  "lastBuild": "https://buildkite.com/gusto/web/builds/121885",
  "escalated": false,
  "attempts": [
    { "build": "121885", "outcome": "failed", "note": "jest snapshot drift in apps/mcp" },
    { "build": "121990", "outcome": "failed", "note": "same failure; fix didn't take" }
  ]
}
```

- **status**: latest triage state (`failed` | `running` | `green` | `unknown`).
- **iterations**: count of completed fix attempts (== `attempts.length`).
- **escalated**: when `true`, the orchestrator skips this PR and surfaces it to the
  human. Set automatically after `ESCALATE_AFTER` (default 3) non-green attempts, or
  manually by a fixer that hit a "can't verify locally" wall (never push a guess).
- **attempts[].outcome**: `green` | `failed` | `paused` (`paused` = fixer stopped to
  ask the human; counts toward escalation only if not resolved).
