-- Despacho de bicicletas (2026-11-21).
--
-- El dueño, para Navidad: «todo lo que sea para niños, ya sea… accesorios,
-- bicicleta, casco… va a ser súper importante. Podemos publicarlo al tiro,
-- con todos los requerimientos técnicos que eso requiera», y después «deja
-- listo lo que sea necesario para que podamos publicar bicicletas».
--
-- Hasta hoy el despacho se cobraba por la región y el monto de la compra
-- (20261014030000), como si todo fuera un paquete: el catálogo no tiene pesos
-- ni medidas. Una bicicleta va en una caja de un metro o más y no cabe en esa
-- regla (una de $250.000 a Antofagasta pagaba $28.490, el tramo más alto).
--
-- * Cada zona tiene su precio por bicicleta (`bike_shipping_gross`, IVA
--   incluido). Sin precio, esa zona no recibe bicicletas por despacho: se
--   retiran en la tienda.
-- * Qué es bicicleta lo dice su categoría: las que se marcan en Sitio Web ›
--   Envíos (`online_shipping_bike_categories`), con sus subcategorías.
-- * La cotización recibe las líneas del carrito (`p_lines`): cada bicicleta
--   paga su precio de despacho y el resto de la compra paga su tramo de
--   siempre, calculado sobre lo que no es bicicleta. Sin líneas, todo sigue
--   como antes.
-- * El pedido web y la cotización aceptada cotizan con sus propias líneas,
--   así que cobran lo mismo que vio el cliente.
-- * La tienda lee el precio por bicicleta de cada zona y qué categorías son
--   bicicleta en la misma lectura de tramos que ya hace cada página.
-- * El editor guarda el precio con las zonas. Una versión anterior de la app,
--   que no lo conoce, conserva el que tenía la zona del mismo nombre.

begin;

-- ---------------------------------------------------------------------------
-- 1. El precio por bicicleta de cada zona.
-- ---------------------------------------------------------------------------
alter table public.online_shipping_zones
  add column if not exists bike_shipping_gross numeric(12,2);

alter table public.online_shipping_zones
  drop constraint if exists online_shipping_zones_bike_shipping_gross_check;
alter table public.online_shipping_zones
  add constraint online_shipping_zones_bike_shipping_gross_check
  check (
    bike_shipping_gross is null
    or (bike_shipping_gross >= 0 and bike_shipping_gross = round(bike_shipping_gross))
  );

comment on column public.online_shipping_zones.bike_shipping_gross is
  'Despacho de una bicicleta a esta zona, por unidad, IVA incluido (20261121120000). Sin valor, la zona no recibe bicicletas por despacho: se retiran en la tienda.';

-- ---------------------------------------------------------------------------
-- 2. Qué se despacha como bicicleta: categorías, con sus subcategorías.
-- ---------------------------------------------------------------------------
create table if not exists public.online_shipping_bike_categories (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  category_id uuid not null references public.product_categories(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (tenant_id, category_id)
);

comment on table public.online_shipping_bike_categories is
  'Las categorías que se despachan como bicicleta, con sus subcategorías (20261121120000). Se eligen en Sitio Web › Envíos.';

alter table public.online_shipping_bike_categories enable row level security;
revoke all on public.online_shipping_bike_categories from anon;
revoke insert, update, delete on public.online_shipping_bike_categories from authenticated;
grant select on public.online_shipping_bike_categories to authenticated;

drop policy if exists online_shipping_bike_categories_staff_read on public.online_shipping_bike_categories;
create policy online_shipping_bike_categories_staff_read
  on public.online_shipping_bike_categories
  for select to authenticated
  using (tenant_id = (select public.user_tenant_id()));

-- Las categorías marcadas y todas las que cuelgan de ellas.
create or replace function public.online_shipping_bike_category_ids_internal(p_tenant_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with recursive marked as (
    select category.id
      from public.product_categories category
      join public.online_shipping_bike_categories bike
        on bike.category_id = category.id
       and bike.tenant_id = category.tenant_id
     where category.tenant_id = p_tenant_id
    union
    select child.id
      from public.product_categories child
      join marked on child.parent_id = marked.id
     where child.tenant_id = p_tenant_id
  )
  select coalesce(array_agg(marked.id order by marked.id), array[]::uuid[])
    from marked;
$function$;

revoke all on function public.online_shipping_bike_category_ids_internal(uuid)
  from public, anon, authenticated;

-- Cuántas bicicletas trae un carrito y cuánto suman. Cada línea es
-- {product_id, quantity, gross}; sin `gross`, el precio publicado.
create or replace function public.online_shipping_bike_lines_internal(
  p_tenant_id uuid,
  p_lines jsonb
)
returns table (bike_units integer, bike_gross numeric)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with bike as (
    select unnest(public.online_shipping_bike_category_ids_internal(p_tenant_id)) as id
  ), lines as (
    select (line->>'product_id')::uuid as product_id,
           greatest(coalesce((line->>'quantity')::numeric, 0), 0)::integer as quantity,
           nullif(btrim(coalesce(line->>'gross', '')), '')::numeric as gross
      from jsonb_array_elements(
             case when jsonb_typeof(p_lines) = 'array' then p_lines else '[]'::jsonb end
           ) line
     where jsonb_typeof(line) = 'object'
       and coalesce(line->>'product_id', '')
           ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  )
  select coalesce(sum(lines.quantity), 0)::integer,
         coalesce(sum(coalesce(
           lines.gross,
           coalesce(product.website_price, product.price, 0) * lines.quantity
         )), 0)
    from lines
    join public.products product
      on product.id = lines.product_id
     and product.tenant_id = p_tenant_id
   where product.category_id in (select bike.id from bike);
$function$;

revoke all on function public.online_shipping_bike_lines_internal(uuid, jsonb)
  from public, anon, authenticated;

-- Las líneas de un pedido, como las manda el checkout.
create or replace function public.online_order_shipping_lines_internal(
  p_order_id uuid,
  p_tenant_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'product_id', item.product_id,
           'quantity', item.quantity,
           'gross', item.subtotal
         ) order by item.id), '[]'::jsonb)
    from public.online_order_items item
   where item.order_id = p_order_id
     and item.tenant_id = p_tenant_id
     and item.product_id is not null;
$function$;

revoke all on function public.online_order_shipping_lines_internal(uuid, uuid)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. La cotización: con líneas, cada bicicleta paga su precio.
-- ---------------------------------------------------------------------------
drop function if exists public.quote_public_online_shipping(uuid, text, numeric, text, text);
drop function if exists public.quote_online_shipping_internal(uuid, text, numeric, text, text);

