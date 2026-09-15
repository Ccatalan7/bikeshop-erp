#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/vinabike-migration-workflow-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] ||
    fail "Expected output to contain: $needle"
}

FAKE_REPO="$TEST_TMP/repo"
FAKE_LOG="$TEST_TMP/workflow.log"
FAKE_STAMP_DIR="$TEST_TMP/stamps"
FAKE_BIN_DIR="$TEST_TMP/bin"
mkdir -p "$FAKE_REPO/scripts/db" "$FAKE_REPO/supabase/migrations" \
  "$FAKE_REPO/supabase/.temp" "$FAKE_REPO/supabase/sql" \
  "$FAKE_STAMP_DIR" "$FAKE_BIN_DIR"

cp "$ROOT_DIR/scripts/db/lib.sh" \
  "$ROOT_DIR/scripts/db/migration_status.sh" \
  "$ROOT_DIR/scripts/db/deploy_migration.sh" \
  "$FAKE_REPO/scripts/db/"
# Keep the literal shell expression in the copied fixture.
# shellcheck disable=SC2016
sed -i.bak 's#export PATH="/opt/homebrew/opt/libpq/bin:$PATH"#export PATH="$PATH"#' \
  "$FAKE_REPO/scripts/db/lib.sh"

cat >"$FAKE_BIN_DIR/psql" <<'FAKE_PSQL'
#!/usr/bin/env bash
printf 'UNEXPECTED_PSQL\n' >>"${FAKE_LOG:?}"
exit 99
FAKE_PSQL
chmod +x "$FAKE_BIN_DIR/psql"

# The low-level guarded query path must reject the historical reference before
# credentials or psql, even if a caller explicitly asks for a hosted write.
cp "$ROOT_DIR/scripts/db/query.sh" "$ROOT_DIR/scripts/db/sensitive_tables.txt" \
  "$FAKE_REPO/scripts/db/"
printf 'xzdvtzdqjeyqxnkqprtf\n' >"$FAKE_REPO/supabase/.temp/project-ref"
printf 'select 1;\n' >"$FAKE_REPO/supabase/sql/core_schema.sql"
if core_guard_output="$(
  cd "$FAKE_REPO"
  VINABIKE_DB_WRITE_CONFIRM=production \
    FAKE_LOG="$FAKE_LOG" \
    PATH="$FAKE_BIN_DIR:$PATH" \
    scripts/db/query.sh production --write \
      --file supabase/sql/core_schema.sql 2>&1
)"; then
  fail "Hosted query path accepted core_schema.sql."
fi
assert_contains "$core_guard_output" "core_schema.sql is a historical local reference"
[[ ! -f "$FAKE_LOG" ]] ||
  fail "Hosted core_schema.sql guard reached an external database command."

printf 'begin; select 1; commit;\n' \
  >"$FAKE_REPO/supabase/migrations/20260817010101_probe.sql"
if direct_migration_output="$(
  cd "$FAKE_REPO"
  VINABIKE_DB_WRITE_CONFIRM=production \
    FAKE_LOG="$FAKE_LOG" \
    PATH="$FAKE_BIN_DIR:$PATH" \
    scripts/db/query.sh production --write \
      --file supabase/migrations/20260817010101_probe.sql 2>&1
)"; then
  fail "Low-level query path accepted a hosted migration without the coordinator."
fi
assert_contains "$direct_migration_output" \
  "Direct hosted migration execution is forbidden"
[[ ! -f "$FAKE_LOG" ]] ||
  fail "Direct migration guard reached an external database command."

if retired_gate_output="$(
  VINABIKE_STAGING_REACTIVATION_CONFIRM=bczzjhjrpmtpgwdvlbut \
    FAKE_LOG="$FAKE_LOG" \
    PATH="$FAKE_BIN_DIR:$PATH" \
    bash "$ROOT_DIR/scripts/db/staging_schema_gate.sh" 2>&1
)"; then
  fail "Retired hosted core-schema gate unexpectedly succeeded."
fi
assert_contains "$retired_gate_output" "never applied to a hosted database"
[[ ! -f "$FAKE_LOG" ]] ||
  fail "Retired hosted core-schema gate reached an external database command."

cat >"$FAKE_REPO/scripts/db/query.sh" <<'FAKE_QUERY'
#!/usr/bin/env bash
set -euo pipefail

format=table
sql=""
file=""
write=false
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --format) format="$2"; shift 2 ;;
    --sql) sql="$2"; shift 2 ;;
    --file) file="$2"; shift 2 ;;
    --write) write=true; shift ;;
    *) shift ;;
  esac
done

if [[ "$write" == true ]]; then
  printf 'WRITE %s\n' "$(basename "$file")" >>"${FAKE_LOG:?}"
  exit 0
fi

if [[ -n "$file" ]]; then
  printf 'VERIFY %s\n' "$(basename "$file")" >>"${FAKE_LOG:?}"
  [[ "$(basename "$file")" != fail-verification.sql ]] || exit 42
  printf 'verification_passed\n'
  exit 0
