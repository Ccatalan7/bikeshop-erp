-- Align the public checkout, accounting snapshot, legal pages and Google
-- Merchant configuration around one truthful shipping contract.
--
-- Public product prices are gross CLP. Shipping is also a gross, IVA-included
-- service. The browser may preview a quote, but the database re-derives it
-- from the immutable item snapshot and rejects a stale client quote.

begin;

create table if not exists public.online_shipping_rate_tiers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  country_code text not null default 'CL'
    check (country_code = upper(country_code) and length(country_code) = 2),
  min_order_gross numeric(12,2) not null,
  max_order_gross numeric(12,2),
  shipping_gross numeric(12,2) not null,
  tax_rate numeric(5,2) not null default 19,
  estimated_min_business_days integer not null default 3,
  estimated_max_business_days integer not null default 12,
  is_active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check (min_order_gross >= 0 and min_order_gross = public.clp_round(min_order_gross)),
  check (
    max_order_gross is null
    or (
      max_order_gross > min_order_gross
      and max_order_gross = public.clp_round(max_order_gross)
    )
  ),
  check (shipping_gross >= 0 and shipping_gross = public.clp_round(shipping_gross)),
  check (tax_rate in (0, 19)),
  check (
    estimated_min_business_days >= 0
    and estimated_max_business_days >= estimated_min_business_days
    and estimated_max_business_days <= 60
  ),
  unique (tenant_id, country_code, min_order_gross)
);

comment on table public.online_shipping_rate_tiers is
  'Tenant-scoped gross-CLP shipping tariff. Active ranges are half-open [min,max), non-overlapping, and quoted server-side before checkout.';

create index if not exists idx_online_shipping_rate_tiers_lookup
  on public.online_shipping_rate_tiers(
    tenant_id, country_code, is_active, min_order_gross
  );

create or replace function public.prevent_overlapping_online_shipping_tiers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.country_code := upper(btrim(new.country_code));
  new.updated_at := clock_timestamp();

  if new.is_active and exists (
    select 1
      from public.online_shipping_rate_tiers tier
     where tier.tenant_id = new.tenant_id
       and tier.country_code = new.country_code
       and tier.is_active
       and tier.id <> new.id
       -- Let an idempotent INSERT ... ON CONFLICT on the range's natural key
       -- reach its DO UPDATE arm. Any plain duplicate still fails on the
       -- unique constraint after this trigger.
       and not (
         tg_op = 'INSERT'
         and tier.min_order_gross = new.min_order_gross
       )
       and numrange(
         tier.min_order_gross,
         tier.max_order_gross,
         '[)'
       ) && numrange(
         new.min_order_gross,
         new.max_order_gross,
         '[)'
       )
  ) then
    raise exception 'Active online shipping rate tiers may not overlap'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

revoke all on function public.prevent_overlapping_online_shipping_tiers()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_online_shipping_rate_tiers_no_overlap
  on public.online_shipping_rate_tiers;
create trigger trg_online_shipping_rate_tiers_no_overlap
  before insert or update on public.online_shipping_rate_tiers
  for each row execute function public.prevent_overlapping_online_shipping_tiers();

alter table public.online_shipping_rate_tiers enable row level security;

drop policy if exists online_shipping_rate_tiers_staff_read
  on public.online_shipping_rate_tiers;
create policy online_shipping_rate_tiers_staff_read
  on public.online_shipping_rate_tiers
  for select to authenticated
  using (tenant_id = public.user_tenant_id());

drop policy if exists online_shipping_rate_tiers_staff_write
  on public.online_shipping_rate_tiers;
create policy online_shipping_rate_tiers_staff_write
  on public.online_shipping_rate_tiers
  for all to authenticated
  using (tenant_id = public.user_tenant_id())
  with check (tenant_id = public.user_tenant_id());

revoke all on public.online_shipping_rate_tiers
  from public, anon, authenticated, service_role;
