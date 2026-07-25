#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/vinabike-supabase-cli-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT

FAKE_BIN_DIR="$TEST_TMP/bin"
FAKE_HOME="$TEST_TMP/home"
FAKE_ENV_LOG="$TEST_TMP/supabase-env.log"
FAKE_ARGS_LOG="$TEST_TMP/supabase-args.log"
FAKE_EXTERNAL_ACCESS_LOG="$TEST_TMP/external-access.log"
mkdir -p "$FAKE_BIN_DIR" "$FAKE_HOME"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] ||
    fail "Expected output to contain: $needle"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" != *"$needle"* ]] ||
    fail "Output unexpectedly contained: $needle"
}

assert_file_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -F -- "$needle" "$file" >/dev/null; then
    fail "$file unexpectedly contained: $needle"
  fi
}

for credential_consumer in \
  "$ROOT_DIR/scripts/deploy.sh" \
  "$ROOT_DIR/scripts/deploy.ps1" \
  "$ROOT_DIR/scripts/messaging/backfill_private_attachments.sh" \
  "$ROOT_DIR/scripts/sync_seo_index.sh"; do
  assert_file_not_contains "$credential_consumer" "projects api-keys"
  assert_file_not_contains "$credential_consumer" "--reveal"
done

for private_key_consumer in \
  "$ROOT_DIR/bin/backfill_product_image_fingerprints.dart" \
  "$ROOT_DIR/bin/optimize_product_images.dart" \
  "$ROOT_DIR/bin/optimize_website_images.dart" \
  "$ROOT_DIR/scripts/add_detailed_specs.py" \
  "$ROOT_DIR/scripts/bike_catalog_feeder.py" \
  "$ROOT_DIR/scripts/generate_product_seo_snapshots.dart" \
  "$ROOT_DIR/scripts/import_templates/connections/supabase_connection.py" \
  "$ROOT_DIR/scripts/ninety_nine_spokes_feeder.py" \
  "$ROOT_DIR/scripts/query_schema.py"; do
  assert_file_not_contains "$private_key_consumer" "dotenv"
  assert_file_not_contains "$private_key_consumer" "load_dotenv"
  assert_file_not_contains "$private_key_consumer" "File('.env')"
  assert_file_not_contains "$private_key_consumer" 'File(".env")'
  assert_file_not_contains "$private_key_consumer" ".env')"
  assert_file_not_contains "$private_key_consumer" '.env")'
  assert_file_not_contains "$private_key_consumer" "in .env"
  assert_file_not_contains "$private_key_consumer" "projects api-keys"
done

for modern_secret_rest_consumer in \
  "$ROOT_DIR/scripts/generate_product_seo_snapshots.dart" \
  "$ROOT_DIR/scripts/messaging/backfill_private_attachments.ts" \
  "$ROOT_DIR/scripts/query_schema.py"; do
  assert_file_not_contains "$modern_secret_rest_consumer" \
    "Authorization': 'Bearer"
  assert_file_not_contains "$modern_secret_rest_consumer" \
    'headers.set("Authorization"'
  assert_file_not_contains "$modern_secret_rest_consumer" \
    "'Authorization': f'Bearer"
done

for active_import_guide in \
  "$ROOT_DIR/scripts/import_templates/AGENT_GUIDE.md" \
  "$ROOT_DIR/scripts/zoho_import/README.md"; do
  assert_file_not_contains "$active_import_guide" "your_service_role_key"
  assert_file_not_contains "$active_import_guide" "service role key - never expires"
  assert_file_not_contains "$active_import_guide" "SUPABASE_SERVICE_ROLE_KEY"
done

assert_file_not_contains \
  "$ROOT_DIR/scripts/generate_product_seo_snapshots.dart" \
  "_readDotEnv"
assert_file_not_contains \
  "$ROOT_DIR/scripts/generate_product_seo_snapshots.dart" \
  "environment or .env"
