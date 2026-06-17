'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parsePort } = require('./parsePort');

test('parsePort returns an integer for a numeric string', () => {
  assert.strictEqual(parsePort('3000'), 3000);
});
