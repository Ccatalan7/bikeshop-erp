-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-15
-- Deployment verification: 18 audited null-tenant items repaired; zero graph
-- conflicts; three guards active; invoice/payment/stock/journal fingerprints
-- unchanged.
-- Purpose:
--   1. Repair only legacy mechanic_job_items whose tenant_id is null when the
--      parent job and every referenced product/bicycle prove one tenant.
--   2. Preserve immutable before/after evidence for every repaired row.
--   3. Enforce the customer/bicycle/invoice/product tenant graph on future
--      workshop writes without changing totals, status, stock or accounting.
--
-- Forward recovery:
--   If a client incompatibility appears, drop the three tenant-graph triggers
--   while leaving the corrected tenant_id values and immutable audit evidence
--   in place. Do not restore null tenant ownership.

begin;

create table if not exists public.workshop_tenant_graph_backfill_audit (
  id uuid primary key default gen_random_uuid(),
  batch_key text not null,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  mechanic_job_item_id uuid not null,
  mechanic_job_id uuid not null,
  before_tenant_id uuid,
  after_tenant_id uuid not null,
  evidence jsonb not null default '{}'::jsonb,
  repaired_at timestamptz not null default clock_timestamp(),
  unique (batch_key, mechanic_job_item_id)
);

comment on table public.workshop_tenant_graph_backfill_audit is
  'Immutable evidence for deterministic legacy mechanic_job_items tenant ownership repair.';

alter table public.workshop_tenant_graph_backfill_audit enable row level security;
revoke all on public.workshop_tenant_graph_backfill_audit
  from public, anon, authenticated, service_role;

create or replace function public.prevent_workshop_tenant_graph_audit_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  raise exception 'Workshop tenant graph backfill audit is immutable'
    using errcode = '55000';
end;
$$;

revoke all on function public.prevent_workshop_tenant_graph_audit_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_workshop_tenant_graph_backfill_audit_immutable
  on public.workshop_tenant_graph_backfill_audit;
create trigger trg_workshop_tenant_graph_backfill_audit_immutable
  before update or delete on public.workshop_tenant_graph_backfill_audit
  for each row execute function public.prevent_workshop_tenant_graph_audit_mutation();

do $$
begin
  if exists (
    select 1
    from public.mechanic_jobs job
    join public.customers customer on customer.id = job.customer_id
    where customer.tenant_id is distinct from job.tenant_id
  ) then
    raise exception 'Workshop tenant graph preflight failed: job/customer conflict';
  end if;

  if exists (
    select 1
    from public.mechanic_jobs job
    join public.bikes bike on bike.id = job.bike_id
    where bike.tenant_id is distinct from job.tenant_id
       or bike.customer_id is distinct from job.customer_id
  ) then
    raise exception 'Workshop tenant graph preflight failed: job/bicycle conflict';
  end if;

  if exists (
    select 1
    from public.mechanic_jobs job
    join public.sales_invoices invoice on invoice.id = job.invoice_id
    where invoice.tenant_id is distinct from job.tenant_id
  ) then
    raise exception 'Workshop tenant graph preflight failed: job/invoice conflict';
  end if;

  if exists (
    select 1 from public.mechanic_jobs
    where coalesce(discount_amount, 0) < 0
  ) then
    raise exception 'Workshop tenant graph preflight failed: negative job discount';
  end if;

  if exists (
    select 1
    from public.mechanic_job_bikes job_bike
    join public.mechanic_jobs job on job.id = job_bike.job_id
    join public.bikes bike on bike.id = job_bike.bike_id
    where job_bike.tenant_id is distinct from job.tenant_id
       or bike.tenant_id is distinct from job_bike.tenant_id
       or bike.customer_id is distinct from job.customer_id
  ) then
    raise exception 'Workshop tenant graph preflight failed: job bicycle graph conflict';
  end if;

  if exists (
    select 1
    from public.mechanic_job_items item
    join public.mechanic_jobs job on job.id = item.job_id
    where item.tenant_id is not null
      and item.tenant_id is distinct from job.tenant_id
  ) then
    raise exception 'Workshop tenant graph preflight failed: non-null item tenant conflict';
  end if;

  if exists (
    select 1
    from public.mechanic_job_items item
    join public.mechanic_jobs job on job.id = item.job_id
    join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
    where job_bike.tenant_id is distinct from job.tenant_id
       or job_bike.job_id is distinct from item.job_id
  ) then
    raise exception 'Workshop tenant graph preflight failed: item bicycle conflict';
  end if;

  if exists (
    select 1
    from public.mechanic_job_items item
    join public.mechanic_jobs job on job.id = item.job_id
    join public.products product on product.id = item.product_id
    where product.tenant_id is distinct from job.tenant_id
  ) then
    raise exception 'Workshop tenant graph preflight failed: item product conflict';
  end if;

  if exists (
    select 1
    from public.mechanic_job_items item
    join public.mechanic_jobs job on job.id = item.job_id
    join public.products product on product.id = item.service_product_id
    where product.tenant_id is distinct from job.tenant_id
  ) then
    raise exception 'Workshop tenant graph preflight failed: item service conflict';
  end if;
