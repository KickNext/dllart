# Contributing

Thanks for contributing to `dllart`.

## Development Setup

```bash
dart pub get
dart run dllart doctor
```

## Local Validation

Run before opening a PR:

```bash
dart analyze
dart run dllart build
scripts/smoke_test.sh
scripts/multi_module_smoke.sh
```

Optional performance validation:

```bash
scripts/benchmark.sh 300000
scripts/benchmark_threads.sh 8 8 50000
```

## Coding Guidelines

- Keep ABI changes backward-compatible unless versioned explicitly.
- Keep generated artifacts deterministic.
- Prefer module-scoped APIs (`<module>_dllart_*`).
- Update docs and changelog for user-facing behavior changes.

## Commit/PR Expectations

- Small, focused changes.
- Clear rationale in PR description.
- Tests/smoke output included for runtime/ABI-impacting changes.
