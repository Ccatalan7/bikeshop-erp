-- Qué se cotiza sin stock (dueño, 2026-11-03): «no es simplemente que si un
-- producto está agotado, automáticamente se puede agregar a una cotización…
-- tiene que existir la opción dentro de su product form… hacer una selección
-- de productos que muchas veces sean de marcas un poco más reconocidas». Hasta
-- hoy los 766 agotados publicados ofrecían «Cotízalo a pedido», también los
-- que se compraron una vez, se descontinuaron o salvaron un apuro.
--
-- Sin stock, un producto se ofrece de una de tres maneras:
--   * a pedido: «Se vende a pedido» con proveedor y plazo (is_active);
--   * se cotiza: el taller confirma con sus proveedores;
--   * no se ofrece: la tienda lo muestra agotado y sólo se pregunta por él.
-- Lo decide la ficha del producto (quote_when_sold_out) o, si la ficha no
-- decide, su marca: las «marcas que se cotizan sin stock» de Ajustes de
-- cotizaciones. La regla vive aquí y el sitio la lee con
-- get_public_sold_out_offers_v1.
--
-- Esta migración sólo agrega: la tienda y el ERP de la 1.0.45 no leen nada
-- de esto y siguen igual. Que la solicitud de una cotización no acepte, más
-- allá del stock, lo que no se ofrece es 20261103080000, que se despliega con
-- la tienda que ya lo dice.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- ---------------------------------------------------------------------------
-- 1. Lo que decide la ficha y lo que decide la marca
-- ---------------------------------------------------------------------------

alter table public.product_on_order_terms
  add column if not exists quote_when_sold_out boolean;

comment on column public.product_on_order_terms.quote_when_sold_out is
  'Sin stock: true se cotiza, false no se ofrece, null lo decide su marca (customer_quote_sold_out_brands). Con is_active se vende a pedido y siempre se ofrece.';

create table if not exists public.customer_quote_sold_out_brands (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  brand_id uuid not null references public.product_brands(id) on delete cascade,
  added_at timestamptz not null default clock_timestamp(),
  added_by uuid references auth.users(id) on delete set null,
  primary key (tenant_id, brand_id)
);

comment on table public.customer_quote_sold_out_brands is
  'Marcas que se cotizan sin stock: un producto de una de ellas, agotado y sin decisión en su ficha, se ofrece para cotizar. Las demás, sólo si su ficha lo dice. Se cambian en Ajustes de cotizaciones.';

alter table public.customer_quote_sold_out_brands enable row level security;
revoke all on public.customer_quote_sold_out_brands from public, anon, authenticated;
grant select on public.customer_quote_sold_out_brands to authenticated;
drop policy if exists customer_quote_sold_out_brands_tenant_read on public.customer_quote_sold_out_brands;
create policy customer_quote_sold_out_brands_tenant_read on public.customer_quote_sold_out_brands
  for select to authenticated using (tenant_id = (select public.user_tenant_id()));

-- ---------------------------------------------------------------------------
-- 2. La regla: on_order, quote o none
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_sold_out_mode_internal(
  p_tenant_id uuid,
  p_product_id uuid,
  p_brand_id uuid
)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when t.is_active then 'on_order'
    when t.quote_when_sold_out then 'quote'
    when t.quote_when_sold_out = false then 'none'
    when p_brand_id is not null and exists (
      select 1 from public.customer_quote_sold_out_brands b
       where b.tenant_id = p_tenant_id and b.brand_id = p_brand_id
    ) then 'quote'
    else 'none'
  end
    from (select 1) one
    left join public.product_on_order_terms t
      on t.product_id = p_product_id and t.tenant_id = p_tenant_id;
$$;

