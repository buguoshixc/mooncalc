#!/usr/bin/env bash
# Zero-IO mechanical check: core must build for both backends.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.moon/bin:$PATH"

moon check --target wasm-gc
moon build --target wasm-gc
moon build --target native
moon test

paths=()
for p in src web facade.mbt; do
  [ -e "$p" ] && paths+=("$p")
done
if [ ${#paths[@]} -gt 0 ]; then
  if grep -RnE '@fs|@sys|println|extern "C"' "${paths[@]}"; then
    echo "zero-IO guard violated: IO found in core" >&2
    exit 1
  fi
fi
echo "ALL CHECKS PASS"