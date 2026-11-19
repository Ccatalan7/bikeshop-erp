begin;

select no_plan();

-- El feed de catálogo de un proveedor (20261119183500): MKR entregó un
-- endpoint con stock exacto, precios netos, descripción y fotos. La base
-- guarda cada lectura, decide qué cambió y no reescribe lo que sigue igual.
-- Sólo el horario puede iniciar una lectura, con un ticket de un solo uso.
-- Todo es sintético y se deshace al final.

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, owner_email, timezone, is_active) values
  ('c7a00000-0000-4000-8000-000000000001', 'Feed A', 'feed-a@example.invalid', 'America/Santiago', true),
  ('c7a00000-0000-4000-8000-000000000002', 'Feed B', 'feed-b@example.invalid', 'America/Santiago', true);

set local session_replication_role = replica;
insert into public.suppliers (id, tenant_id, name, is_active) values
  ('c7a00000-0000-4000-8000-000000000011', 'c7a00000-0000-4000-8000-000000000001', 'Proveedor con feed', true),
  ('c7a00000-0000-4000-8000-000000000012', 'c7a00000-0000-4000-8000-000000000002', 'Proveedor de otra tienda', true),
  ('c7a00000-0000-4000-8000-000000000013', 'c7a00000-0000-4000-8000-000000000001', 'Proveedor sin token', true);

create temp table feed_secret(secret_id uuid primary key);
insert into feed_secret
select vault.create_secret('tok-sintetico-123', 'supplier_feed_pgtap_a', 'pgTAP');
create temp table feed_secret_b(secret_id uuid primary key);
insert into feed_secret_b
select vault.create_secret('tok-de-otra-tienda', 'supplier_feed_pgtap_b', 'pgTAP');

insert into public.supplier_credentials (
  tenant_id, supplier_id, credential_kind, credential_key, label, vault_secret_id
)
select 'c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-000000000011',
  'api_token', 'catalog_feed', 'Endpoint de catálogo', secret_id
from feed_secret;
insert into public.supplier_credentials (
  tenant_id, supplier_id, credential_kind, credential_key, label, vault_secret_id
)
select 'c7a00000-0000-4000-8000-000000000002', 'c7a00000-0000-4000-8000-000000000012',
  'api_token', 'catalog_feed', 'Endpoint de catálogo', secret_id
from feed_secret_b;
set local session_replication_role = origin;

-- Las tareas de otras tiendas de la base local no cuentan en esta prueba.
update public.supplier_catalog_feeds set enabled = false;

insert into public.supplier_catalog_feeds (
  id, tenant_id, supplier_id, format, endpoint_template
) values
  ('c7a00000-0000-4000-8000-0000000000a1', 'c7a00000-0000-4000-8000-000000000001',
   'c7a00000-0000-4000-8000-000000000011', 'mkr_csv_v1', 'https://mkr.cl/api/endpoint?token={token}'),
  ('c7a00000-0000-4000-8000-0000000000b1', 'c7a00000-0000-4000-8000-000000000002',
   'c7a00000-0000-4000-8000-000000000012', 'mkr_csv_v1', 'https://mkr.cl/api/endpoint?token={token}'),
  ('c7a00000-0000-4000-8000-0000000000c1', 'c7a00000-0000-4000-8000-000000000001',
   'c7a00000-0000-4000-8000-000000000013', 'mkr_csv_v1', 'https://mkr.cl/api/endpoint?token={token}');

update public.supplier_catalog_feed_runtime
set enabled = true,
    endpoint = 'https://localhost.invalid/functions/v1/supplier-feed-sync';

-- Abre una lectura con un ticket conocido, como lo haría el horario.
create function pg_temp.open_run(p_feed uuid) returns uuid
language plpgsql as $$
declare
  v_run uuid;
  v_tenant uuid;