revoke all on function public.customer_quote_sold_out_mode_internal(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

comment on function public.customer_quote_sold_out_mode_internal(uuid, uuid, uuid) is
  'Cómo se ofrece un producto cuando no tiene stock: on_order (a pedido con plazo), quote (se cotiza) o none (no se ofrece). Manda la ficha; sin decisión, su marca.';

-- Para el sitio: cómo se ofrecen sin stock hasta 200 productos que publica.
-- Los que no se ofrecen no aparecen; nunca dice el proveedor.
create or replace function public.get_public_sold_out_offers_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with policy as (select public.catalog_web_policy_v1(p_tenant_id) as v),
  offers as (
    select p.id,
           public.customer_quote_sold_out_mode_internal(p_tenant_id, p.id, p.brand_id) as mode,
           t.lead_days_min, t.lead_days_max
      from public.products p
      cross join policy
      left join public.product_on_order_terms t
        on t.product_id = p.id and t.tenant_id = p.tenant_id and t.is_active
     where p.tenant_id = p_tenant_id
       and p.id = any ((coalesce(p_product_ids, array[]::uuid[]))[1:200])
       and coalesce(p.product_type, 'product') <> 'service'
       and public.catalog_product_web_block_v1(p, policy.v) is null
  )
  select coalesce(jsonb_object_agg(o.id::text,
    case when o.mode = 'on_order'
      then jsonb_build_object('mode', 'on_order',
             'leadDaysMin', o.lead_days_min, 'leadDaysMax', o.lead_days_max)
      else jsonb_build_object('mode', o.mode)
    end), '{}'::jsonb)
    from offers o
   where o.mode <> 'none';
$$;

revoke all on function public.get_public_sold_out_offers_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_sold_out_offers_v1(uuid, uuid[])
  to anon, authenticated, service_role;

comment on function public.get_public_sold_out_offers_v1(uuid, uuid[]) is
  'Cómo se ofrecen sin stock hasta 200 productos que el sitio publica: {id: {mode: on_order, leadDaysMin, leadDaysMax}} o {id: {mode: quote}}. Los que no se ofrecen no vienen. No expone el proveedor.';

-- ---------------------------------------------------------------------------
-- 3. La ficha decide: el comando de «Se vende a pedido» también lo guarda
-- ---------------------------------------------------------------------------

-- Igual que en 20261102041700, más quote_when_sold_out: true, false o null
-- (lo decide la marca). Sin la clave queda lo que había, así la ficha de la
-- 1.0.45, que no la manda, no borra la decisión.
create or replace function public.set_product_on_order_terms_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_terms jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_row public.product_on_order_terms%rowtype;
  v_supplier uuid := nullif(p_terms ->> 'supplier_id', '')::uuid;
  v_sets_quote boolean := p_terms ? 'quote_when_sold_out';
  v_quote boolean;
begin
  if not exists (select 1 from public.products p where p.id = p_product_id and p.tenant_id = p_tenant_id) then
    raise exception 'Product not found or not accessible' using errcode = 'P0002';
  end if;
  if v_supplier is not null and not exists (
    select 1 from public.suppliers s where s.id = v_supplier and s.tenant_id = p_tenant_id
  ) then
    raise exception 'Supplier not found' using errcode = 'P0002';
  end if;
  if v_sets_quote then
    if jsonb_typeof(p_terms -> 'quote_when_sold_out') not in ('boolean', 'null') then
      raise exception 'Invalid quote_when_sold_out' using errcode = '22023';
    end if;
    v_quote := (p_terms ->> 'quote_when_sold_out')::boolean;
  end if;
  insert into public.product_on_order_terms (
    product_id, tenant_id, supplier_id, lead_days_min, lead_days_max, is_active,
    quote_when_sold_out, updated_by
  ) values (
    p_product_id, p_tenant_id, v_supplier,
    coalesce((p_terms ->> 'lead_days_min')::smallint, 3),
    coalesce((p_terms ->> 'lead_days_max')::smallint, 5),
    coalesce((p_terms ->> 'is_active')::boolean, true),
    v_quote,
    v_actor
  )
  on conflict (product_id) do update
     set supplier_id = excluded.supplier_id,
         lead_days_min = excluded.lead_days_min,
         lead_days_max = excluded.lead_days_max,
         is_active = excluded.is_active,
         quote_when_sold_out = case
           when v_sets_quote then excluded.quote_when_sold_out
           else public.product_on_order_terms.quote_when_sold_out
         end,
         updated_at = clock_timestamp(),
         updated_by = v_actor
   where public.product_on_order_terms.tenant_id = p_tenant_id
  returning * into v_row;
  if v_row.product_id is null then
    raise exception 'Product not found or not accessible' using errcode = '42501';
  end if;
  return to_jsonb(v_row);
end;
$$;

revoke all on function public.set_product_on_order_terms_v1(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.set_product_on_order_terms_v1(uuid, uuid, jsonb) to authenticated;

comment on function public.set_product_on_order_terms_v1(uuid, uuid, jsonb) is
  'Guarda cómo se ofrece un producto sin stock: a pedido (is_active, supplier_id, lead_days_min, lead_days_max) y quote_when_sold_out (true se cotiza, false no se ofrece, null lo decide su marca; sin la clave queda como estaba).';

-- ---------------------------------------------------------------------------
-- 4. Ajustes: las marcas que se cotizan sin stock
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_settings_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings public.customer_quote_settings;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  v_settings := public.customer_quote_settings_internal(p_tenant_id);
  return jsonb_build_object(
    'offer_validity_hours', v_settings.offer_validity_hours,
    'reminder_hours_before', v_settings.reminder_hours_before,
    'on_order_prepay_percent', v_settings.on_order_prepay_percent,
    'supplier_task_due_hours', v_settings.supplier_task_due_hours,
    'supplier_check_fresh_hours', v_settings.supplier_check_fresh_hours,
    'sold_out_brands', coalesce((
      select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name) order by lower(b.name))
        from public.customer_quote_sold_out_brands sb
        join public.product_brands b on b.id = sb.brand_id
       where sb.tenant_id = p_tenant_id
    ), '[]'::jsonb),
    'updated_at', v_settings.updated_at,
    'can_edit', public.can_edit_tenant_settings(p_tenant_id)
  );
