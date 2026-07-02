const test = require('node:test');
const assert = require('node:assert');
const clamp = require('./clamp');

test('in-range value is returned unchanged', () => {
  assert.strictEqual(clamp(5, 0, 10), 5);
});

test('value below lo is clamped up to lo', () => {
  assert.strictEqual(clamp(-5, 0, 10), 0);
});

test('value above hi is clamped down to hi', () => {
  assert.strictEqual(clamp(15, 0, 10), 10);
});

test('Infinity and -Infinity are valid numeric values and do not throw', () => {
  assert.strictEqual(clamp(5, -Infinity, 10), 5);
  assert.strictEqual(clamp(-100, -Infinity, 10), -100);
  assert.strictEqual(clamp(100, 0, Infinity), 100);
});

test('non-number n throws TypeError', () => {
  assert.throws(() => clamp('5', 0, 10), TypeError);
  assert.throws(() => clamp(null, 0, 10), TypeError);
  assert.throws(() => clamp(undefined, 0, 10), TypeError);
  assert.throws(() => clamp({}, 0, 10), TypeError);
  assert.throws(() => clamp(NaN, 0, 10), TypeError);
});

test('non-number lo throws TypeError', () => {
  assert.throws(() => clamp(5, '0', 10), TypeError);
  assert.throws(() => clamp(5, NaN, 10), TypeError);
});

test('non-number hi throws TypeError', () => {
  assert.throws(() => clamp(5, 0, '10'), TypeError);
  assert.throws(() => clamp(5, 0, NaN), TypeError);
});
