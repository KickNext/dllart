# RFC-0001: DLLART Runtime Architecture

- Status: Proposed
- Date: 2026-02-06
- Owners: dllart core

## Current Implementation Status

- P0 implemented:
  - module-scoped low-level symbols (`<module>_dllart_*`)
  - tolerant VM init when runtime is already initialized in-process
  - multi-module smoke tests
- P1 implemented:
  - typed fast-path ABI: `call_i64_2`, `call_i64_4`, `call_f64_2`
  - indexed typed dispatch: `call_i64_2_index`, `call_i64_4_index`,
    `call_f64_2_index`
  - direct typed dispatch for fixed signatures
  - benchmark suite (`JSON vs typed`)
- P2 partially implemented:
  - isolate pool runtime via `DLLART_ISOLATE_POOL_SIZE`
  - round-robin isolate selection
- DX/operability:
  - `make` command (`doctor + build + integrate`)
  - aliases: `new`, `check`
  - packaging scaffold: `package android|ios|fuchsia|flutter|python|csharp|all`
  - runtime bundle in output: `build/<module>/runtime/dartaotruntime`
  - runtime version check (expected SDK vs loaded runtime)
  - build lock: `<output>/.build.lock`

## Context

`dllart` already covers desktop MVP well (Dart module to shared library with
FFI calls), but scale introduces constraints:

1. Symbol collisions and VM lifecycle complexity in multi-module processes.
2. JSON ABI overhead on hot paths.
3. Host-focused build pipeline (mobile pipelines are separate work).

## Goals

1. Safe multi-module behavior in a single process.
2. Preserve simple CLI UX while adding explicit fast-path ABI.
3. Prepare architecture for Android/iOS/Fuchsia packaging and integration.

## Non-goals (This Iteration)

1. Full native mobile cross-build in this iteration.
2. Replacing JSON ABI as default.
3. Complex isolate orchestration beyond current pool model.

## Key Design

### A. Symbol Namespacing

Each module exports unique low-level symbols:

- `<module>_dllart_init`
- `<module>_dllart_call_json`
- `<module>_dllart_call_i64_2`
- `<module>_dllart_call_i64_2_index`
- `<module>_dllart_call_i64_4`
- `<module>_dllart_call_i64_4_index`
- `<module>_dllart_call_f64_2`
- `<module>_dllart_call_f64_2_index`
- `<module>_dllart_shutdown`
- `<module>_dllart_string_free`

This prevents linker/runtime symbol interposition across modules.

### B. Runtime Lifecycle Tolerance

Bridge behavior when VM is already initialized:

- tolerate already-initialized VM flag/init errors
- continue isolate creation for the current module
- validate runtime version against build SDK version during init

### C. Dual ABI Strategy

- JSON ABI remains universal.
- Typed ABI provides hot-path acceleration for fixed signatures.
- Indexed typed ABI removes method-name lookup on hot path.

### D. Runtime Resolution Strategy

When `init(NULL, ...)` is used, runtime lookup order:

1. explicit `runtime_path` (if passed)
2. `DLLART_DART_RUNTIME`
3. runtime next to loaded module library
4. `../runtime/dartaotruntime` relative to library dir
5. build-time fallback path

### E. ABI Policy and SemVer Rules

- `dllart_abi_version()` is the ABI **major** and is stable for all
  backward-compatible updates.
- `artifact.json.abi` carries full ABI metadata:
  - `major`: must equal `dllart_abi_version()`
  - `minor`: additive ABI surface changes only
  - `patch`: bug fixes without ABI surface expansion
- `artifact.json.build` and `artifact.json.checksums` are additive metadata and
  do not change runtime symbol behavior.

Compatibility matrix:

| Runtime `dllart_abi_version()` | `artifact.json.abi.major` | Compatibility |
|---|---:|---|
| same | same | compatible |
| different | different | incompatible (reject) |

Deprecation policy:

1. Existing exported C ABI symbols are never removed in the same ABI major.
2. New ABI capabilities are additive (`*_call_f64_4`, `*_call_json_batch`,
   `*_last_error_code`, `*_last_error_json`).
3. Legacy string `error_out` remains supported; machine-readable error APIs are
   additive and preferred for automation.

## Migration Plan

1. P0:
  - namespaced symbols
  - tolerant VM init
  - multi-module smoke validation
2. P1:
  - typed fast-path ABI + indexed dispatch
  - benchmark baseline
3. P2:
  - runtime coordinator (`module handles`, lifecycle ownership)
4. P3:
  - native mobile build pipelines (NDK/xcframework/Fuchsia)
  - Android/iOS CI matrix
  - Fuchsia feasibility spike

## Risks and Mitigations

1. ABI compatibility risk:
  - keep low-level contract stable
  - expose higher-level generated wrappers in `<module>_api.h`
2. Typed ABI misuse risk:
  - runtime validation + explicit `error_out`
3. VM lifecycle complexity risk:
  - move toward centralized runtime owner in P2

## Success Metrics

1. Multiple modules can be called in one process without collisions.
2. Typed ABI outperforms JSON ABI on hot path.
3. Integration remains simple (`doctor/build/integrate`).

## Baseline Measurements (macOS arm64, 2026-02-06)

`scripts/benchmark.sh 300000`:

- `json_add`: `avg=1.033us`, `throughput=967783 calls/s`
- `typed_fallback_add`: `avg=0.648us`, `throughput=1544044 calls/s`
- `typed_direct_add`: `avg=0.571us`, `throughput=1751416 calls/s`

`scripts/benchmark_threads.sh 8 8 50000`:

- `json_add`: `947474 calls/s`
- `typed_fallback_add`: `1157411 calls/s`
- `typed_direct_add`: `1213666 calls/s`
