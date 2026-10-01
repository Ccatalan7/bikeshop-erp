-- Una línea del trabajo es de una bici. «General» existe sólo donde no hay a
-- quién dársela: un trabajo sin bici (venta, presupuesto) o uno con varias,
-- hasta que se asigna. En un trabajo de una sola bici, toda línea es de ella.
--
-- El dueño vio PG-00142 con sus productos en «General» (2026-10-01) y lo
-- leyó como un error del personal. No lo era: 352 líneas de 126 trabajos de
-- una bici estaban así, y salían de tres escritores que no sabían de qué bici
-- era la línea y la dejaban sin dueño:
--   1. La factura → el trabajo (`sync_invoice_items_to_job_workshop_internal`):
--      un ítem sin `id` sólo se emparejaba con líneas de General, así que la
--      línea de la bici se borraba —con sus tareas, en cascada— y volvía como
--      línea nueva de General. Un ítem nuevo de la factura también nacía ahí.
--   2. El formulario: lo agregado antes de elegir la bici pasaba a General al
--      elegirla, y en un trabajo de una bici no había cómo sacarlo de ahí
--      («Asignar a…» pedía dos bicis).
--   3. Los trabajos de diciembre y enero, anteriores a las líneas por bici.
-- La base ya trataba esas líneas como de la bici (`job_line_bike_internal`,
-- la memoria de la bici), pero la ficha las mostraba aparte y el subtotal de
-- la bici no las contaba. Aquí la regla pasa a la base, para todo escritor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- 1. La regla, en la fila: una línea sin bici en un trabajo de una sola bici
-- es de esa bici. Los BEFORE corren en orden alfabético: éste va después de
-- las dos guardias que bloquean la fila del trabajo (`guard_final_quotation`
-- y `guard_paid_snapshot`, `for update`), así cuenta las bicis con lo que ya
-- confirmó quien tenía el trabajo —una bici que entraba a la vez no se le
-- escapa—, y antes de la del grafo del taller, que valida la bici que pone.
-- Corre en toda escritura de la línea, no sólo cuando cambia su bici: una
-- línea sin dueño que vuelve con un respaldo antiguo se arregla al primer
-- cambio. Una línea de un trabajo pagado no cambia por otra cosa (la guardia
-- la rechaza antes), y si sólo le falta su bici, darle la única no toca nada
-- de lo cobrado.
create function public.assign_job_line_to_only_bike()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_count integer;
  v_only uuid;
begin
  -- Una línea que pasa a otro trabajo sin que nadie nombre su bici trae la
  -- del trabajo anterior, que aquí no existe: se decide de nuevo en éste.
  if tg_op = 'UPDATE'
     and new.job_id is distinct from old.job_id
     and new.job_bike_id is not distinct from old.job_bike_id then
    new.job_bike_id := null;
  end if;
  if new.job_bike_id is not null then
    return new;
  end if;
  select count(*)::integer, min(jb.id::text)::uuid
    into v_count, v_only
    from public.mechanic_job_bikes jb
   where jb.job_id = new.job_id
     and jb.tenant_id = new.tenant_id;
  if v_count = 1 then
    new.job_bike_id := v_only;
  end if;
  return new;
end;
$function$;

revoke all on function public.assign_job_line_to_only_bike()
  from public, anon, authenticated, service_role;

-- La recuperación de un respaldo devuelve la fila tal como se respaldó: el
-- disparador lleva la marca que ella apaga (20260930171000).
create trigger trg_mechanic_job_items_only_bike
  before insert or update on public.mechanic_job_items
  for each row
  when (not public.workshop_restore_effect_suppressed(
    'public.mechanic_job_items'::regclass,
    'trg_mechanic_job_items_only_bike'::name))
  execute function public.assign_job_line_to_only_bike();

-- 2. Cuando el trabajo queda con una sola bici —recibe la primera, o le
-- quitan una de dos— lo que estaba en General pasa a ella. Las líneas de la
-- bici que sale ya se fueron en cascada (`ON DELETE CASCADE`, cuyo disparador
-- interno corre antes que éste). Un trabajo pagado no recibe ni suelta bicis
-- (`trg_mechanic_job_bikes_guard_paid_snapshot`), así que esto nunca mueve
-- una línea protegida. Límite sabido (revisión de Codex): dos bicis que
-- entran una tras otra en la misma transacción a un trabajo sin bicis dejan
-- lo de General en la primera. Hoy nadie lo hace sin mandar las líneas: el
-- comando de guardado inserta las bicis antes de escribir las líneas, y una
-- línea que el cliente manda sin bici vuelve a General con dos bicis; el
-- formulario nuevo la muestra en la pestaña de la primera y «Pasar a…» la
-- corrige.
create function public.adopt_general_job_lines_for_only_bike()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_job_id uuid;
  v_tenant_id uuid;
  v_count integer;
  v_only uuid;
begin
  if tg_op = 'DELETE' then
    v_job_id := old.job_id;
    v_tenant_id := old.tenant_id;
  else
    v_job_id := new.job_id;
    v_tenant_id := new.tenant_id;
  end if;
  select count(*)::integer, min(jb.id::text)::uuid
    into v_count, v_only
    from public.mechanic_job_bikes jb
   where jb.job_id = v_job_id
     and jb.tenant_id = v_tenant_id;
  if v_count = 1 then
    update public.mechanic_job_items i
       set job_bike_id = v_only
     where i.job_id = v_job_id
       and i.tenant_id = v_tenant_id
       and i.job_bike_id is null;
  end if;
  return null;
end;
$function$;

revoke all on function public.adopt_general_job_lines_for_only_bike()
  from public, anon, authenticated, service_role;

