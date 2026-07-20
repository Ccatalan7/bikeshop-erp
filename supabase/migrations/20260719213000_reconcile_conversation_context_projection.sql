-- Deployment status: NOT DEPLOYED (2026-07-19).
--
-- Reconcile the legacy scalar conversation context with its append-only
-- context ledger, then enforce their equivalence at transaction commit.
--
-- Authority and recovery policy:
--   * an existing primary conversation_contexts row is authoritative;
--   * only when no primary exists may the complete scalar pair be promoted or
--     inserted as primary;
--   * a scalar whose target was deleted is archived once in immutable audit
--     evidence and cleared instead of fabricating a primary row;
--   * non-primary history is never selected by recency or any other guess;
--   * conversations.updated_at is restored exactly after reconciliation;
--   * a client rollback is sufficient recovery because the retained history
--     and additive deferred invariant functions/triggers are compatible. Do
--     not delete context history or reverse a repaired projection.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create table if not exists
  public.messaging_context_projection_reconciliation_audit (
    evidence_fingerprint text primary key,
    tenant_id uuid not null,
    conversation_id uuid not null,
    context_type text not null,
    context_id uuid not null,
    reason text not null,
    action text not null,
    target_presence text not null,
    primary_count_snapshot integer not null,
    original_updated_at timestamptz,
    migration_version text not null,
    recorded_at timestamptz not null default clock_timestamp(),
    check (evidence_fingerprint ~ '^[0-9a-f]{64}$'),
    check (nullif(btrim(context_type), '') is not null),
    check (nullif(btrim(reason), '') is not null),
    check (action = 'cleared_dangling_scalar'),
    check (target_presence = 'missing_all_tenants'),
    check (primary_count_snapshot = 0),
    check (nullif(btrim(migration_version), '') is not null)
  );

-- This migration was exercised repeatedly on the disposable production clone
-- while its audit contract was being reviewed. Converge an earlier empty
-- draft of the same not-yet-deployed table without dropping evidence or the
-- relation. Defaults backfill the three deterministic fields atomically and
-- are removed immediately so every future insert must remain explicit.
alter table public.messaging_context_projection_reconciliation_audit
  add column if not exists action text not null
    default 'cleared_dangling_scalar',
  add column if not exists target_presence text not null
    default 'missing_all_tenants',
  add column if not exists primary_count_snapshot integer not null
    default 0;

alter table public.messaging_context_projection_reconciliation_audit
  alter column action drop default,
  alter column target_presence drop default,
  alter column primary_count_snapshot drop default;

-- UUIDs are immutable evidence snapshots and must survive later aggregate
-- purges. Normalize every prior draft constraint by meaning rather than by its
-- truncated generated name.
do $audit_constraints$
declare
  v_constraint name;
begin
  for v_constraint in
    select constraint_row.conname
    from pg_constraint constraint_row
    where constraint_row.conrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and constraint_row.contype in ('c', 'f')
  loop
    execute format(
      'alter table public.messaging_context_projection_reconciliation_audit drop constraint %I',
      v_constraint
    );
  end loop;

  alter table public.messaging_context_projection_reconciliation_audit
    add constraint messaging_context_projection_audit_fingerprint_check
      check (evidence_fingerprint ~ '^[0-9a-f]{64}$'),
    add constraint messaging_context_projection_audit_context_type_check
      check (nullif(btrim(context_type), '') is not null),
    add constraint messaging_context_projection_audit_reason_check
      check (nullif(btrim(reason), '') is not null),
    add constraint messaging_context_projection_audit_action_check
      check (action = 'cleared_dangling_scalar'),
    add constraint messaging_context_projection_audit_target_presence_check
      check (target_presence = 'missing_all_tenants'),
    add constraint messaging_context_projection_audit_primary_count_check
      check (primary_count_snapshot = 0),
    add constraint messaging_context_projection_audit_version_check
      check (nullif(btrim(migration_version), '') is not null);
end;
$audit_constraints$;

alter table public.messaging_context_projection_reconciliation_audit
  enable row level security;
alter table public.messaging_context_projection_reconciliation_audit
  force row level security;

create index if not exists
  idx_messaging_context_projection_audit_tenant_recorded
  on public.messaging_context_projection_reconciliation_audit(
    tenant_id,
    recorded_at desc
  );