begin
  select tenant_id into v_tenant from public.supplier_catalog_feeds where id = p_feed;
  insert into public.supplier_catalog_feed_runs (tenant_id, feed_id, token_hash, lease_until)
  values (
    v_tenant, p_feed,
    encode(extensions.digest(repeat('ab', 32), 'sha256'), 'hex'),
    clock_timestamp() + interval '3 minutes'
  )
  returning id into v_run;
  perform public.redeem_supplier_catalog_feed_sync(v_run, repeat('ab', 32));
  return v_run;
end;
$$;

-- 1. Nada de esto se toca desde la API.
select is(
  (
    select count(*)
    from unnest(array[
      'public.supplier_catalog_feeds', 'public.supplier_catalog_feed_items',
      'public.supplier_catalog_feed_runs', 'public.supplier_catalog_feed_stock_events',
      'public.supplier_catalog_feed_runtime'
    ]) as relation(name)
    cross join unnest(array['anon', 'authenticated']) as grantee(name)
    cross join unnest(array[
      'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'
    ]) as privilege(name)
    where has_table_privilege(grantee.name, relation.name, privilege.name)
  ),
  0::bigint,
  'anon y authenticated no tienen ningún privilegio sobre las tablas del feed'
);
select is(
  (
    select count(*)
    from pg_class
    where oid in (
      'public.supplier_catalog_feeds'::regclass, 'public.supplier_catalog_feed_items'::regclass,
      'public.supplier_catalog_feed_runs'::regclass,
      'public.supplier_catalog_feed_stock_events'::regclass,
      'public.supplier_catalog_feed_runtime'::regclass
    )
      and relrowsecurity
  ),
  5::bigint,
  'las cinco tablas tienen RLS'
);
select is(
  (
    select count(*)
    from unnest(array[
      'public.fail_supplier_catalog_feed_run_v1(uuid,text,integer)',
      'public.dispatch_supplier_catalog_feed_syncs()',
      'public.redeem_supplier_catalog_feed_sync(uuid,text)',
      'public.apply_supplier_catalog_feed_rows_v1(uuid,jsonb)',
      'public.apply_supplier_catalog_feed_content_v1(uuid,jsonb)',
      'public.finish_supplier_catalog_feed_run_v1(uuid,text[],jsonb)'
    ]) as routine(signature)
    where has_function_privilege('service_role', routine.signature, 'EXECUTE')
      and not has_function_privilege('anon', routine.signature, 'EXECUTE')
      and not has_function_privilege('authenticated', routine.signature, 'EXECUTE')
  ),
  6::bigint,
  'las seis funciones son sólo del servicio'
);
select throws_ok(
  $$insert into public.supplier_catalog_feeds (tenant_id, supplier_id, feed_key, format, endpoint_template)
    values ('c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-000000000011',
            'otro', 'mkr_csv_v1', 'https://mkr.cl/api/endpoint?token=escrito')$$,
  '23514', null,
  'la dirección no puede llevar el token escrito: va con {token}'
);
select throws_ok(
  $$insert into public.supplier_catalog_feeds (tenant_id, supplier_id, feed_key, format, endpoint_template)
    values ('c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-000000000011',
            'otro', 'mkr_csv_v1', 'http://mkr.cl/api/endpoint?token={token}')$$,
  '23514', null,
  'la dirección es https'
);

-- 2. El horario entrega un ticket por feed con token, y uno solo.
select is(
  public.dispatch_supplier_catalog_feed_syncs(), 2,
  'se despacha una lectura por cada feed activo con su token (el feed sin token no)'
);
select is(
  (select count(*) from public.supplier_catalog_feed_runs
   where feed_id = 'c7a00000-0000-4000-8000-0000000000c1'),
  0::bigint,
  'el feed sin token no recibe ticket'
);
select is(
  (select count(*) from net.http_request_queue
   where url = 'https://localhost.invalid/functions/v1/supplier-feed-sync'),
  2::bigint,
  'cada ticket se envía a la función'
);
select is(
  public.dispatch_supplier_catalog_feed_syncs(), 0,
  'con una lectura en curso no se despacha otra'
);
select ok(
  (select bool_and(status = 'dispatched' and token_hash ~ '^[0-9a-f]{64}$'
                   and lease_until > clock_timestamp())
   from public.supplier_catalog_feed_runs),
  'el ticket se guarda sólo como huella, con plazo'
);

