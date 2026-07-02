function clamp(n, lo, hi) {
  if (typeof n !== 'number' || Number.isNaN(n)) {
    throw new TypeError('clamp: "n" must be a number');
  }
  if (typeof lo !== 'number' || Number.isNaN(lo)) {
    throw new TypeError('clamp: "lo" must be a number');
  }
  if (typeof hi !== 'number' || Number.isNaN(hi)) {
    throw new TypeError('clamp: "hi" must be a number');
  }

  if (n < lo) return lo;
  if (n > hi) return hi;
  return n;
}

module.exports = clamp;
