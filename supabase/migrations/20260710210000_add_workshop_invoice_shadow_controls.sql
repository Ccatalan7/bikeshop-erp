-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-10 (shadow mode only)
-- Shadow-only ERP control for the workshop job -> sales invoice boundary.
-- This migration does not update/backfill any existing job, invoice, stock, or journal row.

begin;

create table if not exists public.workshop_invoice_control_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  control_mode text not null default 'shadow'
    check (control_mode in ('shadow', 'enforce')),
  expected_inventory_owner text not null default 'sales_invoice'
    check (expected_inventory_owner = 'sales_invoice'),
  activated_at timestamp with time zone,
  activated_by uuid references auth.users(id),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists public.workshop_invoice_control_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  job_id uuid,
  invoice_id uuid,
  operation_id uuid,
  control_mode text not null check (control_mode in ('shadow', 'enforce')),
  event_type text not null check (
    event_type in ('job_stock_writer_attempt', 'job_journal_writer_attempt')
  ),
  actor_id uuid references auth.users(id),
  transaction_id bigint not null default txid_current(),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamp with time zone not null default clock_timestamp()
);

-- Audit identifiers must remain immutable even if a legacy source document is
-- later removed. Do not let FK actions null out historical linkage.
alter table public.workshop_invoice_control_events
  drop constraint if exists workshop_invoice_control_events_job_id_fkey;
alter table public.workshop_invoice_control_events
  drop constraint if exists workshop_invoice_control_events_invoice_id_fkey;

create index if not exists idx_workshop_invoice_control_events_tenant_created
  on public.workshop_invoice_control_events(tenant_id, created_at desc);
create index if not exists idx_workshop_invoice_control_events_job
  on public.workshop_invoice_control_events(tenant_id, job_id, created_at desc)
  where job_id is not null;
create index if not exists idx_workshop_invoice_control_events_invoice
  on public.workshop_invoice_control_events(tenant_id, invoice_id, created_at desc)
  where invoice_id is not null;

alter table public.workshop_invoice_control_settings enable row level security;
alter table public.workshop_invoice_control_events enable row level security;

drop policy if exists workshop_invoice_control_settings_select
  on public.workshop_invoice_control_settings;
create policy workshop_invoice_control_settings_select
  on public.workshop_invoice_control_settings
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists workshop_invoice_control_events_select
  on public.workshop_invoice_control_events;
create policy workshop_invoice_control_events_select
  on public.workshop_invoice_control_events
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke insert, update, delete on public.workshop_invoice_control_settings
  from public, anon, authenticated;
revoke insert, update, delete on public.workshop_invoice_control_events
  from public, anon, authenticated;
grant select on public.workshop_invoice_control_settings to authenticated;
grant select on public.workshop_invoice_control_events to authenticated;

comment on table public.workshop_invoice_control_settings is
  'Tenant-scoped rollout gate. No row means shadow mode. Enforce is activated only after reviewed observations.';
comment on table public.workshop_invoice_control_events is
  'Append-only evidence of attempted workshop-owned stock or revenue postings. Business rows are never rewritten by this table.';

create or replace function public.observe_workshop_owned_posting_attempt()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
  v_job_id uuid;
  v_invoice_id uuid;
  v_mode text := 'shadow';
  v_event_type text;
  v_reference text;
  v_operation_id uuid;
