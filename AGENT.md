# AGENT.md

## Scope

This document defines how an engineering agent should work in this repository.
Project: `dllart` (Dart-to-native FFI toolchain CLI).

## Goals

- Keep the CLI stable and predictable.
- Preserve ABI compatibility unless change is explicitly approved.
- Prioritize production usability: diagnostics, integration artifacts, and CI reliability.

## Repository Map

- `bin/dllart.dart`: CLI entry point.
- `lib/src/cli/`: command parsing, build/integrate/doctor/package/proto logic.
- `native/`: C bridge sources and headers.
- `example/calc/`: end-to-end reference module and client examples.
- `scripts/`: smoke tests and benchmarks.
- `test/`: unit and e2e tests for CLI behavior.
- `doc/`: schema, RFCs, research, and maintenance docs.

## Quick Commands

```bash
dart pub get
dart analyze
dart test

dart run dllart doctor --config example/calc/dllart.json
dart run dllart build --config example/calc/dllart.json
dart run dllart integrate --config example/calc/dllart.json

scripts/smoke_test.sh
scripts/multi_module_smoke.sh
scripts/benchmark.sh 120000
```

## Working Rules

- Make minimal, focused changes; avoid unrelated refactors.
- Do not break existing CLI flags, command names, or JSON output contracts.
- Keep generated artifact paths and naming stable.
- Treat ABI changes as high risk; document and gate them.
- Prefer explicit errors with actionable messages.
- Update docs when behavior, commands, or artifacts change.

## Testing Requirements

For non-trivial changes, run at least:

```bash
dart analyze
dart test
```

If build/runtime/ABI/integration code changed, also run:

```bash
scripts/smoke_test.sh
```

If module lifecycle or symbol scoping changed, also run:

```bash
scripts/multi_module_smoke.sh
```

If performance-sensitive dispatch changed, run:

```bash
scripts/benchmark.sh 120000
```

## Definition of Done

- Code compiles and tests pass for affected scope.
- CLI output remains backward compatible (unless intentionally versioned).
- Documentation is updated.
- No obvious regressions in smoke scenarios.
