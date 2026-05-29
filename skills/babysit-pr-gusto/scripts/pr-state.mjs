#!/usr/bin/env node
import { execSync } from 'child_process';
// pr-state.mjs — read/append per-PR babysit state at <repo>/tmp/babysit/<pr>.json
//
// Usage:
//   pr-state.mjs get <pr>
//   pr-state.mjs set <pr> <key> <value>
//   pr-state.mjs attempt <pr> <build> <outcome> <note...>
//   pr-state.mjs escalate <pr>
//
// Named .mjs so it is unconditionally ESM regardless of any package.json.
// Run from within the TARGET repo: state lands under that repo's git toplevel.
import fs from 'fs';
import path from 'path';

const ESCALATE_AFTER = 3;
const RETRIGGER_CAP = 2;
const BOOL_FIELDS = new Set(['escalated']);
const NUM_FIELDS = new Set(['iterations', 'pr', 'strikes']);

const [, , cmd, pr, ...rest] = process.argv;
if (!cmd || !pr) {
  console.error('usage: pr-state.mjs <get|set|attempt|escalate> <pr> [...]');
  process.exit(1);
}

// Resolve the MAIN repo root, not the current worktree. Inside a linked worktree
// `--show-toplevel` returns the worktree dir (state would scatter per-worktree);
// `--git-common-dir` points at the main repo's .git from any worktree, so its
// parent is the shared root where the orchestrator and all fixers agree.
let root;
try {
  const commonDir = execSync('git rev-parse --git-common-dir').toString().trim();
  root = path.dirname(path.resolve(commonDir));
} catch {
  console.error('pr-state: must be run from within a git repository');
  process.exit(1);
}
const dir = path.join(root, 'tmp', 'babysit');
const file = path.join(dir, `${pr}.json`);

function load() {
  if (!fs.existsSync(file)) {
    return {
      pr: Number(pr),
      branch: null,
      status: 'unknown',
      iterations: 0,
      strikes: 0,
      lastBuild: null,
      escalated: false,
      attempts: [],
    };
  }
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    console.error(`pr-state: corrupt state file at ${file} — delete it to reset`);
    process.exit(1);
  }
}
function save(s) {
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(file, JSON.stringify(s, null, 2) + '\n');
}

const s = load();
switch (cmd) {
  case 'get':
    process.stdout.write(JSON.stringify(s, null, 2) + '\n');
    break;
  case 'set': {
    const [key, value] = rest;
    if (!key || value === undefined) {
      console.error('usage: pr-state.mjs set <pr> <key> <value>');
      process.exit(1);
    }
    s[key] = BOOL_FIELDS.has(key) ? value === 'true' : NUM_FIELDS.has(key) ? Number(value) : value;
    save(s);
    break;
  }
  case 'attempt': {
    const [build, outcome, ...note] = rest;
    if (!build || !outcome) {
      console.error('usage: pr-state.mjs attempt <pr> <build> <outcome> [note...]');
      process.exit(1);
    }
    s.attempts.push({ build, outcome, note: note.join(' ') });
    s.iterations = s.attempts.length;
    s.lastBuild = build;
    // Derive strikes from the full history (also migrates state files lacking it):
    // forward progress (a green build or a fix we stand behind) resets the count;
    // any non-progress outcome (paused, retriggered, …) adds a strike.
    let strikes = 0;
    for (const a of s.attempts) {
      if (a.outcome === 'green' || a.outcome === 'pushed') strikes = 0;
      else strikes += 1;
    }
    s.strikes = strikes;
    const retriggers = s.attempts.filter(a => a.outcome === 'retriggered').length;
    if (s.strikes >= ESCALATE_AFTER || retriggers >= RETRIGGER_CAP) s.escalated = true;
    save(s);
    break;
  }
  case 'escalate':
    s.escalated = true;
    save(s);
    break;
  default:
    console.error(`unknown command: ${cmd}`);
    process.exit(1);
}
