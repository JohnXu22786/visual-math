const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {fileURLToPath, pathToFileURL} = require('node:url');
const {JSDOM} = require('jsdom');
const packageConfigPath = path.resolve(
  __dirname,
  '../../.dart_tool/package_config.json',
);
const packageConfig = JSON.parse(fs.readFileSync(packageConfigPath, 'utf8'));
const visualMathPackage = packageConfig.packages.find(({name}) => name === 'visual_math');
if (!visualMathPackage) {
  throw new Error('visual_math package is missing from package_config.json');
}
const packageConfigDirectory = path.dirname(packageConfigPath) + path.sep;
const visualMathRoot = fileURLToPath(new URL(
  visualMathPackage.rootUri,
  pathToFileURL(packageConfigDirectory),
));
const assets = path.join(visualMathRoot, 'assets/vendor/mathlive');

async function editor() {
  const dom = new JSDOM('<div id="problem"></div>',
    {runScripts:'dangerously', url:'https://visual-math.test/editor.html', pretendToBeVisual:true});
  const w = dom.window;
  w.HTMLElement.prototype.attachInternals = () => ({setFormValue() {}, setValidity() {}, states:new Set()});
  const shadowQuery = w.ShadowRoot.prototype.querySelector;
  w.ShadowRoot.prototype.querySelector = function(selector) {
    return shadowQuery.call(this, selector.replace(/^:host\s*>\s*/, ''));
  };
  w.HTMLSlotElement.prototype.assignedNodes = () => [];
  w.HTMLSlotElement.prototype.assignedElements = () => [];
  for (const name of ["scrollIntoView", "scroll", "scrollTo"]) {
    w.HTMLElement.prototype[name] = () => {};
    w[name] = () => {};
  }
  w.AudioContext = class { constructor() { this.state = 'running'; } };
  w.__resizeObservers = [];
  w.ResizeObserver = class {
    constructor(callback) { this.callback = callback; this.targets = new Set(); w.__resizeObservers.push(this); }
    observe(target) { this.targets.add(target); }
    disconnect() { this.targets.clear(); }
    unobserve(target) { this.targets.delete(target); }
  };
  w.getComputedStyle = () => ({fontSize:'16px', fontFamily:'serif', direction:'ltr', getPropertyValue:() => ''});
  w.matchMedia = () => ({matches:false, addEventListener() {}, removeEventListener() {}});
  w.FontFace = class { constructor() { this.status = 'loaded'; } load() { return Promise.resolve(this); } };
  w.document.fonts = {check:() => true, ready:Promise.resolve(), add() {}};
  w.document.execCommand = () => true;
  w.document.queryCommandSupported = () => false;
  w.document.elementFromPoint = () => w.document.getElementById('formula');
  w.Range.prototype.getBoundingClientRect = () => ({x:0,y:0,width:100,height:24,top:0,bottom:24,left:0,right:100});
  w.Range.prototype.getClientRects = () => [];
  w.eval(fs.readFileSync(path.join(assets,'mathlive.min.js'),'utf8') + '\n//# sourceURL=https://visual-math.test/mathlive.min.js');
  w.MathLive.MathfieldElement.fontsDirectory = 'https://visual-math.test/fonts';
  w.MathLive.MathfieldElement.soundsDirectory = null;
  w.MathLive.MathfieldElement.keypressSound = null;
  w.MathLive.MathfieldElement.plonkSound = null;
  const field = w.document.createElement('math-field');
  field.id = 'formula';
  w.document.body.prepend(field);
  w.eval(fs.readFileSync(path.join(assets,'navigation.js'),'utf8'));
  w.eval(fs.readFileSync(path.join(assets,'editor.js'),'utf8'));
  await new Promise(resolve => w.setTimeout(resolve,20));
  return {w, dom, field:w.document.getElementById('formula'), bridge:w.stroomMath};
}

test('nested fraction editing, cursor selection, and undo keep rendered math', async () => {
  const {dom, field, bridge} = await editor();
  try {
    bridge.setSource('', 0);
    bridge.command('insert', 'y=');
    bridge.command('insert', '\\frac{#0}{#?}');
    bridge.command('insert', 'x');
    bridge.command('insert', '#@^{2}');
    bridge.command('insert', '+1');
    bridge.command('next','');
    bridge.command('insert','2');
    bridge.command('next','');
    assert.match(field.getValue(), /\\frac\{x\^\{?2\}?\+1\}\{2\}/);
    const selected = JSON.stringify(field.selection);
    const source = bridge.snapshot().latex;
    bridge.setSource(source, 1);
    assert.equal(JSON.stringify(field.selection), selected);
    const end = field.lastOffset;
    field.selection = {ranges:[[0,end]],direction:'forward'};
    bridge.command('insert','z');
    assert.equal(bridge.snapshot().latex,'z');
    bridge.command('command','undo');
    assert.equal(bridge.snapshot().latex, source);
  } finally { dom.window.close(); }
});

