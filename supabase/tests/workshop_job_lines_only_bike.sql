-- Una línea del trabajo es de una bici (20261001200000).
--
-- El dueño vio un trabajo de una sola bici con sus productos en «General»
-- (PG-00142, 2026-10-01). Venían de escritores que no sabían de qué bici era
-- la línea: la factura → el trabajo emparejaba un ítem sin id sólo con líneas
-- de General, así que borraba la línea de la bici —y sus tareas, en cascada—
-- y la volvía a crear sin bici; un ítem nuevo de la factura nacía sin bici; y
-- el formulario dejaba en General lo agregado antes de elegir la bici.
--
-- - En un trabajo de una sola bici, toda línea es de ella, la escriba quien
--   la escriba; con varias bicis, o ninguna, General sigue siendo General.
-- - Cuando el trabajo queda con una sola bici, lo de General pasa a ella.
-- - La factura → el trabajo continúa la misma línea aunque el ítem no traiga
--   id, sin importar en qué bici esté, y le conserva la bici y las tareas.
-- - La recuperación de respaldos conoce los dos disparadores nuevos.
begin;

select no_plan();

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2a00000-0000-4000-8000-0000000000' || p_n)::uuid $$;

insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Taller una bici');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated',
   'una-bici@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);

insert into public.customers(id, tenant_id, name) values
  (pg_temp.id('10'), pg_temp.id('01'), 'Cliente una bici');
insert into public.bikes(id, tenant_id, customer_id, brand, model, is_active)
select pg_temp.id(n), pg_temp.id('01'), pg_temp.id('10'), 'Trek', 'Bici ' || n, true
  from unnest(array['21','22','23','24','25','26','27']) n;
insert into public.products(id, tenant_id, name, product_type) values
  (pg_temp.id('70'), pg_temp.id('01'), 'Cadena 1/2 X 3/32', 'product'),
  (pg_temp.id('71'), pg_temp.id('01'), 'Cámara 26 x 1.95', 'product'),
  (pg_temp.id('72'), pg_temp.id('01'), 'Mantención Maza', 'service');

insert into public.mechanic_jobs(id, tenant_id, customer_id, job_number,
                                 job_type, status)
select pg_temp.id(n), pg_temp.id('01'), pg_temp.id('10'), 'OB-' || n, 'service',
       'PENDIENTE'
  from unnest(array['31','32','33','34','35']) n;

-- La línea, como la escribe cualquiera: sin bici.
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

-- ============================================================================
-- La regla: en un trabajo de una sola bici, la línea es de ella
-- ============================================================================

insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
values (pg_temp.id('41'), pg_temp.id('01'), pg_temp.id('31'), pg_temp.id('21'), 0);
select pg_temp.line('51', '31', '70', 'Cadena 1/2 X 3/32', 9990);
select is(pg_temp.bike_of('51'), pg_temp.id('41'),
  'una línea escrita sin bici en un trabajo de una sola bici queda en ella');

update public.mechanic_job_items set job_bike_id = null where id = pg_temp.id('51');
select is(pg_temp.bike_of('51'), pg_temp.id('41'),
  'quitarle la bici no la deja en General mientras el trabajo tenga una sola');

insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
values
  (pg_temp.id('42'), pg_temp.id('01'), pg_temp.id('32'), pg_temp.id('22'), 0),
  (pg_temp.id('43'), pg_temp.id('01'), pg_temp.id('32'), pg_temp.id('23'), 1);
select pg_temp.line('52', '32', '71', 'Cámara 26 x 1.95', 4990);
select is(pg_temp.bike_of('52'), null,
  'con dos bicis la línea sin bici sigue en General, hasta que se asigne');

select pg_temp.line('53', '33', '71', 'Cámara 26 x 1.95', 4990);
select is(pg_temp.bike_of('53'), null,
  'sin bici en el trabajo (venta, presupuesto) la línea es de General');

