#!/usr/bin/env bash

set -euo pipefail
umask 077

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUPABASE_URL="https://xzdvtzdqjeyqxnkqprtf.supabase.co"
SUPABASE_STORAGE_URL="https://xzdvtzdqjeyqxnkqprtf.storage.supabase.co"
BUCKET="erp-mobile-releases"
TENANT_ID="5443b130-cc28-45af-a420-cd500b288890"
PACKAGE_NAME="com.vinabike.erp"
EXPECTED_SIGNER_CERT_SHA256="7e651eb2989b22a9d9262f91f0657e3a512134ac7675715fed144273ad2a897c"
KEY_ALIAS="${VINABIKE_ANDROID_KEY_ALIAS:-vinabike-erp}"
KEYSTORE_PATH="${VINABIKE_ANDROID_KEYSTORE_PATH:-${HOME}/Library/Application Support/Vinabike ERP/signing/android-release.jks}"
KEYCHAIN_SIGNING_SERVICE="Vinabike ERP Android release keystore password"
KEYCHAIN_SIGNING_ACCOUNT="com.vinabike.erp"
CHECK_ONLY=false

if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 64
fi

cd "$PROJECT_ROOT"

for required in awk base64 cat curl dd find git jq keytool security shasum sort stat tr; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "$required is required." >&2
    exit 127
  fi
done

if command -v fvm >/dev/null 2>&1; then
  FLUTTER_COMMAND=(fvm flutter)
elif [[ -x "${FLUTTER_BIN:-}" ]]; then
  FLUTTER_COMMAND=("$FLUTTER_BIN")
else
  echo "FVM or FLUTTER_BIN is required." >&2
  exit 127
fi

version_value="$(
  sed -nE 's/^version:[[:space:]]*([^[:space:]]+).*$/\1/p' pubspec.yaml |
    head -1
)"
if [[ ! "$version_value" =~ ^([^+]+)\+([0-9]+)$ ]]; then
  echo "pubspec.yaml must contain version: <name>+<positive-code>." >&2
  exit 65
fi
VERSION_NAME="${BASH_REMATCH[1]}"
VERSION_CODE="${BASH_REMATCH[2]}"
if (( VERSION_CODE <= 0 )); then
  echo "Android version code must be positive." >&2
  exit 65
fi

resolve_signing_password() {
  local value="${VINABIKE_ANDROID_STORE_PASSWORD:-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  security find-generic-password \
    -s "$KEYCHAIN_SIGNING_SERVICE" \
    -a "$KEYCHAIN_SIGNING_ACCOUNT" \
    -w 2>/dev/null
}

resolve_supabase_secret() {
  local value="${SUPABASE_SECRET_KEY:-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  security find-generic-password \
    -s "Vinabike ERP Supabase secret key" \
    -a supabase \
    -w 2>/dev/null
}

SIGNING_PASSWORD="$(resolve_signing_password)"
SUPABASE_RELEASE_SECRET="$(resolve_supabase_secret)"
[[ -f "$KEYSTORE_PATH" && -n "$SIGNING_PASSWORD" ]] || {
  echo "Android release signing identity is not ready." >&2
  exit 66
}
[[ -n "$SUPABASE_RELEASE_SECRET" ]] || {
  echo "The local Supabase maintenance credential is unavailable." >&2
  exit 66
}

ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [[ -z "$ANDROID_SDK_ROOT" && -f android/local.properties ]]; then
  ANDROID_SDK_ROOT="$(
    sed -nE 's/^sdk\.dir=(.*)$/\1/p' android/local.properties |
      head -1
  )"
fi
if [[ -z "$ANDROID_SDK_ROOT" ]]; then
  ANDROID_SDK_ROOT="${HOME}/Library/Android/sdk"
fi
APKSIGNER="$(
  find "$ANDROID_SDK_ROOT/build-tools" \
    -mindepth 2 \
    -maxdepth 2 \
    -type f \
    -name apksigner |
    sort -V |
    tail -1
)"
[[ -x "$APKSIGNER" ]] || {
  echo "Android apksigner is unavailable." >&2
  exit 127
}

