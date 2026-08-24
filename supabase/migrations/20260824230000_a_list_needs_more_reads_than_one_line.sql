-- Una lista necesita más lecturas que una línea.
--
-- Medido en el módulo real, con «necesito pastillas de freno shimano, líquido
-- sellante tubeless y cámaras 29» escrito en el compositor del Asistente de
-- compras:
--
--   1-3  search_inventory          (una por línea)
--   4-6  inspect_inventory_schema  (una por línea)
--   7-8  search_inventory          (reintento tras schema_discovery_required)
--   ——   presupuesto agotado; `prepare_supply_request` NUNCA se llamó
--
-- El operador vio «no pude cerrar el análisis con evidencia suficiente» y su
-- lista de tres cosas se perdió entera. No falló ninguna herramienta: las ocho
-- corrieron bien. Faltó presupuesto, y el tope de 8 está calibrado para UNA
-- necesidad.

begin;

CREATE OR REPLACE FUNCTION public.assistant_begin_run_v1(p_client_request_id uuid, p_request_hash text, p_user_content text, p_model_role text, p_thread_id uuid DEFAULT NULL::uuid, p_turn_budget integer DEFAULT 5, p_tool_call_budget integer DEFAULT 8, p_max_output_tokens integer DEFAULT 2048, p_lease_owner text DEFAULT 'ai-agent-gateway-v1'::text, p_lease_ttl_seconds integer DEFAULT 110)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_authority record;
  v_existing public.assistant_runs%rowtype;
  v_thread public.assistant_threads%rowtype;
  v_run_id uuid;
  v_request_message_id uuid;
  v_run_no integer;
  v_sequence_no integer;
  v_lease_token uuid;
  v_fence_token bigint;
  v_lease_expires_at timestamptz;
  v_admitted boolean;
  v_live_count integer;
