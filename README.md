# dllart

`dllart` is a CLI toolchain that compiles a Dart module into a native FFI
library (`.dylib` / `.so` / `.dll`) and generates integration artifacts.

It is designed for:

- fast FFI integration from C/C++/Rust/Python/Go/C#/etc.
- a simple CLI workflow (`create`, `doctor`, `build`, `integrate`).
- post-package smoke checks via `dllart verify`.
- ABI contract checks via `dllart test`.
- production-friendly runtime packaging (`dartaotruntime` bundle + checks).

## Features

- module-scoped ABI symbols (`<module>_dllart_*`) for multi-module safety
- JSON ABI + typed ABI:
  - `i64_2` (+ index dispatch)
  - `i64_4` (+ index dispatch)
  - `f64_2` (+ index dispatch)
  - `f64_4` (+ index dispatch)
  - `json_batch`
- runtime bundling in build output
- runtime auto-lookup when `init(NULL, ...)` is used
- runtime version check (build SDK version vs loaded runtime)
- isolate pool support via `DLLART_ISOLATE_POOL_SIZE`
- machine-readable error contract:
  - `*_last_error_code`
  - `*_last_error_json`
- runtime safety limits for JSON/bytes payloads and method cache
- package scaffolds (`android`, `ios`, `fuchsia`, `flutter`, `python`, `csharp`)

## Installation

Global CLI:

```bash
dart pub global activate dllart
```

Run locally in a repo (without global activation):

```bash
dart run dllart <command>
```

Package page:

- https://pub.dev/packages/dllart

## Quick Start

Start path:

- Use `create` when you want a full new project scaffold.
- Use `init` when you already have an existing Dart project and only need `dllart.json` + module scaffold.

Create a new module project (`create` auto-selects dependency mode):

```bash
dllart create my_module
cd my_module
dart pub get
dllart doctor
dllart build
dllart integrate
```

Dependency selection in `create`:

```bash
# Auto (default): path for local checkout, version for pub-cache installs
dllart create my_module --dependency=auto

# Force pub version dependency
dllart create my_module --dependency=version

# Force local path dependency (explicit root or current tool root)
dllart create my_module --dependency=path --dllart-path=/abs/path/to/dllart

# Backward-compatible alias
dllart create my_module --local-path-dependency
```

One-command flow:

```bash
dllart make
```

## Repository Example Project

This repository keeps its full working example as an independent project in:

- `example/calc/`

Build it from repo root:

```bash
dart pub get
(cd example/calc && dart pub get)
dart run dllart build --config example/calc/dllart.json
```

## Exporting Dart Functions

```dart
import 'dart:typed_data';

import 'package:dllart/dllart_annotations.dart';

@DllartExport()
Object? add(Object? args) {
  final map = args as Map<String, dynamic>;
  return (map['a'] as num) + (map['b'] as num);
}

@DllartExport('add_fast')
int addFast(int a, int b) => a + b;

@DllartExport('sum4_fast')
int sum4Fast(int a, int b, int c, int d) => a + b + c + d;

@DllartExport('avg2_fast')
double avg2Fast(double a, double b) => (a + b) / 2.0;

@DllartExport('proto_fast')
Uint8List protoFast(Uint8List requestBytes) {
  // Decode protobuf, handle, encode protobuf.
  return requestBytes;
}
```

Supported signatures:

- `Object? fn()`
- `Object? fn(Object? args)`
- `int fn(int a, int b)` (direct typed `i64_2`)
- `int fn(int a, int b, int c, int d)` (direct typed `i64_4`)
- `double fn(double a, double b)` (direct typed `f64_2`)
- `double fn(double a, double b, double c, double d)` (direct typed `f64_4`)
- `Uint8List fn(Uint8List args)` / `Uint8List fn(List<int> args)` (direct typed `bytes`, protobuf-ready)

## Config Extensions (`dllart.json`)

All new fields are optional and backward-compatible.

- `limits`:
  - `json_in_max_bytes` (default `1048576`)
  - `json_out_max_bytes` (default `8388608`)
  - `bytes_in_max_bytes` (default `4194304`)
  - `bytes_out_max_bytes` (default `16777216`)
  - `method_cache_max_entries` (default `2048`)
- `runtime.profile`: `full|slim` (default `full`, packaging profile metadata only; does not change `dart:*` library availability in runtime)
- `logging`:
  - `format`: `text|json` (default `text`)
  - `level`: `error|warn|info` (default `info`)

## Build Output

For repository example config (`example/calc/dllart.json`) with
`output: build/calc`, `dllart build` generates:

- `example/calc/build/calc/include/` (`calc_api.h`)
- `example/calc/build/calc/lib/` (`libcalc.dylib` / `libcalc.so` / `calc.dll`)
- `example/calc/build/calc/runtime/` (bundled `dartaotruntime`)
- `example/calc/build/calc/integration/cmake/` (`calcConfig.cmake`)
- `example/calc/build/calc/integration/pkgconfig/` (`calc.pc`)
- `example/calc/build/calc/artifact.json` (manifest)
- `example/calc/build/calc/USAGE.md` (integration guide)