-- ============================================================================
-- Cuando el trabajo queda con una sola bici, lo de General pasa a ella
-- ============================================================================

insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
values (pg_temp.id('44'), pg_temp.id('01'), pg_temp.id('33'), pg_temp.id('24'), 0);
select is(pg_temp.bike_of('53'), pg_temp.id('44'),
  'lo agregado antes de elegir la bici pasa a ella al recibirla');

insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
values (pg_temp.id('45'), pg_temp.id('01'), pg_temp.id('33'), pg_temp.id('25'), 1);
select pg_temp.line('54', '33', '70', 'Cadena 1/2 X 3/32', 9990, '45');
select pg_temp.line('55', '33', '72', 'Mantención Maza', 15000);
select ok(pg_temp.bike_of('53') = pg_temp.id('44') and pg_temp.bike_of('55') is null,
  'una segunda bici no mueve lo que ya era de la primera ni lo de General');

delete from public.mechanic_job_bikes where id = pg_temp.id('45');
select ok(
  not exists (select 1 from public.mechanic_job_items where id = pg_temp.id('54'))
  and pg_temp.bike_of('55') = pg_temp.id('44'),
  'al quitar una de dos bicis, sus líneas se van con ella y General pasa a la que queda');
select ok(
  (select subtotal = 15000 + 4990 from public.mechanic_job_bikes where id = pg_temp.id('44')),
  'el subtotal de la bici cuenta lo que pasó a ella');

-- ============================================================================
-- La factura → el trabajo continúa la misma línea aunque el ítem no traiga id
-- ============================================================================

insert into public.mechanic_job_bikes(id, tenant_id, job_id, bike_id, order_index)
values (pg_temp.id('46'), pg_temp.id('01'), pg_temp.id('34'), pg_temp.id('26'), 0);
select pg_temp.line('56', '34', '70', 'Cadena 1/2 X 3/32', 9990, '46');
select pg_temp.line('57', '34', '72', 'Mantención Maza', 15000, '46');
insert into public.mechanic_job_tasks(id, tenant_id, job_id, parent_item_id, task_name)
values (pg_temp.id('61'), pg_temp.id('01'), pg_temp.id('34'), pg_temp.id('57'),
        'Revisar juego del eje');

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
insert into public.sales_invoices(
  id, tenant_id, invoice_number, customer_id, customer_name, source,
  status, subtotal, net_amount, iva_amount, total, paid_amount, balance,
  tax_treatment, items
) values
  (pg_temp.id('81'), pg_temp.id('01'), 'FV-OB-81', pg_temp.id('10'),
   'Cliente una bici', 'mechanic_job', 'draft', 24990, 24990, 0, 24990, 0,
   24990, 'no_tax',
   jsonb_build_array(pg_temp.item('70', 'Cadena 1/2 X 3/32', 9990),
                     pg_temp.item('72', 'Mantención Maza', 15000))),
  (pg_temp.id('82'), pg_temp.id('01'), 'FV-OB-82', pg_temp.id('10'),
   'Cliente una bici', 'mechanic_job', 'draft', 9980, 9980, 0, 9980, 0,
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
  and (select count(*) from public.mechanic_job_items where job_id = pg_temp.id('34')) = 2,
  'un ítem sin id continúa la línea de la bici: ni se borra ni vuelve en General');
select ok(
  exists (select 1 from public.mechanic_job_tasks where id = pg_temp.id('61')),
  'la tarea de esa línea sigue viva (antes se iba en cascada con la línea)');

update public.sales_invoices
   set items = items || jsonb_build_array(pg_temp.item('71', 'Cámara 26 x 1.95', 4990))
 where id = pg_temp.id('81');
select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('81'))$$,
  'un ítem nuevo de la factura se sincroniza');
select ok(
  (select job_bike_id = pg_temp.id('46') from public.mechanic_job_items
    where job_id = pg_temp.id('34') and product_id = pg_temp.id('71')),
  'un ítem nuevo de la factura nace en la única bici, no en General');

