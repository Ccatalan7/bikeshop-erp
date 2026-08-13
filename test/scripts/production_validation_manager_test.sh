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

credential_value() {
  printf '%s\n' 'fake-production-password'
}

psql() {
  printf '%s\n' '2001:db8::1/128	5432	postgres	postgres'
}

PGHOST="untrusted.example"
PGPORT="6543"
PGDATABASE="other"
PGUSER="postgres.not-production"
production_validation_guard_production_connection
assert_equal \
  "$PGHOST" \
  "db.xzdvtzdqjeyqxnkqprtf.supabase.co" \
  "production validation direct host"
assert_equal "$PGPORT" "5432" "production validation direct port"
assert_equal "$PGDATABASE" "postgres" "production validation database"
assert_equal "$PGUSER" "postgres" "production validation direct user"
assert_equal \
  "$PGCONNECT_TIMEOUT" \
  "10" \
  "production validation direct connect timeout"
[[ "$PGOPTIONS" == *"default_transaction_read_only=on"* ]] ||
  fail "production validation direct connection lost read-only PGOPTIONS"
[[ "$PGHOST" != *"pooler.supabase.com"* ]] ||
  fail "production validation unexpectedly selected the shared pooler"
production_validation_clear_remote_connection

psql() {
  printf '%s\n' '10.0.0.8	5432	postgres	postgres'
}
if (production_validation_guard_production_connection) >/dev/null 2>&1; then
  fail "production validation accepted a non-IPv6 direct connection"
fi
production_validation_clear_remote_connection
unset -f psql credential_value

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
  '2; 2615 2201 SCHEMA - private postgres' \
  '3; 1259 100 TABLE public expenses postgres' \
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

managed_post="$TEST_TMP/local-managed-post.sql"
managed_post_early="$TEST_TMP/local-managed-post-early.sql"
managed_post_late="$TEST_TMP/local-managed-post-late.sql"
printf '%s\n' \
  'CREATE INDEX users_email_idx ON auth.users USING btree (email);' \
  '' \
  'CREATE POLICY users_tenant_access ON auth.users USING ((EXISTS ( SELECT 1' \
  '   FROM public.user_profiles profile' \
  '  WHERE ((profile.user_id = auth.uid()) AND (profile.is_active IS TRUE)))));' \
  '' \
  'CREATE POLICY employee_advance_receipt_guard ON storage.objects USING (' \
  '  (NOT private.is_locked_employee_advance_storage_object(name))' \
  ');' \
  '' \
  'ALTER TABLE ONLY storage.objects' \
  '    ADD CONSTRAINT objects_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES storage.buckets(id);' \
  >"$managed_post"
production_validation_split_managed_post_data \
  "$managed_post" \
  "$managed_post_early" \
  "$managed_post_late"
grep -q 'CREATE INDEX users_email_idx' "$managed_post_early" ||
  fail "managed post-data split lost an independent early statement"
grep -q 'ADD CONSTRAINT objects_bucket_id_fkey' "$managed_post_early" ||
  fail "managed post-data split lost a multiline early statement"
if grep -Eq '(public|private)\.' "$managed_post_early"; then
  fail "managed post-data split left a public/private dependency in early SQL"
fi
grep -q 'CREATE POLICY users_tenant_access' "$managed_post_late" ||
  fail "managed post-data split lost the deferred policy statement"
grep -q 'FROM public.user_profiles profile' "$managed_post_late" ||
  fail "managed post-data split detached the deferred policy body"
grep -q 'private.is_locked_employee_advance_storage_object' "$managed_post_late" ||
  fail "managed post-data split left a private-schema dependency before restore"

grep -q -- '--schema=private' "$ROOT_DIR/scripts/db/production_validation.sh" ||
  fail "production capture omitted the dependency-only private schema"
grep -q "namespace.nspname in ('public', 'private')" \
  "$ROOT_DIR/scripts/db/production_validation_catalog.sql" ||
  fail "catalog fingerprint omitted private schema drift"
grep -q "namespace.nspname in ('public', 'private')" \
  "$ROOT_DIR/scripts/db/production_validation_acl_roles.sql" ||
  fail "ACL role capture omitted private schema grants"

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
if rg -n \
  'configure_remote_pg|pooler\\.supabase\\.com' \
  "$ROOT_DIR/scripts/db/production_validation.sh" \
  >/dev/null; then
  fail "manager contains a production-validation pooler fallback"
fi

echo "production validation manager shell tests passed"