create index if not exists
  idx_messaging_context_projection_audit_conversation_recorded
  on public.messaging_context_projection_reconciliation_audit(
    conversation_id,
    recorded_at desc
  );
create index if not exists
  idx_messaging_context_projection_audit_context_lookup
  on public.messaging_context_projection_reconciliation_audit(
    context_type,
    context_id
  );

revoke all on table
  public.messaging_context_projection_reconciliation_audit
  from public, anon, authenticated, service_role;
grant select on table
  public.messaging_context_projection_reconciliation_audit
  to service_role;

-- Earlier schema history exposed this generic wrapper to authenticated users.
-- Revoke it again here so an API caller cannot mint the custom audit GUC even
-- if migrations are replayed against a database with that old grant.
revoke all on function public.set_config(text, text, boolean)
  from public, anon, authenticated, service_role;

comment on table
  public.messaging_context_projection_reconciliation_audit is
  'Append-only owner-written evidence for dangling legacy scalar contexts cleared without inventing a primary ledger row. Service role may inspect but cannot forge or mutate evidence.';

-- The repair function opens this transaction-local capability only around its
-- audited insert/read-back. Policies target the exact migration owner instead
-- of PUBLIC; API roles also have no INSERT grant and cannot call the generic
-- set_config wrapper. Immutable triggers remain the append-only control even
-- when a privileged database owner has BYPASSRLS.
do $$
declare
  v_owner name := current_user;
  v_owner_oid oid;
  v_service_oid oid;
begin
  select role.oid into strict v_owner_oid
  from pg_roles role
  where role.rolname = v_owner;

  select role.oid into strict v_service_oid
  from pg_roles role
  where role.rolname = 'service_role';

  if not exists (
    select 1
    from pg_policy policy
    where policy.polrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and policy.polname =
        'messaging_context_projection_audit_owner_insert'
  ) then
    execute format($policy$
      create policy messaging_context_projection_audit_owner_insert
      on public.messaging_context_projection_reconciliation_audit
      for insert
      to %I
      with check (
        current_setting(
          'app.messaging_context_projection_reconciliation',
          true
        ) = '20260719213000'
      )
    $policy$, v_owner);
  end if;

  if not exists (
    select 1
    from pg_policy policy
    where policy.polrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and policy.polname =
        'messaging_context_projection_audit_owner_read'
  ) then
    execute format($policy$
      create policy messaging_context_projection_audit_owner_read
      on public.messaging_context_projection_reconciliation_audit
      for select
      to %I
      using (
        current_setting(
          'app.messaging_context_projection_reconciliation',
          true
        ) = '20260719213000'
      )
    $policy$, v_owner);
  end if;

  if not exists (
    select 1
    from pg_policy policy
    where policy.polrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and policy.polname =
        'messaging_context_projection_audit_service_read'
  ) then
    execute $policy$
      create policy messaging_context_projection_audit_service_read
      on public.messaging_context_projection_reconciliation_audit
      for select
      to service_role
      using (true)
    $policy$;
  end if;

  if exists (
    select 1
    from pg_policy policy
    where policy.polrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and policy.polname =
        'messaging_context_projection_audit_owner_reconcile'
  ) then
    raise exception 'Legacy public audit reconciliation policy must not exist'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from pg_policy policy
    where policy.polrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and (
        (
          policy.polname in (
            'messaging_context_projection_audit_owner_insert',
            'messaging_context_projection_audit_owner_read'
          )
          and policy.polroles is distinct from array[v_owner_oid]::oid[]
        )
        or (
          policy.polname = 'messaging_context_projection_audit_service_read'
          and policy.polroles is distinct from array[v_service_oid]::oid[]
        )
        or 0::oid = any(policy.polroles)
      )
  ) then
    raise exception 'Messaging context projection audit policy roles are unsafe'
      using errcode = '23514';
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('authenticated',
      'public.messaging_context_projection_reconciliation_audit', 'SELECT')
     or has_table_privilege('authenticated',
      'public.messaging_context_projection_reconciliation_audit', 'INSERT')
     or has_table_privilege('authenticated',
      'public.messaging_context_projection_reconciliation_audit', 'UPDATE')
     or has_table_privilege('authenticated',
      'public.messaging_context_projection_reconciliation_audit', 'DELETE')
     or has_table_privilege('authenticated',
      'public.messaging_context_projection_reconciliation_audit', 'TRUNCATE')
     or has_table_privilege('anon',
      'public.messaging_context_projection_reconciliation_audit', 'SELECT')
     or has_table_privilege('anon',
      'public.messaging_context_projection_reconciliation_audit', 'INSERT')
     or has_table_privilege('anon',
      'public.messaging_context_projection_reconciliation_audit', 'UPDATE')
     or has_table_privilege('anon',
      'public.messaging_context_projection_reconciliation_audit', 'DELETE')
     or has_table_privilege('anon',
      'public.messaging_context_projection_reconciliation_audit', 'TRUNCATE')
     or not has_table_privilege(
      'service_role',
      'public.messaging_context_projection_reconciliation_audit',
      'SELECT'
    )
     or has_table_privilege('service_role',
      'public.messaging_context_projection_reconciliation_audit', 'INSERT')
     or has_table_privilege('service_role',
      'public.messaging_context_projection_reconciliation_audit', 'UPDATE')
     or has_table_privilege('service_role',
      'public.messaging_context_projection_reconciliation_audit', 'DELETE')
     or has_table_privilege('service_role',
      'public.messaging_context_projection_reconciliation_audit', 'TRUNCATE') then
    raise exception 'Messaging context projection audit ACL reconciliation failed'
      using errcode = '23514';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.set_config(text,text,boolean)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.set_config(text,text,boolean)',
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'public.set_config(text,text,boolean)',
    'EXECUTE'
  ) then
    raise exception 'Generic set_config RPC must remain API-private'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from pg_class relation
    where relation.oid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and (not relation.relrowsecurity or not relation.relforcerowsecurity)
  ) then
    raise exception 'Messaging context projection audit must force row-level security'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function
  public.enforce_messaging_context_projection_audit_immutable()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  raise exception 'Messaging context projection reconciliation audit is immutable'
    using errcode = '23514';
