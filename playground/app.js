import { loadEngine } from './loader.js';
import { parseCsv } from './csv.js';

const COLS = 8, ROWS = 8;
const cells = new Map();
let selected = 'A1';
let evaluate = null;
let recalcIncremental = null;
let lastResults = new Map();
// Incremental recalc: the wasm shell holds the engine state; the page tracks
// edited addresses since the last recalc and forces a reset on bulk loads
// (preset / CSV / iterative toggle), where per-cell change tracking is moot.
let incReset = true;
const pendingChanges = new Set();
// Dependency graph provided by the engine (AST-level, ranges expanded, quoted
// strings ignored) via the evaluate_json response's `graph` field.
let graph = { precedents: new Map(), dependents: new Map() };
let explain = null;

const gridEl = document.getElementById('grid');
const barEl = document.getElementById('formula-bar');
const detailEl = document.getElementById('detail');
const errorsEl = document.getElementById('errors');
const selAddrEl = document.getElementById('sel-addr');
const iterEl = document.getElementById('iterative');
const recalcInfoEl = document.getElementById('recalc-info');

function addr(c, r) { return String.fromCharCode(65 + c) + (r + 1); }

function addrRC(a) {
  const col = a.charCodeAt(0) - 65;
  const row = Number(a.slice(1)) - 1;
  return [col, row];
}

function addrSort(a, b) {
  // M8 起键可能是限定地址（`SHEET!A1`）：非 A1 形态回退字符串比较（不做多表 UI）。
  if (a.includes('!') || b.includes('!')) return a < b ? -1 : a > b ? 1 : 0;
  const [ca, ra] = addrRC(a);
  const [cb, rb] = addrRC(b);
  return ra - rb || ca - cb;
}

function allAddrs() {
  const out = [];
  for (let r = 0; r < ROWS; r++) for (let c = 0; c < COLS; c++) out.push(addr(c, r));
  return out;
}

function currentGrid() {
  const grid = {};
  for (const [a, raw] of cells) {
    const spec = cellSpec(raw);
    if (spec !== null) grid[a] = spec;
  }
  return grid;
}

// Transitive closure in one direction (precedents or dependents).
function reachable(start, map) {
  const out = new Set();
  const stack = [...(map.get(start) ?? [])];
  while (stack.length) {
    const a = stack.pop();
    if (out.has(a)) continue;
    out.add(a);
    for (const n of map.get(a) ?? []) stack.push(n);
  }
  return out;
}

function isErrorAddr(a) {
  const r = lastResults.get(a);
  return !!r && r.value.type === 'error';
}

// Contribution-aware error trace from the engine (leftmost-wins probes).
function errorTrace(start) {
  if (!explain) return { chain: new Set([start]), sources: [], steps: [] };
  const resp = explain({ grid: currentGrid(), addr: start });
  if (!resp.ok) return { chain: new Set([start]), sources: [], steps: [] };
  const chain = new Set(resp.steps.map(s => s.addr));
  chain.add(start);
  return { chain, sources: resp.sources, steps: resp.steps };
}

function buildGrid() {
  const head = document.createElement('tr');
  head.appendChild(document.createElement('th'));
  for (let c = 0; c < COLS; c++) {
    const th = document.createElement('th');
    th.textContent = String.fromCharCode(65 + c);
    head.appendChild(th);
  }
  gridEl.appendChild(head);
  for (let r = 0; r < ROWS; r++) {
    const tr = document.createElement('tr');
    const th = document.createElement('th');
    th.textContent = String(r + 1);
    tr.appendChild(th);
    for (let c = 0; c < COLS; c++) {
      const a = addr(c, r);
      const td = document.createElement('td');
      const input = document.createElement('input');
      input.dataset.addr = a;
      const val = document.createElement('div');
      val.className = 'val';
      td.append(input, val);
      tr.appendChild(td);
      input.addEventListener('focus', () => select(a));
      input.addEventListener('input', () => {
        cells.set(a, input.value);
        pendingChanges.add(a);
        if (a === selected) barEl.value = input.value;
        scheduleRecalc();
      });
    }
    gridEl.appendChild(tr);
  }
}

