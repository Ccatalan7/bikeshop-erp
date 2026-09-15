-- Account isolated public-web provider usage on the originating tool receipt.
-- The model provider attempt remains the owner of the tool call; Browser Use
-- and Gemini grounding are external meters, not synthetic model attempts.
-- Deployment status: pending. Apply through the guarded production migration
-- workflow, then verify columns, constraints, ACLs and aggregate read-back.
-- Forward behavior: a brief ALTER TABLE lock adds nullable/defaulted ledger
-- columns, then an exact dual-shape v2 wrapper keeps the deployed v6 gateway
-- working during a DB-first rollout. There is no row backfill.
-- Recovery: the old Edge body remains accepted with zero external usage. If
-- the new deploy fails, retain this additive schema and roll the function back;
-- dropping metering columns would discard audit evidence and is not recovery.

begin;

alter table public.assistant_tool_receipts
  add column if not exists external_provider text,
  add column if not exists external_model text,
  add column if not exists external_usage_state text,
  add column if not exists external_input_tokens bigint not null default 0,
  add column if not exists external_output_tokens bigint not null default 0,
  add column if not exists external_meter text,
  add column if not exists external_meter_units integer not null default 0,
  add column if not exists external_cost_microusd bigint not null default 0;

alter table public.assistant_tool_receipts
  drop constraint if exists assistant_tool_receipts_external_usage_check;
alter table public.assistant_tool_receipts
  add constraint assistant_tool_receipts_external_usage_check check (
    external_input_tokens between 0 and 100000000
    and external_output_tokens between 0 and 100000000
    and external_meter_units between 0 and 100000000
    and external_cost_microusd between 0 and 1000000000000
    and coalesce((
      (
        external_provider is null
        and external_model is null
        and external_usage_state is null
        and external_meter is null
        and external_input_tokens = 0
        and external_output_tokens = 0
        and external_meter_units = 0
        and external_cost_microusd = 0
      )
      or
      (
        tool_name = 'research_public_web'
        and risk = 'public_research'
        and external_provider in ('browser_use', 'gemini')
        and external_model is not null
        and octet_length(external_model) between 1 and 120
        and external_model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]*$'
        and external_usage_state in (
          'provider_reported', 'configured_estimate', 'unavailable'
        )
        and external_meter in ('browser_step', 'google_search_query')
        and (
          (external_provider = 'browser_use'
            and external_meter = 'browser_step'
            and external_usage_state in ('provider_reported', 'unavailable'))
          or
          (external_provider = 'gemini'
            and external_meter = 'google_search_query'
            and external_usage_state in ('configured_estimate', 'unavailable'))
        )
      )
    ), false)
  );