begin
  select * into strict v_authority
  from public.assistant_current_authority_internal_v1();

  if p_client_request_id is null
     or coalesce(p_request_hash, '') !~ '^[0-9a-f]{64}$'
     or octet_length(coalesce(p_user_content, '')) not between 1 and 8192
     or p_model_role not in ('fast', 'deep', 'vision')
     or p_turn_budget <> 5
     or p_tool_call_budget not in (8, 18)
     -- 18 sólo para el Asistente de compras, que es la superficie donde el
     -- taller escribe varias necesidades de una vez: dos lecturas por línea en
     -- las ocho líneas que el borrador permite, más el borrador. Sigue siendo
     -- una lista cerrada y no un número libre del cliente.
     or p_max_output_tokens not between 64 and 8192
     or p_lease_owner <> 'ai-agent-gateway-v1'
     or p_lease_ttl_seconds <> 110 then
    raise exception 'Invalid assistant run request' using errcode = '22023';
  end if;

  -- Serialize identical client request ids before the replay lookup.  Without
  -- this lock two first requests can both miss and race on the unique index.
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:request:' || v_authority.actor_user_id::text || ':'
      || p_client_request_id::text, 0
  ));
  -- Every admission/replay/reclaim follows request -> tenant -> user advisory
  -- order before touching ledger rows. This also makes concurrency admission
  -- deterministic under a duplicate request race.
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:tenant:' || v_authority.tenant_id::text, 0
  ));
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:user:' || v_authority.actor_user_id::text, 0
  ));

  select * into v_existing
  from public.assistant_runs run
  where run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.client_request_id = p_client_request_id
  for update;

  if found then
    if v_existing.request_hash <> p_request_hash then
      raise exception 'Client request id was already used with different content'
        using errcode = '22023';
    end if;
    if v_existing.authority_fingerprint <> v_authority.authority_fingerprint then
      raise exception 'Assistant authority changed; start a new thread'
        using errcode = '42501';
    end if;
    if v_existing.expires_at <= statement_timestamp() then
      raise exception 'Assistant run is unavailable' using errcode = '42501';
    end if;
    if not exists (
      select 1 from public.assistant_threads thread
      where thread.id = v_existing.thread_id
        and thread.state = 'active'
        and thread.authority_fingerprint = v_authority.authority_fingerprint
        and thread.transcript_expires_at > statement_timestamp()
        and thread.ledger_expires_at > statement_timestamp()
    ) then
      raise exception 'Assistant thread is unavailable' using errcode = '42501';
    end if;
    if v_existing.status = 'succeeded' and not exists (
      select 1 from public.assistant_messages response
      where response.id = v_existing.response_message_id
        and response.thread_id = v_existing.thread_id
        and response.role = 'assistant'
        and response.expires_at > statement_timestamp()
    ) then
      raise exception 'Assistant terminal response is unavailable'
        using errcode = '42501';
    end if;

    if v_existing.status in ('queued', 'running', 'waiting_tool') then
      select lease.lease_token, lease.fence_token, lease.lease_expires_at
      into v_lease_token, v_fence_token, v_lease_expires_at
      from public.assistant_run_leases lease
      where lease.run_id = v_existing.id
      for update;

      if not found or v_lease_expires_at <= statement_timestamp() then
        select count(*) into v_live_count
        from public.assistant_runs run
        join public.assistant_run_leases lease on lease.run_id = run.id
        where run.tenant_id = v_authority.tenant_id
          and run.id <> v_existing.id
          and run.status in ('queued', 'running', 'waiting_tool')
          and lease.lease_expires_at > statement_timestamp();
        if v_live_count >= 4 then
          raise exception 'Assistant tenant concurrency limit reached' using errcode = 'P0001';
        end if;
        select count(*) into v_live_count
        from public.assistant_runs run
        join public.assistant_run_leases lease on lease.run_id = run.id
        where run.tenant_id = v_authority.tenant_id
          and run.actor_user_id = v_authority.actor_user_id
          and run.id <> v_existing.id
          and run.status in ('queued', 'running', 'waiting_tool')
          and lease.lease_expires_at > statement_timestamp();
        if v_live_count >= 2 then
          raise exception 'Assistant user concurrency limit reached' using errcode = 'P0001';
        end if;
        v_lease_token := gen_random_uuid();
        v_lease_expires_at := statement_timestamp()
          + make_interval(secs => p_lease_ttl_seconds);
        insert into public.assistant_run_leases (
          run_id, tenant_id, actor_user_id, lease_token, fence_token,
          lease_owner, acquired_at, heartbeat_at, lease_expires_at
        ) values (
          v_existing.id, v_authority.tenant_id, v_authority.actor_user_id,
          v_lease_token, coalesce(v_fence_token, 0) + 1, p_lease_owner,
          statement_timestamp(), statement_timestamp(), v_lease_expires_at
        )
        on conflict (run_id) do update set
          lease_token = excluded.lease_token,
          fence_token = public.assistant_run_leases.fence_token + 1,
          lease_owner = excluded.lease_owner,
          acquired_at = excluded.acquired_at,
          heartbeat_at = excluded.heartbeat_at,
          lease_expires_at = excluded.lease_expires_at
        returning fence_token into v_fence_token;
        update public.assistant_runs set heartbeat_at = statement_timestamp()
        where id = v_existing.id;
      else
        return public.assistant_run_snapshot_internal_v1(
          v_existing.id, true, null, null, null
        ) || jsonb_build_object(
          'runDisposition', 'in_progress', 'terminalErrorCode', null
        );
      end if;
    else
      v_lease_token := null;
      v_fence_token := null;
      v_lease_expires_at := null;
    end if;

    return public.assistant_run_snapshot_internal_v1(
      v_existing.id, true, v_lease_token, v_fence_token, v_lease_expires_at
    ) || jsonb_build_object(
      'runDisposition', case when v_lease_token is null then 'terminal' else 'claimed' end,
      'terminalErrorCode', v_existing.error_code
    );
  end if;

  -- Serialize admission for this tenant and operator.  The counts include only
  -- live, non-expired worker leases; an abandoned run becomes reclaimable.
  select count(*) into v_live_count
  from public.assistant_runs run
  join public.assistant_run_leases lease on lease.run_id = run.id
  where run.tenant_id = v_authority.tenant_id
    and run.status in ('queued', 'running', 'waiting_tool')
    and lease.lease_expires_at > statement_timestamp();
  if v_live_count >= 4 then
    raise exception 'Assistant tenant concurrency limit reached' using errcode = 'P0001';
  end if;
  select count(*) into v_live_count
  from public.assistant_runs run
  join public.assistant_run_leases lease on lease.run_id = run.id
  where run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.status in ('queued', 'running', 'waiting_tool')
    and lease.lease_expires_at > statement_timestamp();
  if v_live_count >= 2 then
    raise exception 'Assistant user concurrency limit reached' using errcode = 'P0001';
  end if;

  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at, request_count
  ) values (
    v_authority.tenant_id, 'user', v_authority.actor_user_id,
    'five_minutes', date_bin('5 minutes', statement_timestamp(),
      '2000-01-01 00:00:00+00'::timestamptz), 1
  )
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    request_count = public.assistant_quota_buckets.request_count + 1,
    updated_at = statement_timestamp()
  where public.assistant_quota_buckets.request_count < 10
  returning true into v_admitted;
  if coalesce(v_admitted, false) is not true then
    raise exception 'Assistant request quota exceeded' using errcode = 'P0001';
  end if;
  v_admitted := null;
  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at, request_count
  ) values (
    v_authority.tenant_id, 'tenant', v_authority.tenant_id,
    'five_minutes', date_bin('5 minutes', statement_timestamp(),
      '2000-01-01 00:00:00+00'::timestamptz), 1
  )
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    request_count = public.assistant_quota_buckets.request_count + 1,
    updated_at = statement_timestamp()
  where public.assistant_quota_buckets.request_count < 30
  returning true into v_admitted;
  if coalesce(v_admitted, false) is not true then
    raise exception 'Assistant tenant quota exceeded' using errcode = 'P0001';
  end if;
  v_admitted := null;
  insert into public.assistant_quota_buckets (
    tenant_id, scope, scope_id, period, window_started_at, request_count
  ) values
    (v_authority.tenant_id, 'user', v_authority.actor_user_id, 'day',
      date_trunc('day', statement_timestamp()), 1),
    (v_authority.tenant_id, 'tenant', v_authority.tenant_id, 'day',
      date_trunc('day', statement_timestamp()), 1)
  on conflict (tenant_id, scope, scope_id, period, window_started_at) do update set
    request_count = public.assistant_quota_buckets.request_count + 1,
    updated_at = statement_timestamp();
  -- Five-minute buckets above are hard admission controls (10/user,
  -- 30/tenant). Day buckets are accounting telemetry for capacity review;
  -- they intentionally do not claim to be an enforced daily quota.

  if p_thread_id is null then
    insert into public.assistant_threads (
      tenant_id, actor_user_id, authority_role, authority_fingerprint
    ) values (
      v_authority.tenant_id, v_authority.actor_user_id,
      v_authority.authority_role, v_authority.authority_fingerprint
    ) returning * into v_thread;
  else
    select * into v_thread
    from public.assistant_threads thread
    where thread.id = p_thread_id
      and thread.tenant_id = v_authority.tenant_id
      and thread.actor_user_id = v_authority.actor_user_id
      and thread.state = 'active'
      and thread.authority_fingerprint = v_authority.authority_fingerprint
      and thread.transcript_expires_at > statement_timestamp()
      and thread.ledger_expires_at > statement_timestamp()
    for update;
    if not found then
      raise exception 'Assistant thread is unavailable' using errcode = '42501';
    end if;
  end if;

  select coalesce(max(run.run_no), 0) + 1 into v_run_no
  from public.assistant_runs run where run.thread_id = v_thread.id;
  select coalesce(max(message.sequence_no), 0) + 1 into v_sequence_no
  from public.assistant_messages message where message.thread_id = v_thread.id;

  insert into public.assistant_messages (
    tenant_id, actor_user_id, thread_id, sequence_no, role, content
  ) values (
    v_authority.tenant_id, v_authority.actor_user_id, v_thread.id,
    v_sequence_no, 'user', p_user_content
  ) returning id into v_request_message_id;

  insert into public.assistant_runs (
    tenant_id, actor_user_id, thread_id, run_no, client_request_id,
    request_hash, request_message_id, model_role, status, authority_role,
    authority_fingerprint, turn_budget, provider_attempt_budget,
    tool_call_budget, max_output_tokens
  ) values (
    v_authority.tenant_id, v_authority.actor_user_id, v_thread.id, v_run_no,
    p_client_request_id, p_request_hash, v_request_message_id, p_model_role,
    'running', v_authority.authority_role, v_authority.authority_fingerprint,
    p_turn_budget, 2 * (p_turn_budget + 1), p_tool_call_budget, p_max_output_tokens
  ) returning id into v_run_id;

  update public.assistant_messages set run_id = v_run_id
  where id = v_request_message_id;
  update public.assistant_threads set
    updated_at = statement_timestamp(),
    last_activity_at = statement_timestamp(),
    transcript_expires_at = greatest(
      transcript_expires_at, statement_timestamp() + interval '90 days'
    ),
    ledger_expires_at = greatest(
      ledger_expires_at, statement_timestamp() + interval '365 days'
    )
  where id = v_thread.id;

  v_lease_token := gen_random_uuid();
  v_fence_token := 1;
  v_lease_expires_at := statement_timestamp()
    + make_interval(secs => p_lease_ttl_seconds);
  insert into public.assistant_run_leases (
    run_id, tenant_id, actor_user_id, lease_token, fence_token,
    lease_owner, lease_expires_at
  ) values (
    v_run_id, v_authority.tenant_id, v_authority.actor_user_id,
    v_lease_token, v_fence_token, p_lease_owner, v_lease_expires_at
  );

  return public.assistant_run_snapshot_internal_v1(
    v_run_id, false, v_lease_token, v_fence_token, v_lease_expires_at
  ) || jsonb_build_object('runDisposition', 'claimed', 'terminalErrorCode', null);
end;
$function$
;

commit;
