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
MAX_ANDROID_VERSION_CODE=2100000000
KEY_ALIAS="${VINABIKE_ANDROID_KEY_ALIAS:-vinabike-erp}"
KEYSTORE_PATH="${VINABIKE_ANDROID_KEYSTORE_PATH:-${HOME}/Library/Application Support/Vinabike ERP/signing/android-release.jks}"
KEYCHAIN_SIGNING_SERVICE="Vinabike ERP Android release keystore password"
KEYCHAIN_SIGNING_ACCOUNT="com.vinabike.erp"
LATEST_MANIFEST_PATH="${TENANT_ID}/android/latest.json"
CHECK_ONLY=false
PREPARE_VERSION=false
CI_EXACT_SHA=''
RELEASE_NOTES_JSON_PATH="${VINABIKE_ANDROID_RELEASE_NOTES_PATH:-}"
RELEASE_EVIDENCE_PATH="${VINABIKE_ANDROID_RELEASE_EVIDENCE_PATH:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK_ONLY=true
      ;;
    --prepare-version)
      PREPARE_VERSION=true
      CHECK_ONLY=true
      ;;
    --ci-exact-sha)
      CI_EXACT_SHA="${2:?--ci-exact-sha requires a value}"
      shift
      ;;
    *)
      echo "Usage: $0 [--check | --prepare-version] [--ci-exact-sha <40-character-sha>]" >&2
      exit 64
      ;;
  esac
  shift
done

if [[ -n "$CI_EXACT_SHA" && "$PREPARE_VERSION" == true ]]; then
  echo '--ci-exact-sha cannot be combined with local version preparation.' >&2
  exit 64
fi
if [[ -n "$CI_EXACT_SHA" && "$CHECK_ONLY" == true ]]; then
  echo '--ci-exact-sha is a protected publication mode, not a local preflight.' >&2
  exit 64
fi

cd "$PROJECT_ROOT"

for required in \
  awk base64 cat chmod cp curl date dd dirname find git head jq keytool mktemp \
  mv perl rm sed shasum sort stat tail tr; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "$required is required." >&2
    exit 127
  fi
done

if command -v fvm >/dev/null 2>&1; then
  FLUTTER_COMMAND=(fvm flutter)
elif [[ -x "${FLUTTER_BIN:-}" ]]; then
  FLUTTER_COMMAND=("$FLUTTER_BIN")
elif [[ -n "$CI_EXACT_SHA" ]] && command -v flutter >/dev/null 2>&1; then
  FLUTTER_COMMAND=(flutter)
else
  echo "FVM or FLUTTER_BIN is required." >&2
  exit 127
fi

if [[ -n "$CI_EXACT_SHA" ]]; then
  if [[ ! "$CI_EXACT_SHA" =~ ^[0-9a-f]{40}$ ]]; then
    echo 'The CI source binding must be a full lowercase Git commit.' >&2
    exit 64
  fi
  if [[ "$(git rev-parse HEAD)" != "$CI_EXACT_SHA" ]]; then
    echo 'The checked-out source does not match the requested CI commit.' >&2
    exit 73
  fi
  if [[ -n "${GITHUB_SHA:-}" && "$GITHUB_SHA" != "$CI_EXACT_SHA" ]]; then
    echo 'The GitHub workflow source does not match the requested CI commit.' >&2
    exit 73
  fi
  if [[ -n "$(git status --porcelain)" ]]; then
    echo 'The protected Android publisher requires a clean exact-SHA checkout.' >&2
    exit 73
  fi
  if [[
    -z "${VINABIKE_ANDROID_KEYSTORE_PATH:-}" ||
    -z "${VINABIKE_ANDROID_STORE_PASSWORD:-}" ||
    -z "${VINABIKE_ANDROID_KEY_PASSWORD:-}" ||
    -z "${VINABIKE_ANDROID_KEY_ALIAS:-}" ||
    -z "${SUPABASE_RELEASE_SECRET:-}"
  ]]; then
    echo 'The protected Android publisher is missing a required Production secret.' >&2
    exit 66
  fi
fi

