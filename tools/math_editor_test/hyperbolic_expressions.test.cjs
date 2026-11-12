const {test} = require('node:test');
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const path = require('node:path');

test('generated hyperbolic ratios stay stable at large and small inputs', () => {
  const script = path.join(__dirname, 'hyperbolic_expressions.dart');
  const expressions = execFileSync('dart', [script], {encoding: 'utf8'}).trim().split('\n');
  for (const [i, expression] of expressions.slice(0, 2).entries()) {
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

test('generated sinh and csch retain precision near zero', () => {
  const script = path.join(__dirname, 'hyperbolic_expressions.dart');
  const expressions = execFileSync('dart', [script], {encoding: 'utf8'}).trim().split('\n');
  for (const [index, expression] of expressions.slice(2).entries()) {
    const evaluate = new Function('x', `return ${expression}`);
    for (const x of [-1e-4, -1e-20, 1e-20, 1e-4, 0.00010001, 0.01]) {
      const sinh = x * (1 + x * x / 6 + x * x * x * x / 120);
      const expected = index === 0 ? sinh : 1 / sinh;
      assert.ok(Math.abs(evaluate(x) / expected - 1) < 1e-14);
    }
    assert.equal(evaluate(0), index === 0 ? 0 : Infinity);
    assert.ok(index === 0 ? Object.is(evaluate(-0), -0) : evaluate(-0) === -Infinity);
  }
});