assert_file_not_contains "$ROOT_DIR/scripts/deploy.ps1" ".env"
# The GitHub expression must remain literal while this shell test counts it.
# shellcheck disable=SC2016
secret_workflow_bindings="$(
  grep -Fc -- \
    'SUPABASE_SECRET_KEY: ${{ secrets.SUPABASE_SECRET_KEY }}' \
    "$ROOT_DIR/.github/workflows/firebase-hosting-store.yml"
)"
[[ "$secret_workflow_bindings" == 2 ]] ||
  fail "Expected exactly two explicit workflow bindings for SUPABASE_SECRET_KEY."

grep -F -- "projects api-keys" "$ROOT_DIR/scripts/db/status.sh" >/dev/null ||
  fail "Status lost its metadata-only API-key type check."
assert_file_not_contains "$ROOT_DIR/scripts/db/status.sh" "--reveal"

cat >"$FAKE_BIN_DIR/supabase" <<'FAKE_SUPABASE'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  "SUPABASE_TELEMETRY_DISABLED=${SUPABASE_TELEMETRY_DISABLED:-}" \
  "DO_NOT_TRACK=${DO_NOT_TRACK:-}" \
  "OTEL_SDK_DISABLED=${OTEL_SDK_DISABLED:-}" \
  "OTEL_TRACES_EXPORTER=${OTEL_TRACES_EXPORTER:-}" \
  "OTEL_METRICS_EXPORTER=${OTEL_METRICS_EXPORTER:-}" \
  "OTEL_LOGS_EXPORTER=${OTEL_LOGS_EXPORTER:-}" \
  >"${FAKE_ENV_LOG:?}"

if [[ -n "${FAKE_ARGS_LOG:-}" ]]; then
  printf '%s\n' "$@" >"$FAKE_ARGS_LOG"
fi

if [[ "${SUPABASE_TELEMETRY_DISABLED:-}" != 1 ||
      "${DO_NOT_TRACK:-}" != 1 ||
      "${OTEL_SDK_DISABLED:-}" != true ||
      "${OTEL_TRACES_EXPORTER:-}" != none ||
      "${OTEL_METRICS_EXPORTER:-}" != none ||
      "${OTEL_LOGS_EXPORTER:-}" != none ]]; then
  mkdir -p "$HOME/.supabase/traces"
  printf '%s\n' 'should-never-be-written' >"$HOME/.supabase/traces/fake.ndjson"
fi

case "${1:-}" in
  --version)
    printf '%s\n' "2.test"
    ;;
  status)
    exit 1
    ;;
  projects)
    case "${2:-}" in
      list)
        if [[ "${FAKE_CLI_AUTH_MODE:-ready}" == missing ]]; then
          echo "Not logged in. Supply an access token." >&2
          exit 1
        fi
        printf '%s\n' \
          '[{"ref":"xzdvtzdqjeyqxnkqprtf","status":"ACTIVE_HEALTHY"}]'
        ;;
      api-keys)
        printf '%s\n' "secret-stderr-test-value" >&2
        printf '%s\n' \
          '[{"type":"publishable","api_key":"public-test-value"},{"type":"secret","api_key":"secret-test-value"}]'
        ;;
      *)
        printf '%s\n' "unexpected projects command" >&2
        exit 64
        ;;
    esac
    ;;
  start)
    printf '%s\n' "start:ok"
    ;;
  test)
    if [[ "${2:-}" == db ]]; then
      printf '%s\n' "test-db:ok"
    else
      exit 64
    fi
    ;;
  probe)
    printf '%s\n' "probe:${2:-}"
    ;;
  *)
    printf '%s\n' "unexpected command: $*" >&2
    exit 64
    ;;
esac
FAKE_SUPABASE

cat >"$FAKE_BIN_DIR/security" <<'FAKE_SECURITY'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${FAKE_EXTERNAL_ACCESS_LOG:-}" ]]; then
  printf '%s\n' "security $*" >>"$FAKE_EXTERNAL_ACCESS_LOG"
