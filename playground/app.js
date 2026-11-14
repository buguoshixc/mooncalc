import { loadEngine } from './loader.js';

const COLS = 8, ROWS = 8;
const cells = new Map();
let selected = 'A1';
let evaluate = null;
let lastResults = new Map();

const gridEl = document.getElementById('grid');
const barEl = document.getElementById('formula-bar');
const detailEl = document.getElementById('detail');
const errorsEl = document.getElementById('errors');
const selAddrEl = document.getElementById('sel-addr');

function addr(c, r) { return String.fromCharCode(65 + c) + (r + 1); }

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
        if (a === selected) barEl.value = input.value;
        scheduleRecalc();
      });
    }
    gridEl.appendChild(tr);
  }
}

function select(a) {
  selected = a;
  selAddrEl.textContent = a;
  barEl.value = cells.get(a) ?? '';
  document.querySelectorAll('td.selected').forEach(td => td.classList.remove('selected'));
  inputFor(a).parentElement.classList.add('selected');
  renderDetail();
}

function inputFor(a) { return gridEl.querySelector(`input[data-addr="${a}"]`); }

barEl.addEventListener('input', () => {
  cells.set(selected, barEl.value);
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
  const grid = {};
  for (const [a, raw] of cells) {
    const spec = cellSpec(raw);
    if (spec !== null) grid[a] = spec;
  }
  const resp = evaluate({ grid });
  errorsEl.textContent = '';
  lastResults = new Map();
  document.querySelectorAll('td .val').forEach(v => { v.textContent = ''; v.className = 'val'; });
  if (!resp.ok) {
    errorsEl.textContent = resp.error;
    renderDetail();
    return;
  }
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
    if (r.circular) text += '\n⚠ circular reference: cycle cells evaluate to 0 (Excel default, iterative calc off)';
  } else if (raw.trim().startsWith('=')) {
    text += '\n(not evaluated yet)';
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
};

document.getElementById('presets').addEventListener('change', (e) => {
  cells.clear();
  gridEl.querySelectorAll('input').forEach(i => { i.value = ''; });
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
try {
  evaluate = await loadEngine();
  recalc();
} catch (err) {
  detailEl.textContent = 'failed to load engine: ' + err.message;
}