'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { greet, dasherize } = require('./greet');

test('greet returns an HTML paragraph', () => {
  assert.strictEqual(greet('World'), '<p>Hello, World!</p>');
});

test('greet escapes HTML special characters', () => {
  assert.strictEqual(greet('<script>alert(1)</script>'), '<p>Hello, &lt;script&gt;alert(1)&lt;/script&gt;!</p>');
});

test('greet escapes ampersand', () => {
  assert.strictEqual(greet('A&B'), '<p>Hello, A&amp;B!</p>');
});

test('greet escapes double quote', () => {
  assert.strictEqual(greet('say "hi"'), '<p>Hello, say &quot;hi&quot;!</p>');
});

test('greet escapes single quote', () => {
  assert.strictEqual(greet("It's"), '<p>Hello, It&#39;s!</p>');
});

test('dasherize replaces all spaces with hyphens', () => {
  assert.strictEqual(dasherize('hello world'), 'hello-world');
});

test('dasherize replaces multiple spaces', () => {
  assert.strictEqual(dasherize('hello world foo'), 'hello-world-foo');
});

test('dasherize returns empty string unchanged', () => {
  assert.strictEqual(dasherize(''), '');
});

test('dasherize returns string with no spaces unchanged', () => {
  assert.strictEqual(dasherize('nospaces'), 'nospaces');
});

test('dasherize handles leading and trailing spaces', () => {
  assert.strictEqual(dasherize(' hello '), '-hello-');
});