-- Sin id y con otro precio: el mismo producto continúa su línea, con su
-- tarea (revisión de Codex: cambiar el precio borraba la línea y la tarea).
update public.sales_invoices
   set items = jsonb_build_array(
     pg_temp.item('70', 'Cadena 1/2 X 3/32', 9990),
     pg_temp.item('72', 'Mantención Maza', 18000),
     pg_temp.item('71', 'Cámara 26 x 1.95', 4990))
 where id = pg_temp.id('81');
select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('81'))$$,
  'un ítem sin id con otro precio se sincroniza');
select ok(
  (select unit_price = 18000 and job_bike_id = pg_temp.id('46')
     from public.mechanic_job_items where id = pg_temp.id('57'))
  and exists (select 1 from public.mechanic_job_tasks where id = pg_temp.id('61')),
  'la Mantención Maza sigue siendo la misma línea, con el precio nuevo y su tarea');

-- El mismo id dos veces (una línea duplicada en la factura): antes chocaba.
update public.sales_invoices
   set items = jsonb_build_array(
     pg_temp.item('70', 'Cadena 1/2 X 3/32', 9990, '56'),
     pg_temp.item('70', 'Cadena 1/2 X 3/32', 9990, '56'),
     pg_temp.item('72', 'Mantención Maza', 15000, '57'))
 where id = pg_temp.id('81');
select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('81'))$$,
  'la misma línea nombrada dos veces se sincroniza sin chocar');
select ok(
  (select count(*) = 2 and bool_and(job_bike_id = pg_temp.id('46'))
     from public.mechanic_job_items
    where job_id = pg_temp.id('34') and product_id = pg_temp.id('70'))
  and exists (select 1 from public.mechanic_job_items where id = pg_temp.id('56')),
  'la primera continúa su línea y la segunda es una cadena más, en la bici');

-- Dos bicis con la misma cámara cada una, y una factura sin ids.
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

update public.sales_invoices
   set items = items || jsonb_build_array(pg_temp.item('72', 'Mantención Maza', 15000))
 where id = pg_temp.id('82');
select lives_ok($$select public.sync_invoice_items_to_job(pg_temp.id('82'))$$,
  'un ítem nuevo en un trabajo de dos bicis se sincroniza');
select ok(
  (select job_bike_id is null from public.mechanic_job_items
    where job_id = pg_temp.id('35') and service_product_id = pg_temp.id('72')),
  'con dos bicis el ítem nuevo queda en General: no hay a cuál dárselo');

-- ============================================================================
-- Una línea sin dueño que vuelve con un respaldo antiguo
-- ============================================================================

-- La recuperación apaga la regla y devuelve la fila tal como se respaldó; aquí
-- se simula apagando el disparador para esa sola escritura.
alter table public.mechanic_job_items disable trigger trg_mechanic_job_items_only_bike;
select pg_temp.line('60', '31', '71', 'Cámara 26 x 1.95', 4990);
alter table public.mechanic_job_items enable trigger trg_mechanic_job_items_only_bike;
select is(pg_temp.bike_of('60'), null, 'el respaldo antiguo la devuelve sin bici');
update public.mechanic_job_items set unit_price = 5490 where id = pg_temp.id('60');
select is(pg_temp.bike_of('60'), pg_temp.id('41'),
  'el primer cambio cualquiera le da la única bici del trabajo');

-- ============================================================================
-- La recuperación de respaldos conoce los dos disparadores
-- ============================================================================

select is(public.workshop_restore_effects_review_internal('public.mechanic_job_items'::regclass),
  null, 'la recuperación revisó los disparadores de las líneas');
select is(public.workshop_restore_effects_review_internal('public.mechanic_job_bikes'::regclass),
  null, 'la recuperación revisó los disparadores de las bicis del trabajo');

select * from finish();
rollback;
