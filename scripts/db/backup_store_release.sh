#!/usr/bin/env bash
# Keeps the encrypted database backups in a draft release of this repository.
#
# Usage: backup_store_release.sh <dir with base-*.dump.cms>
#
# A draft release is visible only to people who can push to the repository,
# and every archive is also encrypted to the owner's key. Uploads each archive
# of <dir> with its .sha256 and keeps the newest BACKUP_KEEP (10: a month at
# one backup every three days). In GitHub Actions the repository and GH_TOKEN
# come from the workflow; elsewhere gh's own login is used.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly RELEASE_TAG="respaldos-base"
readonly BACKUP_KEEP="${BACKUP_KEEP:-10}"

dir="${1:-}"
[[ -d "$dir" ]] || die "Usage: backup_store_release.sh <dir with base-*.dump.cms>"
require_command gh
repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

if ! gh release view "$RELEASE_TAG" --repo "$repo" >/dev/null 2>&1; then
  gh release create "$RELEASE_TAG" --repo "$repo" --draft \
    --title "Respaldos de la base (privado)" \
    --notes "Copias cifradas de la base de producción. No publicar: un borrador sólo lo ven quienes pueden escribir en el repositorio. Cómo abrirlas: docs/runbooks/DATABASE_BACKUP_AND_RESTORE.md." \
    >/dev/null
fi

uploaded=0
for archive in "$dir"/base-*.dump.cms; do
  [[ -f "$archive" && -f "$archive.sha256" ]] || continue
  gh release upload "$RELEASE_TAG" "$archive" "$archive.sha256" --repo "$repo" --clobber
  uploaded=$((uploaded + 1))
done
((uploaded > 0)) || die "No base-*.dump.cms with its .sha256 in $dir"

kept=0
gh release view "$RELEASE_TAG" --repo "$repo" --json assets \
  --jq '.assets[].name | select(endswith(".dump.cms"))' | sort -r |
  while IFS= read -r name; do
    kept=$((kept + 1))
    ((kept > BACKUP_KEEP)) || continue
    gh release delete-asset "$RELEASE_TAG" "$name" --repo "$repo" --yes
    gh release delete-asset "$RELEASE_TAG" "$name.sha256" --repo "$repo" --yes || true
  done

echo "Uploaded $uploaded backup(s) to the draft release '$RELEASE_TAG'; keeping the newest $BACKUP_KEEP."