create or replace function assistant_runtime.assistant_record_tool_receipt_usage_v1(
  p_tenant_id uuid,
  p_actor_user_id uuid,
  p_authority_fingerprint text,
  p_run_id uuid,
  p_lease_token uuid,
  p_fence_token bigint,
  p_ordinal integer,
  p_provider_attempt_no integer,
  p_provider_call_hash text,
  p_tool_name text,
  p_tool_version text,
  p_risk text,
  p_policy_decision text,
  p_status text,
  p_arguments_hash text,
  p_output_hash text,
  p_result_count integer,
  p_output_bytes integer,
  p_approval_used boolean,
  p_read_back_verified boolean,
  p_failure_code text,
  p_external_provider text,
  p_external_model text,
  p_external_usage_state text,
  p_external_input_tokens bigint,
  p_external_output_tokens bigint,
  p_external_meter text,
  p_external_meter_units integer,
  p_external_cost_microusd bigint,
  p_started_at timestamptz,
  p_completed_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, assistant_runtime, pg_temp
as $$
declare
  v_response jsonb;
  v_receipt_id uuid;
  v_tenant_id uuid;
  v_actor_user_id uuid;
begin
  if p_external_input_tokens is null
     or p_external_output_tokens is null
     or p_external_meter_units is null
     or p_external_cost_microusd is null
     or p_external_input_tokens not between 0 and 100000000
     or p_external_output_tokens not between 0 and 100000000
     or p_external_meter_units not between 0 and 100000000
     or p_external_cost_microusd not between 0 and 1000000000000
     or not coalesce((
       (
         p_external_provider is null
         and p_external_model is null
         and p_external_usage_state is null
         and p_external_meter is null
         and p_external_input_tokens = 0
         and p_external_output_tokens = 0
         and p_external_meter_units = 0
         and p_external_cost_microusd = 0
       )
       or
       (
         p_tool_name = 'research_public_web'
         and p_risk = 'public_research'
         and p_external_provider in ('browser_use', 'gemini')
         and p_external_model is not null
         and octet_length(p_external_model) between 1 and 120
         and p_external_model ~ '^[A-Za-z0-9][A-Za-z0-9._:/-]*$'
         and p_external_usage_state in (
           'provider_reported', 'configured_estimate', 'unavailable'
         )
         and (
           (p_external_provider = 'browser_use'
             and p_external_meter = 'browser_step'
             and p_external_usage_state in ('provider_reported', 'unavailable'))
           or
           (p_external_provider = 'gemini'
             and p_external_meter = 'google_search_query'
             and p_external_usage_state in ('configured_estimate', 'unavailable'))
         )
       )
     ), false) then
    raise exception 'Invalid external tool usage' using errcode = '22023';
  end if;

  v_response := assistant_runtime.assistant_record_tool_receipt_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint,
    p_run_id, p_lease_token, p_fence_token, p_ordinal,
    p_provider_attempt_no, p_provider_call_hash, p_tool_name,
    p_tool_version, p_risk, p_policy_decision, p_status,
    p_arguments_hash, p_output_hash, p_result_count, p_output_bytes,
    p_approval_used, p_read_back_verified, p_failure_code,
    p_started_at, p_completed_at
  );

  v_receipt_id := (v_response ->> 'receiptId')::uuid;
  update public.assistant_tool_receipts receipt set
    external_provider = p_external_provider,
    external_model = p_external_model,
    external_usage_state = p_external_usage_state,
    external_input_tokens = p_external_input_tokens,
    external_output_tokens = p_external_output_tokens,
    external_meter = p_external_meter,
    external_meter_units = p_external_meter_units,
    external_cost_microusd = p_external_cost_microusd
  where receipt.id = v_receipt_id
    and receipt.run_id = p_run_id
  returning receipt.tenant_id, receipt.actor_user_id
  into strict v_tenant_id, v_actor_user_id;

  update public.assistant_runs run set
    input_tokens = run.input_tokens + p_external_input_tokens,
    output_tokens = run.output_tokens + p_external_output_tokens,
    estimated_cost_microusd = run.estimated_cost_microusd
      + p_external_cost_microusd,
    heartbeat_at = statement_timestamp()
  where run.id = p_run_id
    and run.tenant_id = v_tenant_id
    and run.actor_user_id = v_actor_user_id;

  -- External research usage belongs to the current accounting windows but is
  -- not a second model-provider attempt and does not consume that ordinal.
  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at,
    input_tokens, output_tokens, estimated_cost_microusd
  ) values
    (v_tenant_id, 'user', v_actor_user_id, 'five_minutes',
      date_bin('5 minutes', statement_timestamp(),
        '2000-01-01 00:00:00+00'::timestamptz),
      p_external_input_tokens, p_external_output_tokens, p_external_cost_microusd),
    (v_tenant_id, 'tenant', v_tenant_id, 'five_minutes',
      date_bin('5 minutes', statement_timestamp(),
        '2000-01-01 00:00:00+00'::timestamptz),
      p_external_input_tokens, p_external_output_tokens, p_external_cost_microusd),
    (v_tenant_id, 'user', v_actor_user_id, 'day',
      date_trunc('day', statement_timestamp()),
      p_external_input_tokens, p_external_output_tokens, p_external_cost_microusd),
    (v_tenant_id, 'tenant', v_tenant_id, 'day',
      date_trunc('day', statement_timestamp()),
      p_external_input_tokens, p_external_output_tokens, p_external_cost_microusd)
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    input_tokens = public.assistant_quota_buckets.input_tokens
      + excluded.input_tokens,
    output_tokens = public.assistant_quota_buckets.output_tokens
      + excluded.output_tokens,
    estimated_cost_microusd = public.assistant_quota_buckets.estimated_cost_microusd
      + excluded.estimated_cost_microusd,
    updated_at = statement_timestamp();

  return v_response;
end;
$$;

