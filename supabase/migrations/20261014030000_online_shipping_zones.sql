-- Despacho por zona: el costo se calcula con la región de destino.
--
-- 2026-10-14, el dueño: «revisa cómo lo hacen todos nuestros competidores más
-- importantes y haz lo mismo». Oxford, Cycling Store, Tienda Ride y Padrobikes
-- (Viña) cobran el despacho en el checkout, calculado por destino y tamaño;
-- «por pagar» es la excepción (Bikeventura, Quilpué). El catálogo no tiene
-- pesos (0 de 1.463 productos web), así que el tamaño sigue siendo el tramo
-- de subtotal y se agrega el destino: zonas de regiones, cada una con sus
-- tramos.
--
--   · `online_shipping_zones`: zonas con sus regiones (código ISO 3166-2:CL);
--     una región está en una sola zona activa por taller.
--   · Cada tramo pertenece a una zona. Los tramos que ya existían quedan en la
--     zona «Todo Chile» (las 16 regiones): nada cambia hasta configurar zonas.
--   · `quote_online_shipping_internal` y `quote_public_online_shipping`
--     reciben `p_region` (el texto que da el checkout); con una sola zona la
--     región puede faltar (los navegadores con el checkout anterior siguen
--     funcionando).
--   · `create_public_online_order_unkeyed` cotiza con `shipping_state`.
--   · `get_public_online_shipping_tiers` dice la zona de cada tramo.
--   · `online_shipping_zones_for_editor` y `save_online_shipping_zones`: lo
--     que lee y guarda la pantalla «Envíos» del editor del sitio.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. Las regiones de Chile, de norte a sur.
-- ---------------------------------------------------------------------------
create or replace function public.online_shipping_region_codes()
returns text[]
language sql
immutable
set search_path = public, pg_temp
as $function$
  select array[
    'CL-AP', 'CL-TA', 'CL-AN', 'CL-AT', 'CL-CO', 'CL-VS', 'CL-RM', 'CL-LI',
    'CL-ML', 'CL-NB', 'CL-BI', 'CL-AR', 'CL-LR', 'CL-LL', 'CL-AI', 'CL-MA'
  ]::text[];
$function$;

