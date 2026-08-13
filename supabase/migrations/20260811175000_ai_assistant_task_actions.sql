-- First general, approval-gated AI action: prepare and explicitly confirm a
-- normal ERP task. The model can only call prepare_task. The confirmation RPC
-- accepts no task payload, re-derives the caller and authority fingerprint,
-- consumes one durable 10-minute approval, inserts/read-backs the task and
-- records the reversible write atomically.

begin;

create table if not exists public.assistant_approvals (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  actor_user_id uuid not null,
  thread_id uuid not null,
  run_id uuid not null,
  provider_attempt_id uuid not null,
  provider_call_hash text not null check (provider_call_hash ~ '^[0-9a-f]{64}$'),
  arguments_hash text not null check (arguments_hash ~ '^[0-9a-f]{64}$'),
  authority_fingerprint text not null
    check (authority_fingerprint ~ '^[0-9a-f]{64}$'),
  action_name text not null check (action_name = 'create_task'),
  action_payload jsonb not null,
  state text not null default 'pending'
    check (state in ('pending', 'approved', 'discarded', 'expired')),
  client_action_id uuid,
  decision text check (decision is null or decision in ('approve', 'discard')),
  decision_response jsonb,
  created_entity_id uuid,
  action_receipt_id uuid,
  created_at timestamptz not null default statement_timestamp(),
  expires_at timestamptz not null,
  decided_at timestamptz,
  updated_at timestamptz not null default statement_timestamp(),
  unique (run_id, provider_call_hash),
  foreign key (tenant_id, actor_user_id, thread_id)
    references public.assistant_threads(tenant_id, actor_user_id, id)
    on delete cascade,
  foreign key (tenant_id, actor_user_id, run_id)
    references public.assistant_runs(tenant_id, actor_user_id, id)
    on delete cascade,
  foreign key (provider_attempt_id)
    references public.assistant_provider_attempts(id)
    on delete cascade,
  foreign key (action_receipt_id)
    references public.assistant_tool_receipts(id)
    on delete set null,
  check (expires_at = created_at + interval '10 minutes'),
  check (
    (state = 'pending' and client_action_id is null and decision is null
      and decision_response is null and created_entity_id is null
      and action_receipt_id is null and decided_at is null)
    or
    (state = 'approved' and client_action_id is not null and decision = 'approve'
      and decision_response is not null and created_entity_id is not null
      and action_receipt_id is not null and decided_at is not null)
    or
    (state in ('discarded', 'expired') and client_action_id is not null
      and decision is not null and decision_response is not null
      and created_entity_id is null and action_receipt_id is null
      and decided_at is not null)
  )
);

create unique index if not exists assistant_approvals_actor_client_action_uidx
  on public.assistant_approvals(tenant_id, actor_user_id, client_action_id)
  where client_action_id is not null;
create index if not exists assistant_approvals_pending_expiry_idx
  on public.assistant_approvals(expires_at)
  where state = 'pending';

alter table public.assistant_approvals enable row level security;
alter table public.assistant_approvals force row level security;
revoke all on table public.assistant_approvals
from public, anon, authenticated, service_role;

