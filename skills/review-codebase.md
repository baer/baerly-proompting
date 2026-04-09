---
name: codebase-review
description: Deep TypeScript codebase audit with library-aware subagent analysis. Writes findings to .claude/reviews/.
---

# Codebase Review

You are conducting a technical audit of a TypeScript codebase. Your objective is to identify defects, anti-patterns, and deviations from established best practices. Findings must be grounded in code you have read — speculation is inadmissible.

All intermediate analysis is persisted to `.claude/reviews/` so that findings survive context compression and are available for follow-up.

Arguments: $ARGUMENTS

---

## Phase 0: Scope

<scope_instructions>
Before any analysis, determine the review scope using AskUserQuestion. Present the following questions:

**Question 1: "What should be reviewed?"**
Options depend on whether this is a monorepo (check for `pnpm-workspace.yaml`, `workspaces` in `package.json`, or multiple `package.json` files):
- If monorepo: list each package/app as an option, plus "Entire repository"
- If single package: list top-level `src/` subdirectories as options, plus "Entire codebase"
- Always include an option for "Specific path" (let them type a glob or directory)

If $ARGUMENTS already specifies a path or package, skip this question and use the argument.

**Question 2: "What dimensions should the review focus on?"**
Options (multiSelect: true):
- "All dimensions" (type safety, security, performance, architecture, error handling)
- "Security & authorization"
- "Performance & efficiency"
- "Type safety & correctness"
- "Architecture & patterns"
- "Error handling & resilience"
- "Dependency health" (deprecated, vulnerable, unmaintained, severely outdated packages)
- "Modernization advisory" (community-disfavored libraries, toolchain upgrades, unnecessary polyfills)

If $ARGUMENTS already specifies a focus (e.g., "security"), skip this question.

After scoping, create the review output directory:
```
mkdir -p .claude/reviews
```

Proceed to Phase 1 with the confirmed scope.
</scope_instructions>

---

## Phase 1: Discovery

<discovery_instructions>

### Step 1: Read project context files

Before launching any subagents, read these files yourself to calibrate expectations:

1. **Rules files**: Read all `.claude/rules/*.md` files. These are path-scoped instructions that document intentional project conventions — patterns documented here are not defects.
2. **Documentation**: Read all files in `docs/` (or equivalent doc directories). Pay special attention to:
   - Extension/contribution guides (they define the declared patterns — deviations are findings)
   - Shared dependency maps (they show type flow between packages — follow these to find type safety issues)
   - Testing guides (they document test infrastructure and coverage expectations)
3. **MCP servers**: Read `.claude/mcp.json` if it exists. Note which MCP servers are available — these provide direct access to libraries docs, GitHub data, and databases that are faster and more authoritative than web search. Record available servers in the inventory for use in Phase 2.

### Step 2: Build codebase inventory

Use the Agent tool with `subagent_type: "Explore"` and thoroughness "very thorough" to build a complete inventory of the scoped codebase. The Explore agent should:

1. Read all `package.json` files within scope — extract dependencies, devDependencies, scripts, and build tooling.
2. Read all `tsconfig.json` files within scope — extract strict mode, module resolution, path aliases, target.
3. Read lint/format configs (eslint, prettier, biome) — extract enforced rules.
4. Map project structure — directories, entry points, module boundaries.
5. Sample 3-5 representative source files — detect naming conventions, import patterns, error handling approach, state management, data fetching patterns.
6. Read any `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, or architecture docs for declared conventions.
7. Identify test infrastructure — test runner config, coverage thresholds, mutation testing config, test types (unit, integration, e2e, property-based, etc.).

The Explore agent should return a structured inventory. Do NOT produce findings during discovery.

After the Explore agent returns, write the inventory to `.claude/reviews/00-inventory.md` using the Write tool. Incorporate what you learned from the rules and docs files in Step 1. Structure it as:

```markdown
# Codebase Inventory

## Scope
[What is being reviewed]

## Tech Stack
[Frameworks, libraries, build tools, runtimes]

## Dependencies of Note
[Libraries that warrant specialized analysis — anything beyond trivial utilities]

## Project Structure
[Directory layout, module boundaries, monorepo topology if applicable]