create or replace function public.quote_online_shipping_internal(
  p_tenant_id uuid,
  p_delivery_type text,
  p_item_gross numeric,
  p_country_code text default 'CL',
  p_region text default null,
  p_lines jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_delivery_type text := lower(btrim(coalesce(p_delivery_type, 'shipping')));
  v_country text := upper(btrim(coalesce(p_country_code, 'CL')));
  v_region_text text := nullif(btrim(coalesce(p_region, '')), '');
  v_region_code text;
  v_item_gross numeric(12,2);
  v_zone public.online_shipping_zones%rowtype;
  v_zone_count integer;
  v_tier public.online_shipping_rate_tiers%rowtype;
  v_parcel_tier public.online_shipping_rate_tiers%rowtype;
  v_match_count integer;
  v_net numeric(12,2);
  v_tax numeric(12,2);
  v_bike_units integer := 0;
  v_bike_gross numeric(12,2) := 0;
  v_parcel_gross numeric(12,2);
  v_parcel_shipping numeric(12,2) := 0;
  v_shipping_gross numeric(12,2);
begin
  if p_tenant_id is null then
    raise exception 'Shipping quote requires tenant_id' using errcode = '22004';
  end if;
  if v_delivery_type not in ('shipping', 'pickup') then
    raise exception 'Invalid delivery type for shipping quote' using errcode = '22023';
  end if;
  if p_item_gross is null or p_item_gross <= 0
     or p_item_gross <> public.clp_round(p_item_gross) then
    raise exception 'Shipping quote requires a positive whole-CLP item total'
      using errcode = '22023';
  end if;
  v_item_gross := public.clp_round(p_item_gross);

  -- Las bicicletas del carrito (20261121120000). Sin líneas, ninguna: la
  -- cotización es la de siempre.
  if p_lines is not null then
    select bike.bike_units, public.clp_round(bike.bike_gross)
      into v_bike_units, v_bike_gross
      from public.online_shipping_bike_lines_internal(p_tenant_id, p_lines) bike;
    v_bike_units := coalesce(v_bike_units, 0);
    v_bike_gross := least(greatest(coalesce(v_bike_gross, 0), 0), v_item_gross);
  end if;

  if v_delivery_type = 'pickup' then
    return jsonb_build_object(
      'delivery_type', 'pickup',
      'country_code', 'CL',
      'item_gross', v_item_gross,
      'shipping_gross', 0,
      'shipping_net', 0,
      'shipping_tax', 0,
      'tax_rate', 0,
      'estimated_min_business_days', 0,
      'estimated_max_business_days', 0,
      'bike_units', v_bike_units,
      'quoted_at', clock_timestamp()
    );
  end if;

  if v_country <> 'CL' then
    raise exception 'Online shipping is currently available only in Chile'
      using errcode = '22023';
  end if;

  -- La zona de la región de destino. Con una sola zona la región puede
  -- faltar: un checkout anterior a las zonas cotiza igual que antes.
  v_region_code := public.online_shipping_region_code(v_region_text);
  if v_region_text is not null and v_region_code is null then
    raise exception 'No reconocemos la región «%». Elígela de nuevo en la dirección.', v_region_text
      using errcode = '22023';
  end if;
  if v_region_code is null then
    select count(*) into v_zone_count
      from public.online_shipping_zones zone
     where zone.tenant_id = p_tenant_id and zone.is_active;
    if v_zone_count <> 1 then
      raise exception 'Indica la región de despacho para calcular el costo.'
        using errcode = '22023';
    end if;
    select zone.* into v_zone
      from public.online_shipping_zones zone
     where zone.tenant_id = p_tenant_id and zone.is_active;
  else
    select zone.* into v_zone
      from public.online_shipping_zones zone
     where zone.tenant_id = p_tenant_id
       and zone.is_active
       and v_region_code = any(zone.region_codes);
    if not found then
      raise exception 'Por ahora no despachamos a la región de %.', public.online_shipping_region_name(v_region_code)
        using errcode = '23514';
    end if;
  end if;

  select count(*)
    into v_match_count
    from public.online_shipping_rate_tiers tier
   where tier.tenant_id = p_tenant_id
     and tier.zone_id = v_zone.id
     and tier.country_code = v_country
     and tier.is_active
     and v_item_gross >= tier.min_order_gross
     and (tier.max_order_gross is null or v_item_gross < tier.max_order_gross);

  if v_match_count <> 1 then
    raise exception 'Shipping tariff is unavailable or ambiguous for this order'
      using errcode = '23514';
  end if;

  select tier.*
    into strict v_tier
    from public.online_shipping_rate_tiers tier
   where tier.tenant_id = p_tenant_id
     and tier.zone_id = v_zone.id
     and tier.country_code = v_country
     and tier.is_active
     and v_item_gross >= tier.min_order_gross
     and (tier.max_order_gross is null or v_item_gross < tier.max_order_gross);

  if v_bike_units > 0 then
    if v_zone.bike_shipping_gross is null then
      raise exception 'Por ahora no despachamos bicicletas a %. Puedes retirarla en la tienda.',
        coalesce('la región de ' || public.online_shipping_region_name(v_region_code), '«' || v_zone.name || '»')
        using errcode = '23514';
    end if;
    -- Lo que no es bicicleta paga el tramo de su propio monto.
    v_parcel_gross := v_item_gross - v_bike_gross;
    if v_parcel_gross > 0 then
      select tier.*
        into v_parcel_tier
        from public.online_shipping_rate_tiers tier
       where tier.tenant_id = p_tenant_id
         and tier.zone_id = v_zone.id
         and tier.country_code = v_country
         and tier.is_active
         and v_parcel_gross >= tier.min_order_gross
         and (tier.max_order_gross is null or v_parcel_gross < tier.max_order_gross)
       order by tier.min_order_gross desc
       limit 1;
      if not found then
        raise exception 'Shipping tariff is unavailable or ambiguous for this order'
          using errcode = '23514';
      end if;
      v_parcel_shipping := v_parcel_tier.shipping_gross;
    end if;
    v_shipping_gross := v_bike_units * v_zone.bike_shipping_gross + v_parcel_shipping;
  else
    v_shipping_gross := v_tier.shipping_gross;
  end if;

  if v_tier.tax_rate = 19 then
    v_net := public.clp_round(v_shipping_gross / 1.19);
    v_tax := v_shipping_gross - v_net;
  else
    v_net := v_shipping_gross;
    v_tax := 0;
  end if;

  return jsonb_build_object(
    'delivery_type', 'shipping',
    'country_code', v_country,
    'item_gross', v_item_gross,
    'tier_id', v_tier.id,
    'zone_id', v_zone.id,
    'zone_name', v_zone.name,
    'region_code', v_region_code,
    'min_order_gross', v_tier.min_order_gross,
    'max_order_gross', v_tier.max_order_gross,
    'shipping_gross', v_shipping_gross,
    'shipping_net', v_net,
    'shipping_tax', v_tax,
    'tax_rate', v_tier.tax_rate,
    'estimated_min_business_days', v_tier.estimated_min_business_days,
    'estimated_max_business_days', v_tier.estimated_max_business_days,
    'bike_units', v_bike_units,
    'bike_shipping_gross', case when v_bike_units > 0 then v_zone.bike_shipping_gross end,
    'bike_items_gross', case when v_bike_units > 0 then v_bike_gross end,
    'parcel_shipping_gross', case when v_bike_units > 0 then v_parcel_shipping end,
    'quoted_at', clock_timestamp()
  );
end;
$function$;

revoke all on function public.quote_online_shipping_internal(uuid, text, numeric, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.quote_online_shipping_internal(uuid, text, numeric, text, text, jsonb)
  to service_role;

create or replace function public.quote_public_online_shipping(
  p_tenant_id uuid,
  p_delivery_type text,
  p_item_gross numeric,
  p_country_code text default 'CL',
  p_region text default null,
  p_lines jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $function$
begin
  if not exists (
    select 1
      from public.tenants tenant
     where tenant.id = p_tenant_id
       and tenant.is_active is true
  ) then
    raise exception 'Storefront tenant is invalid or inactive'
      using errcode = '42501';
  end if;

  return public.quote_online_shipping_internal(
    p_tenant_id,
    p_delivery_type,
    p_item_gross,
    p_country_code,
    p_region,
    p_lines
  );
end;
$function$;

revoke all on function public.quote_public_online_shipping(uuid, text, numeric, text, text, jsonb) from public;
grant execute on function public.quote_public_online_shipping(uuid, text, numeric, text, text, jsonb)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. La tienda: el precio por bicicleta de cada zona y qué es bicicleta, en
--    la lectura de tramos que ya hace cada página.
-- ---------------------------------------------------------------------------
drop function if exists public.get_public_online_shipping_tiers(uuid);

create or replace function public.get_public_online_shipping_tiers(p_tenant_id uuid)
returns table (
  country_code text,
  min_order_gross numeric,
  max_order_gross numeric,
  shipping_gross numeric,
  estimated_min_business_days integer,
  estimated_max_business_days integer,
  zone_name text,
  zone_sort_order integer,
  region_codes text[],
  bike_shipping_gross numeric,
  bike_category_ids uuid[]
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with bike as (
    select public.online_shipping_bike_category_ids_internal(p_tenant_id) as ids
  )
  select tier.country_code,
         tier.min_order_gross,
         tier.max_order_gross,
         tier.shipping_gross,
         tier.estimated_min_business_days,
         tier.estimated_max_business_days,
         zone.name,
         zone.sort_order,
         zone.region_codes,
         zone.bike_shipping_gross,
         bike.ids
    from public.online_shipping_rate_tiers tier
    join public.online_shipping_zones zone
      on zone.id = tier.zone_id
     and zone.tenant_id = tier.tenant_id
     and zone.is_active
   cross join bike
   where tier.tenant_id = p_tenant_id
     and tier.is_active
   order by zone.sort_order, zone.created_at, tier.country_code, tier.min_order_gross;
$function$;

revoke all on function public.get_public_online_shipping_tiers(uuid) from public;
grant execute on function public.get_public_online_shipping_tiers(uuid)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. «Envíos» en el editor: el precio por bicicleta y qué es bicicleta.
-- ---------------------------------------------------------------------------
create or replace function public.online_shipping_zones_for_editor()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', zone.id,
             'name', zone.name,
             'region_codes', to_jsonb(zone.region_codes),
             'sort_order', zone.sort_order,
             'bike_shipping_gross', zone.bike_shipping_gross,
             'tiers', coalesce((
               select jsonb_agg(jsonb_build_object(
                        'min_order_gross', tier.min_order_gross,
                        'max_order_gross', tier.max_order_gross,
                        'shipping_gross', tier.shipping_gross,
                        'estimated_min_business_days', tier.estimated_min_business_days,
                        'estimated_max_business_days', tier.estimated_max_business_days
                      ) order by tier.min_order_gross)
                 from public.online_shipping_rate_tiers tier
                where tier.tenant_id = v_tenant_id
                  and tier.zone_id = zone.id
                  and tier.is_active
             ), '[]'::jsonb)
           ) order by zone.sort_order, zone.created_at)
      from public.online_shipping_zones zone
     where zone.tenant_id = v_tenant_id
       and zone.is_active
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.online_shipping_zones_for_editor() from public, anon, authenticated;
grant execute on function public.online_shipping_zones_for_editor() to authenticated;

-- Reemplaza las zonas y tramos activos del taller por los que manda el
-- editor, en una transacción. Lo anterior queda inactivo (los pedidos guardan
-- el tramo con que se cobraron). Cada zona cubre todos los montos: el primer
-- tramo parte en $0, cada uno empieza donde termina el anterior y el último
-- no tiene tope. Cada zona puede traer su precio por bicicleta
-- (20261121120000); si no lo trae, conserva el de la zona del mismo nombre.
create or replace function public.save_online_shipping_zones(p_zones jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_zone jsonb;
  v_tier jsonb;
  v_zone_id uuid;
  v_zone_index integer := 0;
  v_tier_index integer;
  v_name text;
  v_codes text[];
  v_bad text;
  v_previous_max numeric;
  v_min numeric;
  v_max numeric;
  v_price numeric;
  v_days_min integer;
  v_days_max integer;
  v_tier_count integer;
  v_previous_bike jsonb;
  v_bike numeric;
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_zones, 'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_zones) = 0 then
    raise exception 'Agrega al menos una zona de despacho.' using errcode = '22023';
  end if;
  if jsonb_array_length(p_zones) > 16 then
    raise exception 'Hay más zonas que regiones.' using errcode = '22023';
  end if;

  perform 1 from public.online_shipping_zones zone
   where zone.tenant_id = v_tenant_id
   for update;

  -- Lo que cobraba cada zona por bicicleta, por si el editor no lo manda.
  select coalesce(jsonb_object_agg(lower(btrim(zone.name)), zone.bike_shipping_gross), '{}'::jsonb)
    into v_previous_bike
    from public.online_shipping_zones zone
   where zone.tenant_id = v_tenant_id
     and zone.is_active
     and zone.bike_shipping_gross is not null;

  update public.online_shipping_rate_tiers tier
     set is_active = false
   where tier.tenant_id = v_tenant_id and tier.is_active;
  update public.online_shipping_zones zone
     set is_active = false
   where zone.tenant_id = v_tenant_id and zone.is_active;

  for v_zone in select value from jsonb_array_elements(p_zones) loop
    v_zone_index := v_zone_index + 1;
    v_name := btrim(coalesce(v_zone->>'name', ''));
    if v_name = '' or char_length(v_name) > 60 then
      raise exception 'La zona % necesita un nombre (hasta 60 letras).', v_zone_index
        using errcode = '22023';
    end if;
    if jsonb_typeof(v_zone->'region_codes') <> 'array'
       or jsonb_array_length(v_zone->'region_codes') = 0 then
      raise exception 'Elige al menos una región para «%».', v_name using errcode = '22023';
    end if;
    select array_agg(upper(btrim(code))) into v_codes
      from jsonb_array_elements_text(v_zone->'region_codes') code;
    select string_agg(code, ', ') into v_bad
      from unnest(v_codes) code
     where code <> all(public.online_shipping_region_codes());
    if v_bad is not null then
      raise exception 'Región desconocida en «%»: %.', v_name, v_bad using errcode = '22023';
    end if;

    if v_zone ? 'bike_shipping_gross' then
      begin
        v_bike := nullif(btrim(coalesce(v_zone->>'bike_shipping_gross', '')), '')::numeric;
      exception when others then
        raise exception 'El despacho de bicicleta de «%» tiene un número inválido.', v_name
          using errcode = '22023';
      end;
    else
      v_bike := (v_previous_bike->>lower(v_name))::numeric;
    end if;
    if v_bike is not null and (v_bike < 0 or v_bike <> public.clp_round(v_bike)) then
      raise exception 'Escribe el despacho de bicicleta de «%» en pesos enteros.', v_name
        using errcode = '22023';
    end if;

    insert into public.online_shipping_zones (tenant_id, name, region_codes, sort_order, bike_shipping_gross)
    values (v_tenant_id, v_name, v_codes, v_zone_index, v_bike)
    returning id into v_zone_id;

    if jsonb_typeof(v_zone->'tiers') <> 'array'
       or jsonb_array_length(v_zone->'tiers') = 0 then
      raise exception '«%» necesita al menos una tarifa.', v_name using errcode = '22023';
    end if;
    v_tier_count := jsonb_array_length(v_zone->'tiers');
    if v_tier_count > 10 then
      raise exception '«%» tiene más de 10 tramos.', v_name using errcode = '22023';
    end if;

    v_previous_max := 0;
    v_tier_index := 0;
    for v_tier in
      select value from jsonb_array_elements(v_zone->'tiers')
       order by coalesce((value->>'min_order_gross')::numeric, 0)
    loop
      v_tier_index := v_tier_index + 1;
      begin
        v_min := coalesce((v_tier->>'min_order_gross')::numeric, 0);
        v_max := nullif(btrim(coalesce(v_tier->>'max_order_gross', '')), '')::numeric;
        v_price := (v_tier->>'shipping_gross')::numeric;
        v_days_min := coalesce((v_tier->>'estimated_min_business_days')::integer, 0);
        v_days_max := coalesce((v_tier->>'estimated_max_business_days')::integer, v_days_min);
      exception when others then
        raise exception 'Una tarifa de «%» tiene un número inválido.', v_name using errcode = '22023';
      end;
      if v_price is null or v_price < 0 or v_price <> public.clp_round(v_price) then
        raise exception 'Escribe el precio de cada tramo de «%» en pesos enteros.', v_name
          using errcode = '22023';
      end if;
      if v_min <> v_previous_max then
        raise exception 'Los tramos de «%» deben seguirse sin huecos desde $0.', v_name
          using errcode = '22023';
      end if;
      if v_max is not null and (v_max <= v_min or v_max <> public.clp_round(v_max)) then
        raise exception 'Cada tramo de «%» debe terminar después de donde empieza.', v_name
          using errcode = '22023';
      end if;
      if (v_tier_index < v_tier_count) <> (v_max is not null) then
        raise exception 'En «%» sólo el último tramo queda sin tope.', v_name
          using errcode = '22023';
      end if;
      if v_days_min < 0 or v_days_max < v_days_min or v_days_max > 60 then
        raise exception 'Revisa los días de entrega de «%».', v_name using errcode = '22023';
      end if;

      insert into public.online_shipping_rate_tiers (
        tenant_id, zone_id, country_code, min_order_gross, max_order_gross,
        shipping_gross, tax_rate, estimated_min_business_days,
        estimated_max_business_days, is_active
      ) values (
        v_tenant_id, v_zone_id, 'CL', v_min, v_max,
        v_price, 19, v_days_min, v_days_max, true
      );
      v_previous_max := v_max;
    end loop;
  end loop;

  return public.online_shipping_zones_for_editor();
end;
$function$;

comment on function public.save_online_shipping_zones(jsonb) is
  'The site editor''s «Envíos»: replaces the tenant''s active shipping zones and their tiers in one transaction, with each zone''s price per bicycle (20261121120000; kept from the zone of the same name when the editor does not send it). Previous rows stay inactive (orders keep the tier they were charged with).';

revoke all on function public.save_online_shipping_zones(jsonb) from public, anon, authenticated;
grant execute on function public.save_online_shipping_zones(jsonb) to authenticated;

-- Las categorías que se despachan como bicicleta, como las eligió el equipo.
create or replace function public.online_shipping_bike_categories_for_editor()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'id', category.id,
             'name', category.name,
             'full_path', coalesce(nullif(category.full_path, ''), category.name)
           ) order by coalesce(nullif(category.full_path, ''), category.name))
      from public.online_shipping_bike_categories bike
      join public.product_categories category
        on category.id = bike.category_id
       and category.tenant_id = bike.tenant_id
     where bike.tenant_id = v_tenant_id
  ), '[]'::jsonb);