fi

case "${FAKE_SECURITY_MODE:-ready}" in
  ready)
    exit 0
    ;;
  inaccessible)
    echo "security: SecKeychainSearchCreateFromAttributes: One or more parameters passed to a function were not valid." >&2
    echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2
    exit 44
    ;;
  missing)
    echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2
    exit 44
    ;;
  *)
    exit 70
    ;;
esac
FAKE_SECURITY

cat >"$FAKE_BIN_DIR/psql" <<'FAKE_PSQL'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "psql $*" >>"${FAKE_EXTERNAL_ACCESS_LOG:?}"
exit 99
FAKE_PSQL

chmod +x "$FAKE_BIN_DIR/supabase" "$FAKE_BIN_DIR/security" "$FAKE_BIN_DIR/psql"

assert_staging_guard_rejected() {
  local expected_status="$1"
  shift
  local output status
  rm -f "$FAKE_EXTERNAL_ACCESS_LOG"
  if output="$("$@" 2>&1)"; then
    fail "Dormant staging command unexpectedly succeeded: $*"
  else
    status=$?
  fi
  [[ "$status" -eq "$expected_status" ]] ||
    fail "Dormant staging command returned $status instead of $expected_status: $*"
  assert_contains "$output" "Staging is policy-dormant"
  [[ ! -e "$FAKE_EXTERNAL_ACCESS_LOG" ]] ||
    fail "Dormant staging command reached credential/network tooling: $*"
}

assert_staging_guard_rejected 1 \
  env -u VINABIKE_STAGING_REACTIVATION_CONFIRM \
    PATH="$FAKE_BIN_DIR:$PATH" \
    FAKE_EXTERNAL_ACCESS_LOG="$FAKE_EXTERNAL_ACCESS_LOG" \
    bash "$ROOT_DIR/scripts/db/query.sh" staging --sql "select 1"
assert_staging_guard_rejected 1 \
  env -u VINABIKE_STAGING_REACTIVATION_CONFIRM \
    PATH="$FAKE_BIN_DIR:$PATH" \
    FAKE_EXTERNAL_ACCESS_LOG="$FAKE_EXTERNAL_ACCESS_LOG" \
    VINABIKE_STAGING_SCHEMA_CONFIRM=staging \
    bash "$ROOT_DIR/scripts/db/staging_schema_gate.sh"
assert_staging_guard_rejected 64 \
  env -u VINABIKE_STAGING_REACTIVATION_CONFIRM \
    PATH="$FAKE_BIN_DIR:$PATH" \
    FAKE_EXTERNAL_ACCESS_LOG="$FAKE_EXTERNAL_ACCESS_LOG" \
    SUPABASE_STAGING_PUBLISHABLE_KEY=fake-publishable \
    E2E_PASSWORD=fake-password \
    E2E_SKIP_BUILD=1 \
    bash "$ROOT_DIR/scripts/e2e/run_staging.sh"

FAKE_REPO="$TEST_TMP/repo"
mkdir -p "$FAKE_REPO/scripts/db" "$FAKE_REPO/supabase/.temp"
cp "$ROOT_DIR/scripts/db/query.sh" "$ROOT_DIR/scripts/db/lib.sh" \
  "$FAKE_REPO/scripts/db/"
printf '%s\n' "not-production" >"$FAKE_REPO/supabase/.temp/project-ref"
rm -f "$FAKE_EXTERNAL_ACCESS_LOG"
if production_identity_output="$(
  SUPABASE_DB_PASSWORD=fake-password \
    PATH="$FAKE_BIN_DIR:$PATH" \
    FAKE_EXTERNAL_ACCESS_LOG="$FAKE_EXTERNAL_ACCESS_LOG" \
    bash "$FAKE_REPO/scripts/db/query.sh" production --sql "select 1" 2>&1
)"; then
  fail "Production read accepted an unapproved linked project identity."
fi
assert_contains "$production_identity_output" \
  "Linked project is not the approved production project"
