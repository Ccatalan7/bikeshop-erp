-- C3: an exact copy is readable by its staff/customer, with no public fallback.
-- Only synthetic rows; the whole transaction rolls back.
begin;
select no_plan();
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create function pg_temp.c3id(p_suffix text) returns uuid language sql as $$
  select ('e3c30000-0000-4000-8000-0000000000' || p_suffix)::uuid
$$;
create function pg_temp.c3source() returns text language sql as $$
  select 'http://127.0.0.1:54321/storage/v1/object/public/vinabike-assets/mechanic_jobs/'
    || pg_temp.c3id('11')::text || '/e2e.jpg'
$$;
create function pg_temp.c3path() returns text language sql as $$
  select pg_temp.c3id('01')::text || '/' || pg_temp.c3id('21')::text || '/'
    || pg_temp.c3id('41')::text || '/e2e.jpg'
$$;

-- Fixture only: no business event is replayed to create these synthetic rows.
set local session_replication_role = replica;
insert into public.tenants(id, shop_name) values
  (pg_temp.c3id('01'), 'C3 privado A'), (pg_temp.c3id('02'), 'C3 privado B');
insert into auth.users(id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select pg_temp.c3id(suffix), 'authenticated', 'authenticated',
  'c3-' || suffix || '@vinabike.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
  now(), now()
from (values ('91'), ('92'), ('93'), ('94')) account(suffix);
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.c3id('91'), pg_temp.c3id('01'), 'mechanic'),
  (pg_temp.c3id('92'), pg_temp.c3id('02'), 'admin');
insert into public.customers(id, tenant_id, name, auth_user_id, is_active) values
  (pg_temp.c3id('11'), pg_temp.c3id('01'), 'Cliente C3 A', pg_temp.c3id('93'), true),
  (pg_temp.c3id('12'), pg_temp.c3id('02'), 'Cliente C3 B', pg_temp.c3id('94'), true);
insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  (pg_temp.c3id('31'), pg_temp.c3id('01'), pg_temp.c3id('11'), 'C3', 'Sintética');
insert into public.mechanic_jobs(id, tenant_id, customer_id, bike_id,
  job_number, image_urls) values
  (pg_temp.c3id('21'), pg_temp.c3id('01'), pg_temp.c3id('11'), pg_temp.c3id('31'),
   'C3-PRIVADO-PGTAP', array[pg_temp.c3source()]);
insert into storage.objects(bucket_id, name, metadata) values
  ('workshop-legacy-private', pg_temp.c3path(), '{"size":42}'::jsonb);
set local session_replication_role = origin;

select is((select public from storage.buckets where id = 'workshop-legacy-private'),
  false, 'las copias del trabajo viven en un bucket privado');
select ok(not has_table_privilege('authenticated',
  'public.workshop_legacy_asset_copies', 'INSERT'),
  'el cliente no puede fabricar un recibo de hash y dueño');
select ok(not has_function_privilege('anon',
  'public.workshop_legacy_asset_read_v1(text)', 'EXECUTE'),
  'un anónimo no puede resolver la copia');

insert into public.workshop_legacy_asset_copies(
  id, tenant_id, customer_id, job_id, source_path, source_reference, storage_path,
  file_name, mime_type, source_size_bytes, private_size_bytes,
  source_sha256, private_sha256, copied_at, verified_at
) values (
  pg_temp.c3id('41'), pg_temp.c3id('01'), pg_temp.c3id('11'), pg_temp.c3id('21'),
  'mechanic_jobs/' || pg_temp.c3id('11')::text || '/e2e.jpg', pg_temp.c3source(),
  pg_temp.c3path(), 'e2e.jpg', 'image/jpeg', 42, 42,
  repeat('a',64), repeat('a',64), now(), now()
);
select throws_ok(format(
  'update public.workshop_legacy_asset_copies set tenant_id = %L where id = %L',
  pg_temp.c3id('02'), pg_temp.c3id('41')), '23514', null,
  'un recibo no se puede reasignar a otro taller');
select throws_ok(format(
  'update public.workshop_legacy_asset_copies set private_sha256 = %L where id = %L',
  repeat('b',64), pg_temp.c3id('41')), '23514', null,
  'los bytes privados tienen que coincidir con el recibo del origen');

