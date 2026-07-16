-- ARCHIVED PROPOSAL: NEVER DEPLOY OR INCLUDE IN core_schema.sql.
-- The reviewed production implementation was split into migrations
-- 20260715130000 through 20260715220000. This draft remains only as historical
-- design evidence because its broad apply_workshop_invoice_backfill command is
-- intentionally not a supported repair boundary.
-- Make the payment terminal the only interactive owner of sales-invoice tax,
-- keep workshop records as operational mirrors, and preserve workshop child IDs
-- across invoice/job round-trips.
--
-- Historical repair is deliberately NOT executed by this migration. The
-- service-role-only apply_workshop_invoice_backfill() command below records a
-- complete audit trail and must be invoked with an explicit batch key.

begin;

alter table public.mechanic_jobs
  add column if not exists estimated_duration_hours numeric(8,2);

alter table public.mechanic_jobs
  drop constraint if exists mechanic_jobs_estimated_duration_hours_valid;
alter table public.mechanic_jobs
  add constraint mechanic_jobs_estimated_duration_hours_valid
  check (
    estimated_duration_hours is null
    or estimated_duration_hours between 0 and 10000
  );

comment on column public.mechanic_jobs.estimated_duration_hours is
  'Operational estimate entered in the workshop form. It does not post payroll, revenue, or inventory.';

create unique index if not exists uq_mechanic_jobs_invoice_id
  on public.mechanic_jobs(invoice_id)
  where invoice_id is not null;

create table if not exists public.workshop_invoice_backfill_runs (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  batch_key text not null,
  status text not null default 'running'
    check (status in ('running', 'completed', 'failed')),
  created_by uuid references auth.users(id) on delete set null,
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  summary jsonb not null default '{}'::jsonb,
  unique (tenant_id, batch_key)
);

