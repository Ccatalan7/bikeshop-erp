-- Read-back de 20260929010000_create_mechanic_job. Antes de desplegar tiene
-- que fallar contra producción (la tabla y las funciones no existen).

select 1 / (case when
  to_regclass('public.mechanic_job_creations') is not null
  and (select relrowsecurity from pg_class
        where oid = 'public.mechanic_job_creations'::regclass)
  and not has_table_privilege('authenticated', 'public.mechanic_job_creations', 'SELECT')
  and not has_table_privilege('authenticated', 'public.mechanic_job_creations', 'INSERT')
  and not has_table_privilege('authenticated', 'public.mechanic_job_creations', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.mechanic_job_creations', 'DELETE')
  and not has_table_privilege('anon', 'public.mechanic_job_creations', 'SELECT')
  and not exists (
    select 1
      from unnest(array['anon', 'authenticated']) as role_name,
           unnest(array['SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE',
                        'REFERENCES', 'TRIGGER']) as privilege
     where has_table_privilege(role_name, 'public.mechanic_job_creations',
                               privilege))
then 1 else 0 end) as recibos_del_alta;

select 1 / (case when
  has_function_privilege('authenticated',
    'public.create_mechanic_job_v1(text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.create_mechanic_job_v1(text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.create_mechanic_job_v1(text,jsonb)', 'EXECUTE')
  and (select prosecdef from pg_proc
        where oid = 'public.create_mechanic_job_v1(text,jsonb)'::regprocedure)
  and pg_get_functiondef('public.create_mechanic_job_v1(text,jsonb)'::regprocedure)
    like '%is_active_tenant_member(v_tenant_id)%'
  and pg_get_functiondef('public.create_mechanic_job_v1(text,jsonb)'::regprocedure)
    like '%''Trabajo creado''%'
then 1 else 0 end) as alta_con_llave;

select 1 / (case when
  has_function_privilege('authenticated',
    'public.get_mechanic_job_creation_v1(text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.get_mechanic_job_creation_v1(text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.get_mechanic_job_creation_v1(text,jsonb)', 'EXECUTE')
  and pg_get_functiondef('public.get_mechanic_job_creation_v1(text,jsonb)'::regprocedure)
    like '%receipt.tenant_id = v_tenant_id%'
  and pg_get_functiondef('public.get_mechanic_job_creation_v1(text,jsonb)'::regprocedure)
    like '%receipt.payload_hash = md5(p_job::text)%'
  and to_regprocedure('public.get_mechanic_job_creation_v1(text)') is null
then 1 else 0 end) as recibo_por_llave_y_taller;
