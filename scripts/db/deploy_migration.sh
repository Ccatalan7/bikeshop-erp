#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/db/deploy_migration.sh \
  --migration supabase/migrations/YYYYMMDDHHMMSS_slug.sql \
  --verify path/to/readback_assertion.sql [--verify another_assertion.sql ...]

This is the only complete hosted schema deployment path:
  1. prove the exact version is not already stamped;
  2. apply the reviewed standalone migration through query.sh;
  3. run every read-only verification file (each must fail at SQL level when
     its expected definition or business invariant is absent);
  4. register the exact version in Supabase migration history;
  5. read the APPLIED stamp back and write a local evidence receipt.

Requires task authorization and VINABIKE_DB_WRITE_CONFIRM=production.
core_schema.sql is never accepted by this command.
USAGE
  exit 64
}

migration=""
verifications=()
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --migration)
      migration="${2:-}"
      shift 2
      ;;
    --verify)
      verifications+=("${2:-}")
      shift 2
      ;;
    -h | --help) usage ;;
    *) usage ;;
  esac
done

[[ -n "$migration" ]] || usage
[[ "${#verifications[@]}" -gt 0 ]] ||
  die "At least one executable read-back assertion is required (--verify FILE)"
[[ "${VINABIKE_DB_WRITE_CONFIRM:-}" == production ]] ||
  die "Production migration deployment requires VINABIKE_DB_WRITE_CONFIRM=production"

cd "$DB_ROOT"
resolve_forward_migration "$migration"
# resolve_forward_migration assigns these exported identity fields.
# shellcheck disable=SC2153
migration_absolute="$MIGRATION_ABSOLUTE"
# shellcheck disable=SC2153
migration_relative="$MIGRATION_RELATIVE"
# shellcheck disable=SC2153
migration_filename="$MIGRATION_FILENAME"
# shellcheck disable=SC2153
migration_version="$MIGRATION_VERSION"

verified_files=()
for verification in "${verifications[@]}"; do
  verification_dir="$(cd "$(dirname "$verification")" 2>/dev/null && pwd -P)" ||
    die "Verification directory does not exist: $(dirname "$verification")"
  verification_absolute="$verification_dir/$(basename "$verification")"
  [[ -f "$verification_absolute" ]] ||
    die "Verification file does not exist: $verification"
  [[ "$verification_absolute" == *.sql ]] ||
    die "Verification must be a SQL file: $verification"
  verified_files+=("$verification_absolute")
done

history_status() {
  local output
  output="$(bash "$DB_ROOT/scripts/db/query.sh" production \
    --format csv \
    --max-rows 0 \
    --sql "select case when exists (
      select 1 from supabase_migrations.schema_migrations
      where version::text = '$migration_version'
    ) then 'APPLIED' else 'NOT_APPLIED' end as production_status")"
  printf '%s\n' "$output" | tail -n 1 | tr -d '\r"'
}

before_status="$(history_status)"
[[ "$before_status" == NOT_APPLIED ]] ||
  die "$migration_filename is already stamped APPLIED in production; immutable migrations are never rerun or edited"

migration_applied=false
deployment_complete=false
report_partial_deployment() {
  status="$?"
  if [[ "$status" -ne 0 && "$migration_applied" == true && "$deployment_complete" == false ]]; then
    echo "ERROR: The migration SQL reached production but verification/stamping did not complete." >&2
    echo "Do not guess or edit history. Diagnose live state, rerun the idempotent migration if needed, then complete this same command." >&2
  fi
  exit "$status"
}
trap report_partial_deployment EXIT

echo "Applying standalone migration $migration_relative"
VINABIKE_DB_DEPLOY_WORKFLOW="apply-verify-stamp:$migration_version" \
  bash "$DB_ROOT/scripts/db/query.sh" production \
  --write \
  --file "$migration_absolute"
migration_applied=true

for verification_absolute in "${verified_files[@]}"; do
  echo "Running guarded read-back assertion ${verification_absolute#"$DB_ROOT"/}"
  bash "$DB_ROOT/scripts/db/query.sh" production \
    --format table \
    --max-rows 0 \
    --file "$verification_absolute"
done

echo "Registering production migration stamp $migration_version"
VINABIKE_DB_WRITE_CONFIRM=production \
  "$DB_ROOT/scripts/supabase_cli.sh" migration repair \
  --linked \
  --status applied \
  "$migration_version"

after_status="$(history_status)"
[[ "$after_status" == APPLIED ]] ||
  die "Migration history read-back did not return APPLIED for $migration_version"

receipt_dir="$DB_CACHE_DIR/migration-receipts"
receipt_file="$receipt_dir/$migration_version.receipt"
mkdir -p "$receipt_dir"
{
  printf 'version=%s\n' "$migration_version"
  printf 'migration=%s\n' "$migration_relative"
  printf 'migration_sha256=%s\n' "$(sha256_file "$migration_absolute")"
  printf 'production_status=APPLIED\n'
  printf 'verified_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for verification_absolute in "${verified_files[@]}"; do
    printf 'verification=%s sha256=%s\n' \
      "${verification_absolute#"$DB_ROOT"/}" \
      "$(sha256_file "$verification_absolute")"
  done
} >"$receipt_file"

deployment_complete=true
trap - EXIT
echo "Migration $migration_version is APPLIED and verified."
echo "Local evidence receipt: ${receipt_file#"$DB_ROOT"/}"