test('source import preserves unsupported source and plain function meanings', async () => {
  const {dom, field, bridge} = await editor();
  try {
    const source = 'sin(x)+pi';
    assert.equal(bridge.setSource(source,2).latex, source);
    assert.match(field.getValue(), /\\sin/);
    bridge.command('insert', '+1');
    assert.match(bridge.snapshot().latex, /\\sin/);
    const unsupported = '\\unknowncommand{x}';
    assert.equal(bridge.setSource(unsupported,3).latex,unsupported);
    assert.equal(field.readOnly,true);
    assert.equal(bridge.command('insert','2').latex,unsupported);
  } finally { dom.window.close(); }
});

test('matrix cells and extra rows remain structured and editable', async () => {
  const {dom, field, bridge} = await editor();
  try {
    bridge.setSource('',0);
    bridge.command('insert','\\begin{pmatrix}#?&#?\\\\#?&#?\\end{pmatrix}');
    for (const number of ['1','2','3','4']) {
      bridge.command('insert',number);
      if (number !== '4') bridge.command('next','');
    }
    assert.match(field.getValue(), /\\begin\{pmatrix\}/);
    assert.match(field.getValue(), /1 & 2/);
    assert.equal(field.errors.length,0);
    bridge.command('command','addRowAfter');
    bridge.command('insert','5');
    assert.match(bridge.snapshot().latex,/5/);
  } finally { dom.window.close(); }
});


test('legacy roots and absolute values import as editable structures', async () => {
  const {dom, field, bridge} = await editor();
  try {
    for (const [source, latex] of [['sqrt(x+1)', '\\sqrt{x+1}'], ['abs(x-1)', '\\left|x-1\\right|']]) {
      assert.equal(bridge.setSource(source,1).latex,source);
      assert.equal(field.getValue(),latex);
      bridge.command('insert','+1');
      assert.equal(bridge.snapshot().latex,latex + '+1');
    }
  } finally { dom.window.close(); }
});


test('legacy inverse trig names remain operators in plain and mixed source', async () => {
  const {dom, field, bridge} = await editor();
  try {
    for (const name of ['asin','acos','atan']) {
      for (const argument of ['x', 'x^{2}']) {
        const source = `${name}(${argument})`;
        bridge.setSource(source,1);
        assert.match(field.getValue(),new RegExp('\\\\arc' + name.slice(1)));
        bridge.command('insert','+1');
        assert.match(bridge.snapshot().latex,new RegExp('\\\\arc' + name.slice(1)));
      }
    }
  } finally { dom.window.close(); }
});

test('MathLive rendered growth does not publish a row height', async () => {
  const {dom, field, bridge} = await editor();
  try {
    bridge.setSource('x',1);
    field.getBoundingClientRect = () => ({height:140});
    assert.equal(Object.hasOwn(bridge.snapshot(),'height'),false);
  } finally { dom.window.close(); }
});

function offsetOf(field, latex) {
  for (let i = 0; i <= field.lastOffset; i++) {
    if (field.getElementInfo(i)?.latex === latex) return i;
  }
  throw new Error('Missing rendered atom: ' + latex);
}

test('horizontal arrows traverse nested slots and collapse selection without editing', async () => {
  const {dom, field, bridge} = await editor();
  try {
    const source = '\\frac{x^{2}+1}{\\sqrt{y}}+z';
    bridge.setSource(source,0);
    field.position = 0;
    const locations = new Set();
    let sequence = bridge.snapshot().sequence;
    for (let i = 0; i < 30 && field.position < field.lastOffset; i++) {
      const previous = field.position;
      const state = bridge.command('navigate','right');
      assert.ok(field.position > previous);
      assert.ok(state.sequence > sequence, 'Caret-only snapshots must also reject late arrivals');
      sequence = state.sequence;
      locations.add(state.location);
      assert.equal(state.edited,false);
      assert.equal(state.latex,source);
    }
    assert.ok(locations.has('分子') && locations.has('指数') && locations.has('根号内'));
    bridge.command('navigate','right');
    assert.equal(field.position,field.lastOffset);
    for (let i = 0; i < 30 && field.position > 0; i++) bridge.command('navigate','left');
    assert.equal(field.position,0);
    bridge.command('navigate','left');
    assert.equal(field.position,0);
    field.selection = {ranges:[[0,field.lastOffset]],direction:'forward'};
    bridge.command('navigate','left');
    assert.equal(field.position,0);
    assert.equal(field.selectionIsCollapsed,true);
    field.selection = {ranges:[[0,field.lastOffset]],direction:'forward'};
    bridge.command('navigate','right');
    assert.equal(field.position,field.lastOffset);
    assert.equal(bridge.snapshot().latex,source);
  } finally { dom.window.close(); }
});

