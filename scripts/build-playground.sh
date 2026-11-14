#!/usr/bin/env bash
# Build the wasm-gc engine and stage it into the static playground.
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."
moon build --target wasm-gc
cp _build/wasm-gc/debug/build/web/web.wasm playground/web.wasm
echo "playground ready: serve playground/ over http and open index.html"