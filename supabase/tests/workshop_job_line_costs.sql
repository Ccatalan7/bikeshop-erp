-- Una sola regla para repartir las líneas del trabajo entre repuestos y mano
-- de obra (20261001190000).
--
-- Servicio es mano de obra; todo lo demás —un producto, un ítem libre escrito
-- a mano— es repuesto. Antes había tres reglas: la bici no sumaba el ítem
-- libre en ningún lado, la factura lo ponía en mano de obra y el trabajo en
-- repuestos; y un segundo disparador pisaba el total del trabajo con el neto
-- de las líneas, sin descuento ni IVA, también en un trabajo facturado.
--
-- Los cinco que reparten (el subtotal de la bici, el trabajo, el disparador
-- de costos, la factura → el trabajo y la cotización pendiente) dan lo mismo
-- con las mismas líneas.
begin;

select no_plan();

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2a10000-0000-4000-8000-0000000000' || p_n)::uuid $$;

insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Taller costos');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated',
   'costos-lineas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);

insert into public.customers(id, tenant_id, name) values
  (pg_temp.id('10'), pg_temp.id('01'), 'Cliente costos');
insert into public.bikes(id, tenant_id, customer_id, brand, model, is_active) values
  (pg_temp.id('26'), pg_temp.id('01'), pg_temp.id('10'), 'Trek', 'Marlin 5', true);
insert into public.products(id, tenant_id, name, product_type) values
  (pg_temp.id('70'), pg_temp.id('01'), 'Cadena 1/2 X 3/32', 'product'),
  (pg_temp.id('72'), pg_temp.id('01'), 'Mantención Maza', 'service'),
  (pg_temp.id('73'), pg_temp.id('01'), 'Casco urbano', 'product');

-- Una línea: el producto 72 es el servicio; sin producto, un ítem libre.
create function pg_temp.line(p_id text, p_job text, p_product text,
                             p_name text, p_price numeric,
                             p_job_bike text default null)
returns void language sql as $$
  insert into public.mechanic_job_items(id, tenant_id, job_id, job_bike_id,
    product_id, service_product_id, product_name, quantity, unit_price,
    total_price, item_type)
  values (pg_temp.id(p_id), pg_temp.id('01'), pg_temp.id(p_job),
    case when p_job_bike is not null then pg_temp.id(p_job_bike) end,
    case when p_product not in ('72', '') then pg_temp.id(p_product) end,
    case when p_product = '72' then pg_temp.id(p_product) end,
    p_name, 1, p_price, p_price,
    case p_product when '72' then 'service' when '' then 'adhoc' else 'product' end)
$$;
create function pg_temp.bike_costs(p_job_bike text) returns numeric[] language sql as $$
  select array[parts_cost, labor_cost, subtotal]
    from public.mechanic_job_bikes where id = pg_temp.id(p_job_bike)
$$;
create function pg_temp.job_costs(p_job text) returns numeric[] language sql as $$
  select array[parts_cost, labor_cost, final_cost, total_cost]
    from public.mechanic_jobs where id = pg_temp.id(p_job)
$$;
create function pg_temp.set_price(p_line text, p_price numeric) returns void language sql as $$
  update public.mechanic_job_items
     set unit_price = p_price, total_price = p_price
   where id = pg_temp.id(p_line) and tenant_id = pg_temp.id('01')
$$;

-- ============================================================================
-- La regla
-- ============================================================================

select is(
  (select jsonb_object_agg(coalesce(t, 'sin tipo'), public.job_line_cost_bucket(t))
     from unnest(array['product', 'service', 'adhoc', null]) t),
  '{"product": "parts", "service": "labor", "adhoc": "parts", "sin tipo": "parts"}'::jsonb,
  'servicio es mano de obra; un producto, un ítem libre o una línea sin tipo, repuestos');

-- ============================================================================
-- La bici, el trabajo y el disparador de costos
-- ============================================================================

insert into public.mechanic_jobs(id, tenant_id, customer_id, job_number,
                                 job_type, status)
values (pg_temp.id('34'), pg_temp.id('01'), pg_temp.id('10'), 'COSTO-34',
        'service', 'PENDIENTE');
insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
values (pg_temp.id('46'), pg_temp.id('01'), pg_temp.id('34'), pg_temp.id('26'), 0);
select pg_temp.line('56', '34', '70', 'Cadena 1/2 X 3/32', 10000, '46');
select pg_temp.line('57', '34', '72', 'Mantención Maza', 5000, '46');
select pg_temp.line('58', '34', '', 'Ajuste de cables', 2000, '46');
select pg_temp.line('55', '34', '73', 'Casco urbano', 3000);

select is(pg_temp.bike_costs('46'), array[12000, 5000, 17000]::numeric[],
  'la bici suma el ítem libre como repuesto (antes no lo sumaba en ningún lado)');
select is(pg_temp.job_costs('34'), array[15000, 5000, 20000, 20000]::numeric[],
  'el trabajo reparte igual, más el casco que el cliente compró aparte en General');

-- Con descuento: cambiar una línea deja el total con su descuento (antes el
-- disparador de costos lo pisaba con repuestos + mano de obra).
update public.mechanic_jobs set discount_amount = 1000 where id = pg_temp.id('34');
select pg_temp.set_price('57', 6000);
select is(pg_temp.job_costs('34'), array[15000, 6000, 20000, 20000]::numeric[],
  'con descuento, el total es el subtotal menos el descuento');
