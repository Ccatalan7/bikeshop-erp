-- Private task files: storage authorization, independent links and replay.
-- The transaction rolls back all fixtures and temporary grants.
begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create function pg_temp.id(p_suffix text) returns uuid language sql as $$
  select ('e3920000-0000-4000-8000-0000000000' || p_suffix)::uuid
$$;
create function pg_temp.path(p_task text, p_file text) returns text
language sql as $$
  select pg_temp.id('01')::text || '/' || pg_temp.id(p_task)::text || '/'
    || pg_temp.id(p_file)::text || '/foto.jpg'
$$;

insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Tareas privadas A'),
  (pg_temp.id('02'), 'Tareas privadas B');
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated',
   'task-file-owner@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now()),
  (pg_temp.id('92'), 'authenticated', 'authenticated',
   'task-file-viewer@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now()),
  (pg_temp.id('93'), 'authenticated', 'authenticated',
   'task-file-outsider@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
   now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin'),
  (pg_temp.id('92'), pg_temp.id('01'), 'cashier'),
  (pg_temp.id('93'), pg_temp.id('02'), 'admin');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
set local role authenticated;
insert into public.smart_tasks(id, tenant_id, title, created_by, visibility)
values
  (pg_temp.id('11'), pg_temp.id('01'), 'Equipo', pg_temp.id('91'), 'team'),
  (pg_temp.id('12'), pg_temp.id('01'), 'Personal', pg_temp.id('91'), 'private');
reset role;

select is((select public from storage.buckets where id = 'task-attachments'),
  false, 'el bucket de tareas no sirve URLs públicas');
select ok(not has_table_privilege('authenticated',
  'public.smart_task_attachments', 'INSERT')
  and not has_table_privilege('authenticated',
    'public.smart_task_attachments', 'UPDATE'),
  'el cliente sólo puede crear vínculos por RPC');

-- The local scratch lacks direct Storage grants. These grants and replica
-- mode are scoped to this rolled-back test; RLS remains active.
grant usage on schema storage to authenticated;
grant select, insert, delete on storage.objects to authenticated;
set local session_replication_role = replica;
set local role authenticated;
select lives_ok(format(
  'insert into storage.objects(bucket_id,name,owner_id) values (%L,%L,%L)',
  'task-attachments', pg_temp.path('11', '21'), pg_temp.id('91')),
  'el creador sube el primer archivo a su tarea');
select lives_ok(format(
  'insert into storage.objects(bucket_id,name,owner_id) values (%L,%L,%L)',
  'task-attachments', pg_temp.path('11', '22'), pg_temp.id('91')),
  'otro archivo con otro ID no reemplaza al primero');
select lives_ok(format(
  'insert into storage.objects(bucket_id,name,owner_id) values (%L,%L,%L)',
  'task-attachments', pg_temp.path('12', '23'), pg_temp.id('91')),
  'la tarea personal recibe un archivo separado');
select lives_ok(format(
  'insert into storage.objects(bucket_id,name,owner_id) values (%L,%L,%L)',
  'task-attachments', pg_temp.path('11', '27'), pg_temp.id('91')),
  'una subida sin vínculo también queda bajo la ruta autorizada');
select throws_ok(format(
  'insert into storage.objects(bucket_id,name,owner_id) values (%L,%L,%L)',
  'task-attachments', pg_temp.id('02')::text || '/' ||
    pg_temp.id('11')::text || '/' || pg_temp.id('24')::text || '/foto.jpg',
  pg_temp.id('91')), '42501', null,
  'la ruta de otro taller no pasa RLS');

select is((select count(*)::int from storage.objects
  where bucket_id = 'task-attachments'), 4,
  'el dueño puede ver sus objetos sin vínculo para limpiar una subida fallida');
reset role;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('92'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('92')::text, true);
set local role authenticated;
select is((select count(*)::int from storage.objects
  where bucket_id = 'task-attachments'), 0,
  'otro empleado no lee objetos que aún no tienen vínculo');
reset role;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
set local role authenticated;
delete from storage.objects where bucket_id = 'task-attachments'
  and name = pg_temp.path('11', '27');
reset role;
select is((select count(*)::int from storage.objects
  where bucket_id = 'task-attachments'), 3,
  'el dueño retira sus propios bytes sin vínculo');
set local role authenticated;
select throws_ok(format(
  'select public.smart_task_attachment_add_v1(%L,%L,%L,%L,%L,%s,%L)',
  pg_temp.id('11'), pg_temp.id('25'), 'fantasma.jpg',
  pg_temp.path('11', '25'), 'image/jpeg', 8, 'add-missing'),
  '23503', null, 'el vínculo exige un objeto realmente subido');
select lives_ok(format(
  'select public.smart_task_attachment_add_v1(%L,%L,%L,%L,%L,%s,%L)',
  pg_temp.id('11'), pg_temp.id('21'), 'uno.jpg',
  pg_temp.path('11', '21'), 'image/jpeg', 8, 'add-one'),
  'el primer archivo se vincula de forma atómica');
select lives_ok(format(
  'select public.smart_task_attachment_add_v1(%L,%L,%L,%L,%L,%s,%L)',
  pg_temp.id('11'), pg_temp.id('21'), 'uno.jpg',
  pg_temp.path('11', '21'), 'image/jpeg', 8, 'add-one'),
  'la misma llave devuelve recibo sin duplicar');
select lives_ok(format(
  'select public.smart_task_attachment_add_v1(%L,%L,%L,%L,%L,%s,%L)',
  pg_temp.id('11'), pg_temp.id('22'), 'dos.jpg',
  pg_temp.path('11', '22'), 'image/jpeg', 9, 'add-two'),
  'otro archivo se vincula sin reemplazar el primero');
select lives_ok(format(
  'select public.smart_task_attachment_add_v1(%L,%L,%L,%L,%L,%s,%L)',
  pg_temp.id('12'), pg_temp.id('23'), 'privado.jpg',
  pg_temp.path('12', '23'), 'image/jpeg', 10, 'add-private'),
  'la tarea personal conserva su propia visibilidad');
select is((select count(*)::int from public.smart_task_attachments), 3,
  'dos vínculos independientes y uno privado, sin duplicados');
select is((select count(*)::int from storage.objects
  where bucket_id = 'task-attachments'), 3,
  'el creador ve sólo objetos ya vinculados');
delete from storage.objects where bucket_id = 'task-attachments'
  and name = pg_temp.path('11', '21');
reset role;
select is((select count(*)::int from storage.objects
  where bucket_id = 'task-attachments'), 3,
  'un archivo activo no se puede borrar por Storage');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('92'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('92')::text, true);
set local role authenticated;
select is((select count(*)::int from public.smart_task_attachments), 2,
  'un compañero ve archivos de equipo y no los personales');
select is((select count(*)::int from storage.objects
  where bucket_id = 'task-attachments'), 2,
  'Storage aplica el mismo límite por tarea');
select throws_ok(format(
  'select public.smart_task_attachment_add_v1(%L,%L,%L,%L,%L,%s,%L)',
  pg_temp.id('11'), pg_temp.id('26'), 'ajeno.jpg',
  pg_temp.path('11', '26'), 'image/jpeg', 8, 'viewer-add'),
  '42501', null, 'un observador no adjunta archivos');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('93'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('93')::text, true);
set local role authenticated;
select is((select count(*)::int from public.smart_task_attachments), 0,
  'otro taller no lee vínculos');
select is((select count(*)::int from storage.objects
  where bucket_id = 'task-attachments'), 0,
  'otro taller no lee bytes');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
set local role authenticated;
select lives_ok(format(
  'select public.smart_task_attachment_remove_v1(%L,%L,%L)',
  pg_temp.id('11'), pg_temp.id('21'), 'remove-one'),
  'quitar oculta el vínculo y entrega la ruta para limpiar Storage');
select lives_ok(format(
  'select public.smart_task_attachment_remove_v1(%L,%L,%L)',
  pg_temp.id('11'), pg_temp.id('21'), 'remove-one'),
  'el borrado también acepta reintento con la misma llave');
select is((select count(*)::int from public.smart_task_attachments), 2,
  'un tombstone no aparece en la bandeja');
select is(jsonb_array_length(
  public.smart_task_attachment_pending_cleanup_v1(25)), 1,
  'el autor encuentra el borrado pendiente después de perder la sesión');
select throws_ok(format(
  'select public.smart_task_attachment_ack_cleanup_v1(%L,%L)',
  pg_temp.id('11'), pg_temp.id('21')),
  '55000', null, 'no se confirma limpieza con bytes todavía presentes');
select throws_ok(
  'select public.smart_task_attachment_pending_cleanup_v1(0)',
  '22023', null, 'el límite de reintentos no puede ser cero');

reset role;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('92'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('92')::text, true);
set local role authenticated;
select is(jsonb_array_length(
  public.smart_task_attachment_pending_cleanup_v1(25)), 0,
  'un observador no recibe rutas de limpieza');
select throws_ok(format(
  'select public.smart_task_attachment_ack_cleanup_v1(%L,%L)',
  pg_temp.id('11'), pg_temp.id('21')),
  '42501', null, 'un observador no confirma borrados');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
set local role authenticated;
delete from storage.objects where bucket_id = 'task-attachments'
  and name = pg_temp.path('11', '21');
select lives_ok(format(
  'select public.smart_task_attachment_ack_cleanup_v1(%L,%L)',
  pg_temp.id('11'), pg_temp.id('21')),
  'el autor confirma el borrado sólo después de retirar bytes');
select is(jsonb_array_length(
  public.smart_task_attachment_pending_cleanup_v1(25)), 0,
  'un borrado confirmado sale de la cola durable');
select lives_ok(format(
  'select public.smart_task_attachment_ack_cleanup_v1(%L,%L)',
  pg_temp.id('11'), pg_temp.id('21')),
  'el mismo acuse puede repetirse');
reset role;
select is((select count(*)::int from storage.objects
  where bucket_id = 'task-attachments'), 2,
  'el creador puede limpiar el objeto tras el tombstone');

-- A caller's current tenant chooses the cleanup page. The two active ERP
-- principals exercise the filter even though the present identity invariant
-- also prevents one principal from holding two active ERP profiles.
reset role;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('93'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('93')::text, true);
set local role authenticated;
insert into public.smart_tasks(id, tenant_id, title, created_by, visibility)
values (pg_temp.id('31'), pg_temp.id('02'), 'Equipo B', pg_temp.id('93'),
  'team');
insert into storage.objects(bucket_id, name, owner_id) values (
  'task-attachments',
  pg_temp.id('02')::text || '/' || pg_temp.id('31')::text || '/' ||
    pg_temp.id('32')::text || '/foto.jpg',
  pg_temp.id('93')::text
);
select lives_ok(format(
  'select public.smart_task_attachment_add_v1(%L,%L,%L,%L,%L,%s,%L)',
  pg_temp.id('31'), pg_temp.id('32'), 'b.jpg',
  pg_temp.id('02')::text || '/' || pg_temp.id('31')::text || '/' ||
    pg_temp.id('32')::text || '/foto.jpg', 'image/jpeg', 8, 'add-b'),
  'el segundo taller vincula su propio archivo');
select lives_ok(format(
  'select public.smart_task_attachment_remove_v1(%L,%L,%L)',
  pg_temp.id('31'), pg_temp.id('32'), 'remove-b'),
  'el segundo taller deja un tombstone más antiguo');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
set local role authenticated;
select lives_ok(format(
  'select public.smart_task_attachment_remove_v1(%L,%L,%L)',
  pg_temp.id('11'), pg_temp.id('22'), 'remove-two'),
  'el primer taller deja su tombstone posterior');
select is(jsonb_array_length(
  public.smart_task_attachment_pending_cleanup_v2(pg_temp.id('01'), 1)), 1,
  'la página de tamaño uno encuentra el taller pedido');
select is(jsonb_array_length(
  public.smart_task_attachment_pending_cleanup_v2(pg_temp.id('02'), 1)), 0,
  'el primer actor no enumera tombstones del segundo taller');
select throws_ok(
  'select public.smart_task_attachment_pending_cleanup_v2(null::uuid, 25)',
  '22023', null, 'la cola nueva exige taller explícito');
select throws_ok(format(
  'select public.smart_task_attachment_pending_cleanup_v2(%L, 0)',
  pg_temp.id('01')),
  '22023', null, 'la cola nueva conserva el límite de página');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('93'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('93')::text, true);
set local role authenticated;
select is(jsonb_array_length(
  public.smart_task_attachment_pending_cleanup_v2(pg_temp.id('02'), 1)), 1,
  'el segundo taller lee sólo su tombstone');
select is(jsonb_array_length(
  public.smart_task_attachment_pending_cleanup_v2(pg_temp.id('01'), 1)), 0,
  'el segundo taller tampoco enumera el primero');
reset role;
select ok(has_function_privilege('authenticated',
  'public.smart_task_attachment_pending_cleanup_v2(uuid,integer)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_pending_cleanup_v2(uuid,integer)', 'EXECUTE'),
  'la cola acotada sólo es ejecutable por usuario autenticado');

-- A malformed historical row with another uploader must fail closed even for
-- someone who can otherwise write this task. The fixture rolls back below.
insert into public.smart_task_attachments (
  id, tenant_id, task_id, uploaded_by, storage_path,
  file_name, mime_type, size_bytes
) values (
  pg_temp.id('28'), pg_temp.id('01'), pg_temp.id('11'), pg_temp.id('92'),
  pg_temp.path('11', '28'), 'otro.jpg', 'image/jpeg', 8
);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);
set local role authenticated;
select is(public.smart_task_attachment_recovery_status_v1(
  pg_temp.id('01'), pg_temp.id('12'), pg_temp.id('23')),
  'active', 'el uploader distingue su vínculo activo');
select is(public.smart_task_attachment_recovery_status_v1(
  pg_temp.id('01'), pg_temp.id('11'), pg_temp.id('22')),
  'removed', 'el uploader distingue su tombstone oculto por RLS');
select is(public.smart_task_attachment_recovery_status_v1(
  pg_temp.id('01'), pg_temp.id('11'), pg_temp.id('25')),
  'absent', 'el uploader distingue un UUID nunca vinculado');
select throws_ok(format(
  'select public.smart_task_attachment_recovery_status_v1(%L,%L,%L)',
  pg_temp.id('01'), pg_temp.id('11'), pg_temp.id('28')),
  '42501', null, 'un UUID de otro uploader no parece propio');
select throws_ok(format(
  'select public.smart_task_attachment_recovery_status_v1(%L,%L,%L)',
  pg_temp.id('02'), pg_temp.id('31'), pg_temp.id('32')),
  '42501', null, 'no puede consultar la tarea de otro taller');
select throws_ok(
  'select public.smart_task_attachment_recovery_status_v1(null::uuid, '
  || quote_literal(pg_temp.id('11')) || ', '
  || quote_literal(pg_temp.id('22')) || ')',
  '22023', null, 'la consulta exige identidad completa');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('92'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('92')::text, true);
set local role authenticated;
select throws_ok(format(
  'select public.smart_task_attachment_recovery_status_v1(%L,%L,%L)',
  pg_temp.id('01'), pg_temp.id('11'), pg_temp.id('22')),
  '42501', null, 'un observador no consulta el estado de recuperación');
reset role;

select ok(has_function_privilege('authenticated',
  'public.smart_task_attachment_recovery_status_v1(uuid,uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.smart_task_attachment_recovery_status_v1(uuid,uuid,uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.smart_task_attachment_recovery_status_v1(uuid,uuid,uuid)', 'EXECUTE'),
  'sólo el cliente autenticado puede ejecutar la consulta');

select * from finish();
rollback;
