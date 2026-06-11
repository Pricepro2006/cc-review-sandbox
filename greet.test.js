const { test } = require('node:test');
const assert = require('node:assert/strict');
const { greet, dasherize } = require('./greet');

test('greet returns an HTML paragraph', () => {
  assert.equal(greet('World'), '<p>Hello, World!</p>');
});

test('dasherize replaces the first space with a hyphen', () => {
  assert.equal(dasherize('hello world'), 'hello-world');
});
