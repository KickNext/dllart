#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EXAMPLE_DIR="$ROOT_DIR/example/calc"
CONFIG_PATH="$EXAMPLE_DIR/dllart.json"
BUILD_DIR="$EXAMPLE_DIR/build/calc"
source "$ROOT_DIR/scripts/runtime_support.sh"
cd "$ROOT_DIR"

POOL_SIZE="${1:-1}"
THREADS="${2:-8}"
PER_THREAD="${3:-100000}"

dart pub get
(cd "$EXAMPLE_DIR" && dart pub get)
dart run dllart build --config "$CONFIG_PATH"

if ! dllart_runtime_dlopen_supported; then
  echo "Skipping benchmark_threads on Linux: dartaotruntime is not dlopen-compatible for this SDK build."
  exit 0
fi

clang -O3 \
  "$ROOT_DIR/scripts/benchmarks/ffi_bench_threads.c" \
  -I"$BUILD_DIR/include" \
  -L"$BUILD_DIR/lib" \
  -lcalc \
  -lpthread \
  -o "$BUILD_DIR/ffi_bench_threads"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export DYLD_LIBRARY_PATH="$BUILD_DIR/lib:${DYLD_LIBRARY_PATH:-}"
else
  export LD_LIBRARY_PATH="$BUILD_DIR/lib:${LD_LIBRARY_PATH:-}"
fi

export DLLART_ISOLATE_POOL_SIZE="$POOL_SIZE"
echo "DLLART_ISOLATE_POOL_SIZE=$DLLART_ISOLATE_POOL_SIZE"
"$BUILD_DIR/ffi_bench_threads" "$THREADS" "$PER_THREAD"
