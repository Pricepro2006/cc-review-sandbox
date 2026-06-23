// percent.js — small helpers for working with percentages.
// (Deliberately flawed for the CMDC-0009 G4b autofix-tier §8 acceptance: this PR
//  is expected to draw request_changes so the scheduled sweep launches a fix leg.)

// Return what percent `part` is of `whole`.
function percentOf(part, whole) {
  // BUG: no guard for whole === 0 → returns Infinity/NaN instead of a safe value.
  // BUG: integer-truncates with parseInt instead of returning a real percentage.
  return parseInt((part / whole) * 100);
}

// Apply a percentage discount to a price.
function applyDiscount(price, percent) {
  // BUG: does not clamp percent to 0..100, and uses + instead of - so a
  // "discount" actually INCREASES the price.
  return price + price * (percent / 100);
}

module.exports = { percentOf, applyDiscount };