begin
  if TG_TABLE_NAME = 'stock_movements' then
    v_reference := coalesce(NEW.reference, '');
    if v_reference !~ '^mechanic_job:[0-9a-fA-F-]{36}(:reversed)?$' then
      return NEW;
    end if;

    v_event_type := 'job_stock_writer_attempt';
    v_tenant_id := NEW.tenant_id;
    v_operation_id := NEW.operation_id;

    if v_tenant_id is null then
      select product.tenant_id
        into v_tenant_id
        from public.products product
       where product.id = NEW.product_id;
    end if;

    begin
      v_job_id := split_part(v_reference, ':', 2)::uuid;
    exception when invalid_text_representation then
      v_job_id := null;
    end;
  elsif TG_TABLE_NAME = 'journal_entries' then
    if coalesce(NEW.source_module, '') <> 'mechanic_jobs' then
      return NEW;
    end if;

    v_event_type := 'job_journal_writer_attempt';
    v_tenant_id := NEW.tenant_id;
    v_operation_id := NEW.operation_id;

    select job.id, job.tenant_id, job.invoice_id
      into v_job_id, v_tenant_id, v_invoice_id
      from public.mechanic_jobs job
     where (v_tenant_id is null or job.tenant_id = v_tenant_id)
       and job.job_number = NEW.source_reference
     order by job.created_at desc
     limit 1;

    if v_job_id is null and NEW.source_reference ~ '^[0-9a-fA-F-]{36}$' then
      select job.id, job.tenant_id, job.invoice_id
        into v_job_id, v_tenant_id, v_invoice_id
        from public.mechanic_jobs job
       where job.id = NEW.source_reference::uuid
         and (v_tenant_id is null or job.tenant_id = v_tenant_id);
    end if;
  else
    return NEW;
  end if;

  if v_job_id is not null and v_invoice_id is null then
    select job.invoice_id
      into v_invoice_id
      from public.mechanic_jobs job
     where job.id = v_job_id;
  end if;

  if v_tenant_id is null then
    raise warning 'Workshop ownership shadow could not resolve tenant for %.%',
      TG_TABLE_SCHEMA, TG_TABLE_NAME;
    return NEW;
  end if;

  select setting.control_mode
    into v_mode
    from public.workshop_invoice_control_settings setting
   where setting.tenant_id = v_tenant_id;
  v_mode := coalesce(v_mode, 'shadow');

  insert into public.workshop_invoice_control_events (
    tenant_id,
    job_id,
    invoice_id,
    operation_id,
    control_mode,
    event_type,
    actor_id,
    payload
  ) values (
    v_tenant_id,
    v_job_id,
    v_invoice_id,
    v_operation_id,
    v_mode,
    v_event_type,
    auth.uid(),
    jsonb_build_object(
      'table', TG_TABLE_SCHEMA || '.' || TG_TABLE_NAME,
      'operation', TG_OP,
      'expected_inventory_owner', 'sales_invoice',
      'attempted_row', to_jsonb(NEW)
    )
  );

  if v_mode = 'enforce' then
    raise log 'ERP_WORKSHOP_OWNERSHIP_BLOCK tenant=% job=% invoice=% event=%',
      v_tenant_id, v_job_id, v_invoice_id, v_event_type;
    raise exception
      'Workshop jobs are operational documents; linked sales invoices exclusively own stock and revenue postings'
      using errcode = 'check_violation';
  end if;

  return NEW;
end;
$$;

revoke all on function public.observe_workshop_owned_posting_attempt()
  from public, anon, authenticated;

drop trigger if exists zz_workshop_invoice_owner_stock_shadow
  on public.stock_movements;
create trigger zz_workshop_invoice_owner_stock_shadow
  before insert on public.stock_movements
  for each row execute function public.observe_workshop_owned_posting_attempt();

drop trigger if exists zz_workshop_invoice_owner_journal_shadow
  on public.journal_entries;
create trigger zz_workshop_invoice_owner_journal_shadow
  before insert on public.journal_entries
  for each row execute function public.observe_workshop_owned_posting_attempt();

create or replace view public.workshop_invoice_ownership_control_view
with (security_invoker = true)
as
select
  job.tenant_id,
  job.id as job_id,
  job.job_number,
  job.status as job_status,
  job.invoice_id,
  invoice.invoice_number,
  invoice.status as invoice_status,
  coalesce(setting.control_mode, 'shadow') as control_mode,
  'sales_invoice'::text as expected_inventory_owner,
  coalesce(job_stock.movement_count, 0) as job_stock_movement_count,
  coalesce(job_journal.journal_count, 0) as job_journal_count,
  coalesce(invoice_stock.movement_count, 0) as invoice_stock_movement_count,
  coalesce(invoice_journal.journal_count, 0) as invoice_journal_count,
  case
    when coalesce(job_stock.movement_count, 0) > 0 then 'job_stock_writer_detected'
    when coalesce(job_journal.journal_count, 0) > 0 then 'job_journal_writer_detected'
    else 'compliant'
  end as control_status,
  job.created_at,
  job.updated_at
