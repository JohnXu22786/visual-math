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
    .replaceAll('$escapedExpr', 'x')
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
