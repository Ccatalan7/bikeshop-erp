#!/usr/bin/env bash

set -euo pipefail

# Supabase CLI telemetry has previously persisted unredacted request metadata
# under ~/.supabase/traces. Force both official opt-out mechanisms and disable
# OpenTelemetry inside the child process so callers cannot accidentally turn
# tracing back on through their ambient environment.
export SUPABASE_TELEMETRY_DISABLED=1
export DO_NOT_TRACK=1
export OTEL_SDK_DISABLED=true
export OTEL_TRACES_EXPORTER=none
export OTEL_METRICS_EXPORTER=none
export OTEL_LOGS_EXPORTER=none

reject_unsafe_cli_usage() {
  echo "Refusing unsafe Supabase CLI invocation: $1" >&2
  exit 64
}

args=("$@")
is_api_keys=false
is_db_query=false
is_db_push=false
is_test_db=false
is_migration_repair=false
is_migration_up=false
is_migration_down=false
is_migration_list=false
is_migration_fetch=false
is_db_dump=false
is_db_pull=false
is_db_advisors=false
is_projects_delete=false
is_functions_remote=false
is_functions_delete=false
is_secrets_remote=false
is_secrets_unset=false
is_backups_remote=false
is_storage_copy=false
is_storage_remove=false
has_linked=false
has_db_url=false
db_url=""
project_ref=""

contains_ordered_tokens() {
  local first="$1"
  local second="$2"
  local saw_first=false
  local token
  shift 2

  for token in "$@"; do
    if [[ "$saw_first" == false && "$token" == "$first" ]]; then
      saw_first=true
    elif [[ "$saw_first" == true && "$token" == "$second" ]]; then
      return 0
    fi
  done
  return 1
}

for ((index = 0; index < ${#args[@]}; index++)); do
  arg="${args[$index]}"
  next_arg="${args[$((index + 1))]:-}"

  case "$arg" in
    --debug | --debug=*)
      reject_unsafe_cli_usage \
        "--debug can expose request metadata. Use the telemetry-disabled default."
      ;;
    --log-level)
      case "$next_arg" in
        [Aa][Ll][Ll] | [Dd][Ee][Bb][Uu][Gg] | [Tt][Rr][Aa][Cc][Ee])
          reject_unsafe_cli_usage \
            "--log-level $next_arg can expose request metadata. Use the default log level."
          ;;
      esac
      ;;
    --log-level=[Aa][Ll][Ll] | --log-level=[Dd][Ee][Bb][Uu][Gg] | --log-level=[Tt][Rr][Aa][Cc][Ee])
      reject_unsafe_cli_usage \
        "$arg can expose request metadata. Use the default log level."
      ;;
    --linked | --linked=*)
      has_linked=true
      ;;
    --db-url)
      has_db_url=true
      db_url="$next_arg"
      ;;
    --db-url=*)
      has_db_url=true
      db_url="${arg#--db-url=}"
      ;;
    --project-ref)
      project_ref="$next_arg"
      ;;
    --project-ref=*)
      project_ref="${arg#--project-ref=}"
      ;;
  esac
done

contains_ordered_tokens projects api-keys "${args[@]}" && is_api_keys=true
contains_ordered_tokens db query "${args[@]}" && is_db_query=true
contains_ordered_tokens db push "${args[@]}" && is_db_push=true
contains_ordered_tokens test db "${args[@]}" && is_test_db=true
contains_ordered_tokens migration repair "${args[@]}" && is_migration_repair=true
contains_ordered_tokens migration up "${args[@]}" && is_migration_up=true
contains_ordered_tokens migration down "${args[@]}" && is_migration_down=true
contains_ordered_tokens migration list "${args[@]}" && is_migration_list=true
contains_ordered_tokens migration fetch "${args[@]}" && is_migration_fetch=true
contains_ordered_tokens db dump "${args[@]}" && is_db_dump=true
contains_ordered_tokens db pull "${args[@]}" && is_db_pull=true
contains_ordered_tokens db advisors "${args[@]}" && is_db_advisors=true
contains_ordered_tokens projects delete "${args[@]}" && is_projects_delete=true
if contains_ordered_tokens functions list "${args[@]}" ||
  contains_ordered_tokens functions deploy "${args[@]}" ||
  contains_ordered_tokens functions download "${args[@]}" ||
  contains_ordered_tokens functions delete "${args[@]}"; then
  is_functions_remote=true
