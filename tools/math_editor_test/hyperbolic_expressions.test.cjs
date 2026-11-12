const {test} = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const path = require('node:path');

test('generated hyperbolic ratios stay stable at large and small inputs', () => {
  const script = path.join(__dirname, 'hyperbolic_expressions.dart');
  const expressions = execFileSync('dart', [script], {encoding: 'utf8'}).trim().split('\n');
  for (const [i, expression] of expressions.entries()) {
    const evaluate = new Function('x', `return ${expression}`);
    const cases = i === 0
      ? [[-1000, -1], [-0.5, -0.46211715726000974], [0.5, 0.46211715726000974], [1000, 1], [1e-20, 1e-20]]
      : [[-1000, -1], [-0.5, -2.163953413738653], [0.5, 2.163953413738653], [1000, 1], [1e-20, 1e20]];
    for (const [x, expected] of cases) {
      assert.ok(Math.abs((evaluate(x) - expected) / expected) < 1e-12);
    }
    assert.equal(evaluate(0), i === 0 ? 0 : Infinity);
    assert.ok(i === 0 ? Object.is(evaluate(-0), -0) : evaluate(-0) === -Infinity);
  }
});