## Detected Conventions
[Naming, imports, error handling, state management, testing patterns]

## Configuration
[tsconfig strictness, lint rules, path aliases]

## Declared Standards
[Anything from CLAUDE.md, README, CONTRIBUTING, or architecture docs]

## Project Rules (.claude/rules/)
[Summary of path-scoped rules — these define intentional conventions that should NOT be flagged as defects]

## Available MCP Servers
[List servers from .claude/mcp.json with what each provides. Note: subagents should use these during Phase 2.]

## Test Infrastructure
[Test runner, test types, coverage thresholds, mutation testing config, key test utilities]

## Validation Commands
[Commands available for automated checks: typecheck, lint, test, etc.]

## Dependency Summary
[Only if dependency health or modernization advisory selected — package manager, lock file location, total dependency count, workspace topology]
```

### Step 2a: Dependency Data Collection (conditional)

> **Run this step only if "Dependency health" or "Modernization advisory" was selected in Phase 0.** If neither was selected, skip to Phase 2.

Collect raw dependency data once so that downstream subagents don't duplicate slow commands:

1. **Identify package manager and lock file.** Check for `yarn.lock`, `pnpm-lock.yaml`, or `package-lock.json`. Note the manager and version (e.g., `yarn --version`).

2. **Run outdated check.** Execute the appropriate command and capture full output:
   - Yarn: `yarn outdated --json` (or `yarn upgrade-interactive --json` for Yarn 4+, whichever produces parseable output)
   - npm: `npm outdated --json`
   - pnpm: `pnpm outdated --format json`

3. **Run audit.** Execute the appropriate command:
   - Yarn Classic: `yarn audit --json`
   - Yarn 4+: `yarn npm audit --all --json`
   - npm: `npm audit --json`
   - pnpm: `pnpm audit --json`

4. **Extract dependency lists.** Read all `package.json` files within scope and collect every `dependencies` and `devDependencies` entry with its declared version range.

5. **Write raw data** to `.claude/reviews/00-dep-data.md`:

```markdown
# Dependency Data

## Package Manager
[Manager name, version, lock file path]

## Outdated Packages (raw)
\`\`\`json
[Full JSON output from outdated command]
\`\`\`

## Audit Results (raw)
\`\`\`json
[Full JSON output from audit command]
\`\`\`

## Dependency List
| Package | Declared Version | Source |
|---------|-----------------|--------|
[Every dependency from every package.json, noting which package.json it came from]
```

Add a "Dependency Summary" section to `00-inventory.md` with: package manager, lock file path, total dependency count, and workspace topology (if monorepo).
</discovery_instructions>

---

## Phase 2: Analysis Queue

<queue_instructions>
Read `.claude/reviews/00-inventory.md`. Based on the detected tech stack and the selected review dimensions, construct a task list using TaskCreate for each analysis pass.

### Core Analysis Tasks

Always include these (filtered by the dimensions selected in Phase 0):

| Task | Dimension | Description |
|------|-----------|-------------|
| Type Safety | type safety & correctness | `any` types, unsafe assertions, bags of optionals, missing discriminated unions, `{}` misuse, untyped parameters, non-exhaustive switches, missing `readonly` |
| Error Handling | error handling & resilience | Swallowed errors, untyped catch, floating promises, missing error boundaries, leaked internals in error messages, missing retry logic, inconsistent error shapes |
| Security | security & authorization | SQL injection, XSS, command injection, secrets exposure, missing input validation, CORS misconfiguration, missing rate limiting, JWT verification gaps, IDOR, path traversal |
| Performance | performance & efficiency | N+1 queries, missing indexes, unbounded fetches, blocking operations, large bundle imports, missing caching, redundant API calls |
| Architecture | architecture & patterns | Circular dependencies, business logic in UI, tight coupling, inconsistent patterns, missing abstraction boundaries, dead code, dependency direction violations |

### Library-Specific Analysis Tasks

For each significant library detected in the inventory, create an additional task. Each library task will be executed by a dedicated subagent that first researches current best practices before reviewing code.

The library registry below lists known checks. For libraries not in this registry, the subagent should search the web for best practices before reviewing.