test('vertical navigation edits fraction, script, radical and matrix target slots', async () => {
  const {dom, field, bridge} = await editor();
  try {
    bridge.setSource('\\frac{12}{34}',1);
    field.position = offsetOf(field,'1');
    assert.equal(bridge.command('navigate','down').location,'分母');
    bridge.command('insert','9');
    assert.equal(field.getValue(),'\\frac{12}{394}');
    bridge.setSource('x^{12}',2);
    field.position = offsetOf(field,'1');
    assert.equal(bridge.command('navigate','down').location,'公式');
    bridge.command('insert','+z');
    assert.match(field.getValue(),/^x\^\{12\}\+z$/);
    bridge.setSource('x_{a}^{b}',3);
    field.position = offsetOf(field,'a');
    assert.equal(bridge.command('navigate','up').location,'指数');
    bridge.command('insert','1');
    assert.match(field.getValue(),/\^\{b1\}/);
    bridge.setSource('\\sqrt[3]{x}',4);
    field.position = offsetOf(field,'x');
    assert.equal(bridge.command('navigate','up').location,'根指数');
    bridge.command('insert','1');
    assert.equal(field.getValue(),'\\sqrt[31]{x}');
    bridge.setSource('\\sqrt{x}',5);
    field.position = offsetOf(field,'x');
    bridge.command('navigate','up');
    assert.equal(bridge.snapshot().edited,false, 'Navigation must not create a missing root index');
    bridge.setSource('\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}',6);
    field.position = offsetOf(field,'1');
    assert.equal(bridge.command('navigate','down').location,'第 2 行，第 1 列');
    bridge.command('insert','9');
    assert.match(field.getValue(),/39 & 4/);
    bridge.setSource('x^{a_{1}}',7);
    field.position = offsetOf(field,'1');
    assert.equal(bridge.command('navigate','out').location,'指数');
    bridge.command('navigate','out');
    assert.equal(bridge.snapshot().location,'公式');
    assert.equal(bridge.snapshot().edited,false);
  } finally { dom.window.close(); }
});

test('limit operators label lower and upper scripts consistently', async () => {
  const {dom, field, bridge} = await editor();
  try {
    for (const operator of ['\\lim', '\\limsup', '\\liminf']) {
      bridge.setSource(`${operator}_{x\\to0}^{n}`, 1);
      field.position = offsetOf(field,'x');
      assert.equal(bridge.snapshot().location,'下限', `${operator} subscript`);
      field.position = offsetOf(field,'n');
      assert.equal(bridge.snapshot().location,'上限', `${operator} superscript`);
    }
  } finally { dom.window.close(); }
});

test('slot navigation revisits filled content and exits the correct parent', async () => {
  const {dom, field, bridge} = await editor();
  try {
    bridge.setSource('\\frac{a b}{c d}',0);
    field.position = offsetOf(field,'b');
    assert.equal(bridge.command('next','').location,'分母');
    assert.equal(field.position,offsetOf(field,'d'));
    assert.equal(bridge.command('previous','').location,'分子');
    assert.equal(field.position,offsetOf(field,'b'));
    bridge.command('previous','');
    assert.equal(field.position,0, 'Previous at the first slot exits before the fraction');
    bridge.command('next','');
    assert.equal(field.position,offsetOf(field,'b'));
    bridge.command('navigate','out');
    assert.equal(field.position,field.lastOffset);
    assert.equal(bridge.snapshot().edited,false);
    field.selection = {ranges:[[0,field.lastOffset]],direction:'forward'};
    bridge.command('next','');
    assert.equal(field.selectionIsCollapsed,true);
    assert.equal(field.position,field.lastOffset);
    bridge.setSource('\\frac{x^{2}}{y}',1);
    field.position = offsetOf(field,'2');
    assert.equal(bridge.command('next','').location,'分子');
    assert.equal(bridge.command('next','').location,'分母');
    const position = field.position;
    const source = field.getValue();
    bridge.command('insert','+1');
    assert.match(field.getValue(),/\{y\+1\}$/);
    bridge.command('command','undo');
    assert.equal(field.getValue(),source);
    assert.equal(field.position,position);
    assert.equal(bridge.snapshot().location,'分母');
  } finally { dom.window.close(); }
});