create or replace function public.online_shipping_region_name(p_code text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $function$
  select case upper(btrim(coalesce(p_code, '')))
    when 'CL-AP' then 'Arica y Parinacota'
    when 'CL-TA' then 'Tarapacá'
    when 'CL-AN' then 'Antofagasta'
    when 'CL-AT' then 'Atacama'
    when 'CL-CO' then 'Coquimbo'
    when 'CL-VS' then 'Valparaíso'
    when 'CL-RM' then 'Metropolitana'
    when 'CL-LI' then 'O''Higgins'
    when 'CL-ML' then 'Maule'
    when 'CL-NB' then 'Ñuble'
    when 'CL-BI' then 'Biobío'
    when 'CL-AR' then 'La Araucanía'
    when 'CL-LR' then 'Los Ríos'
    when 'CL-LL' then 'Los Lagos'
    when 'CL-AI' then 'Aysén'
    when 'CL-MA' then 'Magallanes'
  end;
$function$;

-- El texto de región que llega del checkout (Google, una dirección guardada
-- o escrito a mano) como código: «Región de Valparaíso», «Valparaíso»,
-- «V Región», «RM», «CL-RM»… Null si no es una región de Chile.
create or replace function public.online_shipping_region_code(p_region text)
returns text
language plpgsql
immutable
set search_path = public, pg_temp
as $function$
declare
  v_text text := btrim(regexp_replace(
    regexp_replace(
      lower(translate(coalesce(p_region, ''), 'ÁÉÍÓÚÜÑáéíóúüñ', 'AEIOUUNaeiouun')),
      '[^a-z0-9]+', ' ', 'g'
    ),
    '\s+', ' ', 'g'
  ));
  v_short text;
begin
  if v_text = '' then
    return null;
  end if;
  if v_text ~ '^(cl )?(ap|ta|an|at|co|vs|rm|li|ml|nb|bi|ar|lr|ll|ai|ma)$' then
    return 'CL-' || upper(substring(v_text from '([a-z]{2})$'));
  end if;
  if v_text ~ 'arica|parinacota' then return 'CL-AP'; end if;
  if v_text ~ 'tarapaca' then return 'CL-TA'; end if;
  if v_text ~ 'antofagasta' then return 'CL-AN'; end if;
  if v_text ~ 'atacama' then return 'CL-AT'; end if;
  if v_text ~ 'coquimbo' then return 'CL-CO'; end if;
  if v_text ~ 'valparaiso' then return 'CL-VS'; end if;
  if v_text ~ 'metropolitana|santiago' then return 'CL-RM'; end if;
  if v_text ~ 'higgins|libertador' then return 'CL-LI'; end if;
  if v_text ~ 'maule' then return 'CL-ML'; end if;
  if v_text ~ 'nuble' then return 'CL-NB'; end if;
  if v_text ~ 'bio ?bio' then return 'CL-BI'; end if;
  if v_text ~ 'araucania' then return 'CL-AR'; end if;
  if v_text ~ 'los rios' then return 'CL-LR'; end if;
  if v_text ~ 'los lagos' then return 'CL-LL'; end if;
  if v_text ~ 'aysen|aisen|ibanez' then return 'CL-AI'; end if;
  if v_text ~ 'magallanes|antartica' then return 'CL-MA'; end if;

  -- «V Región», «Región V», «5ª región», «XIII».
  v_short := btrim(regexp_replace(v_text, '\m(region|regiones|de|del|la|a)\M', ' ', 'g'));
  v_short := btrim(regexp_replace(v_short, '\s+', ' ', 'g'));
  return case v_short
    when 'xv' then 'CL-AP' when '15' then 'CL-AP'
    when 'i' then 'CL-TA' when '1' then 'CL-TA'
    when 'ii' then 'CL-AN' when '2' then 'CL-AN'
    when 'iii' then 'CL-AT' when '3' then 'CL-AT'
    when 'iv' then 'CL-CO' when '4' then 'CL-CO'
    when 'v' then 'CL-VS' when '5' then 'CL-VS'
    when 'xiii' then 'CL-RM' when '13' then 'CL-RM'
    when 'vi' then 'CL-LI' when '6' then 'CL-LI'
    when 'vii' then 'CL-ML' when '7' then 'CL-ML'
    when 'xvi' then 'CL-NB' when '16' then 'CL-NB'
    when 'viii' then 'CL-BI' when '8' then 'CL-BI'
    when 'ix' then 'CL-AR' when '9' then 'CL-AR'
    when 'xiv' then 'CL-LR' when '14' then 'CL-LR'
    when 'x' then 'CL-LL' when '10' then 'CL-LL'
    when 'xi' then 'CL-AI' when '11' then 'CL-AI'
    when 'xii' then 'CL-MA' when '12' then 'CL-MA'
  end;
end;
$function$;

grant execute on function public.online_shipping_region_codes() to anon, authenticated;
grant execute on function public.online_shipping_region_name(text) to anon, authenticated;
grant execute on function public.online_shipping_region_code(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Las zonas.
-- ---------------------------------------------------------------------------
create table if not exists public.online_shipping_zones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null check (btrim(name) <> '' and char_length(name) <= 60),
  region_codes text[] not null default '{}'::text[]
    check (region_codes <@ public.online_shipping_region_codes()),
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists online_shipping_zones_tenant_idx
  on public.online_shipping_zones (tenant_id, is_active, sort_order);

comment on table public.online_shipping_zones is
  'Shipping zones of the online store: a name and the Chilean regions (ISO 3166-2:CL) it covers. Each rate tier belongs to one zone; the checkout quote picks the zone of the destination region. Written by save_online_shipping_zones (the site editor''s «Envíos»).';

alter table public.online_shipping_zones enable row level security;
revoke all on public.online_shipping_zones from anon;
revoke insert, update, delete on public.online_shipping_zones from authenticated;
grant select on public.online_shipping_zones to authenticated;

drop policy if exists online_shipping_zones_staff_read on public.online_shipping_zones;
create policy online_shipping_zones_staff_read
  on public.online_shipping_zones
  for select to authenticated
  using (tenant_id = (select public.user_tenant_id()));

create or replace function public.prevent_overlapping_online_shipping_zones()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_taken text;
begin
  new.region_codes := array(
    select distinct upper(btrim(code)) from unnest(new.region_codes) code
     order by 1
  );
  new.name := btrim(new.name);
  new.updated_at := clock_timestamp();
  if new.is_active then
    select string_agg(public.online_shipping_region_name(code), ', ' order by code)
      into v_taken
      from public.online_shipping_zones zone
      cross join lateral unnest(zone.region_codes) code
     where zone.tenant_id = new.tenant_id
       and zone.is_active
       and zone.id <> new.id
       and code = any(new.region_codes);
    if v_taken is not null then
      raise exception 'Una región no puede estar en dos zonas: %.', v_taken
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_online_shipping_zones_no_overlap on public.online_shipping_zones;
create trigger trg_online_shipping_zones_no_overlap
  before insert or update on public.online_shipping_zones
  for each row execute function public.prevent_overlapping_online_shipping_zones();

-- ---------------------------------------------------------------------------
-- 3. Cada tramo pertenece a una zona; los de hoy, a «Todo Chile».
-- ---------------------------------------------------------------------------
alter table public.online_shipping_rate_tiers
  add column if not exists zone_id uuid references public.online_shipping_zones(id) on delete restrict;

insert into public.online_shipping_zones (tenant_id, name, region_codes, sort_order)
select distinct tier.tenant_id, 'Todo Chile', public.online_shipping_region_codes(), 0
  from public.online_shipping_rate_tiers tier
 where tier.zone_id is null
   and not exists (
     select 1 from public.online_shipping_zones zone
      where zone.tenant_id = tier.tenant_id
   );

update public.online_shipping_rate_tiers tier
   set zone_id = (
     select zone.id from public.online_shipping_zones zone
      where zone.tenant_id = tier.tenant_id
      order by zone.sort_order, zone.created_at
      limit 1
   )
 where tier.zone_id is null;

-- Un tramo creado sin zona (semillas y pruebas anteriores) cae en la primera
-- zona del taller, o en una «Todo Chile» nueva si no tiene ninguna.
create or replace function public.assign_online_shipping_tier_zone()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if new.zone_id is null then
    select zone.id into new.zone_id
      from public.online_shipping_zones zone
     where zone.tenant_id = new.tenant_id
       and zone.is_active
     order by zone.sort_order, zone.created_at
     limit 1;
    if new.zone_id is null then
      insert into public.online_shipping_zones (tenant_id, name, region_codes)
      values (new.tenant_id, 'Todo Chile', public.online_shipping_region_codes())
      returning id into new.zone_id;
    end if;
  elsif not exists (
    select 1 from public.online_shipping_zones zone
     where zone.id = new.zone_id and zone.tenant_id = new.tenant_id
  ) then
    raise exception 'The shipping zone belongs to another tenant' using errcode = '42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_online_shipping_rate_tiers_assign_zone on public.online_shipping_rate_tiers;
create trigger trg_online_shipping_rate_tiers_assign_zone
  before insert or update on public.online_shipping_rate_tiers
  for each row execute function public.assign_online_shipping_tier_zone();

alter table public.online_shipping_rate_tiers alter column zone_id set not null;

alter table public.online_shipping_rate_tiers
  drop constraint if exists online_shipping_rate_tiers_tenant_id_country_code_min_order_key;
create unique index if not exists online_shipping_rate_tiers_active_band_key
  on public.online_shipping_rate_tiers (tenant_id, country_code, zone_id, min_order_gross)
  where is_active;

create or replace function public.prevent_overlapping_online_shipping_tiers()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  new.country_code := upper(btrim(new.country_code));
  new.updated_at := clock_timestamp();

  if new.is_active and exists (
    select 1
      from public.online_shipping_rate_tiers tier
     where tier.tenant_id = new.tenant_id
       and tier.country_code = new.country_code
       and tier.zone_id = new.zone_id
       and tier.is_active
       and tier.id <> new.id
       and numrange(tier.min_order_gross, tier.max_order_gross, '[)')
           && numrange(new.min_order_gross, new.max_order_gross, '[)')
  ) then
    raise exception 'Active online shipping rate tiers may not overlap'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 4. Cotizar con la región de destino.
-- ---------------------------------------------------------------------------
drop function if exists public.quote_public_online_shipping(uuid, text, numeric, text);
drop function if exists public.quote_online_shipping_internal(uuid, text, numeric, text);

create or replace function public.quote_online_shipping_internal(
  p_tenant_id uuid,
  p_delivery_type text,
  p_item_gross numeric,
  p_country_code text default 'CL',
  p_region text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
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
  v_match_count integer;
  v_net numeric(12,2);
  v_tax numeric(12,2);
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

  if v_tier.tax_rate = 19 then
    v_net := public.clp_round(v_tier.shipping_gross / 1.19);
    v_tax := v_tier.shipping_gross - v_net;
  else
    v_net := v_tier.shipping_gross;
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
    'shipping_gross', v_tier.shipping_gross,
    'shipping_net', v_net,
    'shipping_tax', v_tax,
    'tax_rate', v_tier.tax_rate,
    'estimated_min_business_days', v_tier.estimated_min_business_days,
    'estimated_max_business_days', v_tier.estimated_max_business_days,
    'quoted_at', clock_timestamp()
  );
end;
$function$;

revoke all on function public.quote_online_shipping_internal(uuid, text, numeric, text, text)
  from public, anon, authenticated;
grant execute on function public.quote_online_shipping_internal(uuid, text, numeric, text, text)
  to service_role;

create or replace function public.quote_public_online_shipping(
  p_tenant_id uuid,
  p_delivery_type text,
  p_item_gross numeric,
  p_country_code text default 'CL',
  p_region text default null
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
    p_region
  );
end;
$function$;

revoke all on function public.quote_public_online_shipping(uuid, text, numeric, text, text) from public;
grant execute on function public.quote_public_online_shipping(uuid, text, numeric, text, text)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. El pedido cotiza con su región (la función viva, sólo cambia la cotización).
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
        if coalesce(v_product.stock_quantity, v_product.inventory_qty, 0)
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
      product_type
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
      coalesce(v_product.product_type, 'product')
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
    nullif(btrim(coalesce(p_order_data->>'shipping_state', '')), '')
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

-- ---------------------------------------------------------------------------
-- 6. Lo que publica la tienda: cada tramo con su zona y sus regiones.
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
  region_codes text[]
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select tier.country_code,
         tier.min_order_gross,
         tier.max_order_gross,
         tier.shipping_gross,
         tier.estimated_min_business_days,
         tier.estimated_max_business_days,
         zone.name,
         zone.sort_order,
         zone.region_codes
    from public.online_shipping_rate_tiers tier
    join public.online_shipping_zones zone
      on zone.id = tier.zone_id
     and zone.tenant_id = tier.tenant_id
     and zone.is_active
   where tier.tenant_id = p_tenant_id
     and tier.is_active
   order by zone.sort_order, zone.created_at, tier.country_code, tier.min_order_gross;
$function$;

revoke all on function public.get_public_online_shipping_tiers(uuid) from public;
grant execute on function public.get_public_online_shipping_tiers(uuid)
  to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. La pantalla «Envíos» del editor: leer y guardar las zonas.
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
-- no tiene tope.
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

    insert into public.online_shipping_zones (tenant_id, name, region_codes, sort_order)
    values (v_tenant_id, v_name, v_codes, v_zone_index)
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
  'The site editor''s «Envíos»: replaces the tenant''s active shipping zones and their tiers in one transaction. Previous rows stay inactive (orders keep the tier they were charged with).';

revoke all on function public.save_online_shipping_zones(jsonb) from public, anon, authenticated;
grant execute on function public.save_online_shipping_zones(jsonb) to authenticated;

notify pgrst, 'reload schema';

commit;
