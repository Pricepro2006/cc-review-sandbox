'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parsePort } = require('./parsePort');

test('parsePort returns an integer for a numeric string', () => {
  assert.strictEqual(parsePort('3000'), 3000);
});

test('parsePort accepts boundary port 1', () => {
  assert.strictEqual(parsePort('1'), 1);
});

test('parsePort accepts boundary port 65535', () => {
  assert.strictEqual(parsePort('65535'), 65535);
});

test('parsePort throws for non-numeric string', () => {
  assert.throws(() => parsePort('abc'), RangeError);
});

test('parsePort throws for partial-numeric string', () => {
  assert.throws(() => parsePort('3000abc'), RangeError);
});

test('parsePort throws for empty string', () => {
  assert.throws(() => parsePort(''), RangeError);
});

test('parsePort throws for port 0', () => {
  assert.throws(() => parsePort('0'), RangeError);
});

test('parsePort throws for port 65536', () => {
  assert.throws(() => parsePort('65536'), RangeError);
});