end;
$$;

revoke all on function public.customer_quote_settings_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_settings_v1(uuid) to authenticated;

comment on function public.customer_quote_settings_v1(uuid) is
  'Los valores de las cotizaciones del taller (sin fila, los de omisión), las marcas que se cotizan sin stock y can_edit: si quien pregunta puede cambiarlos.';

create or replace function public.update_customer_quote_settings_v1(
  p_tenant_id uuid,
  p_settings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_current public.customer_quote_settings := public.customer_quote_settings_internal(p_tenant_id);
  v_validity integer;
  v_reminder integer;
  v_task_due integer;
  v_fresh integer;
  v_brand_ids uuid[];
begin
  if not public.can_edit_tenant_settings(p_tenant_id) then
    raise exception 'quote_settings_not_allowed' using errcode = '42501';
  end if;
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'quote_settings_invalid' using errcode = '22023', detail = 'settings';
  end if;

  if p_settings ? 'on_order_prepay_percent'
     and p_settings -> 'on_order_prepay_percent' is distinct from '100'::jsonb then
    raise exception 'quote_deposit_unsupported' using errcode = '22023',
      detail = 'on_order_prepay_percent';
  end if;

  v_validity := public.customer_quote_setting_value_internal(
    p_settings, 'offer_validity_hours', v_current.offer_validity_hours, 12, 720);
  v_reminder := public.customer_quote_setting_value_internal(
    p_settings, 'reminder_hours_before', v_current.reminder_hours_before, 0, 168);
  v_task_due := public.customer_quote_setting_value_internal(
    p_settings, 'supplier_task_due_hours', v_current.supplier_task_due_hours, 1, 168);
  v_fresh := public.customer_quote_setting_value_internal(
    p_settings, 'supplier_check_fresh_hours', v_current.supplier_check_fresh_hours, 1, 720);

  -- Un recordatorio igual o mayor a la vigencia saldría junto con la oferta.
  if v_reminder >= v_validity then
    raise exception 'quote_settings_invalid' using errcode = '22023',
      detail = 'reminder_hours_before';
  end if;

  -- Las marcas: la lista entera, de las que este taller ve (las suyas y las
  -- del catálogo compartido).
  if p_settings ? 'sold_out_brand_ids' then
    if jsonb_typeof(p_settings -> 'sold_out_brand_ids') <> 'array'
       or exists (
         select 1 from jsonb_array_elements(p_settings -> 'sold_out_brand_ids') e
          where jsonb_typeof(e) <> 'string'
             or (e #>> '{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       ) then
      raise exception 'quote_settings_invalid' using errcode = '22023', detail = 'sold_out_brand_ids';
    end if;
    select coalesce(array_agg(distinct (e #>> '{}')::uuid), array[]::uuid[]) into v_brand_ids
      from jsonb_array_elements(p_settings -> 'sold_out_brand_ids') e;
    if exists (
      select 1 from unnest(v_brand_ids) as wanted(brand_id)
       where not exists (
         select 1 from public.product_brands b
          where b.id = wanted.brand_id and (b.tenant_id is null or b.tenant_id = p_tenant_id)
       )
    ) then
      raise exception 'quote_settings_invalid' using errcode = '22023', detail = 'sold_out_brand_ids';
    end if;
    delete from public.customer_quote_sold_out_brands sb
     where sb.tenant_id = p_tenant_id and not (sb.brand_id = any (v_brand_ids));
    insert into public.customer_quote_sold_out_brands (tenant_id, brand_id, added_by)
    select p_tenant_id, wanted.brand_id, v_actor from unnest(v_brand_ids) as wanted(brand_id)
    on conflict (tenant_id, brand_id) do nothing;
  end if;

  insert into public.customer_quote_settings (
    tenant_id, offer_validity_hours, reminder_hours_before, on_order_prepay_percent,
    supplier_task_due_hours, supplier_check_fresh_hours, notify_email, updated_by
  ) values (
    p_tenant_id, v_validity, v_reminder, 100, v_task_due, v_fresh,
    v_current.notify_email, v_actor
  )
  on conflict (tenant_id) do update
     set offer_validity_hours = excluded.offer_validity_hours,
         reminder_hours_before = excluded.reminder_hours_before,
         on_order_prepay_percent = excluded.on_order_prepay_percent,
         supplier_task_due_hours = excluded.supplier_task_due_hours,
         supplier_check_fresh_hours = excluded.supplier_check_fresh_hours,
         updated_at = clock_timestamp(),
         updated_by = v_actor;

  return public.customer_quote_settings_v1(p_tenant_id);
end;
$$;

revoke all on function public.update_customer_quote_settings_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.update_customer_quote_settings_v1(uuid, jsonb) to authenticated;

comment on function public.update_customer_quote_settings_v1(uuid, jsonb) is
  'Cambia los valores de las cotizaciones (vigencia, recordatorio, plazo de la tarea de proveedor, frescura de una revisión de portal) y la lista entera de marcas que se cotizan sin stock (sold_out_brand_ids). Sólo quien cambia los ajustes del taller; el pago adelantado queda en 100 % (quote_deposit_unsupported); quote_settings_invalid nombra el campo en el detalle.';

-- Lo que la lista de marcas hace hoy: cuántos de los agotados que el sitio
-- publica se ofrecen y de qué manera, y las marcas con productos publicados
-- para elegir, con sus agotados. `quoted_by_product` y `follows` (los
-- agotados de la marca sin decisión propia) dejan que Ajustes diga el total
-- exacto con la lista que se está editando:
-- on_order + quoted_by_product + la suma de `follows` de las marcas elegidas.
create or replace function public.customer_quote_sold_out_summary_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_result jsonb;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  with policy as (select public.catalog_web_policy_v1(p_tenant_id) as v),
  published as (
    select p.id, p.brand_id,
           coalesce(public.customer_quote_available_stock_internal(p_tenant_id, p.id), 0) <= 0 as sold_out
      from public.products p
      cross join policy
     where p.tenant_id = p_tenant_id
       and coalesce(p.product_type, 'product') <> 'service'
       and coalesce(p.track_stock, true)
       and public.catalog_product_web_block_v1(p, policy.v) is null
  ),
  sold_out as (
    select s.*, public.customer_quote_sold_out_mode_internal(p_tenant_id, s.id, s.brand_id) as mode,
           coalesce(t.is_active, false) as on_order_terms,
           t.quote_when_sold_out
      from published s
      left join public.product_on_order_terms t
        on t.tenant_id = p_tenant_id and t.product_id = s.id
     where s.sold_out
  )
  select jsonb_build_object(
    'sold_out', (select count(*) from sold_out),
    'on_order', (select count(*) from sold_out where mode = 'on_order'),
    'quote', (select count(*) from sold_out where mode = 'quote'),
    'none', (select count(*) from sold_out where mode = 'none'),
    'quoted_by_product', (select count(*) from sold_out
                           where not on_order_terms and quote_when_sold_out is true),
    'brands', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', b.id, 'name', b.name,
               'published', x.published, 'sold_out', x.sold_out,
               'follows', coalesce(f.follows, 0),
               'listed', exists (select 1 from public.customer_quote_sold_out_brands sb
                                  where sb.tenant_id = p_tenant_id and sb.brand_id = b.id))
             order by x.sold_out desc, lower(b.name))
        from (select brand_id, count(*) as published, count(*) filter (where sold_out) as sold_out
                from published where brand_id is not null group by brand_id) x
        join public.product_brands b on b.id = x.brand_id
        left join (select brand_id, count(*) as follows
                     from sold_out
                    where not on_order_terms and quote_when_sold_out is null
                    group by brand_id) f on f.brand_id = x.brand_id
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.customer_quote_sold_out_summary_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_sold_out_summary_v1(uuid) to authenticated;

comment on function public.customer_quote_sold_out_summary_v1(uuid) is
  'Para Ajustes de cotizaciones: de los agotados que el sitio publica, cuántos se ofrecen a pedido, se cotizan o no se ofrecen y cuántos se cotizan por su ficha (quoted_by_product), y las marcas con productos publicados (publicados, agotados, follows = agotados sin decisión propia, si están en la lista).';

commit;