function inputFor(a) { return gridEl.querySelector(`input[data-addr="${a}"]`); }

function tdFor(a) { return inputFor(a)?.parentElement ?? null; }

function clearMarks(cls) {
  document.querySelectorAll(`td.${cls}`).forEach(td => td.classList.remove(cls));
}

function mark(addrs, cls) {
  for (const a of addrs) tdFor(a)?.classList.add(cls);
}

function renderHighlights() {
  clearMarks('prec');
  clearMarks('dep');
  if (!evaluate) return;
  // Selected cell -> blue: all cells it (transitively) reads from.
  mark(reachable(selected, graph.precedents), 'prec');
  // Selected cell -> green: all cells that (transitively) read it.
  mark(reachable(selected, graph.dependents), 'dep');
  // Error propagation chain runs upstream from the selected error cell; the
  // chain cells are precedent-highlighted, sources keep their existing .err.
  if (isErrorAddr(selected)) {
    mark(errorTrace(selected).chain, 'prec');
  }
}

function select(a) {
  selected = a;
  selAddrEl.textContent = a;
  barEl.value = cells.get(a) ?? '';
  document.querySelectorAll('td.selected').forEach(td => td.classList.remove('selected'));
  tdFor(a)?.classList.add('selected');
  renderHighlights();
  renderDetail();
}

barEl.addEventListener('input', () => {
  cells.set(selected, barEl.value);
  pendingChanges.add(selected);
  inputFor(selected).value = barEl.value;
  scheduleRecalc();
});

function cellSpec(raw) {
  const s = (raw ?? '').trim();
  if (s === '') return null;
  if (s.startsWith('=')) return { formula: s };
  if (s.startsWith("'")) return s.slice(1);
  if (/^-?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(s)) return Number(s);
  if (s === 'TRUE') return true;
  if (s === 'FALSE') return false;
  return s;
}

let timer = null;
function scheduleRecalc() {
  clearTimeout(timer);
  timer = setTimeout(recalc, 120);
}

function recalc() {
  if (!evaluate) return;
  const grid = currentGrid();
  const iterative = iterEl.checked;
  let resp;
  if (iterative) {
    resp = evaluate({ grid, iter: { max_iterations: 100, max_change: 0.001 } });
    incReset = true;
  } else {
    const req = { grid };
    if (incReset) req.reset = true;
    else req.changed = [...pendingChanges];
    resp = recalcIncremental(req);
    incReset = !resp.ok;
  }
  pendingChanges.clear();
  errorsEl.textContent = '';
  lastResults = new Map();
  document.querySelectorAll('td .val').forEach(v => {
    v.textContent = '';
    v.className = 'val';
  });
  if (!resp.ok) {
    errorsEl.textContent = resp.error;
    recalcInfoEl.textContent = '';
    renderHighlights();
    renderDetail();
    return;
  }
  graph = {
    precedents: new Map(Object.entries(resp.graph?.precedents ?? {})),
    dependents: new Map(Object.entries(resp.graph?.dependents ?? {})),
  };
  for (const r of resp.results) {
    lastResults.set(r.target, r);
    const el = inputFor(r.target)?.parentElement.querySelector('.val');
    if (!el) continue;
    el.textContent = displayValue(r.value);
    if (r.value.type === 'error') el.classList.add('err');
    if (r.circular) el.classList.add('circ');
  }
  if (resp.parse_errors.length) {
    errorsEl.textContent = resp.parse_errors.map(p => `${p.addr}: ${p.message}`).join('\n');
  }
  const total = resp.results.length;
  if (total === 0) {
    recalcInfoEl.textContent = '';
  } else if (iterative) {
    recalcInfoEl.textContent = `recalc: ${total}/${total} formula cells · iterative (≤100 passes, max change 0.001)`;
  } else if (resp.incremental.full) {
    recalcInfoEl.textContent = `recalc: ${total}/${total} formula cells · full rebuild`;
  } else {
    recalcInfoEl.textContent = `recalc: ${resp.incremental.recomputed.length}/${total} formula cells · incremental`;
  }
  renderHighlights();
  renderDetail();
}