**React / React DOM**: Unnecessary re-renders, effects that should be derived values, missing effect cleanup, stale closures, incorrect dependency arrays, `dangerouslySetInnerHTML`, key anti-patterns, context overuse causing full-tree re-renders.

**Next.js**: Client/server boundary violations, `'use client'` too high in tree, secrets in client bundles, missing `loading.tsx`/`error.tsx`, client-side fetching where server-side suffices, missing metadata, improper `server-only` usage, dynamic `process.env` lookups, Server Action validation gaps.

**Drizzle ORM**: N+1 queries, missing prepared statements, unsafe raw SQL interpolation, missing transaction boundaries, incorrect join types, missing implied indexes, connection pool exhaustion.

**Hono**: Middleware ordering errors, missing error middleware, handlers separated from routes (breaks type inference), missing input validation, CORS misconfiguration, missing rate limiting.

**Zod**: Schema/data shape divergence, missing `.transform()` at API boundaries, `z.any()`/`z.unknown()` without refinement, duplicate schemas that should be derived, client/server schema mismatch.

**Tailwind CSS**: Dynamic class construction (`bg-${color}-500`), conflicting utilities, missing responsive considerations, hardcoded values bypassing design tokens.

**Vercel AI SDK**: Missing stream error handling, deprecated `content` property (should use `message.parts`), missing `experimental_throttle`, improper abort handling, missing `onError`, stale closures.

**Clerk**: Missing auth middleware on protected routes, JWT verification gaps, secrets in client code, missing role/permission checks.

**Cloudflare Workers**: Mutable global state, event loop blocking, `Date.now()` assumptions (returns last I/O time), isolate eviction handling.

**shadcn/ui + Radix**: Missing labels, improper ARIA attributes, uncontrolled/controlled mixing, missing keyboard navigation, portal/z-index conflicts.

### Dependency Analysis Tasks (conditional)

If "Dependency health" or "Modernization advisory" was selected in Phase 0, add these tasks. Both require `00-dep-data.md` from Step 2a (Phase 1 must complete first). They are independent of each other and of library-specific tasks.

| Task | Dimension | Condition | Description |
|------|-----------|-----------|-------------|
| Dependency Health | dependency health | Only if "Dependency health" selected | Deprecated, vulnerable, unmaintained, severely outdated packages, known drop-in replacements |
| Modernization Advisory | modernization advisory | Only if "Modernization advisory" selected | Community-disfavored libraries, toolchain upgrades, unnecessary polyfills |

After creating all tasks, set up dependencies: library-specific tasks should not block each other, dependency analysis tasks should not block each other, but the aggregation task (Phase 3) should be blocked by all analysis tasks (core, library-specific, and dependency).
</queue_instructions>

---

## Phase 2b: Execute Analysis

<execution_instructions>
Execute each task from the queue. For each task, update its status to `in_progress` via TaskUpdate before starting.

### Automated Pre-Analysis

Before manual analysis, run available validation commands and write results to `.claude/reviews/00-automated.md`:

