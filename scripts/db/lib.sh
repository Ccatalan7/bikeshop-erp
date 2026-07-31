#!/usr/bin/env bash

set -euo pipefail

DB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DB_CACHE_DIR="$DB_ROOT/.tmp/db"
SUPABASE_CLI_WRAPPER="$DB_ROOT/scripts/supabase_cli.sh"
mkdir -p "$DB_CACHE_DIR"

export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required; run the project bootstrap"
}

run_supabase_cli() {
  "$SUPABASE_CLI_WRAPPER" "$@"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

sha256_text() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  else
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  fi
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

# Append one audit line per guarded database invocation. Records identity and
# outcome only: never SQL text, result values, or credentials.
journal_append() {
  local environment="$1" mode="$2" sql_sha="$3" source="$4" format="$5"
  local max_rows="$6" allow_pii="$7" duration_s="$8" status="$9"
  printf '{"ts":"%s","environment":"%s","mode":"%s","sql_sha256":"%s","source":"%s","format":"%s","max_rows":%s,"allow_pii":%s,"duration_s":%s,"exit_status":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$(json_escape "$environment")" \
    "$(json_escape "$mode")" \
    "$sql_sha" \
    "$(json_escape "$source")" \
    "$(json_escape "$format")" \
    "$max_rows" "$allow_pii" "$duration_s" "$status" \
    >>"$DB_CACHE_DIR/journal.jsonl" 2>/dev/null || true
}

ensure_docker() {
  require_command docker
  if ! docker info >/dev/null 2>&1 && command -v colima >/dev/null 2>&1; then
    colima status >/dev/null 2>&1 || colima start --cpu 4 --memory 8 --disk 60 >/dev/null
  fi
  docker info >/dev/null 2>&1 || die "Docker is unavailable; start Docker Desktop or Colima"
}

local_db_url() {
  local output url
  output="$(run_supabase_cli status -o env 2>/dev/null || true)"
  url="$(printf '%s\n' "$output" | awk -F= '$1=="DB_URL"{print substr($0,index($0,"=")+1)}')"
  url="${url%\"}"
  url="${url#\"}"
  printf '%s\n' "${url:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
}

credential_value() {
  local service="$1"
  local account="$2"
  local env_name="$3"
  if [[ -n "${!env_name:-}" ]]; then
    printf '%s\n' "${!env_name}"
  elif command -v security >/dev/null 2>&1; then
    security find-generic-password -w -s "$service" -a "$account" 2>/dev/null || die "Missing credential '$service' / $env_name"
  else
    die "Missing environment credential $env_name"
  fi
}

configure_remote_pg() {
  local environment="$1"
  case "$environment" in
    staging)
      PGUSER="postgres.$(credential_value 'Vinabike ERP Supabase staging project ref' supabase SUPABASE_STAGING_PROJECT_REF)"
      PGPASSWORD="$(credential_value 'Vinabike ERP Supabase staging database password' postgres SUPABASE_STAGING_DB_PASSWORD)"
      ;;
    production)
      local project_ref
      project_ref="$(tr -d '[:space:]' <"$DB_ROOT/supabase/.temp/project-ref")"
      [[ -n "$project_ref" ]] || die "Production project ref is unavailable"
      PGUSER="postgres.$project_ref"
      PGPASSWORD="$(credential_value 'Vinabike ERP Supabase database password' postgres SUPABASE_DB_PASSWORD)"
      ;;
    *) die "Unsupported remote environment: $environment" ;;
  esac
  export PGHOST="aws-1-sa-east-1.pooler.supabase.com"
  export PGPORT=5432
  export PGDATABASE=postgres
  export PGUSER PGPASSWORD
}
