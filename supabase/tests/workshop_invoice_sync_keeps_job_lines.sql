-- La factura → el trabajo continúa la misma línea (20261001200000).
--
-- El dueño vio un trabajo de una sola bici con sus productos en «General»
-- (PG-00142, 2026-10-01). General es a propósito —lo que el cliente compra
-- aparte, aunque el trabajo tenga una sola bici—, pero la sincronización de la
-- factura metía ahí líneas de la bici: emparejaba un ítem sin id sólo con
-- líneas de General, así que borraba la línea de la bici —y sus tareas, en
-- cascada— y la volvía a crear sin bici.
--
-- - Un ítem sin id continúa su línea esté donde esté, en la bici o en
--   General, y le conserva el lugar y las tareas.
-- - Con otro precio sin id, el mismo producto continúa su línea.
-- - El mismo id repetido ya no aborta la sincronización.
-- - Un ítem nuevo de la factura nace en General: quien edita la factura no
--   dice de qué bici es.
begin;

select no_plan();

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2a00000-0000-4000-8000-0000000000' || p_n)::uuid $$;

insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Taller factura');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated',
   'factura-lineas@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);

insert into public.customers(id, tenant_id, name) values
  (pg_temp.id('10'), pg_temp.id('01'), 'Cliente factura');
insert into public.bikes(id, tenant_id, customer_id, brand, model, is_active)
select pg_temp.id(n), pg_temp.id('01'), pg_temp.id('10'), 'Trek', 'Bici ' || n, true
  from unnest(array['26','27','23']) n;
insert into public.products(id, tenant_id, name, product_type) values
  (pg_temp.id('70'), pg_temp.id('01'), 'Cadena 1/2 X 3/32', 'product'),
  (pg_temp.id('71'), pg_temp.id('01'), 'Cámara 26 x 1.95', 'product'),
  (pg_temp.id('72'), pg_temp.id('01'), 'Mantención Maza', 'service'),
  (pg_temp.id('73'), pg_temp.id('01'), 'Casco urbano', 'product');

insert into public.mechanic_jobs(id, tenant_id, customer_id, job_number,
                                 job_type, status)
select pg_temp.id(n), pg_temp.id('01'), pg_temp.id('10'), 'FS-' || n, 'service',
       'PENDIENTE'
  from unnest(array['34','35']) n;

create function pg_temp.line(p_id text, p_job text, p_product text,
                             p_name text, p_price numeric,
                             p_job_bike text default null)
returns void language sql as $$
  insert into public.mechanic_job_items(id, tenant_id, job_id, job_bike_id,
    product_id, service_product_id, product_name, quantity, unit_price,
    item_type)
  values (pg_temp.id(p_id), pg_temp.id('01'), pg_temp.id(p_job),
    case when p_job_bike is not null then pg_temp.id(p_job_bike) end,
    case when p_product <> '72' then pg_temp.id(p_product) end,
    case when p_product = '72' then pg_temp.id(p_product) end,
    p_name, 1, p_price,
    case when p_product = '72' then 'service' else 'product' end)
$$;
create function pg_temp.bike_of(p_line text) returns uuid language sql as $$
  select job_bike_id from public.mechanic_job_items where id = pg_temp.id(p_line)
$$;
-- Una factura escrita como las de marzo y abril: ítems sin id ni bici.
create function pg_temp.item(p_product text, p_name text, p_price numeric,
                             p_id text default null)
returns jsonb language sql as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', case when p_id is not null then pg_temp.id(p_id) end,
    'product_id', pg_temp.id(p_product),
    'product_name', p_name,
    'item_type', case when p_product = '72' then 'service' else 'product' end,
    'is_service', p_product = '72',
    'quantity', 1, 'unit_price', p_price, 'line_total', p_price))
$$;

-- ============================================================================
-- Una bici: la cadena y la mantención en ella, el casco aparte en General
-- ============================================================================

insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
values (pg_temp.id('46'), pg_temp.id('01'), pg_temp.id('34'), pg_temp.id('26'), 0);
select pg_temp.line('56', '34', '70', 'Cadena 1/2 X 3/32', 9990, '46');
select pg_temp.line('57', '34', '72', 'Mantención Maza', 15000, '46');
select pg_temp.line('55', '34', '73', 'Casco urbano', 29990);
insert into public.mechanic_job_tasks(id, tenant_id, job_id, parent_item_id, task_name)
values (pg_temp.id('61'), pg_temp.id('01'), pg_temp.id('34'), pg_temp.id('57'),
        'Revisar juego del eje');

insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, customer_name, source,
  status, subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values
  (pg_temp.id('81'), pg_temp.id('01'), 'FV-FS-81', pg_temp.id('10'),
   'Cliente factura', 'mechanic_job', 'draft', 54980, 54980, 0, 54980, 0,
   54980, 'no_tax',
   jsonb_build_array(pg_temp.item('70', 'Cadena 1/2 X 3/32', 9990),
                     pg_temp.item('72', 'Mantención Maza', 15000),
                     pg_temp.item('73', 'Casco urbano', 29990))),
  (pg_temp.id('82'), pg_temp.id('01'), 'FV-FS-82', pg_temp.id('10'),
   'Cliente factura', 'mechanic_job', 'draft', 9980, 9980, 0, 9980, 0,
   9980, 'no_tax',
   jsonb_build_array(pg_temp.item('71', 'Cámara 26 x 1.95', 4990),
                     pg_temp.item('71', 'Cámara 26 x 1.95', 4990)));

select set_config('app.syncing_job_to_invoice', 'true', true);
update public.mechanic_jobs
   set invoice_id = case id when pg_temp.id('34') then pg_temp.id('81')
                            else pg_temp.id('82') end,
       is_invoiced = true
 where id in (pg_temp.id('34'), pg_temp.id('35'));
select set_config('app.syncing_job_to_invoice', '', true);

select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('81'))$$,
  'la factura con ítems sin id se sincroniza');
select ok(
  pg_temp.bike_of('56') = pg_temp.id('46') and pg_temp.bike_of('57') = pg_temp.id('46')
  and (select count(*) from public.mechanic_job_items where job_id = pg_temp.id('34')) = 3,
  'un ítem sin id continúa la línea de la bici: ni se borra ni vuelve en General');
select is(pg_temp.bike_of('55'), null,
  'el casco que el cliente compró aparte sigue en General, con una sola bici');
select ok(
  exists (select 1 from public.mechanic_job_tasks where id = pg_temp.id('61')),
  'la tarea de la mantención sigue viva (antes se iba en cascada con la línea)');

update public.sales_invoices
   set items = items || jsonb_build_array(pg_temp.item('71', 'Cámara 26 x 1.95', 4990))
 where id = pg_temp.id('81');
select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('81'))$$,
  'un ítem nuevo de la factura se sincroniza');
select ok(
  (select job_bike_id is null from public.mechanic_job_items
    where job_id = pg_temp.id('34') and product_id = pg_temp.id('71')),
  'un ítem nuevo de la factura nace en General: la factura no dice de qué bici es');

-- Sin id y con otro precio: el mismo producto continúa su línea, con su
-- tarea (revisión de Codex: cambiar el precio borraba la línea y la tarea).
update public.sales_invoices
   set items = jsonb_build_array(
     pg_temp.item('70', 'Cadena 1/2 X 3/32', 9990),
     pg_temp.item('72', 'Mantención Maza', 18000),
     pg_temp.item('73', 'Casco urbano', 29990),
     pg_temp.item('71', 'Cámara 26 x 1.95', 4990))
 where id = pg_temp.id('81');
select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('81'))$$,
  'un ítem sin id con otro precio se sincroniza');
select ok(
  (select unit_price = 18000 and job_bike_id = pg_temp.id('46')
     from public.mechanic_job_items where id = pg_temp.id('57'))
  and exists (select 1 from public.mechanic_job_tasks where id = pg_temp.id('61')),
  'la mantención sigue siendo la misma línea, con el precio nuevo, su bici y su tarea');

-- El mismo id dos veces (una línea duplicada en la factura): antes abortaba.
update public.sales_invoices
   set items = jsonb_build_array(
     pg_temp.item('70', 'Cadena 1/2 X 3/32', 9990, '56'),
     pg_temp.item('70', 'Cadena 1/2 X 3/32', 9990, '56'),
     pg_temp.item('72', 'Mantención Maza', 18000, '57'),
     pg_temp.item('73', 'Casco urbano', 29990, '55'))
 where id = pg_temp.id('81');
select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('81'))$$,
  'la misma línea nombrada dos veces se sincroniza sin abortar');
select ok(
  (select count(*) = 2 from public.mechanic_job_items
    where job_id = pg_temp.id('34') and product_id = pg_temp.id('70'))
  and pg_temp.bike_of('56') = pg_temp.id('46'),
  'la primera continúa su línea en la bici y la segunda es una cadena más');

-- ============================================================================
-- Dos bicis con la misma cámara cada una, y una factura sin ids
-- ============================================================================

insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
values
  (pg_temp.id('47'), pg_temp.id('01'), pg_temp.id('35'), pg_temp.id('27'), 0),
  (pg_temp.id('48'), pg_temp.id('01'), pg_temp.id('35'), pg_temp.id('23'), 1);
select pg_temp.line('58', '35', '71', 'Cámara 26 x 1.95', 4990, '47');
select pg_temp.line('59', '35', '71', 'Cámara 26 x 1.95', 4990, '48');
select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('82'))$$,
  'dos ítems iguales sin id se sincronizan');
select ok(
  pg_temp.bike_of('58') = pg_temp.id('47') and pg_temp.bike_of('59') = pg_temp.id('48'),
  'cada cámara sigue en su bici (antes las dos se borraban y volvían en General)');

select * from finish();
rollback;