end;
$$;

insert into public.workshop_tenant_graph_backfill_audit (
  batch_key,
  tenant_id,
  mechanic_job_item_id,
  mechanic_job_id,
  before_tenant_id,
  after_tenant_id,
  evidence
)
select
  'workshop-tenant-graph-20260715-v1',
  job.tenant_id,
  item.id,
  job.id,
  item.tenant_id,
  job.tenant_id,
  jsonb_build_object(
    'parent_job_tenant_matches', true,
    'product_tenant_matches', product.id is null
      or product.tenant_id is not distinct from job.tenant_id,
    'service_tenant_matches', service_product.id is null
      or service_product.tenant_id is not distinct from job.tenant_id,
    'job_bike_tenant_matches', job_bike.id is null
      or (
        job_bike.tenant_id is not distinct from job.tenant_id
        and job_bike.job_id is not distinct from item.job_id
      )
  )
from public.mechanic_job_items item
join public.mechanic_jobs job on job.id = item.job_id
left join public.products product on product.id = item.product_id
left join public.products service_product on service_product.id = item.service_product_id
left join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
where item.tenant_id is null
on conflict (batch_key, mechanic_job_item_id) do nothing;

update public.mechanic_job_items item
set tenant_id = audit.after_tenant_id
from public.workshop_tenant_graph_backfill_audit audit
where audit.batch_key = 'workshop-tenant-graph-20260715-v1'
  and audit.mechanic_job_item_id = item.id
  and item.tenant_id is null;

do $$
begin
  if exists (
    select 1
    from public.mechanic_job_items item
    join public.mechanic_jobs job on job.id = item.job_id
    where item.tenant_id is distinct from job.tenant_id
  ) then
    raise exception 'Workshop tenant graph repair left an item tenant mismatch';
  end if;
end;
$$;