-- Deliberately broad legacy policies cannot bypass this bucket's fences.
grant usage on schema storage to anon, authenticated;
grant select, insert, update, delete on storage.objects to anon, authenticated;
create policy c3_test_broad_storage_policy on storage.objects
  for all to anon, authenticated using (true) with check (true);
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.c3id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.c3id('91')::text, true);
set local role authenticated;
select is(public.workshop_legacy_asset_read_v1(pg_temp.c3source())->>'mode',
  'private', 'el mecánico resuelve el destino privado');
select is((select count(*)::int from storage.objects
  where bucket_id = 'workshop-legacy-private'), 1,
  'el mecánico lee la copia exacta de su trabajo');
select throws_ok(format(
  'insert into storage.objects(bucket_id,name) values (%L,%L)',
  'workshop-legacy-private', pg_temp.c3path() || '.otro'),
  '42501', null, 'una política antigua permisiva no permite subir una copia');
update storage.objects set name = name || '.otro'
  where bucket_id = 'workshop-legacy-private';
select throws_ok(
  'delete from storage.objects where bucket_id = ''workshop-legacy-private''',
  '42501', null, 'Storage exige su API para retirar bytes, también en la prueba');
reset role;
select is((select name from storage.objects
  where bucket_id = 'workshop-legacy-private'), pg_temp.c3path(),
  'el empleado no puede reemplazar ni retirar los bytes privados');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.c3id('93'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.c3id('93')::text, true);
set local role authenticated;
select is(public.workshop_legacy_asset_read_v1(pg_temp.c3source())->>'mode',
  'private', 'el cliente del trabajo puede abrir su copia');
select is((select count(*)::int from storage.objects
  where bucket_id = 'workshop-legacy-private'), 1,
  'el portal del dueño lee los mismos bytes privados');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.c3id('92'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.c3id('92')::text, true);
set local role authenticated;
select throws_ok(format('select public.workshop_legacy_asset_read_v1(%L)',
  pg_temp.c3source()), '42501', null, 'otro taller no resuelve la copia');
select is((select count(*)::int from storage.objects
  where bucket_id = 'workshop-legacy-private'), 0,
  'otra política permisiva no expone la copia al otro taller');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.c3id('94'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.c3id('94')::text, true);
set local role authenticated;
select throws_ok(format('select public.workshop_legacy_asset_read_v1(%L)',
  pg_temp.c3source()), '42501', null, 'un cliente ajeno no resuelve la copia');
reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;
select is((select count(*)::int from storage.objects
  where bucket_id = 'workshop-legacy-private'), 0,
  'un anónimo no ve los bytes con una política permisiva antigua');
reset role;

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.c3id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.c3id('91')::text, true);
-- Simulate an unavailable copy inside the rolled-back fixture by changing
-- its metadata identity. Do not bypass Storage's direct-delete protection.
update storage.objects set name = name || '.missing'
  where bucket_id = 'workshop-legacy-private';
set local role authenticated;
select throws_ok(format('select public.workshop_legacy_asset_read_v1(%L)',
  pg_temp.c3source()), '55000', null,
  'una copia faltante no vuelve silenciosamente a la URL pública');
reset role;
update storage.objects set name = pg_temp.c3path()
  where bucket_id = 'workshop-legacy-private';
update public.user_profiles set is_active = false where user_id = pg_temp.c3id('91');
set local role authenticated;
select throws_ok(format('select public.workshop_legacy_asset_read_v1(%L)',
  pg_temp.c3source()), '42501', null,
  'un empleado desactivado pierde la lectura privada');
reset role;
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.c3id('93'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.c3id('93')::text, true);
update public.mechanic_jobs set image_urls = '{}'::text[]
  where id = pg_temp.c3id('21');
set local role authenticated;
select throws_ok(format('select public.workshop_legacy_asset_read_v1(%L)',
  pg_temp.c3source()), '42501', null,
  'quitar el vínculo del trabajo revoca nuevas lecturas de la copia');
reset role;

select * from finish();
rollback;
