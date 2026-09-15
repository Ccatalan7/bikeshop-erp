-- Read-back de `20260830040000_recoverable_supplier_portal_search`.
--
-- Falla ANTES del apply: cada aserción divide por cero cuando no se cumple, así
-- que un código 0 contra una base sin migrar no existe.

-- 1. Las dos columnas y la unicidad por tenant.
select 1 / (
  case when count(*) = 2 then 1 else 0 end
) as columnas_presentes
from information_schema.columns
where table_schema = 'public'
  and table_name = 'supplier_need_portal_searches'
  and column_name in ('operation_key', 'operation_request');

select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as indice_unico_por_tenant
from pg_indexes
where tablename = 'supplier_need_portal_searches'
  and indexname = 'supplier_need_portal_searches_tenant_operation_key_idx'
  and indexdef like '%UNIQUE%'
  and indexdef like '%tenant_id%'
  and indexdef like '%operation_key%';

-- 2. El resolvedor de sólo lectura existe, es STABLE y no lo puede llamar anon.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as resolvedor_es_de_solo_lectura
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'supplier_need_portal_search_by_operation_key_v1'
  and p.provolatile = 's'
  and p.prosecdef;

select 1 / (
  case when count(*) = 0 then 1 else 0 end
) as anon_no_puede_resolver
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'supplier_need_portal_search_by_operation_key_v1'
  and grantee = 'anon';

-- 3. El recibo acepta la clave y la reusa en vez de duplicar.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as recibo_acepta_clave
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'record_supplier_need_portal_search_v1'
  and pg_get_function_identity_arguments(p.oid) like '%p_operation_key text%';

select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as recibo_reusa_en_vez_de_insertar
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'record_supplier_need_portal_search_v1'
  and pg_get_functiondef(p.oid) like '%''replay'', true%'
  and pg_get_functiondef(p.oid) like '%pertenece a otra búsqueda%';

-- 4. Una tienda que contesta por API de catálogo ya puede guardar.
select 1 / (
  case when count(*) = 1 then 1 else 0 end
) as api_de_catalogo_puede_guardar
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'record_supplier_need_portal_search_v1'
  and pg_get_functiondef(p.oid) like '%catalog_api%';

-- 5. Y las sondas reales que dependen de eso siguen habilitadas.
select 1 / (
  case when count(*) >= 2 then 1 else 0 end
) as tiendas_con_api_registradas
from public.supplier_portal_probes
where is_enabled
  and need_search_adapter -> 'catalog_api' is not null;
