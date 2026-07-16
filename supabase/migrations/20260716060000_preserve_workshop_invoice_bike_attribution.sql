-- Deployment status: PENDING.
--
-- A sales invoice owns commercial and financial truth, but it does not own
-- which physical bicycle received a workshop line. Historical invoice JSON
-- often omits job_bike_id (or stores JSON null) even after the employee has
-- classified the received bicycle. Preserve the stable mechanic-job item's
-- existing attribution in that case instead of erasing it on the next
-- invoice-to-job synchronization.
--
-- Explicit non-empty job_bike_id values remain authoritative only when they
-- are valid UUIDs linked to the same tenant and workshop job. Invalid or
-- cross-job references abort the transaction rather than silently clearing or
-- misattributing technical history.
--
-- Recovery: this is a backwards-compatible function replacement with no data
-- backfill. A future replacement may supersede it; do not rewrite historical
-- invoice JSON or mechanic-job attribution as rollback work.

begin;

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

  -- Invoice editors do not own workshop bicycle attribution. A non-empty
  -- explicit reference is accepted only when it resolves inside this exact
  -- job/tenant graph. Missing, blank, and JSON-null values are treated as an
  -- omitted mirror and therefore preserve a stable existing item's value.
  if exists (
    select 1
    from jsonb_array_elements(coalesce(v_invoice.items, '[]'::jsonb))
      as invoice_item(value)
    cross join lateral (
      select nullif(
        btrim(coalesce(invoice_item.value->>'job_bike_id', '')),
        ''
      ) as raw_job_bike_id
    ) supplied
    where supplied.raw_job_bike_id is not null
      and case
        when supplied.raw_job_bike_id ~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then not exists (
          select 1
          from public.mechanic_job_bikes job_bike
          where job_bike.id = supplied.raw_job_bike_id::uuid
            and job_bike.job_id = v_job_id
            and job_bike.tenant_id = v_invoice.tenant_id
        )
        else true
      end
  ) then
    raise exception 'Invoice line job_bike_id must reference a bicycle linked to this workshop job.'
      using errcode = '23514';
  end if;

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
    case
      when parsed.job_bike_id is not null then job_bike.id
      else existing.job_bike_id
    end,
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

revoke all on function public.sync_invoice_items_to_job(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_invoice_items_to_job(uuid)
  to authenticated;

comment on function public.sync_invoice_items_to_job(uuid) is
  'Synchronizes invoice lines into stable workshop items while preserving omitted physical bicycle attribution and rejecting invalid cross-job references.';

notify pgrst, 'reload schema';

commit;