1. **Type checking**: Run `pnpm typecheck` (or the project's equivalent). Record errors — these are confirmed type safety issues that don't need manual discovery.
2. **Linting**: Run `pnpm lint` (or equivalent). Record violations — if ESLint already flags an issue, note it as "caught by tooling" (lower priority than undetected issues).
3. **Test coverage** (if available): Run tests with coverage reporting or check existing coverage config. Files with low/no coverage are higher risk and should be prioritized for manual review.
4. **Mutation testing config** (if present): Check which source files are targeted — these are the files the project considers most important.

Use these results to prioritize manual analysis: focus review effort on code that automated tools don't already catch and on under-tested files.

### Core Analysis Tasks (run directly)

For each core task (type safety, error handling, security, performance, architecture):

1. Use Grep and Glob to locate all files within scope relevant to the task.
2. Use Read to examine each file. Do not make claims about unread code.
3. For each finding, extract the exact code snippet as evidence before formulating the finding.
4. Before flagging a pattern, use Grep to check whether it is used consistently across the codebase. Consistent project conventions are noted as conventions, not defects.
5. Assign severity:
   - **critical** (9-10): Security vulnerabilities, data loss, production crashes
   - **high** (7-8): Bugs under normal usage, significant performance degradation
   - **medium** (5-6): Functional code that violates best practices with real maintenance cost
   - **low** (3-4): Minor improvements — include only if systemic (3+ occurrences)

After completing each core task, write findings to `.claude/reviews/[task-name].md` using the Write tool:

```markdown
# [Task Name] Analysis

## Scope
[Files examined]

## Findings

### Finding 1: [One-line description]
- **File:** `path/to/file.ts:LINE`
- **Severity:** critical|high|medium|low (N/10)
- **Evidence:**
  ```typescript
  // exact code from the file
  ```
- **Analysis:** [Why this is a defect or anti-pattern. Cite the specific best practice violated.]
- **Recommendation:**
  ```typescript
  // concrete fix
  ```

### Finding 2: ...

## Systemic Patterns
[Patterns appearing in 3+ locations, listed with all file paths]

## No Issues Found
[Areas examined where no defects were identified — listed for audit completeness]
```

Mark the task as `completed` via TaskUpdate after writing the file.

### Library-Specific Tasks (run via subagents in parallel)

For each library-specific task, spawn a subagent using the Agent tool with `subagent_type: "general-purpose"`. Launch all library subagents in a single message to maximize parallelism.

Each subagent receives this prompt (fill in the bracketed values):

```
You are auditing a TypeScript codebase for [LIBRARY] best practices. This is a technical audit — report defects and anti-patterns only. Do not soften findings.

## Step 1: Research
First, check if a context7 MCP server is available. If it is, use it to fetch current documentation for [LIBRARY] — this is faster and more authoritative than web search. Then supplement with web search only for topics not covered by the MCP docs.

If no context7 MCP server is available, search the web for "[LIBRARY] best practices [CURRENT_YEAR]" and "[LIBRARY] anti-patterns [CURRENT_YEAR]". Read the library's official documentation for recommended patterns. Note any recent API changes or deprecations.

## Step 2: Review
Examine the following files for [LIBRARY]-specific issues:
[FILE LIST — use Glob to find relevant files, then list them]

For each finding, provide:
- file_path and line_number (you MUST read the file and cite the exact line)
- severity: critical (9-10), high (7-8), medium (5-6), low (3-4)
- category: the specific best practice violated
- evidence: the exact code snippet from the file
- analysis: why this deviates from the established best practice, with reference to the documentation or expert source
- recommendation: concrete code fix

## Step 3: Output
Only report findings with severity >= 5, unless the pattern appears in 3+ files.
If a file follows best practices correctly, do not mention it.
Do not manufacture findings. If the code is correct, return an empty findings list.

Write your complete findings to `.claude/reviews/lib-[LIBRARY_SLUG].md` using the Write tool, following this format:

# [LIBRARY] Analysis

## Sources Consulted
[URLs and documentation sections referenced]

## Findings
[Structured findings as above]

## Systemic Patterns
[Repeated anti-patterns with all locations]
```

### Dependency Health Task (conditional, run via subagent)

> **Run only if "Dependency health" was selected in Phase 0.** Spawn a `general-purpose` subagent. Can run in parallel with library-specific subagents.

The subagent receives this prompt:

```
You are auditing a project's dependency health. This is a technical audit — report actionable defects only. These findings are treated the same as code defects.

## Data
Read `.claude/reviews/00-dep-data.md` — it contains pre-collected audit and outdated JSON. Do NOT re-run `yarn audit`, `yarn outdated`, or equivalent commands.

## Checks

### 1. Known Vulnerabilities
Parse the audit JSON from `00-dep-data.md`. For each vulnerability:
- Record the package, severity (from audit), vulnerability ID, and affected version range.
- Map audit severity to review severity: audit critical → 10, audit high → 8, audit moderate → 6, audit low → 4.

### 2. Deprecated Packages
For each direct dependency (not transitive), run `npm view <pkg> deprecated` to check the npm deprecated field. If deprecated, record the deprecation message. Severity: 7 (high).

### 3. Unmaintained Packages
For each direct dependency, run `npm view <pkg> time --json` to get publish timestamps. Flag packages with no publish in 2+ years. Check if the GitHub repo is archived (use `npm view <pkg> repository` to find the repo URL, then check via `gh api`). Severity: 6 (medium) for stale, 7 (high) for archived.

### 4. Severely Outdated
From the outdated JSON in `00-dep-data.md`, flag packages that are 2+ major versions behind latest. Severity: 5 (medium).

### 5. Known Drop-in Replacements
Check every direct dependency against this registry. If a match is found, flag it.

| Package | Replacement | Notes | Severity |
|---------|------------|-------|----------|
| `request` | native `fetch` | Deprecated since 2020 | 7 |
| `node-uuid` | `uuid` | Renamed | 6 |
| `mkdirp` | `fs.mkdir` with `recursive: true` | Node 10+ built-in | 5 |
| `rimraf` | `fs.rm` with `recursive: true` | Node 14+ built-in | 5 |
| `colors` | `picocolors` or `chalk` | Sabotaged in v1.4.1 | 8 |
| `faker` | `@faker-js/faker` | Community fork after sabotage | 8 |
| `querystring` | `URLSearchParams` | Node built-in | 5 |
| `path-is-absolute` | `path.isAbsolute` | Node built-in | 5 |
| `os-tmpdir` | `os.tmpdir` | Node built-in | 5 |
| `is-promise` | native `instanceof Promise` or duck typing | Trivial built-in | 5 |
| `string_decoder` | `TextDecoder` | Web standard | 5 |
| `left-pad` | `String.prototype.padStart` | ES2017 built-in | 5 |
| `node-fetch` | native `fetch` | Node 18+ built-in | 5 |
| `abort-controller` | native `AbortController` | Node 15+ built-in | 5 |
| `cross-fetch` | native `fetch` | Node 18+ built-in (check target runtime) | 5 |
| `glob` | `fs.glob` | Node 22+ built-in (check target runtime) | 5 |

## Output
Write findings to `.claude/reviews/dep-health.md`:

# Dependency Health Analysis

## Findings

### Finding N: [Package — issue type]
- **Package:** `package-name` (declared version)
- **Severity:** critical|high|medium|low (N/10)
- **Category:** vulnerability | deprecated | unmaintained | severely-outdated | drop-in-replacement
- **Evidence:** [Deprecation message, audit advisory ID, last publish date, or replacement rationale]
- **Recommendation:** [Specific action — upgrade to version X, replace with Y, remove if unused]

## Summary
| Category | Count |
|----------|-------|
| Vulnerabilities | N |
| Deprecated | N |
| Unmaintained | N |
| Severely Outdated | N |
| Drop-in Replacements | N |
```

### Modernization Advisory Task (conditional, run via subagent)

> **Run only if "Modernization advisory" was selected in Phase 0.** Spawn a `general-purpose` subagent. Can run in parallel with library-specific subagents.

The subagent receives this prompt:

```
You are producing a modernization advisory for a TypeScript project. These are strategic suggestions, NOT defects. They do not count toward the finding cap. Frame every suggestion as advisory with trade-offs.

## Data
Read `.claude/reviews/00-dep-data.md` and `.claude/reviews/00-inventory.md`.

## Checks

### 1. Community-Disfavored Libraries
Check every direct dependency against this registry. Only flag when the usage pattern warrants it (see Notes column).

| Current | Suggested | Notes | Effort |
|---------|-----------|-------|--------|
| `moment` | `date-fns`, `dayjs`, or `Temporal` | Flag any import of moment | medium |
| `lodash` (full) | native ES2020+, `lodash-es`, or individual imports | Only flag `import _ from 'lodash'` or `import * as _ from 'lodash'`, NOT `lodash/get` etc. | medium |
| `underscore` | native ES2020+ | Flag any import | medium |
| `jest` | `vitest` | Only flag if project already uses Vite or ESM | medium |
| `mocha` + `chai` | `vitest` | Flag any setup | medium |
| `webpack` | `vite` or `rspack` | Only flag if not deeply customized | large |
| `enzyme` | `@testing-library/react` | Flag any import | medium |
| `express` | `hono`, `fastify`, or `h3` | Only flag for new projects or if perf is a stated concern | large |
| `request-promise` | native `fetch` | Flag any import (deprecated) | small |
| `bluebird` | native Promises | Flag unless using specific Bluebird features (cancellation, `.map` concurrency) | small |
| `q` | native Promises | Flag any import | small |
| `tslint` | `eslint` or `biome` | TSLint is deprecated | medium |
| `eslint` | `biome` or `oxlint` | Only flag if project has simple config (< 5 plugins) | medium |
| `prettier` | `biome` or `dprint` | Only flag if project also uses biome for linting | trivial |
| `classnames` | `clsx` | Drop-in with smaller bundle | trivial |
| `node-sass` | `sass` (Dart Sass) | node-sass is deprecated | small |
| `protobufjs` | `@bufbuild/protobuf` | Only flag if also using gRPC | medium |

### 2. Unnecessary Polyfills
Read `tsconfig.json` to determine the target runtime (check `target`, `lib`, and `engines` in `package.json`). Flag polyfills that are unnecessary for the target:
- `core-js` features already in the target
- `regenerator-runtime` if target supports async/await
- `whatwg-fetch` / `cross-fetch` if target has native fetch
- `abortcontroller-polyfill` if target has AbortController

### 3. Verify Alternatives
For each suggestion, use web search to verify:
- The suggested alternative is actively maintained (published within last 6 months)
- It has significant adoption (>1,000 weekly npm downloads)
- It is >= v1.0 or has wide production adoption despite pre-1.0 version
- **Do NOT recommend** alternatives that fail any of these checks

### 4. Stability Assessment
For each verified suggestion, document:
- Current version of the alternative
- Release cadence (approximate)
- Backing organization or key maintainers
- Weekly download count (approximate)

### 5. Effort Estimate
Assign effort for each suggestion:
- **trivial**: Drop-in replacement, no API changes, < 1 hour
- **small**: Minor API differences, < 1 day
- **medium**: Significant API changes, 1-3 days, may require test updates
- **large**: Architectural change, 3+ days, affects build pipeline or multiple packages

## Output
Write findings to `.claude/reviews/dep-modernization.md`:

# Modernization Advisory

> These are strategic suggestions, not defects. Evaluate against your project roadmap and priorities.

## Suggestions

### Suggestion N: [Current] → [Suggested]
- **Current:** `package-name` (version in use)
- **Suggested:** `alternative-name` (latest version)
- **Effort:** trivial | small | medium | large
- **Priority:** high | medium | low (based on staleness of current + maturity of alternative)
- **Stability Assessment:**
  - Version: [latest version]
  - Release cadence: [approximate]
  - Backing: [org or maintainers]
  - Downloads: [approximate weekly]
- **Rationale:** [Why the community has moved away from the current library]
- **Trade-offs:** [What you lose, migration risks, edge cases]
- **Migration path:** [Brief description of the migration approach]
- **Files affected:** [List of files importing the current library]

## Summary Table
| Current | Suggested | Effort | Stability | Priority |
|---------|-----------|--------|-----------|----------|
[One row per suggestion]
```
</execution_instructions>

---

## Phase 3: Aggregation

<aggregation_instructions>
After all analysis tasks are complete (check via TaskList — all tasks should be `completed`):

1. Read every `.md` file in `.claude/reviews/` (except `00-inventory.md`, `00-dep-data.md`, and `REPORT.md`).

2. Separate findings into two pools:
   - **Tier 1 (defects):** All findings from core tasks, library-specific tasks, and `dep-health.md`. These are treated as regular defects.
   - **Tier 2 (advisory):** All suggestions from `dep-modernization.md`. These are strategic suggestions and are handled separately.

3. **Tier 1 processing:**

   a. Collect all Tier 1 findings into a single list.

   b. Deduplicate by file + line range + issue category. When two analyses flag the same issue, retain the finding with more specific evidence. Dependency health findings that overlap with library-specific findings are deduplicated in favor of the more specific library-specific finding.

   c. Merge systemic findings. If the same anti-pattern appears in 3+ files across different analysis passes, consolidate into a single systemic finding listing all locations.

   d. Apply severity threshold. Discard findings with severity < 5 unless systemic (3+ occurrences).

   e. Sort by severity descending, then by file path.

   f. Cap at 20 findings. If more exist after filtering, retain the highest-severity. Note the total unfiltered count.

4. **Tier 2 processing:** Collect all modernization suggestions. Do NOT apply severity threshold or the 20-finding cap. Sort by priority (high → medium → low).

5. Validate grounding. For each Tier 1 finding, confirm that the cited file and line number match the evidence snippet. Discard any finding that cannot be traced to a specific line in a file you read. For Tier 2 suggestions, confirm that the cited package exists in the project's dependencies.

6. Write the final report to `.claude/reviews/REPORT.md` using the Write tool:

```markdown
# Codebase Audit Report

**Scope:** [what was reviewed]
**Date:** [current date]
**Dimensions:** [which review dimensions were applied]
**Files examined:** [count]
**Findings:** [count after filtering] ([count before filtering] pre-filter)

---

## Critical & High Severity

### [Finding title]
- **File:** `path/to/file.ts:LINE`
- **Severity:** critical|high (N/10)
- **Category:** [type safety | security | performance | architecture | error handling | library-specific | dependency-health]
- **Evidence:**
  ```typescript
  // exact code
  ```
- **Analysis:** [Technical explanation of the defect. Reference the specific best practice, documentation section, or security standard violated.]
- **Recommendation:**
  ```typescript
  // concrete fix
  ```

---

## Medium Severity

[Same format, grouped by category]

---

## Systemic Patterns

[Anti-patterns appearing across multiple files. One entry per pattern with all locations listed.]

---

## Dependency Health

> Vulnerabilities, deprecated, unmaintained, and severely outdated packages. These are included in the main findings above by severity.

[Summary table of dependency health findings, if "Dependency health" was selected. Omit this section entirely if not selected.]

| Package | Category | Severity | Action |
|---------|----------|----------|--------|
[One row per dependency health finding]

---

## Modernization Advisory

> Strategic suggestions — not defects. Evaluate against your project roadmap. These do NOT count toward the finding cap.

[Include this section only if "Modernization advisory" was selected. Omit entirely if not selected.]

| Current | Suggested | Effort | Stability | Priority |
|---------|-----------|--------|-----------|----------|
[One row per suggestion from dep-modernization.md]

[Below the table, include the full detailed entries from dep-modernization.md: rationale, trade-offs, migration path, and files affected for each suggestion.]

---

## Filtered Items

[One-line summaries of findings below threshold, so they can be expanded on request.]

---

## Methodology

[List of analysis passes executed, subagents spawned, and sources consulted. This section exists for reproducibility.]
```

7. After writing the report, present a summary to the user. State the number of findings by severity tier, the most critical finding in one sentence, and note that the full report is at `.claude/reviews/REPORT.md`. If modernization advisory was included, mention the number of suggestions separately (e.g., "plus 3 modernization suggestions").
</aggregation_instructions>

---

## Behavioral Constraints

<constraints>
- Do not speculate about code you have not read. Every finding must cite a file path and line number from a file you opened with the Read tool.
- Do not flag deliberate project conventions as defects. If a pattern is consistent across the codebase and documented in CLAUDE.md or lint config, it is intentional until proven otherwise.
- Do not manufacture findings. If a section of the codebase is sound, say nothing about it. An audit that reports zero findings in a category is a valid outcome.
- Do not soften language. Use precise technical terminology. "This introduces a SQL injection vector" not "this might potentially have some security implications."
- Every finding requires a concrete recommendation with code. Identifying a problem without proposing a fix is incomplete analysis.
- Cap output at 20 findings. A focused report with 5 critical findings is more actionable than an exhaustive list of 50. Modernization advisory suggestions do NOT count toward this cap.
- Write all intermediate analysis to `.claude/reviews/` files. This ensures findings persist across context compression and are available for follow-up review.
- Advisory findings (modernization suggestions) are never assigned severity scores. Use effort + priority instead.
- Never recommend bleeding-edge alternatives without verified production adoption (>1,000 weekly downloads, >= v1.0 or widely adopted pre-1.0).
- Dependency health findings that duplicate library-specific findings are deduplicated in favor of the more specific finding.
- "All dimensions" does NOT auto-include "Dependency health" or "Modernization advisory". These are separate opt-ins because they run external commands and web searches, adding time and cost.
</constraints>
