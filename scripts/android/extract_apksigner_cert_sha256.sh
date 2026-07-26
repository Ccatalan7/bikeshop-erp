#!/usr/bin/env bash

set -euo pipefail

digest="$(
  sed -nE \
    -e 's/^Signer #[0-9]+ certificate SHA-256 digest: ([[:xdigit:]]{64})$/\1/p' \
    -e 's/^V[0-9]+ Signer: certificate SHA-256 digest: ([[:xdigit:]]{64})$/\1/p' |
    tr '[:upper:]' '[:lower:]' |
    sort -u
)"

if [[ ! "$digest" =~ ^[a-f0-9]{64}$ ]]; then
  echo 'Could not resolve one unambiguous APK signing certificate.' >&2
  exit 65
fi

printf '%s\n' "$digest"
