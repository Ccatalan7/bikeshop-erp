-- La factura → el trabajo continúa la misma línea (dueño, 2026-10-01).
--
-- El dueño vio PG-00142 con sus productos en «General» y pidió revisar la
-- arquitectura. General es a propósito —lo que el cliente compra aparte en el
-- mismo trabajo, aunque tenga una sola bici: un casco, un bombín, luces—, pero
-- la sincronización de la factura metía ahí líneas que eran de la bici: un
-- ítem sin `id` sólo se emparejaba con líneas de General (`job_bike_id is not
-- distinct from` la bici del ítem, que no traía) y sólo si había una igual. La
-- línea de la bici quedaba sin pareja, se **borraba** —con sus tareas, por
-- `mechanic_job_tasks.parent_item_id ON DELETE CASCADE`— y volvía como línea
-- nueva de General con otro id (PG-00309: cuatro líneas recreadas el
-- 2026-07-03 desde una factura del 1 de abril con dos ítems sin `id`). Y una
-- factura que repetía el mismo `id` abortaba con `duplicate key …
-- workshop_desired_items_pkey`.
--
-- Igual que antes salvo cómo encuentra la línea que continúa cada ítem:
--   - por su `id`, la primera vez que aparece;
--   - sin `id`, por su contenido (tipo, producto, nombre, cantidad, precio y
--     total) entre las líneas que ningún otro ítem tomó: el n-ésimo ítem
--     igual continúa la n-ésima línea igual. Un ítem que nombra su bici sólo
--     continúa una línea de esa bici; uno que no nombra ninguna continúa la
--     línea esté donde esté —en una bici o en General— y le conserva el lugar;
--   - y si cambió el precio o la cantidad, por el mismo producto (un ítem
--     libre, por su nombre) entre las que quedan (revisión de Codex).
-- Un ítem nuevo de la factura, sin bici, sigue naciendo en General: quien
-- edita la factura no dice de qué bici es, y en la ficha se asigna.
--
-- Y repara lo que esos caminos dejaron mal: en los trabajos de una sola bici,
-- los servicios y los componentes que quedaron en General pasan a su bici; los
-- accesorios y lo demás se quedan donde están (paso 2). Después rehace los
-- subtotales y los totales con la regla única de 20261001190000 (paso 3).
-- Va después de 20261001190000 (`job_line_cost_bucket`) y de 20261001195000.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

-- El paso 2 repara lo que dejó la sincronización vieja, y sólo cuando la
-- reemplaza: su cuerpo en producción antes de este cambio era
-- 586c672c1e77d65be585e15a065917d5. Una categoría no prueba que algo sea de
-- la bici; después del arreglo, un componente en General puede ser una compra
-- aparte, y volver a correr esta migración no lo mueve (revisión de Codex).
-- Con el cuerpo nuevo (2aa84b35…) o sin la función no hay nada que reparar;
-- con cualquier otro, alguien cambió la sincronización y la migración se
-- detiene en vez de saltarse la reparación en silencio.
create temporary table workshop_sync_repair_due on commit drop as
select case (
         select md5(p.prosrc)
           from pg_proc p
          where p.oid = to_regprocedure(
                  'public.sync_invoice_items_to_job_workshop_internal(uuid)'))
         when '586c672c1e77d65be585e15a065917d5' then true
         when '2aa84b351c96dae2186f88bde92cf2c8' then false
       end as due,
       to_regprocedure(
         'public.sync_invoice_items_to_job_workshop_internal(uuid)') is null
         as function_missing;

do $baseline$
begin
  if not (select function_missing from pg_temp.workshop_sync_repair_due)
     and (select due from pg_temp.workshop_sync_repair_due) is null then
    raise exception 'Unrecognized invoice sync body: review the bike-work repair of 20261001200000 against it before deploying'
      using errcode = '55000';
  end if;
end;
$baseline$;

