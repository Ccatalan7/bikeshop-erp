-- Restaurar un respaldo cuando falta el archivo de un adjunto o una foto
-- (20260929030000; cierre del Master Schema, 2026-09-29).
--
-- Con respaldos reales (`create_backup`) y la restauración real
-- (`restore_backup`, como la llama la app):
-- - un taller con datos que el respaldo no guarda (los cambios de estado de
--   sus trabajos, la categoría de gastos que trae al crearse): no se restaura
--   nada, se dice qué se perdería, y la consulta previa dice lo mismo;
-- - sin esos datos (se sacan del taller de prueba para llegar a la
--   restauración), archivos que están, que faltan, de otros buckets, en varios trabajos y
--   bicis (también la foto principal): se restaura todo y se omite sólo la URL
--   cuyo archivo falta, con un informe por registro, en la respuesta y en el
--   respaldo;
-- - el respaldo no cambia y no quedan copias de trabajo;
-- - sin nada que falte, el informe dice que no se omitió nada;
-- - una restauración que falla por otra cosa no deja nada a medias ni informe.
begin;

select no_plan();

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2890000-0000-4000-8000-0000000000' || p_n)::uuid $$;

create or replace function pg_temp.url(p_bucket text, p_path text)
returns text
language sql
as $$
  select 'https://ref.supabase.co/storage/v1/object/public/' || p_bucket
    || '/' || p_path
$$;

-- Como la función del servidor que llama la app con la llave de servicio (y
-- como el administrador del taller: la misma función).
insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Taller respaldos');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated',
   'respaldos@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'service_role')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
select set_config('request.jwt.claim.role', 'service_role', true);
insert into public.customers(id, tenant_id, name) values
  (pg_temp.id('10'), pg_temp.id('01'), 'Cliente respaldos');

-- El taller de prueba no usa terminales de pago: se sueltan las que trae al
-- crearse (los medios de pago y las terminales se apuntan entre sí, y el
-- respaldo no guarda las terminales). Reinsertar un medio de pago con tarjeta
-- las vuelve a sembrar, así que también se apaga esa siembra en esta prueba.
alter table public.payment_methods disable trigger zz_seed_terminal_from_legacy_card;
set local session_replication_role = replica;
update public.payment_methods set terminal_profile_id = null
 where tenant_id = pg_temp.id('01');
delete from public.payment_terminal_terms
 where payment_method_id in (select id from public.payment_methods
                              where tenant_id = pg_temp.id('01'));
delete from public.payment_terminal_profiles where tenant_id = pg_temp.id('01');
set local session_replication_role = origin;

-- Los archivos: todos están cuando se toma el respaldo.
insert into storage.objects(bucket_id, name) values
  ('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/presupuesto.pdf'),
  ('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/perdida.pdf'),
  ('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/foto.jpg'),
  ('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/principal.jpg'),
  ('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/lateral.jpg');

