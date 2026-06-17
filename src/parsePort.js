'use strict';

function parsePort(input) {
  const n = parseInt(input, 10);
  if (!Number.isInteger(n) || String(n) !== String(input).trim() || n < 1 || n > 65535) {
    throw new RangeError(`Invalid port: ${input}`);
  }
  return n;
}

module.exports = { parsePort };
