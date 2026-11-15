const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const mathLive = fs.readFileSync(
  path.resolve(__dirname, '../../assets/vendor/mathlive/mathlive.min.js'),
  'utf8',
);

test('light theme variant keycaps honor the public text override', () => {
  const selector = "[theme='light'] .ML__keyboard {";
  const start = mathLive.indexOf(selector);
  assert.notEqual(start, -1, `Missing light theme selector: ${selector}`);
  const end = mathLive.indexOf('\n}', start);
  assert.notEqual(end, -1, `Could not find end of light theme selector: ${selector}`);
  const rules = mathLive.slice(start, end + 2);

  assert.match(
    rules,
    /--_variant-keycap-text:\s*var\(--variant-keycap-text,\s*var\(--_keycap-text\)\);/,
  );
});
