-- Un adjunto nuevo de un trabajo o una foto nueva de una bici, en los buckets
-- que la app administra, tiene que existir y estar en su carpeta
-- (20260929020000; carrera del barrido de adjuntos, 2026-09-29).
--
-- Prueba:
-- - el disparador de cada tabla: archivo que está, que no está, de otra
--   carpeta, de otro taller, lo que ya estaba, quitar, otros buckets;
-- - los mismos casos por los comandos: el alta (`create_mechanic_job_v1`) y
--   el guardado de sólo adjuntos de la tabla (`save_mechanic_job_lines_v1`),
--   como empleado autenticado, sin dejar nada escrito cuando se rechaza.
begin;

select no_plan();

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create or replace function pg_temp.id(p_n text)
returns uuid
language sql
as $$ select ('e2880000-0000-4000-8000-0000000000' || p_n)::uuid $$;

insert into public.tenants(id, shop_name) values
  (pg_temp.id('01'), 'Taller adjuntos'),
  (pg_temp.id('02'), 'Otro taller');
insert into auth.users(
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (pg_temp.id('91'), 'authenticated', 'authenticated',
   'adjuntos@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
insert into public.user_profiles(user_id, tenant_id, role) values
  (pg_temp.id('91'), pg_temp.id('01'), 'admin');

select set_config('request.jwt.claims', jsonb_build_object(
  'sub', pg_temp.id('91'), 'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub', pg_temp.id('91')::text, true);

insert into public.customers(id, tenant_id, name) values
  (pg_temp.id('10'), pg_temp.id('01'), 'Cliente adjuntos');
insert into public.bikes(id, tenant_id, customer_id, brand, model) values
  (pg_temp.id('20'), pg_temp.id('01'), pg_temp.id('10'), 'Trek', 'Marlin 5'),
  (pg_temp.id('21'), pg_temp.id('01'), pg_temp.id('10'), 'Oxford', 'Orion');
insert into public.mechanic_jobs(
  id, tenant_id, customer_id, bike_id, job_number, job_type, status
) values
  (pg_temp.id('50'), pg_temp.id('01'), pg_temp.id('10'), pg_temp.id('20'),
   'ADJ-50', 'service', 'PENDIENTE'),
  (pg_temp.id('51'), pg_temp.id('01'), pg_temp.id('10'), pg_temp.id('20'),
   'ADJ-51', 'service', 'PENDIENTE');

create or replace function pg_temp.url(p_bucket text, p_path text)
returns text
language sql
as $$
  select 'https://ref.supabase.co/storage/v1/object/public/' || p_bucket
    || '/' || p_path
$$;

-- Los archivos que sí están.
insert into storage.objects(bucket_id, name) values
  ('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/esta.pdf'),
  ('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/ajena.pdf'),
  ('job-images', pg_temp.id('02') || '/' || pg_temp.id('50') || '/otro-taller.pdf'),
  ('job-images', pg_temp.id('01') || '/' || pg_temp.id('52') || '/alta.pdf'),
  ('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/esta.jpg'),
  ('bike-images', pg_temp.id('01') || '/' || pg_temp.id('21') || '/ajena.jpg');

create or replace function pg_temp.error_of(p_sql text)
returns text
language plpgsql
as $$
begin
  execute p_sql;
  return null;
exception when others then
  return sqlstate || ' ' || sqlerrm;
end;
$$;

-- ============================================================================
-- Trabajos: el disparador
-- ============================================================================

select lives_ok(
  format($$update public.mechanic_jobs set image_urls = array[%L]
            where id = %L$$,
         pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/esta.pdf'),
         pg_temp.id('50')),
  'un adjunto nuevo que está, en la carpeta del trabajo, entra');

select matches(
  pg_temp.error_of(format(
    $$update public.mechanic_jobs set image_urls = image_urls || %L::text
       where id = %L$$,
    pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/borrada.pdf'),
    pg_temp.id('50'))),
  '^22023 .*ya no está en Storage',
  'uno cuyo archivo no está no entra');

select matches(
  pg_temp.error_of(format(
    $$update public.mechanic_jobs set image_urls = image_urls || %L::text
       where id = %L$$,
    pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/ajena.pdf'),
    pg_temp.id('50'))),
  '^22023 .*carpeta de otro trabajo',
  'ni uno de la carpeta de otro trabajo, aunque exista');

select matches(
  pg_temp.error_of(format(
    $$update public.mechanic_jobs set image_urls = image_urls || %L::text
       where id = %L$$,
    pg_temp.url('job-images', pg_temp.id('02') || '/' || pg_temp.id('50') || '/otro-taller.pdf'),
    pg_temp.id('50'))),
  '^22023 .*carpeta de otro trabajo',
  'ni uno de la carpeta de otro taller');

select is(
  (select image_urls from public.mechanic_jobs where id = pg_temp.id('50')),
  array[pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/esta.pdf')],
  'lo rechazado no quedó');

select lives_ok(
  format($$update public.mechanic_jobs set image_urls = image_urls || %L::text
            where id = %L$$,
         pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('50') || '/esta.pdf')
           || '?t=1#pagina',
         pg_temp.id('50')),
  'la consulta y el fragmento de la URL no son parte del nombre del archivo');
update public.mechanic_jobs
   set image_urls = image_urls[1:1]
 where id = pg_temp.id('50');

-- Lo que ya estaba se queda aunque su archivo falte; quitar siempre se puede.
-- (La API de Storage borra con esta marca; sin ella lo frena
-- `storage.protect_delete`.)
select set_config('storage.allow_delete_query', 'true', true);
delete from storage.objects
 where bucket_id = 'job-images'
   and name = pg_temp.id('01') || '/' || pg_temp.id('50') || '/esta.pdf';
select lives_ok(
  format($$update public.mechanic_jobs
             set image_urls = image_urls || %L::text, notes = 'otra nota'
           where id = %L$$,
         'https://media.invalid/foto.jpg', pg_temp.id('50')),
  'una URL que ya estaba no se juzga; una de otro sitio tampoco');
select lives_ok(
  format($$update public.mechanic_jobs set image_urls = '{}' where id = %L$$,
         pg_temp.id('50')),
  'quitar adjuntos siempre se puede');
select lives_ok(
  format($$update public.mechanic_jobs set image_urls = array[%L]
            where id = %L$$,
         pg_temp.url('vinabike-assets', 'mechanic_jobs/cliente/job_1.jpg'),
         pg_temp.id('50')),
  'uno de vinabike-assets (lo anterior) no se juzga');

-- ============================================================================
-- Bicis: el disparador, también la foto principal
-- ============================================================================

select lives_ok(
  format($$update public.bikes set image_urls = array[%L], image_url = %L
            where id = %L$$,
         pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/esta.jpg'),
         pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/esta.jpg'),
         pg_temp.id('20')),
  'una foto nueva que está, en la carpeta de la bici, entra');
select matches(
  pg_temp.error_of(format(
    $$update public.bikes set image_url = %L where id = %L$$,
    pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('20') || '/borrada.jpg'),
    pg_temp.id('20'))),
  '^22023 .*ya no está en Storage',
  'la foto principal cuyo archivo no está no entra');
select matches(
  pg_temp.error_of(format(
    $$update public.bikes set image_urls = image_urls || %L::text where id = %L$$,
    pg_temp.url('bike-images', pg_temp.id('01') || '/' || pg_temp.id('21') || '/ajena.jpg'),
    pg_temp.id('20'))),
  '^22023 .*carpeta de otro trabajo o bici',
  'ni la de otra bici');

-- ============================================================================
-- Por los comandos, como empleado
-- ============================================================================

set local role authenticated;

select matches(
  pg_temp.error_of(format($$select public.create_mechanic_job_v1(%L, %L::jsonb)$$,
    pg_temp.id('52')::text,
    jsonb_build_object(
      'id', pg_temp.id('52'), 'tenant_id', pg_temp.id('01'),
      'customer_id', pg_temp.id('10'), 'bike_id', pg_temp.id('20'),
      'job_type', 'service', 'workflow_kind', 'service', 'intake_kind', 'bike',
      'status', 'PENDIENTE', 'priority', 'NORMAL',
      'arrival_date', '2026-09-29T12:00:00Z',
      'image_urls', jsonb_build_array(
        pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('52') || '/alta.pdf'),
        pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('52') || '/borrada.pdf'))))),
  '^22023 .*ya no está en Storage',
  'el alta con un adjunto borrado se rechaza');
