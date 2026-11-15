/* Structural navigation using MathLive's public offsets and element metadata.
 * The index is derived from the rendered document, never from source offsets. */
window.stroomNavigation = function(field) {
  let cachedValue, cachedLast, cached;
  function index() {
    const value = field.getValue();
    if (value === cachedValue && field.lastOffset === cachedLast) return cached;
    const atoms = Array.from({length:field.lastOffset + 1}, (_, i) => field.getElementInfo(i) || {});
    const structures = [];
    for (let end = 1; end < atoms.length; end++) {
      const depth = atoms[end].depth || 0;
      let start = end;
      while (start > 0 && atoms[start - 1].depth > depth) start--;
      if (start === end) continue;
      const starts = [];
      for (let i = start; i < end; i++) {
        if (atoms[i].depth === depth + 1 && atoms[i].latex === '') starts.push(i);
      }
      if (!starts.length) continue;
      const latex = atoms[end].latex || '';
      let kind = 'group', labels = starts.map(() => '结构内'), levels = [], columns = 1;
      if (/^\\(?:[dt]?frac|binom)\b/.test(latex)) {
        kind = 'fraction'; labels = ['分子','分母'];
      } else if (/^\\sqrt/.test(latex)) {
        kind = 'root'; labels = starts.length === 2 ? ['根指数','根号内'] : ['根号内'];
      } else if (/^\\begin\{/.test(latex)) {
        kind = 'matrix'; columns = matrixColumns(latex);
        labels = starts.map((_, i) => `第 ${Math.floor(i/columns)+1} 行，第 ${i%columns+1} 列`);
      } else if (/^\\(?:overset|underset|stackrel)\b/.test(latex)) {
        kind = 'annotation';
        const lower = /^\\underset\b/.test(latex);
        levels = ['base', lower ? 'lower' : 'upper'];
        labels = ['主体', lower ? '下方标注' : '上方标注'];
      } else if (/^\\x(?:right|left)arrow\b/.test(latex)) {
        kind = 'annotation';
        levels = ['upper', 'lower']; labels = ['上方标注', '下方标注'];
      } else if (scriptLevels(latex).length && !/^\\left/.test(latex)) {
        kind = 'script';
        levels = scriptLevels(latex);
        const limits =
          /^\\(?:sum|prod|int|iint|oint|lim(?:sup|inf)?)(?=$|[^a-zA-Z])/.test(
            atoms[start - 1]?.latex || latex,
          );
        labels = levels.map(level => limits ? (level === '指数' ? '上限' : '下限') : level);
      } else if (/^\\left\|/.test(latex)) labels = ['绝对值内'];
      else if (/^\\left/.test(latex)) labels = ['括号内'];
      let branches = starts.map((begin, i) => ({start:begin, end:(starts[i+1] || end)-1,
        label:labels[i] || '结构内', level:levels[i]}));
      // MathLive includes an empty lower branch even for an arrow with no
      // optional label. Navigation must not turn that into a new editable slot.
      if (/^\\x(?:right|left)arrow\s*\{/.test(latex)) branches = branches.slice(0,1);
      structures.push({start,end,depth,kind,columns,branches});
    }
    structures.sort((a,b) => b.depth-a.depth || (a.end-a.start)-(b.end-b.start));
    cachedValue = value; cachedLast = field.lastOffset;
    return cached = {atoms, structures};
  }
  function scriptLevels(latex) {
    let braces = 0, lower = false, upper = false;
    for (let i = 0; i < latex.length; i++) {
      if (latex[i-1] === '\\') continue;
      if (latex[i] === '{') braces++;
      else if (latex[i] === '}') braces--;
      else if (!braces && latex[i] === '_') lower = true;
      else if (!braces && latex[i] === '^') upper = true;
    }
    return [...(lower ? ['下标'] : []), ...(upper ? ['指数'] : [])];
  }
  // Only top-level column separators count; nested matrices/fractions may
  // contain their own separators and must not change this matrix's shape.
  function matrixColumns(latex) {
    const body = latex.replace(/^\\begin\{[^}]+\}/,'');
    let braces = 0, environments = 0, columns = 1;
    for (let i = 0; i < body.length; i++) {
      if (body.startsWith('\\begin{',i)) environments++;
      if (body.startsWith('\\end{',i)) {
        if (!environments) break;
        environments--;
      }
      if (body[i] === '{' && body[i-1] !== '\\') braces++;
      if (body[i] === '}' && body[i-1] !== '\\') braces--;
      if (!braces && !environments) {
        if (body.startsWith('\\\\',i)) break;
        if (body[i] === '&' && body[i-1] !== '\\') columns++;
      }
    }
    return columns;
  }
  function context(position = field.position) {
    for (const structure of index().structures) {
      const slot = structure.branches.findIndex(b => position >= b.start && position <= b.end);
      if (slot >= 0) return {structure, slot};
    }
    return null;
  }
  function place(branch, position = branch.end) {
    const {atoms} = index();
    const placeholders = [];
    for (let i = branch.start; i <= branch.end; i++) {
      if (/^\\placeholder/.test(atoms[i].latex || '')) placeholders.push(i);
    }
    // A selected empty slot is replaced by the next insertion, rather than
    // leaving the placeholder beside the new content.
    if (placeholders.length === 1 && branch.end === branch.start+1) {
      const offset = placeholders[0];
      field.selection = {ranges:[[offset-1,offset]],direction:'forward'};
    } else field.position = position;
  }
  function positions(structure, branch) {
    const {atoms} = index(), result = [];
    for (let i = branch.start; i <= branch.end; i++) {
      if (atoms[i].depth === structure.depth+1) result.push(i);
    }
    return result;
  }
  function align(structure, source, target) {
    const targets = positions(structure,target);
    const from = field.getElementInfo(field.position)?.bounds?.right;
    let offset;
    if (Number.isFinite(from)) {
      let distance = Infinity;
      for (const candidate of targets) {
        const x = field.getElementInfo(candidate)?.bounds?.right;
        if (Number.isFinite(x) && Math.abs(x-from) < distance) {
          distance = Math.abs(x-from); offset = candidate;
        }
      }
    }
    if (offset === undefined) {
      const rank = positions(structure,source).filter(p => p <= field.position).length-1;
      offset = targets[Math.min(Math.max(rank,0),targets.length-1)];
    }
    place(target,offset);
  }
  function collapse(direction) {
    if (field.selectionIsCollapsed || /^\\placeholder/.test(field.getValue(field.selection,'latex'))) return false;
    const ends = field.selection.ranges.flat();
    field.position = direction === 'up' ? Math.min(...ends) : Math.max(...ends);
    return true;
  }
  function vertical(direction) {
    if (collapse(direction)) return;
    const position = field.position;
    for (const structure of index().structures) {
      const current = structure.branches.findIndex(b => position >= b.start && position <= b.end);
      const beside = position === structure.start-1 || position === structure.end;
      if (current < 0 && !beside) continue;
      let target = -1;
      const {branches,kind} = structure;
      if (kind === 'fraction' || (kind === 'root' && branches.length === 2)) {
        target = direction === 'up' ? 0 : 1;
        if (target === current) continue;
      } else if (kind === 'script') {
        const label = direction === 'up' ? '指数' : '下标';
        target = branches.findIndex(b => b.level === label);
        if (target === current) continue;
        if (target < 0 && current >= 0) {
          // Insertions before the separate script atom can attach the old
          // exponent to a newly inserted letter. Exit after the whole item.
          field.position = structure.end; return;
        }
      } else if (kind === 'matrix' && current >= 0) {
        target = current + (direction === 'up' ? -structure.columns : structure.columns);
      } else if (kind === 'annotation') {
        const level = current >= 0 ? branches[current].level : 'base';
        const nextLevel = direction === 'up'
          ? (level === 'lower' && branches.some(b => b.level === 'base') ? 'base' : 'upper')
          : (level === 'upper' && branches.some(b => b.level === 'base') ? 'base' : 'lower');
        target = branches.findIndex(b => b.level === nextLevel);
        if (target === current) continue;
      }
      if (target >= 0 && target < branches.length) {
        if (current >= 0) align(structure,branches[current],branches[target]);
        else place(branches[target]);
        return;
      }
    }
  }
  function slot(direction) {
    collapse(direction === 'previous' ? 'up' : 'down');
    const current = context();
    if (current) {
      const next = current.slot + (direction === 'next' ? 1 : -1);
      if (next >= 0 && next < current.structure.branches.length) place(current.structure.branches[next]);
      else field.position = direction === 'next' ? current.structure.end : current.structure.start-1;
      return;
    }
    const candidates = index().structures.filter(s => direction === 'next'
      ? s.start > field.position : s.end <= field.position);
    candidates.sort((a,b) => direction === 'next' ? a.start-b.start || a.depth-b.depth : b.end-a.end || a.depth-b.depth);
    if (candidates.length) {
      const branches = candidates[0].branches;
      place(direction === 'next' ? branches[0] : branches.at(-1));
    }
  }
  return {
    location() {
      const current = context();
      return current ? current.structure.branches[current.slot].label : '公式';
    },
    slot(direction) {
      slot(direction);
      // Pinned MathLive 0.111.0 exposes no public undo boundary for offset
      // setters. This compatibility hook keeps typing in different slots
      // separate and records the final selection without changing content.
      field._mathfield?.stopCoalescingUndo();
    },
    move(direction) {
      if (direction === 'left' || direction === 'right') field.executeCommand(direction === 'left' ? 'moveToPreviousChar' : 'moveToNextChar');
      else if (direction === 'out') {
        collapse('down');
        const current = context();
        if (current) field.position = current.structure.end;
      } else vertical(direction);
      field._mathfield?.stopCoalescingUndo();
    }
  };
};
