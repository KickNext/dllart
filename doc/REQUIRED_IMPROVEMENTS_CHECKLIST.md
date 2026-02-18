# dllart Required Improvements Checklist

## P0 (must-have before scale)

- [x] Define ABI contract policy (`abi_version`, SemVer rules, backward/forward compatibility).
- [x] Finish runtime coordinator for multi-module lifecycle (VM ownership, init/shutdown order).
- [x] Make `init`/`shutdown` fully idempotent and thread-safe.
- [x] Introduce stable error contract (error codes + machine-readable details, not only text).
- [x] Add input safety limits (`json`/`bytes` payload size, oversized payload protection).
- [x] Enforce CI e2e matrix: macOS/Linux/Windows + C/Python smoke + multi-module smoke.
- [x] Add reproducible artifact checks and checksums in `artifact.json`.
- [x] Add ABI symbol gate in `doctor` against `artifact.json.symbols`.
- [x] Enforce bridge source/version consistency checks in `doctor`.

## P1 (major competitive boost)

- [x] Implement Android NDK cross-build in `dllart build`.
- [x] Implement iOS native pipeline (XCFramework + automated Podspec flow).
- [x] Extend typed ABI (`f64_4`, batch call mode, improved bytes fast-path).
- [x] Add performance gates in CI (regression thresholds for benchmarks).
- [x] Add runtime packaging profiles (`full` and `slim`).
- [x] Generate ready-to-use client wrappers for Python and C# (templates + typing).
- [x] Add structured logs/diagnostics for CI/CD integration.
- [x] Add strict release gate behavior for mobile targets/ABIs in CI workflows.

## P2 (DX and adoption)

- [x] Add `doctor --fix` for auto-remediation of common environment issues.
- [x] Add production deployment docs (runtime upgrade, rollback, compatibility strategy).
- [x] Publish compatibility matrix (`dllart` version x Dart SDK x target OS).
- [x] Add migration guide for ABI/artifact changes.
- [ ] Add reference host-app examples for CMake, Python, Rust, and C#.
- [x] Add release automation checklist (tagging, changelog, publish flow).