`artifact.json` includes release-gate metadata:

- `build.requested_target` / `build.effective_target`
- `build.mobile_outputs` (Android ABI libs / iOS xcframework paths)
- `build.bridge.source` + `build.bridge.sha256`
- `verification.symbols_exported`

## Runtime Model

`dllart` bundles `dartaotruntime` at build time and validates runtime version
during init.

With `*_init(NULL, ...)`, runtime lookup order is:

1. explicit `runtime_path` argument (if provided)
2. `DLLART_DART_RUNTIME` env var
3. runtime near the loaded library
4. `../runtime/dartaotruntime` relative to library directory
5. build-time fallback path

For embedders that call C ABI functions from non-standard/synthetic stacks
(for example some Node.js FFI runtimes), you can force dllart to run calls on
a helper pthread stack:

```bash
export DLLART_FORCE_HELPER_THREAD=1
```

## Runtime Library Compatibility (Important)

`dllart` embeds Dart AOT in a custom host runtime. In the current runtime model
(`0.1.0` and mainline as of 2026-02-18), not every `dart:*` library behaves the
same way as in standalone Dart VM/CLI apps.

Known-good in runtime smoke checks:

- `dart:core`
- `dart:async`
- `dart:convert`
- `dart:math`
- `dart:typed_data`
- `dart:ffi`
- basic `dart:isolate` access (`Isolate.current`)

Known limitation:

- `dart:io` is not supported in embedded module calls right now.
- Calls such as `Platform.operatingSystem` / `File.*` can terminate the process
  with unresolved native runtime symbols.

What to do in production:

