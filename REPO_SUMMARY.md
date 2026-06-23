# Repository Summary: cc-review-sandbox

## Purpose

`cc-review-sandbox` is a **public throwaway sandbox repository** whose sole purpose is to acceptance-test the **CommandCenter (CMDC) automated review pipeline**. It is not a product codebase — it is a controlled proving ground used to exercise the pipeline's capabilities by having it create, review, and fix small JavaScript utility modules.

The README states it directly:
> "CommandCenter review pipeline sandbox. Public throwaway repo for proving the CMDC-0004 out-of-run review subsystem (4A read-only review, later 4B/4C). No sensitive content, ever."

---

## Repository Structure (on `main`)

The `main` branch contains almost nothing — just the README and the `.orchestrator/` directory. All source additions live on unmerged branches, representing completed but human-gated PRs.

```
cc-review-sandbox/
├── README.md                     # One-paragraph repo description
└── .orchestrator/
    ├── plan.md                   # Active task plan (most recent: parsePort utility)
    └── events.jsonl              # JSONL event log of all orchestrator state transitions
```

---

## The Orchestrator

The `.orchestrator/` directory is the pipeline's state-tracking layer:

### `plan.md`
Holds the plan for the most recently executed task in a structured Markdown format, including:
- Phase breakdown with files to create/modify
- Implementation details
- Numbered acceptance criteria
- `npm test` pass requirement

The most recent plan describes adding a `parsePort` utility.

### `events.jsonl`
A newline-delimited JSON event log capturing every state transition the orchestrator goes through. Each line is a timestamped event. The recorded state machine is:

```
PLANNING (plan_started → plan_saved → plan_approved)
  ↓
EXECUTING (phase_started → phase_completed)
  ↓
REVIEWING (review_in_progress → review_approved)
  ↓
DONE (sweep_started → sweep_passed → pr_opened)
```

The log covers multiple full runs from June 2026, including one run that ended with `pr_blocked` due to an invalid GitHub token.

---

## Source Modules Created by the Pipeline

All source files below exist on unmerged branches (the pipeline opens PRs; a human merges).

### `greet.js` — on branch `add-greet-module`

Two CommonJS exports:

**`greet(name)`**
Returns an HTML paragraph element greeting the given name:
```javascript
greet("Alice") // → "<p>Hello, Alice!</p>"
```
Internally calls `escapeHtml()` to prevent XSS — a fix applied after the initial reviewer flagged the original unescaped version. The `escapeHtml` helper escapes `&`, `<`, `>`, `"`, and `'`.

**`dasherize(str)`**
Replaces all spaces in a string with hyphens:
```javascript
dasherize("hello world foo") // → "hello-world-foo"
```
Fixed from the original version that only replaced the first space (used `.replace(/ /g, '-')` with global flag after reviewer feedback).

---

### `src/parsePort.js` — on branch `feat/parse-port-utility`

One named export:

**`parsePort(input)`**
Converts a string to an integer TCP/IP port number. Includes strict validation:
- Rejects partial-numeric strings (e.g., `'3000abc'`)
- Rejects non-numeric strings (e.g., `'abc'`)
- Rejects empty string
- Rejects port `0` (below valid range)
- Rejects ports above `65535`
- Throws `RangeError` on any invalid input

```javascript
parsePort('3000')    // → 3000 (integer)
parsePort('65535')   // → 65535
parsePort('0')       // throws RangeError
parsePort('abc')     // throws RangeError
parsePort('3000abc') // throws RangeError
```

The initial implementation was a bare `parseInt(input, 10)` with no validation; input validation was added after reviewer feedback in a fix commit.

**`src/parsePort.test.js`** accompanies the module, using Node.js built-in `node:test` + `node:assert/strict`. It covers:
- Happy path: `'3000'` → `3000`
- Boundary cases: port `1` and port `65535`
- Error cases: non-numeric, partial-numeric, empty string, port `0`, port `65536`

---

