#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/build_module.sh <dart_module_source> [module_name]

Examples:
  scripts/build_module.sh example/calc/lib/calc_module.dart calc
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE="$1"

if [[ -n "${2:-}" ]]; then
  NAME="$2"
else
  NAME=$(basename "$SOURCE" .dart)
fi

cd "$ROOT_DIR"
dart pub get
dart run dllart build --name "$NAME" --source "$SOURCE"