- keep module code pure/compute-oriented (`JSON`, typed ABI, bytes ABI)
- move filesystem/network/process I/O to the host side (C/C++/Rust/Python/Go/C#)
- call into module with prepared payloads and return pure results

Note on profiles:

- `runtime.profile=full|slim` currently does not change this behavior.
- Use profile as packaging/trace metadata only until runtime-side support expands.

## ABI

Low-level module symbols:

- `<module>_dllart_init`
- `<module>_dllart_call_json`
- `<module>_dllart_call_json_batch`
- `<module>_dllart_call_json_raw`
- `<module>_dllart_call_i64_2`
- `<module>_dllart_call_i64_2_index`
- `<module>_dllart_call_i64_4`
- `<module>_dllart_call_i64_4_index`
- `<module>_dllart_call_f64_2`
- `<module>_dllart_call_f64_2_index`
- `<module>_dllart_call_f64_4`
- `<module>_dllart_call_f64_4_index`
- `<module>_dllart_call_bytes`
- `<module>_dllart_call_bytes_index`
- `<module>_dllart_last_error_code`
- `<module>_dllart_last_error_json`
- `<module>_dllart_shutdown`
- `<module>_dllart_string_free`
- `<module>_dllart_bytes_free`

ABI versioning:

- `<module>_dllart_abi_version()` returns ABI major.
- `artifact.json.abi.major` must match `*_abi_version()` (validated by `dllart test`).
- additive ABI changes bump `abi.minor` in `artifact.json` without breaking major.

Generated C wrappers in `<module>_api.h` include:

- JSON wrappers per exported method
- raw JSON wrappers per exported method (`*_raw`)
- typed wrappers per compatible method
- typed fast indexed wrappers (`*_fast`)

`call_json` contract (stable wrapper):

- success: `{"ok":true,"result":...}`
- failure: `{"ok":false,"error":"...","error_details":{"method":"...","input_type":"...","error_type":"...","stack":"..."}}`

Raw mode without wrapper:

- use `<module>_dllart_call_json_raw`
- success returns method result encoded as JSON directly
- failure returns non-zero and detailed `error_out`

Node.js / TypeScript (koffi) notes:

- declare `result_json_out` / `error_out` as `void**` in koffi and decode manually
- free returned buffers with `<module>_dllart_string_free`
- if your FFI runtime uses custom stacks, set `DLLART_FORCE_HELPER_THREAD=1`

```ts
import koffi from 'koffi';

const lib = koffi.load('build/calc/lib/libcalc.dylib');
const voidPtr = koffi.pointer('void');
const voidPtrPtr = koffi.pointer(voidPtr);

const init = lib.func('int calc_dllart_init(const char* runtime_path, _Out_ char** error_out)');
const callRaw = lib.func('calc_dllart_call_json_raw', 'int', [
  'str',
  'str',
  koffi.out(voidPtrPtr),
  koffi.out(voidPtrPtr),
]);
const freeStr = lib.func('void calc_dllart_string_free(void* value)');
```

## Commands

```bash
dllart create my_module
dllart create my_module --dependency=auto|version|path --dllart-path=/abs/path/to/dllart
dllart create my_module --local-path-dependency
dllart new my_module
dllart init --name calc --source lib/module.dart
dllart doctor
dllart check
dllart doctor --fix
dllart doctor --package-target=python|csharp|android|ios|flutter|all
dllart build
dllart build --verbose
dllart build --runtime-profile=full|slim --target=host|android|ios --android-abis=arm64-v8a,armeabi-v7a,x86_64 --ios-variants=all|device|simulator
dllart integrate
dllart integrate --verbose
dllart test --perf-gate
dllart verify --target=c|python|csharp|all --json
dllart make
dllart proto --proto proto/service.proto --out lib/generated/proto
dllart workflow --force
dllart package android|ios|fuchsia|flutter|python|csharp|all
dllart package all --auto-build --android-abis=arm64-v8a,armeabi-v7a,x86_64 --ios-variants=all
```

Help model:

```bash
dllart --help
dllart help build
dllart help package
```

Protobuf prerequisites:

```bash
# protoc
brew install protobuf

# Dart protoc plugin
dart pub global activate protoc_plugin
```

If plugin is not on PATH, add pub cache bin:

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"
```

Machine-readable output is available for automation:

```bash
dllart doctor --json
dllart build --json
dllart integrate --json
dllart proto --json
dllart test --json
```

Each command prints a single JSON object with `ok`, `command`, `status`, and
`data`/`error`.

## MCP Server (for AI agents)

`dllart` includes an MCP stdio server so LLM clients can call CLI workflows as
tools.

Start server:

```bash
dart bin/dllart_mcp.dart
```

or from global activation:

```bash
dllart_mcp
```

Exposed tools:

- `dllart.run` - run a `dllart` command with structured arguments
- `dllart.help` - get global or command-specific help text

Notes:

- `dllart.run` auto-enables `--json` for `build`, `doctor`, `integrate`,
  `proto`, `verify`, and `test` (unless overridden).
- Set `DLLART_MCP_DLLART_BIN` if the `dllart` executable is not available on
  `PATH`.
- In MCP client configs, prefer direct command invocation (`command: "dart"`)
  plus explicit `cwd` instead of shell wrappers such as `zsh -lc`.

## Config Schema

`dllart.json` follows the schema:

- `doc/schema/dllart.schema.json`

Validation is strict:

- unknown keys are rejected
- malformed JSON reports `line:column`
- invalid fields report exact config location when possible
- `logging.format` / `logging.level` affect non-`--json` diagnostics only

Protobuf config example:

```json
{
  "name": "calc",
  "source": "lib/module.dart",
  "output": "build",
  "protobuf": {
    "proto": "proto/calc.proto",
    "out": "lib/generated/proto",
    "includes": ["proto", "third_party/proto"],
    "grpc": false
  }
}
```

Convenience for protobuf generation:

- `dllart proto proto/service.proto` uses positional source path
- `dllart proto` can auto-detect a single file in `./proto/` if config is absent
- `dllart proto --json` returns machine-readable output

## Mobile Package Scaffolds

Build mobile artifacts first:

```bash
dllart build --target=android --android-abis=arm64-v8a,armeabi-v7a,x86_64
dllart build --target=ios --ios-variants=all
```

Then generate package scaffolds from real built outputs:

```bash
dllart package android --force
dllart package ios --force
dllart package flutter --force
```

Target integrity:

- `build --target=android|ios` is fail-fast (no silent host fallback).
- `build --target=android` requires `ANDROID_NDK_HOME`.
- `build --target=ios` is macOS-only and requires iOS `gen_snapshot` binaries
  (`DLLART_IOS_GEN_SNAPSHOT_ARM64`, `DLLART_IOS_GEN_SNAPSHOT_X64`).

Generated directories include:

- `<output>/package/runtime/` (bundled runtime)
- `<output>/package/android/`
- `<output>/package/ios/`
- `<output>/package/fuchsia/`
- `<output>/package/flutter_plugin/`
- `<output>/package/python/`
- `<output>/package/csharp/`

Python/C# scaffolds use host artifacts. Build host target first:

```bash
dllart build --target=host
dllart package python --force
dllart package csharp --force
```

## Performance Snapshot

`scripts/benchmark.sh 300000` (2026-02-06, macOS arm64):

- `json_add`: `967783 calls/s`
- `typed_fallback_add`: `1544044 calls/s`
- `typed_direct_add`: `1751416 calls/s`

`scripts/benchmark_threads.sh 8 8 50000`:

- `json_add`: `947474 calls/s`
- `typed_fallback_add`: `1157411 calls/s`
- `typed_direct_add`: `1213666 calls/s`

## Documentation

- MCP server guide: `doc/MCP.md`
- Deployment playbook: `doc/DEPLOYMENT.md`
- Compatibility matrix: `doc/COMPATIBILITY_MATRIX.md`
- Migration guide: `doc/MIGRATION_GUIDE.md`
- Config schema: `doc/schema/dllart.schema.json`
- Release maintainer guide: `doc/PUBLISHING.md`

## Validation (Repository Checkout)

These checks expect a full repository checkout (with `scripts/` and test assets):

```bash
dart run dllart doctor --config example/calc/dllart.json
dart test test/runtime_lifecycle_stress_test.dart
scripts/smoke_test.sh
scripts/multi_module_smoke.sh
```
