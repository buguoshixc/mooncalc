import { readFileSync } from 'node:fs';

// JS string builtins fallback (used when the host does not auto-provide them).
const jsStringBuiltins = {
  cast: (x) => String(x),
  concat: (a, b) => String(a) + String(b),
  equals: (a, b) => a === b,
  compare: (a, b) => (a < b ? -1 : a > b ? 1 : 0),
  length: (s) => s.length,
  charCodeAt: (s, i) => s.charCodeAt(i),
  substring: (s, a, b) => s.substring(a, b),
  fromCharCode: (c) => String.fromCharCode(c),
  fromCodePoint: (c) => String.fromCodePoint(c),
};

export async function loadMoonWasm(bytes) {
  const mod = await WebAssembly.compile(bytes);
  const imports = {};
  for (const imp of WebAssembly.Module.imports(mod)) {
    if (imp.module === '_' && imp.kind === 'global') {
      // Imported string constants: the import name IS the string value.
      imports['_'] ??= {};
      imports['_'][imp.name] = imp.name;
    } else if (imp.module === 'wasm:js-string') {
      imports['wasm:js-string'] ??= {};
      const fn = jsStringBuiltins[imp.name];
      if (!fn) throw new Error(`unimplemented js-string builtin: ${imp.name}`);
      imports['wasm:js-string'][imp.name] = fn;
    }
  }
  const instance = await WebAssembly.instantiate(mod, imports);
  return instance;
}

const wasmPath = process.argv[2];
if (!wasmPath) {
  console.error('usage: node spike.mjs <path-to-web.wasm>');
  process.exit(2);
}
const instance = await loadMoonWasm(readFileSync(wasmPath));
const result = instance.exports.spike_echo('hello mooncalc');
console.log('spike result:', result);
if (result !== 'echo:hello mooncalc') {
  console.error('SPIKE FAIL');
  process.exit(1);
}
console.log('SPIKE PASS');