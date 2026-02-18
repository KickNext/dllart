#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EXAMPLE_DIR="$ROOT_DIR/example/calc"
CONFIG_PATH="$EXAMPLE_DIR/dllart.json"
BUILD_ROOT="$EXAMPLE_DIR/build"
PRIMARY_BUILD_DIR="$BUILD_ROOT/calc"
SECONDARY_BUILD_DIR="$BUILD_ROOT/calc2"
cd "$ROOT_DIR"

dart pub get
(cd "$EXAMPLE_DIR" && dart pub get)

# Build primary module from repo config.
dart run dllart build --config "$CONFIG_PATH"

TMP_SOURCE="${TMPDIR:-/tmp}/dllart_calc2_module.dart"
cat > "$TMP_SOURCE" <<DART
import '${ROOT_DIR}/lib/dllart_annotations.dart';

@DllartExport()
Object? ping() => 'pong2';

@DllartExport()
Object? add(Object? args) {
  if (args is! Map<String, dynamic>) {
    throw ArgumentError('Expected map payload');
  }
  final a = args['a'];
  final b = args['b'];
  if (a is! num || b is! num) {
    throw ArgumentError('Expected numeric fields a/b');
  }
  return a + b + 1000;
}
DART

dart run dllart build \
  --name calc2 \
  --source "$TMP_SOURCE" \
  --output "$SECONDARY_BUILD_DIR"

cat > "$BUILD_ROOT/multi_module_smoke.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "calc_api.h"
#include "calc2_api.h"

static void fail(const char* ctx, const char* message) {
  fprintf(stderr, "%s failed: %s\n", ctx, message ? message : "<unknown>");
  exit(1);
}

static void expect_contains(const char* ctx, const char* text, const char* needle) {
  if (text == NULL || strstr(text, needle) == NULL) {
    fail(ctx, text);
  }
}

int main(void) {
  char* err = NULL;
  char* res = NULL;

  if (calc_init(NULL, &err) != 0) {
    fail("calc_init", err);
  }
  if (calc2_init(NULL, &err) != 0) {
    fail("calc2_init", err);
  }

  if (calc_ping("{}", &res, &err) != 0) {
    fail("calc_ping", err);
  }
  expect_contains("calc_ping", res, "pong");
  calc_string_free(res);
  res = NULL;

  if (calc2_ping("{}", &res, &err) != 0) {
    fail("calc2_ping", err);
  }
  expect_contains("calc2_ping", res, "pong2");
  calc2_string_free(res);
  res = NULL;

  if (calc_add("{\"a\":1,\"b\":2}", &res, &err) != 0) {
    fail("calc_add", err);
  }
  expect_contains("calc_add", res, "\"result\":3");
  calc_string_free(res);
  res = NULL;

  if (calc2_add("{\"a\":1,\"b\":2}", &res, &err) != 0) {
    fail("calc2_add", err);
  }
  expect_contains("calc2_add", res, "\"result\":1003");
  calc2_string_free(res);
  res = NULL;

  calc2_shutdown();
  calc_shutdown();
  printf("multi-module smoke passed\n");
  return 0;
}
C

clang \
  "$BUILD_ROOT/multi_module_smoke.c" \
  -I"$PRIMARY_BUILD_DIR/include" \
  -I"$SECONDARY_BUILD_DIR/include" \
  -L"$PRIMARY_BUILD_DIR/lib" \
  -L"$SECONDARY_BUILD_DIR/lib" \
  -lcalc \
  -lcalc2 \
  -o "$BUILD_ROOT/multi_module_smoke"

if [[ "$(uname -s)" == "Darwin" ]]; then
  export DYLD_LIBRARY_PATH="$PRIMARY_BUILD_DIR/lib:$SECONDARY_BUILD_DIR/lib:${DYLD_LIBRARY_PATH:-}"
else
  export LD_LIBRARY_PATH="$PRIMARY_BUILD_DIR/lib:$SECONDARY_BUILD_DIR/lib:${LD_LIBRARY_PATH:-}"
fi

"$BUILD_ROOT/multi_module_smoke"