create or replace function public.assert_workshop_tenant_access(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_role text := coalesce(auth.role(), '');
begin
  if p_tenant_id is null then
    raise exception 'Workshop entity tenant is required' using errcode = '42501';
  end if;

  if v_role not in ('anon', 'authenticated') then
    return;
  end if;

  if v_role = 'anon' or v_actor is null then
    raise exception 'Authenticated employee tenant is required' using errcode = '42501';
  end if;

  if public.user_tenant_id() is distinct from p_tenant_id then
    raise exception 'Workshop entity does not belong to the active employee tenant'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assert_workshop_tenant_access(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.validate_workshop_tenant_graph()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_tenant uuid;
  v_parent_job uuid;
  v_customer_id uuid;
begin
  perform public.assert_workshop_tenant_access(new.tenant_id);

  if tg_table_name = 'mechanic_jobs' then
    if new.customer_id is not null then
      select tenant_id into v_parent_tenant
      from public.customers where id = new.customer_id;
      if v_parent_tenant is distinct from new.tenant_id then
        raise exception 'Workshop customer must belong to the job tenant';
      end if;
    end if;

    if new.bike_id is not null then
      select tenant_id, customer_id into v_parent_tenant, v_customer_id
      from public.bikes where id = new.bike_id;
      if v_parent_tenant is distinct from new.tenant_id
         or v_customer_id is distinct from new.customer_id then
        raise exception 'Workshop bicycle must belong to the job customer and tenant';
      end if;
    end if;

    if new.invoice_id is not null then
      select tenant_id into v_parent_tenant
      from public.sales_invoices where id = new.invoice_id;
      if v_parent_tenant is distinct from new.tenant_id then
        raise exception 'Workshop invoice must belong to the job tenant';
      end if;
    end if;

    if coalesce(new.discount_amount, 0) < 0 then
      raise exception 'Workshop discount cannot be negative';
    end if;
  elsif tg_table_name = 'mechanic_job_bikes' then
    select tenant_id, customer_id into v_parent_tenant, v_customer_id
    from public.mechanic_jobs where id = new.job_id;
    if v_parent_tenant is distinct from new.tenant_id then
      raise exception 'Job bicycle must belong to the parent job tenant';
    end if;

    select tenant_id into v_parent_tenant
    from public.bikes where id = new.bike_id and customer_id = v_customer_id;
    if v_parent_tenant is distinct from new.tenant_id then
      raise exception 'Job bicycle must belong to the job customer and tenant';
    end if;
  elsif tg_table_name = 'mechanic_job_items' then
    select tenant_id into v_parent_tenant
    from public.mechanic_jobs where id = new.job_id;
    if v_parent_tenant is distinct from new.tenant_id then
      raise exception 'Workshop item must belong to the parent job tenant';
    end if;

    if new.job_bike_id is not null then
      select tenant_id, job_id into v_parent_tenant, v_parent_job
      from public.mechanic_job_bikes where id = new.job_bike_id;
      if v_parent_tenant is distinct from new.tenant_id
         or v_parent_job is distinct from new.job_id then
        raise exception 'Workshop item bicycle must belong to the same job and tenant';
      end if;
    end if;

    if new.product_id is not null then
      select tenant_id into v_parent_tenant
      from public.products where id = new.product_id;
      if v_parent_tenant is distinct from new.tenant_id then
        raise exception 'Workshop product must belong to the item tenant';
      end if;
    end if;

    if new.service_product_id is not null then
      select tenant_id into v_parent_tenant
      from public.products where id = new.service_product_id;
      if v_parent_tenant is distinct from new.tenant_id then
        raise exception 'Workshop service must belong to the item tenant';
      end if;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.validate_workshop_tenant_graph()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_jobs_tenant_graph on public.mechanic_jobs;
create trigger trg_mechanic_jobs_tenant_graph
  before insert or update of tenant_id, customer_id, bike_id, invoice_id, discount_amount
  on public.mechanic_jobs
  for each row execute function public.validate_workshop_tenant_graph();

drop trigger if exists trg_mechanic_job_bikes_tenant_graph
  on public.mechanic_job_bikes;
create trigger trg_mechanic_job_bikes_tenant_graph
  before insert or update of tenant_id, job_id, bike_id
  on public.mechanic_job_bikes
  for each row execute function public.validate_workshop_tenant_graph();

drop trigger if exists trg_mechanic_job_items_tenant_graph
  on public.mechanic_job_items;
create trigger trg_mechanic_job_items_tenant_graph
  before insert or update of tenant_id, job_id, job_bike_id, product_id, service_product_id
  on public.mechanic_job_items
  for each row execute function public.validate_workshop_tenant_graph();

comment on function public.validate_workshop_tenant_graph() is
  'Rejects cross-tenant or cross-customer workshop relationships before persistence.';

commit;
