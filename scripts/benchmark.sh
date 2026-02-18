#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EXAMPLE_DIR="$ROOT_DIR/example/calc"
CONFIG_PATH="$EXAMPLE_DIR/dllart.json"
BUILD_DIR="$EXAMPLE_DIR/build/calc"
source "$ROOT_DIR/scripts/runtime_support.sh"
cd "$ROOT_DIR"

ITERATIONS="${1:-500000}"

dart pub get
(cd "$EXAMPLE_DIR" && dart pub get)
dart run dllart build --config "$CONFIG_PATH"

if ! dllart_runtime_dlopen_supported; then
  echo "Skipping benchmark on Linux: dartaotruntime is not dlopen-compatible for this SDK build."
  exit 0
fi

clang -O3 \
  "$ROOT_DIR/scripts/benchmarks/ffi_bench.c" \
  -I"$BUILD_DIR/include" \
  -L"$BUILD_DIR/lib" \
  -lcalc \
  -o "$BUILD_DIR/ffi_bench"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export DYLD_LIBRARY_PATH="$BUILD_DIR/lib:${DYLD_LIBRARY_PATH:-}"
else
  export LD_LIBRARY_PATH="$BUILD_DIR/lib:${LD_LIBRARY_PATH:-}"
fi

"$BUILD_DIR/ffi_bench" "$ITERATIONS"
