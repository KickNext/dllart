#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EXAMPLE_DIR="$ROOT_DIR/example/calc"
CONFIG_PATH="$EXAMPLE_DIR/dllart.json"
BUILD_DIR="$EXAMPLE_DIR/build/calc"
source "$ROOT_DIR/scripts/runtime_support.sh"
cd "$ROOT_DIR"

run_case() {
  local label="$1"
  shift
  echo "== Runtime mode case: $label =="
  env "$@" "$BUILD_DIR/c_client"
}

dart pub get
(cd "$EXAMPLE_DIR" && dart pub get)
dart run dllart build --config "$CONFIG_PATH"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export DYLD_LIBRARY_PATH="$BUILD_DIR/lib:${DYLD_LIBRARY_PATH:-}"
else
  export LD_LIBRARY_PATH="$BUILD_DIR/lib:${LD_LIBRARY_PATH:-}"
fi

clang \
  "$EXAMPLE_DIR/c_client/main.c" \
  -I"$BUILD_DIR/include" \
  -L"$BUILD_DIR/lib" \
  -lcalc \
  -o "$BUILD_DIR/c_client"

run_case "auto(default)"
run_case "auto+helper-thread" DLLART_FORCE_HELPER_THREAD=1
run_case "sidecar" DLLART_RUNTIME_MODE=sidecar
run_case "sidecar+helper-thread" DLLART_RUNTIME_MODE=sidecar DLLART_FORCE_HELPER_THREAD=1

if dllart_runtime_dlopen_supported; then
  run_case "inprocess" DLLART_RUNTIME_MODE=inprocess
  run_case "inprocess+helper-thread" DLLART_RUNTIME_MODE=inprocess DLLART_FORCE_HELPER_THREAD=1
else
  echo "Skipping inprocess runtime cases: dartaotruntime is not dlopen-compatible for this SDK build."
fi