fi

version="$(printf '%s' "$sql" | grep -Eo '[0-9]{14}' | head -n 1)"
status=NOT_APPLIED
[[ ! -f "${FAKE_STAMP_DIR:?}/$version" ]] || status=APPLIED
printf 'STATUS %s %s\n' "$version" "$status" >>"${FAKE_LOG:?}"
if [[ "$format" == csv ]]; then
  printf 'production_status\n%s\n' "$status"
else
  printf 'filename | version | production_status\nprobe | %s | %s\n' \
    "$version" "$status"
fi
FAKE_QUERY

cat >"$FAKE_REPO/scripts/supabase_cli.sh" <<'FAKE_CLI'
#!/usr/bin/env bash
set -euo pipefail
version="${*: -1}"
printf 'STAMP %s\n' "$version" >>"${FAKE_LOG:?}"
touch "${FAKE_STAMP_DIR:?}/$version"
FAKE_CLI
chmod +x "$FAKE_REPO/scripts/db/"*.sh "$FAKE_REPO/scripts/supabase_cli.sh"

printf 'begin; select 1; commit;\n' \
  >"$FAKE_REPO/supabase/migrations/20260817010101_probe.sql"
printf 'select 1 as verified;\n' >"$TEST_TMP/verification.sql"

status_before="$(
  cd "$FAKE_REPO"
  FAKE_LOG="$FAKE_LOG" FAKE_STAMP_DIR="$FAKE_STAMP_DIR" \
    scripts/db/migration_status.sh \
      supabase/migrations/20260817010101_probe.sql
)"
assert_contains "$status_before" "NOT_APPLIED"

deploy_output="$(
  cd "$FAKE_REPO"
  VINABIKE_DB_WRITE_CONFIRM=production \
    FAKE_LOG="$FAKE_LOG" \
    FAKE_STAMP_DIR="$FAKE_STAMP_DIR" \
    scripts/db/deploy_migration.sh \
      --migration supabase/migrations/20260817010101_probe.sql \
      --verify "$TEST_TMP/verification.sql"
)"
assert_contains "$deploy_output" "is APPLIED and verified"
[[ -f "$FAKE_REPO/.tmp/db/migration-receipts/20260817010101.receipt" ]] ||
  fail "Successful deployment did not create its local receipt."
grep -Fx 'WRITE 20260817010101_probe.sql' "$FAKE_LOG" >/dev/null ||
  fail "Standalone migration was not applied."
grep -Fx 'VERIFY verification.sql' "$FAKE_LOG" >/dev/null ||
  fail "Verification file was not executed."
grep -Fx 'STAMP 20260817010101' "$FAKE_LOG" >/dev/null ||
  fail "Exact migration version was not stamped."

status_after="$(
  cd "$FAKE_REPO"
  FAKE_LOG="$FAKE_LOG" FAKE_STAMP_DIR="$FAKE_STAMP_DIR" \
    scripts/db/migration_status.sh \
      supabase/migrations/20260817010101_probe.sql
)"
assert_contains "$status_after" "APPLIED"

if rerun_output="$(
  cd "$FAKE_REPO"
  VINABIKE_DB_WRITE_CONFIRM=production \
    FAKE_LOG="$FAKE_LOG" \
    FAKE_STAMP_DIR="$FAKE_STAMP_DIR" \
    scripts/db/deploy_migration.sh \
      --migration supabase/migrations/20260817010101_probe.sql \
      --verify "$TEST_TMP/verification.sql" 2>&1
)"; then
  fail "An already stamped migration was rerun."
fi
assert_contains "$rerun_output" "already stamped APPLIED"
[[ "$(grep -Fc 'WRITE 20260817010101_probe.sql' "$FAKE_LOG")" == 1 ]] ||
  fail "An applied migration reached the write path more than once."

printf 'begin; select 2; commit;\n' \
  >"$FAKE_REPO/supabase/migrations/20260817010202_verify_failure.sql"
printf 'select 1;\n' >"$TEST_TMP/fail-verification.sql"
if failed_verify_output="$(
  cd "$FAKE_REPO"
  VINABIKE_DB_WRITE_CONFIRM=production \
    FAKE_LOG="$FAKE_LOG" \
    FAKE_STAMP_DIR="$FAKE_STAMP_DIR" \
    scripts/db/deploy_migration.sh \
      --migration supabase/migrations/20260817010202_verify_failure.sql \
      --verify "$TEST_TMP/fail-verification.sql" 2>&1
)"; then
  fail "A migration with failed live verification was stamped."
fi
assert_contains "$failed_verify_output" \
  "migration SQL reached production but verification/stamping did not complete"
[[ ! -f "$FAKE_STAMP_DIR/20260817010202" ]] ||
  fail "Failed verification still created a remote stamp."

echo "Database migration workflow tests passed."
