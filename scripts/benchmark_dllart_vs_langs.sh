#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC_DIR="$ROOT_DIR/scripts/benchmarks/library_compare"
BUILD_DIR="$ROOT_DIR/build/library_compare"
TMP_DIR="$BUILD_DIR/tmp"
REPORT_PATH="${1:-$ROOT_DIR/doc/dllart-vs-cpp-rust-go.md}"

ITERATIONS="${BENCH_ITERATIONS:-100000000}"
FILE_MB="${BENCH_FILE_MB:-256}"
REPEATS="${BENCH_REPEATS:-3}"

mkdir -p "$BUILD_DIR" "$TMP_DIR" "$(dirname "$REPORT_PATH")"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd dart
require_cmd c++
require_cmd rustc
require_cmd go
require_cmd python3

if [[ "$(uname -s)" == "Darwin" ]]; then
  SHARED_EXT="dylib"
else
  SHARED_EXT="so"
fi

DLLART_BUILD_DIR="$ROOT_DIR/example/calc/build/calc"
DLLART_LIB="$DLLART_BUILD_DIR/lib/libcalc.$SHARED_EXT"
CPP_LIB="$BUILD_DIR/libbench_cpp.$SHARED_EXT"
RUST_LIB="$BUILD_DIR/libbench_rust.$SHARED_EXT"
GO_LIB="$BUILD_DIR/libbench_go.$SHARED_EXT"

cd "$ROOT_DIR"

dart pub get
(cd "$ROOT_DIR/example/calc" && dart pub get)
dart run dllart build --config "$ROOT_DIR/example/calc/dllart.json"

c++ -O3 -std=c++20 -fPIC -shared \
  "$SRC_DIR/cpp_native_lib.cpp" \
  -o "$CPP_LIB"

rustc -O -C target-cpu=native -C codegen-units=1 \
  --crate-type=cdylib \
  "$SRC_DIR/rust_native_lib.rs" \
  -o "$RUST_LIB"

go build -buildmode=c-shared -trimpath -ldflags='-s -w' \
  -o "$GO_LIB" \
  "$SRC_DIR/go_native_lib.go"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export DYLD_LIBRARY_PATH="$DLLART_BUILD_DIR/lib:$BUILD_DIR:${DYLD_LIBRARY_PATH:-}"
else
  export LD_LIBRARY_PATH="$DLLART_BUILD_DIR/lib:$BUILD_DIR:${LD_LIBRARY_PATH:-}"
fi

python3 "$ROOT_DIR/scripts/benchmark_dllart_vs_langs.py" \
  --dllart-lib "$DLLART_LIB" \
  --cpp-lib "$CPP_LIB" \
  --rust-lib "$RUST_LIB" \
  --go-lib "$GO_LIB" \
  --report "$REPORT_PATH" \
  --iterations "$ITERATIONS" \
  --file-mb "$FILE_MB" \
  --repeats "$REPEATS" \
  --tmp-dir "$TMP_DIR"
