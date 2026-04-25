#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ensure_docker_runtime() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required" >&2
    exit 1
  fi

  if docker info >/dev/null 2>&1; then
    return
  fi

  if command -v colima >/dev/null 2>&1; then
    if ! colima status >/dev/null 2>&1; then
      colima start --cpu 4 --memory 8 --disk 60 >/dev/null
    fi
  fi

  docker info >/dev/null 2>&1
}

local_db_url() {
  local status_output=""
  if status_output="$(supabase status -o env 2>/dev/null)"; then
    local parsed_url
    parsed_url="$(printf '%s\n' "$status_output" | awk -F= '$1=="DB_URL"{print substr($0, index($0, "=") + 1)}')"
    parsed_url="${parsed_url%\"}"
    parsed_url="${parsed_url#\"}"
    if [[ -n "$parsed_url" ]]; then
      printf '%s\n' "$parsed_url"
      return
    fi
  fi

  printf '%s\n' "postgresql://postgres:postgres@127.0.0.1:54322/postgres"
}

reset_public_schema() {
  local db_url="$1"

  psql "$db_url" -v ON_ERROR_STOP=1 <<'SQL'
drop schema if exists public cascade;

create schema public;

grant all on schema public to postgres;
grant all on schema public to public;

create extension if not exists pgcrypto with schema public;
create extension if not exists pg_trgm with schema public;
create extension if not exists unaccent with schema public;
create extension if not exists vector with schema public;
create extension if not exists pgtap with schema public;
SQL
}

apply_baseline() {
  local db_url="$1"
  psql "$db_url" -v ON_ERROR_STOP=1 -f "$ROOT_DIR/supabase/sql/local_public_baseline.sql"
}

run_local_tests() {
  supabase test db --local supabase/tests/*.sql
}

ensure_docker_runtime
supabase db start

DB_URL="$(local_db_url)"
if [[ -z "$DB_URL" ]]; then
  echo "Could not resolve local DB_URL from supabase status" >&2
  exit 1
fi

reset_public_schema "$DB_URL"
apply_baseline "$DB_URL"
run_local_tests

echo
echo "Local Supabase DB bootstrapped and smoke-tested."
