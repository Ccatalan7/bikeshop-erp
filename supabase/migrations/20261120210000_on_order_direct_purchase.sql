-- Lo que llega del proveedor se compra directo, con su plazo (2026-11-20).
--
-- El dueño, al ver la tienda: «habíamos quedado en que lo de a pedido iba a
-- ser súper sutil… es simplemente ponerlo bajo otros plazos de entrega nomás.
-- No decir directamente que es a pedido, eso ahuyenta mucho a los clientes»,
-- y después «sí, vende lo a pedido con plazo y compra directa, y publícalo».
-- Hasta hoy un producto con «Se vende a pedido» sólo se cotizaba: la tienda
-- decía «A pedido» y pedía una cuenta y una cotización. Desde esta migración
-- se compra con el carrito, como lo que está en la repisa, y la tienda dice
-- sólo el plazo.
--
-- * Una sola regla dice qué se vende así ahora y cuánto
--   (`product_on_order_offer_internal_v1`): «Se vende a pedido» activo con
--   proveedor y plazo y, si ese proveedor tiene lector de catálogo (MKR,
--   20261119183500), su última lectura de hace menos de 3 horas tiene el
--   producto con 6 o más: se vende lo que tiene menos 5 de colchón y menos lo
--   vendido de los últimos 2 días que todavía no llega, con tope por compra
--   según el precio (5 hasta $50.000, 3 hasta $200.000, 2 sobre eso). El
--   dueño, 2026-11-14: «publicar sólo lo que en MKR tenga más 3 o más 5» y lo
--   caro «máximo 2 o 3». Sin lector, la ficha manda y vale sólo el tope.
--   La misma regla decide los listados, la ficha, la cotización y el pedido.
-- * Un producto con «Se vende a pedido» que el proveedor ya no tiene (o sin
--   lectura fresca) deja de venderse así y pasa a cotizarse, salvo que su
--   ficha diga que no se ofrece.
-- * El pedido web marca la línea `on_order` con su proveedor y plazo cuando
--   lo libre no alcanza (la cotización ya lo hacía, 20261103010000). Desde ahí
--   sigue el camino de la etapa 5 de cotizaciones, que deja de exigir una
--   cotización: al pagar, lo que hay queda apartado 90 días, sale el borrador
--   de compra (PED) por proveedor y el aviso al equipo; al llegar se aparta y
--   se emite la venta; si el proveedor no lo tiene, «Anular y devolver».
--   Los avisos de un pedido sin cotización llevan al pedido web.

begin;

set local lock_timeout = '5s';

-- ---------------------------------------------------------------------------
-- 1. La regla: qué se vende hoy con plazo y cuánto.
-- ---------------------------------------------------------------------------

