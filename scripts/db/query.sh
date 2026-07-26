#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

contains_transaction_control() {
  tr '\r\n\t' '   ' |
    grep -Eiq \
      '(^|;)[[:space:]]*(begin([[:space:]]+(work|transaction))?|commit([[:space:]]+(work|transaction))?|rollback([[:space:]]+(work|transaction))?|end([[:space:]]+(work|transaction))?|set[[:space:]]+transaction)([[:space:];]|$)'
}

usage() {
  echo "Usage: $0 <local|staging|production> (--sql SQL | --file PATH) [--format table|csv|json] [--write]" >&2
  exit 64
}

environment="${1:-}"
[[ -n "$environment" ]] || usage
shift

sql=""
file=""
format=table
write=false
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --sql)
      sql="${2:-}"
      shift 2
      ;;
    --file)
      file="${2:-}"
      shift 2
      ;;
    --format)
      format="${2:-}"
      shift 2
      ;;
    --write)
      write=true
      shift
      ;;
    *) usage ;;
  esac
done
[[ -n "$sql" || -n "$file" ]] || usage
[[ -z "$sql" || -z "$file" ]] || die "Use either --sql or --file, not both"
[[ "$format" =~ ^(table|csv|json)$ ]] || die "Format must be table, csv or json"

if [[ "$environment" == staging ]]; then
  expected_staging_ref="bczzjhjrpmtpgwdvlbut"
  [[ "${VINABIKE_STAGING_REACTIVATION_CONFIRM:-}" == "$expected_staging_ref" ]] ||
    die "Staging is policy-dormant. Owner reactivation requires VINABIKE_STAGING_REACTIVATION_CONFIRM=$expected_staging_ref"
fi

require_command psql
psql_args=(-X -v ON_ERROR_STOP=1 -P pager=off)
if [[ "$environment" == local ]]; then
  bash "$DB_ROOT/scripts/db/ensure_local.sh" >/dev/null
  connection=("$(local_db_url)")
elif [[ "$environment" == staging || "$environment" == production ]]; then
  configure_remote_pg "$environment"
  connection=("dbname=postgres")
  export PGOPTIONS="-c statement_timeout=30000 -c search_path=public,extensions"
  if [[ "$write" == false ]]; then
    export PGOPTIONS="$PGOPTIONS -c default_transaction_read_only=on"
  fi
else
  usage
fi

if [[ "$environment" == staging ]]; then
  staging_ref="${PGUSER#postgres.}"
  [[ "$staging_ref" == "$expected_staging_ref" ]] ||
    die "Staging connection identity does not match the approved dormant project"
fi

if [[ "$environment" == production ]]; then
  expected_production_ref="xzdvtzdqjeyqxnkqprtf"
  [[ -f "$DB_ROOT/supabase/.temp/project-ref" ]] ||
    die "Linked production project identity is unavailable"
  linked_ref="$(tr -d '[:space:]' <"$DB_ROOT/supabase/.temp/project-ref")"
  connection_ref="${PGUSER#postgres.}"
  [[ "$linked_ref" == "$expected_production_ref" ]] ||
    die "Linked project is not the approved production project"
  [[ "$connection_ref" == "$expected_production_ref" ]] ||
    die "Production connection identity does not match the approved project"
fi
if [[ "$environment" == production && "$write" == true ]]; then
  [[ "${VINABIKE_DB_WRITE_CONFIRM:-}" == production ]] ||
    die "Production writes require VINABIKE_DB_WRITE_CONFIRM=production"
fi
if [[ "$environment" == staging && "$write" == true && "${VINABIKE_DB_WRITE_CONFIRM:-}" != staging ]]; then
  die "Staging writes require VINABIKE_DB_WRITE_CONFIRM=staging"
fi
if [[ "$environment" == staging && "$write" == true ]]; then
  production_ref="$(tr -d '[:space:]' <"$DB_ROOT/supabase/.temp/project-ref")"
  [[ -n "$production_ref" && -n "$staging_ref" ]] ||
    die "Cannot prove staging and production project identities"
  [[ "$staging_ref" != "$production_ref" ]] ||
    die "Staging project ref matches production; refusing write"
fi

if [[ -n "$file" ]]; then
  [[ -f "$file" ]] || die "SQL file not found: $file"
  if [[ "$format" != table ]]; then
    sql="$(<"$file")"
  elif [[ "$environment" != local && "$write" == false ]]; then
    if contains_transaction_control <"$file"; then
      die "Remote read-only SQL files cannot manage transactions"
    fi
    {
      printf '%s\n' "begin read only;" "set local statement_timeout = '30s';"
      cat "$file"
      printf '%s\n' "rollback;"
    } |
      psql "${connection[@]}" "${psql_args[@]}" -q
    exit "${PIPESTATUS[1]}"
  else
    exec psql "${connection[@]}" "${psql_args[@]}" -f "$file"
  fi
fi

sql="${sql%;}"
original_sql="$sql"
if [[ "$environment" != local && "$write" == false ]]; then
  if printf '%s\n' "$sql" | contains_transaction_control; then
    die "Remote read-only SQL cannot manage transactions"
  fi
  sql="begin read only; set local statement_timeout = '30s'; $sql; rollback"
  psql_args+=(-q)
fi
case "$format" in
  table) exec psql "${connection[@]}" "${psql_args[@]}" -c "$sql" ;;
  csv) exec psql "${connection[@]}" "${psql_args[@]}" --csv -c "$sql" ;;
  json)
    if [[ "$environment" != local && "$write" == false ]]; then
      exec psql "${connection[@]}" "${psql_args[@]}" -tA -c "begin read only; set local statement_timeout = '30s'; select coalesce(jsonb_pretty(jsonb_agg(to_jsonb(result))), '[]') from ($original_sql) result; rollback"
    fi
    exec psql "${connection[@]}" "${psql_args[@]}" -tA -c "select coalesce(jsonb_pretty(jsonb_agg(to_jsonb(result))), '[]') from ($sql) result"
    ;;
esac