grant select, insert, update, delete on public.online_shipping_rate_tiers
  to authenticated;

alter table public.online_orders
  add column if not exists shipping_net_amount numeric(12,2) not null default 0,
  add column if not exists shipping_tax_amount numeric(12,2) not null default 0,
  add column if not exists shipping_tax_rate numeric(5,2) not null default 0,
  add column if not exists shipping_rate_tier_id uuid,
  add column if not exists shipping_rate_snapshot jsonb not null default '{}'::jsonb;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.online_orders'::regclass
       and conname = 'online_orders_shipping_rate_tier_fkey'
  ) then
    alter table public.online_orders
      add constraint online_orders_shipping_rate_tier_fkey
      foreign key (shipping_rate_tier_id)
      references public.online_shipping_rate_tiers(id)
      on delete restrict;
  end if;
end;
$$;

alter table public.online_orders
  drop constraint if exists online_orders_shipping_money_check,
  add constraint online_orders_shipping_money_check check (
    shipping_cost = public.clp_round(shipping_cost)
    and shipping_net_amount = public.clp_round(shipping_net_amount)
    and shipping_tax_amount = public.clp_round(shipping_tax_amount)
    and shipping_cost >= 0
    and shipping_net_amount >= 0
    and shipping_tax_amount >= 0
    and shipping_cost = shipping_net_amount + shipping_tax_amount
    and shipping_tax_rate in (0, 19)
    and jsonb_typeof(shipping_rate_snapshot) = 'object'
    and (
      (shipping_cost = 0 and shipping_net_amount = 0 and shipping_tax_amount = 0)
      or (
        delivery_type = 'shipping'
        and shipping_cost > 0
        and shipping_tax_rate = 19
        and shipping_rate_tier_id is not null
        and shipping_rate_snapshot <> '{}'::jsonb
      )
    )
  );

comment on column public.online_orders.shipping_cost is
  'Immutable gross CLP shipping charge accepted by the customer before order creation.';
comment on column public.online_orders.shipping_net_amount is
  'Immutable net portion of shipping_cost used by invoice/accounting.';
comment on column public.online_orders.shipping_tax_amount is
  'Immutable IVA portion of shipping_cost used by invoice/accounting.';
comment on column public.online_orders.shipping_rate_snapshot is
  'Immutable quote evidence: tier, range, country, tax and promised delivery window.';