end;
$$;

revoke all on function
  public.enforce_messaging_context_projection_audit_immutable()
  from public, anon, authenticated, service_role;

do $$
begin
  if not exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and trigger.tgname =
        'trg_messaging_context_projection_audit_immutable'
      and not trigger.tgisinternal
  ) then
    execute $trigger$
      create trigger trg_messaging_context_projection_audit_immutable
      before update or delete
      on public.messaging_context_projection_reconciliation_audit
      for each row execute function
        public.enforce_messaging_context_projection_audit_immutable()
    $trigger$;
  elsif exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and trigger.tgname =
        'trg_messaging_context_projection_audit_immutable'
      and trigger.tgfoid <>
        'public.enforce_messaging_context_projection_audit_immutable()'::regprocedure
  ) then
    raise exception 'Existing context projection audit trigger has an incompatible definition'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and trigger.tgname =
        'trg_messaging_context_projection_audit_no_truncate'
      and not trigger.tgisinternal
  ) then
    execute $trigger$
      create trigger trg_messaging_context_projection_audit_no_truncate
      before truncate
      on public.messaging_context_projection_reconciliation_audit
      for each statement execute function
        public.enforce_messaging_context_projection_audit_immutable()
    $trigger$;
  elsif exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid =
      'public.messaging_context_projection_reconciliation_audit'::regclass
      and trigger.tgname =
        'trg_messaging_context_projection_audit_no_truncate'
      and trigger.tgfoid <>
        'public.enforce_messaging_context_projection_audit_immutable()'::regprocedure
  ) then
    raise exception 'Existing context projection audit truncate trigger has an incompatible definition'
      using errcode = '23514';
  end if;
end;
$$;