insert into public.bikes(id, tenant_id, customer_id, brand, model,
                         image_url, image_urls) values
  (pg_temp.id('20'), pg_temp.id('01'), pg_temp.id('10'), 'Trek', 'Marlin 5',
   pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/principal.jpg'),
   array[pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/principal.jpg'),
         pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/lateral.jpg')]),
  (pg_temp.id('21'), pg_temp.id('01'), pg_temp.id('10'), 'Oxford', 'Orion',
   null, '{}'::text[]);

insert into public.mechanic_jobs(id, tenant_id, customer_id, bike_id,
                                 job_number, job_type, status, image_urls) values
  (pg_temp.id('50'), pg_temp.id('01'), pg_temp.id('10'), pg_temp.id('20'),
   'RB-50', 'service', 'PENDIENTE',
   array[pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/presupuesto.pdf'),
         pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/perdida.pdf'),
         pg_temp.url('vinabike-assets', 'mechanic_jobs/cliente/job_1.jpg')]),
  (pg_temp.id('51'), pg_temp.id('01'), pg_temp.id('10'), pg_temp.id('21'),
   'RB-51', 'service', 'PENDIENTE',
   array[pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/foto.jpg')]);

-- Saca del taller de prueba lo que el respaldo no guarda y depende de lo que
-- la restauración borraría: la categoría de gastos que trae al crearse y los
-- cambios de estado que nacen con cada trabajo.
-- Sin los disparadores de guardia, sólo en esta limpieza.
create or replace function pg_temp.clear_uncovered()
returns void
language plpgsql
as $$
begin
  set local session_replication_role = replica;
  delete from public.mechanic_job_status_transitions
   where job_id in (select id from public.mechanic_jobs
                     where tenant_id = pg_temp.id('01'));
  delete from public.expense_categories where tenant_id = pg_temp.id('01');
  set local session_replication_role = origin;
end;
$$;

create temporary table results (label text primary key, result jsonb);
insert into results
select 'respaldo', public.create_backup(pg_temp.id('01'), 'Antes de perder archivos', 'manual', null);
select ok((select (result ->> 'success')::boolean from results where label = 'respaldo'),
  'el respaldo se toma con todos los archivos');

-- Después faltan dos archivos: un adjunto del trabajo y la foto principal.
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
 where (bucket_id = 'job-images'
        and name = pg_temp.id('01') || '/' || pg_temp.id('50') || '/perdida.pdf')
    or (bucket_id = 'bike-images'
        and name = pg_temp.id('01') || '/' || pg_temp.id('20') || '/principal.jpg');

-- Y el taller siguió trabajando: lo que la restauración va a reemplazar.
update public.mechanic_jobs set notes = 'cambio después del respaldo'
 where id = pg_temp.id('51');

-- ============================================================================
-- Con datos que el respaldo no guarda, no se restaura nada y se dice qué
-- ============================================================================

insert into results
select 'previa', public.restore_backup_preflight(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo'),
  pg_temp.id('01'));
select ok(not (select (result ->> 'can_restore')::boolean from results where label = 'previa'),
  'la consulta previa dice que no se puede restaurar');
select is(
  (select array_agg(item ->> 'table' order by item ->> 'table')
     from results, jsonb_array_elements(result -> 'uncovered_dependents') item
    where label = 'previa'),
  array['expense_categories', 'mechanic_job_status_transitions'],
  'y qué datos del taller se perderían');
select is(
  (select jsonb_array_length(result -> 'omitted_attachments') from results where label = 'previa'),
  3, 'y qué adjuntos se omitirían');

insert into results
select 'rechazada', public.restore_backup(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo'),
  pg_temp.id('01'));
select is(
  (select result ->> 'error_code' from results where label = 'rechazada'),
  'restore_would_lose_uncovered_data', 'la restauración se niega antes de tocar nada');
select matches(
  (select result ->> 'message' from results where label = 'rechazada'),
  '^No se restauró nada: el taller tiene datos que este respaldo no guarda y restaurar los perdería \(cambios de estado de los trabajos: 2, categorías de gastos: 1\)\. Puedes descargar el respaldo para consultarlo\.$',
  'con lo que se perdería, en palabras del taller');
select is((select notes from public.mechanic_jobs where id = pg_temp.id('51')),
  'cambio después del respaldo', 'los datos de ahora siguen intactos');
select ok(
  (select restore_report is null and status = 'completed'
     from public.database_backups
    where id = (select (result ->> 'backup_id')::uuid from results where label = 'respaldo')),
  'el respaldo sigue disponible y sin informe');

-- Quien llame al motor directo (la llave de servicio puede) recibe la misma
-- negativa: el motor la repite después de tomar las filas del taller.
insert into results
select 'motor-directo', public.restore_backup_internal(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo'),
  pg_temp.id('01'));
select ok(not (select (result ->> 'success')::boolean from results where label = 'motor-directo'),
  'el motor, llamado directo, tampoco restaura');
select matches((select result ->> 'error' from results where label = 'motor-directo'),
  '^No se restauró nada: el taller tiene datos que este respaldo no guarda',
  'y dice por qué');
select is((select notes from public.mechanic_jobs where id = pg_temp.id('51')),
  'cambio después del respaldo', 'sin tocar los datos');
select is(
  (select count(*)::integer from public.database_backups where tenant_id = pg_temp.id('01')),
  1, 'ni dejar copias de trabajo');
-- Contó con las tablas cercadas: nadie puede agregar una fila nueva (un
-- cliente con su dirección) entre la cuenta y el borrado.
select ok(
  (select count(distinct l.relation) = 38
     from pg_locks l
    where l.pid = pg_backend_pid()
      and l.mode = 'ShareRowExclusiveLock'
      and l.granted
      and l.relation in (select format('public.%I', t)::regclass
                           from unnest(public.restore_backup_covered_tables()) t)),
  'el motor cuenta con las 38 tablas cercadas');

-- ============================================================================
-- Restaurar: todo vuelve, salvo las URL cuyo archivo falta
-- ============================================================================

select pg_temp.clear_uncovered();

insert into results
select 'previa-lista', public.restore_backup_preflight(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo'),
  pg_temp.id('01'));
select ok(
  (select (result ->> 'can_restore')::boolean and result -> 'message' = 'null'::jsonb
     from results where label = 'previa-lista'),
  'sin nada que se pierda, la consulta previa ofrece restaurar');

insert into results
select 'restaurado', public.restore_backup(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo'),
  pg_temp.id('01'));

select ok((select (result ->> 'success')::boolean from results where label = 'restaurado'),
  'la restauración se completa aunque falten archivos');

select is(
  (select result -> 'omitted_attachments' from results where label = 'restaurado'),
  jsonb_build_array(
    jsonb_build_object(
      'table', 'bikes', 'record_id', pg_temp.id('20'), 'label', 'Trek Marlin 5',
      'field', 'image_urls',
      'url', pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/principal.jpg'),
      'reason', 'ya no está en Storage (se borró o no terminó de subir)'),
    jsonb_build_object(
      'table', 'bikes', 'record_id', pg_temp.id('20'), 'label', 'Trek Marlin 5',
      'field', 'image_url',
      'url', pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/principal.jpg'),
      'reason', 'ya no está en Storage (se borró o no terminó de subir)'),
    jsonb_build_object(
      'table', 'mechanic_jobs', 'record_id', pg_temp.id('50'), 'label', 'RB-50',
      'field', 'image_urls',
      'url', pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/perdida.pdf'),
      'reason', 'ya no está en Storage (se borró o no terminó de subir)')),
  'la respuesta dice qué registro y qué archivo se omitió, uno por uno');

select is(
  (select image_urls from public.mechanic_jobs where id = pg_temp.id('50')),
  array[pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/presupuesto.pdf'),
        pg_temp.url('vinabike-assets', 'mechanic_jobs/cliente/job_1.jpg')],
  'el trabajo vuelve con el adjunto que está y el de otro bucket; sin el que falta');
select is(
  (select image_urls from public.mechanic_jobs where id = pg_temp.id('51')),
  array[pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/foto.jpg')],
  'el otro trabajo vuelve entero');
select is(
  (select notes from public.mechanic_jobs where id = pg_temp.id('51')),
  null, 'con los datos del respaldo');
select is(
  (select row(image_url, image_urls)::text from public.bikes where id = pg_temp.id('20')),
  row(null::text, array[pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/lateral.jpg')])::text,
  'la bici vuelve sin la foto principal que falta, con la otra');
select is(
  (select count(*)::integer from public.bikes where tenant_id = pg_temp.id('01')),
  2, 'las dos bicis');
select is(
  (select count(*)::integer from public.mechanic_jobs where tenant_id = pg_temp.id('01')),
  2, 'los dos trabajos');

select is(
  (select jsonb_array_length(restore_report -> 'omitted_attachments')
     from public.database_backups
    where id = (select (result ->> 'backup_id')::uuid from results where label = 'respaldo')),
  3, 'el respaldo guarda el informe de lo omitido');
select ok(
  (select (restore_report ->> 'restored_at') is not null and status = 'restored'
     from public.database_backups
    where id = (select (result ->> 'backup_id')::uuid from results where label = 'respaldo')),
  'con su fecha, y el respaldo queda como restaurado');
select ok(
  (select backup_data::text like '%perdida.pdf%' and backup_data::text like '%principal.jpg%'
     from public.database_backups
    where id = (select (result ->> 'backup_id')::uuid from results where label = 'respaldo')),
  'el respaldo mismo no cambia: si el archivo se recupera, restaurar lo trae');
select is(
  (select count(*)::integer from public.database_backups where tenant_id = pg_temp.id('01')),
  1, 'no quedan copias de trabajo');

-- ============================================================================
-- Sin nada que falte: el informe dice que no se omitió nada
-- ============================================================================

insert into results
select 'respaldo-2', public.create_backup(pg_temp.id('01'), 'Sin faltantes', 'manual', null);
select pg_temp.clear_uncovered();
insert into results
select 'restaurado-2', public.restore_backup(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-2'),
  pg_temp.id('01'));
select ok((select (result ->> 'success')::boolean from results where label = 'restaurado-2'),
  'se restaura');
select is((select result -> 'omitted_attachments' from results where label = 'restaurado-2'),
  '[]'::jsonb, 'la respuesta dice que no se omitió nada');
select is(
  (select restore_report -> 'omitted_attachments' from public.database_backups
    where id = (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-2')),
  '[]'::jsonb, 'y el informe del respaldo también');

-- ============================================================================
-- Una restauración que falla por otra cosa no deja nada a medias
-- ============================================================================

insert into results
select 'respaldo-3', public.create_backup(pg_temp.id('01'), 'Roto', 'manual', null);
-- Un trabajo con un cliente que no existe, y un adjunto que falta.
update public.database_backups
   set backup_data = jsonb_set(
         backup_data, '{mechanic_jobs}',
         (select jsonb_agg(case when job ->> 'id' = pg_temp.id('51')::text
                                then job || jsonb_build_object(
                                  'customer_id', pg_temp.id('99'),
                                  'image_urls', jsonb_build_array(
                                    pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/nunca.jpg')))
                                else job end)
            from jsonb_array_elements(backup_data -> 'mechanic_jobs') job))
 where id = (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-3');
update public.mechanic_jobs set notes = 'lo de ahora'
 where id = pg_temp.id('50');

select pg_temp.clear_uncovered();
insert into results
select 'restaurado-3', public.restore_backup(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-3'),
  pg_temp.id('01'));
select ok(not (select (result ->> 'success')::boolean from results where label = 'restaurado-3'),
  'la restauración falla');
select is((select result ->> 'error_code' from results where label = 'restaurado-3'),
  'supplier_foundation_legacy_restore_failed',
  'por el cliente que no existe, dentro de la restauración');
select ok(not ((select result from results where label = 'restaurado-3') ? 'omitted_attachments'),
  'y no informa omisiones de algo que no se restauró');
select is((select notes from public.mechanic_jobs where id = pg_temp.id('50')),
  'lo de ahora', 'los datos de ahora siguen intactos');
select ok(
  (select restore_report is null and status = 'completed'
     from public.database_backups
    where id = (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-3')),
  'el respaldo sigue disponible y sin informe');
select is(
  (select count(*)::integer from public.database_backups where tenant_id = pg_temp.id('01')),
  3, 'y no quedan copias de trabajo');

-- ============================================================================
-- Un respaldo antiguo, al que le faltan tablas, no se restaura
-- ============================================================================

insert into results
select 'respaldo-4', public.create_backup(pg_temp.id('01'), 'Antiguo', 'manual', null);
-- Como el del taller principal (2025-12-09): de antes de que el respaldo
-- guardara la mensajería y los trabajadores.
update public.database_backups
   set backup_data = backup_data - 'messages' - 'employees'
 where id = (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-4');
insert into results
select 'previa-4', public.restore_backup_preflight(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-4'),
  pg_temp.id('01'));
select ok(not (select (result ->> 'can_restore')::boolean from results where label = 'previa-4'),
  'la consulta previa no ofrece restaurar un respaldo al que le faltan tablas');
select is(
  (select array_agg(item.value ->> 'label' order by item.ordinality)
     from results,
          jsonb_array_elements(result -> 'missing_tables')
            with ordinality as item(value, ordinality)
    where label = 'previa-4'),
  array['mensajes', 'trabajadores'], 'y dice cuáles, en palabras del taller');
insert into results
select 'restaurado-4', public.restore_backup(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-4'),
  pg_temp.id('01'));
select is((select result ->> 'error_code' from results where label = 'restaurado-4'),
  'restore_backup_incomplete', 'restaurarlo se niega');
select is((select result ->> 'message' from results where label = 'restaurado-4'),
  'No se restauró nada: este respaldo es de una versión anterior y no guarda mensajes, trabajadores; restaurarlo los borraría sin reponerlos. Puedes descargarlo para consultarlo.',
  'con lo que borraría sin reponer');
insert into results
select 'motor-4', public.restore_backup_internal(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-4'),
  pg_temp.id('01'));
select matches((select result ->> 'error' from results where label = 'motor-4'),
  'versión anterior', 'el motor directo también se niega');
select is((select notes from public.mechanic_jobs where id = pg_temp.id('50')),
  'lo de ahora', 'y los datos de ahora siguen intactos');

-- ============================================================================
-- Una fila de otro taller que apunta a este cuenta como lo que se perdería
-- ============================================================================

insert into public.tenants(id, shop_name) values
  (pg_temp.id('02'), 'Otro taller');
set local session_replication_role = replica;
insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  (pg_temp.id('29'), pg_temp.id('02'), pg_temp.id('10'), 'Ajena', 'Cruzada');
set local session_replication_role = origin;
insert into results
select 'previa-cruzada', public.restore_backup_preflight(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-3'),
  pg_temp.id('01'));
select is(
  (select item - 'effect'
     from results, jsonb_array_elements(result -> 'uncovered_dependents') item
    where label = 'previa-cruzada' and item ->> 'table' = 'bikes'),
  '{"table": "bikes", "label": "bicis de otro taller", "other_tenant": true, "rows": 1}'::jsonb,
  'la bici de otro taller con un cliente de este se cuenta: restaurar la tocaría');
set local session_replication_role = replica;
delete from public.bikes where id = pg_temp.id('29');
set local session_replication_role = origin;

-- ============================================================================
-- Proveedores distintos: la consulta previa dice lo que el motor negaría
-- ============================================================================

insert into public.suppliers(id, tenant_id, name) values
  (pg_temp.id('30'), pg_temp.id('01'), 'Proveedor nuevo');
insert into results
select 'previa-proveedores', public.restore_backup_preflight(
  (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-3'),
  pg_temp.id('01'));
select ok(not (select (result ->> 'can_restore')::boolean from results where label = 'previa-proveedores'),
  'con otro proveedor desde el respaldo, no se ofrece restaurar');
select is(
  (select result -> 'foundation_blocker' ->> 'message'
     from results where label = 'previa-proveedores'),
  'Desde este respaldo cambiaron los proveedores (1 ahora, 0 en el respaldo), y restaurar exige los mismos.',
  'y dice por qué');

-- ============================================================================
-- Permisos
-- ============================================================================

-- Una persona de otro taller, sin permiso sobre estos respaldos.
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('92'), 'authenticated', 'authenticated',
   'otro-respaldos@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('92'), pg_temp.id('02'), 'admin');
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('92'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('92')::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
select throws_ok(
  format($$select public.restore_backup(%L, %L)$$,
    (select (result ->> 'backup_id')::uuid from results where label = 'respaldo-3'),
    pg_temp.id('01')),
  '42501', null, 'quien no administra respaldos del taller no restaura');

select * from finish();
rollback;
