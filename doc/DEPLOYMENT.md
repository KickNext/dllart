# DLLART Deployment Playbook

## Goals

- Safe runtime upgrades.
- Fast rollback path.
- ABI compatibility guardrails.

## Deployment Unit

Deploy as one immutable unit:

- Native library (`lib<module>.so` / `lib<module>.dylib` / `<module>.dll`)
- Bundled runtime (`runtime/dartaotruntime*`)
- `artifact.json`
- Generated header (`include/<module>_api.h`)

Do not mix files from different builds.

## Pre-Deploy Checklist

1. `dart run dllart doctor --config <config> --json` returns `ok=true`.
2. `dart run dllart test --config <config> --skip-build --json` returns `ok=true`.
3. Check `artifact.json.abi.major` and exported symbols match expected consumer contract.
4. Validate runtime + library checksums from `artifact.json.checksums`.
5. Validate exported call paths do not depend on `dart:io` in module runtime.

## Rollout Steps

1. Build with pinned toolchain.
2. Publish full artifact directory as a versioned bundle.
3. Deploy new bundle alongside current bundle.
4. Switch host app to new bundle path atomically.
5. Run post-switch smoke calls (`init`, `call_json`, typed fast-path).
6. Monitor error code and error JSON rates (`*_last_error_code`, `*_last_error_json`).

## Rollback Steps

1. Switch host app back to previous bundle path.
2. Restart host processes if runtime/library handle caching is present in host app.
3. Re-run smoke calls against rolled-back bundle.
4. Record incident and attach failed `artifact.json` + logs.

## Compatibility Strategy

- `abi.major` must match consumer expectations; mismatches are blocking.
- Additive ABI changes increase `abi.minor` only.
- Keep symbol namespace module-scoped (`<module>_dllart_*`).
- Treat runtime + bridge template + manifest checksums as release gates.

## Operational Notes

- Prefer `init(NULL, ...)` with packaged runtime next to library.
- Use `DLLART_DART_RUNTIME` only for explicit override scenarios.
- For embedded hosts with non-standard call stacks, use `DLLART_FORCE_HELPER_THREAD=1`.
- For concurrency tuning, set `DLLART_ISOLATE_POOL_SIZE` and validate with stress tests.
- Keep filesystem/network/process I/O in host code; pass data to module via JSON/typed ABI.