create or replace function public.quote_online_shipping_internal(
  p_tenant_id uuid,
  p_delivery_type text,
  p_item_gross numeric,
  p_country_code text default 'CL'
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_delivery_type text := lower(btrim(coalesce(p_delivery_type, 'shipping')));
  v_country text := upper(btrim(coalesce(p_country_code, 'CL')));
  v_item_gross numeric(12,2);
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

  select count(*)
    into v_match_count
    from public.online_shipping_rate_tiers tier
   where tier.tenant_id = p_tenant_id
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
$$;

revoke all on function public.quote_online_shipping_internal(uuid, text, numeric, text)
  from public, anon, authenticated, service_role;

create or replace function public.quote_public_online_shipping(
  p_tenant_id uuid,
  p_delivery_type text,
  p_item_gross numeric,
  p_country_code text default 'CL'
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if not exists (
    select 1 from public.tenants tenant where tenant.id = p_tenant_id
  ) then
    raise exception 'Invalid tenant_id' using errcode = '22023';
  end if;

  return public.quote_online_shipping_internal(
    p_tenant_id,
    p_delivery_type,
    p_item_gross,
    p_country_code
  );
end;
$$;

comment on function public.quote_public_online_shipping(uuid, text, numeric, text) is
  'Narrow public shipping quote. The browser preview is advisory; checkout re-derives the quote from authoritative product prices and rejects stale cost consent.';

revoke all on function public.quote_public_online_shipping(uuid, text, numeric, text)
  from public, anon, authenticated, service_role;
grant execute on function public.quote_public_online_shipping(uuid, text, numeric, text)
  to anon, authenticated, service_role;

create or replace function public.prevent_online_order_shipping_snapshot_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.shipping_cost is distinct from new.shipping_cost
     or old.shipping_net_amount is distinct from new.shipping_net_amount
     or old.shipping_tax_amount is distinct from new.shipping_tax_amount
     or old.shipping_tax_rate is distinct from new.shipping_tax_rate
     or old.shipping_rate_tier_id is distinct from new.shipping_rate_tier_id
     or old.shipping_rate_snapshot is distinct from new.shipping_rate_snapshot then
    if coalesce(
      current_setting('app.online_order_shipping_quote_in_progress', true),
      ''
    ) <> 'true' then
      raise exception 'Online order shipping quote is immutable'
        using errcode = '55000';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.prevent_online_order_shipping_snapshot_mutation()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_online_order_shipping_snapshot_immutable
  on public.online_orders;
create trigger trg_online_order_shipping_snapshot_immutable
  before update on public.online_orders
  for each row execute function public.prevent_online_order_shipping_snapshot_mutation();

-- Existing Merchant Center values become the single price-based tariff. The
-- former weight dimension could not be evaluated because published catalog
-- weights are absent; these bands preserve the already-configured <=5 kg
-- amounts without fabricating product weights.
insert into public.online_shipping_rate_tiers (
  tenant_id, country_code, min_order_gross, max_order_gross,
  shipping_gross, tax_rate,
  estimated_min_business_days, estimated_max_business_days
)
select seed.tenant_id, seed.country_code, seed.min_order_gross,
       seed.max_order_gross, seed.shipping_gross, seed.tax_rate,
       seed.estimated_min_business_days, seed.estimated_max_business_days
  from (values
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'CL', 0::numeric, 30000::numeric, 6990::numeric, 19::numeric, 3, 12),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'CL', 30000::numeric, 80000::numeric, 8990::numeric, 19::numeric, 3, 12),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'CL', 80000::numeric, 150000::numeric, 11990::numeric, 19::numeric, 3, 12),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'CL', 150000::numeric, null::numeric, 14990::numeric, 19::numeric, 3, 12)
  ) as seed(
    tenant_id, country_code, min_order_gross, max_order_gross,
    shipping_gross, tax_rate,
    estimated_min_business_days, estimated_max_business_days
  )
 where exists (
   select 1 from public.tenants tenant where tenant.id = seed.tenant_id
 )
on conflict (tenant_id, country_code, min_order_gross) do update
set max_order_gross = excluded.max_order_gross,
    shipping_gross = excluded.shipping_gross,
    tax_rate = excluded.tax_rate,
    estimated_min_business_days = excluded.estimated_min_business_days,
    estimated_max_business_days = excluded.estimated_max_business_days,
    is_active = true,
    updated_at = clock_timestamp();

-- Canonical public business identity. Keep the customer-facing and sales
-- addresses distinct while eliminating the legacy Gmail identity mismatch.
update public.companies
   set name = 'Viñabike',
       legal_name = 'NEWEN SpA',
       fantasy_name = 'Viñabike',
       tax_id = '77.541.999-7',
       rut = '77.541.999-7',
       business_activity = 'Venta al por menor de bicicletas y sus repuestos en comercios especializados',
       address = 'Alvarez 32, Local 17',
       comuna = 'Viña del Mar',
       city = 'Viña del Mar',
       region = 'Valparaíso',
       postal_code = '2520000',
       country = 'Chile',
       phone = '+56 9 9835 7797',
       whatsapp_phone = '+56 9 9835 7797',
       email = 'contacto@vinabike.cl',
       public_email = 'contacto@vinabike.cl',
       billing_email = 'ventas@vinabike.cl',
       website_url = 'https://vinabike.cl',
       updated_at = clock_timestamp()
 where tenant_id = '5443b130-cc28-45af-a420-cd500b288890';

