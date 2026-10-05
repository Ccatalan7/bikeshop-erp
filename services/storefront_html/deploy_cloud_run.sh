#!/bin/bash
# Deploys the HTML storefront to Cloud Run in southamerica-east1, the region
# of the Supabase database (sa-east-1), so each page's reads stay in São Paulo.
#
# Needs the Google Cloud CLI signed in as an owner of the Firebase project
# (`gcloud auth login`, once per machine) and a billing account on it. The
# image is built by Cloud Build from a staged context: this service plus the
# shared core, nothing else from the repository.
#
# The publishable key is public by design (it ships in every page of the
# Flutter store); it is set as a plain environment variable.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT="${GCP_PROJECT:-project-vinabike}"
REGION="southamerica-east1"
SERVICE="storefront-html"
KEY="${SUPABASE_PUBLISHABLE_KEY:-$(security find-generic-password -w -s 'Vinabike ERP Supabase publishable key' -a supabase)}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "Falta la CLI de Google Cloud (gcloud)." >&2
  exit 2
fi

# The store publication checks that Cloud Run answers with the source of the
# commit it publishes; this stops on uncommitted changes in the service or
# the core.
SOURCE="$("$REPO/services/storefront_html/tool/source_id.sh")"

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/storefront-html-XXXXXX")"
cleanup() { rm -r "$STAGE"; }
trap cleanup EXIT

mkdir -p "$STAGE/packages" "$STAGE/services"
rsync -a --exclude .dart_tool --exclude build --exclude pubspec.lock \
  "$REPO/packages/vinabike_public_core" "$STAGE/packages/"
rsync -a --exclude .dart_tool --exclude build \
  "$REPO/services/storefront_html" "$STAGE/services/"
cp "$REPO/services/storefront_html/Dockerfile" "$STAGE/Dockerfile"

# min-instances 0: the owner's requirement is a free site (2026-10-04). An
# always-warm instance costs ~US$10–15 a month whether anyone visits or not;
# at zero, Cloud Run bills only while it answers, inside its monthly free
# allowance, at the price of a cold start for the first visit after a quiet
# spell. Change it only with the owner's explicit decision.
gcloud run deploy "$SERVICE" \
  --project "$PROJECT" \
  --region "$REGION" \
  --source "$STAGE" \
  --allow-unauthenticated \
  --port 8080 \
  --cpu 1 \
  --memory 512Mi \
  --concurrency 80 \
  --min-instances 0 \
  --max-instances 4 \
  --cpu-boost \
  --set-env-vars "SUPABASE_PUBLISHABLE_KEY=$KEY,STOREFRONT_SOURCE=$SOURCE" \
  --labels "app=vinabike,part=storefront-html" \
  --quiet

gcloud run services describe "$SERVICE" --project "$PROJECT" --region "$REGION" \
  --format 'value(status.url)'
echo "Fuente publicada: $SOURCE"