-- 3. El ticket se canjea una vez y entrega la dirección y el token.
update public.supplier_catalog_feed_runs
set token_hash = encode(extensions.digest(repeat('cd', 32), 'sha256'), 'hex')
where feed_id = 'c7a00000-0000-4000-8000-0000000000a1';
create temp table first_run as
select id from public.supplier_catalog_feed_runs
where feed_id = 'c7a00000-0000-4000-8000-0000000000a1';

select is(
  public.redeem_supplier_catalog_feed_sync((select id from first_run), repeat('ee', 32)),
  null::jsonb,
  'un ticket equivocado no abre nada'
);
select is(
  (select status from public.supplier_catalog_feed_runs where id = (select id from first_run)),
  'dispatched',
  'y la lectura sigue esperando su ticket'
);
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok(
  format($$select public.redeem_supplier_catalog_feed_sync(%L, repeat('cd', 32))$$,
         (select id from first_run)),
  '42501', null,
  'sólo el servicio canjea un ticket'
);
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(
  public.redeem_supplier_catalog_feed_sync((select id from first_run), repeat('cd', 32)),
  jsonb_build_object(
    'run_id', (select id from first_run),
    'format', 'mkr_csv_v1',
    'endpoint_template', 'https://mkr.cl/api/endpoint?token={token}',
    'token', 'tok-sintetico-123'
  ),
  'el ticket correcto entrega formato, dirección y el token de Vault'
);
select is(
  (select status || '/' || coalesce(token_hash, 'sin huella')
   from public.supplier_catalog_feed_runs where id = (select id from first_run)),
  'running/sin huella',
  'la lectura queda en curso y el ticket desaparece'
);
select is(
  public.redeem_supplier_catalog_feed_sync((select id from first_run), repeat('cd', 32)),
  null::jsonb,
  'el mismo ticket no sirve dos veces'
);