insert into public.website_settings (tenant_id, key, value, description)
select seed.tenant_id, seed.key, seed.value, seed.description
  from (values
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'legal_business_name', 'NEWEN SpA', 'Razón social pública del proveedor'),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'legal_tax_id', '77.541.999-7', 'RUT público del proveedor'),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'legal_address', 'Alvarez 32, Local 17, Viña del Mar, Valparaíso, Chile', 'Domicilio público del proveedor'),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'sales_email', 'ventas@vinabike.cl', 'Contacto transaccional de ventas'),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'seo_terms_url', '/terminos', 'Términos públicos'),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'seo_privacy_policy_url', '/privacidad', 'Política de privacidad pública'),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'seo_refund_policy_url', '/devoluciones', 'Política de devoluciones pública'),
    ('5443b130-cc28-45af-a420-cd500b288890'::uuid, 'seo_shipping_policy_url', '/envios', 'Política de despacho pública')
  ) as seed(tenant_id, key, value, description)
 where exists (
   select 1 from public.tenants tenant where tenant.id = seed.tenant_id
 )
on conflict (tenant_id, key) do update
set value = excluded.value,
    description = excluded.description,
    updated_at = clock_timestamp();

update public.website_pages
   set meta_title = case slug
         when 'terminos' then 'Términos y condiciones | Viñabike'
         when 'privacidad' then 'Política de privacidad | Viñabike'
         when 'devoluciones' then 'Cambios, devoluciones y garantía | Viñabike'
         when 'envios' then 'Despachos y retiro en tienda | Viñabike'
         when 'nosotros' then 'Viñabike | Tienda y taller en Viña del Mar'
         else meta_title
       end,
       meta_description = case slug
         when 'terminos' then 'Identidad del proveedor, compra, pago, stock y condiciones de la tienda online Viñabike.'
         when 'privacidad' then 'Responsable, finalidades, proveedores y derechos sobre los datos personales tratados por Viñabike.'
         when 'devoluciones' then 'Plazos, condiciones, costos, garantía legal y proceso de reembolso de compras en Viñabike.'
         when 'envios' then 'Tarifas, plazos de despacho, seguimiento y retiro en tienda de los pedidos Viñabike.'
         when 'nosotros' then 'Identidad, ubicación y canales oficiales de Viñabike y NEWEN SpA en Viña del Mar.'
         else meta_description
       end,
       updated_at = clock_timestamp()
 where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and slug in ('terminos', 'privacidad', 'devoluciones', 'envios', 'nosotros');

update public.website_blocks block
   set block_data = jsonb_set(
         jsonb_set(block.block_data, '{title}', to_jsonb('Identidad del proveedor'::text), true),
         '{content}',
         to_jsonb('Viñabike es el nombre comercial de NEWEN SpA, RUT 77.541.999-7. Somos una tienda y taller de bicicletas establecidos en Alvarez 32, Local 17, Viña del Mar, Región de Valparaíso, Chile. Atendemos consultas generales en contacto@vinabike.cl, ventas online en ventas@vinabike.cl y por teléfono o WhatsApp en +56 9 9835 7797.\n\nEn https://vinabike.cl vendemos bicicletas, repuestos y accesorios, y coordinamos servicios de mantención y reparación. Mostramos precio, disponibilidad, despacho y condiciones antes de confirmar cada pedido.'::text),
         true
       ),
       updated_at = clock_timestamp()
  from public.website_pages page
 where block.page_id = page.id
   and block.tenant_id = page.tenant_id
   and page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and page.slug = 'nosotros'
   and block.block_type = 'about';