file_size_bytes() {
  local file_path="$1"
  local result

  if result="$(stat -f '%z' "$file_path" 2>/dev/null)"; then
    printf '%s' "$result"
  else
    stat -c '%s' "$file_path"
  fi
}

read_pubspec_version() {
  local version_value

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
  if [[ ! "$VERSION_NAME" =~ ^[0-9A-Za-z][0-9A-Za-z._-]{0,63}$ ]]; then
    echo 'Android version name contains unsupported release-path characters.' >&2
    exit 65
  fi
  if (( VERSION_CODE <= 0 || VERSION_CODE > MAX_ANDROID_VERSION_CODE )); then
    echo "Android version code must be between 1 and ${MAX_ANDROID_VERSION_CODE}." >&2
    exit 65
  fi
}

write_pubspec_version_code() {
  local next_code="$1"
  local next_version="${VERSION_NAME}+${next_code}"

  NEXT_ANDROID_VERSION="$next_version" \
    perl -0pi -e \
      's/^version:[ \t]*[^ \t\r\n]+.*$/version: $ENV{NEXT_ANDROID_VERSION}/m' \
      pubspec.yaml
  read_pubspec_version
  if [[ "$VERSION_CODE" != "$next_code" ]]; then
    echo 'Could not persist the next Android build code in pubspec.yaml.' >&2
    exit 65
  fi
}

read_pubspec_version

resolve_signing_password() {
  local value="${VINABIKE_ANDROID_STORE_PASSWORD:-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  if ! command -v security >/dev/null 2>&1; then
    return 1
  fi
  security find-generic-password \
    -s "$KEYCHAIN_SIGNING_SERVICE" \
    -a "$KEYCHAIN_SIGNING_ACCOUNT" \
    -w 2>/dev/null
}

resolve_signing_key_password() {
  local value="${VINABIKE_ANDROID_KEY_PASSWORD:-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  resolve_signing_password
}

resolve_supabase_secret() {
  local value="${SUPABASE_SECRET_KEY:-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  value="${SUPABASE_RELEASE_SECRET:-}"
  if [[ -n "$value" ]]; then
    printf '%s' "$value"
    return
  fi
  if ! command -v security >/dev/null 2>&1; then
    return 1
  fi
  security find-generic-password \
    -s "Vinabike ERP Supabase secret key" \
    -a supabase \
    -w 2>/dev/null
}

load_latest_android_release() {
  local latest_json

  if ! latest_json="$(
    curl --fail --show-error --silent \
      "${SUPABASE_URL}/storage/v1/object/authenticated/${BUCKET}/${LATEST_MANIFEST_PATH}" \
      -H "apikey: ${SUPABASE_RELEASE_SECRET}" \
      -H "Authorization: Bearer ${SUPABASE_RELEASE_SECRET}"
  )"; then
    echo 'Could not read the current private Android release manifest.' >&2
    exit 69
  fi
  if ! jq -e \
    '
      .schema_version == 1
      and (.version_name | type == "string" and length > 0)
      and (.version_code | type == "number" and . > 0 and . <= 2100000000 and floor == .)
      and (.commit | type == "string" and test("^[0-9a-f]{40}$"))
    ' >/dev/null <<< "$latest_json"; then
    echo 'The current private Android release manifest is invalid.' >&2
    exit 69
  fi

  LATEST_ANDROID_RELEASE_JSON="$latest_json"
  LATEST_ANDROID_VERSION_NAME="$(jq -r '.version_name' <<< "$latest_json")"
  LATEST_ANDROID_VERSION_CODE="$(
    jq -r '.version_code | floor' <<< "$latest_json"
  )"
  LATEST_ANDROID_COMMIT="$(jq -r '.commit' <<< "$latest_json")"
}

