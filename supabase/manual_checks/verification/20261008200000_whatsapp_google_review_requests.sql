-- Read-back de 20261008200000_whatsapp_google_review_requests. Antes de
-- desplegar tiene que fallar contra producción (la tabla, la función y la
-- tarea no existen).

select 1 / (case when
  to_regclass('public.whatsapp_review_requests') is not null
  and (select relrowsecurity from pg_class
        where oid = 'public.whatsapp_review_requests'::regclass)
  and has_table_privilege('authenticated', 'public.whatsapp_review_requests', 'SELECT')
  and not exists (
    select 1
      from unnest(array['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                        'REFERENCES', 'TRIGGER']) as privilege
     where has_table_privilege('authenticated', 'public.whatsapp_review_requests',
                               privilege))
  and not exists (
    select 1
      from unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                        'REFERENCES', 'TRIGGER']) as privilege
     where has_table_privilege('anon', 'public.whatsapp_review_requests', privilege))
  and exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'whatsapp_review_requests'
       and policyname = 'whatsapp_review_requests_staff_read'
       and cmd = 'SELECT'
       and qual like '%messaging_is_staff_in_tenant(tenant_id)%')
  and exists (
    select 1 from pg_constraint
     where conrelid = 'public.whatsapp_review_requests'::regclass
       and contype = 'u'
       and pg_get_constraintdef(oid) = 'UNIQUE (tenant_id, job_id)')
then 1 else 0 end) as una_fila_por_trabajo_y_sólo_lectura;

select 1 / (case when
  has_function_privilege('service_role',
    'public.process_whatsapp_review_requests_v1(timestamp with time zone)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.process_whatsapp_review_requests_v1(timestamp with time zone)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.process_whatsapp_review_requests_v1(timestamp with time zone)', 'EXECUTE')
  and (select prosecdef from pg_proc
        where oid = 'public.process_whatsapp_review_requests_v1(timestamp with time zone)'::regprocedure)
  and pg_get_functiondef('public.process_whatsapp_review_requests_v1(timestamp with time zone)'::regprocedure)
    like '%public.enqueue_whatsapp_message_v1(%'
  and pg_get_functiondef('public.process_whatsapp_review_requests_v1(timestamp with time zone)'::regprocedure)
    like '%''resena_google_v1''%'
  and pg_get_functiondef('public.process_whatsapp_review_requests_v1(timestamp with time zone)'::regprocedure)
    like '%interval ''365 days''%'
then 1 else 0 end) as envia_por_la_cola_una_vez_al_año;

select 1 / (case when exists (
  select 1 from cron.job
   where jobname = 'vinabike_whatsapp_review_requests'
     and schedule = '*/10 * * * *'
     and command = 'select public.process_whatsapp_review_requests_v1();'
     and active)
then 1 else 0 end) as tarea_cada_diez_minutos;