update public.website_blocks block
   set block_data = jsonb_set(
         jsonb_set(block.block_data, '{title}', to_jsonb('Proveedor y alcance del contrato'::text), true),
         '{content}',
         to_jsonb('Este sitio es operado por NEWEN SpA, RUT 77.541.999-7, bajo el nombre comercial Viñabike, con domicilio en Alvarez 32, Local 17, Viña del Mar, Región de Valparaíso, Chile. Contacto general: contacto@vinabike.cl. Ventas online: ventas@vinabike.cl. Teléfono y WhatsApp: +56 9 9835 7797.\n\nLos precios se expresan en pesos chilenos e incluyen los impuestos informados. Antes de enviar el pedido mostramos productos, cantidades, disponibilidad, costo de despacho y total. El pedido queda sujeto a validación del pago y del stock reservado. La confirmación escrita y sus condiciones se envían al correo informado por el cliente.'::text),
         true
       ),
       updated_at = clock_timestamp()
  from public.website_pages page
 where block.page_id = page.id
   and block.tenant_id = page.tenant_id
   and page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and page.slug = 'terminos'
   and block.block_type = 'about';

update public.website_blocks block
   set block_data = jsonb_set(
         jsonb_set(block.block_data, '{title}', to_jsonb('Derecho a retracto y garantía legal'::text), true),
         '{content}',
         to_jsonb('En compras a distancia puedes ejercer el derecho a retracto dentro de los 10 días siguientes a la recepción del producto, antes de usarlo y devolviéndolo en buen estado con su embalaje original. Si no recibes confirmación escrita del contrato, el plazo legal puede extenderse a 90 días.\n\nEl retracto no reemplaza la garantía legal. Si el producto presenta una falla dentro del plazo legal, puedes solicitar la alternativa que corresponda conforme a la Ley del Consumidor. Para iniciar cualquier caso escribe a ventas@vinabike.cl con tu número de pedido y evidencia disponible.'::text),
         true
       ),
       updated_at = clock_timestamp()
  from public.website_pages page
 where block.page_id = page.id
   and block.tenant_id = page.tenant_id
   and page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and page.slug = 'devoluciones'
   and block.block_type = 'about';

update public.website_blocks block
   set block_data = jsonb_set(
         block.block_data,
         '{items}',
         jsonb_build_array(
           jsonb_build_object('question', '¿Cómo solicito una devolución?', 'answer', 'Escribe a ventas@vinabike.cl con tu número de pedido, motivo, fotos cuando correspondan y un medio de contacto. Confirmaremos la recepción y las instrucciones por email.'),
           jsonb_build_object('question', '¿Quién paga el envío de devolución?', 'answer', 'En un retracto voluntario, el costo de devolución es responsabilidad del cliente. Si el producto está defectuoso, dañado o no corresponde a lo comprado, Viñabike asume el costo aplicable.'),
           jsonb_build_object('question', '¿Cuándo se procesa el reembolso?', 'answer', 'Una vez recibido y verificado el producto, procesamos el reembolso dentro de 10 días. El abono final puede depender de los plazos del medio de pago.'),
           jsonb_build_object('question', '¿Qué excepciones existen?', 'answer', 'Solo aplican las exclusiones permitidas por la normativa: bienes que por su naturaleza no puedan devolverse o se deterioren rápidamente, productos confeccionados a medida y bienes de uso personal o higiene sellados una vez abiertos. Una oferta o liquidación no elimina la garantía legal.'),
           jsonb_build_object('question', '¿Qué comprobante sirve?', 'answer', 'Puedes acreditar la compra con la boleta, el comprobante de pago, el correo de confirmación o cualquier antecedente que identifique el pedido.')
         ),
         true
       ),
       updated_at = clock_timestamp()
  from public.website_pages page
 where block.page_id = page.id
   and block.tenant_id = page.tenant_id
   and page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and page.slug = 'devoluciones'
   and block.block_type = 'faq';

