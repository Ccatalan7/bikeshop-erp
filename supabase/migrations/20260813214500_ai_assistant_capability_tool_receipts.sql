-- Keep the durable receipt allowlist synchronized with the model-visible
-- capability catalog. Unknown names remain rejected; the two new primitives
-- are read-only and keep the same hash-only receipt boundary.
begin;

create or replace function assistant_runtime.assistant_record_tool_receipt_v1(
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
  p_output_hash text default null,
  p_result_count integer default 0,
  p_output_bytes integer default 0,
  p_approval_used boolean default false,
  p_read_back_verified boolean default false,
  p_failure_code text default null,
  p_started_at timestamptz default statement_timestamp(),
  p_completed_at timestamptz default statement_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_authority record;
  v_run public.assistant_runs%rowtype;
  v_attempt_id uuid;
  v_receipt_id uuid;
  v_prior_output_bytes bigint;
begin
  select * into strict v_authority
  from public.assistant_server_authority_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint
  );
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));
  v_run := public.assistant_assert_live_lease_internal_v1(
    p_tenant_id, p_actor_user_id, p_authority_fingerprint,
    p_run_id, p_lease_token, p_fence_token
  );
  select attempt.id into v_attempt_id
  from public.assistant_provider_attempts attempt
  where attempt.run_id = p_run_id
    and attempt.attempt_no = p_provider_attempt_no
    and attempt.status = 'succeeded'
    and attempt.finish_reason = 'tool_calls';
  if v_attempt_id is null then
    raise exception 'Provider attempt is unavailable for tool receipt'
      using errcode = '22023';
  end if;
  select coalesce(sum(receipt.output_bytes), 0)
  into v_prior_output_bytes
  from public.assistant_tool_receipts receipt
  where receipt.run_id = p_run_id;
  if p_ordinal <> coalesce((
       select max(receipt.ordinal) + 1
       from public.assistant_tool_receipts receipt
       where receipt.run_id = p_run_id
     ), 1)
     or p_ordinal > v_run.tool_call_budget
     or p_result_count not between 0 and 10
     or p_output_bytes not between 0 and 49152
     or v_prior_output_bytes > 98304
     or v_prior_output_bytes + p_output_bytes > 147456
     or (v_prior_output_bytes + p_output_bytes > 98304 and (
       p_status <> 'failed'
       or p_failure_code <> 'run_tool_output_budget_exhausted'
       or p_read_back_verified is not false
     ))
     or p_tool_name not in (
       'inspect_inventory_schema', 'search_inventory',
       'list_attention_items', 'get_business_snapshot',
       'search_workshop_jobs', 'search_tasks', 'search_customers',
       'search_suppliers', 'search_sales_invoices',
       'search_purchase_invoices', 'find_inventory_risks',
       'list_recent_expenses', 'analyze_cash_and_receivables',
       'search_conversations', 'research_public_web', 'prepare_task',
       'report_capability_gap'
     )
     or p_tool_version <> 'v1'
     or not (
       (p_tool_name = 'research_public_web'
         and p_risk = 'public_research' and p_policy_decision = 'allowed')
       or (p_tool_name = 'prepare_task'
         and p_risk = 'draft' and p_policy_decision = 'approval_required')
       or (p_tool_name not in ('research_public_web', 'prepare_task')
         and p_risk = 'read' and p_policy_decision = 'allowed')
     )
     or p_approval_used is not false
     or p_status not in ('succeeded', 'rejected', 'failed', 'timed_out', 'cancelled')
     or (p_status = 'succeeded' and
       (p_failure_code is not null or p_output_hash is null
        or p_read_back_verified is not true))
     or (p_status <> 'succeeded' and p_failure_code is null)
     or p_started_at is null or p_completed_at is null
     or p_started_at < statement_timestamp() - interval '10 minutes'
     or p_started_at > statement_timestamp() + interval '1 minute'
     or p_completed_at < p_started_at
     or p_completed_at > statement_timestamp() + interval '1 minute' then
    raise exception 'Invalid tool receipt counters' using errcode = '22023';
  end if;

  insert into public.assistant_tool_receipts (
    tenant_id, actor_user_id, run_id, provider_attempt_id, ordinal,
    provider_call_hash, tool_name, tool_version, risk, policy_decision,
    status, arguments_hash, output_hash, result_count, output_bytes,
    approval_used, read_back_verified, failure_code, started_at, completed_at
  ) values (
    v_run.tenant_id, v_run.actor_user_id, v_run.id, v_attempt_id, p_ordinal,
    p_provider_call_hash, p_tool_name, p_tool_version, p_risk,
    p_policy_decision, p_status, p_arguments_hash, p_output_hash,
    p_result_count, p_output_bytes, p_approval_used, p_read_back_verified,
    p_failure_code, p_started_at, p_completed_at
  ) returning id into v_receipt_id;

  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at, tool_call_count
  ) values
    (v_run.tenant_id, 'user', v_run.actor_user_id, 'five_minutes',
      date_bin('5 minutes', statement_timestamp(),
        '2000-01-01 00:00:00+00'::timestamptz), 1),
    (v_run.tenant_id, 'tenant', v_run.tenant_id, 'five_minutes',
      date_bin('5 minutes', statement_timestamp(),
        '2000-01-01 00:00:00+00'::timestamptz), 1),
    (v_run.tenant_id, 'user', v_run.actor_user_id, 'day',
      date_trunc('day', statement_timestamp()), 1),
    (v_run.tenant_id, 'tenant', v_run.tenant_id, 'day',
      date_trunc('day', statement_timestamp()), 1)
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    tool_call_count = public.assistant_quota_buckets.tool_call_count + 1,
    updated_at = statement_timestamp();

  return jsonb_build_object(
    'authorityTenantId', v_run.tenant_id,
    'runId', v_run.id,
    'receiptId', v_receipt_id,
    'ordinal', p_ordinal,
    'status', p_status
  );
end;
$$;

revoke all on function assistant_runtime.assistant_record_tool_receipt_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer, integer, text, text, text,
  text, text, text, text, text, integer, integer, boolean, boolean, text,
  timestamptz, timestamptz
) from public, anon, authenticated, service_role;

comment on function assistant_runtime.assistant_record_tool_receipt_v1(
  uuid, uuid, text, uuid, uuid, bigint, integer, integer, text, text, text,
  text, text, text, text, text, integer, integer, boolean, boolean, text,
  timestamptz, timestamptz
) is 'Internal durable hash-only receipt writer for the closed assistant capability catalog.';

commit;
