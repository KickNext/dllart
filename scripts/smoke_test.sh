#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EXAMPLE_DIR="$ROOT_DIR/example/calc"
CONFIG_PATH="$EXAMPLE_DIR/dllart.json"
BUILD_DIR="$EXAMPLE_DIR/build/calc"
cd "$ROOT_DIR"

dart pub get
(cd "$EXAMPLE_DIR" && dart pub get)
dart run dllart build --config "$CONFIG_PATH"

UNAME_OUT=$(uname -s)
if [[ "$UNAME_OUT" == "Darwin" ]]; then
  LIB_PATH="$BUILD_DIR/lib/libcalc.dylib"
else
  LIB_PATH="$BUILD_DIR/lib/libcalc.so"
fi

if [[ ! -f "$LIB_PATH" ]]; then
  echo "Built library not found: $LIB_PATH" >&2
  exit 1
fi

clang \
  "$EXAMPLE_DIR/c_client/main.c" \
  -I"$BUILD_DIR/include" \
  -L"$BUILD_DIR/lib" \
  -lcalc \
  -o "$BUILD_DIR/c_client"

if [[ "$UNAME_OUT" == "Darwin" ]]; then
  export DYLD_LIBRARY_PATH="$BUILD_DIR/lib:${DYLD_LIBRARY_PATH:-}"
else
  export LD_LIBRARY_PATH="$BUILD_DIR/lib:${LD_LIBRARY_PATH:-}"
fi

"$BUILD_DIR/c_client"
python3 "$EXAMPLE_DIR/python_client/main.py" "$LIB_PATH"
