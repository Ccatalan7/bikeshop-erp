-- Audited, replay-safe archive/restore for workshop jobs.
--
-- A mechanic job is an operational document. Archiving it never deletes or
-- rewrites its linked sales invoice, payments, stock movements, or journals.
-- Those financial records remain owned by the invoice and must use their own
-- correction workflows when the underlying sale did not occur.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter table public.mechanic_jobs
  add column if not exists archive_reason text,
  add column if not exists archive_operation_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'mechanic_jobs_archive_operation_tenant_fkey'
      and conrelid = 'public.mechanic_jobs'::regclass
  ) then
    alter table public.mechanic_jobs
      add constraint mechanic_jobs_archive_operation_tenant_fkey
      foreign key (tenant_id, archive_operation_id)
      references public.inventory_accounting_operations(tenant_id, id)
      on delete restrict;
  end if;
end;
$$;

create table if not exists public.mechanic_job_archive_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  job_id uuid not null references public.mechanic_jobs(id) on delete restrict,
  event_type text not null check (event_type in ('discarded', 'restored')),
  reason text not null check (btrim(reason) <> ''),
  actor_id uuid references auth.users(id) on delete set null,
  operation_key text not null,
  operation_id uuid not null,
  before_snapshot jsonb not null,
  after_snapshot jsonb not null,
  financial_snapshot jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key),
  foreign key (tenant_id, operation_id)
    references public.inventory_accounting_operations(tenant_id, id)
    on delete restrict
);

create index if not exists idx_mechanic_job_archive_events_job
  on public.mechanic_job_archive_events(tenant_id, job_id, occurred_at desc);

alter table public.mechanic_job_archive_events enable row level security;

drop policy if exists mechanic_job_archive_events_select
  on public.mechanic_job_archive_events;
create policy mechanic_job_archive_events_select
  on public.mechanic_job_archive_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke all on public.mechanic_job_archive_events
  from public, anon, authenticated, service_role;
grant select on public.mechanic_job_archive_events to authenticated;

create or replace function public.prevent_mechanic_job_archive_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Mechanic job archive events are append-only'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_mechanic_job_archive_event_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_job_archive_events_immutable
  on public.mechanic_job_archive_events;
create trigger trg_mechanic_job_archive_events_immutable
  before update or delete on public.mechanic_job_archive_events
  for each row execute function public.prevent_mechanic_job_archive_event_mutation();

create or replace function public.mechanic_job_archive_snapshot(p_row jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', p_row->'id',
    'job_number', p_row->'job_number',
    'status', p_row->'status',
    'status_id', p_row->'status_id',
    'job_type', p_row->'job_type',
    'workflow_kind', p_row->'workflow_kind',
    'intake_kind', p_row->'intake_kind',
    'quotation_status', p_row->'quotation_status',
    'customer_id', p_row->'customer_id',
    'bike_id', p_row->'bike_id',
    'invoice_id', p_row->'invoice_id',
    'total_cost', p_row->'total_cost',
    'is_invoiced', p_row->'is_invoiced',
    'is_paid', p_row->'is_paid',
    'deleted_at', p_row->'deleted_at',
    'deleted_by', p_row->'deleted_by',
    'archive_reason', p_row->'archive_reason',
    'archive_operation_id', p_row->'archive_operation_id',
    'updated_at', p_row->'updated_at'
  ));
$$;

