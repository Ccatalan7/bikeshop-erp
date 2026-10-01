-- Read-back de 20260929020000_managed_image_urls_exist. Antes de desplegar
-- tiene que fallar contra producción (las funciones y los disparadores no
-- existen).

select 1 / (case when
  exists (
    select 1 from pg_trigger
     where tgrelid = 'public.mechanic_jobs'::regclass
       and tgname = 'trg_mechanic_job_image_urls_exist'
       and not tgisinternal and tgenabled <> 'D')
  and exists (
    select 1 from pg_trigger
     where tgrelid = 'public.bikes'::regclass
       and tgname = 'trg_bike_image_urls_exist'
       and not tgisinternal and tgenabled <> 'D')
then 1 else 0 end) as disparadores_de_adjuntos;

select 1 / (case when
  pg_get_functiondef('public.managed_image_url_problem(text,text,text)'::regprocedure)
    like '%storage.objects%'
  and pg_get_functiondef('public.mechanic_job_image_urls_exist()'::regprocedure)
    like '%''job-images''%'
  and pg_get_functiondef('public.bike_image_urls_exist()'::regprocedure)
    like '%''bike-images''%'
  and not exists (
    select 1
      from unnest(array['anon', 'authenticated', 'service_role']) as role_name,
           unnest(array[
             'public.managed_image_url_problem(text,text,text)',
             'public.mechanic_job_image_urls_exist()',
             'public.bike_image_urls_exist()']) as fn
     where has_function_privilege(role_name, fn, 'EXECUTE'))
then 1 else 0 end) as regla_de_archivo_y_carpeta;
