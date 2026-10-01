-- Una sola regla para repartir las líneas del trabajo entre repuestos y mano
-- de obra (dueño, 2026-10-01).
--
-- Había tres reglas y una cuarta sobreescribiendo el total:
--   - `recalculate_job_bike_costs` (subtotal de cada bici): repuestos =
--     producto o sin tipo; mano de obra = servicio; un ítem libre (`adhoc`) no
--     contaba en ninguna. 8 bicis dejaban fuera su ítem libre.
--   - `sync_invoice_items_to_job_workshop_internal`: repuestos = producto;
--     mano de obra = servicio o libre. 8 trabajos facturados (y sus 8 bicis)
--     tenían su ítem libre en mano de obra.
--   - `recalculate_mechanic_job_costs` (el trabajo): repuestos = todo lo que
--     no es servicio; mano de obra = servicio.
--   - `update_mechanic_job_costs` corre después que la anterior en cada cambio
--     de línea y escribía `total_cost = repuestos + mano de obra`, sin
--     descuento ni IVA: en un trabajo facturado el total que ve el cliente en
--     el portal pasaba del total de la factura al neto de las líneas.
-- La regla es la del formulario y la del trabajo: un ítem libre es un repuesto
-- escrito a mano (`JobPartItem.itemType`), y lo que se cobra como servicio
-- lleva `item_type = 'service'`. Servicio es mano de obra; todo lo demás,
-- repuestos. Vive en `job_line_cost_bucket` y la usan estas funciones y la
-- sincronización (20261001200000). La guardia de modos
-- (`guard_canonical_mechanic_job_mode_transition`, el total de una
-- cotización pendiente) ya calculaba con esta misma regla y no se reescribe
-- aquí; `workshop_job_line_costs.sql` falla si alguna de las cinco se aparta.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function public.job_line_cost_bucket(p_item_type text)
returns text
language sql
immutable
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
  select case when p_item_type = 'service' then 'labor' else 'parts' end
$function$;

revoke all on function public.job_line_cost_bucket(text)
  from public, anon, authenticated, service_role;

-- El subtotal de cada bici, con la regla y con su taller.
create or replace function public.recalculate_job_bike_costs()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_job_bike_ids uuid[];
  v_job_bike_id uuid;
  v_tenant_id uuid := coalesce(NEW.tenant_id, OLD.tenant_id);
  v_parts_cost numeric(12,2);
  v_labor_cost numeric(12,2);
begin
  -- 🔄 CIRCULAR SYNC GUARD
  if current_setting('app.syncing_invoice_to_job', true) = 'true' or
     current_setting('app.syncing_job_to_invoice', true) = 'true' then
    return coalesce(NEW, OLD);
  end if;

  if TG_OP = 'DELETE' then
    v_job_bike_ids := array[OLD.job_bike_id];
  elsif TG_OP = 'INSERT' then
    v_job_bike_ids := array[NEW.job_bike_id];
  else
    v_job_bike_ids := array[OLD.job_bike_id, NEW.job_bike_id];
  end if;

  for v_job_bike_id in
    select distinct changed.id
      from unnest(v_job_bike_ids) as changed(id)
     where changed.id is not null
     order by changed.id
  loop
    select coalesce(sum(total_price) filter (
             where public.job_line_cost_bucket(item_type) = 'parts'), 0),
           coalesce(sum(total_price) filter (
             where public.job_line_cost_bucket(item_type) = 'labor'), 0)
      into v_parts_cost, v_labor_cost
      from mechanic_job_items
     where job_bike_id = v_job_bike_id
       and tenant_id = v_tenant_id;
    update mechanic_job_bikes
       set parts_cost = v_parts_cost,
           labor_cost = v_labor_cost,
           subtotal = v_parts_cost + v_labor_cost,
           updated_at = now()
     where id = v_job_bike_id
       and tenant_id = v_tenant_id;
  end loop;
  return coalesce(NEW, OLD);
end;
$function$;

-- El trabajo: igual que antes, con la regla en su lugar.
create or replace function public.recalculate_mechanic_job_costs(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_job public.mechanic_jobs%rowtype;
  v_parts_cost numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_effective_discount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
begin
  if current_setting('app.syncing_invoice_to_job', true) = 'true'
     or current_setting('app.syncing_job_to_invoice', true) = 'true' then
    return;
  end if;

  if p_job_id is null then
    return;
  end if;

  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id
  for update;

  if not found then
    return;
  end if;

  select
    coalesce(sum(coalesce(
      item.total_price,
      item.quantity * item.unit_price,
      0
    )) filter (
      where public.job_line_cost_bucket(item.item_type) = 'parts'
    ), 0),
    coalesce(sum(coalesce(
      item.total_price,
      item.quantity * item.unit_price,
      0
    )) filter (
      where public.job_line_cost_bucket(item.item_type) = 'labor'
    ), 0)
  into v_parts_cost, v_labor_cost
  from public.mechanic_job_items item
  where item.job_id = v_job.id
    and item.tenant_id = v_job.tenant_id;

  v_parts_cost := round(v_parts_cost, 2);
  v_labor_cost := round(v_labor_cost, 2);
  v_subtotal := round(v_parts_cost + v_labor_cost, 2);
  v_discount := round(coalesce(v_job.discount_amount, 0), 2);

  if v_discount < 0 then
    raise exception 'El descuento del trabajo no puede ser negativo.'
      using errcode = '23514';
  end if;

  -- Legacy clients persist the job before its lines. Preserve the requested
  -- discount while clamping only its temporary application; approval below
  -- rejects a final quotation whose complete subtotal still cannot cover it.
  v_effective_discount := least(v_discount, v_subtotal);
  v_total := round(v_subtotal - v_effective_discount, 2);

  if v_job.invoice_id is null then
    update public.mechanic_jobs
    set parts_cost = v_parts_cost,
        labor_cost = v_labor_cost,
        final_cost = v_total,
        tax_amount = 0,
        total_cost = v_total,
        tax_treatment = 'no_tax',
        updated_at = clock_timestamp()
    where id = v_job.id
      and tenant_id = v_job.tenant_id;
  else
    update public.mechanic_jobs
    set parts_cost = v_parts_cost,
        labor_cost = v_labor_cost,
        updated_at = clock_timestamp()
    where id = v_job.id
      and tenant_id = v_job.tenant_id;
  end if;
end;
$function$;

-- El segundo disparador de costos ya no tiene su propia cuenta: pide la del
-- trabajo, que respeta el descuento y deja el total de la factura donde la hay.
create or replace function public.update_mechanic_job_costs()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public.recalculate_mechanic_job_costs(coalesce(NEW.job_id, OLD.job_id));
  return coalesce(NEW, OLD);
end;
$function$;

commit;