create or replace function public.messaging_context_entity_exists_any_tenant(
  p_context_type text,
  p_context_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case lower(coalesce(p_context_type, ''))
    when 'job' then exists (
      select 1 from public.mechanic_jobs row where row.id = p_context_id
    )
    when 'invoice' then exists (
      select 1 from public.sales_invoices row where row.id = p_context_id
    )
    when 'bike' then exists (
      select 1 from public.bikes row where row.id = p_context_id
    )
    when 'product' then exists (
      select 1 from public.products row where row.id = p_context_id
    )
    when 'order' then exists (
      select 1 from public.online_orders row where row.id = p_context_id
    )
    when 'customer' then exists (
      select 1 from public.customers row where row.id = p_context_id
    )
    when 'supplier' then exists (
      select 1 from public.suppliers row where row.id = p_context_id
    )
    when 'purchase_invoice' then exists (
      select 1 from public.purchase_invoices row where row.id = p_context_id
    )
    else false
  end;
$$;

comment on function
  public.messaging_context_entity_exists_any_tenant(text, uuid) is
  'API-private reconciliation helper that distinguishes a deleted target from a still-existing cross-tenant target.';

revoke all on function
  public.messaging_context_entity_exists_any_tenant(text, uuid)
  from public, anon, authenticated, service_role;

create or replace function public.assert_conversation_context_projection(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_conversation public.conversations%rowtype;
  v_primary_count integer;
  v_primary_context_type text;
  v_primary_context_id uuid;
  v_primary_tenant_id uuid;
begin
  select conversation.*
  into v_conversation
  from public.conversations conversation
  where conversation.id = p_conversation_id;

  -- A parent delete may cascade context rows before this deferred trigger is
  -- evaluated. The aggregate no longer exists, so there is no projection to
  -- validate.
  if not found then
    return;
  end if;

  if (v_conversation.context_type is null)
      is distinct from (v_conversation.context_id is null) then
    raise exception 'Conversation context type and id must be set together'
      using errcode = '23514';
  end if;

  select count(*)::integer
  into v_primary_count
  from public.conversation_contexts context_link
  where context_link.conversation_id = v_conversation.id
    and context_link.is_primary;

  select
    context_link.context_type,
    context_link.context_id,
    context_link.tenant_id
  into
    v_primary_context_type,
    v_primary_context_id,
    v_primary_tenant_id
  from public.conversation_contexts context_link
  where context_link.conversation_id = v_conversation.id
    and context_link.is_primary
  order by context_link.id
  limit 1;

  if v_conversation.context_type is null then
    if v_primary_count <> 0 then
      raise exception 'Cleared conversation context cannot retain a primary ledger row'
        using errcode = '23514';
    end if;
    return;
  end if;

  if v_primary_count <> 1
     or v_primary_tenant_id is distinct from v_conversation.tenant_id
     or v_primary_context_type is distinct from v_conversation.context_type
     or v_primary_context_id is distinct from v_conversation.context_id then
    raise exception 'Conversation context projection must match exactly one primary ledger row'
      using errcode = '23514';
  end if;

  if not public.messaging_context_belongs_to_tenant(
    v_primary_context_type,
    v_primary_context_id,
    v_conversation.tenant_id
  ) then
    raise exception 'Primary messaging context does not belong to conversation tenant'
      using errcode = '23514';
  end if;

  if v_conversation.type = 'support'
     and v_conversation.counterparty_type = 'supplier'
     and v_primary_context_type not in ('supplier', 'purchase_invoice') then
    raise exception 'Supplier conversation has an incompatible primary context'
      using errcode = '23514';
  end if;

  if v_conversation.type = 'support'
     and v_conversation.counterparty_type = 'customer'
     and v_primary_context_type in ('supplier', 'purchase_invoice') then
    raise exception 'Customer conversation has an incompatible primary context'
      using errcode = '23514';
  end if;
end;
$$;

comment on function public.assert_conversation_context_projection(uuid) is
  'API-private deferred assertion: scalar context is null with no primary, or exactly matches one same-tenant primary ledger row.';

create or replace function public.reconcile_conversation_context_projections()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_repaired_count integer := 0;
begin
  -- Serialize the authority decision with every writer. The conversation lock
  -- is acquired first everywhere in this migration to keep lock order stable.
  lock table public.conversations in share row exclusive mode;
  lock table public.conversation_contexts in share row exclusive mode;

  if exists (
    select 1
    from public.conversations conversation
    where (conversation.context_type is null)
        is distinct from (conversation.context_id is null)
  ) then
    raise exception 'Cannot reconcile a partial scalar conversation context'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.conversation_contexts context_link
    where context_link.is_primary
    group by context_link.conversation_id
    having count(*) > 1
  ) then
    raise exception 'Cannot reconcile multiple primary context rows'
      using errcode = '23514';
  end if;

  -- Validate only authoritative primary rows. Non-primary rows are retained as
  -- history and are not interpreted unless they exactly match a scalar pair
  -- that has no primary.
  if exists (
    select 1
    from public.conversation_contexts context_link
    join public.conversations conversation
      on conversation.id = context_link.conversation_id
    where context_link.is_primary
      and (
        context_link.tenant_id is distinct from conversation.tenant_id
        or not public.messaging_context_belongs_to_tenant(
          context_link.context_type,
          context_link.context_id,
          conversation.tenant_id
        )
        or (
          conversation.type = 'support'
          and conversation.counterparty_type = 'supplier'
          and context_link.context_type not in ('supplier', 'purchase_invoice')
        )
        or (
          conversation.type = 'support'
          and conversation.counterparty_type = 'customer'
          and context_link.context_type in ('supplier', 'purchase_invoice')
        )
      )
  ) then
    raise exception 'Cannot reconcile an invalid authoritative primary context'
      using errcode = '23514';
  end if;

  -- A complete scalar pair is authoritative only when the ledger has no
  -- primary. Unknown types remain an invalid write rather than being mistaken
  -- for an entity that was deleted.
  if exists (
    select 1
    from public.conversations conversation
    where conversation.context_type is not null
      and not exists (
        select 1
        from public.conversation_contexts primary_context
        where primary_context.conversation_id = conversation.id
          and primary_context.is_primary
      )
      and conversation.context_type not in (
        'job',
        'invoice',
        'bike',
        'product',
        'order',
        'customer',
        'supplier',
        'purchase_invoice'
      )
  ) then
    raise exception 'Cannot reconcile an unsupported scalar context type'
      using errcode = '23514';
  end if;

  -- A same-type entity that still exists under another tenant is an active
  -- security defect and must never be archived as if it had simply been deleted.
  -- Capability is a property of the conversation/context-type pair, not of the
  -- target row's current existence. Reject an incompatible type even when its
  -- referenced entity has since disappeared; otherwise a malformed relation
  -- could be silently reclassified as ordinary dangling history.
  if exists (
    select 1
    from public.conversations conversation
    where conversation.context_type is not null
      and not exists (
        select 1
        from public.conversation_contexts primary_context
        where primary_context.conversation_id = conversation.id
          and primary_context.is_primary
      )
      and public.messaging_context_entity_exists_any_tenant(
        conversation.context_type,
        conversation.context_id
      )
      and not public.messaging_context_belongs_to_tenant(
        conversation.context_type,
        conversation.context_id,
        conversation.tenant_id
      )
  ) then
    raise exception 'Cannot reconcile a cross-tenant scalar conversation context'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.conversations conversation
    where conversation.context_type is not null
      and not exists (
        select 1
        from public.conversation_contexts primary_context
        where primary_context.conversation_id = conversation.id
          and primary_context.is_primary
      )
      and (
        (
          conversation.type = 'support'
          and conversation.counterparty_type = 'supplier'
          and conversation.context_type not in ('supplier', 'purchase_invoice')
        )
        or (
          conversation.type = 'support'
          and conversation.counterparty_type = 'customer'
          and conversation.context_type in ('supplier', 'purchase_invoice')
        )
      )
  ) then
    raise exception 'Cannot reconcile a capability-incompatible scalar conversation context'
      using errcode = '23514';
  end if;

  create temporary table if not exists
    pg_temp.conversation_context_projection_repair_snapshot (
      conversation_id uuid primary key,
      original_updated_at timestamptz
    ) on commit drop;

  truncate table pg_temp.conversation_context_projection_repair_snapshot;

  insert into pg_temp.conversation_context_projection_repair_snapshot (
    conversation_id,
    original_updated_at
  )
  select
    conversation.id,
    conversation.updated_at
  from public.conversations conversation
  left join public.conversation_contexts primary_context
    on primary_context.conversation_id = conversation.id
   and primary_context.is_primary
  where (
      primary_context.id is not null
      and (
        conversation.context_type is distinct from primary_context.context_type
        or conversation.context_id is distinct from primary_context.context_id
      )
    )
    or (
      primary_context.id is null
      and conversation.context_type is not null
    );

  get diagnostics v_repaired_count = row_count;

  -- A deleted target cannot be promoted into a fabricated primary. Preserve
  -- the exact scalar evidence once, prove that write, then clear only the
  -- invalid active projection. The retained audit row prevents this repair
  -- from erasing why the scalar was removed.
  perform pg_catalog.set_config(
    'app.messaging_context_projection_reconciliation',
    '20260719213000',
    true
  );

  insert into public.messaging_context_projection_reconciliation_audit (
    evidence_fingerprint,
    tenant_id,
    conversation_id,
    context_type,
    context_id,
    reason,
    action,
    target_presence,
    primary_count_snapshot,
    original_updated_at,
    migration_version
  )
  select
    encode(extensions.digest(convert_to(concat_ws(
        '|',
        '20260719213000',
        conversation.tenant_id::text,
        conversation.id::text,
        conversation.context_type,
        conversation.context_id::text,
        'scalar_context_target_missing',
        'cleared_dangling_scalar',
        'missing_all_tenants',
        '0'
      ), 'UTF8'), 'sha256'), 'hex'),
    conversation.tenant_id,
    conversation.id,
    conversation.context_type,
    conversation.context_id,
    'scalar_context_target_missing',
    'cleared_dangling_scalar',
    'missing_all_tenants',
    0,
    conversation.updated_at,
    '20260719213000'
  from public.conversations conversation
  where conversation.context_type is not null
    and not exists (
      select 1
      from public.conversation_contexts primary_context
      where primary_context.conversation_id = conversation.id
        and primary_context.is_primary
    )
    and not public.messaging_context_entity_exists_any_tenant(
      conversation.context_type,
      conversation.context_id
    )
  on conflict (evidence_fingerprint) do nothing;

  if exists (
    select 1
    from public.conversations conversation
    where conversation.context_type is not null
      and not exists (
        select 1
        from public.conversation_contexts primary_context
        where primary_context.conversation_id = conversation.id
          and primary_context.is_primary
      )
      and not public.messaging_context_entity_exists_any_tenant(
        conversation.context_type,
        conversation.context_id
      )
      and not exists (
        select 1
        from public.messaging_context_projection_reconciliation_audit audit
        where audit.evidence_fingerprint = encode(extensions.digest(
            convert_to(concat_ws(
              '|',
              '20260719213000',
              conversation.tenant_id::text,
              conversation.id::text,
              conversation.context_type,
              conversation.context_id::text,
              'scalar_context_target_missing',
              'cleared_dangling_scalar',
              'missing_all_tenants',
              '0'
            ), 'UTF8'),
            'sha256'
          ), 'hex')
          and audit.tenant_id = conversation.tenant_id
          and audit.conversation_id = conversation.id
          and audit.context_type = conversation.context_type
          and audit.context_id = conversation.context_id
          and audit.reason = 'scalar_context_target_missing'
          and audit.action = 'cleared_dangling_scalar'
          and audit.target_presence = 'missing_all_tenants'
          and audit.primary_count_snapshot = 0
          and audit.original_updated_at is not distinct from
            conversation.updated_at
          and audit.migration_version = '20260719213000'
      )
  ) then
    raise exception 'Dangling scalar context reconciliation audit is incomplete'
      using errcode = '23514';
  end if;

  update public.conversations conversation
  set context_type = null,
      context_id = null
  where conversation.context_type is not null
    and not exists (
      select 1
      from public.conversation_contexts primary_context
      where primary_context.conversation_id = conversation.id
        and primary_context.is_primary
    )
    and not public.messaging_context_entity_exists_any_tenant(
      conversation.context_type,
      conversation.context_id
    );

  if exists (
    select 1
    from public.messaging_context_projection_reconciliation_audit audit
    join pg_temp.conversation_context_projection_repair_snapshot snapshot
      on snapshot.conversation_id = audit.conversation_id
    join public.conversations conversation
      on conversation.id = audit.conversation_id
    where audit.migration_version = '20260719213000'
      and (
        conversation.context_type is not null
        or conversation.context_id is not null
      )
  ) then
    raise exception 'Audited dangling scalar context was not cleared'
      using errcode = '23514';
  end if;

  perform pg_catalog.set_config(
    'app.messaging_context_projection_reconciliation',
    '',
    true
  );

  -- Existing primary wins, including over a complete but stale scalar pair.
  update public.conversations conversation
  set context_type = primary_context.context_type,
      context_id = primary_context.context_id
  from public.conversation_contexts primary_context
  where primary_context.conversation_id = conversation.id
    and primary_context.tenant_id = conversation.tenant_id
    and primary_context.is_primary
    and (
      conversation.context_type is distinct from primary_context.context_type
      or conversation.context_id is distinct from primary_context.context_id
    );

  -- No primary exists: reuse the exact retained scalar link when available.
  -- The existing BEFORE guard synchronizes the scalar projection and preserves
  -- every immutable context identity/evidence field.
  update public.conversation_contexts context_link
  set is_primary = true
  from public.conversations conversation
  where context_link.conversation_id = conversation.id
    and context_link.tenant_id = conversation.tenant_id
    and context_link.context_type = conversation.context_type
    and context_link.context_id = conversation.context_id
    and conversation.context_type is not null
    and not context_link.is_primary
    and not exists (
      select 1
      from public.conversation_contexts primary_context
      where primary_context.conversation_id = conversation.id
        and primary_context.is_primary
    );

  -- If no exact historical row exists, append one without inventing an actor.
  insert into public.conversation_contexts (
    conversation_id,
    context_type,
    context_id,
    is_primary,
    added_by,
    tenant_id
  )
  select
    conversation.id,
    conversation.context_type,
    conversation.context_id,
    true,
    null,
    conversation.tenant_id
  from public.conversations conversation
  where conversation.context_type is not null
    and not exists (
      select 1
      from public.conversation_contexts primary_context
      where primary_context.conversation_id = conversation.id
        and primary_context.is_primary
    )
    and not exists (
      select 1
      from public.conversation_contexts exact_context
      where exact_context.conversation_id = conversation.id
        and exact_context.tenant_id = conversation.tenant_id
        and exact_context.context_type = conversation.context_type
        and exact_context.context_id = conversation.context_id
    );

  -- Context promotion invokes the existing synchronization guard, which
  -- intentionally touches updated_at. A reconciliation is not a user/business
  -- event, so restore the exact pre-migration timestamp after the graph is sane.
  update public.conversations conversation
  set updated_at = snapshot.original_updated_at
  from pg_temp.conversation_context_projection_repair_snapshot snapshot
  where conversation.id = snapshot.conversation_id
    and conversation.updated_at is distinct from snapshot.original_updated_at;

  if exists (
    select 1
    from pg_temp.conversation_context_projection_repair_snapshot snapshot
    join public.conversations conversation
      on conversation.id = snapshot.conversation_id
    where conversation.updated_at is distinct from snapshot.original_updated_at
  ) then
    raise exception 'Conversation context reconciliation changed updated_at'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from public.conversations conversation
    left join public.conversation_contexts primary_context
      on primary_context.conversation_id = conversation.id
     and primary_context.is_primary
    where (conversation.context_type is null)
        is distinct from (conversation.context_id is null)
       or (
         conversation.context_type is null
         and primary_context.id is not null
       )
       or (
         conversation.context_type is not null
         and (
           primary_context.id is null
           or primary_context.tenant_id is distinct from conversation.tenant_id
           or primary_context.context_type is distinct from conversation.context_type
           or primary_context.context_id is distinct from conversation.context_id
         )
       )
  ) then
    raise exception 'Conversation context projection reconciliation failed'
      using errcode = '23514';
  end if;

  return v_repaired_count;