[[ ! -e "$FAKE_EXTERNAL_ACCESS_LOG" ]] ||
  fail "Production identity mismatch reached psql."

rm -f "$FAKE_EXTERNAL_ACCESS_LOG"
if staging_identity_output="$(
  VINABIKE_STAGING_REACTIVATION_CONFIRM=bczzjhjrpmtpgwdvlbut \
    SUPABASE_STAGING_PROJECT_REF=xzdvtzdqjeyqxnkqprtf \
    SUPABASE_STAGING_DB_PASSWORD=fake-password \
    PATH="$FAKE_BIN_DIR:$PATH" \
    FAKE_EXTERNAL_ACCESS_LOG="$FAKE_EXTERNAL_ACCESS_LOG" \
    bash "$ROOT_DIR/scripts/db/query.sh" staging --sql "select 1" 2>&1
)"; then
  fail "Staging query accepted a non-staging database identity."
fi
assert_contains "$staging_identity_output" \
  "Staging connection identity does not match"
[[ ! -e "$FAKE_EXTERNAL_ACCESS_LOG" ]] ||
  fail "Staging identity mismatch reached psql."

if staging_url_output="$(
  VINABIKE_STAGING_REACTIVATION_CONFIRM=bczzjhjrpmtpgwdvlbut \
    SUPABASE_STAGING_URL=https://xzdvtzdqjeyqxnkqprtf.supabase.co \
    SUPABASE_STAGING_PUBLISHABLE_KEY=fake-publishable \
    E2E_PASSWORD=fake-password \
    E2E_SKIP_BUILD=1 \
    PATH="$FAKE_BIN_DIR:$PATH" \
    FAKE_EXTERNAL_ACCESS_LOG="$FAKE_EXTERNAL_ACCESS_LOG" \
    bash "$ROOT_DIR/scripts/e2e/run_staging.sh" 2>&1
)"; then
  fail "Staging E2E accepted a non-staging URL."
fi
assert_contains "$staging_url_output" \
  "does not identify the approved dormant staging project"

wrapper_output="$(
  HOME="$FAKE_HOME" \
    FAKE_ENV_LOG="$FAKE_ENV_LOG" \
    FAKE_ARGS_LOG="$FAKE_ARGS_LOG" \
    VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
    SUPABASE_TELEMETRY_DISABLED=0 \
    DO_NOT_TRACK=0 \
    OTEL_SDK_DISABLED=false \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_METRICS_EXPORTER=otlp \
    OTEL_LOGS_EXPORTER=otlp \
    "$ROOT_DIR/scripts/supabase_cli.sh" probe forwarded
)"
[[ "$wrapper_output" == "probe:forwarded" ]] ||
  fail "Wrapper did not forward arguments exactly."
[[ ! -e "$FAKE_HOME/.supabase/traces/fake.ndjson" ]] ||
  fail "Wrapper allowed the fake CLI to write a trace."

wrapper_environment="$(<"$FAKE_ENV_LOG")"
assert_contains "$wrapper_environment" "SUPABASE_TELEMETRY_DISABLED=1"
assert_contains "$wrapper_environment" "DO_NOT_TRACK=1"
assert_contains "$wrapper_environment" "OTEL_SDK_DISABLED=true"
assert_contains "$wrapper_environment" "OTEL_TRACES_EXPORTER=none"
assert_contains "$wrapper_environment" "OTEL_METRICS_EXPORTER=none"
assert_contains "$wrapper_environment" "OTEL_LOGS_EXPORTER=none"