function displayValue(v) {
  switch (v.type) {
    case 'number': return String(v.value);
    case 'text': return v.value === '' ? '""' : v.value;
    case 'bool': return v.value ? 'TRUE' : 'FALSE';
    case 'error': return v.value;
    case 'blank': return '';
    case 'range': return `[${v.rows}×${v.cols} range]`;
    default: return '?';
  }
}

function renderDetail() {
  const raw = cells.get(selected) ?? '';
  const r = lastResults.get(selected);
  let text = `${selected}  raw: ${raw === '' ? '(blank)' : raw}`;
  if (r) {
    text += `\nvalue: ${JSON.stringify(r.value)}`;
    if (r.circular) {
      text += iterEl.checked
        ? '\n⚠ circular reference: iterated toward convergence (iterative calc on: ≤100 passes, max change 0.001)'
        : '\n⚠ circular reference: cycle cells evaluate to 0 (Excel default, iterative calc off)';
    }
  } else if (raw.trim().startsWith('=')) {
    text += '\n(not evaluated yet)';
  }
  const prec = [...(graph.precedents.get(selected) ?? [])].sort(addrSort);
  const dep = [...(graph.dependents.get(selected) ?? [])].sort(addrSort);
  if (prec.length) text += `\nprecedents: ${prec.join(', ')}`;
  if (dep.length) text += `\ndependents: ${dep.join(', ')}`;
  if (isErrorAddr(selected)) {
    const tr = errorTrace(selected);
    const { chain, sources } = tr;
    const chainText = [...chain].sort(addrSort).join(', ');
    const sourceText = sources.map((a) => {
      const src = cells.get(a) ?? '';
      const val = lastResults.get(a)?.value;
      return `${a} = ${src}${val ? ' → ' + displayValue(val) : ''}`;
    }).join('; ');
    text += `\nerror trace: ${chainText}`;
    text += `\nerror source: ${sourceText}`;
    if (tr.steps.length) text += `\npath: ${tr.steps.map(s => s.addr).join(' → ')}`;
  } else if (evaluate && lastResults.size === 0) {
    text += '\nengine ready — edit a cell or pick a preset';
  }
  detailEl.textContent = text;
}

