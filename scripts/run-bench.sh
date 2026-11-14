#!/usr/bin/env bash
# Build the native CLI and run bench. Usage: scripts/run-bench.sh [corpus-dir] [extra flags...]
set -euo pipefail
export PATH="$HOME/.moon/bin:$PATH"
cd "$(dirname "$0")/.."
moon build --target native
exec _build/native/debug/build/cmd/main/main.exe bench --corpus "${1:-corpus/provisional}" "${@:2}"