validate_complete_release_manifest() {
  local manifest_json="$1"
  local expected_commit="$2"

  jq -e \
    --arg tenant_id "$TENANT_ID" \
    --arg package_name "$PACKAGE_NAME" \
    --arg expected_commit "$expected_commit" \
    '
      (. | keys | sort) == [
        "apk_object_path",
        "apk_parts",
        "commit",
        "package_name",
        "published_at",
        "release_notes",
        "schema_version",
        "sha256",
        "size_bytes",
        "version_code",
        "version_name"
      ]
      and .schema_version == 1
      and .package_name == $package_name
      and (.version_name | type == "string" and length > 0 and length <= 64)
      and (.version_code | type == "number" and . > 0 and . <= 2100000000 and floor == .)
      and .commit == $expected_commit
      and (
        .apk_object_path
        | type == "string"
          and startswith($tenant_id + "/android/releases/")
          and endswith(".apk")
          and (contains("..") | not)
          and (contains("\\") | not)
      )
      and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
      and (.size_bytes | type == "number" and . > 0 and . <= 262144000 and floor == .)
      and (.apk_parts | type == "array" and length > 0 and length <= 8)
      and (
        [
          range(0; (.apk_parts | length)) as $index
          | .apk_parts[$index] as $part
          | (
              ($part | keys | sort) == ["object_path", "sha256", "size_bytes"]
              and $part.object_path
                == (.apk_object_path + ".part" + ($index | tostring | ("000" + .)[-3:]))
              and ($part.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
              and (
                $part.size_bytes
                | type == "number"
                  and . > 0
                  and . <= 41943040
                  and floor == .
              )
            )
        ]
        | all
      )
      and ([.apk_parts[].size_bytes] | add) == .size_bytes
      and (.published_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))
      and (
        (.release_notes | keys | sort) == [
          "from_commit",
          "locale",
          "modules",
          "schema_version",
          "source",
          "summary",
          "title",
          "to_commit"
        ]
        and .release_notes.schema_version == 1
        and .release_notes.locale == "es-CL"
        and (.release_notes.source == "ai" or .release_notes.source == "fallback")
        and (.release_notes.from_commit | type == "string" and test("^[0-9a-f]{40}$"))
        and .release_notes.to_commit == $expected_commit
        and (.release_notes.title | type == "string" and length > 0 and length <= 80)
        and (.release_notes.summary | type == "string" and length > 0 and length <= 280)
        and (.release_notes.modules | type == "array" and length > 0 and length <= 5)
        and (
          {
            workshop: "Taller",
            inventory: "Inventario",
            sales: "Ventas y pagos",
            purchases: "Compras",
            hr: "Personal",
            messaging: "Mensajes",
            mail: "Correo",
            website: "Sitio web",
            storage: "Archivos",
            accounting: "Contabilidad",
            settings: "Configuración",
            general: "General"
          } as $labels
          | .release_notes.modules
          | all(
              (. | keys | sort) == ["evidence_paths", "id", "items", "label"]
              and ($labels[.id] // "") == .label
              and (.items | type == "array" and length > 0 and length <= 3)
              and (.items | all(type == "string" and length > 0 and length <= 160))
              and (.evidence_paths | type == "array" and length <= 12)
              and (
                .evidence_paths
                | all(type == "string" and length > 0 and length <= 512)
              )
            )
        )
      )
    ' <<< "$manifest_json" >/dev/null
}

write_release_evidence() {
  local manifest_json="$1"
  local evidence_parent
  local temporary_evidence

  if [[ -z "$RELEASE_EVIDENCE_PATH" ]]; then
    return
  fi
  evidence_parent="$(dirname "$RELEASE_EVIDENCE_PATH")"
  [[ -d "$evidence_parent" ]] || {
    echo 'The Android release evidence directory does not exist.' >&2
    exit 70
  }
  temporary_evidence="${RELEASE_EVIDENCE_PATH}.tmp.$$"
  printf '%s\n' "$manifest_json" > "$temporary_evidence"
  chmod 600 "$temporary_evidence"
  mv -f "$temporary_evidence" "$RELEASE_EVIDENCE_PATH"
}

prepare_ci_version() {
  if [[
    "$LATEST_ANDROID_COMMIT" == "$CI_EXACT_SHA" &&
    "$LATEST_ANDROID_VERSION_NAME" == "$VERSION_NAME"
  ]]; then
    validate_complete_release_manifest \
      "$LATEST_ANDROID_RELEASE_JSON" \
      "$CI_EXACT_SHA"
    write_release_evidence "$LATEST_ANDROID_RELEASE_JSON"
    echo "Android ${LATEST_ANDROID_VERSION_NAME}+${LATEST_ANDROID_VERSION_CODE} is already published from commit $CI_EXACT_SHA."
    exit 0
  fi

  if (( VERSION_CODE <= LATEST_ANDROID_VERSION_CODE )); then
    if (( LATEST_ANDROID_VERSION_CODE >= MAX_ANDROID_VERSION_CODE )); then
      echo 'The Android version-code range is exhausted.' >&2
      exit 65
    fi
    VERSION_CODE=$((LATEST_ANDROID_VERSION_CODE + 1))
  fi
  echo "Protected Android release selected ${VERSION_NAME}+${VERSION_CODE}."
}

prepare_next_android_version() {
  local current_head
  local next_code

  current_head="$(git rev-parse HEAD)"
  if (( VERSION_CODE > LATEST_ANDROID_VERSION_CODE )); then
    echo "Android build code ${VERSION_CODE} is ready (published: ${LATEST_ANDROID_VERSION_CODE})."
    return
  fi

  if [[
    "$VERSION_CODE" == "$LATEST_ANDROID_VERSION_CODE" &&
    "$VERSION_NAME" == "$LATEST_ANDROID_VERSION_NAME" &&
    "$current_head" == "$LATEST_ANDROID_COMMIT" &&
    -z "$(git status --porcelain)"
  ]]; then
    echo "Android ${VERSION_NAME}+${VERSION_CODE} is already published from this clean commit."
    return
  fi

  if (( LATEST_ANDROID_VERSION_CODE >= MAX_ANDROID_VERSION_CODE )); then
    echo 'The Android version-code range is exhausted.' >&2
    exit 65
  fi
  next_code=$((LATEST_ANDROID_VERSION_CODE + 1))
  write_pubspec_version_code "$next_code"
  printf 'Advanced Android build code to %s+%s for the shared ERP update.\n' \
    "$VERSION_NAME" \
    "$VERSION_CODE"
}

android_release_is_already_published() {
  local release_commit="$1"

  if [[ -n "$CI_EXACT_SHA" ]]; then
    [[
      "$VERSION_NAME" == "$LATEST_ANDROID_VERSION_NAME" &&
      "$release_commit" == "$LATEST_ANDROID_COMMIT"
    ]]
    return
  fi

  [[
    "$VERSION_CODE" == "$LATEST_ANDROID_VERSION_CODE" &&
    "$VERSION_NAME" == "$LATEST_ANDROID_VERSION_NAME" &&
    "$release_commit" == "$LATEST_ANDROID_COMMIT" &&
    -z "$(git status --porcelain)"
  ]]
}

assert_android_version_is_publishable() {
  local release_commit="$1"

  if android_release_is_already_published "$release_commit"; then
    return 2
  fi
  if (( VERSION_CODE <= LATEST_ANDROID_VERSION_CODE )); then
    echo "Android build code ${VERSION_CODE} is not newer than published code ${LATEST_ANDROID_VERSION_CODE}." >&2
    echo "The next Android release requires build code $((LATEST_ANDROID_VERSION_CODE + 1))." >&2
    return 1
  fi
  return 0
}

SIGNING_PASSWORD="$(resolve_signing_password || true)"
SIGNING_KEY_PASSWORD="$(resolve_signing_key_password || true)"
SUPABASE_RELEASE_SECRET="$(resolve_supabase_secret || true)"
[[ -f "$KEYSTORE_PATH" && -n "$SIGNING_PASSWORD" ]] || {
  echo "Android release signing identity is not ready." >&2
  exit 66
}
[[ -n "$SIGNING_KEY_PASSWORD" ]] || {
  echo "The Android release key password is unavailable." >&2
  exit 66
}
[[ -n "$SUPABASE_RELEASE_SECRET" ]] || {
  echo "The Supabase release credential is unavailable." >&2
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

load_latest_android_release

if [[ -n "$CI_EXACT_SHA" ]]; then
  prepare_ci_version
fi

if [[ "$PREPARE_VERSION" == true ]]; then
  "${FLUTTER_COMMAND[@]}" pub get
  read_pubspec_version
  prepare_next_android_version
  echo "Android shared-release preflight passed for ${VERSION_NAME}+${VERSION_CODE}."
  exit 0
fi

release_commit="$(git rev-parse HEAD)"
if [[ -z "$CI_EXACT_SHA" && "$CHECK_ONLY" == false && -n "$(git status --porcelain)" ]]; then
  echo "Refusing to publish an Android release from an uncommitted worktree." >&2
  exit 73
fi

version_status=0
assert_android_version_is_publishable "$release_commit" || version_status=$?
if (( version_status == 2 )); then
  echo "Android ${VERSION_NAME}+${VERSION_CODE} is already published from commit $release_commit."
  exit 0
fi
if (( version_status != 0 )); then
  exit "$version_status"
fi

if [[ "$CHECK_ONLY" == true ]]; then
  echo "Android direct-release preflight passed for ${VERSION_NAME}+${VERSION_CODE}."
  exit 0
fi

if [[ -z "$CI_EXACT_SHA" ]]; then
  expected_confirmation="publish-${VERSION_NAME}+${VERSION_CODE}"
  if [[ "${VINABIKE_ANDROID_RELEASE_CONFIRM:-}" != "$expected_confirmation" ]]; then
    echo "Set VINABIKE_ANDROID_RELEASE_CONFIRM=$expected_confirmation for this exact release." >&2
    exit 64
  fi
fi

export VINABIKE_ANDROID_KEYSTORE_PATH="$KEYSTORE_PATH"
export VINABIKE_ANDROID_STORE_PASSWORD="$SIGNING_PASSWORD"
export VINABIKE_ANDROID_KEY_ALIAS="$KEY_ALIAS"
export VINABIKE_ANDROID_KEY_PASSWORD="$SIGNING_KEY_PASSWORD"

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
APK_SIZE="$(file_size_bytes "$APK_PATH")"
if (( APK_SIZE <= 0 || APK_SIZE > 262144000 )); then
  echo 'The Android release APK is outside the supported size boundary.' >&2
  exit 70
fi
PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
GIT_COMMIT="$release_commit"
APK_NAME="vinabike-erp-${VERSION_NAME}+${VERSION_CODE}-arm64-v8a.apk"
APK_OBJECT_PATH="${TENANT_ID}/android/releases/${APK_NAME}"
VERSIONED_MANIFEST_PATH="${TENANT_ID}/android/manifests/${VERSION_NAME}+${VERSION_CODE}.json"
RELEASE_NOTES="${VINABIKE_ANDROID_RELEASE_NOTES:-Piloto privado de Vinabike ERP para Android.}"
RELEASE_NOTES_JSON=''

if [[ -n "$RELEASE_NOTES_JSON_PATH" ]]; then
  [[ -f "$RELEASE_NOTES_JSON_PATH" ]] || {
    echo 'The prepared Android release notes are unavailable.' >&2
    exit 65
  }
  if (( $(file_size_bytes "$RELEASE_NOTES_JSON_PATH") > 65536 )); then
    echo 'The prepared Android release notes exceed the allowed size.' >&2
    exit 65
  fi
  jq -e \
    --arg head "$GIT_COMMIT" \
    '
      (. | keys | sort) == ["release_notes"]
      and (.release_notes | keys | sort) == [
        "from_commit",
        "locale",
        "modules",
        "schema_version",
        "source",
        "summary",
        "title",
        "to_commit"
      ]
      and .release_notes.schema_version == 1
      and .release_notes.locale == "es-CL"
      and (.release_notes.source == "ai" or .release_notes.source == "fallback")
      and (.release_notes.from_commit | type == "string" and test("^[0-9a-f]{40}$"))
      and .release_notes.to_commit == $head
      and (.release_notes.title | type == "string" and length > 0 and length <= 80)
      and (.release_notes.summary | type == "string" and length > 0 and length <= 280)
      and (.release_notes.modules | type == "array" and length > 0 and length <= 5)
      and (
        {
          workshop: "Taller",
          inventory: "Inventario",
          sales: "Ventas y pagos",
          purchases: "Compras",
          hr: "Personal",
          messaging: "Mensajes",
          mail: "Correo",
          website: "Sitio web",
          storage: "Archivos",
          accounting: "Contabilidad",
          settings: "Configuración",
          general: "General"
        } as $labels
        | .release_notes.modules
        | all(
            (. | keys | sort) == ["evidence_paths", "id", "items", "label"]
            and ($labels[.id] // "") == .label
            and (.items | type == "array" and length > 0 and length <= 3)
            and (.items | all(type == "string" and length > 0 and length <= 160))
            and (.evidence_paths | type == "array" and length <= 12)
            and (
              .evidence_paths
              | all(type == "string" and length > 0 and length <= 512)
            )
          )
      )
    ' "$RELEASE_NOTES_JSON_PATH" >/dev/null || {
      echo 'The prepared Android release notes are invalid.' >&2
      exit 65
    }
  RELEASE_NOTES_JSON="$(
    jq -c '.release_notes' "$RELEASE_NOTES_JSON_PATH"
  )"
elif [[ -n "$CI_EXACT_SHA" ]]; then
  echo 'Protected Android publication requires exact-SHA structured release notes.' >&2
  exit 65
else
  RELEASE_NOTES_JSON="$(jq -cn --arg release_notes "$RELEASE_NOTES" '$release_notes')"
fi

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
  part_size="$(file_size_bytes "$part_file")"
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
  --argjson release_notes "$RELEASE_NOTES_JSON" \
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

download_private_object_if_present() {
  local object_path="$1"
  local destination="$2"
  local encoded_path
  local http_status

  encoded_path="$(encode_storage_path "$object_path")"
  http_status="$(
    curl --show-error --silent \
      --output "$destination" \
      --write-out '%{http_code}' \
      "${SUPABASE_URL}/storage/v1/object/authenticated/${BUCKET}/${encoded_path}" \
      -H "apikey: ${SUPABASE_RELEASE_SECRET}" \
      -H "Authorization: Bearer ${SUPABASE_RELEASE_SECRET}"
  )"
  case "$http_status" in
    200)
      return 0
      ;;
    404)
      rm -f "$destination"
      return 1
      ;;
    *)
      rm -f "$destination"
      echo "Could not inspect an existing Android release object (HTTP ${http_status})." >&2
      return 2
      ;;
  esac
}