fi
contains_ordered_tokens functions delete "${args[@]}" && is_functions_delete=true
if contains_ordered_tokens secrets list "${args[@]}" ||
  contains_ordered_tokens secrets set "${args[@]}" ||
  contains_ordered_tokens secrets unset "${args[@]}"; then
  is_secrets_remote=true
fi
contains_ordered_tokens secrets unset "${args[@]}" && is_secrets_unset=true
contains_ordered_tokens backups list "${args[@]}" && is_backups_remote=true
contains_ordered_tokens storage cp "${args[@]}" && is_storage_copy=true
contains_ordered_tokens storage rm "${args[@]}" && is_storage_remove=true

if [[ "$is_api_keys" == true ]]; then
  for arg in "${args[@]}"; do
    case "$arg" in
      --reveal | --reveal=*)
        reject_unsafe_cli_usage \
          "projects api-keys --reveal is forbidden. Use process environment or the documented OS credential store."
        ;;
    esac
  done
fi

[[ "$is_db_query" == false ]] ||
  reject_unsafe_cli_usage \
    "raw db query bypasses repository guards. Use scripts/db/query.sh."
[[ "$is_db_push" == false ]] ||
  reject_unsafe_cli_usage \
    "db push bypasses repository validation. Use scripts/db/production_validation.sh and the guarded deployment runbook."
[[ "$is_migration_up" == false && "$is_migration_down" == false ]] ||
  reject_unsafe_cli_usage \
    "migration up/down bypasses guarded deployment. Use scripts/db/query.sh and register only the verified version."
[[ "$is_db_dump" == false && "$is_db_pull" == false &&
  "$is_db_advisors" == false ]] ||
  reject_unsafe_cli_usage \
    "hosted db dump/pull/advisors bypass the production-validation and guarded-query paths."
[[ "$is_migration_list" == false && "$is_migration_fetch" == false ]] ||
  reject_unsafe_cli_usage \
    "remote migration inspection uses scripts/db/query.sh; CLI list/fetch is not an agent path."
[[ "$is_projects_delete" == false ]] ||
  reject_unsafe_cli_usage \
    "project deletion is an owner-only provider action and is never available through this wrapper."
[[ "$is_storage_remove" == false ]] ||
  reject_unsafe_cli_usage \
    "storage removal requires an application-specific reviewed cleanup path."
[[ "$has_linked" == false || "$is_migration_repair" == true ||
  "$is_storage_copy" == true ]] ||
  reject_unsafe_cli_usage \
    "--linked is reserved for verified migration repair or confirmed reviewed storage copy. Use repository guards for hosted database access."

if [[ "$has_db_url" == true ]]; then
  [[ "$is_test_db" == true ]] ||
    reject_unsafe_cli_usage \
      "--db-url is allowed only for pgTAP against an explicit local scratch database."
  case "$db_url" in
    postgresql://*@127.0.0.1:*/* | postgres://*@127.0.0.1:*/* | \
      postgresql://*@localhost:*/* | postgres://*@localhost:*/*)
      ;;
    *)
      reject_unsafe_cli_usage \
        "test db --db-url must target loopback; hosted database tests are forbidden."
      ;;
  esac
fi

if [[ "$is_storage_copy" == true && "$has_linked" == true ]]; then
  wrapper_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  linked_ref_file="$wrapper_root/supabase/.temp/project-ref"
  [[ -f "$linked_ref_file" ]] ||
    reject_unsafe_cli_usage \
      "linked storage copy cannot prove the production project."
  linked_ref="$(tr -d '[:space:]' <"$linked_ref_file")"
  [[ "$linked_ref" == "xzdvtzdqjeyqxnkqprtf" ]] ||
    reject_unsafe_cli_usage \
      "linked storage copy targets an unapproved project."
  [[ "${VINABIKE_SUPABASE_STORAGE_WRITE_CONFIRM:-}" == "$linked_ref" ]] ||
    reject_unsafe_cli_usage \
      "linked storage copy requires VINABIKE_SUPABASE_STORAGE_WRITE_CONFIRM to equal the reviewed project ref."