-- 4. Primera lectura: todo es nuevo y todo pide su contenido.
select is(
  public.apply_supplier_catalog_feed_rows_v1(
    (select id from first_run),
    '[["S1","0001","7800000000011",10,"100.00","100.00","70.00","150.00","h1"],
      ["S2",null,null,0,"200.00",null,null,"300.00","h2"],
      ["S3",null,null,4,"50.00",null,null,"80.00","h3"],
      ["S5",null,null,60,"10.00",null,null,"15.00","h5"],
      ["S5",null,null,61,"10.00",null,null,"15.00","h5"],
      ["",null,null,9,"1.00",null,null,"2.00","hx"]]'::jsonb
  ),
  '{"rows":4,"new":4,"stock_changes":0,"price_changes":0,"need_content":["S1","S2","S3","S5"]}'::jsonb,
  'cuatro códigos nuevos (el repetido vale por su última línea y el vacío se ignora)'
);
select results_eq(
  $$select supplier_sku, tenant_id::text, supplier_id::text, stock, price_net, price_offer_net,
           suggested_retail_net, barcode, is_listed, content_hash
    from public.supplier_catalog_feed_items
    where feed_id = 'c7a00000-0000-4000-8000-0000000000a1'
    order by supplier_sku collate "C"$$,
  $$values
    ('S1', 'c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-000000000011',
     10, 100.00::numeric(14,2), 70.00::numeric(14,2), 150.00::numeric(14,2), '7800000000011', true, null::text),
    ('S2', 'c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-000000000011',
     0, 200.00, null, 300.00, null, true, null),
    ('S3', 'c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-000000000011',
     4, 50.00, null, 80.00, null, true, null),
    ('S5', 'c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-000000000011',
     61, 10.00, null, 15.00, null, true, null)$$,
  'quedan con su tienda, su proveedor, stock exacto y precios netos'
);
select is(
  (select count(*) from public.supplier_catalog_feed_stock_events),
  0::bigint,
  'ver un producto por primera vez no es un movimiento de stock'
);
select is(
  public.apply_supplier_catalog_feed_content_v1(
    (select id from first_run),
    '[["S1","Cadena 8 v","KMC","<p>Para 8 velocidades</p>",
       ["https://cdn.example/s1-1.jpg","http://sin-https.example/s1.jpg","https://cdn.example/s1-2.jpg"],"h1"],
      ["S2","Candado U","On Guard",null,[],"h2"],
      ["S5","Eje sellado","VP Components","<p>68 mm</p>",["https://cdn.example/s5.jpg"],"h5"],
      ["NO-EXISTE","X","Y",null,[],"hz"]]'::jsonb
  ),
  3,
  'se guarda el contenido de los códigos que existen'
);
select results_eq(
  $$select supplier_sku, name, brand, description_html, photo_urls, content_hash
    from public.supplier_catalog_feed_items
    where feed_id = 'c7a00000-0000-4000-8000-0000000000a1' and supplier_sku in ('S1', 'S2')
    order by supplier_sku collate "C"$$,
  $$values
    ('S1', 'Cadena 8 v', 'KMC', '<p>Para 8 velocidades</p>',
     array['https://cdn.example/s1-1.jpg', 'https://cdn.example/s1-2.jpg'], 'h1'),
    ('S2', 'Candado U', 'On Guard', null, '{}'::text[], 'h2')$$,
  'nombre, marca, descripción y sólo las fotos https'
);
select throws_ok(
  format($$select public.finish_supplier_catalog_feed_run_v1(%L, array['S1','S2','S3'])$$,
         (select id from first_run)),
  '22023', null,
  'cerrar con menos códigos que los guardados es un error del lector'
);
select is(
  public.finish_supplier_catalog_feed_run_v1(
    (select id from first_run), array['S1', 'S2', 'S3', 'S5'],
    '{"http_status":200,"bytes":1234,"duration_ms":900}'::jsonb
  ),
  '{"status":"ok","rows":4,"listed":4,"in_stock":3,"delisted":0}'::jsonb,
  'la lectura completa se cierra bien'
);
select results_eq(
  $$select run.status, run.row_count, run.new_count, run.content_changes, run.http_status,
           run.bytes, run.duration_ms, feed.last_status, feed.listed_count, feed.in_stock_count,
           feed.consecutive_failures, feed.last_ok_at is not null, feed.last_run_id = run.id
    from public.supplier_catalog_feed_runs run
    join public.supplier_catalog_feeds feed on feed.id = run.feed_id
    where run.id = (select id from first_run)$$,
  $$values ('ok', 4, 4, 3, 200, 1234::bigint, 900, 'ok', 4, 3, 0, true, true)$$,
  'la lectura y su feed dicen cómo quedó'
);
select throws_ok(
  format($$select public.apply_supplier_catalog_feed_rows_v1(%L, '[["S1",null,null,1,null,null,null,null,"h1"]]'::jsonb)$$,
         (select id from first_run)),
  '55000', null,
  'una lectura cerrada no recibe más filas'
);

-- 5. Segunda lectura: sólo se escribe lo que cambió.
create temp table untouched as
select xmin::text as row_version
from public.supplier_catalog_feed_items
where feed_id = 'c7a00000-0000-4000-8000-0000000000a1' and supplier_sku = 'S5';
create temp table second_run as
select pg_temp.open_run('c7a00000-0000-4000-8000-0000000000a1') as id;