end;
$function$;

revoke all on function public.online_shipping_bike_categories_for_editor() from public, anon, authenticated;
grant execute on function public.online_shipping_bike_categories_for_editor() to authenticated;

create or replace function public.save_online_shipping_bike_categories_v1(p_category_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_ids uuid[] := coalesce(p_category_ids, array[]::uuid[]);
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.is_active_tenant_member(v_tenant_id) then
    raise exception 'Authenticated tenant context is required' using errcode = '42501';
  end if;
  if cardinality(v_ids) > 50 then
    raise exception 'Son demasiadas categorías.' using errcode = '22023';
  end if;
  if exists (
    select 1
      from unnest(v_ids) wanted(category_id)
     where wanted.category_id is null
        or not exists (
          select 1 from public.product_categories category
           where category.id = wanted.category_id
             and category.tenant_id = v_tenant_id
        )
  ) then
    raise exception 'Una de las categorías no existe.' using errcode = '22023';
  end if;

  delete from public.online_shipping_bike_categories bike
   where bike.tenant_id = v_tenant_id
     and bike.category_id <> all(v_ids);
  insert into public.online_shipping_bike_categories (tenant_id, category_id)
  select v_tenant_id, wanted.category_id
    from unnest(v_ids) wanted(category_id)
  on conflict (tenant_id, category_id) do nothing;

  return public.online_shipping_bike_categories_for_editor();
end;
$function$;

comment on function public.save_online_shipping_bike_categories_v1(uuid[]) is
  'Sitio Web › Envíos: las categorías que se despachan como bicicleta (20261121120000). Reemplaza la lista del taller.';

revoke all on function public.save_online_shipping_bike_categories_v1(uuid[]) from public, anon, authenticated;
grant execute on function public.save_online_shipping_bike_categories_v1(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. El pedido web y la cotización aceptada cotizan con sus líneas.
--    Lectura de producción del 2026-11-21; sólo cambia la llamada a la
--    cotización (el sexto argumento).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_public_online_order_unkeyed(p_order_data jsonb, p_order_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_customer_id uuid;
  v_auth_uid uuid := auth.uid();
  v_customer_name text;
  v_customer_email text;
  v_customer_phone text;
  v_customer_address text;
  v_delivery_type text;
  v_payment_method text;
  v_order_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_quantity integer;
  v_product record;
  v_unit_price numeric(12,2);
  v_line_total numeric(12,2);
  v_customer_id_text text;
  v_checkout_key text;
  v_created_response jsonb;
  v_item_tax_snapshot jsonb;
  v_shipping_quote jsonb;
  v_expected_shipping_gross numeric(12,2);
  v_shipping_gross numeric(12,2);
  v_shipping_net numeric(12,2);
  v_shipping_tax numeric(12,2);
  v_shipping_tax_rate numeric(5,2);
  v_shipping_tier_id uuid;
  v_shipping_country text;
  -- Lo que llega del proveedor (20261120210000): la línea sabe de dónde sale.
  v_fulfillment text;
  v_offer_product uuid;
  v_offer_supplier uuid;
  v_offer_lead_min smallint;
  v_offer_lead_max smallint;
  v_offer_max integer;
begin
  if p_order_data is null or jsonb_typeof(p_order_data) <> 'object' then
    raise exception 'Invalid order payload';
  end if;

  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array'
     or jsonb_array_length(p_order_items) = 0 then
    raise exception 'Order must include at least one item';
  end if;
  if jsonb_array_length(p_order_items) > 50 then
    raise exception 'Order item limit exceeded';
  end if;

  v_tenant_id := nullif(p_order_data->>'tenant_id', '')::uuid;
  if v_tenant_id is null or not exists (
    select 1 from public.tenants tenant where tenant.id = v_tenant_id
  ) then
    raise exception 'Invalid tenant_id';
  end if;

  v_customer_name := btrim(coalesce(p_order_data->>'customer_name', ''));
  v_customer_email := lower(btrim(coalesce(p_order_data->>'customer_email', '')));
  v_customer_phone := nullif(btrim(coalesce(p_order_data->>'customer_phone', '')), '');
  v_customer_address := nullif(btrim(coalesce(p_order_data->>'customer_address', '')), '');
  v_delivery_type := lower(btrim(coalesce(
    nullif(p_order_data->>'delivery_type', ''),
    'shipping'
  )));
  v_payment_method := lower(btrim(coalesce(
    nullif(p_order_data->>'payment_method', ''),
    'transfer'
  )));
  v_checkout_key := nullif(
    btrim(coalesce(p_order_data->>'checkout_idempotency_key', '')),
    ''
  );
  v_shipping_country := btrim(coalesce(
    nullif(p_order_data->>'shipping_country', ''),
    'Chile'
  ));

  if length(v_customer_name) < 2 or length(v_customer_name) > 160 then
    raise exception 'Invalid customer name';
  end if;
  if v_customer_email !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Invalid customer email';
  end if;
  if v_customer_phone is not null and length(v_customer_phone) > 40 then
    raise exception 'Invalid customer phone';
  end if;
  if v_delivery_type not in ('shipping', 'pickup') then
    raise exception 'Invalid delivery type: %', v_delivery_type;
  end if;
  if v_delivery_type = 'shipping'
     and lower(v_shipping_country) not in ('chile', 'cl') then
    raise exception 'Online shipping is currently available only in Chile';
  end if;
  if v_payment_method not in (
    'mercadopago', 'mercado_pago', 'transfer', 'bank_transfer'
  ) then
    raise exception 'Invalid payment method: %', v_payment_method;
  end if;

  if v_payment_method = 'mercado_pago' then
    v_payment_method := 'mercadopago';
  elsif v_payment_method = 'bank_transfer' then
    v_payment_method := 'transfer';
  end if;

  if v_delivery_type = 'shipping'
     and coalesce(
       nullif(p_order_data->>'shipping_address_line1', ''),
       v_customer_address
     ) is null then
    raise exception 'Shipping address is required';
  end if;

  if p_order_data ? 'shipping_quote_cost' then
    begin
      v_expected_shipping_gross :=
        (p_order_data->>'shipping_quote_cost')::numeric;
    exception when others then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end;
    if v_expected_shipping_gross is null
       or v_expected_shipping_gross < 0
       or v_expected_shipping_gross
            <> public.clp_round(v_expected_shipping_gross) then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end if;
  end if;

  v_customer_id_text := nullif(p_order_data->>'customer_id', '');
  if v_customer_id_text is not null then
    v_customer_id := v_customer_id_text::uuid;
    if v_auth_uid is null or not exists (
      select 1
        from public.customers customer
       where customer.id = v_customer_id
         and customer.tenant_id = v_tenant_id
         and customer.auth_user_id = v_auth_uid
    ) then
      raise exception 'Invalid customer reference';
    end if;
  end if;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', 'true', true);

  insert into public.online_orders (
    tenant_id,
    order_number,
    customer_id,
    customer_email,
    customer_name,
    customer_phone,
    customer_address,
    delivery_type,
    shipping_address_line1,
    shipping_address_line2,
    shipping_city,
    shipping_state,
    shipping_postal_code,
    shipping_country,
    subtotal,
    tax_amount,
    shipping_cost,
    shipping_net_amount,
    shipping_tax_amount,
    shipping_tax_rate,
    shipping_rate_snapshot,
    discount_amount,
    total,
    status,
    payment_status,
    payment_method,
    customer_notes
  ) values (
    v_tenant_id,
    public.generate_online_order_number(v_tenant_id, clock_timestamp()),
    v_customer_id,
    v_customer_email,
    v_customer_name,
    v_customer_phone,
    v_customer_address,
    v_delivery_type,
    nullif(btrim(coalesce(p_order_data->>'shipping_address_line1', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_address_line2', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_city', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_state', '')), ''),
    nullif(btrim(coalesce(p_order_data->>'shipping_postal_code', '')), ''),
    case when v_delivery_type = 'pickup' then null else 'Chile' end,
    0,
    0,
    0,
    0,
    0,
    0,
    '{}'::jsonb,
    0,
    0,
    'pending',
    'pending',
    v_payment_method,
    nullif(left(btrim(coalesce(p_order_data->>'customer_notes', '')), 1000), '')
  ) returning id into v_order_id;

  for v_item in select value from jsonb_array_elements(p_order_items)
  loop
    v_product_id := nullif(v_item->>'product_id', '')::uuid;
    v_quantity := coalesce((v_item->>'quantity')::integer, 0);

    if v_product_id is null then
      raise exception 'Order item is missing product_id';
    end if;
    if v_quantity < 1 or v_quantity > 99 then
      raise exception 'Invalid quantity for product %', v_product_id;
    end if;
    v_fulfillment := 'stock';
    v_offer_product := null;
    v_offer_supplier := null;
    v_offer_lead_min := null;
    v_offer_lead_max := null;
    v_offer_max := null;

    select
      product.id,
      product.name,
      product.sku,
      coalesce(product.website_price, product.price) as public_price,
      product.cost,
      product.tax_rate,
      product.product_type,
      product.is_service,
      product.purchase_treatment,
      product.track_stock,
      product.is_set,
      product.inventory_qty,
      product.stock_quantity
      into v_product
      from public.products product
     where product.id = v_product_id
       and product.tenant_id = v_tenant_id
       and product.is_active = true
       and coalesce(product.is_published, false) = true
       and coalesce(product.show_on_website, false) = true
     for update;

    if not found then
      raise exception 'Product is unavailable: %', v_product_id;
    end if;
    if v_product.tax_rate is null
       or v_product.tax_rate not in (0, 0.19, 19) then
      raise exception 'Product % has missing or unsupported tax classification',
        v_product.name
        using errcode = '23514';
    end if;

    if not (
      coalesce(v_product.is_service, false)
      or v_product.product_type = 'service'
    )
       and coalesce(v_product.track_stock, true) then
      if coalesce(v_product.is_set, false) then
        -- Canonical set headers are virtual. Validate their component map and
        -- availability after active reservations; the item-insert trigger then
        -- locks and reserves every physical component atomically.
        perform public.assert_valid_product_set_maps(
          v_tenant_id,
          jsonb_build_array(jsonb_build_object(
            'product_id', v_product.id,
            'quantity', v_quantity
          ))
        );
        if public.online_product_available_quantity(
          v_tenant_id,
          v_product.id
        ) < v_quantity then
          raise exception 'Insufficient stock for product %', v_product.name;
        end if;
      else
        if v_product.stock_quantity is not null
           and v_product.inventory_qty is not null
           and v_product.stock_quantity <> v_product.inventory_qty then
          raise exception 'Product stock columns disagree; checkout blocked for %',
            v_product.name;
        end if;
        -- Lo que se vende con plazo (20261120210000): si lo libre no alcanza
        -- y el proveedor lo tiene según su última lectura, la línea entera
        -- llega del proveedor, hasta lo que la regla deja pedir. Sin esa
        -- regla, todo sigue como siempre.
        select offer.product_id, offer.supplier_id, offer.lead_days_min,
               offer.lead_days_max, offer.max_quantity
          into v_offer_product, v_offer_supplier, v_offer_lead_min,
               v_offer_lead_max, v_offer_max
          from public.product_on_order_offer_internal_v1(
                 v_tenant_id, array[v_product.id]
               ) offer;
        if v_offer_product is not null
           and public.online_product_available_quantity(v_tenant_id, v_product.id)
               < v_quantity then
          if v_offer_max < v_quantity then
            raise exception 'Insufficient stock for product %', v_product.name;
          end if;
          v_fulfillment := 'on_order';
        elsif coalesce(v_product.stock_quantity, v_product.inventory_qty, 0)
           < v_quantity then
          raise exception 'Insufficient stock for product %', v_product.name;
        end if;
      end if;
    end if;

    if v_product.public_price is null
       or v_product.public_price <= 0
       or v_product.public_price <> public.clp_round(v_product.public_price) then
      raise exception 'Product % requires a positive whole-CLP website price',
        v_product.name
        using errcode = '23514';
    end if;
    -- Después de los rechazos con su propio mensaje (IVA, stock, precio),
    -- la misma regla que decide qué se lista: un consumible del taller, un
    -- producto bajo el costo o sin foto no se compra aunque llegue su id.
    if exists (
      select 1
        from public.products rule_product
       where rule_product.id = v_product_id
         and rule_product.tenant_id = v_tenant_id
         and public.catalog_product_web_block_v1(
               rule_product,
               public.catalog_web_policy_v1(v_tenant_id)
             ) is not null
    ) then
      raise exception 'Product is unavailable: %', v_product_id;
    end if;
    v_unit_price := public.clp_round(v_product.public_price);
    v_line_total := public.clp_round(v_unit_price * v_quantity);

    insert into public.online_order_items (
      tenant_id,
      order_id,
      product_id,
      product_name,
      product_sku,
      quantity,
      unit_price,
      subtotal,
      unit_cost,
      tax_rate,
      is_service,
      purchase_treatment,
      product_type,
      fulfillment,
      on_order_supplier_id,
      lead_days_min,
      lead_days_max
    ) values (
      v_tenant_id,
      v_order_id,
      v_product.id,
      v_product.name,
      v_product.sku,
      v_quantity,
      v_unit_price,
      v_line_total,
      v_product.cost,
      case when v_product.tax_rate = 0.19 then 19 else v_product.tax_rate end,
      (
        coalesce(v_product.is_service, false)
        or v_product.product_type = 'service'
      ),
      coalesce(v_product.purchase_treatment, 'inventory'),
      coalesce(v_product.product_type, 'product'),
      v_fulfillment,
      case when v_fulfillment = 'on_order' then v_offer_supplier end,
      case when v_fulfillment = 'on_order' then v_offer_lead_min end,
      case when v_fulfillment = 'on_order' then v_offer_lead_max end
    );
  end loop;

  v_item_tax_snapshot := public.calculate_online_order_tax_snapshot(
    v_order_id,
    v_tenant_id
  );
  v_shipping_quote := public.quote_online_shipping_internal(
    v_tenant_id,
    v_delivery_type,
    (v_item_tax_snapshot->>'gross_amount')::numeric,
    'CL',
    nullif(btrim(coalesce(p_order_data->>'shipping_state', '')), ''),
    -- Las líneas del pedido: cada bicicleta paga su despacho (20261121120000).
    public.online_order_shipping_lines_internal(v_order_id, v_tenant_id)
  );
  v_shipping_gross := (v_shipping_quote->>'shipping_gross')::numeric;
  v_shipping_net := (v_shipping_quote->>'shipping_net')::numeric;
  v_shipping_tax := (v_shipping_quote->>'shipping_tax')::numeric;
  v_shipping_tax_rate := (v_shipping_quote->>'tax_rate')::numeric;
  v_shipping_tier_id := nullif(v_shipping_quote->>'tier_id', '')::uuid;

  if v_expected_shipping_gross is null then
    if v_shipping_gross > 0 then
      raise exception 'A current shipping quote is required before checkout'
        using errcode = '23514';
    end if;
    v_expected_shipping_gross := 0;
  end if;

  if v_expected_shipping_gross <> v_shipping_gross then
    raise exception 'Shipping quote changed; refresh checkout before paying'
      using errcode = '40001';
  end if;

  perform pg_catalog.set_config(
    'app.online_order_shipping_quote_in_progress',
    'true',
    true
  );
  update public.online_orders
     set subtotal = (v_item_tax_snapshot->>'net_amount')::numeric,
         tax_amount = (v_item_tax_snapshot->>'tax_amount')::numeric,
         shipping_cost = v_shipping_gross,
         shipping_net_amount = v_shipping_net,
         shipping_tax_amount = v_shipping_tax,
         shipping_tax_rate = v_shipping_tax_rate,
         shipping_rate_tier_id = v_shipping_tier_id,
         shipping_rate_snapshot = v_shipping_quote,
         discount_amount = 0,
         total = (v_item_tax_snapshot->>'gross_amount')::numeric
           + v_shipping_gross
   where id = v_order_id
     and tenant_id = v_tenant_id;
  perform pg_catalog.set_config(
    'app.online_order_shipping_quote_in_progress',
    '',
    true
  );

  select jsonb_build_object(
    'success', true,
    'order_id', orders.id,
    'status', orders.status,
    'payment_status', orders.payment_status,
    'version', orders.version,
    'invoice_id', orders.sales_invoice_id,
    'total', orders.total,
    'shipping_cost', orders.shipping_cost,
    'changed', true
  )
    into v_created_response
    from public.online_orders orders
   where orders.id = v_order_id
     and orders.tenant_id = v_tenant_id;

  insert into public.online_order_events (
    tenant_id,
    order_id,
    event_type,
    from_status,
    to_status,
    from_payment_status,
    to_payment_status,
    changed,
    expected_version,
    result_version,
    actor_id,
    operation_key,
    request_snapshot,
    response_snapshot
  )
  select
    orders.tenant_id,
    orders.id,
    'order_created',
    null,
    orders.status,
    null,
    orders.payment_status,
    true,
    null,
    orders.version,
    v_auth_uid,
    'checkout-created:' || orders.id::text,
    jsonb_build_object(
      'source', 'public_checkout',
      'checkout_idempotency_key', v_checkout_key,
      'delivery_type', orders.delivery_type,
      'payment_method', orders.payment_method,
      'item_count', jsonb_array_length(p_order_items),
      'tax_source', 'product_line_snapshot',
      'shipping_quote', orders.shipping_rate_snapshot,
      'accepted_shipping_cost', v_expected_shipping_gross
    ),
    v_created_response
  from public.online_orders orders
  where orders.id = v_order_id
    and orders.tenant_id = v_tenant_id;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);

  if v_payment_method <> 'mercadopago' then
    perform public.process_public_checkout_order(v_order_id, v_tenant_id);
  end if;

  return v_order_id;
exception
  when others then
    perform pg_catalog.set_config(
      'app.online_order_shipping_quote_in_progress',
      '',
      true
    );
    perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);
    raise;
end;
$function$;

CREATE OR REPLACE FUNCTION public.accept_public_customer_quote_v1(p_token text, p_request jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_access public.customer_quote_access_tokens;
  v_quote public.customer_quotes%rowtype;
  v_offer public.customer_quote_offers%rowtype;
  v_event public.customer_quote_events%rowtype;
  v_key text := lower(btrim(coalesce(p_request ->> 'operation_key', '')));
  v_delivery text := lower(btrim(coalesce(p_request ->> 'delivery_type', '')));
  v_method text := lower(btrim(coalesce(p_request ->> 'payment_method', '')));
  v_line1 text := nullif(left(btrim(coalesce(p_request ->> 'shipping_address_line1', '')), 200), '');
  v_line2 text := nullif(left(btrim(coalesce(p_request ->> 'shipping_address_line2', '')), 200), '');
  v_city text := nullif(left(btrim(coalesce(p_request ->> 'shipping_city', '')), 120), '');
  v_region text := nullif(left(btrim(coalesce(p_request ->> 'shipping_state', '')), 120), '');
  v_postal text := nullif(left(btrim(coalesce(p_request ->> 'shipping_postal_code', '')), 20), '');
  v_notes text := nullif(left(btrim(coalesce(p_request ->> 'customer_notes', '')), 1000), '');
  v_expected_shipping numeric;
  v_capabilities jsonb;
  v_capability jsonb;
  v_settings public.customer_quote_settings%rowtype;
  v_line record;
  v_product public.products%rowtype;
  v_order_id uuid;
  v_tax_rate numeric;
  v_on_order integer := 0;
  v_item_snapshot jsonb;
  v_shipping jsonb;
  v_shipping_gross numeric(12,2);
  v_created jsonb;
  v_access_token jsonb;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Invalid quote acceptance' using errcode = '22023';
  end if;
  if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'A random operation key is required' using errcode = '22023';
  end if;

  v_access := public.customer_quote_token_internal(p_token, 'respond_quote');
  if v_access.id is null then
    raise exception 'quote_link_invalid' using errcode = '42501';
  end if;
  select * into v_quote from public.customer_quotes
   where id = v_access.quote_id and tenant_id = v_access.tenant_id
   for update;

  -- La misma aceptación repetida (una respuesta perdida) devuelve el mismo
  -- pedido con un acceso nuevo.
  select * into v_event from public.customer_quote_events e
   where e.quote_id = v_quote.id and e.operation_key = v_key;
  if found then
    if v_event.event_type <> 'accepted' or v_quote.online_order_id is null then
      raise exception 'Operation key already used' using errcode = '23505';
    end if;
    v_access_token := public.issue_online_order_access_token(
      v_quote.online_order_id, array['view_order']::text[], clock_timestamp() + interval '30 days'
    );
    return public.customer_quote_order_receipt_internal(v_quote.online_order_id, v_access_token, true);
  end if;

  if v_quote.status <> 'offered' then
    raise exception 'quote_not_open' using errcode = '55000', detail = v_quote.status;
  end if;
  select * into v_offer from public.customer_quote_offers where id = v_quote.current_offer_id for update;
  if (p_request ->> 'offer_id') is not null
     and (p_request ->> 'offer_id')::uuid is distinct from v_offer.id then
    raise exception 'quote_offer_outdated' using errcode = '40001';
  end if;
  if v_offer.valid_until <= clock_timestamp() then
    raise exception 'quote_offer_expired' using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.customer_quote_offer_lines l
     where l.offer_id = v_offer.id and l.quantity_offered > 0
       and l.availability in ('in_stock', 'on_order')
  ) then
    raise exception 'quote_offer_empty' using errcode = '55000';
  end if;
  if v_quote.customer_email is null then
    raise exception 'quote_contact_invalid' using errcode = '22023', detail = 'customer_email';
  end if;

  if v_delivery not in ('pickup', 'shipping') then
    raise exception 'quote_delivery_invalid' using errcode = '22023';
  end if;
  if v_delivery = 'shipping' and (v_line1 is null or v_city is null or v_region is null) then
    raise exception 'quote_address_required' using errcode = '22023';
  end if;
  if v_method = 'mercado_pago' then
    v_method := 'mercadopago';
  elsif v_method = 'bank_transfer' then
    v_method := 'transfer';
  end if;
  if v_method not in ('mercadopago', 'transfer') then
    raise exception 'quote_payment_invalid' using errcode = '22023';
  end if;
  v_capabilities := public.resolve_public_checkout_capabilities(v_quote.tenant_id);
  select method.value into v_capability
    from jsonb_array_elements(v_capabilities -> 'methods') method(value)
   where method.value ->> 'code' = v_method;
  if v_capability is null or coalesce((v_capability ->> 'available')::boolean, false) is not true then
    raise exception 'quote_payment_unavailable' using errcode = 'P0001';
  end if;
  if p_request ? 'shipping_quote_cost' then
    begin
      v_expected_shipping := (p_request ->> 'shipping_quote_cost')::numeric;
    exception when others then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end;
    if v_expected_shipping is null or v_expected_shipping < 0
       or v_expected_shipping <> public.clp_round(v_expected_shipping) then
      raise exception 'Invalid shipping quote cost' using errcode = '22023';
    end if;
  end if;

  -- Hoy lo a pedido se paga entero al aceptar (plan aprobado, «100 % al
  -- aceptar»). Un abono necesitaría un segundo pago que el pedido web no tiene.
  v_settings := public.customer_quote_settings_internal(v_quote.tenant_id);
  if v_settings.on_order_prepay_percent <> 100 and exists (
    select 1 from public.customer_quote_offer_lines l
     where l.offer_id = v_offer.id and l.quantity_offered > 0 and l.availability = 'on_order'
  ) then
    raise exception 'quote_deposit_unsupported' using errcode = '0A000';
  end if;

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', 'true', true);

  insert into public.online_orders (
    tenant_id, order_number, customer_id, customer_email, customer_name, customer_phone,
    customer_address, delivery_type, shipping_address_line1, shipping_address_line2,
    shipping_city, shipping_state, shipping_postal_code, shipping_country,
    subtotal, tax_amount, shipping_cost, shipping_net_amount, shipping_tax_amount,
    shipping_tax_rate, shipping_rate_snapshot, discount_amount, total,
    status, payment_status, payment_method, customer_notes, checkout_idempotency_key
  ) values (
    v_quote.tenant_id,
    public.generate_online_order_number(v_quote.tenant_id, clock_timestamp()),
    v_quote.customer_id, v_quote.customer_email, v_quote.customer_name, v_quote.customer_phone,
    case when v_delivery = 'shipping' then concat_ws(', ', v_line1, v_line2, v_city) end,
    v_delivery,
    case when v_delivery = 'shipping' then v_line1 end,
    case when v_delivery = 'shipping' then v_line2 end,
    case when v_delivery = 'shipping' then v_city end,
    case when v_delivery = 'shipping' then v_region end,
    case when v_delivery = 'shipping' then v_postal end,
    case when v_delivery = 'pickup' then null else 'Chile' end,
    0, 0, 0, 0, 0, 0, '{}'::jsonb, 0, 0,
    'pending', 'pending', v_method, v_notes,
    'customer-quote:' || v_offer.id::text
  ) returning id into v_order_id;

  -- La cotización apunta a su pedido antes del primer evento del pedido: así
  -- el correo «recibimos tu pedido» ya sabe si el cliente eligió correo.
  update public.customer_quotes set online_order_id = v_order_id where id = v_quote.id;

  for v_line in
    select l.*
      from public.customer_quote_offer_lines l
     where l.offer_id = v_offer.id
       and l.quantity_offered > 0
       and l.availability in ('in_stock', 'on_order')
     order by l.line_no
  loop
    select * into v_product from public.products p
     where p.id = v_line.product_id and p.tenant_id = v_quote.tenant_id
     for update;
    if not found then
      raise exception 'quote_product_missing' using errcode = '55000', detail = v_line.product_name;
    end if;
    v_tax_rate := case
      when coalesce(v_line.tax_rate, v_product.tax_rate) in (0.19, 19) then 19
      when coalesce(v_line.tax_rate, v_product.tax_rate) = 0 then 0
    end;
    if v_tax_rate is null then
      raise exception 'Product % has missing or unsupported tax classification', v_line.product_name
        using errcode = '23514';
    end if;
    if v_line.unit_price is null or v_line.unit_price <= 0
       or v_line.unit_price <> public.clp_round(v_line.unit_price) then
      raise exception 'Offer line % requires a positive whole-CLP price', v_line.product_name
        using errcode = '23514';
    end if;

    -- Primero del stock: lo que está en el taller se aparta ya, aunque la
    -- oferta lo diera a pedido (llega antes). Lo prometido «en stock» que se
    -- acabó recién no se vende a pedido sin decirlo: se pide otra oferta.
    begin
      insert into public.online_order_items (
        tenant_id, order_id, product_id, product_name, product_sku, quantity,
        unit_price, subtotal, unit_cost, tax_rate, is_service, purchase_treatment,
        product_type, fulfillment, customer_quote_offer_line_id
      ) values (
        v_quote.tenant_id, v_order_id, v_product.id, v_line.product_name, v_line.product_sku,
        v_line.quantity_offered, v_line.unit_price,
        public.clp_round(v_line.unit_price * v_line.quantity_offered),
        v_product.cost, v_tax_rate,
        (coalesce(v_product.is_service, false) or v_product.product_type = 'service'),
        coalesce(v_product.purchase_treatment, 'inventory'),
        coalesce(v_product.product_type, 'product'),
        'stock', v_line.id
      );
    exception when check_violation then
      if v_line.availability = 'in_stock' then
        raise exception 'quote_stock_changed' using errcode = '40001', detail = v_line.product_name;
      end if;
      insert into public.online_order_items (
        tenant_id, order_id, product_id, product_name, product_sku, quantity,
        unit_price, subtotal, unit_cost, tax_rate, is_service, purchase_treatment,
        product_type, fulfillment, customer_quote_offer_line_id, on_order_supplier_id,
        lead_days_min, lead_days_max
      ) values (
        v_quote.tenant_id, v_order_id, v_product.id, v_line.product_name, v_line.product_sku,
        v_line.quantity_offered, v_line.unit_price,
        public.clp_round(v_line.unit_price * v_line.quantity_offered),
        coalesce(v_line.unit_cost_net, v_product.cost), v_tax_rate,
        false,
        coalesce(v_product.purchase_treatment, 'inventory'),
        coalesce(v_product.product_type, 'product'),
        'on_order', v_line.id, coalesce(v_line.supplier_id, v_product.supplier_id),
        v_line.lead_days_min, v_line.lead_days_max
      );
      v_on_order := v_on_order + 1;
    end;
  end loop;

  v_item_snapshot := public.calculate_online_order_tax_snapshot(v_order_id, v_quote.tenant_id);
  v_shipping := public.quote_online_shipping_internal(
    v_quote.tenant_id, v_delivery, (v_item_snapshot ->> 'gross_amount')::numeric, 'CL', v_region,
    -- Las líneas del pedido: cada bicicleta paga su despacho (20261121120000).
    public.online_order_shipping_lines_internal(v_order_id, v_quote.tenant_id)
  );
  v_shipping_gross := (v_shipping ->> 'shipping_gross')::numeric;
  if v_expected_shipping is null then
    if v_shipping_gross > 0 then
      raise exception 'A current shipping quote is required before checkout' using errcode = '23514';
    end if;
    v_expected_shipping := 0;
  end if;
  if v_expected_shipping <> v_shipping_gross then
    raise exception 'Shipping quote changed; refresh checkout before paying' using errcode = '40001';
  end if;

  perform pg_catalog.set_config('app.online_order_shipping_quote_in_progress', 'true', true);
  update public.online_orders
     set subtotal = (v_item_snapshot ->> 'net_amount')::numeric,
         tax_amount = (v_item_snapshot ->> 'tax_amount')::numeric,
         shipping_cost = v_shipping_gross,
         shipping_net_amount = (v_shipping ->> 'shipping_net')::numeric,
         shipping_tax_amount = (v_shipping ->> 'shipping_tax')::numeric,
         shipping_tax_rate = (v_shipping ->> 'tax_rate')::numeric,
         shipping_rate_tier_id = nullif(v_shipping ->> 'tier_id', '')::uuid,
         shipping_rate_snapshot = v_shipping,
         discount_amount = 0,
         total = (v_item_snapshot ->> 'gross_amount')::numeric + v_shipping_gross
   where id = v_order_id and tenant_id = v_quote.tenant_id;
  perform pg_catalog.set_config('app.online_order_shipping_quote_in_progress', '', true);

  select jsonb_build_object(
    'success', true, 'order_id', o.id, 'status', o.status, 'payment_status', o.payment_status,
    'version', o.version, 'invoice_id', o.sales_invoice_id, 'total', o.total,
    'shipping_cost', o.shipping_cost, 'changed', true
  ) into v_created
    from public.online_orders o where o.id = v_order_id;

  insert into public.online_order_events (
    tenant_id, order_id, event_type, from_status, to_status, from_payment_status,
    to_payment_status, changed, expected_version, result_version, actor_id,
    operation_key, request_snapshot, response_snapshot
  )
  select o.tenant_id, o.id, 'order_created', null, o.status, null, o.payment_status,
         true, null, o.version, auth.uid(),
         'customer-quote-created:' || o.id::text,
         jsonb_build_object(
           'source', 'customer_quote',
           'quote_id', v_quote.id,
           'quote_number', v_quote.quote_number,
           'offer_id', v_offer.id,
           'delivery_type', o.delivery_type,
           'payment_method', o.payment_method,
           'on_order_lines', v_on_order,
           'tax_source', 'customer_quote_offer',
           'shipping_quote', o.shipping_rate_snapshot,
           'accepted_shipping_cost', v_expected_shipping
         ),
         v_created
    from public.online_orders o where o.id = v_order_id;

  perform public.capture_online_order_storefront_snapshot(v_order_id, v_quote.tenant_id);

  update public.customer_quote_offers
     set status = 'accepted', responded_at = clock_timestamp()
   where id = v_offer.id;
  update public.customer_quotes
     set status = 'accepted', accepted_at = clock_timestamp(), online_order_id = v_order_id,
         updated_at = clock_timestamp(), version = version + 1
   where id = v_quote.id;
  perform public.customer_quote_log_internal(
    v_quote.id, 'accepted', 'customer', null, 'web', v_offer.id, v_key,
    jsonb_build_object(
      'total', v_offer.total, 'order_id', v_order_id,
      'order_number', (select order_number from public.online_orders where id = v_order_id),
      'delivery_type', v_delivery, 'payment_method', v_method, 'on_order_lines', v_on_order
    )
  );
  perform public.customer_quote_notify_internal(
    v_quote.id, 'customer_quote_accepted', 'Cotización aceptada', 'customer_quote_offer', v_offer.id, 'success'
  );

  perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);

  -- Una transferencia con todo en stock sigue el camino de cualquier pedido:
  -- su venta nace al tiro y se paga al confirmar. Con algo a pedido, la
  -- venta espera a que llegue.
  if v_method = 'transfer' and v_on_order = 0 then
    perform public.process_public_checkout_order(v_order_id, v_quote.tenant_id);
  end if;

  v_access_token := public.issue_online_order_access_token(
    v_order_id, array['view_order']::text[], clock_timestamp() + interval '30 days'
  );
  return public.customer_quote_order_receipt_internal(v_order_id, v_access_token, false);
exception
  when others then
    perform pg_catalog.set_config('app.online_order_shipping_quote_in_progress', '', true);
    perform pg_catalog.set_config('app.public_order_rpc_in_progress', '', true);
    raise;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. La oferta que ve el cliente dice qué producto es cada línea, para que su
--    página cotice el despacho con sus líneas (lectura de producción del
--    2026-11-21; sólo se agrega `productId`).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.customer_quote_public_projection_internal(p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with q as (
    select * from public.customer_quotes where id = p_quote_id
  ), offer as (
    select o.* from public.customer_quote_offers o, q
     where o.id = q.current_offer_id
  )
  select jsonb_build_object(
    'quote', (select jsonb_strip_nulls(jsonb_build_object(
      'number', q.quote_number,
      'status', q.status,
      'customerName', q.customer_name,
      'notifyEmail', q.notify_email,
      'notifyWhatsapp', q.notify_whatsapp,
      -- Sólo si la cuenta tiene cada dato, nunca el dato: el enlace se puede
      -- reenviar.
      'canEmail', q.customer_email is not null,
      'canWhatsapp', q.customer_phone is not null,
      'requestedAt', q.requested_at,
      'offeredAt', q.offered_at,
      'expiresAt', q.expires_at,
      'acceptedAt', q.accepted_at,
      'rejectedAt', q.rejected_at,
      'expiredAt', q.expired_at,
      'cancelledAt', q.cancelled_at
    )) from q),
    -- El membrete del PDF y dónde se acepta: lo que la tienda ya publica.
    'storefront', (select public.storefront_identity_internal(q.tenant_id)
                          || jsonb_strip_nulls(jsonb_build_object('storeUrl', (
                               select nullif(btrim(s.value), '')
                                 from public.website_settings s
                                where s.tenant_id = q.tenant_id and s.key = 'store_url'
                             )))
                     from q),
    'requested', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lineNo', l.line_no, 'name', l.product_name, 'sku', l.product_sku,
        'quantity', l.quantity, 'kind', l.kind_at_request
      ) order by l.line_no)
        from public.customer_quote_lines l where l.quote_id = p_quote_id
    ), '[]'::jsonb),
    'offer', (select jsonb_strip_nulls(jsonb_build_object(
      'id', offer.id,
      'number', offer.offer_no,
      'status', offer.status,
      'sentAt', offer.sent_at,
      'validUntil', offer.valid_until,
      'subtotal', offer.subtotal,
      'taxAmount', offer.tax_amount,
      'total', offer.total,
      'notes', offer.notes_to_customer,
      'lines', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'id', ol.id, 'lineNo', ol.line_no, 'productId', ol.product_id, 'name', ol.product_name, 'sku', ol.product_sku,
          'quantityRequested', ol.quantity_requested, 'quantity', ol.quantity_offered,
          'availability', ol.availability, 'unitPrice', ol.unit_price,
          'lineTotal', case when ol.quantity_offered > 0 then ol.unit_price * ol.quantity_offered end,
          'leadDaysMin', ol.lead_days_min, 'leadDaysMax', ol.lead_days_max,
          'note', ol.customer_note
        )) order by ol.line_no)
          from public.customer_quote_offer_lines ol where ol.offer_id = offer.id
      ), '[]'::jsonb)
    )) from offer where offer.status <> 'draft'),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('type', e.event_type, 'at', e.occurred_at) order by e.id)
        from public.customer_quote_events e
       where e.quote_id = p_quote_id
         and e.event_type in (
           'requested', 'offer_sent', 'accepted', 'changes_requested', 'rejected', 'expired', 'cancelled',
           'order_paid', 'order_sale_issued', 'order_ready', 'order_shipped', 'order_delivered', 'order_cancelled',
           'order_refunded'
         )
    ), '[]'::jsonb),
    -- El pedido que nació al aceptar: estado, entrega y qué viene a pedido.
    -- Sin su acceso: la página lo pide con el enlace (20261103010000).
    'order', (select jsonb_strip_nulls(jsonb_build_object(
      'number', o.order_number,
      'status', o.status,
      'paymentStatus', o.payment_status,
      'paymentMethod', o.payment_method,
      'deliveryType', o.delivery_type,
      'productsTotal', o.subtotal + o.tax_amount,
      'shippingCost', o.shipping_cost,
      'total', o.total,
      'waiting', public.customer_quote_order_waiting_internal(o.id),
      'readyForPickupAt', o.ready_for_pickup_at,
      'shippedAt', o.shipped_at,
      'deliveredAt', o.delivered_at,
      'cancelledAt', o.cancelled_at,
      'trackingCarrier', o.shipping_carrier,
      'trackingNumber', o.tracking_number,
      'lines', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'name', i.product_name,
          'quantity', i.quantity,
          'onOrder', i.fulfillment = 'on_order',
          'arrived', case when i.fulfillment = 'on_order' then i.arrived_at is not null end,
          'leadDaysMin', i.lead_days_min,
          'leadDaysMax', i.lead_days_max
        )) order by i.created_at, i.id)
          from public.online_order_items i
         where i.order_id = o.id
      ), '[]'::jsonb)
    ))
      from public.online_orders o, q
     where o.id = q.online_order_id and o.tenant_id = q.tenant_id)
  );
$function$;

notify pgrst, 'reload schema';

commit;
