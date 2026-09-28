-- Read-back de 20260927030000_bike_technical_fact_patch.
-- Antes de desplegar tiene que fallar contra producción: la tabla no existe.

-- Cada escritura a la ficha deja un recibo con su llave, lo aplicado y el
-- trabajo que la originó.
select 1 / (case when count(*) = 12 then 1 else 0 end) as tabla_de_recibos
from information_schema.columns
where table_schema = 'public'
  and table_name = 'bike_technical_fact_patches'
  and column_name in (
    'id', 'tenant_id', 'operation_key', 'payload_hash', 'bike_id',
    'profile_id', 'job_id', 'source', 'applied', 'result_snapshot',
    'created_by', 'completed_at'
  );

-- Una llave por taller: el reintento encuentra su recibo.
select 1 / (case when count(*) = 1 then 1 else 0 end) as llave_unica_por_taller
from pg_constraint
where conrelid = 'public.bike_technical_fact_patches'::regclass
  and contype = 'u'
  and pg_get_constraintdef(oid) = 'UNIQUE (tenant_id, operation_key)';

-- Los recibos no se escriben a mano.
select 1 / (case when
  (select relrowsecurity from pg_class
    where oid = 'public.bike_technical_fact_patches'::regclass)
  and not has_table_privilege('authenticated', 'public.bike_technical_fact_patches', 'INSERT')
  and not has_table_privilege('authenticated', 'public.bike_technical_fact_patches', 'UPDATE')
  and not has_table_privilege('authenticated', 'public.bike_technical_fact_patches', 'DELETE')
  and not has_table_privilege('anon', 'public.bike_technical_fact_patches', 'SELECT')
then 1 else 0 end) as recibos_sin_escritura_directa;

-- El comando es definer, lo ejecuta un empleado autenticado y nadie más.
select 1 / (case when
  (select prosecdef from pg_proc
    where oid = 'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
  and has_function_privilege('authenticated',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)', 'EXECUTE')
then 1 else 0 end) as comando_para_empleados;

-- La versión desplegada es la corregida tras las dos revisiones de Codex:
-- exige taller activo, confirmación esperada y el trabajo, no confirma
-- «desconocido», y ya no recibe el resumen del cliente (la firma de cinco
-- parámetros lo prueba arriba).
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%is_active_tenant_member(v_tenant_id)%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%expected_confirmed%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%''bikes.wheel_size''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    not like '%''suspensionLayout''%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%A service fact needs the job that confirmed it%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%cannot be confirmed as unknown%'
  and to_regprocedure('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb,jsonb)') is null
then 1 else 0 end) as version_corregida;

-- «Desconocido» se guarda como revisado, nunca confirmado.
select 1 / (case when count(*) = 0 then 1 else 0 end) as desconocido_sin_confirmar
  from public.bike_profiles p,
       jsonb_object_keys(coalesce(p.technical_profile->'values', '{}'::jsonb)) as k
 where lower(p.technical_profile->'values'->>k) in ('unknown', 'desconocido')
   and p.technical_profile->'confirmed'->k = 'true'::jsonb;