select is(
  public.apply_supplier_catalog_feed_rows_v1(
    (select id from second_run),
    '[["S1","0001","7800000000011",7,"100.00","100.00","70.00","150.00","h1"],
      ["S2",null,null,0,"210.00",null,null,"300.00","h2"],
      ["S5",null,null,61,"10.00",null,null,"15.00","h5"],
      ["S4",null,null,3,"999.00",null,null,"1500.00","h4"]]'::jsonb
  ),
  '{"rows":4,"new":1,"stock_changes":1,"price_changes":1,"need_content":["S4"]}'::jsonb,
  'un stock que bajó, un precio que cambió, uno igual y uno nuevo: sólo el nuevo pide contenido'
);
select results_eq(
  $$select supplier_sku, stock_before, stock_after
    from public.supplier_catalog_feed_stock_events
    where feed_id = 'c7a00000-0000-4000-8000-0000000000a1'$$,
  $$values ('S1', 10, 7)$$,
  'el movimiento de stock queda con su antes y su después'
);
select ok(
  (select stock = 7 and stock_changed_at is not null and price_changed_at is null
   from public.supplier_catalog_feed_items
   where feed_id = 'c7a00000-0000-4000-8000-0000000000a1' and supplier_sku = 'S1'),
  'el stock cambió y el precio no'
);
select ok(
  (select price_net = 210.00 and price_changed_at is not null and stock_changed_at is null
   from public.supplier_catalog_feed_items
   where feed_id = 'c7a00000-0000-4000-8000-0000000000a1' and supplier_sku = 'S2'),
  'el precio cambió y el stock no'
);
select is(
  (select xmin::text from public.supplier_catalog_feed_items
   where feed_id = 'c7a00000-0000-4000-8000-0000000000a1' and supplier_sku = 'S5'),
  (select row_version from untouched),
  'la fila que no cambió no se volvió a escribir'
);
select is(
  public.finish_supplier_catalog_feed_run_v1(
    (select id from second_run), array['S1', 'S2', 'S5', 'S4']
  ),
  '{"status":"ok","rows":4,"listed":4,"in_stock":3,"delisted":1}'::jsonb,
  'lo que el archivo ya no trae deja de estar listado'
);
select ok(
  (select not is_listed and delisted_at is not null and stock = 4
   from public.supplier_catalog_feed_items
   where feed_id = 'c7a00000-0000-4000-8000-0000000000a1' and supplier_sku = 'S3'),
  'el producto que desapareció queda marcado, con su último stock'
);

-- 6. Un producto que vuelve, vuelve a estar listado.
create temp table third_run as
select pg_temp.open_run('c7a00000-0000-4000-8000-0000000000a1') as id;
select is(
  public.apply_supplier_catalog_feed_rows_v1(
    (select id from third_run),
    '[["S1","0001","7800000000011",7,"100.00","100.00","70.00","150.00","h1"],
      ["S2",null,null,0,"210.00",null,null,"300.00","h2"],
      ["S3",null,null,4,"50.00",null,null,"80.00","h3"],
      ["S4",null,null,3,"999.00",null,null,"1500.00","h4"],
      ["S5",null,null,61,"10.00",null,null,"15.00","h5"]]'::jsonb
  ) - 'need_content',
  '{"rows":5,"new":0,"stock_changes":0,"price_changes":0}'::jsonb,
  'nada cambió salvo el que volvió'
);
select ok(
  (select is_listed and delisted_at is null
   from public.supplier_catalog_feed_items
   where feed_id = 'c7a00000-0000-4000-8000-0000000000a1' and supplier_sku = 'S3'),
  'el que volvió está listado otra vez'
);
select is(
  (public.finish_supplier_catalog_feed_run_v1(
    (select id from third_run), array['S1', 'S2', 'S3', 'S4', 'S5']
  ))->>'status',
  'ok',
  'tercera lectura cerrada'
);

-- 7. Un archivo con menos de la mitad no es el catálogo achicándose.
insert into public.supplier_catalog_feed_items (
  tenant_id, feed_id, supplier_id, supplier_sku, stock
)
select 'c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-0000000000a1',
  'c7a00000-0000-4000-8000-000000000011', 'R' || lpad(number::text, 4, '0'), 5
