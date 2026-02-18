# DLLART Research: Architecture, Risks, Performance

- Date: 2026-02-06
- Scope: architecture validity, pitfalls, usage patterns, performance, and
  low-level optimization opportunities.

## 1. Is the Direction Correct?

Short answer: yes for desktop FFI scenarios.

Reasons:

- clear UX (`create/new`, `doctor/check`, `build`, `integrate`, `make`,
  `package`)
- module-scoped symbols prevent collisions in multi-module processes
- bundled runtime + runtime auto-lookup + runtime version validation
- typed fast-path ABI (`i64_2`, `i64_4`, `f64_2`) with indexed dispatch
- isolate pool support for concurrent throughput scaling

Current boundary:

- `dllart build` is host build (macOS/Linux/Windows), not a full native mobile
  cross-build pipeline.

## 2. Platform Status (iOS/Android/Fuchsia)

- macOS/Linux/Windows: supported today
- Android: scaffold exists, native NDK cross-build not yet integrated
- iOS: scaffold exists, xcframework build pipeline not yet integrated
- Fuchsia: scaffold exists, dedicated target/pipeline not yet integrated
- Flutter: plugin scaffold exists

Scaffold command:

- `dllart package android|ios|fuchsia|flutter|python|csharp|all`

## 3. Pitfalls

### 3.1 Runtime Distribution

- shared library depends on compatible `dartaotruntime`
- SDK/runtime mismatch can fail at init/runtime
- mitigated by:
  - runtime bundle in output artifacts
  - runtime version validation during `*_init`

### 3.2 ABI Evolution

- low-level ABI cannot be broken without versioning
- capability/manifest contract is required for future ABI expansion

### 3.3 JSON Hot-path Cost

- UTF-8 marshaling + JSON decode/encode + allocation overhead
- typed ABI should be preferred for high-frequency low-latency calls

### 3.4 Parallel Build Races

- solved by output lock (`<output>/.build.lock`)

### 3.5 Multi-module Lifecycle

- VM lifecycle is process-wide
- isolate pool + tolerant VM init reduce risk
- centralized runtime coordinator remains the next major step

## 4. Usage Patterns

1. C/C++ service logic integration
2. Python automation via `ctypes`
3. Multi-module host process with isolated module APIs

## 5. Performance Snapshot

`scripts/benchmark.sh 300000` (single-thread, 2026-02-06, macOS arm64):

- `json_add`: ~968k calls/s
- `typed_fallback_add`: ~1.54M calls/s
- `typed_direct_add`: ~1.75M calls/s
- typed direct vs JSON: ~1.87x

`scripts/benchmark_threads.sh 8 8 50000`:

- `json_add`: ~947k calls/s
- `typed_fallback_add`: ~1.16M calls/s
- `typed_direct_add`: ~1.21M calls/s

Conclusion:

- typed ABI gives stable wins
- isolate pool improves concurrent throughput

## 6. Improvement Backlog

### Done

- namespaced module ABI
- tolerant VM init
- typed ABI (`i64_2`, `i64_4`, `f64_2`) + indexed dispatch
- benchmark suite
- runtime bundle + version check

### In Progress

- runtime coordinator with module handles and ownership model

### Next

- native mobile build modes (Android/iOS)
- Fuchsia feasibility prototype

### Low-level Optimization Candidates

1. extra fixed-signature ABI (`f64_4`, bytes/buffer ABI, batch-call ABI)
2. reduced branch cost in dispatch (precomputed binders/tables)
3. optional response arena to reduce allocation pressure
4. LTO/PGO and per-platform compiler tuning
5. per-isolate preallocated typed argument structures

## 7. DX Recommendations

- keep default flow minimal: `dllart create <name>` then `dllart make`
- keep generated integration artifacts canonical:
  - `artifact.json`
  - `USAGE.md`
  - CMake and pkg-config output
- keep mobile integration path explicit and separate from host build path

## 8. Practical Summary

`dllart` is production-capable for desktop-style FFI integration now.

Mobile/Fuchsia native build pipelines still require dedicated work, but the
current runtime and ABI architecture provides a strong base for that phase.