VINABIKE_KEYSTORE_PASSWORD="$SIGNING_PASSWORD" \
  keytool -list \
    -keystore "$KEYSTORE_PATH" \
    -storepass:env VINABIKE_KEYSTORE_PASSWORD \
    -alias "$KEY_ALIAS" >/dev/null

if [[ "$CHECK_ONLY" == true ]]; then
  echo "Android direct-release preflight passed for ${VERSION_NAME}+${VERSION_CODE}."
  exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Refusing to publish an Android release from an uncommitted worktree." >&2
  exit 73
fi

expected_confirmation="publish-${VERSION_NAME}+${VERSION_CODE}"
if [[ "${VINABIKE_ANDROID_RELEASE_CONFIRM:-}" != "$expected_confirmation" ]]; then
  echo "Set VINABIKE_ANDROID_RELEASE_CONFIRM=$expected_confirmation for this exact release." >&2
  exit 64
fi

export VINABIKE_ANDROID_KEYSTORE_PATH="$KEYSTORE_PATH"
export VINABIKE_ANDROID_STORE_PASSWORD="$SIGNING_PASSWORD"
export VINABIKE_ANDROID_KEY_ALIAS="$KEY_ALIAS"
export VINABIKE_ANDROID_KEY_PASSWORD="$SIGNING_PASSWORD"

"${FLUTTER_COMMAND[@]}" build apk \
  --release \
  --split-per-abi \
  --build-name "$VERSION_NAME" \
  --build-number "$VERSION_CODE"

APK_PATH="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
[[ -f "$APK_PATH" ]] || {
  echo "Flutter did not produce $APK_PATH." >&2
  exit 70
}

APKSIGNER_OUTPUT="$(
  "$APKSIGNER" verify --verbose --print-certs "$APK_PATH"
)"
SIGNER_CERT_SHA256="$(
  printf '%s\n' "$APKSIGNER_OUTPUT" |
    sed -nE 's/^Signer #1 certificate SHA-256 digest: ([a-f0-9]{64})$/\1/p'
)"
if [[ "$SIGNER_CERT_SHA256" != "$EXPECTED_SIGNER_CERT_SHA256" ]]; then
  echo "The APK signer does not match the permanent Vinabike release key." >&2
  exit 74
fi

APK_SHA256="$(shasum -a 256 "$APK_PATH" | awk '{print $1}')"
APK_SIZE="$(stat -f '%z' "$APK_PATH")"
PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
GIT_COMMIT="$(git rev-parse HEAD)"
APK_NAME="vinabike-erp-${VERSION_NAME}+${VERSION_CODE}-arm64-v8a.apk"
APK_OBJECT_PATH="${TENANT_ID}/android/releases/${APK_NAME}"
VERSIONED_MANIFEST_PATH="${TENANT_ID}/android/manifests/${VERSION_NAME}+${VERSION_CODE}.json"
LATEST_MANIFEST_PATH="${TENANT_ID}/android/latest.json"
RELEASE_NOTES="${VINABIKE_ANDROID_RELEASE_NOTES:-Piloto privado de Vinabike ERP para Android.}"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vinabike-android-release.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
MANIFEST_PATH="$TEMP_DIR/android-release-manifest.json"
APK_PART_BYTES=41943040
APK_PARTS_JSON='[]'
APK_PART_FILES=()
APK_PART_OBJECT_PATHS=()
part_index=0
part_offset=0

while (( part_offset < APK_SIZE )); do
  printf -v part_suffix '%03d' "$part_index"
  part_file="$TEMP_DIR/${APK_NAME}.part${part_suffix}"
  part_object_path="${APK_OBJECT_PATH}.part${part_suffix}"
  dd \
    if="$APK_PATH" \
    of="$part_file" \
    bs="$APK_PART_BYTES" \
    skip="$part_index" \
    count=1 2>/dev/null
  part_size="$(stat -f '%z' "$part_file")"
  part_sha256="$(shasum -a 256 "$part_file" | awk '{print $1}')"
  APK_PARTS_JSON="$(
    jq \
      --arg object_path "$part_object_path" \
      --arg sha256 "$part_sha256" \
      --argjson size_bytes "$part_size" \
      '. + [{
        object_path: $object_path,
        sha256: $sha256,
        size_bytes: $size_bytes
      }]' <<< "$APK_PARTS_JSON"
  )"
  APK_PART_FILES+=("$part_file")
  APK_PART_OBJECT_PATHS+=("$part_object_path")
  part_offset=$((part_offset + part_size))
  part_index=$((part_index + 1))