from generate_series(1, 300) as series(number);
create temp table feed_before_suspect as
select last_ok_at, consecutive_failures
from public.supplier_catalog_feeds where id = 'c7a00000-0000-4000-8000-0000000000a1';
create temp table short_run as
select pg_temp.open_run('c7a00000-0000-4000-8000-0000000000a1') as id;
select is(
  (public.apply_supplier_catalog_feed_rows_v1(
    (select id from short_run),
    '[["S1","0001","7800000000011",7,"100.00","100.00","70.00","150.00","h1"]]'::jsonb
  ))->>'rows',
  '1',
  'llega una sola fila'
);
select is(
  public.finish_supplier_catalog_feed_run_v1((select id from short_run), array['S1']),
  '{"status":"suspect","rows":1,"listed":305}'::jsonb,
  'la lectura se cierra como sospechosa'
);
select results_eq(
  $$select run.status, run.error_code, feed.last_status,
           feed.consecutive_failures - before.consecutive_failures,
           feed.last_ok_at = before.last_ok_at,
           (select count(*) from public.supplier_catalog_feed_items item
            where item.feed_id = feed.id and item.is_listed)
    from public.supplier_catalog_feed_runs run
    join public.supplier_catalog_feeds feed on feed.id = run.feed_id
    cross join feed_before_suspect before
    where run.id = (select id from short_run)$$,
  $$values ('suspect', 'too_few_rows', 'suspect', 1, true, 305::bigint)$$,
  'no deslista nada, el feed no queda más fresco y cuenta una falla'
);

-- 8. Una lectura que falla queda con su código, y una que nunca vuelve se cierra sola.
create temp table failed_run as
select pg_temp.open_run('c7a00000-0000-4000-8000-0000000000a1') as id;
select ok(
  public.fail_supplier_catalog_feed_run_v1((select id from failed_run), 'HTTP 500!', 500),
  'el lector cierra una lectura que no pudo terminar'
);
select results_eq(
  $$select status, error_code, http_status, finished_at is not null
    from public.supplier_catalog_feed_runs where id = (select id from failed_run)$$,
  $$values ('failed', 'http_500_', 500, true)$$,
  'queda fallida con un código corto'
);
select ok(
  not public.fail_supplier_catalog_feed_run_v1((select id from failed_run), 'otra_vez'),
  'una lectura cerrada no se vuelve a cerrar'
);
select is(
  (select consecutive_failures from public.supplier_catalog_feeds
   where id = 'c7a00000-0000-4000-8000-0000000000a1'),
  (select consecutive_failures + 2 from feed_before_suspect),
  'cada falla se cuenta en su feed'
);

create temp table lost_run as
select pg_temp.open_run('c7a00000-0000-4000-8000-0000000000a1') as id;
update public.supplier_catalog_feed_runs
set lease_until = clock_timestamp() - interval '1 second'
where id = (select id from lost_run);
select throws_ok(
  format($$select public.apply_supplier_catalog_feed_rows_v1(%L, '[]'::jsonb)$$,
         (select id from lost_run)),
  '55000', null,
  'pasado su plazo, una lectura no recibe filas'
);
-- La otra tienda sigue con su ticket del principio: sólo se despacha el feed A.
update public.supplier_catalog_feed_runs
set lease_until = clock_timestamp() + interval '3 minutes'
where feed_id = 'c7a00000-0000-4000-8000-0000000000b1';
select is(
  public.dispatch_supplier_catalog_feed_syncs(), 1,
  'el horario cierra la lectura perdida y despacha otra'
);
select results_eq(
  $$select status, error_code from public.supplier_catalog_feed_runs
    where id = (select id from lost_run)$$,
  $$values ('failed', 'reader_timeout')$$,
  'la lectura que nunca volvió queda fallida'
);

