#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/vinabike-production-validation-test.XXXXXX")"
trap 'rm -rf -- "$TEST_TMP"' EXIT

export VINABIKE_PROD_VALIDATION_ROOT="$TEST_TMP/cache"
export VINABIKE_PROD_VALIDATION_LOCK_TIMEOUT_SECONDS=1

# shellcheck source=scripts/db/production_validation.sh
source "$ROOT_DIR/scripts/db/production_validation.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_equal() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] ||
    fail "$label: expected '$expected', got '$actual'"
}

assert_not_equal() {
  local left="$1"
  local right="$2"
  local label="$3"
  [[ "$left" != "$right" ]] ||
    fail "$label: values unexpectedly matched"
}

help_output="$(
  bash "$ROOT_DIR/scripts/db/production_validation.sh" --help
)"
[[ "$help_output" == *"prepare --task TASK"* ]] ||
  fail "global --help did not print the command interface"
[[ "$help_output" != *"Unknown command"* ]] ||
  fail "global --help fell through to unknown-command handling"

key_one="$(
  production_validation_cache_key \
    170006 \
    20260724230000 \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
)"
key_two="$(
  production_validation_cache_key \
    170006 \
    20260724230000 \
    aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
)"
key_changed="$(
  production_validation_cache_key \
    170006 \
    20260724230000 \
    bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
)"
assert_equal "$key_one" "$key_two" "cache key determinism"
assert_not_equal "$key_one" "$key_changed" "catalog fingerprint cache invalidation"
[[ "$key_one" =~ ^[0-9a-f]{64}$ ]] ||
  fail "cache key is not SHA-256 shaped"

production_validation_validate_task "expense-notifications"
if (production_validation_validate_task "bad/task") >/dev/null 2>&1; then
  fail "task validation accepted a path separator"
fi

clean_toc="$TEST_TMP/clean.toc"
data_toc="$TEST_TMP/data.toc"
acl_toc="$TEST_TMP/acl.toc"
printf '%s\n' \
  '1; 2615 2200 SCHEMA - public postgres' \
  '2; 1259 100 TABLE public expenses postgres' \
  >"$clean_toc"
printf '%s\n' \
  '1; 2615 2200 SCHEMA - public postgres' \
  '2; 0 100 TABLE DATA public expenses postgres' \
  >"$data_toc"
printf '%s\n' \
  '1; 2615 2200 SCHEMA - public postgres' \
  '2; 0 0 ACL - TABLE public.expenses postgres' \
  >"$acl_toc"
production_validation_verify_schema_only_toc "$clean_toc"
if (production_validation_verify_schema_only_toc "$data_toc") \
  >/dev/null 2>&1; then
  fail "schema-only guard accepted TABLE DATA"
fi
production_validation_verify_acl_toc "$acl_toc"
if (production_validation_verify_acl_toc "$clean_toc") >/dev/null 2>&1; then
  fail "ACL guard accepted an archive without ACL entries"
fi

stale_lock="$PRODUCTION_VALIDATION_LOCKS/stale"
mkdir -p "$stale_lock"
printf 'pid=999999\nhost=%s\n' "$(hostname)" >"$stale_lock/owner"
production_validation_acquire_lock stale
assert_equal \
  "$(awk -F= '$1 == "pid" { print $2 }' "$stale_lock/owner")" \
  "$$" \
  "stale lock replacement"
production_validation_release_lock "$stale_lock"

production_validation_acquire_lock contention
if VINABIKE_PROD_VALIDATION_ROOT="$VINABIKE_PROD_VALIDATION_ROOT" \
  VINABIKE_PROD_VALIDATION_LOCK_TIMEOUT_SECONDS=0 \
  bash -c \
    'source "$1"; production_validation_acquire_lock contention' \
    bash \
    "$ROOT_DIR/scripts/db/production_validation.sh" \
    >/dev/null 2>&1; then
  fail "cross-process lock allowed concurrent cache mutation"
fi
production_validation_release_lock \
  "$PRODUCTION_VALIDATION_LOCKS/contention"

resolved_migration="$(
  production_validation_resolve_migration \
    "$ROOT_DIR/supabase/migrations/20260724230000_add_expense_notifications.sql"
)"
assert_equal \
  "$(production_validation_migration_version "$resolved_migration")" \
  "20260724230000" \
  "migration version parsing"
if (production_validation_resolve_migration "$ROOT_DIR/pubspec.yaml") \
  >/dev/null 2>&1; then
  fail "migration resolver accepted a file outside supabase/migrations"
fi

recorded_manifest="$TEST_TMP/applied-migrations.tsv"
recorded_sha="$(sha256_file "$resolved_migration")"
printf '%s\t%s\t%s\n' \
  "20260724230000" \
  "$recorded_sha" \
  "$resolved_migration" \
  >"$recorded_manifest"
production_validation_recorded_migrations_are_current "$recorded_manifest" ||
  fail "valid recorded migration manifest was rejected"
printf '%s\t%s\t%s\n' \
  "20260724230000" \
  "$(printf '0%.0s' {1..64})" \
  "$resolved_migration" \
  >"$recorded_manifest"
if production_validation_recorded_migrations_are_current "$recorded_manifest"; then
  fail "changed recorded migration hash was not detected"
fi
printf '%s\t%s\t%s\n' \
  "20260724230000" \
  "$recorded_sha" \
  "$ROOT_DIR/supabase/migrations/missing.sql" \
  >"$recorded_manifest"
if production_validation_recorded_migrations_are_current "$recorded_manifest"; then
  fail "missing recorded migration file was not detected"
fi

selected_tests="$TEST_TMP/selected-tests.txt"
production_validation_select_tests "$selected_tests" expense_notifications
assert_equal \
  "$(wc -l <"$selected_tests" | tr -d '[:space:]')" \
  "1" \
  "focused pgTAP selector"
assert_equal \
  "$(basename "$(<"$selected_tests")")" \
  "expense_notifications.sql" \
  "focused pgTAP file"

if rg -n \
  '(^|[;&|[:space:]])supabase[[:space:]]+(status|db|test|projects|functions|secrets|backups)' \
  "$ROOT_DIR/scripts/db/production_validation.sh" \
  >/dev/null; then
  fail "manager contains a raw Supabase CLI invocation"
fi

echo "production validation manager shell tests passed"
