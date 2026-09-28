-- Lectura ejecutable tras 20260928002200. Sólo tres columnas visibles para el
-- empleado del tenant; RLS mantiene la frontera de filas.
select
  has_table_privilege('authenticated', 'public.bike_technical_fact_patches', 'SELECT')
    as authenticated_table_select,
  has_column_privilege('authenticated', 'public.bike_technical_fact_patches', 'id', 'SELECT')
    as authenticated_id_select,
  has_column_privilege('authenticated', 'public.bike_technical_fact_patches', 'tenant_id', 'SELECT')
    as authenticated_tenant_select,
  has_column_privilege('authenticated', 'public.bike_technical_fact_patches', 'operation_key', 'SELECT')
    as authenticated_key_select,
  has_column_privilege('authenticated', 'public.bike_technical_fact_patches', 'payload_hash', 'SELECT')
    as authenticated_payload_select,
  has_table_privilege('anon', 'public.bike_technical_fact_patches', 'SELECT')
    as anon_table_select;

select 1 / (case when
  not has_table_privilege('authenticated', 'public.bike_technical_fact_patches', 'SELECT')
  and has_column_privilege('authenticated', 'public.bike_technical_fact_patches', 'id', 'SELECT')
  and has_column_privilege('authenticated', 'public.bike_technical_fact_patches', 'tenant_id', 'SELECT')
  and has_column_privilege('authenticated', 'public.bike_technical_fact_patches', 'operation_key', 'SELECT')
  and not has_column_privilege('authenticated', 'public.bike_technical_fact_patches', 'payload_hash', 'SELECT')
  and not has_table_privilege('anon', 'public.bike_technical_fact_patches', 'SELECT')
  and not has_column_privilege('anon', 'public.bike_technical_fact_patches', 'id', 'SELECT')
  and exists (
    select 1 from pg_class
     where oid = 'public.bike_technical_fact_patches'::regclass
       and relrowsecurity
  )
  and exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename = 'bike_technical_fact_patches'
       and policyname = 'bike_technical_fact_patches_select'
       and cmd = 'SELECT'
       and 'authenticated' = any(roles)
       and qual = '(tenant_id = user_tenant_id())'
  )
then 1 else 0 end) as receipt_lookup_grant_is_narrow_and_tenant_scoped;
