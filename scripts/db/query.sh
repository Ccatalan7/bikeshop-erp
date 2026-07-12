#!/usr/bin/env bash

set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

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

require_command psql
psql_args=(-X -v ON_ERROR_STOP=1 -P pager=off)
if [[ "$environment" == local ]]; then
  bash "$DB_ROOT/scripts/db/ensure_local.sh"
  connection=("$(local_db_url)")
elif [[ "$environment" == staging || "$environment" == production ]]; then
  configure_remote_pg "$environment"
  connection=("dbname=postgres")
  export PGOPTIONS="-c statement_timeout=30000"
  if [[ "$write" == false ]]; then
    export PGOPTIONS="$PGOPTIONS -c default_transaction_read_only=on"
  fi
else
  usage
fi

if [[ "$environment" == production && "$write" == true ]]; then
  die "Production writes are intentionally unsupported by this helper"
fi
if [[ "$environment" == staging && "$write" == true && "${VINABIKE_DB_WRITE_CONFIRM:-}" != staging ]]; then
  die "Staging writes require VINABIKE_DB_WRITE_CONFIRM=staging"
fi

if [[ -n "$file" ]]; then
  [[ -f "$file" ]] || die "SQL file not found: $file"
  [[ "$format" == table ]] || die "--file currently supports table output; use --sql for csv/json"
  if [[ "$environment" != local && "$write" == false ]]; then
    if rg -n -i '^\s*(begin|commit|rollback|end|set\s+transaction)\b' "$file" >/dev/null; then
      die "Remote read-only SQL files cannot manage transactions"
    fi
    {
      printf '%s\n' "begin read only;" "set local statement_timeout = '30s';"
      cat "$file"
      printf '%s\n' "rollback;"
    } |
      psql "${connection[@]}" "${psql_args[@]}" -q
    exit "${PIPESTATUS[1]}"
  fi
  exec psql "${connection[@]}" "${psql_args[@]}" -f "$file"
fi

sql="${sql%;}"
original_sql="$sql"
if [[ "$environment" != local && "$write" == false ]]; then
  if printf '%s\n' "$sql" | rg -i '\b(begin|commit|rollback|end|set\s+transaction)\b' >/dev/null; then
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