create trigger trg_mechanic_job_bikes_adopt_general_lines
  after insert or delete on public.mechanic_job_bikes
  for each row
  when (not public.workshop_restore_effect_suppressed(
    'public.mechanic_job_bikes'::regclass,
    'trg_mechanic_job_bikes_adopt_general_lines'::name))
  execute function public.adopt_general_job_lines_for_only_bike();

-- 3. La recuperación sólo escribe en tablas cuyos efectos revisó: los dos
-- disparadores nuevos se apagan mientras devuelve filas.
alter function public.workshop_restore_trigger_review_internal()
  rename to workshop_restore_trigger_review_without_only_bike_internal;
create function public.workshop_restore_trigger_review_internal()
returns table(table_name text, trigger_name name, review text, function_md5 text)
language sql immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select * from public.workshop_restore_trigger_review_without_only_bike_internal()
  union all select 'mechanic_job_items', 'trg_mechanic_job_items_only_bike'::name,
    'hook', null::text
  union all select 'mechanic_job_bikes', 'trg_mechanic_job_bikes_adopt_general_lines'::name,
    'hook', null::text
$function$;

revoke all on function public.workshop_restore_trigger_review_internal(),
  public.workshop_restore_trigger_review_without_only_bike_internal()
  from public, anon, authenticated, service_role;

-- 4. La factura → el trabajo. Igual que antes salvo cómo encuentra la línea
-- que continúa cada ítem:
--   - por su `id`, la primera vez que aparece;
--   - sin `id`, por su contenido (tipo, producto, nombre, cantidad, precio y
--     total) entre las líneas que ningún otro ítem tomó: el n-ésimo ítem
--     igual continúa la n-ésima línea igual. Un ítem que nombra su bici sólo
--     continúa una línea de esa bici; uno que no nombra ninguna continúa la
--     línea esté donde esté y le conserva la bici. Antes pedía que la línea
--     estuviera en General y que hubiera una sola igual;
--   - y si cambió el precio o la cantidad, por el mismo producto (un ítem
--     libre, por su nombre) entre las que quedan.
-- Un ítem nuevo nace sin bici y la regla de arriba le da la única que haya.
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
$function$;

-- 5. Lo que ya estaba: las líneas de General de cada trabajo de una sola bici
-- pasan a ella. Sólo cambia de quién es la línea —ni precio, ni cantidad, ni
-- stock, ni contabilidad: 0 de las 352 tiene un total distinto de cantidad ×
-- precio, que su disparador recalcula—, así que corre bajo la marca de la
-- sincronización desde la factura: la guardia de lo pagado la deja pasar como
-- deja pasar esa sincronización, y no se reescriben facturas ni totales del
-- trabajo. El subtotal de la bici se rehace como lo rehace esa
-- sincronización. Una cotización decidida es inmutable y queda como está.
-- Todo o nada: si un trabajo no se deja (la puerta de cambio de partes, un
-- bloqueo), se juntan todos los que fallan y la migración entera se deshace
-- nombrándolos; nada queda aplicado a medias ni sin sellar.
do $backfill$
declare
  v_job record;
  v_count integer;
  v_lines integer := 0;
  v_jobs integer := 0;
  v_skipped jsonb := '[]'::jsonb;
begin
  perform set_config('app.syncing_invoice_to_job', 'true', true);
  for v_job in
    select j.id, j.tenant_id, j.job_number, min(jb.id::text)::uuid as job_bike_id
      from public.mechanic_jobs j
      join public.mechanic_job_bikes jb
        on jb.job_id = j.id and jb.tenant_id = j.tenant_id
     where exists (
             select 1 from public.mechanic_job_items i
              where i.job_id = j.id and i.tenant_id = j.tenant_id
                and i.job_bike_id is null)
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
         and i.job_bike_id is null;
      get diagnostics v_count = row_count;

      update public.mechanic_job_bikes jb
         set parts_cost = totals.parts_cost,
             labor_cost = totals.labor_cost,
             subtotal = totals.parts_cost + totals.labor_cost,
             updated_at = clock_timestamp()
        from (
          select
            coalesce(sum(case when i.item_type = 'product' then i.total_price else 0 end), 0) as parts_cost,
            coalesce(sum(case when i.item_type in ('service', 'adhoc') then i.total_price else 0 end), 0) as labor_cost
            from public.mechanic_job_items i
           where i.job_bike_id = v_job.job_bike_id
             and i.tenant_id = v_job.tenant_id
        ) totals
       where jb.id = v_job.job_bike_id
         and jb.tenant_id = v_job.tenant_id;

      v_lines := v_lines + v_count;
      v_jobs := v_jobs + 1;
    exception when others then
      v_skipped := v_skipped || jsonb_build_object(
        'job', v_job.job_number, 'sqlstate', sqlstate, 'message', sqlerrm);
    end;
  end loop;
  perform set_config('app.syncing_invoice_to_job', '', true);
  if jsonb_array_length(v_skipped) > 0 then
    raise exception 'Only-bike backfill refused by % job(s): %',
      jsonb_array_length(v_skipped), v_skipped
      using errcode = '23514';
  end if;
  raise notice 'Lines adopted by the only bike: % lines in % jobs.',
    v_lines, v_jobs;
end;
$backfill$;

-- Contrato: los dos disparadores revisados por la recuperación y la regla
-- cumplida, salvo cotizaciones decididas.
do $contract$
begin
  if public.workshop_restore_effects_review_internal(
       'public.mechanic_job_items'::regclass) is not null
     or public.workshop_restore_effects_review_internal(
       'public.mechanic_job_bikes'::regclass) is not null then
    raise exception 'The only-bike line triggers are not reviewed by recovery';
  end if;
end;
$contract$;
commit;