-- 1. La factura → el trabajo.
create or replace function public.sync_invoice_items_to_job_workshop_internal(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_invoice public.sales_invoices%rowtype;
  v_job_id uuid;
  v_parts numeric(12,2) := 0;
  v_labor numeric(12,2) := 0;
  v_ord bigint;
  v_item_type text;
  v_product_id uuid;
  v_product_name text;
  v_named_bike uuid;
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

  -- Cada ítem de la factura, leído una vez, con la línea que continúa.
  create temporary table if not exists pg_temp.workshop_invoice_rows (
    ord bigint primary key,
    value jsonb not null,
    item_id uuid,
    product_id uuid,
    product_name text not null,
    product_sku text,
    item_type text not null,
    job_bike_id uuid,
    quantity numeric(10,2) not null,
    unit_price numeric(12,2) not null,
    total_price numeric(12,2) not null,
    line_id uuid
  ) on commit drop;
  truncate pg_temp.workshop_invoice_rows;

  insert into pg_temp.workshop_invoice_rows (
    ord, value, item_id, product_id, product_name, product_sku, item_type,
    job_bike_id, quantity, unit_price, total_price
  )
  select
    invoice_item.ordinality,
    invoice_item.value,
    parsed.item_id,
    product.id,
    coalesce(nullif(invoice_item.value->>'product_name', ''), product.name, 'Artículo'),
    coalesce(nullif(invoice_item.value->>'product_sku', ''), product.sku),
    normalized.item_type,
    job_bike.id,
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
    )
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
   and job_bike.tenant_id = v_invoice.tenant_id;

  -- Por su id: la línea que el ítem nombra, la primera vez que la nombra.
  update pg_temp.workshop_invoice_rows r
     set line_id = r.item_id
   where r.item_id is not null
     and r.ord = (select min(o.ord) from pg_temp.workshop_invoice_rows o
                   where o.item_id = r.item_id)
     and exists (
       select 1 from public.mechanic_job_items item
        where item.id = r.item_id
          and item.job_id = v_job_id
          and item.tenant_id = v_invoice.tenant_id);

  -- Sin id y nombrando su bici: la n-ésima línea igual de esa bici.
  with open_lines as (
    select item.id, item.job_bike_id, item.item_type,
           item.product_id, item.service_product_id, item.product_name,
           item.quantity, item.unit_price, item.total_price,
           row_number() over (
             partition by item.job_bike_id, item.item_type, item.product_id,
               item.service_product_id, item.product_name, item.quantity,
               item.unit_price, item.total_price
             order by item.created_at, item.id) as n
      from public.mechanic_job_items item
     where item.job_id = v_job_id
       and item.tenant_id = v_invoice.tenant_id
       and item.job_bike_id is not null
       and not exists (select 1 from pg_temp.workshop_invoice_rows c
                        where c.line_id = item.id)
  ), wanted as (
    select r.ord,
           row_number() over (
             partition by r.job_bike_id, r.item_type,
               case when r.item_type = 'product' then r.product_id end,
               case when r.item_type = 'service' then r.product_id end,
               r.product_name, r.quantity, r.unit_price, r.total_price
             order by r.ord) as n
      from pg_temp.workshop_invoice_rows r
     where r.line_id is null
       and r.job_bike_id is not null
  )
  update pg_temp.workshop_invoice_rows r
     set line_id = line.id
    from wanted
    join open_lines line on line.n = wanted.n
   where r.ord = wanted.ord
     and line.job_bike_id = r.job_bike_id
     and line.item_type = r.item_type
     and line.product_id is not distinct from
       case when r.item_type = 'product' then r.product_id end
     and line.service_product_id is not distinct from
       case when r.item_type = 'service' then r.product_id end
     and line.product_name = r.product_name
     and line.quantity = r.quantity
     and line.unit_price = r.unit_price
     and line.total_price = r.total_price;

  -- Sin id ni bici: la n-ésima línea igual, esté en la bici que esté.
  with open_lines as (
    select item.id, item.item_type,
           item.product_id, item.service_product_id, item.product_name,
           item.quantity, item.unit_price, item.total_price,
           row_number() over (
             partition by item.item_type, item.product_id,
               item.service_product_id, item.product_name, item.quantity,
               item.unit_price, item.total_price
             order by item.created_at, item.id) as n
      from public.mechanic_job_items item
     where item.job_id = v_job_id
       and item.tenant_id = v_invoice.tenant_id
       and not exists (select 1 from pg_temp.workshop_invoice_rows c
                        where c.line_id = item.id)
  ), wanted as (
    select r.ord,
           row_number() over (
             partition by r.item_type,
               case when r.item_type = 'product' then r.product_id end,
               case when r.item_type = 'service' then r.product_id end,
               r.product_name, r.quantity, r.unit_price, r.total_price
             order by r.ord) as n
      from pg_temp.workshop_invoice_rows r
     where r.line_id is null
       and r.job_bike_id is null
  )
  update pg_temp.workshop_invoice_rows r
     set line_id = line.id
    from wanted
    join open_lines line on line.n = wanted.n
   where r.ord = wanted.ord
     and line.item_type = r.item_type
     and line.product_id is not distinct from
       case when r.item_type = 'product' then r.product_id end
     and line.service_product_id is not distinct from
       case when r.item_type = 'service' then r.product_id end
     and line.product_name = r.product_name
     and line.quantity = r.quantity
     and line.unit_price = r.unit_price
     and line.total_price = r.total_price;

  -- Sin id y con otro precio, cantidad o total: el mismo producto (un ítem
  -- libre, por su nombre) entre las líneas que nadie tomó, en el orden de la
  -- factura. Cambiar el precio de un ítem sin id borraba la línea —y sus
  -- tareas— y creaba otra (revisión de Codex, 2026-10-01).
  for v_ord, v_item_type, v_product_id, v_product_name, v_named_bike in
    select r.ord, r.item_type, r.product_id, r.product_name, r.job_bike_id
      from pg_temp.workshop_invoice_rows r
     where r.line_id is null
     order by r.ord
  loop
    update pg_temp.workshop_invoice_rows r
       set line_id = (
         select item.id
           from public.mechanic_job_items item
          where item.job_id = v_job_id
            and item.tenant_id = v_invoice.tenant_id
            and item.item_type = v_item_type
            and case v_item_type
                  when 'product' then item.product_id = v_product_id
                  when 'service' then item.service_product_id = v_product_id
                  else item.product_name = v_product_name
                end
            and (v_named_bike is null or item.job_bike_id = v_named_bike)
            and not exists (select 1 from pg_temp.workshop_invoice_rows c
                             where c.line_id = item.id)
          order by item.created_at, item.id
          limit 1)
     where r.ord = v_ord;
  end loop;

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
    coalesce(r.line_id, gen_random_uuid()),
    r.ord,
    coalesce(r.job_bike_id, matched.job_bike_id),
    case when r.item_type = 'product' then r.product_id end,
    case when r.item_type = 'service' then r.product_id end,
    r.product_name,
    r.product_sku,
    r.quantity,
    r.unit_price,
    r.total_price,
    nullif(coalesce(r.value->>'description', r.value->>'notes', ''), ''),
    r.item_type,
    case
      when jsonb_typeof(r.value->'service_configuration_data') = 'object'
        then r.value->'service_configuration_data'
      else matched.service_configuration_data
    end,
    coalesce(nullif(r.value->>'system_key', ''), matched.system_key),
    coalesce(nullif(r.value->>'component_slot_key', ''), matched.component_slot_key),
    coalesce(nullif(r.value->>'location_key', ''), matched.location_key, 'none'),
    coalesce(nullif(r.value->>'intervention_type', ''), matched.intervention_type),
    case
      when r.value ? 'creates_lifecycle'
        then coalesce((r.value->>'creates_lifecycle')::boolean, false)
      else coalesce(matched.creates_lifecycle, false)
    end
  from pg_temp.workshop_invoice_rows r
  left join public.mechanic_job_items matched
    on matched.id = r.line_id
   and matched.job_id = v_job_id
   and matched.tenant_id = v_invoice.tenant_id;

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
    coalesce(sum(total_price) filter (
      where public.job_line_cost_bucket(item_type) = 'parts'), 0),
    coalesce(sum(total_price) filter (
      where public.job_line_cost_bucket(item_type) = 'labor'), 0)
    into v_parts, v_labor
    from public.mechanic_job_items
   where job_id = v_job_id
     and tenant_id = v_invoice.tenant_id;

  with totals as (
    select
      job_bike.id,
      coalesce(sum(item.total_price) filter (
        where public.job_line_cost_bucket(item.item_type) = 'parts'), 0) as parts_cost,
      coalesce(sum(item.total_price) filter (
        where public.job_line_cost_bucket(item.item_type) = 'labor'), 0) as labor_cost
    from public.mechanic_job_bikes job_bike
    left join public.mechanic_job_items item
      on item.job_bike_id = job_bike.id
     and item.tenant_id = job_bike.tenant_id
    where job_bike.job_id = v_job_id
      and job_bike.tenant_id = v_invoice.tenant_id
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
$function$;

-- Privada, como en producción: el `create or replace` conserva sus permisos,
-- y esto los fija también si se crea de cero (revisión de Codex).
revoke all on function public.sync_invoice_items_to_job_workshop_internal(uuid)
  from public, anon, authenticated, service_role;

-- 2. Lo que ya estaba. En los trabajos de una sola bici, General tenía 352
-- líneas (lectura de producción, 2026-10-01): 214 servicios, 13 ítems de la
-- categoría «Servicio» y 103 componentes («Componentes / Ruedas, Frenos,
-- Transmisión, Cambios, Dirección, Fundas y piolas») —trabajo en la bici que
-- llegó ahí por los caminos de arriba— y 22 accesorios, mantenimiento o sin
-- categoría (luces, bombín, candado, guantes, stickers, campanillas, pedales,
-- puños, parches), que pueden ser una compra aparte y se quedan en General.
-- Pasan a su bici sólo las del primer grupo. Sólo cambia de quién es la línea
-- —ni precio, ni cantidad, ni stock, ni contabilidad: ninguna tiene un total
-- distinto de cantidad × precio, que su disparador recalcula—, así que corre
-- bajo la marca de la sincronización desde la factura: la guardia de lo
-- pagado la deja pasar como deja pasar esa sincronización, y no se reescriben
-- facturas ni totales del trabajo. El subtotal de la bici se rehace con la
-- regla única (`job_line_cost_bucket`, 20261001190000). Una cotización decidida es inmutable y queda
-- como está; los trabajos de varias bicis o con la bici sólo en la cabecera no
-- se tocan. Todo o nada: si un trabajo no se deja (la puerta de cambio de
-- partes, un bloqueo), se juntan los que fallan y la migración entera se
-- deshace nombrándolos.
-- Corre una sola vez: al reemplazar la sincronización vieja (arriba).
create or replace function pg_temp.is_bike_work(p_line public.mechanic_job_items)
returns boolean
language sql stable
as $$
  select p_line.item_type = 'service'
      or exists (
        select 1
          from public.products product
          join public.product_categories category
            on category.id = product.category_id
           and category.tenant_id = product.tenant_id
         where product.id = coalesce(p_line.product_id, p_line.service_product_id)
           and product.tenant_id = p_line.tenant_id
           and split_part(category.full_path, ' / ', 1) in ('Componentes', 'Servicio'))
$$;

do $backfill$
declare
  v_job record;
  v_count integer;
  v_lines integer := 0;
  v_jobs integer := 0;
  v_failed jsonb := '[]'::jsonb;
begin
  if not coalesce((select due from pg_temp.workshop_sync_repair_due), false) then
    raise notice 'Bike-work repair skipped: the invoice sync was already fixed.';
    return;
  end if;
  perform set_config('app.syncing_invoice_to_job', 'true', true);
  for v_job in
    select j.id, j.tenant_id, j.job_number, min(jb.id::text)::uuid as job_bike_id
      from public.mechanic_jobs j
      join public.mechanic_job_bikes jb
        on jb.job_id = j.id and jb.tenant_id = j.tenant_id
     where exists (
             select 1 from public.mechanic_job_items i
              where i.job_id = j.id and i.tenant_id = j.tenant_id
                and i.job_bike_id is null
                and pg_temp.is_bike_work(i))
       and not (j.workflow_kind = 'quotation'
                and coalesce(j.quotation_status, 'pending') <> 'pending')
     group by j.id, j.tenant_id, j.job_number
    having count(*) = 1
     order by j.id
  loop
    begin
      update public.mechanic_job_items i
         set job_bike_id = v_job.job_bike_id
       where i.job_id = v_job.id
         and i.tenant_id = v_job.tenant_id
         and i.job_bike_id is null
         and pg_temp.is_bike_work(i);
      get diagnostics v_count = row_count;

      update public.mechanic_job_bikes jb
         set parts_cost = totals.parts_cost,
             labor_cost = totals.labor_cost,
             subtotal = totals.parts_cost + totals.labor_cost,
             updated_at = clock_timestamp()
        from (
          select
            coalesce(sum(i.total_price) filter (
              where public.job_line_cost_bucket(i.item_type) = 'parts'), 0) as parts_cost,
            coalesce(sum(i.total_price) filter (
              where public.job_line_cost_bucket(i.item_type) = 'labor'), 0) as labor_cost
            from public.mechanic_job_items i
           where i.job_bike_id = v_job.job_bike_id
             and i.tenant_id = v_job.tenant_id
        ) totals
       where jb.id = v_job.job_bike_id
         and jb.tenant_id = v_job.tenant_id;

      v_lines := v_lines + v_count;
      v_jobs := v_jobs + 1;
    exception when others then
      v_failed := v_failed || jsonb_build_object(
        'job', v_job.job_number, 'sqlstate', sqlstate, 'message', sqlerrm);
    end;
  end loop;
  perform set_config('app.syncing_invoice_to_job', '', true);
  if jsonb_array_length(v_failed) > 0 then
    raise exception 'Bike-work repair refused by % job(s): %',
      jsonb_array_length(v_failed), v_failed
      using errcode = '23514';
  end if;
  raise notice 'Bike work moved from General to the only bike: % lines in % jobs.',
    v_lines, v_jobs;
end;
$backfill$;

-- 3. Los subtotales y los totales con la regla única (20261001190000), una
-- vez. Lectura de producción del 2026-10-01, fuera de las bicis que ya rehace
-- el paso 2: 27 bicis no sumaban sus líneas (8 dejaban fuera su ítem libre, 8
-- lo tenían en mano de obra porque lo escribió la factura, y 11 no se
-- recalcularon después de un cambio), 8 trabajos facturados tenían su ítem
-- libre en mano de obra, y 22 trabajos facturados no decían lo de su
-- factura: 9 en el total (cuatro con IVA sumado otra vez sobre su factura,
-- uno por redondeo, y el disparador que escribía el neto de las líneas) y 13
-- sólo en el IVA, guardado sin redondear. Los 33 trabajos sin factura ya
-- cuadraban con la regla, descuento incluido. Sólo cambia cómo se lee lo
-- que ya está: ni una línea, ni una factura, ni stock ni asientos. Corre bajo
-- la marca de la sincronización desde la factura, que es quien escribe esos
-- espejos. Las bicis de un presupuesto decidido son inmutables y quedan.
do $rollups$
declare
  v_bikes integer;
  v_jobs integer;
  v_mirrors integer;
begin
  perform set_config('app.syncing_invoice_to_job', 'true', true);

  with totals as (
    select jb.id, jb.tenant_id,
      coalesce(sum(i.total_price) filter (
        where public.job_line_cost_bucket(i.item_type) = 'parts'), 0) as parts_cost,
      coalesce(sum(i.total_price) filter (
        where public.job_line_cost_bucket(i.item_type) = 'labor'), 0) as labor_cost
      from public.mechanic_job_bikes jb
      join public.mechanic_jobs j on j.id = jb.job_id and j.tenant_id = jb.tenant_id
      left join public.mechanic_job_items i
        on i.job_bike_id = jb.id and i.tenant_id = jb.tenant_id
     where not (j.workflow_kind = 'quotation' and j.intake_kind = 'bike'
                and coalesce(j.quotation_status, 'pending') <> 'pending')
     group by jb.id, jb.tenant_id
  )
  update public.mechanic_job_bikes jb
     set parts_cost = t.parts_cost,
         labor_cost = t.labor_cost,
         subtotal = t.parts_cost + t.labor_cost,
         updated_at = clock_timestamp()
    from totals t
   where jb.id = t.id
     and jb.tenant_id = t.tenant_id
     and (jb.parts_cost, jb.labor_cost, jb.subtotal)
         is distinct from (t.parts_cost, t.labor_cost, t.parts_cost + t.labor_cost);
  get diagnostics v_bikes = row_count;

  -- Un trabajo sin factura ya tenía la regla (`recalculate_mechanic_job_costs`).
  with totals as (
    select j.id, j.tenant_id,
      round(coalesce(sum(i.total_price) filter (
        where public.job_line_cost_bucket(i.item_type) = 'parts'), 0), 2) as parts_cost,
      round(coalesce(sum(i.total_price) filter (
        where public.job_line_cost_bucket(i.item_type) = 'labor'), 0), 2) as labor_cost
      from public.mechanic_jobs j
      left join public.mechanic_job_items i
        on i.job_id = j.id and i.tenant_id = j.tenant_id
     where j.invoice_id is not null
     group by j.id, j.tenant_id
  )
  update public.mechanic_jobs j
     set parts_cost = t.parts_cost,
         labor_cost = t.labor_cost,
         updated_at = clock_timestamp()
    from totals t
   where j.id = t.id
     and j.tenant_id = t.tenant_id
     and (round(j.parts_cost, 2), round(j.labor_cost, 2))
         is distinct from (t.parts_cost, t.labor_cost);
  get diagnostics v_jobs = row_count;

  -- Lo que es de la factura se lee de la factura, como lo escribe la
  -- sincronización: el total y el IVA (revisión de Codex: el total sin el IVA
  -- dejaba IVA sobre una factura sin impuesto).
  update public.mechanic_jobs j
     set total_cost = inv.total,
         final_cost = inv.total,
         tax_amount = inv.iva_amount,
         tax_treatment = inv.tax_treatment,
         updated_at = clock_timestamp()
    from public.sales_invoices inv
   where inv.id = j.invoice_id
     and inv.tenant_id = j.tenant_id
     and (j.total_cost, j.final_cost, j.tax_amount, j.tax_treatment)
         is distinct from (inv.total, inv.total, inv.iva_amount, inv.tax_treatment);
  get diagnostics v_mirrors = row_count;

  perform set_config('app.syncing_invoice_to_job', '', true);
  raise notice 'One cost rule: % bike subtotals, % job splits, % invoice mirrors.',
    v_bikes, v_jobs, v_mirrors;
end;
$rollups$;

commit;