create or replace function assistant_runtime.assistant_record_tool_receipt_v2(
  p_envelope text,
  p_body text,
  p_mac_hex text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, assistant_runtime, pg_temp
as $$
declare
  v_attestation jsonb;
  v_body jsonb := p_body::jsonb;
  v_response jsonb;
  v_has_external_usage boolean;
begin
  v_has_external_usage := assistant_runtime.assistant_json_has_exact_keys_internal_v1(
    v_body, array[
    'p_actor_user_id', 'p_approval_used', 'p_arguments_hash',
    'p_authority_fingerprint', 'p_completed_at', 'p_external_cost_microusd',
    'p_external_input_tokens', 'p_external_meter', 'p_external_meter_units',
    'p_external_model', 'p_external_output_tokens', 'p_external_provider',
    'p_external_usage_state', 'p_failure_code', 'p_fence_token',
    'p_lease_token', 'p_ordinal', 'p_output_bytes', 'p_output_hash',
    'p_policy_decision', 'p_provider_attempt_no', 'p_provider_call_hash',
    'p_read_back_verified', 'p_result_count', 'p_risk', 'p_run_id',
    'p_started_at', 'p_status', 'p_tenant_id', 'p_tool_name', 'p_tool_version'
  ]);
  if not v_has_external_usage and not
    assistant_runtime.assistant_json_has_exact_keys_internal_v1(v_body, array[
      'p_actor_user_id', 'p_approval_used', 'p_arguments_hash',
      'p_authority_fingerprint', 'p_completed_at', 'p_failure_code',
      'p_fence_token', 'p_lease_token', 'p_ordinal', 'p_output_bytes',
      'p_output_hash', 'p_policy_decision', 'p_provider_attempt_no',
      'p_provider_call_hash', 'p_read_back_verified', 'p_result_count', 'p_risk',
      'p_run_id', 'p_started_at', 'p_status', 'p_tenant_id', 'p_tool_name',
      'p_tool_version'
    ]) then
    raise exception 'Invalid tool attestation body' using errcode = '22023';
  end if;
  v_attestation := assistant_runtime.assistant_verify_attestation_internal_v1(
    'assistant_record_tool_receipt_v2', p_envelope, p_body, p_mac_hex
  );
  if (v_attestation ->> 'replayed')::boolean then
    return v_attestation -> 'response';
  end if;
  v_response := assistant_runtime.assistant_record_tool_receipt_usage_v1(
    (v_body ->> 'p_tenant_id')::uuid,
    (v_body ->> 'p_actor_user_id')::uuid,
    v_body ->> 'p_authority_fingerprint',
    (v_body ->> 'p_run_id')::uuid,
    (v_body ->> 'p_lease_token')::uuid,
    (v_body ->> 'p_fence_token')::bigint,
    (v_body ->> 'p_ordinal')::integer,
    (v_body ->> 'p_provider_attempt_no')::integer,
    v_body ->> 'p_provider_call_hash',
    v_body ->> 'p_tool_name',
    v_body ->> 'p_tool_version',
    v_body ->> 'p_risk',
    v_body ->> 'p_policy_decision',
    v_body ->> 'p_status',
    v_body ->> 'p_arguments_hash',
    v_body ->> 'p_output_hash',
    (v_body ->> 'p_result_count')::integer,
    (v_body ->> 'p_output_bytes')::integer,
    (v_body ->> 'p_approval_used')::boolean,
    (v_body ->> 'p_read_back_verified')::boolean,
    v_body ->> 'p_failure_code',
    case when v_has_external_usage then v_body ->> 'p_external_provider' end,
    case when v_has_external_usage then v_body ->> 'p_external_model' end,
    case when v_has_external_usage then v_body ->> 'p_external_usage_state' end,
    case when v_has_external_usage
      then (v_body ->> 'p_external_input_tokens')::bigint else 0 end,
    case when v_has_external_usage
      then (v_body ->> 'p_external_output_tokens')::bigint else 0 end,
    case when v_has_external_usage then v_body ->> 'p_external_meter' end,
    case when v_has_external_usage
      then (v_body ->> 'p_external_meter_units')::integer else 0 end,
    case when v_has_external_usage
      then (v_body ->> 'p_external_cost_microusd')::bigint else 0 end,
    (v_body ->> 'p_started_at')::timestamptz,
    (v_body ->> 'p_completed_at')::timestamptz
  );
  return assistant_runtime.assistant_store_attestation_response_internal_v1(
    v_attestation, v_response
  );
end;
$$;

revoke all on function assistant_runtime.assistant_record_tool_receipt_usage_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer, integer, text, text, text,
  text, text, text, text, text, integer, integer, boolean, boolean, text,
  text, text, text, bigint, bigint, text, integer, bigint,
  timestamptz, timestamptz
) from public, anon, authenticated, service_role;

revoke all on function assistant_runtime.assistant_record_tool_receipt_v2(
  text, text, text
) from public, anon, authenticated, service_role;
grant execute on function assistant_runtime.assistant_record_tool_receipt_v2(
  text, text, text
) to authenticated;

comment on function assistant_runtime.assistant_record_tool_receipt_usage_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer, integer, text, text, text,
  text, text, text, text, text, integer, integer, boolean, boolean, text,
  text, text, text, bigint, bigint, text, integer, bigint,
  timestamptz, timestamptz
) is 'Internal receipt owner that atomically adds bounded external public-research usage to run and current quota buckets without creating a provider attempt.';
comment on table public.assistant_tool_receipts is
  'Hash-only tool evidence plus bounded server-owned external usage for isolated public research; raw arguments, outputs and provider payloads remain request-local.';

commit;