done

jq -n \
  --arg package_name "$PACKAGE_NAME" \
  --arg version_name "$VERSION_NAME" \
  --argjson version_code "$VERSION_CODE" \
  --arg apk_object_path "$APK_OBJECT_PATH" \
  --arg sha256 "$APK_SHA256" \
  --argjson size_bytes "$APK_SIZE" \
  --argjson apk_parts "$APK_PARTS_JSON" \
  --arg published_at "$PUBLISHED_AT" \
  --arg release_notes "$RELEASE_NOTES" \
  --arg commit "$GIT_COMMIT" \
  '{
    schema_version: 1,
    package_name: $package_name,
    version_name: $version_name,
    version_code: $version_code,
    apk_object_path: $apk_object_path,
    sha256: $sha256,
    size_bytes: $size_bytes,
    apk_parts: $apk_parts,
    published_at: $published_at,
    release_notes: $release_notes,
    commit: $commit
  }' > "$MANIFEST_PATH"

encode_storage_path() {
  local raw="$1"
  local encoded=""
  local segment
  IFS='/' read -r -a segments <<< "$raw"
  for segment in "${segments[@]}"; do
    if [[ -n "$encoded" ]]; then
      encoded+="/"
    fi
    encoded+="$(printf '%s' "$segment" | jq -sRr @uri)"
  done
  printf '%s' "$encoded"
}

upload_object() {
  local object_path="$1"
  local file_path="$2"
  local content_type="$3"
  local upsert="$4"
  local encoded_path
  encoded_path="$(encode_storage_path "$object_path")"
  curl --fail --show-error --silent \
    -X POST \
    "${SUPABASE_URL}/storage/v1/object/${BUCKET}/${encoded_path}" \
    -H "apikey: ${SUPABASE_RELEASE_SECRET}" \
    -H "Authorization: Bearer ${SUPABASE_RELEASE_SECRET}" \
    -H "Content-Type: ${content_type}" \
    -H "x-upsert: ${upsert}" \
    --data-binary "@${file_path}" >/dev/null
}

encode_tus_metadata() {
  printf '%s' "$1" | base64 | tr -d '\r\n'
}

read_tus_header() {
  local header_name="$1"
  local headers_path="$2"
  awk -v expected="$header_name" '
    tolower($1) == tolower(expected ":") {
      gsub("\r", "", $2)
      value = $2
    }
    END { print value }
  ' "$headers_path"
}