metadata_output="$(
  HOME="$FAKE_HOME" \
    FAKE_ENV_LOG="$FAKE_ENV_LOG" \
    FAKE_ARGS_LOG="$FAKE_ARGS_LOG" \
    VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
    "$ROOT_DIR/scripts/supabase_cli.sh" \
      projects api-keys --project-ref xzdvtzdqjeyqxnkqprtf --output table
)"
assert_contains "$metadata_output" '"type":"publishable"'
assert_contains "$metadata_output" '"type":"secret"'
assert_not_contains "$metadata_output" "public-test-value"
assert_not_contains "$metadata_output" "secret-test-value"
assert_not_contains "$metadata_output" "secret-stderr-test-value"
grep -Fx -- "--output" "$FAKE_ARGS_LOG" >/dev/null ||
  fail "Metadata path did not force an output flag."
grep -Fx -- "json" "$FAKE_ARGS_LOG" >/dev/null ||
  fail "Metadata path did not force JSON output."
if grep -Fx -- "table" "$FAKE_ARGS_LOG" >/dev/null; then
  fail "Metadata path forwarded the caller's unsafe output format."
fi

allowed_start="$(
  HOME="$FAKE_HOME" \
    FAKE_ENV_LOG="$FAKE_ENV_LOG" \
    VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
    "$ROOT_DIR/scripts/supabase_cli.sh" start
)"
[[ "$allowed_start" == "start:ok" ]] ||
  fail "Wrapper blocked local start."

allowed_local_test="$(
  HOME="$FAKE_HOME" \
    FAKE_ENV_LOG="$FAKE_ENV_LOG" \
    VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
    "$ROOT_DIR/scripts/supabase_cli.sh" \
      test db --db-url postgresql://postgres:postgres@127.0.0.1:54322/postgres
)"
[[ "$allowed_local_test" == "test-db:ok" ]] ||
  fail "Wrapper blocked test db --db-url."

assert_wrapper_rejected() {
  local expected="$1"
  shift
  local output status
  rm -f "$FAKE_ARGS_LOG"
  if output="$(
    HOME="$FAKE_HOME" \
      FAKE_ENV_LOG="$FAKE_ENV_LOG" \
      FAKE_ARGS_LOG="$FAKE_ARGS_LOG" \
      VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
      "$ROOT_DIR/scripts/supabase_cli.sh" "$@" 2>&1
  )"; then
    fail "Unsafe wrapper invocation unexpectedly succeeded: $*"
  else
    status=$?
  fi
  [[ "$status" -eq 64 ]] ||
    fail "Unsafe wrapper invocation returned $status instead of 64: $*"
  assert_contains "$output" "$expected"
  [[ ! -e "$FAKE_ARGS_LOG" ]] ||
    fail "Unsafe wrapper invocation reached the Supabase binary: $*"
}

assert_wrapper_rejected "request metadata" --debug projects list
assert_wrapper_rejected "request metadata" projects list --log-level debug
assert_wrapper_rejected "request metadata" projects list --log-level=trace
assert_wrapper_rejected "request metadata" projects list --log-level ALL
assert_wrapper_rejected "OS credential store" \
  projects api-keys --project-ref xzdvtzdqjeyqxnkqprtf --reveal
assert_wrapper_rejected "scripts/db/query.sh" db query --sql "select 1"
assert_wrapper_rejected "scripts/db/query.sh" db --workdir . query --sql "select 1"
assert_wrapper_rejected "scripts/db/production_validation.sh" db push
assert_wrapper_rejected "scripts/db/production_validation.sh" db --workdir . push
assert_wrapper_rejected "verified migration repair" test db --linked
assert_wrapper_rejected "verified migration repair" test --workdir . db --linked
assert_wrapper_rejected "verified migration repair" test db --linked=true
assert_wrapper_rejected "verified migration repair" db reset --linked
assert_wrapper_rejected "guarded deployment" migration up --linked
assert_wrapper_rejected "guarded deployment" migration down --linked
assert_wrapper_rejected "loopback" \
  test db --db-url postgresql://postgres:secret@db.example.invalid:5432/postgres
assert_wrapper_rejected "only for pgTAP" \
  db reset --db-url postgresql://postgres:postgres@127.0.0.1:54322/postgres
assert_wrapper_rejected "VINABIKE_DB_WRITE_CONFIRM=production" \
  migration repair --linked --status applied 20260725000000