create or replace function public.assistant_cards_valid_v1(p_cards jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_card jsonb;
  v_chip jsonb;
  v_entity_ref jsonb;
  v_approval_ref jsonb;
  v_kind text;
  v_destination text;
begin
  if p_cards is null or jsonb_typeof(p_cards) <> 'array'
     or jsonb_array_length(p_cards) > 6 then
    return false;
  end if;
  for v_card in select value from jsonb_array_elements(p_cards) element(value)
  loop
    if jsonb_typeof(v_card) <> 'object'
       or not (v_card ? 'kind' and v_card ? 'title'
         and v_card ? 'destination' and v_card ? 'chips')
       or jsonb_typeof(v_card -> 'kind') <> 'string'
       or jsonb_typeof(v_card -> 'title') <> 'string'
       or jsonb_typeof(v_card -> 'destination') <> 'string'
       or jsonb_typeof(v_card -> 'chips') <> 'array'
       or (v_card ? 'eyebrow' and jsonb_typeof(v_card -> 'eyebrow') <> 'string')
       or (v_card ? 'subtitle' and jsonb_typeof(v_card -> 'subtitle') <> 'string')
       or (v_card ? 'description' and jsonb_typeof(v_card -> 'description') <> 'string')
       or (v_card ? 'entityRef' and jsonb_typeof(v_card -> 'entityRef') <> 'object')
       or (v_card ? 'approvalRef' and jsonb_typeof(v_card -> 'approvalRef') <> 'object')
       or exists (
         select 1 from jsonb_object_keys(v_card) key
         where key not in (
           'kind', 'title', 'destination', 'eyebrow', 'subtitle',
           'description', 'chips', 'entityRef', 'approvalRef'
         )
       ) then
      return false;
    end if;
    v_kind := v_card ->> 'kind';
    v_destination := v_card ->> 'destination';
    if v_kind !~ '^[a-z][a-z0-9_]{0,31}$'
       or octet_length(v_kind) > 32
       or octet_length(v_card ->> 'title') not between 1 and 160
       or octet_length(coalesce(v_card ->> 'eyebrow', '')) > 80
       or octet_length(coalesce(v_card ->> 'subtitle', '')) > 240
       or octet_length(coalesce(v_card ->> 'description', '')) > 500
       or not (
         (v_kind = 'customer' and v_destination = 'customers')
         or (v_kind = 'supplier' and v_destination = 'suppliers')
         or (v_kind = 'job' and v_destination = 'workshop_jobs')
         or (v_kind = 'sales_invoice' and v_destination = 'sales_invoices')
         or (v_kind = 'purchase_invoice' and v_destination = 'purchases')
         or (v_kind = 'inventory' and v_destination = 'inventory_products')
         or (v_kind in ('task', 'task_preview') and v_destination = 'tasks')
         or (v_kind = 'expense' and v_destination = 'expenses')
         or (v_kind = 'conversation' and v_destination = 'conversations')
       )
       or jsonb_array_length(v_card -> 'chips') > 4 then
      return false;
    end if;
    if v_card ? 'entityRef' then
      v_entity_ref := v_card -> 'entityRef';
      if v_kind = 'task_preview'
         or not (v_entity_ref ? 'kind' and v_entity_ref ? 'id')
         or jsonb_typeof(v_entity_ref -> 'kind') <> 'string'
         or jsonb_typeof(v_entity_ref -> 'id') <> 'string'
         or exists (
           select 1 from jsonb_object_keys(v_entity_ref) key
           where key not in ('kind', 'id')
         )
         or lower(v_entity_ref ->> 'id') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or not (
           (v_kind = 'customer' and v_entity_ref ->> 'kind' = 'customer')
           or (v_kind = 'supplier' and v_entity_ref ->> 'kind' = 'supplier')
           or (v_kind = 'job' and v_entity_ref ->> 'kind' = 'workshopJob')
           or (v_kind = 'sales_invoice' and v_entity_ref ->> 'kind' = 'salesInvoice')
           or (v_kind = 'purchase_invoice' and v_entity_ref ->> 'kind' = 'purchaseInvoice')
           or (v_kind = 'inventory' and v_entity_ref ->> 'kind' = 'product')
           or (v_kind = 'expense' and v_entity_ref ->> 'kind' = 'expense')
           or (v_kind = 'conversation' and v_entity_ref ->> 'kind' = 'conversation')
         ) then
        return false;
      end if;
    end if;
    if v_kind = 'task_preview' then
      if not (v_card ? 'approvalRef') then
        return false;
      end if;
      v_approval_ref := v_card -> 'approvalRef';
      if not (v_approval_ref ? 'id' and v_approval_ref ? 'action'
          and v_approval_ref ? 'state' and v_approval_ref ? 'expiresAt')
         or exists (
           select 1 from jsonb_object_keys(v_approval_ref) key
           where key not in ('id', 'action', 'state', 'expiresAt')
         )
         or jsonb_typeof(v_approval_ref -> 'id') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'action') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'state') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'expiresAt') <> 'string'
         or lower(v_approval_ref ->> 'id') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or v_approval_ref ->> 'action' <> 'create_task'
         or v_approval_ref ->> 'state' not in (
           'pending', 'approved', 'discarded', 'expired'
         )
         or v_approval_ref ->> 'expiresAt' !~
           '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.]\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
        return false;
      end if;
    elsif v_card ? 'approvalRef' then
      return false;
    end if;
    for v_chip in select value
      from jsonb_array_elements(v_card -> 'chips') element(value)
    loop
      if jsonb_typeof(v_chip) <> 'string'
         or octet_length(v_chip #>> '{}') not between 1 and 64 then
        return false;
      end if;
    end loop;
  end loop;
  return true;
end;
$$;

revoke all on function public.assistant_cards_valid_v1(jsonb)
from public, anon, authenticated, service_role;

create or replace function public.assistant_prepare_task_v1(
  p_title text,
  p_description text,
  p_priority text,
  p_due_at text,
  p_assignee_mode text,
  p_assignee_name text,
  p_run_id uuid,
  p_provider_attempt_no integer,
  p_provider_call_hash text,
  p_arguments_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_run record;
  v_attempt record;
  v_existing record;
  v_approval record;
  v_title text := btrim(coalesce(p_title, ''));
  v_description text := nullif(btrim(coalesce(p_description, '')), '');
  v_due_at timestamptz;
  v_assigned_to uuid;
  v_assignee_label text;
  v_name_count integer;
  v_payload jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_current_authority_internal_v1() authority;

  if octet_length(v_title) not between 1 and 160
     or (p_description is not null and v_description is null)
     or octet_length(coalesce(v_description, '')) > 2000
     or p_priority not in ('low', 'normal', 'high', 'urgent')
     or p_assignee_mode not in ('me', 'unassigned', 'name')
     or (p_assignee_mode = 'name') <> (nullif(btrim(p_assignee_name), '') is not null)
     or octet_length(coalesce(nullif(btrim(p_assignee_name), ''), '')) > 160
     or coalesce(p_provider_call_hash, '') !~ '^[0-9a-f]{64}$'
     or coalesce(p_arguments_hash, '') !~ '^[0-9a-f]{64}$'
     or p_provider_attempt_no is null or p_provider_attempt_no not between 1 and 42 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  if p_due_at is not null then
    if octet_length(p_due_at) not between 20 and 40
       or p_due_at !~
         '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.]\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    begin
      v_due_at := p_due_at::timestamptz;
    exception when others then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end;
  end if;

  select run.id, run.tenant_id, run.actor_user_id, run.thread_id
  into v_run
  from public.assistant_runs run
  where run.id = p_run_id
    and run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.authority_fingerprint = v_authority.authority_fingerprint
    and run.status in ('running', 'waiting_tool')
    and run.expires_at > statement_timestamp();
  if not found then
    raise exception 'Assistant run is unavailable' using errcode = '42501';
  end if;
  select attempt.id into v_attempt
  from public.assistant_provider_attempts attempt
  where attempt.run_id = v_run.id
    and attempt.attempt_no = p_provider_attempt_no
    and attempt.status = 'succeeded'
    and attempt.finish_reason = 'tool_calls';
  if not found then
    raise exception 'Assistant provider attempt is unavailable'
      using errcode = '42501';
  end if;

  if p_assignee_mode = 'me' then
    v_assigned_to := v_authority.actor_user_id;
    v_assignee_label := 'Tú';
  elsif p_assignee_mode = 'unassigned' then
    v_assigned_to := null;
    v_assignee_label := 'Sin asignar';
  else
    if not public.can_manage_tenant_users(v_authority.tenant_id) then
      raise exception 'Named task assignment is not allowed' using errcode = '42501';
    end if;
    with candidates as (
      select profile.user_id,
        coalesce(
          nullif(btrim(concat_ws(' ', employee.first_name, employee.last_name)), ''),
          nullif(split_part(auth_user.email, '@', 1), '')
        ) display_name,
        nullif(btrim(employee.first_name), '') first_name,
        nullif(split_part(auth_user.email, '@', 1), '') email_name
      from public.user_profiles profile
      join auth.users auth_user on auth_user.id = profile.user_id
      left join public.employees employee
        on employee.tenant_id = profile.tenant_id
       and (
         employee.id = profile.employee_id
         or (profile.employee_id is null and employee.user_id = profile.user_id)
       )
      where profile.tenant_id = v_authority.tenant_id
        and profile.is_active is true
        and (profile.employee_id is null or employee.status = 'active')
    ), exact_candidates as (
      select candidate.user_id, candidate.display_name
      from candidates candidate
      where lower(regexp_replace(btrim(p_assignee_name), '\s+', ' ', 'g')) in (
        lower(regexp_replace(btrim(candidate.display_name), '\s+', ' ', 'g')),
        lower(regexp_replace(btrim(candidate.first_name), '\s+', ' ', 'g')),
        lower(regexp_replace(btrim(candidate.email_name), '\s+', ' ', 'g'))
      )
    )
    select count(*), min(user_id::text)::uuid, min(display_name)
    into v_name_count, v_assigned_to, v_assignee_label
    from exact_candidates;
    if v_name_count <> 1 or v_assigned_to is null then
      raise exception 'Named task assignee is unavailable' using errcode = '42501';
    end if;
  end if;

  v_payload := jsonb_build_object(
    'title', v_title,
    'description', v_description,
    'priority', p_priority,
    'dueAt', p_due_at,
    'dueAtValue', v_due_at,
    'assigneeMode', p_assignee_mode,
    'assignedTo', v_assigned_to,
    'assigneeName', v_assignee_label
  );

  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:prepare-task:' || v_run.id::text || ':' || p_provider_call_hash, 0
  ));
  select approval.id, approval.action_name, approval.state,
    approval.expires_at, approval.arguments_hash, approval.action_payload,
    approval.authority_fingerprint
  into v_existing
  from public.assistant_approvals approval
  where approval.run_id = v_run.id
    and approval.provider_call_hash = p_provider_call_hash
  for update;
  if found then
    if v_existing.arguments_hash <> p_arguments_hash
       or v_existing.action_payload <> v_payload
       or v_existing.authority_fingerprint <> v_authority.authority_fingerprint then
      raise exception 'AI preparation idempotency conflict' using errcode = '22023';
    end if;
    v_approval := v_existing;
  else
    insert into public.assistant_approvals (
      tenant_id, actor_user_id, thread_id, run_id, provider_attempt_id,
      provider_call_hash, arguments_hash, authority_fingerprint,
      action_name, action_payload, created_at, expires_at
    ) values (
      v_run.tenant_id, v_run.actor_user_id, v_run.thread_id, v_run.id,
      v_attempt.id, p_provider_call_hash, p_arguments_hash,
      v_authority.authority_fingerprint, 'create_task', v_payload,
      statement_timestamp(), statement_timestamp() + interval '10 minutes'
    ) returning id, action_name, state, expires_at, arguments_hash,
      action_payload, authority_fingerprint into v_approval;
  end if;

  return jsonb_build_object(
    'authorityTenantId', v_authority.tenant_id,
    'asOf', statement_timestamp(),
    'status', 'success',
    'items', jsonb_build_array(jsonb_build_object(
      'approvalId', v_approval.id,
      'action', v_approval.action_name,
      'state', v_approval.state,
      'title', v_payload ->> 'title',
      'description', v_payload -> 'description',
      'priority', v_payload ->> 'priority',
      'dueAt', v_payload -> 'dueAt',
      'assigneeMode', v_payload ->> 'assigneeMode',
      'assigneeName', v_payload ->> 'assigneeName',
      'expiresAt', to_char(v_approval.expires_at at time zone 'UTC',
        'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    )),
    'resultCount', 1,
    'hasMore', false
  );
end;
$$;

create or replace function public.assistant_apply_task_approval_v1(
  p_approval_id uuid,
  p_action text,
  p_client_action_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_approval record;
  v_run record;
  v_payload jsonb;
  v_task_id uuid;
  v_task_projection jsonb;
  v_response jsonb;
  v_receipt_id uuid;
  v_receipt_ordinal integer;
  v_action_call_hash text;
  v_output_hash text;
  v_now timestamptz := statement_timestamp();
  v_final_state text;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_current_authority_internal_v1() authority;
  if p_approval_id is null or p_client_action_id is null
     or p_action not in ('approve', 'discard') then
    raise exception 'Invalid approval action' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:approval-action:' || v_authority.actor_user_id::text || ':'
      || p_client_action_id::text, 0
  ));
  if exists (
    select 1 from public.assistant_approvals other
    where other.tenant_id = v_authority.tenant_id
      and other.actor_user_id = v_authority.actor_user_id
      and other.client_action_id = p_client_action_id
      and other.id <> p_approval_id
  ) then
    raise exception 'Approval action id was already used' using errcode = '22023';
  end if;

  select approval.id, approval.authority_fingerprint, approval.state,
    approval.client_action_id, approval.decision, approval.decision_response,
    approval.run_id, approval.expires_at, approval.action_payload,
    approval.action_name, approval.provider_attempt_id,
    approval.arguments_hash
  into v_approval
  from public.assistant_approvals approval
  where approval.id = p_approval_id
    and approval.tenant_id = v_authority.tenant_id
    and approval.actor_user_id = v_authority.actor_user_id
  for update;
  if not found or v_approval.authority_fingerprint <>
      v_authority.authority_fingerprint then
    raise exception 'Approval is unavailable' using errcode = '42501';
  end if;
  if v_approval.state <> 'pending' then
    if v_approval.client_action_id = p_client_action_id
       and v_approval.decision = p_action
       and v_approval.decision_response is not null then
      return v_approval.decision_response;
    end if;
    raise exception 'Approval was already consumed' using errcode = '22023';
  end if;

  select run.id, run.status into v_run
  from public.assistant_runs run
  where run.id = v_approval.run_id
    and run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.authority_fingerprint = v_authority.authority_fingerprint
  for update;
  if not found or v_run.status <> 'succeeded' then
    raise exception 'Approval run is unavailable' using errcode = '42501';
  end if;

  if v_approval.expires_at <= v_now then
    v_final_state := 'expired';
    v_response := jsonb_build_object(
      'authorityTenantId', v_authority.tenant_id,
      'actorUserId', v_authority.actor_user_id,
      'approvalId', v_approval.id,
      'clientActionId', p_client_action_id,
      'approvalState', v_final_state,
      'task', null
    );
    update public.assistant_approvals set
      state = v_final_state, client_action_id = p_client_action_id,
      decision = p_action, decision_response = v_response,
      decided_at = v_now, updated_at = v_now
    where id = v_approval.id;
  elsif p_action = 'discard' then
    v_final_state := 'discarded';
    v_response := jsonb_build_object(
      'authorityTenantId', v_authority.tenant_id,
      'actorUserId', v_authority.actor_user_id,
      'approvalId', v_approval.id,
      'clientActionId', p_client_action_id,
      'approvalState', v_final_state,
      'task', null
    );
    update public.assistant_approvals set
      state = v_final_state, client_action_id = p_client_action_id,
      decision = p_action, decision_response = v_response,
      decided_at = v_now, updated_at = v_now
    where id = v_approval.id;
  else
    v_payload := v_approval.action_payload;
    if v_approval.action_name <> 'create_task'
       or jsonb_typeof(v_payload) <> 'object'
       or exists (
         select 1 from jsonb_object_keys(v_payload) key
         where key not in (
           'title', 'description', 'priority', 'dueAt', 'dueAtValue',
           'assigneeMode', 'assignedTo', 'assigneeName'
         )
       )
       or octet_length(coalesce(v_payload ->> 'title', '')) not between 1 and 160
       or octet_length(coalesce(v_payload ->> 'description', '')) > 2000
       or v_payload ->> 'priority' not in ('low', 'normal', 'high', 'urgent')
       or v_payload ->> 'assigneeMode' not in ('me', 'unassigned', 'name')
       or octet_length(coalesce(v_payload ->> 'assigneeName', '')) not between 1 and 160
       or not (
         (v_payload -> 'assignedTo') = 'null'::jsonb
         or lower(v_payload ->> 'assignedTo') ~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       ) then
      raise exception 'Approval payload is invalid' using errcode = '22023';
    end if;
    if v_payload -> 'assignedTo' <> 'null'::jsonb and not exists (
      select 1 from public.user_profiles profile
      where profile.user_id = (v_payload ->> 'assignedTo')::uuid
        and profile.tenant_id = v_authority.tenant_id
        and profile.is_active is true
    ) then
      raise exception 'Approval assignee is unavailable' using errcode = '42501';
    end if;

    insert into public.smart_tasks (
      tenant_id, title, description, status, priority, due_date,
      assigned_to, created_by
    ) values (
      v_authority.tenant_id,
      v_payload ->> 'title',
      v_payload ->> 'description',
      'pending',
      v_payload ->> 'priority',
      nullif(v_payload ->> 'dueAtValue', '')::timestamptz,
      nullif(v_payload ->> 'assignedTo', '')::uuid,
      v_authority.actor_user_id
    ) returning id into v_task_id;

    select jsonb_build_object(
      'entityId', task.id,
      'title', task.title,
      'description', task.description,
      'status', task.status,
      'priority', task.priority,
      'dueAt', case when task.due_date is null then null else
        to_char(task.due_date at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') end,
      'assigneeName', v_payload ->> 'assigneeName'
    ) into strict v_task_projection
    from public.smart_tasks task
    where task.id = v_task_id
      and task.tenant_id = v_authority.tenant_id
      and task.created_by = v_authority.actor_user_id
      and task.title = v_payload ->> 'title'
      and task.status = 'pending'
      and task.priority = v_payload ->> 'priority'
      and task.assigned_to is not distinct from nullif(
        v_payload ->> 'assignedTo', ''
      )::uuid;

    v_response := jsonb_build_object(
      'authorityTenantId', v_authority.tenant_id,
      'actorUserId', v_authority.actor_user_id,
      'approvalId', v_approval.id,
      'clientActionId', p_client_action_id,
      'approvalState', 'approved',
      'task', v_task_projection
    );
    v_action_call_hash := encode(extensions.digest(convert_to(
      'assistant:task-action:' || p_client_action_id::text, 'UTF8'
    ), 'sha256'), 'hex');
    v_output_hash := encode(extensions.digest(convert_to(
      v_task_projection::text, 'UTF8'
    ), 'sha256'), 'hex');
    select coalesce(max(receipt.ordinal), 0) + 1
    into v_receipt_ordinal
    from public.assistant_tool_receipts receipt
    where receipt.run_id = v_run.id;
    insert into public.assistant_tool_receipts (
      tenant_id, actor_user_id, run_id, provider_attempt_id, ordinal,
      provider_call_hash, tool_name, tool_version, risk, policy_decision,
      status, arguments_hash, output_hash, result_count, output_bytes,
      approval_used, read_back_verified, failure_code, started_at, completed_at
    ) values (
      v_authority.tenant_id, v_authority.actor_user_id, v_run.id,
      v_approval.provider_attempt_id, v_receipt_ordinal,
      v_action_call_hash, 'create_task', 'v1', 'reversible_write', 'allowed',
      'succeeded', v_approval.arguments_hash, v_output_hash, 1,
      octet_length(v_response::text), true, true, null, v_now, v_now
    ) returning id into v_receipt_id;
    update public.assistant_approvals set
      state = 'approved', client_action_id = p_client_action_id,
      decision = p_action, decision_response = v_response,
      created_entity_id = v_task_id, action_receipt_id = v_receipt_id,
      decided_at = v_now, updated_at = v_now
    where id = v_approval.id;
    v_final_state := 'approved';
  end if;

  update public.assistant_messages message set cards = coalesce((
    select jsonb_agg(
      case when card.value #>> '{approvalRef,id}' = v_approval.id::text
        then jsonb_set(card.value, '{approvalRef,state}', to_jsonb(v_final_state), false)
        else card.value end
      order by card.ordinality
    )
    from jsonb_array_elements(message.cards) with ordinality card(value, ordinality)
  ), '[]'::jsonb)
  where message.run_id = v_run.id
    and exists (
      select 1 from jsonb_array_elements(message.cards) card
      where card #>> '{approvalRef,id}' = v_approval.id::text
    );

  return v_response;
end;
$$;

revoke all on function public.assistant_prepare_task_v1(
  text, text, text, text, text, text, uuid, integer, text, text
) from public, anon, authenticated, service_role;
revoke all on function public.assistant_apply_task_approval_v1(uuid, text, uuid)
from public, anon, authenticated, service_role;

grant execute on function public.assistant_prepare_task_v1(
  text, text, text, text, text, text, uuid, integer, text, text
) to authenticated;
grant execute on function public.assistant_apply_task_approval_v1(uuid, text, uuid)
to authenticated;

comment on table public.assistant_approvals is
  'Caller- and fingerprint-bound, single-use AI action approvals. The canonical payload is server-owned and expires exactly ten minutes after preparation.';
comment on function public.assistant_prepare_task_v1(
  text, text, text, text, text, text, uuid, integer, text, text
) is 'Prepares but never creates a task; persists one exact 10-minute approval tied to the model tool receipt identity.';
comment on function public.assistant_apply_task_approval_v1(uuid, text, uuid)
is 'Consumes one caller-owned task approval. Approve atomically inserts, exact-read-backs and receipts the task; discard/expiry never write a task.';

commit;