remote_object_matches_file() {
  local object_path="$1"
  local file_path="$2"
  local remote_file="$TEMP_DIR/remote-object"
  local download_status=0

  download_private_object_if_present \
    "$object_path" \
    "$remote_file" || download_status=$?
  if (( download_status == 1 )); then
    return 1
  fi
  if (( download_status != 0 )); then
    return "$download_status"
  fi
  if [[
    "$(file_size_bytes "$remote_file")" != "$(file_size_bytes "$file_path")" ||
    "$(shasum -a 256 "$remote_file" | awk '{print $1}')" != "$(shasum -a 256 "$file_path" | awk '{print $1}')"
  ]]; then
    echo 'An immutable Android release object already exists with different content.' >&2
    return 2
  fi
  rm -f "$remote_file"
  return 0
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

  file_size="$(file_size_bytes "$file_path")"
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

load_latest_android_release
version_status=0
assert_android_version_is_publishable "$GIT_COMMIT" || version_status=$?
if (( version_status == 2 )); then
  if [[ -n "$CI_EXACT_SHA" ]]; then
    validate_complete_release_manifest \
      "$LATEST_ANDROID_RELEASE_JSON" \
      "$GIT_COMMIT"
    write_release_evidence "$LATEST_ANDROID_RELEASE_JSON"
  fi
  echo "Android ${VERSION_NAME}+${VERSION_CODE} was published while this APK was building."
  exit 0
fi
if (( version_status != 0 )); then
  exit "$version_status"
fi

for part_array_index in "${!APK_PART_FILES[@]}"; do
  existing_part_status=0
  remote_object_matches_file \
    "${APK_PART_OBJECT_PATHS[$part_array_index]}" \
    "${APK_PART_FILES[$part_array_index]}" || existing_part_status=$?
  case "$existing_part_status" in
    0)
      printf 'Reusing verified Android APK part %d.\n' "$part_array_index"
      ;;
    1)
      upload_large_object \
        "${APK_PART_OBJECT_PATHS[$part_array_index]}" \
        "${APK_PART_FILES[$part_array_index]}" \
        "application/vnd.android.package-archive"
      ;;
    *)
      exit "$existing_part_status"
      ;;
  esac
