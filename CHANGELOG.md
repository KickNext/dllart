# Changelog

## Unreleased

- Fixed MCP parity issue where stale precompiled `bin/dllart_mcp` could miss
  newer commands/options (`verify`, `dependency`, `auto_build`, etc.).
- Reduced duplicate `dart pub get` error noise in `build`/`make` failure paths.
- Changed `doctor` package config check to skip warning when project context has
  no `pubspec.yaml` (common `init`-only layout).
- Improved `package --target=all --auto-build` preflight to report aggregated
  environment/toolchain blockers before attempting builds.
- Removed internal research/readiness/RFC docs from repository root docs set to
  keep user-facing documentation focused.
- Documented embedded runtime library compatibility boundaries:
  - `dart:io` is currently unsupported in module call paths.
  - Added explicit guidance in README + deployment/compatibility/migration docs.

- Added ABI surface extensions (backward-compatible):
  - `call_json_batch`
  - `call_f64_4`
  - `call_f64_4_index`
  - `last_error_code`
  - `last_error_json`
- Added runtime safety limits in `dllart.json` (`limits.*`) with safe defaults.
- Added runtime packaging profile in `dllart.json` (`runtime.profile=full|slim`).
- Added logging config in `dllart.json` (`logging.format`, `logging.level`).
- Added CLI options:
  - `doctor --fix`
  - `doctor --package-target=python|csharp|android|ios|flutter|all`
  - `build --runtime-profile=full|slim`
  - `build --target=host|android|ios`
  - `build --android-abis=arm64-v8a,armeabi-v7a,x86_64`
  - `build --ios-variants=all|device|simulator`
  - `build|make|package|integrate|doctor|verify --verbose`
  - `create --local-path-dependency`
  - `create --dependency=auto|version|path`
  - `create --dllart-path=<dir>`
  - `package --auto-build`
  - `test --perf-gate`
- Changed `create` default dependency mode:
  - now uses `--dependency=auto`
  - auto resolves to path dependency for local checkout installs
  - auto resolves to version dependency for pub-cache/global installs
  - `--local-path-dependency` remains a compatibility alias for path mode
- Added command-scoped help model:
  - global help lists commands only
  - flags are documented per command via `dllart help <command>`
- Made mobile target behavior strict:
  - removed silent host fallback for `build --target=android|ios`
  - fail-fast with actionable errors when mobile toolchain requirements are missing
- Added artifact reproducibility and traceability metadata:
  - `artifact.json.abi`
  - `artifact.json.build.reproducible`
  - `artifact.json.build.effective_target`
  - `artifact.json.build.mobile_outputs`
  - `artifact.json.build.bridge` (`source`, `sha256`)
  - `artifact.json.runtime.profile`
  - `artifact.json.checksums` (SHA-256)
  - `artifact.json.verification.symbols_exported`
- Added ABI contract validation that `*_abi_version()` matches
  `artifact.json.abi.major`.
- Added doctor ABI gates:
  - checks exported symbols in produced binaries against `artifact.json.symbols`
  - validates bridge source/sha consistency with tool templates
- Updated package/integrate mobile behavior:
  - package generation now consumes real Android/iOS artifacts from manifest
  - `package` is now idempotent across targets by default (merge behavior)
  - `package all` runs preflight checks and prints unified prerequisite checklist
  - `package all --auto-build` can build missing host/android/ios prerequisites
  - Flutter scaffold now includes `f64_4`/`f64_4_index` method IDs and bindings
  - integrate output includes mobile artifact paths when present
  - integrate output includes minimal Python/C# runnable snippets
- CI updates:
  - ABI contract checks run on Unix and Windows
  - perf workflow now depends on ABI gate
  - added mobile jobs for Android ABI matrix and iOS xcframework validation
- Added package scaffold targets:
  - `package python`
  - `package csharp`
- Added `verify` command:
  - `dllart verify --target=c|python|csharp|all`
  - supports `--json` and returns exit code `1` on any FAIL item
- Added optional doctor package toolchain checks:
  - python3 / dotnet / Android NDK / iOS toolchain / Flutter
- Added runtime lifecycle hardening:
  - cleanup path now releases isolate pool + runtime handle deterministically
  - VM ownership tracking for safer `shutdown` cleanup behavior
- Added runtime lifecycle stress test coverage (`test/runtime_lifecycle_stress_test.dart`).
- Enabled config-driven diagnostics behavior:
  - `logging.format` and `logging.level` now affect non-`--json` command logs
- Added production operations docs:
  - production readiness report
  - deployment playbook
  - compatibility matrix
  - migration guide

## 0.1.0

- Initial public release of `dllart`.
- Added project scaffolding commands: `create`, `new`, `init`.
- Added validation and guided workflow commands:
  - `doctor`, `check`, `build`, `integrate`, `make`, `workflow`.
- Added typed ABI support with indexed fast-path dispatch:
  - `i64_2`, `i64_4`, `f64_2`.
- Added runtime bundling:
  - output includes `runtime/dartaotruntime`.
  - runtime auto-lookup in `*_init(NULL, ...)`.
  - runtime version check against build SDK version.
- Added packaging scaffolds:
  - `android`, `ios`, `fuchsia`, `flutter`, `all`.
- Added benchmark and smoke scripts for correctness and throughput checks.
