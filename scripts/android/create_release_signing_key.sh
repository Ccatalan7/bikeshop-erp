#!/usr/bin/env bash

set -euo pipefail
umask 077

KEY_ALIAS="${VINABIKE_ANDROID_KEY_ALIAS:-vinabike-erp}"
KEYSTORE_PATH="${VINABIKE_ANDROID_KEYSTORE_PATH:-${HOME}/Library/Application Support/Vinabike ERP/signing/android-release.jks}"
KEYCHAIN_SERVICE="Vinabike ERP Android release keystore password"
KEYCHAIN_ACCOUNT="com.vinabike.erp"
MODE="${1:---check}"

usage() {
  echo "Usage: $0 [--check|--create]" >&2
}

if [[ "$MODE" != "--check" && "$MODE" != "--create" ]]; then
  usage
  exit 64
fi

for required in keytool security openssl; do
  if ! command -v "$required" >/dev/null 2>&1; then
    echo "$required is required." >&2
    exit 127
  fi
done

if [[ "$MODE" == "--check" ]]; then
  [[ -f "$KEYSTORE_PATH" ]] || {
    echo "Android release keystore is missing at $KEYSTORE_PATH." >&2
    exit 66
  }
  password="$(
    security find-generic-password \
      -s "$KEYCHAIN_SERVICE" \
      -a "$KEYCHAIN_ACCOUNT" \
      -w 2>/dev/null
  )"
  [[ -n "$password" ]] || {
    echo "Android signing password is missing from macOS Keychain." >&2
    exit 66
  }
  VINABIKE_KEYSTORE_PASSWORD="$password" \
    keytool -list \
      -keystore "$KEYSTORE_PATH" \
      -storepass:env VINABIKE_KEYSTORE_PASSWORD \
      -alias "$KEY_ALIAS" >/dev/null
  echo "Android release signing identity is ready."
  exit 0
fi

if [[ -e "$KEYSTORE_PATH" ]]; then
  echo "Refusing to replace the existing Android release keystore." >&2
  exit 73
fi

mkdir -p "$(dirname "$KEYSTORE_PATH")"
password="$(openssl rand -base64 36 | tr -d '\n')"
[[ -n "$password" ]] || {
  echo "Could not generate the Android signing password." >&2
  exit 70
}

VINABIKE_KEYSTORE_PASSWORD="$password" \
  keytool -genkeypair \
    -keystore "$KEYSTORE_PATH" \
    -storetype JKS \
    -storepass:env VINABIKE_KEYSTORE_PASSWORD \
    -keypass:env VINABIKE_KEYSTORE_PASSWORD \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 10000 \
    -dname "CN=Vinabike ERP, OU=Software, O=Vinabike, L=Vina del Mar, ST=Valparaiso, C=CL"

security add-generic-password \
  -U \
  -s "$KEYCHAIN_SERVICE" \
  -a "$KEYCHAIN_ACCOUNT" \
  -w "$password" >/dev/null

unset password

"$0" --check
echo "Created the durable Android release key at $KEYSTORE_PATH."
echo "Back up this keystore before distributing the first APK."
