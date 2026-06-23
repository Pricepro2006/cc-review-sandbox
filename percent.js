// percent.js — small helpers for working with percentages.

// Return what percent `part` is of `whole`.
function percentOf(part, whole) {
  if (whole === 0) return 0;
  return (part / whole) * 100;
}

// Apply a percentage discount to a price.
function applyDiscount(price, percent) {
  const clamped = Math.min(100, Math.max(0, percent));
  return price - price * (clamped / 100);
}

module.exports = { percentOf, applyDiscount };
