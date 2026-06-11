const { test } = require('node:test');
const assert = require('node:assert/strict');
const { greet, dasherize } = require('./greet');

test('greet returns an HTML paragraph', () => {
  assert.equal(greet('World'), '<p>Hello, World!</p>');
});

test('greet escapes HTML special characters', () => {
  assert.equal(greet('<script>alert(1)</script>'), '<p>Hello, &lt;script&gt;alert(1)&lt;/script&gt;!</p>');
});

test('dasherize replaces all spaces with hyphens', () => {
  assert.equal(dasherize('hello world'), 'hello-world');
});

test('dasherize replaces multiple spaces', () => {
  assert.equal(dasherize('hello world foo'), 'hello-world-foo');
});
