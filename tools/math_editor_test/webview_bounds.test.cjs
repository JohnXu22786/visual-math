const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

test('JSXGraph bounds drive coordinates and round-trip viewport changes', () => {
  const source = fs.readFileSync(process.env.WEBVIEW_SOURCE || path.join(__dirname,
    '../../lib/src/widgets/math_canvas_webview.dart'), 'utf8');
  const script = source.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replaceAll('$boardId', 'board')
    .replaceAll('$encodedExpression', JSON.stringify('x'))
    .replaceAll('$encodedInitialParameters', '{}');
  const messages = [];
  let timer;
  let onBounds;
  let bounds = [-4, 7, 6, -2];
  const board = {
    getBoundingBox: () => bounds,
    setBoundingBox: value => { bounds = Array.from(value); },
    on: (event, callback) => { if (event === 'boundingbox') onBounds = callback; },
    create: () => ({}),
    removeObject: () => {},
  };
  const context = {
    JXG: {JSXGraph: {initBoard: () => board}},
    window: {flutter_inappwebview: {callHandler: (_, message) => messages.push(JSON.parse(message))}},
    document: {getElementById: () => null},
    setInterval: callback => { timer = callback; return 1; },
    clearInterval: () => {},
    console,
  };
  vm.runInNewContext(script, context);
  timer();
  const points = messages.find(message => message.type === 'coordinateUpdate').points;
  assert.ok(points.length > 0);
  assert.ok(points.every(point => point.y >= -3 && point.y <= 8));
  assert.ok(points.some(point => Math.abs(point.x) < 0.001));
  onBounds();
  const viewport = messages.find(message => message.type === 'viewportChange');
  assert.deepEqual(viewport, {type: 'viewportChange', xMin: -4, yMin: -2, xMax: 6, yMax: 7});
  context.window.setViewport(-8, -3, 9, 5);
  assert.deepEqual(bounds, [-8, 5, 9, -3]);
});

test('clearing an invalid expression hides its error', () => {
  const source = fs.readFileSync(path.join(__dirname,
    '../../lib/src/widgets/math_canvas_webview.dart'), 'utf8');
  const script = source.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replaceAll('$boardId', 'board')
    .replaceAll('$encodedExpression', JSON.stringify(''))
    .replaceAll('$encodedInitialParameters', '{}');
  const error = {style: {display: 'none'}, textContent: ''};
  const board = {on: () => {}, removeObject: () => {}, create: () => ({})};
  const context = {
    JXG: {JSXGraph: {initBoard: () => board}},
    window: {flutter_inappwebview: {callHandler: () => {}}},
    document: {getElementById: () => error},
    setInterval: () => 1,
    clearInterval: () => {},
    console,
  };
  vm.runInNewContext(script, context);
  context.window.setExpression('x +', null);
  assert.equal(error.style.display, 'block');
  context.window.setExpression('', null);
  assert.equal(error.style.display, 'none');
});