done

existing_manifest_path="$TEMP_DIR/existing-versioned-manifest.json"
existing_manifest_status=0
download_private_object_if_present \
  "$VERSIONED_MANIFEST_PATH" \
  "$existing_manifest_path" || existing_manifest_status=$?
case "$existing_manifest_status" in
  0)
    jq -e \
      --arg package_name "$PACKAGE_NAME" \
      --arg version_name "$VERSION_NAME" \
      --arg sha "$APK_SHA256" \
      --argjson code "$VERSION_CODE" \
      --arg commit "$GIT_COMMIT" \
      --arg apk_object_path "$APK_OBJECT_PATH" \
      --argjson size_bytes "$APK_SIZE" \
      --argjson apk_parts "$APK_PARTS_JSON" \
      '
        .schema_version == 1
        and .package_name == $package_name
        and .version_name == $version_name
        and .version_code == $code
        and .commit == $commit
        and .apk_object_path == $apk_object_path
        and .sha256 == $sha
        and .size_bytes == $size_bytes
        and .apk_parts == $apk_parts
        and (.published_at | type == "string" and length > 0)
      ' "$existing_manifest_path" >/dev/null || {
        echo 'The immutable Android version manifest already exists with different content.' >&2
        exit 74
      }
    if [[ -n "$CI_EXACT_SHA" ]]; then
      existing_manifest_json="$(cat "$existing_manifest_path")"
      validate_complete_release_manifest \
        "$existing_manifest_json" \
        "$GIT_COMMIT"
      RELEASE_NOTES_JSON="$(
        jq -c '.release_notes' "$existing_manifest_path"
      )"
    elif ! jq -e \
      --argjson release_notes "$RELEASE_NOTES_JSON" \
      '.release_notes == $release_notes' \
      "$existing_manifest_path" >/dev/null; then
      echo 'The immutable Android version manifest has different release notes.' >&2
      exit 74
    fi
    cp "$existing_manifest_path" "$MANIFEST_PATH"
    echo 'Reusing the verified immutable Android version manifest.'
    ;;
  1)
    upload_object \
      "$VERSIONED_MANIFEST_PATH" \
      "$MANIFEST_PATH" \
      "application/json" \
      "false"
    ;;
  *)
    exit "$existing_manifest_status"
    ;;
