// Browser loader for the MoonBit wasm-gc module (same contract as scripts/spike.mjs).
// Prefers native wasm:js-string builtins; falls back to JS polyfills where possible.
// fromCharCodeArray (GC array → string) cannot be polyfilled in JS, so engines
// that import it require a host with native builtin support (modern Chromium/Node).
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

function stringGlobals(mod) {
  const imports = {};
  for (const imp of WebAssembly.Module.imports(mod)) {
    if (imp.module === '_' && imp.kind === 'global') {
      // Imported string constants: the import name IS the string value.
      imports['_'] ??= {};
      imports['_'][imp.name] = imp.name;
    }
  }
  return imports;
}

export async function loadMoonWasm(bytes) {
  try {
    const mod = await WebAssembly.compile(bytes, { builtins: ['js-string'] });
    return await WebAssembly.instantiate(mod, stringGlobals(mod));
  } catch (nativeErr) {
    const mod = await WebAssembly.compile(bytes);
    const imports = stringGlobals(mod);
    for (const imp of WebAssembly.Module.imports(mod)) {
      if (imp.module === 'wasm:js-string') {
        imports['wasm:js-string'] ??= {};
        const fn = jsStringBuiltins[imp.name];
        if (!fn) {
          throw new Error(
            `this browser lacks wasm js-string builtin "${imp.name}"; use a current Chromium or Firefox`,
            { cause: nativeErr },
          );
        }
        imports['wasm:js-string'][imp.name] = fn;
      }
    }
    return WebAssembly.instantiate(mod, imports);
  }
}

export async function loadEngine(wasmUrl = 'web.wasm') {
  const bytes = await (await fetch(wasmUrl)).arrayBuffer();
  const instance = await loadMoonWasm(bytes);
  return {
    evaluate: (request) => JSON.parse(instance.exports.evaluate_json(JSON.stringify(request))),
    explain: (request) => JSON.parse(instance.exports.explain_json(JSON.stringify(request))),
    recalcIncremental: (request) => JSON.parse(instance.exports.recalc_incremental_json(JSON.stringify(request))),
  };
}