create table if not exists public.workshop_invoice_backfill_rows (
  id uuid primary key default gen_random_uuid(),
  run_id uuid not null references public.workshop_invoice_backfill_runs(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  invoice_id uuid references public.sales_invoices(id) on delete set null,
  entity_type text not null,
  entity_id uuid,
  changed_fields text[] not null default '{}',
  before_data jsonb not null default '{}'::jsonb,
  after_data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_workshop_invoice_backfill_rows_run
  on public.workshop_invoice_backfill_rows(run_id, created_at, id);

alter table public.workshop_invoice_backfill_runs enable row level security;
alter table public.workshop_invoice_backfill_rows enable row level security;

drop policy if exists workshop_invoice_backfill_runs_select
  on public.workshop_invoice_backfill_runs;
create policy workshop_invoice_backfill_runs_select
  on public.workshop_invoice_backfill_runs
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists workshop_invoice_backfill_rows_select
  on public.workshop_invoice_backfill_rows;
create policy workshop_invoice_backfill_rows_select
  on public.workshop_invoice_backfill_rows
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

revoke insert, update, delete
  on public.workshop_invoice_backfill_runs,
     public.workshop_invoice_backfill_rows
  from public, anon, authenticated;
grant select
  on public.workshop_invoice_backfill_runs,
     public.workshop_invoice_backfill_rows
  to authenticated;

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

  -- Direct SQL migrations/tests and service-role trigger calls do not carry an
  -- employee JWT. Enforce the graph at row level for those callers, and apply
  -- the employee-tenant check only to PostgREST anon/authenticated sessions.
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
  perform public.assert_workshop_tenant_access(NEW.tenant_id);

  if TG_TABLE_NAME = 'mechanic_jobs' then
    if NEW.customer_id is not null then
      select tenant_id into v_parent_tenant
        from public.customers where id = NEW.customer_id;
      if v_parent_tenant is distinct from NEW.tenant_id then
        raise exception 'Workshop customer must belong to the job tenant';
      end if;
    end if;

    if NEW.bike_id is not null then
      select tenant_id, customer_id into v_parent_tenant, v_customer_id
        from public.bikes where id = NEW.bike_id;
      if v_parent_tenant is distinct from NEW.tenant_id
         or v_customer_id is distinct from NEW.customer_id then
        raise exception 'Workshop bicycle must belong to the job customer and tenant';
      end if;
    end if;

    if NEW.invoice_id is not null then
      select tenant_id into v_parent_tenant
        from public.sales_invoices where id = NEW.invoice_id;
      if v_parent_tenant is distinct from NEW.tenant_id then
        raise exception 'Workshop invoice must belong to the job tenant';
      end if;
    end if;

    if coalesce(NEW.discount_amount, 0) < 0 then
      raise exception 'Workshop discount cannot be negative';
    end if;
  elsif TG_TABLE_NAME = 'mechanic_job_bikes' then
    select tenant_id, customer_id into v_parent_tenant, v_customer_id
      from public.mechanic_jobs where id = NEW.job_id;
    if v_parent_tenant is distinct from NEW.tenant_id then
      raise exception 'Job bicycle must belong to the parent job tenant';
    end if;

    select tenant_id into v_parent_tenant
      from public.bikes where id = NEW.bike_id and customer_id = v_customer_id;
    if v_parent_tenant is distinct from NEW.tenant_id then
      raise exception 'Job bicycle must belong to the job customer and tenant';
    end if;
  elsif TG_TABLE_NAME = 'mechanic_job_items' then
    select tenant_id into v_parent_tenant
      from public.mechanic_jobs where id = NEW.job_id;
    if v_parent_tenant is distinct from NEW.tenant_id then
      raise exception 'Workshop item must belong to the parent job tenant';
    end if;

    if NEW.job_bike_id is not null then
      select tenant_id, job_id into v_parent_tenant, v_parent_job
        from public.mechanic_job_bikes where id = NEW.job_bike_id;
      if v_parent_tenant is distinct from NEW.tenant_id
         or v_parent_job is distinct from NEW.job_id then
        raise exception 'Workshop item bicycle must belong to the same job and tenant';
      end if;
    end if;

    if NEW.product_id is not null then
      select tenant_id into v_parent_tenant
        from public.products where id = NEW.product_id;
      if v_parent_tenant is distinct from NEW.tenant_id then
        raise exception 'Workshop product must belong to the item tenant';
      end if;
    end if;

    if NEW.service_product_id is not null then
      select tenant_id into v_parent_tenant
        from public.products where id = NEW.service_product_id;
      if v_parent_tenant is distinct from NEW.tenant_id then
        raise exception 'Workshop service must belong to the item tenant';
      end if;
    end if;
  end if;

  return NEW;
end;
$$;

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

create or replace function public.guard_sales_invoice_tax_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.tax_treatment is distinct from OLD.tax_treatment
     and auth.uid() is not null
     and current_setting('app.payment_tax_command', true) is distinct from 'true' then
    raise exception 'El IVA de la factura se controla únicamente desde el panel de pago.'
      using errcode = '42501';
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_sales_invoice_tax_ownership
  on public.sales_invoices;
create trigger trg_sales_invoice_tax_ownership
  before update of tax_treatment on public.sales_invoices
  for each row execute function public.guard_sales_invoice_tax_ownership();

create or replace function public.validate_sales_payment_integrity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice record;
  v_existing_paid numeric(12,2);
  v_remaining numeric(12,2);
  v_amount numeric(12,2);
  v_net numeric(12,2);
begin
  if TG_OP = 'DELETE' then
    return OLD;
  end if;

  if NEW.invoice_id is null then
    raise exception 'El pago debe pertenecer a una factura de venta.';
  end if;

  select id, tenant_id, invoice_number, total, tax_treatment
    into v_invoice
    from public.sales_invoices
   where id = NEW.invoice_id
   for update;

  if not found then
    raise exception 'La factura de venta asociada al pago no existe.';
  end if;

  if NEW.tenant_id is null then
    NEW.tenant_id := v_invoice.tenant_id;
  end if;
  if NEW.tenant_id is distinct from v_invoice.tenant_id then
    raise exception 'El pago no pertenece al mismo tenant que la factura de venta.';
  end if;

  perform public.assert_workshop_tenant_access(NEW.tenant_id);

  v_amount := public.clp_round(NEW.amount);
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  NEW.amount := v_amount;
  NEW.invoice_reference := coalesce(
    nullif(NEW.invoice_reference, ''),
    v_invoice.invoice_number
  );

  -- Payment rows mirror the invoice classification. Cash settlement itself is
  -- accounting-only and never recognizes a second copy of IVA or revenue.
  NEW.tax_treatment := v_invoice.tax_treatment;
  if v_invoice.tax_treatment = 'tax_included' then
    v_net := public.clp_round(v_amount / 1.19);
    NEW.net_amount := v_net;
    NEW.iva_amount := v_amount - v_net;
  else
    NEW.net_amount := v_amount;
    NEW.iva_amount := 0;
  end if;

  if NEW.deleted_at is not null then
    return NEW;
  end if;

  select public.clp_round(coalesce(sum(amount), 0))
    into v_existing_paid
    from public.sales_payments
   where invoice_id = NEW.invoice_id
     and deleted_at is null
     and id is distinct from NEW.id;

  v_remaining := public.clp_round(
    greatest(coalesce(v_invoice.total, 0) - v_existing_paid, 0)
  );

  if v_amount > v_remaining then
    raise exception 'El pago excede el saldo pendiente de la factura de venta. Saldo pendiente: %, monto enviado: %.',
      v_remaining, v_amount;
  end if;

  return NEW;
end;
$$;

create or replace function public.register_sales_payment_with_invoice_tax(
  p_invoice_id uuid,
  p_payment_method_id uuid,
  p_idempotency_key text,
  p_amount numeric,
  p_date timestamptz,
  p_reference text,
  p_notes text,
  p_tax_treatment text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant uuid := public.user_tenant_id();
  v_invoice public.sales_invoices%rowtype;
  v_existing public.sales_payments%rowtype;
  v_payment public.sales_payments%rowtype;
  v_key text := btrim(coalesce(p_idempotency_key, ''));
  v_amount numeric := public.clp_round(p_amount);
  v_status text;
begin
  if v_actor is null or v_tenant is null then
    raise exception 'Authenticated employee tenant is required' using errcode = '42501';
  end if;
  if p_tax_treatment not in ('no_tax', 'tax_included') then
    raise exception 'Tratamiento tributario inválido.';
  end if;
  if v_key = '' or length(v_key) > 128 then
    raise exception 'La clave idempotente del pago es obligatoria y admite hasta 128 caracteres.';
  end if;
  if v_amount <= 0 then
    raise exception 'El monto del pago debe ser mayor a cero.';
  end if;
  if p_date is null then
    raise exception 'La fecha del pago es obligatoria.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant::text || ':sales-payment:' || v_key, 0)
  );

  select * into v_existing
    from public.sales_payments
   where tenant_id = v_tenant
     and idempotency_key = v_key;

  if found then
    if v_existing.invoice_id is distinct from p_invoice_id
       or v_existing.payment_method_id is distinct from p_payment_method_id
       or v_existing.amount is distinct from v_amount
       or v_existing.date is distinct from p_date then
      raise exception 'La clave idempotente ya fue usada con otro contenido de pago.'
        using errcode = 'integrity_constraint_violation';
    end if;
    return jsonb_build_object(
      'payment', to_jsonb(v_existing),
      'invoice_id', v_existing.invoice_id,
      'replayed', true
    );
  end if;

  select * into v_invoice
    from public.sales_invoices
   where id = p_invoice_id
     and tenant_id = v_tenant
   for update;
  if not found then
    raise exception 'Factura no encontrada para el tenant activo.' using errcode = '42501';
  end if;

  if lower(v_invoice.status) in (
    'cancelled', 'cancelado', 'cancelada', 'anulado', 'anulada'
  ) then
    raise exception 'No se puede pagar una factura anulada.';
  end if;

  if not exists (
    select 1
      from public.payment_methods pm
     where pm.id = p_payment_method_id
       and pm.tenant_id = v_tenant
       and pm.is_active
  ) then
    raise exception 'Medio de pago no encontrado o inactivo para el tenant activo.';
  end if;

  if v_amount > public.clp_round(greatest(v_invoice.total - v_invoice.paid_amount, 0)) then
    raise exception 'El pago excede el saldo pendiente de la factura de venta.';
  end if;

  -- Paying a draft/sent invoice posts it first. This guarantees that the
  -- invoice-owned inventory and revenue/IVA journal are created before the
  -- payment trigger settles accounts receivable.
  v_status := case
    when lower(v_invoice.status) in (
      'draft', 'borrador', 'sent', 'enviado', 'enviada', 'issued', 'emitido', 'emitida'
    ) then 'confirmed'
    else v_invoice.status
  end;

  perform set_config('app.payment_tax_command', 'true', true);
  update public.sales_invoices
     set tax_treatment = p_tax_treatment,
         status = v_status,
         updated_at = clock_timestamp()
   where id = p_invoice_id;
  perform set_config('app.payment_tax_command', '', true);

  insert into public.sales_payments (
    tenant_id,
    invoice_id,
    invoice_reference,
    payment_method_id,
    idempotency_key,
    amount,
    date,
    reference,
    notes,
    tax_treatment
  ) values (
    v_tenant,
    p_invoice_id,
    v_invoice.invoice_number,
    p_payment_method_id,
    v_key,
    v_amount,
    p_date,
    nullif(btrim(coalesce(p_reference, '')), ''),
    nullif(btrim(coalesce(p_notes, '')), ''),
    p_tax_treatment
  )
  returning * into v_payment;

  return jsonb_build_object(
    'payment', to_jsonb(v_payment),
    'invoice_id', p_invoice_id,
    'replayed', false
  );
exception
  when others then
    perform set_config('app.payment_tax_command', '', true);
    raise;
end;
$$;

revoke all on function public.register_sales_payment_with_invoice_tax(
  uuid, uuid, text, numeric, timestamptz, text, text, text
) from public, anon;
grant execute on function public.register_sales_payment_with_invoice_tax(
  uuid, uuid, text, numeric, timestamptz, text, text, text
) to authenticated;

create or replace function public.recalculate_mechanic_job_costs(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_parts numeric(12,2) := 0;
  v_labor numeric(12,2) := 0;
  v_gross numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
  v_tax numeric(12,2) := 0;
  v_treatment text := 'no_tax';
begin
  if p_job_id is null then return; end if;
  if current_setting('app.syncing_invoice_to_job', true) = 'true' then return; end if;

  select * into v_job
    from public.mechanic_jobs
   where id = p_job_id
   for update;
  if not found then return; end if;
  perform public.assert_workshop_tenant_access(v_job.tenant_id);

  select
    coalesce(sum(case when coalesce(item_type, 'product') = 'product' then total_price else 0 end), 0),
    coalesce(sum(case when coalesce(item_type, 'product') in ('service', 'adhoc') then total_price else 0 end), 0)
    into v_parts, v_labor
    from public.mechanic_job_items
   where job_id = p_job_id;

  v_gross := public.clp_round(v_parts + v_labor);
  v_discount := public.clp_round(coalesce(v_job.discount_amount, 0));
  if v_discount < 0 or v_discount > v_gross then
    raise exception 'El descuento del trabajo debe estar entre cero y el subtotal (%).', v_gross;
  end if;
  v_total := v_gross - v_discount;

  if v_job.invoice_id is not null then
    select * into v_invoice
      from public.sales_invoices
     where id = v_job.invoice_id
       and tenant_id = v_job.tenant_id;
    if found then
      v_total := v_invoice.total;
      v_tax := v_invoice.iva_amount;
      v_treatment := v_invoice.tax_treatment;
    end if;
  end if;

  update public.mechanic_jobs
     set parts_cost = v_parts,
         labor_cost = v_labor,
         final_cost = v_gross - v_discount,
         tax_amount = v_tax,
         total_cost = v_total,
         tax_treatment = v_treatment,
         updated_at = clock_timestamp()
   where id = p_job_id;
end;
$$;

create or replace function public.sync_invoice_items_to_job(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_job_id uuid;
  v_parts numeric(12,2) := 0;
  v_labor numeric(12,2) := 0;
begin
  if p_invoice_id is null then return; end if;
  if current_setting('app.syncing_job_to_invoice', true) = 'true' then return; end if;

  select * into v_invoice
    from public.sales_invoices
   where id = p_invoice_id
   for update;
  if not found then return; end if;
  perform public.assert_workshop_tenant_access(v_invoice.tenant_id);

  select id into v_job_id
    from public.mechanic_jobs
   where invoice_id = p_invoice_id
     and tenant_id = v_invoice.tenant_id
   for update;
  if v_job_id is null then return; end if;

  create temporary table if not exists pg_temp.workshop_desired_items (
    item_id uuid primary key,
    ord bigint not null,
    job_bike_id uuid,
    product_id uuid,
    service_product_id uuid,
    product_name text not null,
    product_sku text,
    quantity numeric(10,2) not null,
    unit_price numeric(12,2) not null,
    total_price numeric(12,2) not null,
    notes text,
    item_type text not null
  ) on commit drop;
  truncate pg_temp.workshop_desired_items;

  insert into pg_temp.workshop_desired_items (
    item_id, ord, job_bike_id, product_id, service_product_id,
    product_name, product_sku, quantity, unit_price, total_price, notes, item_type
  )
  select
    case
      when existing.id is not null then existing.id
      else gen_random_uuid()
    end,
    item.ordinality,
    case
      when job_bike.id is not null then job_bike.id
      else null
    end,
    case when normalized.item_type = 'product' then product.id else null end,
    case when normalized.item_type = 'service' then product.id else null end,
    coalesce(nullif(item.value->>'product_name', ''), product.name, 'Artículo'),
    coalesce(nullif(item.value->>'product_sku', ''), product.sku),
    greatest(coalesce(nullif(item.value->>'quantity', '')::numeric, 1), 0.01),
    public.clp_round(coalesce(nullif(item.value->>'unit_price', '')::numeric, 0)),
    public.clp_round(
      coalesce(
        nullif(item.value->>'line_total', '')::numeric,
        coalesce(nullif(item.value->>'quantity', '')::numeric, 1)
          * coalesce(nullif(item.value->>'unit_price', '')::numeric, 0)
          - coalesce(nullif(item.value->>'discount', '')::numeric, 0)
      )
    ),
    nullif(coalesce(item.value->>'description', item.value->>'notes', ''), ''),
    normalized.item_type
  from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb))
       with ordinality as item(value, ordinality)
  cross join lateral (
    select case
      when nullif(item.value->>'item_type', '') in ('product', 'service', 'adhoc')
        then item.value->>'item_type'
      when coalesce(nullif(item.value->>'is_catalog_product', '')::boolean, true) = false
        then 'adhoc'
      when coalesce(nullif(item.value->>'is_service', '')::boolean, false)
        then 'service'
      else 'product'
    end as item_type
  ) normalized
  left join public.mechanic_job_items existing
    on existing.id = case
      when coalesce(item.value->>'id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (item.value->>'id')::uuid
      else null
    end
   and existing.job_id = v_job_id
   and existing.tenant_id = v_invoice.tenant_id
  left join public.mechanic_job_bikes job_bike
    on job_bike.id = case
      when coalesce(item.value->>'job_bike_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (item.value->>'job_bike_id')::uuid
      else null
    end
   and job_bike.job_id = v_job_id
   and job_bike.tenant_id = v_invoice.tenant_id
  left join public.products product
    on product.id = case
      when coalesce(item.value->>'product_id', '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (item.value->>'product_id')::uuid
      else null
    end
   and product.tenant_id = v_invoice.tenant_id;

  perform set_config('app.syncing_invoice_to_job', 'true', true);

  insert into public.mechanic_job_items (
    id, tenant_id, job_id, job_bike_id, product_id, service_product_id,
    product_name, product_sku, quantity, unit_price, total_price,
    notes, description, item_type, created_at, updated_at
  )
  select
    item_id, v_invoice.tenant_id, v_job_id, job_bike_id, product_id,
    service_product_id, product_name, product_sku, quantity, unit_price,
    total_price, notes, notes, item_type, clock_timestamp(), clock_timestamp()
  from pg_temp.workshop_desired_items
  order by ord
  on conflict (id) do update
  set tenant_id = excluded.tenant_id,
      job_id = excluded.job_id,
      job_bike_id = excluded.job_bike_id,
      product_id = excluded.product_id,
      service_product_id = excluded.service_product_id,
      product_name = excluded.product_name,
      product_sku = excluded.product_sku,
      quantity = excluded.quantity,
      unit_price = excluded.unit_price,
      total_price = excluded.total_price,
      notes = excluded.notes,
      description = excluded.description,
      item_type = excluded.item_type,
      updated_at = clock_timestamp();

  delete from public.mechanic_job_items item
   where item.job_id = v_job_id
     and item.tenant_id = v_invoice.tenant_id
     and not exists (
       select 1 from pg_temp.workshop_desired_items desired
        where desired.item_id = item.id
     );

  select
    coalesce(sum(case when item_type = 'product' then total_price else 0 end), 0),
    coalesce(sum(case when item_type in ('service', 'adhoc') then total_price else 0 end), 0)
    into v_parts, v_labor
    from public.mechanic_job_items
   where job_id = v_job_id;

  with totals as (
    select
      job_bike.id,
      coalesce(sum(case when item.item_type = 'product' then item.total_price else 0 end), 0) as parts_cost,
      coalesce(sum(case when item.item_type in ('service', 'adhoc') then item.total_price else 0 end), 0) as labor_cost
    from public.mechanic_job_bikes job_bike
    left join public.mechanic_job_items item on item.job_bike_id = job_bike.id
    where job_bike.job_id = v_job_id
    group by job_bike.id
  )
  update public.mechanic_job_bikes job_bike
     set parts_cost = totals.parts_cost,
         labor_cost = totals.labor_cost,
         subtotal = totals.parts_cost + totals.labor_cost,
         updated_at = clock_timestamp()
    from totals
   where job_bike.id = totals.id;

  update public.mechanic_jobs
     set parts_cost = v_parts,
         labor_cost = v_labor,
         final_cost = v_invoice.total,
         estimated_cost = v_invoice.total,
         tax_amount = v_invoice.iva_amount,
         total_cost = v_invoice.total,
         tax_treatment = v_invoice.tax_treatment,
         is_invoiced = true,
         updated_at = clock_timestamp()
   where id = v_job_id;

  perform set_config('app.syncing_invoice_to_job', '', true);
exception
  when others then
    perform set_config('app.syncing_invoice_to_job', '', true);
    raise;
end;
$$;

create or replace function public.sync_invoice_status_to_job(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice public.sales_invoices%rowtype;
  v_job_id uuid;
begin
  if p_invoice_id is null then return; end if;
  select * into v_invoice from public.sales_invoices where id = p_invoice_id;
  if not found then return; end if;
  perform public.assert_workshop_tenant_access(v_invoice.tenant_id);

  select id into v_job_id
    from public.mechanic_jobs
   where invoice_id = p_invoice_id
     and tenant_id = v_invoice.tenant_id;
  if v_job_id is null then return; end if;

  update public.mechanic_jobs
     set is_invoiced = true,
         is_paid = lower(v_invoice.status) in ('paid', 'pagado', 'pagada'),
         tax_treatment = v_invoice.tax_treatment,
         tax_amount = v_invoice.iva_amount,
         total_cost = v_invoice.total,
         updated_at = clock_timestamp()
   where id = v_job_id;
end;
$$;

create or replace function public.sync_job_to_invoice(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_parts numeric(12,2) := 0;
  v_labor numeric(12,2) := 0;
  v_gross numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
begin
  if p_job_id is null then return; end if;
  if current_setting('app.syncing_invoice_to_job', true) = 'true' then return; end if;

  select * into v_job
    from public.mechanic_jobs
   where id = p_job_id
   for update;
  if not found or v_job.invoice_id is null then return; end if;
  perform public.assert_workshop_tenant_access(v_job.tenant_id);

  select * into v_invoice
    from public.sales_invoices
   where id = v_job.invoice_id
     and tenant_id = v_job.tenant_id
   for update;
  if not found then
    raise exception 'La factura vinculada al trabajo no existe en el mismo tenant.';
  end if;

  for v_item in
    select item.*,
           coalesce(nullif(concat_ws(' ', bike.brand, bike.model), ''), 'Bicicleta') as bike_name
      from public.mechanic_job_items item
      left join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
      left join public.bikes bike on bike.id = job_bike.bike_id
     where item.job_id = p_job_id
       and item.tenant_id = v_job.tenant_id
     order by item.created_at, item.id
  loop
    v_items := v_items || jsonb_build_object(
      'id', v_item.id,
      'product_id', case
        when coalesce(v_item.item_type, 'product') = 'service'
          then coalesce(v_item.service_product_id::text, '')
        when coalesce(v_item.item_type, 'product') = 'product'
          then coalesce(v_item.product_id::text, '')
        else ''
      end,
      'product_name', v_item.product_name,
      'product_sku', coalesce(v_item.product_sku, ''),
      'description', coalesce(v_item.notes, v_item.description, ''),
      'item_type', coalesce(v_item.item_type, 'product'),
      'is_service', coalesce(v_item.item_type, 'product') = 'service',
      'is_catalog_product',
        coalesce(v_item.item_type, 'product') <> 'adhoc'
        and coalesce(v_item.product_id, v_item.service_product_id) is not null,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'discount', 0,
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0),
      'job_bike_id', v_item.job_bike_id,
      'bike_name', case when v_item.job_bike_id is null then null else v_item.bike_name end
    );

    if coalesce(v_item.item_type, 'product') = 'product' then
      v_parts := v_parts + coalesce(v_item.total_price, 0);
    else
      v_labor := v_labor + coalesce(v_item.total_price, 0);
    end if;
  end loop;

  v_gross := public.clp_round(v_parts + v_labor);
  v_discount := public.clp_round(coalesce(v_job.discount_amount, 0));
  if v_discount < 0 or v_discount > v_gross then
    raise exception 'El descuento del trabajo debe estar entre cero y el subtotal (%).', v_gross;
  end if;
  v_total := v_gross - v_discount;

  -- Do not set app.syncing_job_to_invoice here. The invoice trigger must run
  -- its inventory/accounting side effects when a posted invoice's physical
  -- item signature changes. The ID-preserving invoice->job sync is safe to
  -- execute afterward and cannot recurse through the disabled legacy writer.
  update public.sales_invoices
     set items = v_items,
         subtotal = v_total,
         total = v_total,
         discount_amount = v_discount,
         updated_at = clock_timestamp()
   where id = v_invoice.id;

  perform public.recalculate_sales_invoice_payments(v_invoice.id);
end;
$$;

create or replace function public.create_invoice_from_mechanic_job(p_job_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_invoice_id uuid;
  v_invoice_number text;
  v_items jsonb := '[]'::jsonb;
  v_item record;
  v_gross numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
begin
  select * into v_job
    from public.mechanic_jobs
   where id = p_job_id
   for update;
  if not found then return null; end if;
  perform public.assert_workshop_tenant_access(v_job.tenant_id);

  if v_job.invoice_id is not null then
    perform public.sync_job_to_invoice(p_job_id);
    return v_job.invoice_id;
  end if;

  select * into v_customer
    from public.customers
   where id = v_job.customer_id
     and tenant_id = v_job.tenant_id;
  if not found then
    raise exception 'Cliente del trabajo no encontrado en el mismo tenant.';
  end if;

  for v_item in
    select item.*,
           coalesce(nullif(concat_ws(' ', bike.brand, bike.model), ''), 'Bicicleta') as bike_name
      from public.mechanic_job_items item
      left join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
      left join public.bikes bike on bike.id = job_bike.bike_id
     where item.job_id = p_job_id
       and item.tenant_id = v_job.tenant_id
     order by item.created_at, item.id
  loop
    v_items := v_items || jsonb_build_object(
      'id', v_item.id,
      'product_id', case
        when coalesce(v_item.item_type, 'product') = 'service'
          then coalesce(v_item.service_product_id::text, '')
        when coalesce(v_item.item_type, 'product') = 'product'
          then coalesce(v_item.product_id::text, '')
        else ''
      end,
      'product_name', v_item.product_name,
      'product_sku', coalesce(v_item.product_sku, ''),
      'description', coalesce(v_item.notes, v_item.description, ''),
      'item_type', coalesce(v_item.item_type, 'product'),
      'is_service', coalesce(v_item.item_type, 'product') = 'service',
      'is_catalog_product',
        coalesce(v_item.item_type, 'product') <> 'adhoc'
        and coalesce(v_item.product_id, v_item.service_product_id) is not null,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'discount', 0,
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0),
      'job_bike_id', v_item.job_bike_id,
      'bike_name', case when v_item.job_bike_id is null then null else v_item.bike_name end
    );
    v_gross := v_gross + coalesce(v_item.total_price, 0);
  end loop;

  v_gross := public.clp_round(v_gross);
  v_discount := public.clp_round(coalesce(v_job.discount_amount, 0));
  if v_discount < 0 or v_discount > v_gross then
    raise exception 'El descuento del trabajo debe estar entre cero y el subtotal (%).', v_gross;
  end if;
  v_total := v_gross - v_discount;
  v_invoice_number := public.get_next_document_number(v_job.tenant_id, 'sales_invoice');

  insert into public.sales_invoices (
    tenant_id, invoice_number, customer_id, customer_name, customer_rut,
    date, due_date, reference, status, subtotal, iva_amount, net_amount,
    tax_treatment, total, paid_amount, balance, discount_amount, items,
    source, created_at, updated_at
  ) values (
    v_job.tenant_id, v_invoice_number, v_customer.id, v_customer.name,
    v_customer.rut, coalesce(v_job.arrival_date, v_job.created_at),
    coalesce(v_job.arrival_date, v_job.created_at) + interval '30 days',
    'Trabajo ' || v_job.job_number, 'draft', v_total, 0, v_total,
    'no_tax', v_total, 0, v_total, v_discount, v_items,
    'mechanic_job', clock_timestamp(), clock_timestamp()
  ) returning id into v_invoice_id;

  update public.mechanic_jobs
     set invoice_id = v_invoice_id,
         is_invoiced = true,
         tax_treatment = 'no_tax',
         tax_amount = 0,
         total_cost = v_total,
         final_cost = v_total,
         updated_at = clock_timestamp()
   where id = p_job_id;

  return v_invoice_id;
end;
$$;

revoke all on function public.create_invoice_from_mechanic_job(uuid)
  from public, anon;
revoke all on function public.sync_invoice_items_to_job(uuid)
  from public, anon;
revoke all on function public.sync_invoice_status_to_job(uuid)
  from public, anon;
revoke all on function public.sync_job_to_invoice(uuid)
  from public, anon;

grant execute on function public.create_invoice_from_mechanic_job(uuid)
  to authenticated, service_role;
grant execute on function public.sync_invoice_items_to_job(uuid)
  to authenticated, service_role;
grant execute on function public.sync_invoice_status_to_job(uuid)
  to authenticated, service_role;
grant execute on function public.sync_job_to_invoice(uuid)
  to authenticated, service_role;

create or replace view public.workshop_invoice_backfill_preview
with (security_invoker = true)
as
select
  job.tenant_id,
  job.id as job_id,
  job.job_number,
  invoice.id as invoice_id,
  invoice.invoice_number,
  job.tax_treatment is distinct from invoice.tax_treatment
    or job.tax_amount is distinct from invoice.iva_amount
    or job.total_cost is distinct from invoice.total as job_financial_mirror_mismatch,
  coalesce(item_stats.missing_tenant_count, 0) as missing_item_tenant_count,
  coalesce(item_stats.item_count, 0) as job_item_count,
  jsonb_array_length(coalesce(invoice.items, '[]'::jsonb)) as invoice_item_count,
  coalesce(item_stats.item_count, 0)
    <> jsonb_array_length(coalesce(invoice.items, '[]'::jsonb))
    as item_count_mismatch,
  coalesce(invoice_stats.missing_stable_id_count, 0) as invoice_items_without_stable_job_id,
  coalesce(payment_stats.tax_mismatch_count, 0) as payment_tax_mismatch_count,
  coalesce(bike_stats.cost_mismatch_count, 0) as job_bike_cost_mismatch_count
from public.mechanic_jobs job
join public.sales_invoices invoice
  on invoice.id = job.invoice_id
 and invoice.tenant_id = job.tenant_id
left join lateral (
  select
    count(*) as item_count,
    count(*) filter (where item.tenant_id is null) as missing_tenant_count
  from public.mechanic_job_items item
  where item.job_id = job.id
) item_stats on true
left join lateral (
  select count(*) filter (
    where coalesce(element.value->>'id', '') !~*
      '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
       or not exists (
         select 1
         from public.mechanic_job_items item
         where item.id = case
           when coalesce(element.value->>'id', '') ~*
             '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
             then (element.value->>'id')::uuid
           else null
         end
           and item.job_id = job.id
       )
  ) as missing_stable_id_count
  from jsonb_array_elements(coalesce(invoice.items, '[]'::jsonb)) element(value)
) invoice_stats on true
left join lateral (
  select count(*) filter (
    where payment.tax_treatment is distinct from invoice.tax_treatment
       or payment.net_amount is distinct from case
         when invoice.tax_treatment = 'tax_included'
           then public.clp_round(payment.amount / 1.19)
         else payment.amount
       end
       or payment.iva_amount is distinct from case
         when invoice.tax_treatment = 'tax_included'
           then payment.amount - public.clp_round(payment.amount / 1.19)
         else 0
       end
  ) as tax_mismatch_count
  from public.sales_payments payment
  where payment.invoice_id = invoice.id
    and payment.deleted_at is null
) payment_stats on true
left join lateral (
  select count(*) filter (
    where job_bike.parts_cost is distinct from totals.parts_cost
       or job_bike.labor_cost is distinct from totals.labor_cost
       or job_bike.subtotal is distinct from totals.parts_cost + totals.labor_cost
  ) as cost_mismatch_count
  from public.mechanic_job_bikes job_bike
  cross join lateral (
    select
      coalesce(sum(case when item.item_type = 'product' then item.total_price else 0 end), 0) as parts_cost,
      coalesce(sum(case when item.item_type in ('service', 'adhoc') then item.total_price else 0 end), 0) as labor_cost
    from public.mechanic_job_items item
    where item.job_bike_id = job_bike.id
  ) totals
  where job_bike.job_id = job.id
) bike_stats on true;

grant select on public.workshop_invoice_backfill_preview to authenticated;

create or replace function public.apply_workshop_invoice_backfill(
  p_tenant_id uuid,
  p_batch_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run public.workshop_invoice_backfill_runs%rowtype;
  v_key text := btrim(coalesce(p_batch_key, ''));
  v_job record;
  v_item record;
  v_payment record;
  v_job_bike record;
  v_rebuilt_items jsonb;
  v_rebuilt_diagnosis jsonb;
  v_summary jsonb;
  v_invoice_item_count integer;
  v_job_item_count integer;
begin
  if p_tenant_id is null or not exists (
    select 1 from public.tenants where id = p_tenant_id
  ) then
    raise exception 'A valid tenant is required for workshop backfill.';
  end if;
  if v_key = '' or length(v_key) > 128 then
    raise exception 'Backfill batch key is required and must be at most 128 characters.';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_tenant_id::text || ':workshop-backfill:' || v_key, 0)
  );

  select * into v_run
    from public.workshop_invoice_backfill_runs
   where tenant_id = p_tenant_id
     and batch_key = v_key;
  if found then
    if v_run.status = 'completed' then
      return v_run.summary || jsonb_build_object('replayed', true, 'run_id', v_run.id);
    end if;
    raise exception 'Backfill batch % already exists with status %.', v_key, v_run.status;
  end if;

  insert into public.workshop_invoice_backfill_runs (
    tenant_id, batch_key, created_by
  ) values (
    p_tenant_id, v_key, auth.uid()
  ) returning * into v_run;

  -- Recover tenant visibility without guessing financial meaning.
  for v_item in
    select item.*, job.tenant_id as expected_tenant_id, job.invoice_id
      from public.mechanic_job_items item
      join public.mechanic_jobs job on job.id = item.job_id
     where job.tenant_id = p_tenant_id
       and item.tenant_id is distinct from job.tenant_id
  loop
    insert into public.workshop_invoice_backfill_rows (
      run_id, tenant_id, job_id, invoice_id, entity_type, entity_id,
      changed_fields, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_item.job_id, v_item.invoice_id,
      'mechanic_job_item', v_item.id, array['tenant_id'],
      jsonb_build_object('tenant_id', v_item.tenant_id),
      jsonb_build_object('tenant_id', v_item.expected_tenant_id)
    );
    update public.mechanic_job_items
       set tenant_id = v_item.expected_tenant_id,
           updated_at = clock_timestamp()
     where id = v_item.id;
  end loop;

  -- Stamp a stable mechanic_job_items UUID only for an exact, unique line
  -- match. Ambiguous/unmatched historical lines remain explicit manual review;
  -- this command never pairs rows by position or guesses which line is right.
  for v_job in
    select job.id as job_id, job.invoice_id, invoice.items
      from public.mechanic_jobs job
      join public.sales_invoices invoice
        on invoice.id = job.invoice_id
       and invoice.tenant_id = job.tenant_id
     where job.tenant_id = p_tenant_id
  loop
    v_invoice_item_count := jsonb_array_length(coalesce(v_job.items, '[]'::jsonb));
    select count(*) into v_job_item_count
      from public.mechanic_job_items where job_id = v_job.job_id;

    if v_invoice_item_count = v_job_item_count then
      select coalesce(jsonb_agg(
               case
                 when existing_item.id is not null then invoice_item.value
                 when candidate.candidate_count = 1 then
                   invoice_item.value || jsonb_build_object('id', candidate.match_id)
                 else invoice_item.value
               end
               order by invoice_item.ordinality
             ), '[]'::jsonb)
        into v_rebuilt_items
        from jsonb_array_elements(coalesce(v_job.items, '[]'::jsonb))
             with ordinality invoice_item(value, ordinality)
        left join lateral (
          select item.id
            from public.mechanic_job_items item
           where item.job_id = v_job.job_id
             and item.id::text = invoice_item.value ->> 'id'
           limit 1
        ) existing_item on true
        left join lateral (
          select min(item.id::text)::uuid as match_id,
                 count(*) as candidate_count
            from public.mechanic_job_items item
           where item.job_id = v_job.job_id
             and lower(btrim(coalesce(item.product_name, ''))) =
                 lower(btrim(coalesce(invoice_item.value ->> 'product_name', '')))
             and item.quantity = coalesce(
               nullif(invoice_item.value ->> 'quantity', '')::numeric,
               0
             )
             and item.unit_price = coalesce(
               nullif(invoice_item.value ->> 'unit_price', '')::numeric,
               0
             )
             and (
               coalesce(invoice_item.value ->> 'product_id', '') = ''
               or invoice_item.value ->> 'product_id' in (
                 coalesce(item.product_id::text, ''),
                 coalesce(item.service_product_id::text, '')
               )
             )
             and (
               coalesce(invoice_item.value ->> 'job_bike_id', '') = ''
               or invoice_item.value ->> 'job_bike_id' =
                  coalesce(item.job_bike_id::text, '')
             )
        ) candidate on true;

      if v_rebuilt_items is distinct from v_job.items then
        insert into public.workshop_invoice_backfill_rows (
          run_id, tenant_id, job_id, invoice_id, entity_type, entity_id,
          changed_fields, before_data, after_data
        ) values (
          v_run.id, p_tenant_id, v_job.job_id, v_job.invoice_id,
          'sales_invoice', v_job.invoice_id, array['items.id'],
          jsonb_build_object('items', v_job.items),
          jsonb_build_object('items', v_rebuilt_items)
        );
        perform set_config('app.syncing_job_to_invoice', 'true', true);
        update public.sales_invoices
           set items = v_rebuilt_items,
               updated_at = clock_timestamp()
         where id = v_job.invoice_id;
        perform set_config('app.syncing_job_to_invoice', '', true);
      end if;
    end if;
  end loop;

  -- Invoice is the canonical financial owner. Repair only operational mirrors.
  for v_job in
    select job.id as job_id,
           job.invoice_id,
           to_jsonb(job) as before_data,
           invoice.tax_treatment,
           invoice.iva_amount,
           invoice.total,
           invoice.subtotal,
           invoice.status
      from public.mechanic_jobs job
      join public.sales_invoices invoice
        on invoice.id = job.invoice_id
       and invoice.tenant_id = job.tenant_id
     where job.tenant_id = p_tenant_id
       and (
         job.tax_treatment is distinct from invoice.tax_treatment
         or job.tax_amount is distinct from invoice.iva_amount
         or job.total_cost is distinct from invoice.total
         or job.is_paid is distinct from (
           lower(invoice.status) in ('paid', 'pagado', 'pagada')
         )
       )
  loop
    update public.mechanic_jobs
       set tax_treatment = v_job.tax_treatment,
           tax_amount = v_job.iva_amount,
           total_cost = v_job.total,
           final_cost = v_job.total,
           estimated_cost = v_job.total,
           is_invoiced = true,
           is_paid = lower(v_job.status) in ('paid', 'pagado', 'pagada'),
           updated_at = clock_timestamp()
     where id = v_job.job_id;

    insert into public.workshop_invoice_backfill_rows (
      run_id, tenant_id, job_id, invoice_id, entity_type, entity_id,
      changed_fields, before_data, after_data
    )
    select
      v_run.id, p_tenant_id, v_job.job_id, v_job.invoice_id,
      'mechanic_job', v_job.job_id,
      array['tax_treatment', 'tax_amount', 'total_cost', 'is_paid'],
      v_job.before_data,
      to_jsonb(job)
    from public.mechanic_jobs job where job.id = v_job.job_id;
  end loop;

  for v_payment in
    select payment.*, invoice.tax_treatment as invoice_tax_treatment,
           job.id as job_id
      from public.sales_payments payment
      join public.sales_invoices invoice on invoice.id = payment.invoice_id
      left join public.mechanic_jobs job on job.invoice_id = invoice.id
     where payment.tenant_id = p_tenant_id
       and payment.deleted_at is null
       and (
         payment.tax_treatment is distinct from invoice.tax_treatment
         or payment.net_amount is distinct from case
           when invoice.tax_treatment = 'tax_included'
             then public.clp_round(payment.amount / 1.19)
           else payment.amount
         end
         or payment.iva_amount is distinct from case
           when invoice.tax_treatment = 'tax_included'
             then payment.amount - public.clp_round(payment.amount / 1.19)
           else 0
         end
       )
  loop
    insert into public.workshop_invoice_backfill_rows (
      run_id, tenant_id, job_id, invoice_id, entity_type, entity_id,
      changed_fields, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_payment.job_id, v_payment.invoice_id,
      'sales_payment', v_payment.id,
      array['tax_treatment', 'net_amount', 'iva_amount'],
      jsonb_build_object(
        'tax_treatment', v_payment.tax_treatment,
        'net_amount', v_payment.net_amount,
        'iva_amount', v_payment.iva_amount
      ),
      jsonb_build_object(
        'tax_treatment', v_payment.invoice_tax_treatment,
        'net_amount', case when v_payment.invoice_tax_treatment = 'tax_included'
          then public.clp_round(v_payment.amount / 1.19) else v_payment.amount end,
        'iva_amount', case when v_payment.invoice_tax_treatment = 'tax_included'
          then v_payment.amount - public.clp_round(v_payment.amount / 1.19) else 0 end
      )
    );
    update public.sales_payments
       set tax_treatment = v_payment.invoice_tax_treatment,
           updated_at = clock_timestamp()
     where id = v_payment.id;
  end loop;

  -- Normalize the legacy 0..1 wear fraction into the canonical 0..100 unit.
  for v_job_bike in
    select job_bike.*, job.invoice_id
      from public.mechanic_job_bikes job_bike
      join public.mechanic_jobs job on job.id = job_bike.job_id
     where job_bike.tenant_id = p_tenant_id
       and (
         coalesce(
           job_bike.diagnosis_sheet_data #>> '{drivetrain,chain_wear_percent}',
           ''
         ) ~ '^0\.[0-9]+$'
         or coalesce(
           job_bike.diagnosis_sheet_data #>> '{front_brake,pad_wear_percent}',
           ''
         ) ~ '^0\.[0-9]+$'
         or coalesce(
           job_bike.diagnosis_sheet_data #>> '{rear_brake,pad_wear_percent}',
           ''
         ) ~ '^0\.[0-9]+$'
       )
  loop
    v_rebuilt_diagnosis := v_job_bike.diagnosis_sheet_data;
    if coalesce(
      v_rebuilt_diagnosis #>> '{drivetrain,chain_wear_percent}', ''
    ) ~ '^0\.[0-9]+$' then
      v_rebuilt_diagnosis := jsonb_set(
        v_rebuilt_diagnosis,
        '{drivetrain,chain_wear_percent}',
        to_jsonb(
          (v_rebuilt_diagnosis #>> '{drivetrain,chain_wear_percent}')::numeric * 100
        ),
        true
      );
    end if;
    if coalesce(
      v_rebuilt_diagnosis #>> '{front_brake,pad_wear_percent}', ''
    ) ~ '^0\.[0-9]+$' then
      v_rebuilt_diagnosis := jsonb_set(
        v_rebuilt_diagnosis,
        '{front_brake,pad_wear_percent}',
        to_jsonb(
          (v_rebuilt_diagnosis #>> '{front_brake,pad_wear_percent}')::numeric * 100
        ),
        true
      );
    end if;
    if coalesce(
      v_rebuilt_diagnosis #>> '{rear_brake,pad_wear_percent}', ''
    ) ~ '^0\.[0-9]+$' then
      v_rebuilt_diagnosis := jsonb_set(
        v_rebuilt_diagnosis,
        '{rear_brake,pad_wear_percent}',
        to_jsonb(
          (v_rebuilt_diagnosis #>> '{rear_brake,pad_wear_percent}')::numeric * 100
        ),
        true
      );
    end if;

    insert into public.workshop_invoice_backfill_rows (
      run_id, tenant_id, job_id, invoice_id, entity_type, entity_id,
      changed_fields, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_job_bike.job_id, v_job_bike.invoice_id,
      'mechanic_job_bike', v_job_bike.id, array['diagnosis_sheet_data.wear_percent'],
      jsonb_build_object('diagnosis_sheet_data', v_job_bike.diagnosis_sheet_data),
      jsonb_build_object('diagnosis_sheet_data', v_rebuilt_diagnosis)
    );
    update public.mechanic_job_bikes
       set diagnosis_sheet_data = v_rebuilt_diagnosis,
           diagnosis_sheet_updated_at = clock_timestamp(),
           updated_at = clock_timestamp()
     where id = v_job_bike.id;
  end loop;

  for v_job_bike in
    select job_bike.*, job.invoice_id,
           coalesce(sum(case when item.item_type = 'product' then item.total_price else 0 end), 0) as expected_parts,
           coalesce(sum(case when item.item_type in ('service', 'adhoc') then item.total_price else 0 end), 0) as expected_labor
      from public.mechanic_job_bikes job_bike
      join public.mechanic_jobs job on job.id = job_bike.job_id
      left join public.mechanic_job_items item on item.job_bike_id = job_bike.id
     where job_bike.tenant_id = p_tenant_id
     group by job_bike.id, job.invoice_id
     having job_bike.parts_cost is distinct from
              coalesce(sum(case when item.item_type = 'product' then item.total_price else 0 end), 0)
         or job_bike.labor_cost is distinct from
              coalesce(sum(case when item.item_type in ('service', 'adhoc') then item.total_price else 0 end), 0)
         or job_bike.subtotal is distinct from
              coalesce(sum(item.total_price), 0)
  loop
    insert into public.workshop_invoice_backfill_rows (
      run_id, tenant_id, job_id, invoice_id, entity_type, entity_id,
      changed_fields, before_data, after_data
    ) values (
      v_run.id, p_tenant_id, v_job_bike.job_id, v_job_bike.invoice_id,
      'mechanic_job_bike', v_job_bike.id,
      array['parts_cost', 'labor_cost', 'subtotal'],
      jsonb_build_object(
        'parts_cost', v_job_bike.parts_cost,
        'labor_cost', v_job_bike.labor_cost,
        'subtotal', v_job_bike.subtotal
      ),
      jsonb_build_object(
        'parts_cost', v_job_bike.expected_parts,
        'labor_cost', v_job_bike.expected_labor,
        'subtotal', v_job_bike.expected_parts + v_job_bike.expected_labor
      )
    );
    update public.mechanic_job_bikes
       set parts_cost = v_job_bike.expected_parts,
           labor_cost = v_job_bike.expected_labor,
           subtotal = v_job_bike.expected_parts + v_job_bike.expected_labor,
           updated_at = clock_timestamp()
     where id = v_job_bike.id;
  end loop;

  select jsonb_build_object(
    'run_id', v_run.id,
    'tenant_id', p_tenant_id,
    'batch_key', v_key,
    'changed_rows', count(*),
    'changed_by_entity', coalesce(jsonb_object_agg(entity_type, entity_count), '{}'::jsonb),
    'manual_review_item_count_mismatches', (
      select count(*)
      from public.workshop_invoice_backfill_preview preview
      where preview.tenant_id = p_tenant_id and preview.item_count_mismatch
    ),
    'manual_review_unmatched_or_ambiguous_invoice_lines', (
      select coalesce(sum(preview.invoice_items_without_stable_job_id), 0)
      from public.workshop_invoice_backfill_preview preview
      where preview.tenant_id = p_tenant_id
    ),
    'replayed', false
  ) into v_summary
  from (
    select entity_type, count(*) as entity_count
    from public.workshop_invoice_backfill_rows
    where run_id = v_run.id
    group by entity_type
  ) counts;

  update public.workshop_invoice_backfill_runs
     set status = 'completed',
         completed_at = clock_timestamp(),
         summary = v_summary
   where id = v_run.id;

  return v_summary;
exception
  when others then
    perform set_config('app.syncing_job_to_invoice', '', true);
    raise;
end;
$$;

revoke all on function public.apply_workshop_invoice_backfill(uuid, text)
  from public, anon, authenticated;
grant execute on function public.apply_workshop_invoice_backfill(uuid, text)
  to service_role;

commit;