select is(
  (select count(*)::integer from public.mechanic_jobs where id = pg_temp.id('52')),
  0, 'y no crea el trabajo');

select lives_ok(
  format($$select public.create_mechanic_job_v1(%L, %L::jsonb)$$,
    pg_temp.id('52')::text,
    jsonb_build_object(
      'id', pg_temp.id('52'), 'tenant_id', pg_temp.id('01'),
      'customer_id', pg_temp.id('10'), 'bike_id', pg_temp.id('20'),
      'job_type', 'service', 'workflow_kind', 'service', 'intake_kind', 'bike',
      'status', 'PENDIENTE', 'priority', 'NORMAL',
      'arrival_date', '2026-09-29T12:00:00Z',
      'image_urls', jsonb_build_array(
        pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('52') || '/alta.pdf')))),
  'con el adjunto que está, en la carpeta del id que eligió el formulario, se crea');

select matches(
  pg_temp.error_of(format(
    $$select public.save_mechanic_job_lines_v1(%L, %L, null, null, '[]'::jsonb,
        %L::jsonb, null, false)$$,
    'adjuntos-51', pg_temp.id('51'),
    jsonb_build_object('image_urls', jsonb_build_object(
      'value', jsonb_build_array(
        pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/borrada.pdf')),
      'expected', '[]'::jsonb)))),
  '^22023 .*ya no está en Storage',
  'agregar desde la tabla uno borrado se rechaza');
select lives_ok(
  format(
    $$select public.save_mechanic_job_lines_v1(%L, %L, null, null, '[]'::jsonb,
        %L::jsonb, null, false)$$,
    'adjuntos-51-bien', pg_temp.id('51'),
    jsonb_build_object('image_urls', jsonb_build_object(
      'value', jsonb_build_array(
        pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/ajena.pdf')),
      'expected', '[]'::jsonb))),
  'y el suyo que está, entra');

reset role;

select is(
  (select image_urls from public.mechanic_jobs where id = pg_temp.id('51')),
  array[pg_temp.url('job-images', pg_temp.id('01') || '/' || pg_temp.id('51') || '/ajena.pdf')],
  'el trabajo tiene sólo el adjunto que está');

select * from finish();
rollback;