from public.mechanic_jobs job
left join public.sales_invoices invoice
  on invoice.id = job.invoice_id
 and invoice.tenant_id = job.tenant_id
left join public.workshop_invoice_control_settings setting
  on setting.tenant_id = job.tenant_id
left join lateral (
  select count(*)::bigint as movement_count
  from public.stock_movements movement
  where movement.tenant_id = job.tenant_id
    and movement.reference in (
      'mechanic_job:' || job.id::text,
      'mechanic_job:' || job.id::text || ':reversed'
    )
) job_stock on true
left join lateral (
  select count(*)::bigint as journal_count
  from public.journal_entries entry
  where entry.tenant_id = job.tenant_id
    and entry.source_module = 'mechanic_jobs'
    and entry.source_reference in (job.id::text, job.job_number)
) job_journal on true
left join lateral (
  select count(*)::bigint as movement_count
  from public.stock_movements movement
  where job.invoice_id is not null
    and movement.tenant_id = job.tenant_id
    and movement.reference = 'sales_invoice:' || job.invoice_id::text
) invoice_stock on true
left join lateral (
  select count(*)::bigint as journal_count
  from public.journal_entries entry
  where invoice.id is not null
    and entry.tenant_id = job.tenant_id
    and entry.source_module = 'sales_invoices'
    and entry.source_reference in (invoice.id::text, invoice.invoice_number)
) invoice_journal on true;

grant select on public.workshop_invoice_ownership_control_view to authenticated;

create or replace function public.checkpoint_workshop_invoice_ownership_shadow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice_id uuid;
  v_operation_text text;
  v_control record;
begin
  v_invoice_id := case when TG_OP = 'DELETE' then OLD.id else NEW.id end;
  v_operation_text := nullif(current_setting('app.inventory_operation_id', true), '');

  if v_operation_text is null then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  select control.*
    into v_control
    from public.workshop_invoice_ownership_control_view control
   where control.invoice_id = v_invoice_id
   limit 1;

  if not found then
    return case when TG_OP = 'DELETE' then OLD else NEW end;
  end if;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_text::uuid,
    'invariants_verified',
    case when v_control.control_status = 'compliant' then 'completed' else 'failed' end,
    'mechanic_job',
    v_control.job_id,
    jsonb_build_object(
      'control_name', 'workshop_invoice_owner',
      'job_number', v_control.job_number,
      'invoice_id', v_control.invoice_id,
      'invoice_number', v_control.invoice_number,
      'expected_inventory_owner', v_control.expected_inventory_owner,
      'control_mode', v_control.control_mode,
      'control_status', v_control.control_status,
      'job_stock_movement_count', v_control.job_stock_movement_count,
      'job_journal_count', v_control.job_journal_count,
      'invoice_stock_movement_count', v_control.invoice_stock_movement_count,
      'invoice_journal_count', v_control.invoice_journal_count
    )
  );

  return case when TG_OP = 'DELETE' then OLD else NEW end;
end;
$$;

revoke all on function public.checkpoint_workshop_invoice_ownership_shadow()
  from public, anon, authenticated;

drop trigger if exists zzy_workshop_invoice_ownership_shadow
  on public.sales_invoices;
create trigger zzy_workshop_invoice_ownership_shadow
  after insert or update or delete on public.sales_invoices
  for each row execute function public.checkpoint_workshop_invoice_ownership_shadow();

-- These legacy SECURITY DEFINER writers are trigger internals, not client RPCs.
-- Removing direct client execution closes an unaudited stock/accounting bypass
-- without changing trigger behavior or any persisted business row.
revoke all on function public.consume_mechanic_job_inventory(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.restore_mechanic_job_inventory(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.create_mechanic_job_journal_entry(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_mechanic_job_journal_entry(uuid)
  from public, anon, authenticated, service_role;

commit;
