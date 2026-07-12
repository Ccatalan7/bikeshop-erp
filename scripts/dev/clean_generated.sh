#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

paths=(
  build
  .dart_tool
  .firebase
  .tmp
  tmp
  android/.gradle
  ios/Flutter/ephemeral
  macos/Flutter/ephemeral
  mobile_scanner_app/build
  mobile_scanner_app/.dart_tool
  mobile_scanner_app/android/.gradle
  mobile_scanner_app/ios/Flutter/ephemeral
  mobile_scanner_app/macos/Flutter/ephemeral
  tools/invoice-parser-service/.venv
)

printf 'The following generated paths will be removed if present:\n'
printf '  %s\n' "${paths[@]}"

if [[ "${VINABIKE_CLEAN_CONFIRM:-}" != "YES" ]]; then
  echo "No files removed. Re-run with VINABIKE_CLEAN_CONFIRM=YES after reviewing the list."
  exit 0
fi

for path in "${paths[@]}"; do
  rm -rf -- "$path"
done

echo "Generated paths removed. Source, secrets, lockfiles, and Docker volumes were not touched."