test('coordinate sampling terminates for narrow and normal bounds', () => {
  const source = fs.readFileSync(process.env.WEBVIEW_SOURCE || path.join(__dirname,
    '../../lib/src/widgets/math_canvas_webview.dart'), 'utf8');
  const script = source.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replaceAll('$boardId', 'board')
    .replaceAll('$encodedExpression', JSON.stringify('x'))
    .replaceAll('$encodedInitialParameters', '{}');
  const messages = [];
  let bounds;
  let timer;
  const board = {getBoundingBox: () => bounds, on: () => {}, create: () => ({})};
  const context = {
    JXG: {JSXGraph: {initBoard: () => board}},
    window: {flutter_inappwebview: {callHandler: (_, message) => messages.push(JSON.parse(message))}},
    document: {getElementById: () => null},
    setInterval: callback => { timer = callback; return 1; },
    clearInterval: () => {}, console,
  };
  vm.createContext(context);
  vm.runInContext(script, context, {timeout: 1000});
  for (bounds of [[-10, 100, 10, -100], [1e16, 1e17, 1e16 + 2, -1e17]]) {
    context.tick = timer;
    vm.runInContext('tick()', context, {timeout: 1000});
  }
  assert.equal(messages.length, 2);
  for (const message of messages) {
    assert.equal(message.type, 'coordinateUpdate');
    assert.equal(message.points.length, 51);
  }
  assert.equal(messages[0].points[0].x, -10);
  assert.equal(messages[0].points[50].x, 10);
  assert.equal(messages[1].points[0].x, 1e16);
  assert.equal(messages[1].points[50].x, 1e16 + 2);
});
test('parameter updates do not restore a cleared expression', () => {
  const source = fs.readFileSync(path.join(__dirname,
    '../../lib/src/widgets/math_canvas_webview.dart'), 'utf8');
  const script = source.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replaceAll('$boardId', 'board')
    .replaceAll('$encodedExpression', JSON.stringify(''))
    .replaceAll('$encodedInitialParameters', '{}');
  let activeCurve = null;
  const board = {
    on: () => {},
    create: () => { activeCurve = {}; return activeCurve; },
    removeObject: curve => { assert.equal(curve, activeCurve); activeCurve = null; },
  };
  const context = {
    JXG: {JSXGraph: {initBoard: () => board}},
    window: {},
    document: {getElementById: () => null},
    setInterval: () => 1,
    clearInterval: () => {},
    console,
  };
  vm.runInNewContext(script, context);
  for (const emptyExpression of ['', '  ']) {
    context.window.setExpression('a*x', JSON.stringify({a: 1}));
    assert.ok(activeCurve);
    context.window.setExpression(emptyExpression, null);
    assert.equal(activeCurve, null);
    context.window.updateParameters(JSON.stringify({a: 2}));
    assert.equal(activeCurve, null);
  }
});

test('leading newlines evaluate in plots and coordinate samples', () => {
  const source = fs.readFileSync(path.join(__dirname,
    '../../lib/src/widgets/math_canvas_webview.dart'), 'utf8');
  const script = source.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replaceAll('$boardId', 'board')
    .replaceAll('$encodedExpression', JSON.stringify('\nx + 1'))
    .replaceAll('$encodedInitialParameters', '{}');
  let evaluate, timer;
  const messages = [];
  const board = {
    getBoundingBox: () => [-1, 5, 1, -5], on: () => {},
    create: (_, args) => { evaluate = args[0]; return {}; },
  };
  vm.runInNewContext(script, {
    JXG: {JSXGraph: {initBoard: () => board}},
    window: {flutter_inappwebview: {callHandler: (_, message) => messages.push(JSON.parse(message))}},
    document: {getElementById: () => null},
    setInterval: callback => { timer = callback; return 1; }, clearInterval: () => {}, console,
  });
  assert.equal(evaluate(2), 3);
  timer();
  const points = messages.find(message => message.type === 'coordinateUpdate').points;
  assert.equal(points.length, 51);
  assert.equal(points[0].y, 0);
});

test('partial parameter updates retain the current expression scope', () => {
  const source = fs.readFileSync(path.join(__dirname,
    '../../lib/src/widgets/math_canvas_webview.dart'), 'utf8');
  const script = source.match(/<script>\s*([\s\S]*?)<\/script>/)[1]
    .replaceAll('$boardId', 'board')
    .replaceAll('$encodedExpression', JSON.stringify('a*x+b'))
    .replaceAll('$encodedInitialParameters', JSON.stringify({a: 2, b: 3}));
  let evaluate;
  const board = {
    on: () => {}, removeObject: () => {},
    create: (_, args) => { evaluate = args[0]; return {}; },
  };
  const context = {
    JXG: {JSXGraph: {initBoard: () => board}}, window: {},
    document: {getElementById: () => null},
    setInterval: () => 1, clearInterval: () => {}, console,
  };
  vm.runInNewContext(script, context);
  assert.equal(evaluate(2), 7);
  context.window.updateParameters(JSON.stringify({a: 4}));
  assert.equal(evaluate(2), 11);
  context.window.updateParameters(JSON.stringify({b: 5}));
  assert.equal(evaluate(2), 13);
  context.window.setExpression('a*x+b', JSON.stringify({a: 1, b: 10}));
  context.window.updateParameters(JSON.stringify({a: 3}));
  assert.equal(evaluate(2), 16);
});
