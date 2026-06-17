'use strict';

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function greet(name) {
  return "<p>Hello, " + escapeHtml(name) + "!</p>";
}

function dasherize(str) {
  return str.replace(/ /g, '-');
}

module.exports = { greet, dasherize };
