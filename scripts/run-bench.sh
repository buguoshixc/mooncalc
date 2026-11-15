#!/usr/bin/env bash
# Build the native CLI and run bench. Usage: scripts/run-bench.sh [corpus-dir] [extra flags...]
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."
moon build --target native
# Artifact path differs between single-module and workspace layouts.
exe=$(find _build/native/debug/build -path "*/cmd/main/main.exe" | head -1)
if [ -z "$exe" ]; then
  echo "main.exe not found under _build/native/debug/build" >&2
  exit 1
fi
exec "$exe" bench --corpus "${1:-corpus/cases}" "${@:2}"