end;
$$;

comment on function public.reconcile_conversation_context_projections() is
  'Owner-only idempotent repair: existing primary wins; valid scalar-only context is promoted/appended; dangling scalar evidence is archived then cleared; timestamps and non-primary history are preserved.';

create or replace function public.enforce_conversation_context_projection_at_commit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_table_name = 'conversations' then
    perform public.assert_conversation_context_projection(
      case when tg_op = 'DELETE' then old.id else new.id end
    );
    return null;
  end if;

  if tg_op in ('UPDATE', 'DELETE') then
    perform public.assert_conversation_context_projection(old.conversation_id);
  end if;

  if tg_op in ('INSERT', 'UPDATE')
     and (
       tg_op = 'INSERT'
       or new.conversation_id is distinct from old.conversation_id
     ) then
    perform public.assert_conversation_context_projection(new.conversation_id);
  end if;

  return null;
end;
$$;

comment on function public.enforce_conversation_context_projection_at_commit() is
  'API-private deferred constraint trigger enforcing final scalar/primary context equivalence.';

revoke all on function public.assert_conversation_context_projection(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.reconcile_conversation_context_projections()
  from public, anon, authenticated, service_role;
revoke all on function public.enforce_conversation_context_projection_at_commit()
  from public, anon, authenticated, service_role;

-- Hosted default privileges may add deployment/test roles beyond the standard
-- API roles whenever a function is first created. Reconcile the complete
-- effective ACL so every migration-only helper is executable by its exact
-- owner and by no PUBLIC or named non-owner grantee.
do $owner_only_acl$
declare
  v_signature text;
  v_function regprocedure;
  v_owner oid;
  v_grantee oid;
  v_grantee_name name;
begin
  foreach v_signature in array array[
    'public.enforce_messaging_context_projection_audit_immutable()',
    'public.messaging_context_entity_exists_any_tenant(text,uuid)',
    'public.assert_conversation_context_projection(uuid)',
    'public.reconcile_conversation_context_projections()',
    'public.enforce_conversation_context_projection_at_commit()'
  ]
  loop
    v_function := to_regprocedure(v_signature);

    if v_function is null then
      raise exception 'Required context projection helper is missing: %',
        v_signature
        using errcode = '42883';
    end if;

    select procedure_row.proowner
    into strict v_owner
    from pg_proc procedure_row
    where procedure_row.oid = v_function;

    execute format(
      'revoke all privileges on function %s from public cascade',
      v_function
    );

    for v_grantee in
      select distinct expanded_acl.grantee
      from pg_proc procedure_row
      cross join lateral aclexplode(
        coalesce(
          procedure_row.proacl,
          acldefault('f', procedure_row.proowner)
        )
      ) expanded_acl
      where procedure_row.oid = v_function
        and expanded_acl.grantee <> 0
        and expanded_acl.grantee <> procedure_row.proowner
    loop
      v_grantee_name := pg_get_userbyid(v_grantee);
      if v_grantee_name is null then
        raise exception 'Cannot resolve function ACL grantee OID % for %',
          v_grantee,
          v_signature
          using errcode = '42704';
      end if;

      execute format(
        'revoke all privileges on function %s from %I cascade',
        v_function,
        v_grantee_name
      );
    end loop;

    if exists (
      select 1
      from pg_proc procedure_row
      cross join lateral aclexplode(
        coalesce(
          procedure_row.proacl,
          acldefault('f', procedure_row.proowner)
        )
      ) expanded_acl
      where procedure_row.oid = v_function
        and expanded_acl.grantee <> procedure_row.proowner
    ) then
      raise exception 'Context projection helper did not converge to owner-only: %',
        v_signature
        using errcode = '42501';
    end if;
  end loop;
end;
$owner_only_acl$;

select public.reconcile_conversation_context_projections();

-- CREATE TRIGGER has no IF NOT EXISTS form. Do not drop an existing trigger on
-- replay: hosted migration roles may execute this owner-defined function while
-- not owning the table itself. CREATE OR REPLACE above preserves the function
-- OID referenced by an existing trigger, so an exact valid trigger can remain.
do $$
begin
  if not exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.conversations'::regclass
      and trigger.tgname = 'trg_conversations_context_projection_commit'
      and not trigger.tgisinternal
  ) then
    execute $trigger$
      create constraint trigger trg_conversations_context_projection_commit
      after insert or update of context_type, context_id
      on public.conversations
      deferrable initially deferred
      for each row execute function
        public.enforce_conversation_context_projection_at_commit()
    $trigger$;
  elsif exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.conversations'::regclass
      and trigger.tgname = 'trg_conversations_context_projection_commit'
      and (
        not trigger.tgdeferrable
        or not trigger.tginitdeferred
        or trigger.tgfoid <>
          'public.enforce_conversation_context_projection_at_commit()'::regprocedure
      )
  ) then
    raise exception 'Existing conversation projection trigger has an incompatible definition'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.conversation_contexts'::regclass
      and trigger.tgname = 'trg_conversation_contexts_projection_commit'
      and not trigger.tgisinternal
  ) then
    execute $trigger$
      create constraint trigger trg_conversation_contexts_projection_commit
      after insert or update or delete
      on public.conversation_contexts
      deferrable initially deferred
      for each row execute function
        public.enforce_conversation_context_projection_at_commit()
    $trigger$;
  elsif exists (
    select 1
    from pg_trigger trigger
    where trigger.tgrelid = 'public.conversation_contexts'::regclass
      and trigger.tgname = 'trg_conversation_contexts_projection_commit'
      and (
        not trigger.tgdeferrable
        or not trigger.tginitdeferred
        or trigger.tgfoid <>
          'public.enforce_conversation_context_projection_at_commit()'::regprocedure
      )
  ) then
    raise exception 'Existing context-ledger projection trigger has an incompatible definition'
      using errcode = '23514';
  end if;
end;
$$;

-- Force the newly created deferred constraints once inside the migration. A
-- later application transaction still receives normal commit-time semantics.
set constraints all immediate;
set constraints all deferred;

commit;
