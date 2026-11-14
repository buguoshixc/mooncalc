// Headless smoke: serve playground/, load smoke.html in Chromium, wait for the
// #done verdict via the DevTools protocol (Node built-in WebSocket, zero npm deps).
// Uses the playwright-chromium wrapper (or $PLAYWRIGHT_CHROMIUM).
import http from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { spawn } from 'node:child_process';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '../playground');
const types = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.wasm': 'application/wasm',
};
const server = http.createServer((req, res) => {
  const urlPath = decodeURIComponent(req.url.split('?')[0]);
  const file = path.normalize(path.join(root, urlPath === '/' ? 'index.html' : urlPath));
  if (!file.startsWith(root) || !existsSync(file)) {
    res.writeHead(404);
    res.end('not found');
    return;
  }
  res.writeHead(200, { 'Content-Type': types[path.extname(file)] ?? 'application/octet-stream' });
  res.end(readFileSync(file));
});
await new Promise((r) => server.listen(0, '127.0.0.1', r));
const port = server.address().port;

// Grab a free port for the DevTools endpoint.
const probe = http.createServer();
await new Promise((r) => probe.listen(0, '127.0.0.1', r));
const dbgPort = probe.address().port;
await new Promise((r) => probe.close(r));

const chrome = process.env.PLAYWRIGHT_CHROMIUM ?? '/home/buguoshixc/.local/bin/playwright-chromium';
const child = spawn(chrome, [
  '--headless',
  '--no-sandbox',
  '--disable-gpu',
  `--remote-debugging-port=${dbgPort}`,
  `http://127.0.0.1:${port}/smoke.html`,
], { stdio: ['ignore', 'ignore', 'pipe'] });
let chromeErr = '';
child.stderr.on('data', (d) => { chromeErr += d; });

const deadline = Date.now() + 90_000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function findPageWs() {
  while (Date.now() < deadline) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${dbgPort}/json/list`)).json();
      const page = list.find((t) => t.type === 'page' && t.url.includes('/smoke.html'));
      if (page) return page.webSocketDebuggerUrl;
    } catch {}
    await sleep(200);
  }
  throw new Error('DevTools page target never appeared');
}

let verdict = null;
let items = [];
try {
  const ws = new WebSocket(await findPageWs());
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  let nextId = 1;
  const pending = new Map();
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      pending.get(msg.id)(msg);
      pending.delete(msg.id);
    }
  };
  const evaluate = (expression) => new Promise((res, rej) => {
    const id = nextId++;
    pending.set(id, (msg) => {
      if (msg.error) rej(new Error(msg.error.message));
      else if (msg.result.exceptionDetails) rej(new Error(JSON.stringify(msg.result.exceptionDetails)));
      else res(msg.result.result.value);
    });
    ws.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: { expression, returnByValue: true } }));
  });
  while (Date.now() < deadline) {
    const state = await evaluate(
      'JSON.stringify({done: document.getElementById("done").textContent,' +
      ' items: [...document.querySelectorAll("#results li")].map(li => li.textContent)})',
    );
    const { done, items: list } = JSON.parse(state);
    if (done !== 'RUNNING') { verdict = done; items = list; break; }
    await sleep(250);
  }
  ws.close();
} catch (err) {
  console.error('SMOKE FAIL:', err.message);
} finally {
  child.kill();
  server.close();
}

for (const item of items) console.log(item);
if (verdict === 'SMOKE PASS') {
  console.log('SMOKE PASS');
  process.exit(0);
}
console.error(verdict ?? 'SMOKE FAIL: timed out waiting for verdict');
if (!verdict) console.error(chromeErr.slice(-1500));
process.exit(1);