revoke all on function public.mechanic_job_archive_snapshot(jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.set_mechanic_job_archived(
  p_job_id uuid,
  p_archived boolean,
  p_reason text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_reason text := nullif(btrim(p_reason), '');
  v_idempotency_key text := nullif(btrim(p_idempotency_key), '');
  v_event_type text := case when p_archived then 'discarded' else 'restored' end;
  v_action text := case when p_archived then 'archive' else 'restore' end;
  v_operation_key text;
  v_operation_id uuid := gen_random_uuid();
  v_event_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_after public.mechanic_jobs%rowtype;
  v_existing public.mechanic_job_archive_events%rowtype;
  v_before_snapshot jsonb;
  v_after_snapshot jsonb;
  v_financial_before jsonb;
  v_financial_after jsonb;
  v_item_count_before integer := 0;
  v_item_count_after integer := 0;
  v_bike_count_before integer := 0;
  v_bike_count_after integer := 0;
begin
  if p_archived is null then
    raise exception 'Debes indicar si el trabajo se elimina o se restaura.'
      using errcode = '22023';
  end if;

  if v_actor_id is null or v_tenant_id is null then
    raise exception 'Se requiere una sesión de trabajador autenticada.'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.user_profiles profile
    where profile.user_id = v_actor_id
      and profile.tenant_id = v_tenant_id
      and coalesce(profile.is_active, false)
  ) then
    raise exception 'El trabajador no tiene una membresía activa en este negocio.'
      using errcode = '42501';
  end if;

  if v_reason is null then
    raise exception 'Debes registrar el motivo de esta acción.'
      using errcode = '22023';
  end if;
  if v_idempotency_key is null then
    raise exception 'La acción requiere una clave de reintento.'
      using errcode = '22023';
  end if;

  v_operation_key := format(
    'mechanic_job_archive:%s:%s:%s',
    p_job_id,
    v_event_type,
    v_idempotency_key
  );

  select *
  into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.tenant_id = v_tenant_id
  for update;

  if not found then
    raise exception 'El trabajo no existe en este negocio.'
      using errcode = 'P0002';
  end if;

  select *
  into v_existing
  from public.mechanic_job_archive_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;

  if found then
    if v_existing.job_id is distinct from p_job_id
       or v_existing.event_type is distinct from v_event_type then
      raise exception 'La clave de reintento pertenece a otra acción.'
        using errcode = '23514';
    end if;
    return jsonb_build_object(
      'job_id', v_existing.job_id,
      'job_number', v_existing.after_snapshot->>'job_number',
      'archived', v_existing.event_type = 'discarded',
      'operation_id', v_existing.operation_id,
      'event_id', v_existing.id,
      'invoice_id', v_existing.financial_snapshot->>'invoice_id',
      'financial_effects_preserved', true,
      'replayed', true
    );
  end if;

  if p_archived and v_job.deleted_at is not null then
    raise exception 'El trabajo ya está en Eliminados.'
      using errcode = '23514';
  end if;
  if not p_archived and v_job.deleted_at is null then
    raise exception 'El trabajo ya está activo.'
      using errcode = '23514';
  end if;

  -- Serialize against invoice/payment posting when a financial owner exists.
  if v_job.invoice_id is not null then
    perform 1
    from public.sales_invoices invoice
    where invoice.id = v_job.invoice_id
      and invoice.tenant_id = v_tenant_id
    for update;
    if not found then
      raise exception 'El vínculo factura-trabajo está incompleto. No se aplicó ningún cambio.'
        using errcode = '23514';
    end if;
  end if;

  select count(*)::integer
  into v_item_count_before
  from public.mechanic_job_items item
  where item.job_id = v_job.id;

  select count(*)::integer
  into v_bike_count_before
  from public.mechanic_job_bikes job_bike
  where job_bike.job_id = v_job.id;

  select jsonb_build_object(
    'invoice_id', v_job.invoice_id,
    'invoice_status', invoice.status,
    'invoice_total', invoice.total,
    'invoice_paid_amount', invoice.paid_amount,
    'invoice_balance', invoice.balance,
    'active_payment_count', (
      select count(*)
      from public.sales_payments payment
      where payment.invoice_id = v_job.invoice_id
        and payment.tenant_id = v_tenant_id
        and payment.deleted_at is null
    ),
    'active_payment_total', (
      select coalesce(sum(payment.amount), 0)
      from public.sales_payments payment
      where payment.invoice_id = v_job.invoice_id
        and payment.tenant_id = v_tenant_id
        and payment.deleted_at is null
    ),
    'invoice_stock_movement_count', (
      select count(*)
      from public.stock_movements movement
      where movement.tenant_id = v_tenant_id
        and movement.reference = 'sales_invoice:' || v_job.invoice_id::text
    ),
    'invoice_journal_count', (
      select count(*)
      from public.journal_entries entry
      where entry.tenant_id = v_tenant_id
        and (
          entry.source_document_type = 'sales_invoice'
          and entry.source_document_id = v_job.invoice_id
          or entry.source_module = 'sales_invoices'
          and entry.source_reference = invoice.invoice_number
        )
    ),
    'job_stock_movement_count', (
      select count(*)
      from public.stock_movements movement
      where movement.tenant_id = v_tenant_id
        and (
          movement.reference = 'mechanic_job:' || v_job.id::text
          or movement.source_document_type = 'mechanic_job'
          and movement.source_document_id = v_job.id
        )
    ),
    'job_journal_count', (
      select count(*)
      from public.journal_entries entry
      where entry.tenant_id = v_tenant_id
        and (
          entry.source_document_type = 'mechanic_job'
          and entry.source_document_id = v_job.id
          or entry.source_module = 'mechanic_jobs'
          and entry.source_reference in (v_job.id::text, v_job.job_number)
        )
    )
  )
  into v_financial_before
  from (select 1) seed
  left join public.sales_invoices invoice
    on invoice.id = v_job.invoice_id
   and invoice.tenant_id = v_tenant_id;

  v_before_snapshot := public.mechanic_job_archive_snapshot(to_jsonb(v_job));

  insert into public.inventory_accounting_operations (
    id,
    tenant_id,
    operation_key,
    source_channel,
    action,
    document_type,
    document_id,
    actor_id,
    executor,
    old_status,
    new_status,
    before_snapshot,
    context
  ) values (
    v_operation_id,
    v_tenant_id,
    v_operation_key,
    'workshop_job_archive',
    v_action,
    'mechanic_job',
    v_job.id,
    v_actor_id,
    'database_command',
    case when p_archived then v_job.status else 'deleted' end,
    case when p_archived then 'deleted' else v_job.status end,
    v_before_snapshot,
    jsonb_build_object(
      'reason', v_reason,
      'job_number', v_job.job_number,
      'event_type', v_event_type,
      'financial_owner', case
        when v_job.invoice_id is null then 'none'
        else 'sales_invoice'
      end,
      'financial_snapshot_before', v_financial_before,
      'item_count_before', v_item_count_before,
      'bike_count_before', v_bike_count_before
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accepted',
    'started',
    'mechanic_job',
    v_job.id,
    jsonb_build_object(
      'action', v_action,
      'reason', v_reason,
      'old_state', case when p_archived then 'active' else 'deleted' end,
      'new_state', case when p_archived then 'deleted' else 'active' end
    )
  );

  if p_archived then
    update public.mechanic_jobs
    set deleted_at = clock_timestamp(),
        deleted_by = v_actor_id,
        archive_reason = v_reason,
        archive_operation_id = v_operation_id
    where id = v_job.id
      and tenant_id = v_tenant_id;
  else
    -- Listing customer_id in SET deliberately re-runs the complete workshop
    -- tenant/customer/bicycle/invoice graph guard before restoration.
    update public.mechanic_jobs
    set deleted_at = null,
        deleted_by = null,
        archive_reason = null,
        archive_operation_id = null,
        customer_id = v_job.customer_id
    where id = v_job.id
      and tenant_id = v_tenant_id;
  end if;

  select *
  into v_after
  from public.mechanic_jobs job
  where job.id = v_job.id
    and job.tenant_id = v_tenant_id;

  select count(*)::integer
  into v_item_count_after
  from public.mechanic_job_items item
  where item.job_id = v_job.id;

  select count(*)::integer
  into v_bike_count_after
  from public.mechanic_job_bikes job_bike
  where job_bike.job_id = v_job.id;

  select jsonb_build_object(
    'invoice_id', v_after.invoice_id,
    'invoice_status', invoice.status,
    'invoice_total', invoice.total,
    'invoice_paid_amount', invoice.paid_amount,
    'invoice_balance', invoice.balance,
    'active_payment_count', (
      select count(*)
      from public.sales_payments payment
      where payment.invoice_id = v_after.invoice_id
        and payment.tenant_id = v_tenant_id
        and payment.deleted_at is null
    ),
    'active_payment_total', (
      select coalesce(sum(payment.amount), 0)
      from public.sales_payments payment
      where payment.invoice_id = v_after.invoice_id
        and payment.tenant_id = v_tenant_id
        and payment.deleted_at is null
    ),
    'invoice_stock_movement_count', (
      select count(*)
      from public.stock_movements movement
      where movement.tenant_id = v_tenant_id
        and movement.reference = 'sales_invoice:' || v_after.invoice_id::text
    ),
    'invoice_journal_count', (
      select count(*)
      from public.journal_entries entry
      where entry.tenant_id = v_tenant_id
        and (
          entry.source_document_type = 'sales_invoice'
          and entry.source_document_id = v_after.invoice_id
          or entry.source_module = 'sales_invoices'
          and entry.source_reference = invoice.invoice_number
        )
    ),
    'job_stock_movement_count', (
      select count(*)
      from public.stock_movements movement
      where movement.tenant_id = v_tenant_id
        and (
          movement.reference = 'mechanic_job:' || v_after.id::text
          or movement.source_document_type = 'mechanic_job'
          and movement.source_document_id = v_after.id
        )
    ),
    'job_journal_count', (
      select count(*)
      from public.journal_entries entry
      where entry.tenant_id = v_tenant_id
        and (
          entry.source_document_type = 'mechanic_job'
          and entry.source_document_id = v_after.id
          or entry.source_module = 'mechanic_jobs'
          and entry.source_reference in (v_after.id::text, v_after.job_number)
        )
    )
  )
  into v_financial_after
  from (select 1) seed
  left join public.sales_invoices invoice
    on invoice.id = v_after.invoice_id
   and invoice.tenant_id = v_tenant_id;

  if (p_archived and v_after.deleted_at is null)
     or (not p_archived and v_after.deleted_at is not null)
     or v_item_count_before <> v_item_count_after
     or v_bike_count_before <> v_bike_count_after
     or v_financial_before is distinct from v_financial_after then
    raise exception 'La verificación final del trabajo falló. No se aplicó ningún cambio.'
      using errcode = '23514';
  end if;

  v_after_snapshot := public.mechanic_job_archive_snapshot(to_jsonb(v_after));

  insert into public.mechanic_job_archive_events (
    tenant_id,
    job_id,
    event_type,
    reason,
    actor_id,
    operation_key,
    operation_id,
    before_snapshot,
    after_snapshot,
    financial_snapshot
  ) values (
    v_tenant_id,
    v_job.id,
    v_event_type,
    v_reason,
    v_actor_id,
    v_operation_key,
    v_operation_id,
    v_before_snapshot,
    v_after_snapshot,
    v_financial_after
  )
  returning id into v_event_id;

  update public.inventory_accounting_operations
  set after_snapshot = v_after_snapshot,
      context = context || jsonb_build_object(
        'event_id', v_event_id,
        'financial_snapshot_after', v_financial_after,
        'item_count_after', v_item_count_after,
        'bike_count_after', v_bike_count_after
      )
  where id = v_operation_id
    and tenant_id = v_tenant_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'source_snapshotted',
    'completed',
    'mechanic_job',
    v_job.id,
    jsonb_build_object(
      'before', v_before_snapshot,
      'after', v_after_snapshot,
      'archive_event_id', v_event_id
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'inventory_applied',
    'completed',
    'mechanic_job',
    v_job.id,
    jsonb_build_object(
      'changed', false,
      'job_stock_movement_count',
        v_financial_after->'job_stock_movement_count',
      'invoice_stock_movement_count',
        v_financial_after->'invoice_stock_movement_count'
    )
  );

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id,
    'accounting_planned',
    'completed',
    'mechanic_job',
    v_job.id,
    jsonb_build_object(
      'changed', false,
      'linked_invoice_preserved', v_after.invoice_id is not null,
      'active_payment_count', v_financial_after->'active_payment_count',
      'invoice_journal_count', v_financial_after->'invoice_journal_count',
      'job_journal_count', v_financial_after->'job_journal_count'
    )
  );

  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    v_tenant_id,
    jsonb_build_object(
      'job_id', v_job.id,
      'job_number', v_job.job_number,
      'archived', p_archived,
      'archive_event_id', v_event_id,
      'financial_effects_preserved', true
    )
  );

  return jsonb_build_object(
    'job_id', v_job.id,
    'job_number', v_job.job_number,
    'archived', p_archived,
    'operation_id', v_operation_id,
    'event_id', v_event_id,
    'invoice_id', v_after.invoice_id,
    'financial_effects_preserved', true,
    'replayed', false
  );
end;
$$;

revoke all on function public.set_mechanic_job_archived(
  uuid, boolean, text, text
) from public, anon, service_role;
grant execute on function public.set_mechanic_job_archived(
  uuid, boolean, text, text
) to authenticated;

comment on function public.set_mechanic_job_archived(uuid, boolean, text, text)
is 'Atomically archives/restores a workshop job, preserving its complete operational and invoice-owned financial graph with append-only evidence.';

notify pgrst, 'reload schema';

commit;
