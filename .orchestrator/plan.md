# Plan: Add clamp utility

**project_id:** g8-clamp-utility

## Phase 1: Add util/clamp.js and util/clamp.test.js

### Files to create/modify
- `util/clamp.js` (new)
- `util/clamp.test.js` (new)

### Description
Create `util/clamp.js` exporting a single function `clamp(n, lo, hi)` that returns
`n` bounded to the inclusive range `[lo, hi]`. The function must validate its
inputs and throw a `TypeError` when `n`, `lo`, or `hi` is not of type `number`,
or is `NaN`. `Infinity` and `-Infinity` are valid numeric values (e.g. `lo` may
be `-Infinity` to only cap the upper bound) and must NOT throw.

Create `util/clamp.test.js` using `node:test` and `node:assert` covering:
1. In-range value is returned unchanged.
2. Value below `lo` is clamped up to `lo`.
3. Value above `hi` is clamped down to `hi`.
4. Non-number arguments (including `NaN`) throw `TypeError`.

Run the tests with the Node.js built-in test runner to confirm they pass.

After tests pass, commit `util/clamp.js` and `util/clamp.test.js` on a new
branch (not `main`), push the branch, and open a PR titled exactly:
`feat: add clamp utility (g8 acceptance)`.

### Acceptance criteria
1. `util/clamp.js` exports a single function `clamp(n, lo, hi)`.
2. `clamp` returns `n` when `lo <= n <= hi`.
3. `clamp` returns `lo` when `n < lo`.
4. `clamp` returns `hi` when `n > hi`.
5. `clamp` throws `TypeError` when any argument is not of type `number`, or is `NaN`. `Infinity`/`-Infinity` are valid and must not throw.
6. `util/clamp.test.js` uses `node:test` and `node:assert` and covers in-range, below, above, and error cases.
7. `node --test util/clamp.test.js` passes with zero failures.
8. A PR is opened on a new branch (not main) titled exactly: `feat: add clamp utility (g8 acceptance)`.
