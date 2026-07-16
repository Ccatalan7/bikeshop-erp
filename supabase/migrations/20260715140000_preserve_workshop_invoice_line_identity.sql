-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-15
-- Live verification: stable-link index present; authenticated-only RPC ACL;
-- workshop, invoice, inventory, journal, and payment counts unchanged.
-- Preserve workshop line identity and technical service metadata across the
-- bidirectional mechanic-job / sales-invoice bridge. Tax remains owned by the
-- invoice/payment workflow; this migration does not run a payment backfill.
begin;

create unique index if not exists uq_mechanic_jobs_invoice_id
  on public.mechanic_jobs(invoice_id)
  where invoice_id is not null;

create or replace function public.assert_workshop_rpc_tenant(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(auth.role(), '');
  v_actor uuid := auth.uid();
begin
  if p_tenant_id is null then
    raise exception 'Workshop tenant is required' using errcode = '42501';
  end if;

  if v_role = 'anon' then
    raise exception 'Authenticated workshop access is required'
      using errcode = '42501';
  end if;

  if v_actor is not null
     and public.user_tenant_id() is distinct from p_tenant_id then
    raise exception 'Workshop record does not belong to the active tenant'
      using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assert_workshop_rpc_tenant(uuid)
  from public, anon, authenticated, service_role;

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
  perform public.assert_workshop_rpc_tenant(v_invoice.tenant_id);

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
    item_type text not null,
    service_configuration_data jsonb,
    system_key text,
    component_slot_key text,
    location_key text not null,
    intervention_type text,
    creates_lifecycle boolean not null
  ) on commit drop;
  truncate pg_temp.workshop_desired_items;

  insert into pg_temp.workshop_desired_items (
    item_id, ord, job_bike_id, product_id, service_product_id,
    product_name, product_sku, quantity, unit_price, total_price,
    notes, item_type, service_configuration_data, system_key,
    component_slot_key, location_key, intervention_type, creates_lifecycle
  )
  select
    coalesce(
      existing.id,
      case when candidate.match_count = 1 then candidate.item_id end,
      gen_random_uuid()
    ),
    invoice_item.ordinality,
    job_bike.id,
    case when normalized.item_type = 'product' then product.id end,
    case when normalized.item_type = 'service' then product.id end,
    coalesce(nullif(invoice_item.value->>'product_name', ''), product.name, 'Artículo'),
    coalesce(nullif(invoice_item.value->>'product_sku', ''), product.sku),
    greatest(coalesce(nullif(invoice_item.value->>'quantity', '')::numeric, 1), 0.01),
    round(coalesce(nullif(invoice_item.value->>'unit_price', '')::numeric, 0), 2),
    round(
      coalesce(
        nullif(invoice_item.value->>'line_total', '')::numeric,
        coalesce(nullif(invoice_item.value->>'quantity', '')::numeric, 1)
          * coalesce(nullif(invoice_item.value->>'unit_price', '')::numeric, 0)
          - coalesce(nullif(invoice_item.value->>'discount', '')::numeric, 0)
      ),
      2
    ),
    nullif(coalesce(invoice_item.value->>'description', invoice_item.value->>'notes', ''), ''),
    normalized.item_type,
    case
      when jsonb_typeof(invoice_item.value->'service_configuration_data') = 'object'
        then invoice_item.value->'service_configuration_data'
      else matched.service_configuration_data
    end,
    coalesce(nullif(invoice_item.value->>'system_key', ''), matched.system_key),
    coalesce(
      nullif(invoice_item.value->>'component_slot_key', ''),
      matched.component_slot_key
    ),
    coalesce(
      nullif(invoice_item.value->>'location_key', ''),
      matched.location_key,
      'none'
    ),
    coalesce(
      nullif(invoice_item.value->>'intervention_type', ''),
      matched.intervention_type
    ),
    case
      when invoice_item.value ? 'creates_lifecycle'
        then coalesce((invoice_item.value->>'creates_lifecycle')::boolean, false)
      else coalesce(matched.creates_lifecycle, false)
    end
  from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb))
       with ordinality as invoice_item(value, ordinality)
  cross join lateral (
    select
      case
        when coalesce(invoice_item.value->>'id', '') ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          then (invoice_item.value->>'id')::uuid
      end as item_id,
      case
        when coalesce(invoice_item.value->>'product_id', '') ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          then (invoice_item.value->>'product_id')::uuid
      end as product_id,
      case
        when coalesce(invoice_item.value->>'job_bike_id', '') ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          then (invoice_item.value->>'job_bike_id')::uuid
      end as job_bike_id
  ) parsed
  left join public.products product
    on product.id = parsed.product_id
   and product.tenant_id = v_invoice.tenant_id
  cross join lateral (
    select case
      when nullif(invoice_item.value->>'item_type', '') in ('product', 'service', 'adhoc')
        then invoice_item.value->>'item_type'
      when coalesce(nullif(invoice_item.value->>'is_catalog_product', '')::boolean, true) = false
        then 'adhoc'
      when coalesce(nullif(invoice_item.value->>'is_service', '')::boolean, false)
           or product.product_type = 'service'
        then 'service'
      else 'product'
    end as item_type
  ) normalized
  left join public.mechanic_job_bikes job_bike
    on job_bike.id = parsed.job_bike_id
   and job_bike.job_id = v_job_id
   and job_bike.tenant_id = v_invoice.tenant_id
  left join public.mechanic_job_items existing
    on existing.id = parsed.item_id
   and existing.job_id = v_job_id
   and existing.tenant_id = v_invoice.tenant_id
  left join lateral (
    select (array_agg(item.id order by item.id))[1] as item_id,
           count(*) as match_count
      from public.mechanic_job_items item
     where existing.id is null
       and item.job_id = v_job_id
       and item.tenant_id = v_invoice.tenant_id
       and item.job_bike_id is not distinct from job_bike.id
       and item.item_type = normalized.item_type
       and item.product_id is not distinct from
         case when normalized.item_type = 'product' then product.id end
       and item.service_product_id is not distinct from
         case when normalized.item_type = 'service' then product.id end
       and item.product_name = coalesce(
         nullif(invoice_item.value->>'product_name', ''),
         product.name,
         'Artículo'
       )
       and item.quantity = greatest(
         coalesce(nullif(invoice_item.value->>'quantity', '')::numeric, 1),
         0.01
       )
       and item.unit_price = round(
         coalesce(nullif(invoice_item.value->>'unit_price', '')::numeric, 0),
         2
       )
       and item.total_price = round(
         coalesce(
           nullif(invoice_item.value->>'line_total', '')::numeric,
           coalesce(nullif(invoice_item.value->>'quantity', '')::numeric, 1)
             * coalesce(nullif(invoice_item.value->>'unit_price', '')::numeric, 0)
             - coalesce(nullif(invoice_item.value->>'discount', '')::numeric, 0)
         ),
         2
       )
  ) candidate on true
  left join public.mechanic_job_items matched
    on matched.id = coalesce(
      existing.id,
      case when candidate.match_count = 1 then candidate.item_id end
    );

  perform set_config('app.syncing_invoice_to_job', 'true', true);

  insert into public.mechanic_job_items (
    id, tenant_id, job_id, job_bike_id, product_id, service_product_id,
    product_name, product_sku, quantity, unit_price, total_price,
    notes, description, item_type, service_configuration_data, system_key,
    component_slot_key, location_key, intervention_type, creates_lifecycle,
    created_at, updated_at
  )
  select
    item_id, v_invoice.tenant_id, v_job_id, job_bike_id, product_id,
    service_product_id, product_name, product_sku, quantity, unit_price,
    total_price, notes, notes, item_type, service_configuration_data,
    system_key, component_slot_key, location_key, intervention_type,
    creates_lifecycle, clock_timestamp(), clock_timestamp()
  from pg_temp.workshop_desired_items
  order by ord
  on conflict (id) do update
  set job_bike_id = excluded.job_bike_id,
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
      service_configuration_data = excluded.service_configuration_data,
      system_key = excluded.system_key,
      component_slot_key = excluded.component_slot_key,
      location_key = excluded.location_key,
      intervention_type = excluded.intervention_type,
      creates_lifecycle = excluded.creates_lifecycle,
      updated_at = clock_timestamp()
  where (
    mechanic_job_items.job_bike_id,
    mechanic_job_items.product_id,
    mechanic_job_items.service_product_id,
    mechanic_job_items.product_name,
    mechanic_job_items.product_sku,
    mechanic_job_items.quantity,
    mechanic_job_items.unit_price,
    mechanic_job_items.total_price,
    mechanic_job_items.notes,
    mechanic_job_items.description,
    mechanic_job_items.item_type,
    mechanic_job_items.service_configuration_data,
    mechanic_job_items.system_key,
    mechanic_job_items.component_slot_key,
    mechanic_job_items.location_key,
    mechanic_job_items.intervention_type,
    mechanic_job_items.creates_lifecycle
  ) is distinct from (
    excluded.job_bike_id,
    excluded.product_id,
    excluded.service_product_id,
    excluded.product_name,
    excluded.product_sku,
    excluded.quantity,
    excluded.unit_price,
    excluded.total_price,
    excluded.notes,
    excluded.description,
    excluded.item_type,
    excluded.service_configuration_data,
    excluded.system_key,
    excluded.component_slot_key,
    excluded.location_key,
    excluded.intervention_type,
    excluded.creates_lifecycle
  );

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
  select * into v_invoice
    from public.sales_invoices
   where id = p_invoice_id;
  if not found then return; end if;
  perform public.assert_workshop_rpc_tenant(v_invoice.tenant_id);

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
  v_existing jsonb;
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
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

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
           coalesce(nullif(concat_ws(' ', bike.brand, bike.model), ''), 'Bicicleta') as bike_name,
           product.cost as catalog_cost
      from public.mechanic_job_items item
      left join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
      left join public.bikes bike on bike.id = job_bike.bike_id
      left join public.products product
        on product.id = coalesce(item.product_id, item.service_product_id)
       and product.tenant_id = item.tenant_id
     where item.job_id = p_job_id
       and item.tenant_id = v_job.tenant_id
     order by item.created_at, item.id
  loop
    select element.value into v_existing
      from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb)) element(value)
     where element.value->>'id' = v_item.id::text
     limit 1;

    v_items := v_items || jsonb_build_object(
      'id', v_item.id,
      'product_id', case
        when v_item.item_type = 'service' then coalesce(v_item.service_product_id::text, '')
        when v_item.item_type = 'product' then coalesce(v_item.product_id::text, '')
        else ''
      end,
      'product_name', v_item.product_name,
      'product_sku', coalesce(v_item.product_sku, ''),
      'description', coalesce(v_item.notes, v_item.description, ''),
      'item_type', v_item.item_type,
      'is_service', v_item.item_type = 'service',
      'is_catalog_product',
        v_item.item_type <> 'adhoc'
        and coalesce(v_item.product_id, v_item.service_product_id) is not null,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'discount', coalesce(nullif(v_existing->>'discount', '')::numeric, 0),
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0),
      'cost', coalesce(nullif(v_existing->>'cost', '')::numeric, v_item.catalog_cost, 0),
      'purchase_treatment', coalesce(v_existing->>'purchase_treatment', 'inventory'),
      'job_bike_id', v_item.job_bike_id,
      'bike_name', case when v_item.job_bike_id is null then null else v_item.bike_name end,
      'service_configuration_data', v_item.service_configuration_data,
      'system_key', v_item.system_key,
      'component_slot_key', v_item.component_slot_key,
      'location_key', v_item.location_key,
      'intervention_type', v_item.intervention_type,
      'creates_lifecycle', v_item.creates_lifecycle
    );

    if v_item.item_type = 'product' then
      v_parts := v_parts + coalesce(v_item.total_price, 0);
    else
      v_labor := v_labor + coalesce(v_item.total_price, 0);
    end if;
  end loop;

  v_gross := round(v_parts + v_labor, 2);
  v_discount := round(coalesce(v_job.discount_amount, 0), 2);
  if v_discount < 0 or v_discount > v_gross then
    raise exception 'El descuento del trabajo debe estar entre cero y el subtotal (%).', v_gross;
  end if;
  v_total := v_gross - v_discount;

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
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

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
           coalesce(nullif(concat_ws(' ', bike.brand, bike.model), ''), 'Bicicleta') as bike_name,
           product.cost as catalog_cost
      from public.mechanic_job_items item
      left join public.mechanic_job_bikes job_bike on job_bike.id = item.job_bike_id
      left join public.bikes bike on bike.id = job_bike.bike_id
      left join public.products product
        on product.id = coalesce(item.product_id, item.service_product_id)
       and product.tenant_id = item.tenant_id
     where item.job_id = p_job_id
       and item.tenant_id = v_job.tenant_id
     order by item.created_at, item.id
  loop
    v_items := v_items || jsonb_build_object(
      'id', v_item.id,
      'product_id', case
        when v_item.item_type = 'service' then coalesce(v_item.service_product_id::text, '')
        when v_item.item_type = 'product' then coalesce(v_item.product_id::text, '')
        else ''
      end,
      'product_name', v_item.product_name,
      'product_sku', coalesce(v_item.product_sku, ''),
      'description', coalesce(v_item.notes, v_item.description, ''),
      'item_type', v_item.item_type,
      'is_service', v_item.item_type = 'service',
      'is_catalog_product',
        v_item.item_type <> 'adhoc'
        and coalesce(v_item.product_id, v_item.service_product_id) is not null,
      'quantity', v_item.quantity,
      'unit_price', v_item.unit_price,
      'discount', 0,
      'line_total', coalesce(v_item.total_price, v_item.quantity * v_item.unit_price, 0),
      'cost', coalesce(v_item.catalog_cost, 0),
      'purchase_treatment', 'inventory',
      'job_bike_id', v_item.job_bike_id,
      'bike_name', case when v_item.job_bike_id is null then null else v_item.bike_name end,
      'service_configuration_data', v_item.service_configuration_data,
      'system_key', v_item.system_key,
      'component_slot_key', v_item.component_slot_key,
      'location_key', v_item.location_key,
      'intervention_type', v_item.intervention_type,
      'creates_lifecycle', v_item.creates_lifecycle
    );
    v_gross := v_gross + coalesce(v_item.total_price, 0);
  end loop;

  v_gross := round(v_gross, 2);
  v_discount := round(coalesce(v_job.discount_amount, 0), 2);
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

  -- The invoice was just built from these exact job rows. Prevent the legacy
  -- link trigger from immediately deleting and recreating those rows.
  perform set_config('app.syncing_job_to_invoice', 'true', true);
  update public.mechanic_jobs
     set invoice_id = v_invoice_id,
         is_invoiced = true,
         tax_treatment = 'no_tax',
         tax_amount = 0,
         total_cost = v_total,
         final_cost = v_total,
         updated_at = clock_timestamp()
   where id = p_job_id;
  perform set_config('app.syncing_job_to_invoice', '', true);

  return v_invoice_id;
exception
  when others then
    perform set_config('app.syncing_job_to_invoice', '', true);
    raise;
end;
$$;

revoke all on function public.create_invoice_from_mechanic_job(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.sync_invoice_items_to_job(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.sync_invoice_status_to_job(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.sync_job_to_invoice(uuid)
  from public, anon, authenticated, service_role;

grant execute on function public.create_invoice_from_mechanic_job(uuid)
  to authenticated;
grant execute on function public.sync_invoice_items_to_job(uuid)
  to authenticated;
grant execute on function public.sync_invoice_status_to_job(uuid)
  to authenticated;
grant execute on function public.sync_job_to_invoice(uuid)
  to authenticated;

comment on function public.sync_invoice_items_to_job(uuid) is
  'ID-preserving invoice-to-workshop upsert. Retains technical service metadata and task parent identities.';
comment on function public.sync_job_to_invoice(uuid) is
  'Workshop-to-invoice sync preserving stable line IDs, accounting cost metadata, and technical service metadata.';

commit;
