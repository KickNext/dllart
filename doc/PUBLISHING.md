# Publishing to pub.dev

This guide is for publishing `dllart` to [pub.dev](https://pub.dev).

## 1. Pre-publish Checklist

- `pubspec.yaml` contains:
  - `description`
  - `homepage` / `repository` / `issue_tracker` / `documentation`
  - package `topics`
- `README.md` is up to date and in English.
- Runtime-library limitations are documented clearly (`dart:io` boundary for embedded module calls).
- `LICENSE` exists.
- `CHANGELOG.md` has an entry for the release version.
- `example/` exists and is useful.
- standalone runnable example remains in `example/calc/`.
- Mobile target gates are green in CI:
  - Android ABI matrix (`arm64-v8a`, `armeabi-v7a`, `x86_64`)
  - iOS xcframework validation (`ios-arm64`, `ios-arm64_x86_64-simulator`)
- ABI gate passes (`dllart test --skip-build --json`) on all required jobs.

Release gates:

- Gate A (Core Quality): analyze/test/smoke/publish dry-run.
- Gate B (ABI/Runtime Safety): ABI contract + lifecycle stress coverage.
- Gate C (DX/Usability): `create -> doctor -> build -> integrate -> package`.
- Gate D (Ecosystem Completeness): wrappers + deployment/compatibility/migration docs.

Stage policy:

- Stage 1 release requires A+B+C.
- Stage 2 release requires A+B+C+D.

## 2. Validate Locally

```bash
dart pub get
dart analyze
dart test
scripts/smoke_test.sh
scripts/multi_module_smoke.sh
dart test test/runtime_lifecycle_stress_test.dart
dart run dllart test --config example/calc/dllart.json --json
dart pub publish --dry-run
```

Fix all blocking issues from `--dry-run` before continuing.

## 3. Versioning

1. Update version in `pubspec.yaml`.
2. Add a matching section in `CHANGELOG.md`.
3. Commit the release changes.

## 4. Release Automation Checklist

1. Ensure changelog section matches `pubspec.yaml` version.
2. Re-run local validation block from section 2.
3. Confirm CI workflows are green for current release commit.
4. Tag release commit (recommended format: `vX.Y.Z`).
5. Publish package.

## 5. Publish

```bash
dart pub publish
```

## 6. Post-publish

- Verify the package page on pub.dev:
  - rendered README
  - API/documentation links
  - package score and pub points
- Tag release in VCS (recommended).
