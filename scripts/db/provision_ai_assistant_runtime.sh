#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
project_ref="xzdvtzdqjeyqxnkqprtf"
key_id="runtime-20260811-v1"
audience="supabase:${project_ref}:assistant-runtime"
vault_name="ai_agent_runtime_attestation_v1"

if [[ $# -ne 0 ]]; then
  echo "Usage: VINABIKE_AI_RUNTIME_PROVISION_CONFIRM=production $0" >&2
  exit 64
fi
if [[ "${VINABIKE_AI_RUNTIME_PROVISION_CONFIRM:-}" != "production" ]]; then
  echo "Refusing AI runtime provisioning without the exact production marker." >&2
  exit 64
fi

cd "$repo_root"
linked_ref="$(tr -d '[:space:]' < supabase/.temp/project-ref 2>/dev/null || true)"
if [[ "$linked_ref" != "$project_ref" ]]; then
  echo "Refusing AI runtime provisioning for unexpected project: ${linked_ref:-missing}." >&2
  exit 64
fi

existing_key_count="$({
  scripts/db/query.sh production --format json --sql \
    "select count(*)::integer as count from assistant_runtime.attestation_keys"
} | jq -er '.[0].count')"
if [[ "$existing_key_count" != "0" ]]; then
  echo "Refusing to rotate an existing AI runtime attestation key." >&2
  exit 65
fi

umask 077
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/vinabike-ai-runtime.XXXXXX")"
env_file="$work_dir/edge-secrets.env"
sql_file="$work_dir/vault-provision.sql"
runtime_key_hex="$(openssl rand -hex 32)"
audit_key_hex="$(openssl rand -hex 32)"

cleanup() {
  runtime_key_hex=""
  audit_key_hex=""
  rm -f "$env_file" "$sql_file"
  rmdir "$work_dir" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

{
  printf 'AI_AGENT_RUNTIME_ATTESTATION_KID=%s\n' "$key_id"
  printf 'AI_AGENT_RUNTIME_ATTESTATION_KEY_HEX=%s\n' "$runtime_key_hex"
  printf 'AI_AGENT_RUNTIME_ATTESTATION_AUDIENCE=%s\n' "$audience"
  printf 'AI_AGENT_AUDIT_HMAC_KEY=%s\n' "$audit_key_hex"
  printf 'AI_AGENT_FAST_PROVIDER=gemini\n'
  printf 'AI_AGENT_DEEP_PROVIDER=gemini\n'
  printf 'AI_AGENT_VISION_PROVIDER=gemini\n'
  printf 'AI_AGENT_GEMINI_MODEL_ALLOWLIST=gemini-3.6-flash,gemini-3.1-pro-preview\n'
  printf 'AI_AGENT_GEMINI_FAST_MODEL=gemini-3.6-flash\n'
  printf 'AI_AGENT_GEMINI_DEEP_MODEL=gemini-3.1-pro-preview\n'
  printf 'AI_AGENT_GEMINI_VISION_MODEL=gemini-3.6-flash\n'
  printf 'AI_AGENT_GEMINI_RESEARCH_MODEL=gemini-3.6-flash\n'
  printf '%s\n' \
    "AI_AGENT_MODEL_PRICING_JSON='{\"gemini-3.6-flash\":{\"inputMicrousdPerMillionTokens\":1500000,\"outputMicrousdPerMillionTokens\":7500000},\"gemini-3.1-pro-preview\":{\"inputMicrousdPerMillionTokens\":2000000,\"outputMicrousdPerMillionTokens\":12000000}}'"
  printf 'AI_AGENT_TIMEOUT_MS=90000\n'
  printf 'AI_AGENT_MAX_OUTPUT_TOKENS=2048\n'
} > "$env_file"

# Set Edge secrets before Vault. If the guarded database write fails, a retry
# may safely overwrite these unused pre-activation values; the function is not
# deployed yet. Once Vault metadata exists, the guard above refuses rotation.
scripts/supabase_cli.sh secrets set \
  --env-file "$env_file" \
  --project-ref "$project_ref"

{
  printf '%s\n' "do \$provision\$"
  printf '%s\n' 'declare'
  printf '%s\n' '  v_secret_id uuid;'
  printf '%s\n' 'begin'
  printf "  select id into v_secret_id from vault.secrets where name = '%s';\n" \
    "$vault_name"
  printf '%s\n' '  if v_secret_id is null then'
  printf "    v_secret_id := vault.create_secret('%s', '%s', '%s');\n" \
    "$runtime_key_hex" "$vault_name" \
    'AI assistant runtime HMAC attestation key'
  printf '%s\n' '  else'
  printf "    perform vault.update_secret(v_secret_id, '%s', '%s', '%s');\n" \
    "$runtime_key_hex" "$vault_name" \
    'AI assistant runtime HMAC attestation key'
  printf '%s\n' '  end if;'
  printf '%s\n' '  update assistant_runtime.attestation_keys set is_active = false where is_active;'
  printf '%s\n' \
    '  insert into assistant_runtime.attestation_keys (' \
    '    key_id, vault_secret_id, audience, is_active, not_before, expires_at' \
    '  ) values ('
  printf "    '%s', v_secret_id, '%s', true, statement_timestamp() - interval '1 minute',\n" \
    "$key_id" "$audience"
  printf "%s\n" "    statement_timestamp() + interval '365 days'"
  printf '%s\n' '  );'
  printf '%s\n' 'end'
  printf '%s\n' "\$provision\$;"
} > "$sql_file"

VINABIKE_DB_WRITE_CONFIRM=production \
  scripts/db/query.sh production --write --file "$sql_file"

echo "AI runtime secrets and Vault metadata provisioned without value output."