test('stacked annotations and arrow labels remain editable with vertical navigation', async () => {
  const {dom, field, bridge} = await editor();
  try {
    bridge.setSource('\\overset{a}{x}',1);
    field.position = offsetOf(field,'x');
    bridge.command('navigate','up');
    assert.equal(bridge.snapshot().location,'上方标注');
    bridge.command('insert','+1');
    assert.equal(field.getValue(),'\\overset{a+1}{x}');
    bridge.command('navigate','down');
    assert.equal(bridge.snapshot().location,'主体');
    bridge.command('insert','+2');
    assert.equal(field.getValue(),'\\overset{a+1}{x+2}');
    bridge.setSource('\\underset{b}{x}',2);
    field.position = offsetOf(field,'x');
    bridge.command('navigate','down');
    assert.equal(bridge.snapshot().location,'下方标注');
    bridge.command('insert','+3');
    assert.equal(field.getValue(),'\\underset{b+3}{x}');
    bridge.setSource('\\xrightarrow[b]{a}',3);
    field.position = offsetOf(field,'a');
    bridge.command('navigate','down');
    assert.equal(bridge.snapshot().location,'下方标注');
    bridge.command('insert','+4');
    assert.equal(field.getValue(),'\\xrightarrow[b+4]{a}');
    bridge.command('navigate','up');
    assert.equal(bridge.snapshot().location,'上方标注');
    bridge.setSource('\\xrightarrow{a}',4);
    field.position = offsetOf(field,'a');
    const position=field.position;
    bridge.command('navigate','down');
    assert.equal(field.position,position);
    assert.equal(field.getValue(),'\\xrightarrow{a}');
  } finally { dom.window.close(); }
});

test('expanded symbol families parse and remain editable in rendered math', async () => {
  const {dom, field, bridge} = await editor();
  // Undo rebuilds array spacing and the thin space inside limsup/liminf.
  // Compare the expanded expression independently of those layout tokens.
  const content = () => field.getValue('latex-expanded').replace(/\s+|\\,/g,'');
  try {
    for (const source of [
      '\\omicron+\\varpi+\\varrho+\\varsigma+\\varkappa+\\digamma',
      '\\Alpha+\\Beta+\\Epsilon+\\Zeta+\\Eta+\\Iota+\\Kappa+\\Mu+\\Nu+\\Omicron+\\Rho+\\Tau+\\Chi',
      '\\mathbb{N}\\subseteq\\mathbb{Z}\\subseteq\\mathbb{Q}\\subseteq\\mathbb{R}\\subseteq\\mathbb{C}',
      '\\partial+\\nabla+f^{\\prime}+\\iiint+\\bigcup+\\bigcap+\\coprod',
      '\\limsup_{x\\to0}x+\\liminf_{x\\to0}x',
      'A\\supseteq B\\setminus C\\mid x\\sim y\\simeq z\\cong w\\ll a\\gg b',
      'x\\leftarrow y\\leftrightarrow z\\Leftarrow w',
      '\\left[0,1\\right)+\\left(0,1\\right]',
      '\\begin{vmatrix}1&2\\\\3&4\\end{vmatrix}+\\begin{Vmatrix}1&2\\\\3&4\\end{Vmatrix}',
      '\\widehat{x}+\\overset{a}{x}+\\underset{b}{x}+\\xrightarrow[b]{a}+\\xleftarrow[b]{a}',
      '\\operatorname{arccot}(x)+\\operatorname{arcsec}(x)+\\operatorname{arccsc}(x)',
      '\\operatorname{arsinh}(x)+\\operatorname{arcosh}(x)+\\operatorname{artanh}(x)',
      'x\\times2\\div3+1\\mp2\\colon3',
    ]) {
      bridge.setSource('',1);
      bridge.command('insert',source);
      assert.equal(field.errors.length,0,source);
      const rendered=content();
      field.position=field.lastOffset;
      bridge.command('navigate','right');
      bridge.command('insert','+1');
      assert.equal(content(),rendered+'+1',source);
      assert.equal(bridge.snapshot().latex,field.getValue('latex'),source);
      bridge.command('command','undo');
      assert.equal(content(),rendered,source);
    }
  } finally { dom.window.close(); }
});

