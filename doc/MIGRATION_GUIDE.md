# DLLART Migration Guide

Updated: 2026-02-18

## Scope

This guide covers migration between `0.1.0` and current mainline behavior.

## Summary Of Non-Breaking Changes

- Extended ABI surface (batch + additional typed paths).
- Stronger doctor/build/test release gates.
- Runtime lifecycle hardening for repeated init/shutdown paths.
- New package scaffold targets: `python`, `csharp`.
- Config `logging` now drives non-JSON diagnostics formatting/verbosity.
- `create` dependency model now supports `--dependency=auto|version|path` and `--dllart-path`.
- `package` is idempotent across targets and `package all` now supports preflight + `--auto-build`.
- New integration smoke command: `dllart verify --target=c|python|csharp|all`.
- `doctor` supports optional package toolchain checks via `--package-target=...`.
- Help model is command-scoped (`dllart help <command>`).
- Embedded runtime boundary is now explicitly documented: `dart:io` is not
  supported in module calls and should be kept in host-side code.

## Consumer Migration Checklist

1. Rebuild module with current `dllart`.
2. Compare old/new `artifact.json`:
   - `abi.major` must remain compatible for in-place upgrade.
   - Review new `build` and `verification` fields.
3. Re-run ABI contract test:
   - `dart run dllart test --config <config> --skip-build --json`
4. Re-run host smoke calls:
   - JSON path (`call_json`)
   - Typed path (`call_i64_2`, `call_i64_4`, `call_f64_2`, `call_f64_4`, `call_bytes`)
5. Validate module imports:
   - If exported methods rely on `dart:io`, move that logic to host side before release.
6. If adopting new scaffolds, regenerate packages:
   - `dllart package python`
   - `dllart package csharp`
7. Run scaffold smoke verification:
   - `dllart verify --target=python`
   - `dllart verify --target=csharp`

## Runtime Upgrade Notes

- Deploy runtime + library + manifest as one bundle.
- Do not reuse runtime binary from a different artifact build.
- Keep rollback bundle available before switch.

## Config Migration Notes

- Existing configs remain valid.
- Optional `logging` section can be added safely:

```json
{
  "logging": {
    "format": "text",
    "level": "info"
  }
}
```

`--json` command output remains unchanged.

## CLI Migration Notes

- `create` default is now `--dependency=auto`:
  - local checkout install -> path dependency
  - pub/global install -> version dependency
- `--local-path-dependency` is still accepted as an alias for path mode.
- `package all` now prints a preflight checklist instead of failing late when mobile artifacts are missing.
- Add `--auto-build` to let package preflight build missing targets automatically.

## Troubleshooting

- Missing host library during `dllart package python|csharp`:
  - Run `dllart build --target=host` first.
- Android/iOS package generation without mobile artifacts:
  - Run target-specific mobile builds before packaging.
- ABI mismatch at runtime:
  - Rebuild both producer and consumer against same release line.
- Process abort with unresolved native symbol in module call:
  - Check for `dart:io` usage in exported call path and refactor I/O to host side.