fi

if [[ "$is_functions_remote" == true ||
  "$is_secrets_remote" == true ||
  "$is_backups_remote" == true ||
  "$is_api_keys" == true ]]; then
  [[ -n "$project_ref" ]] ||
    reject_unsafe_cli_usage \
      "remote control-plane commands require an explicit approved --project-ref."
  if [[ "$project_ref" == "bczzjhjrpmtpgwdvlbut" ]]; then
    [[ "${VINABIKE_STAGING_REACTIVATION_CONFIRM:-}" == "$project_ref" ]] ||
      reject_unsafe_cli_usage \
        "staging is policy-dormant and requires explicit owner reactivation."
  else
    [[ "$project_ref" == "xzdvtzdqjeyqxnkqprtf" ]] ||
      reject_unsafe_cli_usage \
        "remote control-plane target is not an approved repository project."
  fi
fi

if [[ "$is_functions_delete" == true || "$is_secrets_unset" == true ]]; then
  [[ "${VINABIKE_SUPABASE_DESTRUCTIVE_CONFIRM:-}" == "$project_ref" ]] ||
    reject_unsafe_cli_usage \
      "destructive control-plane changes require VINABIKE_SUPABASE_DESTRUCTIVE_CONFIRM to equal the reviewed project ref."
fi

if [[ "$is_migration_repair" == true ]]; then
  [[ "$has_linked" == true ]] ||
    reject_unsafe_cli_usage \
      "migration repair requires the explicit linked-production verification path."
  [[ "${VINABIKE_DB_WRITE_CONFIRM:-}" == production ]] ||
    reject_unsafe_cli_usage \
      "migration repair requires VINABIKE_DB_WRITE_CONFIRM=production after exact read-back."
  wrapper_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  linked_ref_file="$wrapper_root/supabase/.temp/project-ref"
  [[ -f "$linked_ref_file" ]] ||
    reject_unsafe_cli_usage \
      "migration repair cannot prove the linked production project."
  linked_ref="$(tr -d '[:space:]' <"$linked_ref_file")"
  [[ "$linked_ref" == "xzdvtzdqjeyqxnkqprtf" ]] ||
    reject_unsafe_cli_usage \
      "migration repair is linked to an unapproved project."
fi

requested_bin="${VINABIKE_SUPABASE_BIN:-supabase}"
resolved_bin="$(command -v "$requested_bin" 2>/dev/null || true)"
[[ -n "$resolved_bin" ]] || {
  echo "Supabase CLI is unavailable; run the project bootstrap." >&2
  exit 127
}

wrapper_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
[[ "$resolved_bin" != "$wrapper_path" ]] || {
  echo "VINABIKE_SUPABASE_BIN must not point to the Supabase CLI wrapper itself." >&2
  exit 64
}

if [[ "$is_api_keys" == true ]]; then
  command -v jq >/dev/null 2>&1 || {
    echo "jq is required for the metadata-only API-key status check." >&2
    exit 127
  }

  safe_args=()
  skip_output_value=false
  for arg in "${args[@]}"; do
    if [[ "$skip_output_value" == true ]]; then
      skip_output_value=false
      continue
    fi
    case "$arg" in
      --output | -o)
        skip_output_value=true
        ;;
      --output=* | -o=*)
        ;;
      *)
        safe_args+=("$arg")
        ;;
    esac
  done
  safe_args+=(--output json)

  set +e
  api_keys_json="$("$resolved_bin" "${safe_args[@]}" 2>/dev/null)"
  cli_status=$?
  set -e
  if [[ "$cli_status" -ne 0 ]]; then
    echo "Supabase API-key metadata request failed; no key material was returned." >&2
    exit "$cli_status"
  fi

  # The provider includes full legacy JWT values even without --reveal.
  # Return only the key type required by scripts/db/status.sh.
  printf '%s\n' "$api_keys_json" |
    jq -c 'if type == "array" then map({type}) else error("unexpected API-key metadata response") end'
  exit "${PIPESTATUS[1]}"
fi

exec "$resolved_bin" "$@"
