# DLLART Compatibility Matrix

Updated: 2026-02-18

## Package Compatibility

| dllart version | Dart SDK constraint | Notes |
| --- | --- | --- |
| 0.1.0 | `^3.10.0` | Initial public release line with typed ABI and runtime bundling. |
| Unreleased (main) | `^3.10.0` | Includes mobile strict gates, runtime hardening, Python/C# package scaffolds. |

## Host Build Targets

| Target | Build Support | Runtime Notes |
| --- | --- | --- |
| macOS arm64 | Yes | `.dylib` + `dartaotruntime` bundle. |
| macOS x64 | Yes | Generated via target config / workflow matrix. |
| Linux x64 | Yes | `.so` + `dartaotruntime` bundle. |
| Windows x64 | Yes | `.dll` + `dartaotruntime.exe` bundle. |

## Mobile Build Targets

| Target | Build Support | Required Inputs |
| --- | --- | --- |
| Android (`arm64-v8a`, `armeabi-v7a`, `x86_64`) | Yes | `ANDROID_NDK_HOME`, ABI-specific `gen_snapshot` when host arch differs. |
| iOS (device + simulator xcframework) | Yes (macOS only) | `DLLART_IOS_GEN_SNAPSHOT_ARM64`, `DLLART_IOS_GEN_SNAPSHOT_X64` when needed. |

## Embedded `dart:*` Library Support

Scope: module code executed through `*_dllart_call_*` APIs in embedded runtime.
Status snapshot: validated on 2026-02-18 (Dart 3.11 runtime, macOS arm64 host).

| Library | Status | Notes |
| --- | --- | --- |
| `dart:core`, `dart:async`, `dart:convert`, `dart:math`, `dart:typed_data` | Supported | Works in standard module calls. |
| `dart:ffi` | Supported | `Abi.current()` and basic FFI types work in module code. |
| `dart:isolate` | Partially supported | Basic access (`Isolate.current`) works; advanced isolate orchestration should be validated per module. |
| `dart:io` | Not supported | `Platform.*` / `File.*` calls can abort process with unresolved native symbol errors. |

Operational guidance:

- Treat `dart:io` usage in module code as a release blocker.
- Keep I/O in host runtime and pass prepared data into module calls.
- `runtime.profile=full|slim` does not currently change `dart:io` availability.

## Package Scaffold Targets

| `dllart package` target | Status |
| --- | --- |
| `android` | Supported |
| `ios` | Supported |
| `fuchsia` | Supported |
| `flutter` | Supported |
| `python` | Supported |
| `csharp` | Supported |
| `all` | Supported (requires artifacts for included targets) |

## ABI Compatibility Rules

- `artifact.json.abi.major` must match `<module>_dllart_abi_version()`.
- Major changes are breaking.
- Minor changes are additive and backward-compatible.