test('compact identifier subscripts keep parameter boundaries in edited exports', async () => {
  const {dom, field, bridge} = await editor();
  try {
    for (const base of ['a','\\alpha']) {
      for (const index of ['1','b']) {
        const source = base + '_{' + index + '}x';
        assert.equal(bridge.setSource(source,1).latex,source);
        field.position = field.lastOffset;
        bridge.command('insert','+1');
        assert.equal(bridge.snapshot().latex,source+'+1');
        bridge.setSource('',2);
        bridge.command('insert',base);
        bridge.command('insert','#@_{#?}');
        bridge.command('insert',index);
        bridge.command('navigate','out');
        bridge.command('insert','x');
        assert.equal(bridge.snapshot().latex,source);
        field.selection = {ranges:[[0,field.lastOffset]],direction:'forward'};
        assert.equal(bridge.selectedLatex(),source);
      }
    }
    for (const source of ['\\text{a_1}', '\\operatorname{a_1}']) {
      bridge.setSource(source,3);field.position=field.lastOffset;
      bridge.command('insert','+1');
      assert.equal(bridge.snapshot().latex,field.getValue('latex'));
    }
  } finally {dom.window.close();}
});

test('separate rendered letter atoms keep graph token boundaries in snapshots and copies', async () => {
  const {dom, field, bridge} = await editor();
  try {
    for (const [atoms, exported, reimported=exported] of [
      [['A','x'], 'A x'],
      [['a','x'], 'a x'],
      [['A','2'], 'A 2'],
      [['a','2','3'], 'a 23'],
      [['2','A'], '2 A'],
      [['1','e','3'], '1 e 3'],
      [['e','E'], 'e E', 'e e'],
    ]) {
      bridge.setSource('',0);
      for (const atom of atoms) bridge.command('insert',atom);
      assert.equal(bridge.snapshot().latex,exported,atoms.join(','));
      field.selection = {ranges:[[0,field.lastOffset]],direction:'forward'};
      assert.equal(bridge.selectedLatex(),exported,atoms.join(','));
      // MathLive removes ordinary input spaces; reimporting an edited snapshot
      // must restore the same atom boundaries on the next edit.
      bridge.setSource('',1);
      bridge.setSource(exported,2);
      field.position=field.lastOffset;
      bridge.command('insert','+1');
      assert.equal(bridge.snapshot().latex,reimported+'+1',atoms.join(','));
    }
  } finally { dom.window.close(); }
});

test('legacy identifier namespaces survive rendered edits without splitting literals', async () => {
  const {dom, field, bridge} = await editor();
  try {
    for (const name of ['foo','Ax','A2','a2ln2','constructor','foo_bar_baz','foo_pi_ln2','foo_','foo__bar','foo___','foo__bar_']) {
      const source=name+'*x';
      assert.equal(bridge.setSource(source,1).latex,source);
      assert.equal(field.errors.length,0,source);
      field.position=field.lastOffset;
      bridge.command('insert','+1');
      const exported='\\mathrm{'+name.replaceAll('_','\\_')+'}\\cdot x+1';
      assert.equal(bridge.snapshot().latex,exported,source);
      field.selection={ranges:[[0,field.lastOffset]],direction:'forward'};
      assert.equal(bridge.selectedLatex(),exported,source);
    }
    for (const source of [
      '\\text{Ax a2ln2 a\\_b}', '\\operatorname{a_1}',
      '\\mathrm{alpha}_{12}x', 'a_{ln2}x', '\\alpha_{1e3}x',
      'a\\_b', '\\sin(x)+\\alpha x+1.25',
      '\\begin{pmatrix}1&2\\\\3&4\\end{pmatrix}',
    ]) {
      bridge.setSource(source,2);
      assert.equal(field.errors.length,0,source);
      field.position=field.lastOffset;
      bridge.command('insert','+1');
      assert.equal(bridge.snapshot().latex,field.getValue('latex'),source);
    }
    bridge.setSource('sin(xa_{12})',3);
    field.position=field.lastOffset;
    bridge.command('insert','+1');
    assert.equal(bridge.snapshot().latex,'\\sin\\left(x a_{12}\\right)+1');
    bridge.setSource('unknown(x)',4);
    field.position=field.lastOffset;
    bridge.command('insert','+1');
    assert.equal(bridge.snapshot().latex,'\\mathrm{unknown}(x)+1');
    const romanIndex='\\mathrm{foo}_{bar_baz}\\cdot x';
    assert.equal(bridge.setSource(romanIndex,5).latex,romanIndex);
    field.position=field.lastOffset;
    bridge.command('insert','+1');
    assert.equal(bridge.snapshot().latex,'\\mathrm{foo\\_bar\\_baz}\\cdot x+1');
  } finally { dom.window.close(); }
});