create or replace function public.product_on_order_offer_internal_v1(
  p_tenant_id uuid,
  p_product_ids uuid[] default null
)
returns table (
  product_id uuid,
  supplier_id uuid,
  lead_days_min smallint,
  lead_days_max smallint,
  max_quantity integer
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with terms as (
    select t.product_id,
           t.supplier_id,
           t.lead_days_min,
           t.lead_days_max,
           coalesce(p.website_price, p.price, 0) as price,
           nullif(btrim(coalesce(p.supplier_code, '')), '') as supplier_code,
           array_remove(array[
             nullif(btrim(coalesce(p.barcode, '')), ''),
             nullif(btrim(coalesce(p.supplier_code, '')), ''),
             nullif(btrim(coalesce(p.sku, '')), '')
           ], null) as codes
      from public.product_on_order_terms t
      join public.products p
        on p.id = t.product_id
       and p.tenant_id = t.tenant_id
     where t.tenant_id = p_tenant_id
       and t.is_active
       and t.supplier_id is not null
       and (p_product_ids is null or t.product_id = any (p_product_ids))
  ), sized as (
    select terms.*,
           feed.id as feed_id,
           feed.last_ok_at,
           item.stock as supplier_stock,
           coalesce(pending.quantity, 0) as pending,
           case
             when terms.price <= 50000 then 5
             when terms.price <= 200000 then 3
             else 2
           end as per_order
      from terms
      left join lateral (
        select f.id, f.last_ok_at
          from public.supplier_catalog_feeds f
         where f.tenant_id = p_tenant_id
           and f.supplier_id = terms.supplier_id
           and f.enabled
         order by f.last_ok_at desc nulls last
         limit 1
      ) feed on true
      left join lateral (
        -- El producto en la lectura del proveedor: por su código del
        -- proveedor y, si no, por un código de barras (los del local llevan
        -- el código de barras en el SKU o en el código del proveedor).
        select fi.stock
          from public.supplier_catalog_feed_items fi
         where fi.tenant_id = p_tenant_id
           and fi.supplier_id = terms.supplier_id
           and fi.feed_id = feed.id
           and fi.is_listed
           and (
             fi.supplier_sku = terms.supplier_code
             or (fi.barcode = any (terms.codes) and fi.barcode not in ('', '0'))
           )
         order by (fi.supplier_sku = terms.supplier_code) desc nulls last,
                  fi.stock desc
         limit 1
      ) item on feed.id is not null
      left join lateral (
        -- Lo vendido que todavía no llega: la lectura del proveedor recién lo
        -- descuenta cuando se le compra.
        select sum(i.quantity)::integer as quantity
          from public.online_order_items i
          join public.online_orders o
            on o.id = i.order_id
           and o.tenant_id = i.tenant_id
         where i.tenant_id = p_tenant_id
           and i.product_id = terms.product_id
           and i.fulfillment = 'on_order'
           and i.arrived_at is null
           and o.status <> 'cancelled'
           and o.created_at > clock_timestamp() - interval '2 days'
      ) pending on true
  )
  select sized.product_id,
         sized.supplier_id,
         sized.lead_days_min,
         sized.lead_days_max,
         (case
            when sized.feed_id is null then sized.per_order
            else least(sized.per_order, sized.supplier_stock - 5 - sized.pending)
          end)::integer as max_quantity
    from sized
   where sized.feed_id is null
      or (
        sized.last_ok_at > clock_timestamp() - interval '3 hours'
        and sized.supplier_stock is not null
        and sized.supplier_stock - 5 - sized.pending >= 1
      );
$function$;

revoke all on function public.product_on_order_offer_internal_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;

comment on function public.product_on_order_offer_internal_v1(uuid, uuid[]) is
  'Lo que se vende hoy con plazo (20261120210000): «Se vende a pedido» activo con '
  'proveedor y, con lector de catálogo, su lectura de menos de 3 h con 6 o más. '
  'max_quantity: lo del proveedor menos 5 y menos lo vendido sin llegar, con tope '
  'por compra (5/3/2 según precio). Núcleo privado; sin grant.';

-- Cómo se ofrece cada producto sin stock: a pedido (con plazo y cuánto), se
-- cotiza o no se ofrece. Una lectura para muchos productos; la versión de
-- uno lo lee de aquí.
create or replace function public.customer_quote_sold_out_modes_internal(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns table (
  product_id uuid,
  mode text,
  lead_days_min smallint,
  lead_days_max smallint,
  max_quantity integer
)
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with ids as (
    select distinct id
      from unnest(coalesce(p_product_ids, array[]::uuid[])) id
     where id is not null
  ), offer as (
    select o.*
      from public.product_on_order_offer_internal_v1(
             p_tenant_id,
             (select coalesce(array_agg(ids.id), array[]::uuid[]) from ids)
           ) o
  )
  select ids.id,
         case
           when offer.product_id is not null then 'on_order'
           when t.quote_when_sold_out = false then 'none'
           -- «Se vende a pedido» que hoy no se puede vender así (el proveedor
           -- no lo tiene o no hay lectura fresca): se cotiza.
           when t.is_active then 'quote'
           when t.quote_when_sold_out then 'quote'
           when p.brand_id is not null and exists (
             select 1 from public.customer_quote_sold_out_brands b
              where b.tenant_id = p_tenant_id and b.brand_id = p.brand_id
           ) then 'quote'
           else 'none'
         end,
         offer.lead_days_min,
         offer.lead_days_max,
         offer.max_quantity
    from ids
    left join public.products p
      on p.id = ids.id
     and p.tenant_id = p_tenant_id
    left join public.product_on_order_terms t
      on t.product_id = ids.id
     and t.tenant_id = p_tenant_id
    left join offer
      on offer.product_id = ids.id;
$function$;

revoke all on function public.customer_quote_sold_out_modes_internal(uuid, uuid[])
  from public, anon, authenticated, service_role;

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
as $function$
  -- p_brand_id queda por compatibilidad: la marca se lee del producto.
  select coalesce((
    select m.mode
      from public.customer_quote_sold_out_modes_internal(
             p_tenant_id, array[p_product_id]
           ) m
  ), 'none');
$function$;

create or replace function public.get_public_sold_out_offers_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  with policy as (
    select public.catalog_web_policy_v1(p_tenant_id) as v
  ), goods as (
    select p.id
      from public.products p
      cross join policy
     where p.tenant_id = p_tenant_id
       and p.id = any ((coalesce(p_product_ids, array[]::uuid[]))[1:200])
       and coalesce(p.product_type, 'product') <> 'service'
       and public.catalog_product_web_block_v1(p, policy.v) is null
  ), modes as (
    select m.*
      from public.customer_quote_sold_out_modes_internal(
             p_tenant_id,
             (select coalesce(array_agg(goods.id), array[]::uuid[]) from goods)
           ) m
  )
  select coalesce(jsonb_object_agg(m.product_id::text,
    case when m.mode = 'on_order'
      then jsonb_build_object(
             'mode', 'on_order',
             'leadDaysMin', m.lead_days_min,
             'leadDaysMax', m.lead_days_max,
             -- Cuánto se puede comprar con plazo en una compra
             -- (20261120210000).
             'maxQuantity', m.max_quantity)
      else jsonb_build_object('mode', m.mode)
    end), '{}'::jsonb)
    from modes m
   where m.mode <> 'none';
$function$;

create or replace function public.catalog_on_order_product_ids_internal_v1(p_tenant_id uuid)
returns uuid[]
language sql
stable
security definer
set search_path to 'public'
as $function$
  -- Lo que hoy se vende con plazo, no toda ficha con «Se vende a pedido»
  -- (20261120210000): lo que el proveedor ya no tiene sale de los listados.
  select coalesce(array_agg(o.product_id order by o.product_id), array[]::uuid[])
    from public.product_on_order_offer_internal_v1(p_tenant_id, null) o;
$function$;

-- ---------------------------------------------------------------------------
-- 2. El pedido web: la línea que llega del proveedor.
-- ---------------------------------------------------------------------------

-- Lectura de producción del 2026-11-20 (20261014030000 y siguientes) con el
-- agregado marcado: la línea que llega del proveedor.
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
-- 3. Del pago al proveedor, con o sin cotización.
-- ---------------------------------------------------------------------------

-- El pedido al proveedor de una compra directa no tiene cotización.
alter table public.customer_quote_purchase_orders
  alter column quote_id drop not null;

comment on table public.customer_quote_purchase_orders is
  'El pedido a cada proveedor que nació de un pedido web con productos que llegan del proveedor: el documento de compra en borrador (PED-…) que el equipo manda y que después recibe la factura. quote_id sólo cuando el pedido nació de una cotización (20261120210000).';

-- Un aviso al equipo sobre lo que llega del proveedor: con cotización, el de
-- la cotización (lleva a ella); sin cotización, lleva al pedido web.
create or replace function public.online_order_on_order_notify_internal(
  p_order_id uuid,
  p_type text,
  p_title text,
  p_severity text default 'info'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order public.online_orders%rowtype;
  v_quote_id uuid;
  v_lines integer;
begin
  select * into v_order from public.online_orders where id = p_order_id;
  if not found then
    return;
  end if;
  select q.id into v_quote_id
    from public.customer_quotes q
   where q.online_order_id = p_order_id
     and q.tenant_id = v_order.tenant_id;
  if v_quote_id is not null then
    perform public.customer_quote_notify_internal(
      v_quote_id, p_type, p_title, 'online_order', p_order_id, p_severity
    );
    return;
  end if;
  select count(*) into v_lines
    from public.online_order_items
   where order_id = p_order_id
     and tenant_id = v_order.tenant_id;
  insert into public.erp_notifications (
    tenant_id, type, title, body, route, entity_type, entity_id, severity, data
  ) values (
    v_order.tenant_id,
    p_type,
    p_title,
    coalesce(nullif(v_order.order_number, ''), 'Pedido web') || ' · '
      || coalesce(nullif(v_order.customer_name, ''), 'Cliente') || ' · '
      || v_lines || case when v_lines = 1 then ' producto' else ' productos' end,
    '/website/orders?order=' || p_order_id::text,
    'online_order',
    p_order_id,
    p_severity,
    jsonb_build_object(
      'order_id', p_order_id,
      'order_number', v_order.order_number,
      'customer_name', v_order.customer_name
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;
exception
  when others then
    raise warning 'Online order notification could not be recorded';
end;
$function$;

revoke all on function public.online_order_on_order_notify_internal(uuid, text, text, text)
  from public, anon, authenticated;

-- Un pedido a cada proveedor con lo que falta, como borrador en Compras: el
-- mismo documento que arma el asistente de compras y que después lleva la
-- factura. Un borrador no toca stock ni contabilidad. Con o sin cotización
-- (20261120210000).
create or replace function public.customer_quote_order_prepare_purchases_internal(p_order_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order public.online_orders%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_has_quote boolean;
  v_group record;
  v_supplier public.suppliers%rowtype;
  v_net numeric;
  v_iva numeric;
  v_number text;
  v_invoice_id uuid;
  v_count integer := 0;
begin
  select * into v_order from public.online_orders where id = p_order_id;
  if not found then
    return 0;
  end if;
  select * into v_quote from public.customer_quotes
   where online_order_id = p_order_id and tenant_id = v_order.tenant_id;
  v_has_quote := found;

  for v_group in
    select item.on_order_supplier_id as supplier_id,
           jsonb_agg(jsonb_build_object(
             'product_id', item.product_id,
             'product_name', item.product_name,
             'product_sku', item.product_sku,
             'quantity', item.quantity,
             'unit_cost', coalesce(line.unit_cost_net, item.unit_cost, product.cost, 0),
             'iva_rate', 0.19,
             'discount', 0,
             'description', null,
             'purchase_treatment', 'inventory',
             'created_at', to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
           ) order by item.product_name) as items,
           sum(item.quantity * coalesce(line.unit_cost_net, item.unit_cost, product.cost, 0)) as net
      from public.online_order_items item
      left join public.customer_quote_offer_lines line on line.id = item.customer_quote_offer_line_id
      left join public.products product on product.id = item.product_id and product.tenant_id = item.tenant_id
     where item.order_id = p_order_id
       and item.tenant_id = v_order.tenant_id
       and item.fulfillment = 'on_order'
       and item.arrived_at is null
       and item.on_order_supplier_id is not null
       and not exists (
         select 1 from public.customer_quote_purchase_orders po
          where po.online_order_id = p_order_id and po.supplier_id = item.on_order_supplier_id
       )
     group by item.on_order_supplier_id
  loop
    select * into v_supplier from public.suppliers
     where id = v_group.supplier_id and tenant_id = v_order.tenant_id;
    if not found then
      continue;
    end if;
    v_net := public.clp_round(v_group.net);
    v_iva := public.clp_round(v_net * 0.19);
    -- El número provisorio del asistente de compras: cuando llegue la
    -- factura, el campo pasa a llevar el folio del proveedor.
    loop
      v_number := 'PED-' || to_char(clock_timestamp(), 'YYYYMM') || '-'
        || lpad((floor(random() * 100000))::integer::text, 5, '0');
      exit when not exists (
        select 1 from public.purchase_invoices pi
         where pi.tenant_id = v_order.tenant_id
           and pi.supplier_id = v_supplier.id
           and pi.invoice_number = v_number
      );
    end loop;
    insert into public.purchase_invoices (
      tenant_id, invoice_number, supplier_id, supplier_name, supplier_rut, date,
      status, subtotal, iva_amount, total, net_amount, tax_treatment,
      source_document_kind, notes, items
    ) values (
      v_order.tenant_id, v_number, v_supplier.id, v_supplier.name, v_supplier.rut, clock_timestamp(),
      'draft', v_net, v_iva, v_net + v_iva, v_net, 'tax_included',
      'tax_invoice',
      'Para el pedido ' || v_order.order_number
        || case when v_has_quote then ' (cotización ' || v_quote.quote_number || ')' else '' end
        || '.',
      v_group.items
    ) returning id into v_invoice_id;
    insert into public.customer_quote_purchase_orders (
      tenant_id, quote_id, online_order_id, supplier_id, purchase_invoice_id
    ) values (
      v_order.tenant_id,
      case when v_has_quote then v_quote.id end,
      p_order_id,
      v_supplier.id,
      v_invoice_id
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.customer_quote_order_prepare_purchases_internal(uuid) from public, anon, authenticated;

-- Un pedido que espera lo que llega del proveedor quedó pagado: lo que estaba
-- en stock sigue apartado (si otro se lo llevó mientras pagaba, pasa a
-- pedirse), lo que ya llegó se aparta, todo espera y sale el pedido a cada
-- proveedor. Se puede llamar más de una vez. Con o sin cotización
-- (20261120210000).
create or replace function public.customer_quote_order_paid_internal(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order public.online_orders%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_has_quote boolean;
  v_item public.online_order_items%rowtype;
  v_moved integer := 0;
  v_filled integer := 0;
  v_purchases integer := 0;
  v_without_supplier integer;
begin
  select * into v_order from public.online_orders where id = p_order_id for update;
  if not found or v_order.payment_status <> 'paid' or v_order.status = 'cancelled' then
    return null;
  end if;
  select * into v_quote from public.customer_quotes
   where online_order_id = p_order_id and tenant_id = v_order.tenant_id;
  v_has_quote := found;
  -- Sin cotización, sólo un pedido con algo que llega del proveedor.
  if not v_has_quote and not exists (
    select 1 from public.online_order_items i
     where i.order_id = p_order_id
       and i.tenant_id = v_order.tenant_id
       and i.fulfillment = 'on_order'
  ) then
    return null;
  end if;

  for v_item in
    select * from public.online_order_items
     where order_id = p_order_id and tenant_id = v_order.tenant_id and fulfillment = 'stock'
     order by id
  loop
    begin
      perform public.reserve_online_order_item_inventory(v_item.id, 'customer_quote_paid');
    exception when check_violation then
      update public.online_order_items
         set fulfillment = 'on_order',
             on_order_supplier_id = coalesce(
               (select t.supplier_id from public.product_on_order_terms t
                 where t.product_id = v_item.product_id and t.tenant_id = v_item.tenant_id
                   and t.is_active),
               (select p.supplier_id from public.products p
                 where p.id = v_item.product_id and p.tenant_id = v_item.tenant_id)
             )
       where id = v_item.id;
      v_moved := v_moved + 1;
    end;
  end loop;

  for v_item in
    select * from public.online_order_items
     where order_id = p_order_id and tenant_id = v_order.tenant_id
       and fulfillment = 'on_order' and arrived_at is null
     order by id
  loop
    if public.customer_quote_order_fill_line_internal(v_item.id) then
      v_filled := v_filled + 1;
    end if;
  end loop;

  perform public.customer_quote_order_hold_internal(p_order_id);

  if v_order.status = 'pending' then
    update public.online_orders set status = 'confirmed'
     where id = p_order_id and tenant_id = v_order.tenant_id;
  end if;

  if not public.customer_quote_order_waiting_internal(p_order_id) then
    return jsonb_build_object('waiting', false, 'filled', v_filled, 'moved', v_moved);
  end if;

  -- El pedido al proveedor no puede tumbar el pago: si no sale, el equipo lo
  -- arma en Compras.
  begin
    v_purchases := public.customer_quote_order_prepare_purchases_internal(p_order_id);
  exception when others then
    v_purchases := 0;
    perform public.online_order_on_order_notify_internal(
      p_order_id, 'customer_quote_order_attention', 'Arma en Compras el pedido al proveedor',
      'warning'
    );
  end;

  select count(*) into v_without_supplier
    from public.online_order_items
   where order_id = p_order_id and fulfillment = 'on_order' and arrived_at is null
     and on_order_supplier_id is null;

  if v_has_quote and not exists (
    select 1 from public.customer_quote_events e
     where e.quote_id = v_quote.id and e.operation_key = 'order-waiting:' || p_order_id::text
  ) then
    perform public.customer_quote_log_internal(
      v_quote.id, 'order_waiting', 'system', null, 'system', v_quote.current_offer_id,
      'order-waiting:' || p_order_id::text,
      jsonb_build_object(
        'order_id', p_order_id, 'order_number', v_order.order_number,
        'purchases', v_purchases, 'moved_to_order', v_moved, 'filled', v_filled,
        'without_supplier', v_without_supplier
      )
    );
  end if;
  perform public.online_order_on_order_notify_internal(
    p_order_id, 'customer_quote_order_to_purchase', 'Pagado: pedir lo que viene a pedido',
    'warning'
  );
  return jsonb_build_object(
    'waiting', true, 'filled', v_filled, 'moved', v_moved,
    'purchases', v_purchases, 'without_supplier', v_without_supplier
  );
end;
$function$;

revoke all on function public.customer_quote_order_paid_internal(uuid) from public, anon, authenticated;

-- Mira si llegó lo que falta; con todo apartado emite la venta: con Mercado
-- Pago vuelve a procesar el pago que quedó esperando, con transferencia el
-- proceso normal del pedido. Con o sin cotización (20261120210000).
create or replace function public.customer_quote_order_check_arrivals_internal(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order public.online_orders%rowtype;
  v_quote public.customer_quotes%rowtype;
  v_has_quote boolean;
  v_item public.online_order_items%rowtype;
  v_filled integer := 0;
  v_event_id bigint;
  v_result jsonb;
  v_invoice uuid;
  v_error text;
  v_claims text := current_setting('request.jwt.claims', true);
  v_claim_sub text := current_setting('request.jwt.claim.sub', true);
  v_claim_role text := current_setting('request.jwt.claim.role', true);
begin
  select * into v_order from public.online_orders where id = p_order_id for update;
  if not found then
    return null;
  end if;
  select * into v_quote from public.customer_quotes
   where online_order_id = p_order_id and tenant_id = v_order.tenant_id;
  v_has_quote := found;
  if not v_has_quote and not exists (
    select 1 from public.online_order_items i
     where i.order_id = p_order_id
       and i.tenant_id = v_order.tenant_id
       and i.fulfillment = 'on_order'
  ) then
    return null;
  end if;
  if v_order.status = 'cancelled' or v_order.payment_status <> 'paid'
     or v_order.sales_invoice_id is not null then
    return jsonb_build_object(
      'order_id', p_order_id,
      'waiting', public.customer_quote_order_waiting_internal(p_order_id),
      'invoice_id', v_order.sales_invoice_id
    );
  end if;

  for v_item in
    select * from public.online_order_items
     where order_id = p_order_id and tenant_id = v_order.tenant_id
       and fulfillment = 'on_order' and arrived_at is null
     order by id
  loop
    if public.customer_quote_order_fill_line_internal(v_item.id) then
      v_filled := v_filled + 1;
      if v_has_quote then
        perform public.customer_quote_log_internal(
          v_quote.id, 'order_line_arrived', 'system', null, 'system', v_quote.current_offer_id,
          'order-line-arrived:' || v_item.id::text,
          jsonb_build_object('order_id', p_order_id, 'product', v_item.product_name, 'quantity', v_item.quantity)
        );
      end if;
    end if;
  end loop;

  if public.customer_quote_order_waiting_internal(p_order_id) then
    return jsonb_build_object('order_id', p_order_id, 'waiting', true, 'arrived', v_filled);
  end if;

  begin
    if v_order.payment_method = 'mercadopago' then
      select processing.payment_event_id into v_event_id
        from public.sales_channel_payment_processing processing
       where processing.order_id = p_order_id
         and processing.tenant_id = v_order.tenant_id
         and processing.processing_state = 'action_required'
         and processing.last_error_code = 'awaiting_on_order_stock'
       order by processing.updated_at desc
       limit 1;
    end if;
    if v_event_id is not null then
      -- El pago se vuelve a procesar como lo hace el barrido de cada 10
      -- minutos, sin la sesión de quien apretó «Revisar si llegó» (su
      -- comando ya comprobó que es del taller). Con una sesión, la guarda de
      -- sales_payments (guard_sales_payment_correction_command) no deja
      -- estampar la llave del pago de Mercado Pago y la venta no salía:
      -- encontrado al probar la compra directa, el 2026-11-20; pasaba igual
      -- con el botón de la cotización (20261120210000).
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
      perform set_config('request.jwt.claim.role', '', true);
      v_result := public.process_mercadopago_payment_observation(v_event_id);
      v_invoice := nullif(v_result ->> 'invoice_id', '')::uuid;
      if v_invoice is null then
        v_error := coalesce(v_result ->> 'error_message', 'La venta no se pudo emitir.');
      end if;
    else
      v_invoice := public.process_online_order(p_order_id);
    end if;
  exception when others then
    v_invoice := null;
    v_error := left(sqlerrm, 300);
  end;
  -- La sesión vuelve a ser la de quien llamó.
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  perform set_config('request.jwt.claim.sub', coalesce(v_claim_sub, ''), true);
  perform set_config('request.jwt.claim.role', coalesce(v_claim_role, ''), true);

  if v_invoice is null then
    if v_has_quote then
      perform public.customer_quote_log_internal(
        v_quote.id, 'order_attention', 'system', null, 'system', v_quote.current_offer_id, null,
        jsonb_build_object('order_id', p_order_id, 'error', coalesce(v_error, 'La venta no se emitió.'))
      );
    end if;
    perform public.online_order_on_order_notify_internal(
      p_order_id, 'customer_quote_order_attention', 'Llegó todo, pero la venta no se emitió',
      'warning'
    );
    return jsonb_build_object('order_id', p_order_id, 'waiting', false, 'arrived', v_filled, 'error', v_error);
  end if;

  if v_has_quote then
    perform public.customer_quote_log_internal(
      v_quote.id, 'order_sale_issued', 'system', null, 'system', v_quote.current_offer_id,
      'order-sale:' || p_order_id::text,
      jsonb_build_object(
        'order_id', p_order_id, 'invoice_id', v_invoice,
        'invoice_number', (select invoice_number from public.sales_invoices where id = v_invoice)
      )
    );
  end if;
  update public.erp_notifications n
     set read_at = coalesce(n.read_at, clock_timestamp())
   where n.tenant_id = v_order.tenant_id
     and n.type in ('customer_quote_order_to_purchase', 'customer_quote_order_attention')
     and n.entity_type = 'online_order'
     and n.entity_id = p_order_id;
  perform public.online_order_on_order_notify_internal(
    p_order_id, 'customer_quote_order_ready', 'Llegó todo: preparar el pedido',
    'success'
  );
  return jsonb_build_object('order_id', p_order_id, 'waiting', false, 'arrived', v_filled, 'invoice_id', v_invoice);
end;
$function$;

revoke all on function public.customer_quote_order_check_arrivals_internal(uuid) from public, anon, authenticated;

-- Cada 10 minutos: los pedidos pagados que esperan algo que ya tiene stock,
-- de una cotización o de una compra directa (20261120210000).
create or replace function public.customer_quote_orders_check_arrivals_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order_id uuid;
  v_count integer := 0;
begin
  for v_order_id in
    select distinct o.id
      from public.online_orders o
      join public.online_order_items item on item.order_id = o.id and item.tenant_id = o.tenant_id
      join public.products p on p.id = item.product_id and p.tenant_id = item.tenant_id
     where o.payment_status = 'paid'
       and o.status <> 'cancelled'
       and o.sales_invoice_id is null
       and item.fulfillment = 'on_order'
       and item.arrived_at is null
       and coalesce(p.stock_quantity, p.inventory_qty, 0) >= item.quantity
     limit 50
  loop
    begin
      perform public.customer_quote_order_check_arrivals_internal(v_order_id);
      v_count := v_count + 1;
    exception when others then
      raise warning 'On-order arrival check failed for %: %', v_order_id, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$function$;

revoke all on function public.customer_quote_orders_check_arrivals_v1() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 4. En el ERP: el pedido con lo que llega del proveedor.
-- ---------------------------------------------------------------------------

-- El pedido, sus líneas (de dónde sale cada una y si llegó) y sus pedidos a
-- proveedores: lo mismo para la cotización y para Pedidos web.
create or replace function public.online_order_on_order_projection_internal(p_order_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $function$
  select jsonb_build_object(
    'id', o.id,
    'number', o.order_number,
    'status', o.status,
    'payment_status', o.payment_status,
    'payment_method', o.payment_method,
    'delivery_type', o.delivery_type,
    'total', o.total,
    'shipping_cost', o.shipping_cost,
    'paid_at', o.paid_at,
    'tracking_number', o.tracking_number,
    'shipping_carrier', o.shipping_carrier,
    'sales_invoice_id', o.sales_invoice_id,
    'invoice_number', (
      select si.invoice_number from public.sales_invoices si
       where si.id = o.sales_invoice_id and si.tenant_id = o.tenant_id
    ),
    'quote_id', (
      select q.id from public.customer_quotes q
       where q.online_order_id = o.id and q.tenant_id = o.tenant_id
    ),
    'waiting', public.customer_quote_order_waiting_internal(o.id),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id,
        'product_id', i.product_id,
        'product_name', i.product_name,
        'product_sku', i.product_sku,
        'quantity', i.quantity,
        'fulfillment', i.fulfillment,
        'arrived_at', i.arrived_at,
        'supplier_id', i.on_order_supplier_id,
        'supplier_name', s.name,
        'lead_days_min', i.lead_days_min,
        'lead_days_max', i.lead_days_max,
        'stock_now', p.stock_quantity
      ) order by i.created_at, i.id)
        from public.online_order_items i
        left join public.suppliers s on s.id = i.on_order_supplier_id and s.tenant_id = i.tenant_id
        left join public.products p on p.id = i.product_id and p.tenant_id = i.tenant_id
       where i.order_id = o.id and i.tenant_id = o.tenant_id
    ), '[]'::jsonb),
    'purchases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', po.id,
        'supplier_id', po.supplier_id,
        'supplier_name', s.name,
        'sales_rep_name', s.sales_rep_name,
        'sales_rep_phone', s.sales_rep_phone,
        'purchase_invoice_id', pi.id,
        'number', pi.invoice_number,
        'status', pi.status,
        'total', pi.total,
        'created_at', po.created_at
      ) order by po.created_at)
        from public.customer_quote_purchase_orders po
        left join public.suppliers s on s.id = po.supplier_id and s.tenant_id = po.tenant_id
        left join public.purchase_invoices pi on pi.id = po.purchase_invoice_id and pi.tenant_id = po.tenant_id
       where po.online_order_id = o.id and po.tenant_id = o.tenant_id
    ), '[]'::jsonb)
  )
    from public.online_orders o
   where o.id = p_order_id;
$function$;

revoke all on function public.online_order_on_order_projection_internal(uuid)
  from public, anon, authenticated;

-- Pedidos web › un pedido con algo que llega del proveedor (sólo el equipo).
create or replace function public.online_order_on_order_detail_v1(
  p_tenant_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  if not exists (
    select 1 from public.online_orders o
     where o.id = p_order_id and o.tenant_id = p_tenant_id
  ) then
    raise exception 'Order not found or not accessible' using errcode = 'P0002';
  end if;
  return public.online_order_on_order_projection_internal(p_order_id);
end;
$function$;

revoke all on function public.online_order_on_order_detail_v1(uuid, uuid) from public, anon;
grant execute on function public.online_order_on_order_detail_v1(uuid, uuid) to authenticated;

-- «Revisar si llegó» desde Pedidos web: no espera los 10 minutos.
create or replace function public.online_order_on_order_check_arrivals_v1(
  p_tenant_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  if not exists (
    select 1 from public.online_orders o
     where o.id = p_order_id and o.tenant_id = p_tenant_id
  ) then
    raise exception 'Order not found or not accessible' using errcode = 'P0002';
  end if;
  return coalesce(
    public.customer_quote_order_check_arrivals_internal(p_order_id),
    jsonb_build_object('order_id', p_order_id, 'waiting', false)
  );
end;
$function$;

revoke all on function public.online_order_on_order_check_arrivals_v1(uuid, uuid) from public, anon;
grant execute on function public.online_order_on_order_check_arrivals_v1(uuid, uuid) to authenticated;

-- «Anular y devolver» un pedido web pagado que espera lo que llega del
-- proveedor y que no nació de una cotización (el de una cotización se anula
-- desde ella, customer_quote_order_cancel_v1). El equipo ya devolvió la plata
-- y anota la referencia; la base anula el pedido, libera lo apartado, anula el
-- borrador de compra que nadie mandó, cierra el pago de Mercado Pago que
-- esperaba y registra el reembolso. No hay venta: no hay asiento que revertir.
create or replace function public.online_order_on_order_cancel_v1(
  p_tenant_id uuid,
  p_order_id uuid,
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_key text := lower(btrim(coalesce(p_request ->> 'operation_key', '')));
  v_reason text := btrim(coalesce(p_request ->> 'reason', ''));
  v_reference text := btrim(coalesce(p_request ->> 'refund_reference', ''));
  v_refunded_at timestamptz;
  v_order public.online_orders%rowtype;
  v_operation_id uuid;
  v_before jsonb;
  v_cancelled_purchases integer := 0;
  v_sent_purchases integer := 0;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  if not public.online_order_correction_actor_allowed(p_tenant_id) then
    raise exception 'quote_refund_not_allowed' using errcode = '42501';
  end if;
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Invalid order cancellation' using errcode = '22023';
  end if;
  if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'A random operation key is required' using errcode = '22023';
  end if;
  if length(v_reason) not between 4 and 500 then
    raise exception 'quote_cancel_reason_required' using errcode = '22023';
  end if;
  if length(v_reference) not between 2 and 120 then
    raise exception 'quote_refund_reference_required' using errcode = '22023';
  end if;
  begin
    v_refunded_at := coalesce(nullif(p_request ->> 'refunded_at', '')::timestamptz, clock_timestamp());
  exception when others then
    raise exception 'Invalid refund date' using errcode = '22023';
  end;
  if v_refunded_at > clock_timestamp() + interval '5 minutes' then
    raise exception 'quote_refund_date_in_future' using errcode = '22023';
  end if;

  select * into v_order from public.online_orders
   where id = p_order_id and tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Order not found or not accessible' using errcode = 'P0002';
  end if;

  -- Un reintento con la misma llave devuelve lo que ya quedó hecho.
  if exists (
    select 1 from public.online_order_events e
     where e.tenant_id = p_tenant_id
       and e.order_id = p_order_id
       and e.operation_key = 'on-order-cancel:' || v_key
  ) then
    return public.online_order_on_order_projection_internal(p_order_id)
      || jsonb_build_object('replay', true);
  end if;

  if exists (
    select 1 from public.customer_quotes q
     where q.online_order_id = p_order_id and q.tenant_id = p_tenant_id
  ) then
    raise exception 'online_order_has_quote' using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.online_order_items i
     where i.order_id = p_order_id and i.tenant_id = p_tenant_id
       and i.fulfillment = 'on_order'
  ) then
    raise exception 'online_order_not_on_order' using errcode = '55000';
  end if;
  if v_order.status = 'cancelled' then
    raise exception 'quote_order_already_cancelled' using errcode = '55000';
  end if;
  if v_order.payment_status <> 'paid' then
    -- Sin pago no hay nada que devolver: se anula como cualquier pedido web.
    raise exception 'quote_order_not_paid' using errcode = '55000';
  end if;
  if v_order.sales_invoice_id is not null then
    -- Con venta, la devolución es de Correcciones, con su nota de crédito.
    raise exception 'quote_order_has_sale' using errcode = '55000';
  end if;
  if v_order.status not in ('pending', 'confirmed', 'processing', 'ready_for_pickup') then
    raise exception 'quote_order_already_delivered' using errcode = '55000';
  end if;
  if v_refunded_at < coalesce(v_order.paid_at, v_order.created_at) - interval '1 day' then
    raise exception 'quote_refund_date_before_payment' using errcode = '22023';
  end if;

  v_before := jsonb_build_object('order', to_jsonb(v_order));
  insert into public.inventory_accounting_operations (
    tenant_id, operation_key, source_channel, action, document_type,
    document_id, actor_id, executor, old_status, new_status,
    before_snapshot, context
  ) values (
    p_tenant_id,
    'online_order_cancel:' || v_order.id::text,
    'online_sale',
    'cancel',
    'online_order',
    v_order.id,
    auth.uid(),
    'database_rpc',
    v_order.status,
    'cancelled',
    v_before,
    jsonb_build_object(
      'reason', v_reason,
      'refund_requested', v_order.total,
      'refund_executed', true,
      'refund_reference', v_reference,
      'transaction_id', txid_current()::text
    )
  )
  returning id into v_operation_id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accepted', 'started', 'online_order', v_order.id,
    jsonb_build_object('action', 'cancel', 'reason', v_reason)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'source_snapshotted', 'completed', 'online_order', v_order.id,
    v_before
  );

  perform set_config('app.inventory_operation_id', v_operation_id::text, true);
  perform set_config('app.inventory_source_document_type', 'online_order', true);
  perform set_config('app.inventory_source_document_id', v_order.id::text, true);
  perform set_config('app.inventory_source_channel', 'online_sale', true);
  perform set_config('app.online_order_operation_key', 'on-order-cancel:' || v_key, true);
  perform set_config(
    'app.online_order_request_snapshot',
    jsonb_build_object(
      'source', 'online_order_on_order_cancel_v1',
      'reason', v_reason,
      'refund_reference', v_reference
    )::text,
    true
  );

  -- Los disparadores de siempre: liberan lo apartado, anotan la transición y
  -- encolan los correos de pedido cancelado y de reembolso.
  update public.online_orders
     set status = 'cancelled',
         cancelled_at = clock_timestamp(),
         cancelled_reason = v_reason,
         cancelled_by = auth.uid(),
         cancellation_operation_id = v_operation_id,
         payment_status = 'refunded',
         refund_amount = v_order.total,
         refunded_at = v_refunded_at,
         updated_at = clock_timestamp()
   where id = v_order.id
     and tenant_id = p_tenant_id;

  perform set_config('app.online_order_operation_key', '', true);
  perform set_config('app.online_order_request_snapshot', '', true);

  -- Lo que nadie mandó al proveedor se anula; lo enviado queda para que el
  -- equipo le avise.
  update public.purchase_invoices pi
     set status = 'cancelled',
         updated_at = clock_timestamp()
    from public.customer_quote_purchase_orders po
   where po.online_order_id = v_order.id
     and po.tenant_id = p_tenant_id
     and pi.id = po.purchase_invoice_id
     and pi.tenant_id = p_tenant_id
     and pi.status = 'draft';
  get diagnostics v_cancelled_purchases = row_count;
  select count(*) into v_sent_purchases
    from public.customer_quote_purchase_orders po
    join public.purchase_invoices pi on pi.id = po.purchase_invoice_id and pi.tenant_id = po.tenant_id
   where po.online_order_id = v_order.id
     and po.tenant_id = p_tenant_id
     and pi.status not in ('draft', 'cancelled');

  -- El pago de Mercado Pago que esperaba la llegada ya no espera nada.
  update public.sales_channel_payment_processing processing
     set processing_state = 'processed',
         processed_at = clock_timestamp(),
         action_required_at = null,
         last_error_code = 'quote_order_refunded',
         last_error_message = 'Pedido anulado y pago devuelto (' || v_reference || ').',
         requires_refund_review = false,
         updated_at = clock_timestamp()
   where processing.order_id = v_order.id
     and processing.tenant_id = p_tenant_id
     and processing.processing_state <> 'processed';

  update public.erp_notifications n
     set read_at = coalesce(n.read_at, clock_timestamp())
   where n.tenant_id = p_tenant_id
     and n.type in ('customer_quote_order_to_purchase', 'customer_quote_order_attention',
                    'customer_quote_order_ready')
     and n.entity_type = 'online_order'
     and n.entity_id = v_order.id;

  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'inventory_applied', 'completed', 'online_order', v_order.id,
    jsonb_build_object('reservations_released_by_trigger', true)
  );
  perform public.append_inventory_accounting_checkpoint(
    v_operation_id, 'accounting_planned', 'completed', 'online_order', v_order.id,
    jsonb_build_object(
      'refund_executed', true,
      'refund_outside_erp', true,
      'sale_never_issued', true,
      'purchases_cancelled', v_cancelled_purchases
    )
  );
  perform public.complete_inventory_accounting_operation(
    v_operation_id,
    p_tenant_id,
    jsonb_build_object(
      'status', 'cancelled',
      'refund_amount', v_order.total,
      'refund_reference', v_reference
    )
  );

  return public.online_order_on_order_projection_internal(p_order_id)
    || jsonb_build_object('replay', false, 'purchases_sent', v_sent_purchases);
end;
$function$;

revoke all on function public.online_order_on_order_cancel_v1(uuid, uuid, jsonb) from public, anon;
grant execute on function public.online_order_on_order_cancel_v1(uuid, uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. La cotización lee su pedido con la misma proyección.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.customer_quote_detail_v1(p_tenant_id uuid, p_quote_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_quote public.customer_quotes%rowtype;
  v_draft uuid;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  select * into v_quote from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  select o.id into v_draft from public.customer_quote_offers o
   where o.quote_id = p_quote_id and o.status = 'draft';

  return jsonb_build_object(
    'quote', to_jsonb(v_quote) - 'request_idempotency_key',
    'settings', to_jsonb(public.customer_quote_settings_internal(p_tenant_id)),
    'requested', coalesce((select jsonb_agg(to_jsonb(l) order by l.line_no)
                             from public.customer_quote_lines l where l.quote_id = p_quote_id), '[]'::jsonb),
    'offers', coalesce((
      select jsonb_agg(to_jsonb(o) || jsonb_build_object(
        'lines', coalesce((
          select jsonb_agg(to_jsonb(ol) || jsonb_build_object(
            'supplier_name', s.name,
            'stock_now', p.inventory_qty
          ) order by ol.line_no)
            from public.customer_quote_offer_lines ol
            left join public.suppliers s on s.id = ol.supplier_id
            left join public.products p on p.id = ol.product_id
           where ol.offer_id = o.id
        ), '[]'::jsonb)
      ) order by o.offer_no desc)
        from public.customer_quote_offers o
       where o.quote_id = p_quote_id and o.status <> 'cancelled'
    ), '[]'::jsonb),
    'draftOfferId', v_draft,
    'tasks', coalesce((
      select jsonb_agg(to_jsonb(t) || jsonb_build_object(
        'supplier_name', s.name,
        'sales_rep_name', s.sales_rep_name,
        'sales_rep_phone', s.sales_rep_phone
      ) order by t.created_at)
        from public.customer_quote_supplier_tasks t
        left join public.suppliers s on s.id = t.supplier_id
       where t.quote_id = p_quote_id and t.status <> 'cancelled'
    ), '[]'::jsonb),
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'kind', m.kind, 'channel', m.channel, 'recipient', m.recipient,
        'state', m.state, 'sent_at', m.sent_at, 'created_at', m.created_at,
        'offer_id', m.offer_id, 'last_error', m.last_error
      ) order by m.created_at)
        from public.customer_quote_messages m where m.quote_id = p_quote_id
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.id)
        from public.customer_quote_events e where e.quote_id = p_quote_id
    ), '[]'::jsonb),
    -- El pedido que nació al aceptar, con lo que viene a pedido y el pedido a
    -- cada proveedor (20261103010000); la misma lectura que Pedidos web
    -- (20261120210000).
    'order', public.online_order_on_order_projection_internal(v_quote.online_order_id)
  );