upload_large_object() {
  local object_path="$1"
  local file_path="$2"
  local content_type="$3"
  local file_size
  local upload_url
  local current_offset
  local next_offset
  local chunk_index
  local chunk_path="$TEMP_DIR/tus-chunk"
  local create_headers="$TEMP_DIR/tus-create-headers"
  local create_body="$TEMP_DIR/tus-create-body"
  local head_headers="$TEMP_DIR/tus-head-headers"
  local patch_headers="$TEMP_DIR/tus-patch-headers"
  local patch_body="$TEMP_DIR/tus-patch-body"
  local failures=0
  local chunk_size=6291456

  file_size="$(stat -f '%z' "$file_path")"
  if ! curl --fail-with-body --show-error --silent \
    --request POST \
    "${SUPABASE_STORAGE_URL}/storage/v1/upload/resumable" \
    --header "apikey: ${SUPABASE_RELEASE_SECRET}" \
    --header "Authorization: Bearer ${SUPABASE_RELEASE_SECRET}" \
    --header "Tus-Resumable: 1.0.0" \
    --header "Upload-Length: ${file_size}" \
    --header "x-upsert: false" \
    --header "Upload-Metadata: bucketName $(encode_tus_metadata "$BUCKET"),objectName $(encode_tus_metadata "$object_path"),contentType $(encode_tus_metadata "$content_type"),cacheControl $(encode_tus_metadata "3600")" \
    --dump-header "$create_headers" \
    --output "$create_body"; then
    cat "$create_body" >&2
    return 1
  fi

  upload_url="$(read_tus_header location "$create_headers")"
  [[ -n "$upload_url" ]] || {
    echo "Supabase did not return a resumable upload URL." >&2
    return 1
  }
  if [[ "$upload_url" == /* ]]; then
    upload_url="${SUPABASE_STORAGE_URL}${upload_url}"
  fi

  while true; do
    curl --fail --show-error --silent \
      --request HEAD \
      "$upload_url" \
      --header "apikey: ${SUPABASE_RELEASE_SECRET}" \
      --header "Authorization: Bearer ${SUPABASE_RELEASE_SECRET}" \
      --header "Tus-Resumable: 1.0.0" \
      --dump-header "$head_headers" \
      --output /dev/null

    current_offset="$(read_tus_header upload-offset "$head_headers")"
    [[ "$current_offset" =~ ^[0-9]+$ ]] || {
      echo "Supabase returned an invalid resumable upload offset." >&2
      return 1
    }
    if (( current_offset == file_size )); then
      break
    fi
    if (( current_offset > file_size || current_offset % chunk_size != 0 )); then
      echo "Supabase returned an unexpected resumable upload offset." >&2
      return 1
    fi

    chunk_index=$((current_offset / chunk_size))
    dd \
      if="$file_path" \
      of="$chunk_path" \
      bs="$chunk_size" \
      skip="$chunk_index" \
      count=1 2>/dev/null

    if ! curl --fail-with-body --show-error --silent \
      --request PATCH \
      "$upload_url" \
      --header "apikey: ${SUPABASE_RELEASE_SECRET}" \
      --header "Authorization: Bearer ${SUPABASE_RELEASE_SECRET}" \
      --header "Tus-Resumable: 1.0.0" \
      --header "Upload-Offset: ${current_offset}" \
      --header "Content-Type: application/offset+octet-stream" \
      --data-binary "@${chunk_path}" \
      --dump-header "$patch_headers" \
      --output "$patch_body"; then
      failures=$((failures + 1))
      if (( failures >= 5 )); then
        cat "$patch_body" >&2
        return 1
      fi
      echo "Resuming APK upload after a transient chunk failure..." >&2
      continue
    fi

    next_offset="$(read_tus_header upload-offset "$patch_headers")"
    [[ "$next_offset" =~ ^[0-9]+$ && "$next_offset" -gt "$current_offset" ]] || {
      echo "Supabase did not advance the resumable upload offset." >&2
      return 1
    }
    printf 'APK upload: %d%%\n' "$((next_offset * 100 / file_size))"
    failures=0
  done
}

for part_array_index in "${!APK_PART_FILES[@]}"; do
  upload_large_object \
    "${APK_PART_OBJECT_PATHS[$part_array_index]}" \
    "${APK_PART_FILES[$part_array_index]}" \
    "application/vnd.android.package-archive"
done
upload_object \
  "$VERSIONED_MANIFEST_PATH" \
  "$MANIFEST_PATH" \
  "application/json" \
  "false"
upload_object \
  "$LATEST_MANIFEST_PATH" \
  "$MANIFEST_PATH" \
  "application/json" \
  "true"

ENCODED_LATEST_PATH="$(encode_storage_path "$LATEST_MANIFEST_PATH")"
curl --fail --show-error --silent \
  "${SUPABASE_URL}/storage/v1/object/authenticated/${BUCKET}/${ENCODED_LATEST_PATH}" \
  -H "apikey: ${SUPABASE_RELEASE_SECRET}" \
  -H "Authorization: Bearer ${SUPABASE_RELEASE_SECRET}" \
  > "$TEMP_DIR/latest-readback.json"

jq -e \
  --arg sha "$APK_SHA256" \
  --argjson code "$VERSION_CODE" \
  '.sha256 == $sha and .version_code == $code' \
  "$TEMP_DIR/latest-readback.json" >/dev/null

unset SIGNING_PASSWORD SUPABASE_RELEASE_SECRET
echo "Published Vinabike ERP Android ${VERSION_NAME}+${VERSION_CODE}."
echo "Private page: https://vinabike.cl/cuenta/descargas/android"