test('identifier subscripts survive import and rendered editing', async () => {
  const {dom, field, bridge} = await editor();
  try {
    for (const name of ['pi','PI','ln2','ln10','log2e','log10e','sqrt2','sqrt1_2','asin','1e3']) {
      for (const base of ['a','\\alpha']) {
        const script = base + '_{' + name + '}';
        const source = 'sin(' + script + '*x)+pi';
        bridge.setSource(source,1);
        assert.equal(field.errors.length,0,source);
        assert.ok(field.getValue('latex').includes(script),source);
        assert.match(field.getValue('latex'),/\\sin.*\\pi/);
        field.position = field.lastOffset;
        bridge.command('navigate','right');
        bridge.command('insert','+1');
        assert.ok(bridge.snapshot().latex.includes(script),source);
      }
    }
    for (const [source, structure] of [
      ['a_12*x+pi', 'a_{12}'],
      ['alpha_12*x+pi', '\\mathrm{alpha}_{12}'],
      ['foo_12*x+pi', '\\mathrm{foo}_{12}'],
      ['pi_1*x+pi', '\\mathrm{pi}_{1}'],
    ]) {
      assert.equal(bridge.setSource(source,2).latex,source);
      field.position=field.lastOffset;
      bridge.command('insert','+1');
      assert.ok(bridge.snapshot().latex.includes(structure),source);
      assert.match(bridge.snapshot().latex,/\\pi/);
    }
  } finally { dom.window.close(); }
});

test('legacy functions and constants retain their structures after editing', async () => {
  const {dom, field, bridge} = await editor();
  try {
    for (const [source, pattern] of [
      ['floor(x+1)', /\\lfloor x\+1\\right\\rfloor/],
      ['ceil(x)', /\\lceil x\\right\\rceil/],
      ['fact(x+1)', /x\+1.*!/],
      ['round(x)', /\\operatorname\{round\}/],
      ['csch(x)', /\\operatorname\{csch\}/],
      ['sech(x)', /\\operatorname\{sech\}/],
      ['coth(x)', /\\coth/],
      ['nrt(3,x)', /\\sqrt\[3\]\{x\}/],
      ['pow(x+1,2)', /\^2|\^\{2\}/],
      ['log(2,x)', /\\log_2|\\log_\{2\}/],
      ['x%2', /\\bmod/],
      ['1e-3*x', /10\^\{-3\}/],
      ['ln2', /\\ln\\left\(2\\right\)/],
      ['ln10', /\\ln\\left\(10\\right\)/],
      ['log2e', /\\log_(?:2|\{2\})\\left\(e\\right\)/],
      ['log10e', /\\log_\{10\}\\left\(e\\right\)/],
      ['sqrt2', /\\sqrt\{2\}/],
      ['sqrt1_2', /\\frac\{1\}\{\\sqrt\{2\}\}/],
      ['SQRT1_2', /\\frac\{1\}\{\\sqrt\{2\}\}/],
      ['PI', /\\pi/],
      ['pi', /\\pi/],
      ['e', /^e/],
      ['E', /^e/],
      ['2ln2', /2\\ln\\left\(2\\right\)/],
      ['2sqrt1_2', /2\\frac\{1\}\{\\sqrt\{2\}\}/],
      ['a2ln2', /^\\mathrm\{a2ln2\}/],
      ['constructor*x', /^\\mathrm\{constructor\}\\cdot x/],
    ]) {
      assert.equal(bridge.setSource(source,1).latex,source);
      assert.equal(field.errors.length,0,source);
      assert.match(field.getValue(),pattern,source);
      field.position = field.lastOffset;
      bridge.command('insert','+1');
      assert.match(bridge.snapshot().latex,pattern,source);
    }
  } finally { dom.window.close(); }
});
