#!/bin/bash

set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <tag-prefix> <manifest-name> <head-commit>" >&2
  exit 64
fi

readonly TAG_PREFIX="$1"
readonly MANIFEST_NAME="$2"
readonly HEAD_COMMIT="$3"
readonly REPOSITORY="${GH_REPO:?GH_REPO is required}"

if [[ ! "$TAG_PREFIX" =~ ^[0-9A-Za-z._-]+$ ]]; then
  echo "Invalid release tag prefix: $TAG_PREFIX" >&2
  exit 64
fi
if [[ ! "$MANIFEST_NAME" =~ ^[0-9A-Za-z._-]+\.json$ ]]; then
  echo "Invalid release manifest name: $MANIFEST_NAME" >&2
  exit 64
fi
if [[ ! "$HEAD_COMMIT" =~ ^[0-9a-f]{40}$ ]] ||
   ! git cat-file -e "${HEAD_COMMIT}^{commit}" 2>/dev/null; then
  echo "Invalid or unavailable release head commit: $HEAD_COMMIT" >&2
  exit 64
fi

work_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/vinabike-release-base.XXXXXX")"
cleanup() {
  rm -rf -- "$work_root"
}
trap cleanup EXIT

candidate_root="${work_root}/candidate"
mkdir -p "$candidate_root"

while IFS=$'\t' read -r release_tag release_target; do
  [[ "$release_tag" == "${TAG_PREFIX}"* ]] || continue
  [[ "$release_target" =~ ^[0-9a-f]{40}$ ]] || continue

  candidate_manifest="${candidate_root}/${MANIFEST_NAME}"
  rm -f -- "$candidate_manifest"
  if ! gh release download "$release_tag" \
    --repo "$REPOSITORY" \
    --pattern "$MANIFEST_NAME" \
    --dir "$candidate_root" \
    --clobber >/dev/null 2>&1; then
    continue
  fi

  candidate_manifest_tag="$(
    jq -r '.tag_name // empty' "$candidate_manifest" 2>/dev/null || true
  )"
  candidate_commit="$(jq -r '.commit // empty' "$candidate_manifest" 2>/dev/null || true)"
  if [[ -n "$candidate_manifest_tag" ]] &&
     [[ "$candidate_manifest_tag" != "$release_tag" ]]; then
    continue
  fi
  if [[ ! "$candidate_commit" =~ ^[0-9a-f]{40}$ ]] ||
     [[ "$candidate_commit" == "$HEAD_COMMIT" ]] ||
     [[ "$candidate_commit" != "$release_target" ]]; then
    continue
  fi

  if ! git cat-file -e "${candidate_commit}^{commit}" 2>/dev/null; then
    git fetch --no-tags origin "$candidate_commit" >/dev/null 2>&1 || continue
  fi
  if ! git merge-base --is-ancestor "$candidate_commit" "$HEAD_COMMIT"; then
    continue
  fi

  printf '%s\n' "$candidate_commit"
  exit 0
done < <(
  gh api --paginate "repos/${REPOSITORY}/releases?per_page=100" \
    --jq \
    '.[] | select(.draft == false) | [.tag_name, .target_commitish] | @tsv'
)

fallback_commit="$(git rev-parse "${HEAD_COMMIT}^" 2>/dev/null || true)"
if [[ ! "$fallback_commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Could not resolve a previous release or parent commit for $HEAD_COMMIT." >&2
  exit 1
fi

echo "No prior ${TAG_PREFIX} manifest applies; using the release head parent." >&2
printf '%s\n' "$fallback_commit"
