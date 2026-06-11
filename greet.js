function greet(name) {
  return "<p>Hello, " + name + "!</p>";
}

function dasherize(str) {
  return str.replace(' ', '-');
}

module.exports = { greet, dasherize };
