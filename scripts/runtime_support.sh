#!/usr/bin/env bash

dllart_find_dartaotruntime() {
  local dart_bin
  dart_bin="$(command -v dart 2>/dev/null || true)"
  if [[ -z "$dart_bin" ]]; then
    return 1
  fi

  local dart_dir
  dart_dir="$(cd "$(dirname "$dart_bin")" && pwd)"
  local candidates=(
    "$dart_dir/dartaotruntime"
    "$dart_dir/dartaotruntime.exe"
    "$dart_dir/cache/dart-sdk/bin/dartaotruntime"
    "$dart_dir/cache/dart-sdk/bin/dartaotruntime.exe"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

dllart_runtime_dlopen_supported() {
  if [[ "$(uname -s)" != "Linux" ]]; then
    return 0
  fi

  if ! command -v clang >/dev/null 2>&1; then
    return 1
  fi

  local runtime_path
  runtime_path="$(dllart_find_dartaotruntime 2>/dev/null || true)"
  if [[ -z "$runtime_path" || ! -f "$runtime_path" ]]; then
    return 1
  fi

  local probe_dir probe_src probe_bin
  probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/dllart_runtime_probe_XXXXXX")"
  probe_src="$probe_dir/probe.c"
  probe_bin="$probe_dir/probe"

  cat >"$probe_src" <<'C'
#include <dlfcn.h>

int main(int argc, char** argv) {
  if (argc < 2) {
    return 2;
  }
  void* handle = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
  if (handle == NULL) {
    return 1;
  }
  dlclose(handle);
  return 0;
}
C

  if ! clang "$probe_src" -ldl -o "$probe_bin" >/dev/null 2>&1; then
    rm -rf "$probe_dir"
    return 1
  fi

  "$probe_bin" "$runtime_path" >/dev/null 2>&1
  local status=$?
  rm -rf "$probe_dir"
  return "$status"
}