### `percent.js` — on branch `g4b-trigger-flawed`

Two CommonJS exports for percentage arithmetic:

**`percentOf(part, whole)`**
Returns what percentage `part` is of `whole`. Guards against division by zero (returns `0` when `whole === 0`).

**`applyDiscount(price, percent)`**
Applies a percentage discount to a price. Clamps `percent` to `[0, 100]` before computing.

This module is notable because it was **deliberately introduced with bugs** to test the pipeline's autofix capability (CMDC-0009 G4b tier). The original commit (`fc8c94b`) contained three intentional bugs:
1. No zero-guard in `percentOf` → returned `Infinity`/`NaN`
2. Used `parseInt()` truncating to integer instead of returning a real percentage
3. `applyDiscount` used `+` instead of `-`, making "discounts" increase the price

A follow-up commit (`1a1fcf5`) corrected all three bugs. The expectation is that the review pipeline detects the flawed PR, issues `request_changes`, and automatically launches a "fix leg" to correct the errors.

---

### `SECURITY.md` — on branch `add-security-policy`

A standard security disclosure policy document covering:
- Instructions for responsible disclosure (no public issues before fix)
- Contact method (email or GitHub private security advisory)
- Response SLA: 48-hour acknowledgement, 7-business-day resolution timeline
- Coordinated disclosure after a fix is released
- Supported versions table (latest release only)

---

### `NOTES.md` — on branch `add-greet-module`

A simple change log file recording acceptance run dates. Example entry:
```
- 2026-06-12: Initial acceptance run recorded (CMDC-0007b)
```

---

## Branch Taxonomy

The repository uses a consistent branch naming scheme that reveals what each branch tests:

| Branch | Purpose |
|---|---|
| `main` | Baseline — only the seeded README |
| `add-greet-module` | Feature addition with XSS fix |
| `feat/parse-port-utility` | Feature addition with validation fix |
| `add-security-policy` | Documentation addition |
| `g4b-trigger-flawed` | Deliberately flawed PR to test autofix pipeline tier |
| `g1-acceptance-2026-06-12` | G1 (basic review) acceptance test |
| `cmdc-0007b-acceptance-2026-06-17` | CMDC-0007b (ntfy notifications) acceptance test |
| `cmdc-0007b-acceptance-2026-06-13` | Earlier CMDC-0007b acceptance run (token failure) |
| `pat-verify-test` | PAT merge-refusal verification (Lesson #26) |

---

## CMDC Pipeline Capabilities Demonstrated

1. **CMDC-0004 (4A read-only review)**: The pipeline reviews PRs it opens against the repo. Reviewer agents can approve, comment, or request changes.

2. **CMDC-0007b (ntfy notifications)**: The pipeline sends push notifications on key events. Acceptance runs record that notifications were received.

3. **G4b autofix tier**: When a reviewer issues `request_changes`, the pipeline automatically creates a fix commit addressing the review findings. The deliberately flawed `percent.js` is the test vector for this capability.

4. **PAT/token validation**: The `pat-verify-test` branch records a test that the pipeline refuses to merge when a Personal Access Token is invalid or lacks sufficient permission.

---

## Testing

Tests use **Node.js built-in test runner** (`node:test`) with `node:assert/strict`. No external test framework (Jest, Mocha, etc.) is used. Tests are run with `npm test`.

---

## Key Observations

- **Nothing on `main` is functional source code** — the repo's value is the pipeline activity it records, not the utilities it contains.
- **All feature branches are unmerged** and await human review before landing on `main`. This is intentional: the pipeline is designed to open PRs, not auto-merge.
- **The pipeline is iterative**: review cycles happen (e.g., `review_in_progress → review_approved` with a `note` explaining what was resolved), and fix commits are authored by the pipeline itself (co-authored by `Claude Sonnet 4.6`).
- **The `.orchestrator/` directory tracks pipeline state** across runs, acting as a lightweight state machine journal. The `events.jsonl` format allows replaying what happened in each run.