end;
$function$;

-- ---------------------------------------------------------------------------
-- 6. El correo del pedido dice el plazo de despacho de cada línea que trae
--    el proveedor (la plantilla lo escribe).
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.transactional_email_render_payload(p_order online_orders, p_message_kind text, p_shipment online_order_shipments DEFAULT NULL::online_order_shipments)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_store_url text;
  v_items jsonb;
  v_payload jsonb;
begin
  select * into v_tenant
  from public.tenants
  where id = p_order.tenant_id;

  select * into v_settings
  from public.transactional_email_settings
  where tenant_id = p_order.tenant_id;

  v_store_url := public.transactional_email_store_url(
    v_settings.public_store_url,
    v_tenant.custom_domain
  );

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', item.product_name,
      'sku', item.product_sku,
      'quantity', item.quantity,
      'unitPrice', item.unit_price,
      'subtotal', item.subtotal,
      -- Lo que todavía trae el proveedor lleva su plazo de despacho; el
      -- correo dice sólo ese plazo, nunca «a pedido» (20261120210000).
      'leadDaysMin', case
        when item.fulfillment = 'on_order' and item.arrived_at is null
          then item.lead_days_min
      end,
      'leadDaysMax', case
        when item.fulfillment = 'on_order' and item.arrived_at is null
          then item.lead_days_max
      end
    ) order by item.created_at, item.id
  ), '[]'::jsonb)
  into v_items
  from public.online_order_items item
  where item.order_id = p_order.id
    and item.tenant_id = p_order.tenant_id;

  v_payload := jsonb_build_object(
    'schemaVersion', 1,
    'eventType', p_message_kind,
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else (
          select setting.value
            from public.website_settings setting
           where setting.tenant_id = p_order.tenant_id
             and setting.key = 'company_logo_url'
             and setting.value ~* '^https://[^[:space:]]+$'
           limit 1
        )
      end,
      'storeUrl', v_store_url,
      'currency', coalesce(v_tenant.currency, 'CLP'),
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago'),
      -- La marca del correo es la del tema del editor del sitio.
      'brandColor', (
        select case
          when setting.value ~ '^#[0-9A-Fa-f]{6}$' then upper(setting.value)
          when setting.value ~ '^[0-9]{1,10}$'
            then '#' || upper(lpad(to_hex(setting.value::bigint & 16777215), 6, '0'))
        end
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_primary_color'
         limit 1
      ),
      'headingFont', (
        select btrim(setting.value)
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_heading_font'
           and btrim(setting.value) ~ '^[A-Za-z0-9 ]{1,40}$'
         limit 1
      ),
      'bodyFont', (
        select btrim(setting.value)
          from public.website_settings setting
         where setting.tenant_id = p_order.tenant_id
           and setting.key = 'theme_body_font'
           and btrim(setting.value) ~ '^[A-Za-z0-9 ]{1,40}$'
         limit 1
      )
    )),
    'customer', jsonb_build_object('name', p_order.customer_name),
    'order', jsonb_strip_nulls(jsonb_build_object(
      'id', p_order.id,
      'number', p_order.order_number,
      'status', p_order.status,
      'paymentStatus', p_order.payment_status,
      'createdAt', p_order.created_at,
      'deliveryType', p_order.delivery_type,
      'subtotal', p_order.subtotal,
      'shippingCost', p_order.shipping_cost,
      'discountAmount', p_order.discount_amount,
      'total', p_order.total,
      'trackingCarrier', p_order.shipping_carrier,
      'trackingNumber', p_order.tracking_number,
      'trackingUrl', case
        when p_order.tracking_url ~* '^https://[^[:space:]]+$' then p_order.tracking_url
        else null
      end,
      'refundedAmount', case
        when p_message_kind = 'refund_completed' then p_order.refund_amount
        else null
      end,
      'refundedAt', case
        when p_message_kind = 'refund_completed' then p_order.refunded_at
        else null
      end
    )),
    'items', v_items,
    'document', jsonb_build_object(
      'kind', 'order_receipt',
      'taxStatus', 'not_a_tax_document',
      'label', 'Comprobante de pedido · No constituye documento tributario'
    )
  );

  -- «Va en camino» cuenta con qué se envió y adónde (20261013210000).
  if p_message_kind = 'shipped' then
    v_payload := v_payload || jsonb_build_object(
      'shipment', case
        when p_shipment is null then null
        else jsonb_strip_nulls(jsonb_build_object(
          'carrier', p_shipment.carrier,
          'carrierCode', p_shipment.carrier_code,
          'service', p_shipment.service,
          'trackingNumber', p_shipment.tracking_number,
          'trackingUrl', p_shipment.tracking_url,
          'admittedAt', p_shipment.admitted_at
        ))
      end,
      'delivery', jsonb_strip_nulls(jsonb_build_object(
        'name', nullif(btrim(p_order.customer_name), ''),
        'addressLine1', nullif(btrim(p_order.shipping_address_line1), ''),
        'addressLine2', nullif(btrim(p_order.shipping_address_line2), ''),
        'city', nullif(btrim(p_order.shipping_city), ''),
        'state', nullif(btrim(p_order.shipping_state), '')
      ))
    );
  end if;

  return v_payload;
end;
$function$;

commit;
