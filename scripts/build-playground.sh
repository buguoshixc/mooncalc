#!/usr/bin/env bash
# Build the wasm-gc engine and stage it into the static playground.
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."
moon build --target wasm-gc
# Artifact path differs between single-module (build/web/) and workspace
# (build/<module>/web/) layouts; locate it instead of hardcoding.
wasm=$(find _build/wasm-gc/debug/build -path "*/web/web.wasm" | head -1)
if [ -z "$wasm" ]; then
  echo "web.wasm not found under _build/wasm-gc/debug/build" >&2
  exit 1
fi
cp "$wasm" playground/web.wasm
echo "playground ready: serve playground/ over http and open index.html"