update public.website_blocks block
   set block_data = jsonb_set(
         block.block_data,
         '{features}',
         jsonb_build_array(
           jsonb_build_object('icon', 'local_shipping', 'title', 'Despacho a domicilio', 'description', 'Chile continental: 3 a 12 días hábiles. Antes de realizar el pedido mostramos y sumamos el costo exacto al total.'),
           jsonb_build_object('icon', 'payments', 'title', 'Tarifa por subtotal', 'description', '$6.990 hasta $29.999; $8.990 entre $30.000 y $79.999; $11.990 entre $80.000 y $149.999; $14.990 desde $150.000.'),
           jsonb_build_object('icon', 'store', 'title', 'Retiro en tienda', 'description', 'Sin costo en Alvarez 32, Local 17, Viña del Mar. Enviamos un aviso cuando el pedido está listo.'),
           jsonb_build_object('icon', 'inventory', 'title', 'Seguimiento', 'description', 'Cuando el courier entregue un código de seguimiento, lo enviamos por email y lo mostramos en el estado del pedido.')
         ),
         true
       ),
       updated_at = clock_timestamp()
  from public.website_pages page
 where block.page_id = page.id
   and block.tenant_id = page.tenant_id
   and page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and page.slug = 'envios'
   and block.block_type = 'features';

update public.website_blocks block
   set block_data = jsonb_set(
         block.block_data,
         '{items}',
         jsonb_build_array(
           jsonb_build_object('question', '¿Cuánto demora el despacho?', 'answer', 'El plazo estimado es de 3 a 12 días hábiles para Chile continental, contado desde la confirmación y preparación del pedido. Informaremos cualquier excepción antes o después de la compra.'),
           jsonb_build_object('question', '¿Cuánto cuesta?', 'answer', 'El checkout calcula el costo por subtotal: $6.990 hasta $29.999; $8.990 entre $30.000 y $79.999; $11.990 entre $80.000 y $149.999; $14.990 desde $150.000. No se cobra despacho al elegir retiro en tienda.'),
           jsonb_build_object('question', '¿Puedo retirar en tienda?', 'answer', 'Sí. El retiro en Alvarez 32, Local 17, Viña del Mar no tiene costo. Espera el email que confirma que el pedido está listo antes de visitarnos.'),
           jsonb_build_object('question', '¿Cómo recibo seguimiento?', 'answer', 'Cuando el pedido sea despachado recibirás el transportista, código y enlace de seguimiento si el courier los proporciona.'),
           jsonb_build_object('question', '¿Qué ocurre si no pueden entregar?', 'answer', 'Te contactaremos para coordinar un nuevo intento, retiro en sucursal o la solución que corresponda. No ocultamos cargos adicionales fuera del total aceptado en el checkout.')
         ),
         true
       ),
       updated_at = clock_timestamp()
  from public.website_pages page
 where block.page_id = page.id
   and block.tenant_id = page.tenant_id
   and page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and page.slug = 'envios'
   and block.block_type = 'faq';

update public.website_blocks block
   set block_data = jsonb_set(
         jsonb_set(block.block_data, '{title}', to_jsonb('Responsable y uso de los datos'::text), true),
         '{content}',
         to_jsonb('NEWEN SpA, RUT 77.541.999-7, con domicilio en Alvarez 32, Local 17, Viña del Mar, es responsable del tratamiento de los datos usados por Viñabike. Contacto de privacidad: contacto@vinabike.cl.\n\nTratamos nombre, email, teléfono, dirección, pedido, pago y comunicaciones para crear y entregar pedidos, prevenir fraude, dar soporte, cumplir obligaciones contables y legales y enviar información comercial solo cuando exista consentimiento. Compartimos únicamente los datos necesarios con proveedores de infraestructura, correo, pagos y transporte. No vendemos datos personales.'::text),
         true
       ),
       updated_at = clock_timestamp()
  from public.website_pages page
 where block.page_id = page.id
   and block.tenant_id = page.tenant_id
   and page.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   and page.slug = 'privacidad'
   and block.block_type = 'about';

commit;
