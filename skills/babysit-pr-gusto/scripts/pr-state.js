#!/usr/bin/env node
import { execSync } from 'child_process';
// pr-state.js — read/append per-PR babysit state at <repo>/tmp/babysit/<pr>.json
//
// Usage:
//   pr-state.js get <pr>
//   pr-state.js set <pr> <key> <value>
//   pr-state.js attempt <pr> <build> <outcome> <note...>
//   pr-state.js escalate <pr>
import fs from 'fs';
import path from 'path';

const ESCALATE_AFTER = 3;
const root = execSync('git rev-parse --show-toplevel').toString().trim();
const dir = path.join(root, 'tmp', 'babysit');
const [, , cmd, pr, ...rest] = process.argv;

if (!cmd || !pr) {
  console.error('usage: pr-state.js <get|set|attempt|escalate> <pr> [...]');
  process.exit(1);
}
const file = path.join(dir, `${pr}.json`);

function load() {
  if (!fs.existsSync(file)) {
    return {
      pr: Number(pr),
      branch: null,
      status: 'unknown',
      iterations: 0,
      lastBuild: null,
      escalated: false,
      attempts: [],
    };
  }
  return JSON.parse(fs.readFileSync(file, 'utf8'));
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
    s[key] = value;
    save(s);
    break;
  }
  case 'attempt': {
    const [build, outcome, ...note] = rest;
    s.attempts.push({ build, outcome, note: note.join(' ') });
    s.iterations = s.attempts.length;
    s.lastBuild = build ? `build ${build}` : s.lastBuild;
    if (outcome !== 'green' && s.iterations >= ESCALATE_AFTER) s.escalated = true;
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
