#!/usr/bin/env bash
# Keeps the newest Android releases in Storage and deletes the older ones.
#
# Usage: scripts/android/prune_direct_releases.sh [--keep N] [--apply]
#
# A release is an APK in 40 MB parts (~103 MB) under
# <tenant>/android/releases/. On 2026-11-01 the 115 APKs published since July
# were 11 GB of a bucket the free plan caps at 1 GB, and nothing downloads an
# old one: the app and the staff download page read latest.json. The APKs of
# the newest N builds stay (3 by default: the current one and two to go back
# to), and so does whatever latest.json names. The versioned manifests under
# <tenant>/android/manifests/, a couple of kB each, all stay: they are the
# release ledger (docs/ANDROID_DIRECT_DISTRIBUTION.md, Rollback). Without
# --apply it only prints what it would delete. A name it does not recognise
# is never deleted, and nothing is deleted when latest.json cannot be read.
# publish_direct_release.sh runs it after every published release.

set -euo pipefail
umask 077

SUPABASE_URL="https://xzdvtzdqjeyqxnkqprtf.supabase.co"
BUCKET="erp-mobile-releases"
TENANT_ID="5443b130-cc28-45af-a420-cd500b288890"
KEEP=3
APPLY=false

usage() {
  echo 'Usage: scripts/android/prune_direct_releases.sh [--keep N] [--apply]' >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)
      KEEP="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY=true
      shift
      ;;
    *) usage ;;
  esac
done
[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || usage
for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing $tool." >&2
    exit 127
  }
done

secret="${SUPABASE_SECRET_KEY:-${SUPABASE_RELEASE_SECRET:-}}"
if [[ -z "$secret" ]] && command -v security >/dev/null 2>&1; then
  secret="$(security find-generic-password -s 'Vinabike ERP Supabase secret key' \
    -a supabase -w 2>/dev/null || true)"
fi
[[ -n "$secret" ]] || {
  echo 'No Supabase secret key (SUPABASE_SECRET_KEY, SUPABASE_RELEASE_SECRET or the Keychain).' >&2
  exit 78
}

work="$(mktemp -d)"
cleanup() {
  rm -f "$work"/*.json "$work"/*.ndjson
  rmdir "$work" 2>/dev/null || true
}
trap cleanup EXIT

storage() {
  local method="$1" path="$2" body="${3:-}"
  local args=(--fail-with-body --silent --show-error --retry 3 --retry-delay 2
    -X "$method" "$SUPABASE_URL/storage/v1/$path"
    -H "apikey: $secret" -H "Authorization: Bearer $secret")
  if [[ -n "$body" ]]; then
    args+=(-H 'Content-Type: application/json' --data "$body")
  fi
  curl "${args[@]}"
}

# Every object under a folder, with its full name and size.
list_objects() {
  local prefix="$1" offset=0 page
  : >"$work/list.ndjson"
  while :; do
    page="$(storage POST "object/list/$BUCKET" "$(jq -nc --arg p "$prefix" --argjson o "$offset" \
      '{prefix: $p, limit: 1000, offset: $o, sortBy: {column: "name", order: "asc"}}')")"
    jq -c --arg p "$prefix" '.[] | select(.id != null)
      | {name: ($p + .name), size: (.metadata.size // 0)}' <<<"$page" >>"$work/list.ndjson"
    (($(jq 'length' <<<"$page") < 1000)) && break
    offset=$((offset + 1000))
  done
  jq -sc '.' "$work/list.ndjson"
}

storage GET "object/authenticated/$BUCKET/$TENANT_ID/android/latest.json" >"$work/latest.json" || {
  echo 'latest.json could not be read; nothing is deleted.' >&2
  exit 69
}
current="$(jq -er '.apk_object_path
  | capture("/vinabike-erp-(?<k>[0-9.]+\\+[0-9]+)-arm64-v8a\\.apk$").k' "$work/latest.json")" || {
  echo 'latest.json names no APK; nothing is deleted.' >&2
  exit 65
}

plan() {
  jq -n \
    --argjson releases "$(list_objects "$TENANT_ID/android/releases/")" \
    --arg current "$current" \
    --argjson keep "$KEEP" '
    def apk: (.name | capture("/vinabike-erp-(?<k>[0-9.]+\\+(?<b>[0-9]+))-arm64-v8a\\.apk(\\.part[0-9]{3})?$")) // {};
    [$releases[] | . + apk] as $all
    | ([$all[] | select(.k) | {k, b: (.b | tonumber)}]
        | unique_by(.k) | sort_by(-.b) | .[:$keep] | map(.k)) + [$current] | unique as $kept
    | {
        kept: $kept,
        delete: [$all[] | select(.k) | select(.k as $k | $kept | any(. == $k) | not) | {name, size}],
        unknown: [$all[] | select(.k | not) | .name],
        objects: ($all | length)
      }'
}

before="$(plan)"
jq -r '"Objects: \(.objects). Kept: \(.kept | join(", ")).",
  "To delete: \(.delete | length) objects, \((.delete | map(.size) | add // 0) / 1048576 | floor) MB.",
  (if (.unknown | length) > 0 then "Not recognised, kept: \(.unknown | join(", "))" else empty end)' <<<"$before"

if [[ "$APPLY" != true ]]; then
  echo 'Dry run: pass --apply to delete.'
  exit 0
fi

deleted=0
while IFS= read -r batch; do
  storage DELETE "object/$BUCKET" "$(jq -nc --argjson p "$batch" '{prefixes: $p}')" >"$work/deleted.json"
  deleted=$((deleted + $(jq 'length' "$work/deleted.json")))
done < <(jq -c '.delete | map(.name) | [range(0; length; 100) as $i | .[$i:$i + 100]] | .[]' <<<"$before")

# Read back: nothing of what was deleted remains, and every part latest.json
# names is still there.
after="$(plan)"
leftover="$(jq '.delete | length' <<<"$after")"
missing="$(jq -n --slurpfile latest "$work/latest.json" --argjson a "$(list_objects "$TENANT_ID/android/releases/")" \
  '[$latest[0].apk_parts[].object_path] - [$a[].name] | length')"
echo "Deleted $deleted objects; $(jq '.objects' <<<"$after") remain."
if ((leftover > 0 || missing > 0)); then
  echo "Read-back failed: $leftover objects still to delete, $missing parts of the current release missing." >&2
  exit 70
fi