select is(pg_temp.bike_costs('46'), array[12000, 6000, 18000]::numeric[],
  'y la bici suma la mano de obra nueva');

-- ============================================================================
-- La factura → el trabajo, y lo que pasa después en un trabajo facturado
-- ============================================================================

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, customer_name, source,
  status, subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values
  (pg_temp.id('81'), pg_temp.id('01'), 'FV-COSTO-81', pg_temp.id('10'),
   'Cliente costos', 'mechanic_job', 'draft', 21000, 21000, 3990, 24990, 0,
   24990, 'tax_included',
   jsonb_build_array(
     jsonb_build_object('id', pg_temp.id('56'), 'product_id', pg_temp.id('70'),
       'product_name', 'Cadena 1/2 X 3/32', 'item_type', 'product',
       'quantity', 1, 'unit_price', 10000, 'line_total', 10000),
     jsonb_build_object('id', pg_temp.id('57'), 'product_id', pg_temp.id('72'),
       'product_name', 'Mantención Maza', 'item_type', 'service', 'is_service', true,
       'quantity', 1, 'unit_price', 6000, 'line_total', 6000),
     jsonb_build_object('id', pg_temp.id('58'), 'product_name', 'Ajuste de cables',
       'item_type', 'adhoc', 'is_catalog_product', false,
       'quantity', 1, 'unit_price', 2000, 'line_total', 2000),
     jsonb_build_object('id', pg_temp.id('55'), 'product_id', pg_temp.id('73'),
       'product_name', 'Casco urbano', 'item_type', 'product',
       'quantity', 1, 'unit_price', 3000, 'line_total', 3000)));

select set_config('app.syncing_job_to_invoice', 'true', true);
update public.mechanic_jobs
   set invoice_id = pg_temp.id('81'), is_invoiced = true
 where id = pg_temp.id('34');
select set_config('app.syncing_job_to_invoice', '', true);

select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('81'))$$,
  'la factura se sincroniza con el trabajo');
select is(pg_temp.job_costs('34'), array[15000, 6000, 24990, 24990]::numeric[],
  'la factura reparte igual (el ítem libre en repuestos, no en mano de obra) y el total es el de la factura');
select is(pg_temp.bike_costs('46'), array[12000, 6000, 18000]::numeric[],
  'y la bici, también con el ítem libre en repuestos');

-- Una línea cambia en el trabajo facturado: el reparto se rehace y el total
-- sigue siendo el de la factura (antes pasaba al neto de las líneas, y el
-- portal mostraba eso al cliente).
select pg_temp.set_price('58', 2500);
select is(pg_temp.job_costs('34'), array[15500, 6000, 24990, 24990]::numeric[],
  'en un trabajo facturado, cambiar una línea rehace el reparto y deja el total de la factura');
select is(pg_temp.bike_costs('46'), array[12500, 6000, 18500]::numeric[],
  'y la bici suma el ítem libre nuevo');

-- ============================================================================
-- La cotización pendiente
-- ============================================================================

insert into public.mechanic_jobs(id, tenant_id, customer_id, job_number,
                                 job_type, quotation_status,
                                 quotation_valid_until, status)
values (pg_temp.id('35'), pg_temp.id('01'), pg_temp.id('10'), 'COSTO-35',
        'quotation', 'pending', clock_timestamp() + interval '7 days',
        'PRESUPUESTO');
select pg_temp.line('59', '35', '70', 'Cadena 1/2 X 3/32', 10000);
select pg_temp.line('60', '35', '72', 'Mantención Maza', 5000);
select pg_temp.line('61', '35', '', 'Ajuste de cables', 2000);
select is(pg_temp.job_costs('35'), array[12000, 5000, 17000, 17000]::numeric[],
  'la cotización pendiente reparte con la misma regla');

-- ============================================================================
-- Los cinco usan la misma regla
-- ============================================================================

select ok(
  strpos(pg_get_functiondef('public.recalculate_job_bike_costs()'::regprocedure),
         'job_line_cost_bucket') > 0
  and strpos(pg_get_functiondef('public.recalculate_mechanic_job_costs(uuid)'::regprocedure),
             'job_line_cost_bucket') > 0
  and strpos(pg_get_functiondef(
        'public.sync_invoice_items_to_job_workshop_internal(uuid)'::regprocedure),
        'job_line_cost_bucket') > 0,
  'la bici, el trabajo y la factura → el trabajo reparten con job_line_cost_bucket');
select ok(
  strpos(pg_get_functiondef('public.update_mechanic_job_costs()'::regprocedure),
         'recalculate_mechanic_job_costs') > 0
  and strpos(pg_get_functiondef('public.update_mechanic_job_costs()'::regprocedure),
             'total_cost') = 0,
  'el disparador de costos pide la cuenta del trabajo y no escribe el total por su cuenta');
select ok(
  strpos(pg_get_functiondef(
           'public.guard_canonical_mechanic_job_mode_transition()'::regprocedure),
         'coalesce(item.item_type, ''product''::text) <> ''service''::text') > 0
  or strpos(pg_get_functiondef(
           'public.guard_canonical_mechanic_job_mode_transition()'::regprocedure),
         'coalesce(item.item_type, ''product'') <> ''service''') > 0,
  'la cotización pendiente sigue con la regla: todo lo que no es servicio es repuesto');

select * from finish();
rollback;