-- 9. Cada tienda con lo suyo.
update public.supplier_catalog_feed_runs
set token_hash = encode(extensions.digest(repeat('ab', 32), 'sha256'), 'hex')
where feed_id = 'c7a00000-0000-4000-8000-0000000000b1' and status = 'dispatched';
create temp table other_run as
select id from public.supplier_catalog_feed_runs
where feed_id = 'c7a00000-0000-4000-8000-0000000000b1' and status = 'dispatched';
select is(
  (public.redeem_supplier_catalog_feed_sync((select id from other_run), repeat('ab', 32)))->>'token',
  'tok-de-otra-tienda',
  'el ticket de otra tienda entrega su propio token'
);
select is(
  (public.apply_supplier_catalog_feed_rows_v1(
    (select id from other_run),
    '[["S1",null,null,99,"1.00",null,null,"2.00","otro"]]'::jsonb
  ))->>'new',
  '1',
  'el mismo código en otra tienda es otro producto'
);
select results_eq(
  $$select tenant_id::text, stock from public.supplier_catalog_feed_items
    where supplier_sku = 'S1' order by tenant_id$$,
  $$values ('c7a00000-0000-4000-8000-000000000001', 7),
           ('c7a00000-0000-4000-8000-000000000002', 99)$$,
  'y no toca el de la primera'
);

-- 10. Un feed apagado, o sin token, no se lee.
update public.supplier_catalog_feed_runs
set status = 'failed', finished_at = clock_timestamp()
where status in ('dispatched', 'running');
update public.supplier_catalog_feeds set enabled = false
where id = 'c7a00000-0000-4000-8000-0000000000b1';
create temp table disabled_run(id uuid);
with created as (
  insert into public.supplier_catalog_feed_runs (tenant_id, feed_id, token_hash, lease_until)
  values (
    'c7a00000-0000-4000-8000-000000000002', 'c7a00000-0000-4000-8000-0000000000b1',
    encode(extensions.digest(repeat('ab', 32), 'sha256'), 'hex'),
    clock_timestamp() + interval '3 minutes'
  )
  returning id
)
insert into disabled_run select id from created;
select is(
  public.redeem_supplier_catalog_feed_sync((select id from disabled_run), repeat('ab', 32)),
  null::jsonb,
  'el ticket de un feed apagado no entrega nada'
);
select is(
  (select status || '/' || error_code from public.supplier_catalog_feed_runs
   where id = (select id from disabled_run)),
  'failed/feed_disabled',
  'y su lectura queda fallida'
);
delete from public.supplier_credentials
where supplier_id = 'c7a00000-0000-4000-8000-000000000011';
create temp table tokenless_run(id uuid);
with created as (
  insert into public.supplier_catalog_feed_runs (tenant_id, feed_id, token_hash, lease_until)
  values (
    'c7a00000-0000-4000-8000-000000000001', 'c7a00000-0000-4000-8000-0000000000a1',
    encode(extensions.digest(repeat('ab', 32), 'sha256'), 'hex'),
    clock_timestamp() + interval '3 minutes'
  )
  returning id
)
insert into tokenless_run select id from created;
select is(
  public.redeem_supplier_catalog_feed_sync((select id from tokenless_run), repeat('ab', 32)),
  null::jsonb,
  'sin token guardado, el ticket no entrega nada'
);
select is(
  (select status || '/' || error_code from public.supplier_catalog_feed_runs
   where id = (select id from tokenless_run)),
  'failed/credential_missing',
  'y la lectura dice que falta el token'
);
select is(
  public.dispatch_supplier_catalog_feed_syncs(), 0,
  'sin token y con el otro feed apagado, el horario no despacha nada'
);
update public.supplier_catalog_feed_runtime set enabled = false;
update public.supplier_catalog_feeds set enabled = true
where id = 'c7a00000-0000-4000-8000-0000000000b1';
select is(
  public.dispatch_supplier_catalog_feed_syncs(), 0,
  'con el interruptor apagado el horario no despacha nada'
);

select * from finish();
rollback;
