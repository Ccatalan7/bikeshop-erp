#!/bin/bash
# Prints which source the HTML storefront binary is built from: the git
# objects, at HEAD, of what the image compiles (the shared core's lib and
# pubspec; this service's bin, lib, pubspec, lockfile and Dockerfile). A README,
# a tool or a test does not change it. deploy_cloud_run.sh stamps it on the
# server (STOREFRONT_SOURCE) and the store publication compares it with the
# `x-storefront-source` header Cloud Run answers with
# (scripts/releases/check_storefront_html_routes.mjs).
#
# Fails when any of those paths differs from HEAD (edits or untracked files):
# the image would then hold a source this name does not describe.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
CORE=(
  packages/vinabike_public_core/lib
  packages/vinabike_public_core/pubspec.yaml
)
SERVER=(
  services/storefront_html/bin
  services/storefront_html/lib
  services/storefront_html/pubspec.yaml
  services/storefront_html/pubspec.lock
  services/storefront_html/Dockerfile
)

if [ -n "$(git -C "$REPO" status --porcelain -- "${CORE[@]}" "${SERVER[@]}")" ]; then
  echo "Hay cambios sin commit en el código del servidor HTML o del núcleo: se publica desde un commit." >&2
  git -C "$REPO" status --short -- "${CORE[@]}" "${SERVER[@]}" >&2
  exit 3
fi

objects() {
  for path in "$@"; do git -C "$REPO" rev-parse "HEAD:$path"; done |
    shasum -a 256 | cut -c1-12
}
echo "core-$(objects "${CORE[@]}").server-$(objects "${SERVER[@]}")"