esac

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
  --arg package_name "$PACKAGE_NAME" \
  --arg version_name "$VERSION_NAME" \
  --arg sha "$APK_SHA256" \
  --argjson code "$VERSION_CODE" \
  --arg commit "$GIT_COMMIT" \
  --arg apk_object_path "$APK_OBJECT_PATH" \
  --argjson size_bytes "$APK_SIZE" \
  --argjson apk_parts "$APK_PARTS_JSON" \
  --argjson release_notes "$RELEASE_NOTES_JSON" \
  '
    .schema_version == 1
    and .package_name == $package_name
    and .version_name == $version_name
    and .version_code == $code
    and .commit == $commit
    and .apk_object_path == $apk_object_path
    and .sha256 == $sha
    and .size_bytes == $size_bytes
    and .apk_parts == $apk_parts
    and .release_notes == $release_notes
  ' \
  "$TEMP_DIR/latest-readback.json" >/dev/null

LATEST_ANDROID_RELEASE_JSON="$(cat "$TEMP_DIR/latest-readback.json")"
if [[ -n "$CI_EXACT_SHA" ]]; then
  validate_complete_release_manifest "$LATEST_ANDROID_RELEASE_JSON" "$GIT_COMMIT"
  write_release_evidence "$LATEST_ANDROID_RELEASE_JSON"
fi

unset SIGNING_PASSWORD SIGNING_KEY_PASSWORD SUPABASE_RELEASE_SECRET
echo "Published Vinabike ERP Android ${VERSION_NAME}+${VERSION_CODE}."
echo "Private page: https://vinabike.cl/cuenta/descargas/android"
