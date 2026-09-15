#!/usr/bin/env bash

# One-command session preflight for database work. Run once at the start of a
# task, not before every query. Reports identity, authentication, hosted
# control-plane reachability, and credential presence. Never prints a
# credential value.

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

EXPECTED_PRODUCTION_REF="xzdvtzdqjeyqxnkqprtf"

section() {
  printf '\n== %s ==\n' "$1"
}

section "Supabase CLI"
run_supabase_cli --version || die "Supabase CLI is unavailable; run the project bootstrap"

section "Linked project identity"
if [[ -f "$DB_ROOT/supabase/.temp/project-ref" ]]; then
  linked_ref="$(tr -d '[:space:]' <"$DB_ROOT/supabase/.temp/project-ref")"
  if [[ "$linked_ref" == "$EXPECTED_PRODUCTION_REF" ]]; then
    echo "linked: $linked_ref (approved production)"
  else
    echo "linked: $linked_ref"
    die "Linked project is not the approved production project $EXPECTED_PRODUCTION_REF"
  fi
else
  die "Linked production project identity is unavailable"
fi

section "Hosted control plane"
if run_supabase_cli projects list --output json >"$DB_CACHE_DIR/preflight_projects.json" 2>/dev/null; then
  echo "projects list: reachable (${DB_CACHE_DIR#"$DB_ROOT"/}/preflight_projects.json)"
else
  echo "projects list: unreachable — check CLI authentication or provider status" >&2
fi

section "Environment and credentials"
bash "$DB_ROOT/scripts/db/status.sh"

cat <<'NEXT'

== Reminders ==
All SQL goes through scripts/db/query.sh; the CLI never runs SQL.
Hosted reads: BEGIN READ ONLY, 30s timeout, 200-row cap, sensitive-column guard.
Writes need VINABIKE_DB_WRITE_CONFIRM and the owner's authorization in the task.
Hosted schema changes use scripts/db/deploy_migration.sh; direct migration files
and core_schema.sql are rejected. scripts/db/migration_status.sh reads the
authoritative production stamp.
Contract: docs/development/AGENT_DATABASE_CONTRACT.md
NEXT
