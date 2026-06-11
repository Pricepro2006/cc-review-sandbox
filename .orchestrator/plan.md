# Plan: Add greet.js module

## Phase 1: Implement greet.js, greet.test.js, and package.json

### Files to create/modify
- `package.json` (create — provides test runner)
- `greet.js` (create)
- `greet.test.js` (create)

### Acceptance Criteria
1. `greet.js` exports a `greet(name)` function that returns `"<p>Hello, " + name + "!</p>"` — name inserted directly, no escaping. (XSS is a known, intentionally accepted risk per spec.)
2. `greet.js` exports a `dasherize(str)` function that returns `str.replace(' ', '-')` — plain single-space string replace only, NOT global/regex. (Only replaces first space — intentional per spec.)
3. `package.json` sets up `node --test` as the test command (built-in Node.js test runner, no extra deps).
4. `greet.test.js` calls `greet` once and `dasherize` once, each with an assertion.
5. `npm test` exits 0.