const PRESETS = {
  error: { A1: '1', A2: '0', B1: '=A1/A2', B2: '=B1+1', C1: '=SUM(B1:B2)' },
  textnum: { A1: "'3", A2: '4', B1: '=SUM(A1,4)', B2: '=SUM("3",4)', C1: '=A1=A2' },
  blank: { B1: '=A1+1', B2: '=A1=0', A2: '=""', B3: '=COUNTA(A1:A2)' },
  circular: { A1: '=A1+1', B1: '=A1+5' },
  iterative: { A1: '=B1+10', B1: '=A1/2', C1: '=A1+B1' },
  xlookup: {
    A1: 'apple', A2: 'banana', A3: 'cherry',
    B1: '10', B2: '20', B3: '30',
    D1: '=XLOOKUP("banana",A1:A3,B1:B3)',
    D2: '=XLOOKUP("berry",A1:A3,B1:B3,"not found")',
    D3: '=XLOOKUP("b*",A1:A3,B1:B3,"none",2)',
  },
  ifs: {
    A1: '75',
    B1: '=IFS(A1>=90,"A",A1>=60,"B",TRUE,"C")',
    B2: '=IFS(A1>=90,"A",A1>=80,"B")',
    B3: '=IFS(TRUE,1,TRUE,1/0)',
  },
  switch: {
    A1: '75',
    B1: '=SWITCH(A1,100,"full",75,"three quarters","other")',
    B2: '=SWITCH(A1,1,"one",2,"two")',
    B3: '=SWITCH("B","b","hit","miss")',
  },
  textjoin: {
    A1: 'alpha', A3: 'gamma',
    B1: '=TEXTJOIN(", ",TRUE,A1:A3)',
    B2: '=TEXTJOIN("-",TRUE,A1:A2)',
  },
  eomonth: {
    A1: '=DATE(2026,11,15)',
    B1: '=EOMONTH(A1,0)',
    B2: '=DAY(B1)',
    C1: '=EOMONTH(DATE(2024,1,31),1)',
    C2: '=YEAR(C1)',
    C3: '=EOMONTH(DATE(2026,1,15),-1)',
  },
  textfmt: {
    A1: '=TEXT(12345,"0.00E+00")',
    A2: '=TEXT(0.000123,"0.00E+00")',
    A3: '=TEXT(9.99,"0.0E+00")',
    C1: '=TEXT(1.5,"[h]:mm")',
    C2: '=TEXT(0.5,"[m]:ss")',
    E1: '=TEXT(150,"[>100]""big"";""small""")',
    E2: '=TEXT(50,"[>100]""big"";""small""")',
  },
};

document.getElementById('presets').addEventListener('change', (e) => {
  cells.clear();
  incReset = true;
  pendingChanges.clear();
  gridEl.querySelectorAll('input').forEach(i => { i.value = ''; });
  gridEl.querySelectorAll('td .val').forEach(v => { v.textContent = ''; v.className = 'val'; });
  const preset = PRESETS[e.target.value] ?? {};
  for (const [a, raw] of Object.entries(preset)) {
    cells.set(a, raw);
    inputFor(a).value = raw;
  }
  select(selected);
  recalc();
});

buildGrid();
select('A1');

// CSV import: drag-drop onto the page or the Import CSV button. Row-major into
// the 8×8 grid; cellSpec typing applies (=formula cells are the demo point).
function importCsvText(text) {
  let rows;
  try {
    rows = parseCsv(text);
  } catch (err) {
    errorsEl.textContent = 'CSV import failed: ' + err.message;
    return;
  }
  let overflow = false;
  cells.clear();
  incReset = true;
  pendingChanges.clear();
  gridEl.querySelectorAll('input').forEach(i => { i.value = ''; });
  for (let r = 0; r < rows.length; r++) {
    for (let c = 0; c < rows[r].length; c++) {
      if (r >= ROWS || c >= COLS) { overflow = true; continue; }
      const raw = rows[r][c];
      if (raw === '') continue;
      const a = addr(c, r);
      cells.set(a, raw);
      inputFor(a).value = raw;
    }
  }
  select(selected);
  recalc();
  if (overflow) errorsEl.textContent = 'CSV truncated to the 8×8 grid';
}

document.body.addEventListener('dragover', (e) => { e.preventDefault(); });
document.body.addEventListener('drop', (e) => {
  e.preventDefault();
  const file = e.dataTransfer?.files?.[0];
  if (file) file.text().then(importCsvText);
});
const csvFileEl = document.getElementById('csv-file');
document.getElementById('csv-import').addEventListener('click', () => csvFileEl.click());
csvFileEl.addEventListener('change', () => {
  const f = csvFileEl.files?.[0];
  if (f) f.text().then(importCsvText);
  csvFileEl.value = '';
});

iterEl.addEventListener('change', () => {
  incReset = true;
  pendingChanges.clear();
  recalc();
});

try {
  const eng = await loadEngine();
  evaluate = eng.evaluate;
  explain = eng.explain;
  recalcIncremental = eng.recalcIncremental;
  recalc();
} catch (err) {
  detailEl.textContent = 'failed to load engine: ' + err.message;
}