assert_wrapper_rejected "OS credential store" \
  projects --workdir . api-keys \
    --project-ref xzdvtzdqjeyqxnkqprtf --reveal
assert_wrapper_rejected "production-validation" db dump
assert_wrapper_rejected "production-validation" db --workdir . pull
assert_wrapper_rejected "scripts/db/query.sh" migration list --linked
assert_wrapper_rejected "owner-only" projects delete xzdvtzdqjeyqxnkqprtf
assert_wrapper_rejected "application-specific" storage rm --recursive path
assert_wrapper_rejected "VINABIKE_SUPABASE_STORAGE_WRITE_CONFIRM" \
  --experimental storage cp --linked local.png ss:///bucket/local.png
assert_wrapper_rejected "explicit approved --project-ref" functions list
assert_wrapper_rejected "approved repository project" \
  functions list --project-ref not-an-approved-project
assert_wrapper_rejected "policy-dormant" \
  functions list --project-ref bczzjhjrpmtpgwdvlbut
assert_wrapper_rejected "VINABIKE_SUPABASE_DESTRUCTIVE_CONFIRM" \
  functions delete old-function --project-ref xzdvtzdqjeyqxnkqprtf

status_ready="$(
  PATH="$FAKE_BIN_DIR:$PATH" \
    HOME="$FAKE_HOME" \
    FAKE_ENV_LOG="$FAKE_ENV_LOG" \
    FAKE_ARGS_LOG="$FAKE_ARGS_LOG" \
    FAKE_SECURITY_MODE=ready \
    VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
    "$ROOT_DIR/scripts/db/status.sh"
)"
assert_contains "$status_ready" "2.test (telemetry disabled)"
assert_contains "$status_ready" "credential-ready (Keychain)"
assert_contains "$status_ready" "authenticated (production accessible)"
assert_contains "$status_ready" "publishable-ready, secret-ready"
assert_not_contains "$status_ready" "public-test-value"
assert_not_contains "$status_ready" "secret-test-value"

status_inaccessible="$(
  PATH="$FAKE_BIN_DIR:$PATH" \
    HOME="$FAKE_HOME" \
    FAKE_ENV_LOG="$FAKE_ENV_LOG" \
    FAKE_ARGS_LOG="$FAKE_ARGS_LOG" \
    FAKE_SECURITY_MODE=inaccessible \
    VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
    "$ROOT_DIR/scripts/db/status.sh"
)"
assert_contains "$status_inaccessible" "inaccessible (Keychain access denied)"

status_missing="$(
  PATH="$FAKE_BIN_DIR:$PATH" \
    HOME="$FAKE_HOME" \
    FAKE_ENV_LOG="$FAKE_ENV_LOG" \
    FAKE_ARGS_LOG="$FAKE_ARGS_LOG" \
    FAKE_SECURITY_MODE=missing \
    VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
    "$ROOT_DIR/scripts/db/status.sh"
)"
assert_contains "$status_missing" "missing"
assert_not_contains "$status_missing" "inaccessible (Keychain access denied)"

status_unauthenticated="$(
  PATH="$FAKE_BIN_DIR:$PATH" \
    HOME="$FAKE_HOME" \
    FAKE_ENV_LOG="$FAKE_ENV_LOG" \
    FAKE_ARGS_LOG="$FAKE_ARGS_LOG" \
    FAKE_SECURITY_MODE=ready \
    FAKE_CLI_AUTH_MODE=missing \
    VINABIKE_SUPABASE_BIN="$FAKE_BIN_DIR/supabase" \
    "$ROOT_DIR/scripts/db/status.sh"
)"
assert_contains "$status_unauthenticated" "CLI authentication"
assert_contains "$status_unauthenticated" "missing or invalid"
assert_contains "$status_unauthenticated" "Project API keys"
assert_contains "$status_unauthenticated" "inaccessible"

echo "Supabase CLI safety tests passed."
