const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const mathLive = fs.readFileSync(
  path.resolve(__dirname, '../../assets/vendor/mathlive/mathlive.min.js'),
  'utf8',
);

function darkThemeRules(selector) {
  const start = mathLive.indexOf(selector);
  assert.notEqual(start, -1, `Missing dark theme selector: ${selector}`);
  const end = mathLive.indexOf('\n}', start);
  assert.notEqual(end, -1, `Could not find end of dark theme selector: ${selector}`);
  return mathLive.slice(start, end + 2);
}

test('dark themes preserve consumer keycap border overrides', () => {
  for (const selector of [
    '@media (prefers-color-scheme: dark) {\n  .ML__keyboard {',
    "[theme='dark'] .ML__keyboard {",
  ]) {
    const rules = darkThemeRules(selector);
    assert.match(rules, /--_keycap-border:\s*var\(--keycap-border,\s*transparent\);/);
    assert.match(rules, /--_keycap-border-bottom:\s*var\(--keycap-border-bottom,\s*transparent\);/);
  }
});
