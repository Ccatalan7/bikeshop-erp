-- Read-back de la migración 20260829120000. Se corre DESPUÉS del rollout.
--
-- **Falla antes del apply y pasa después.** La versión anterior sólo
-- proyectaba conteos: salía con código 0 contra una base sin migrar, así que
-- «corrió y no dijo nada» se leía igual que «quedó bien». Cada aserción de
-- abajo divide por cero cuando la condición no se cumple, que es la forma que
-- este repo usa para que un read-back falso sea imposible de ignorar.
--
-- Primero el diagnóstico —para leer qué hay—, después las aserciones.

-- ===========================================================================
-- Diagnóstico
-- ===========================================================================

select
  column_name,
  data_type,
  is_nullable
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'supplier_portal_probes'
     and column_name in ('catalog_taxonomy', 'catalog_taxonomy_discovered_at'))
    or (table_name = 'supplier_need_portal_searches'
        and column_name = 'coverage')
  )
order by table_name, column_name;

select
  proc.proname,
  proc.pronargs,
  proc.prosecdef,
  pg_get_userbyid(proc.proowner) as owner,
  has_function_privilege('authenticated', proc.oid, 'EXECUTE') as authenticated_exec,
  has_function_privilege('anon', proc.oid, 'EXECUTE') as anon_exec
from pg_proc proc
join pg_namespace namespace on namespace.oid = proc.pronamespace
where namespace.nspname = 'public'
  and proc.proname in (
    'record_supplier_need_portal_search_v1',
    'record_supplier_portal_catalog_taxonomy_v1',
    'supplier_portal_probes_guard_catalog_cache'
  )
order by proc.proname, proc.pronargs;

select
  trigger.tgname,
  trigger.tgenabled,
  pg_get_triggerdef(trigger.oid) as definition
from pg_trigger trigger
where trigger.tgrelid = 'public.supplier_portal_probes'::regclass
  and not trigger.tgisinternal;

select
  constraint_.conname,
  pg_get_constraintdef(constraint_.oid) as definition
from pg_constraint constraint_
where constraint_.conrelid = 'public.supplier_need_portal_searches'::regclass
  and constraint_.conname = 'supplier_need_portal_searches_coverage_check';

select
  supplier.name,
  probe.need_search_adapter -> 'catalog_route' ->> 'page_size' as page_size,
  probe.need_search_adapter ->> 'result_cap' as result_cap,
  probe.need_search_adapter -> 'taxonomy_discovery' ->> 'child_field'
    as child_field,
  -- Vía `to_jsonb` a propósito: el diagnóstico tiene que poder correr ANTES
  -- del apply. Nombrar la columna directamente aborta con un error de parseo
  -- y nadie llega a leer la aserción, que es la que dice qué falta.
  to_jsonb(probe) ->> 'catalog_taxonomy_discovered_at'
    as catalog_taxonomy_discovered_at
from public.supplier_portal_probes probe
join public.suppliers supplier
  on supplier.id = probe.supplier_id
 and supplier.tenant_id = probe.tenant_id
where supplier.name = 'RBX';

-- ===========================================================================
-- Aserciones. Cualquiera que no se cumpla aborta el read-back.
-- ===========================================================================

-- 1. Las columnas del caché y de la cobertura existen.
select 1 / (case when (
  select count(*) from information_schema.columns
  where table_schema = 'public'
    and table_name = 'supplier_portal_probes'
    and column_name in ('catalog_taxonomy', 'catalog_taxonomy_discovered_at')
) = 2 then 1 else 0 end) as probe_cache_columns_present;

select 1 / (case when exists (
  select 1 from information_schema.columns
  where table_schema = 'public'
    and table_name = 'supplier_need_portal_searches'
    and column_name = 'coverage'
) then 1 else 0 end) as coverage_column_present;

-- 2. Una cobertura completa sólo puede venir de una enumeración terminada.
select 1 / (case when exists (
  select 1 from pg_constraint
  where conrelid = 'public.supplier_need_portal_searches'::regclass
    and conname = 'supplier_need_portal_searches_coverage_check'
    and pg_get_constraintdef(oid) like '%enumerated%'
) then 1 else 0 end) as coverage_cannot_lie_about_completeness;

-- 3. El recibo acepta la cobertura, y la firma vieja ya no está para que una
--    llamada ambigua no la elija.
select 1 / (case when (
  select count(*) from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'record_supplier_need_portal_search_v1'
    and proc.pronargs = 8
) = 1 then 1 else 0 end) as receipt_accepts_coverage;

select 1 / (case when (
  select count(*) from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'record_supplier_need_portal_search_v1'
    and proc.pronargs = 7
) = 0 then 1 else 0 end) as old_receipt_signature_removed;

select 1 / (case when exists (
  select 1 from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'record_supplier_portal_catalog_taxonomy_v1'
    and proc.pronargs = 2
) then 1 else 0 end) as taxonomy_receipt_present;

-- 4. **La protección del caché.** Sin el disparador, `anon` y `authenticated`
--    escriben estas columnas por PostgREST sin pasar por el recibo: la tabla
--    les concede DML completo y su política es `for all` sólo por tenant.
select 1 / (case when exists (
  select 1 from pg_trigger trigger
  where trigger.tgrelid = 'public.supplier_portal_probes'::regclass
    and trigger.tgname = 'supplier_portal_probes_guard_catalog_cache'
    and not trigger.tgisinternal
    and trigger.tgenabled in ('O', 'A')
) then 1 else 0 end) as catalog_cache_guard_enabled;

-- Si el guardián corriera como `security definer`, su `current_user` sería su
-- propio dueño y se auto-aprobaría siempre: la protección sería decorativa.
select 1 / (case when exists (
  select 1 from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and proc.proname = 'supplier_portal_probes_guard_catalog_cache'
    and not proc.prosecdef
) then 1 else 0 end) as catalog_cache_guard_runs_as_caller;

-- 5. Permisos efectivos de las funciones, no la intención de un `grant`.
select 1 / (case when (
  select bool_and(
    has_function_privilege('authenticated', proc.oid, 'EXECUTE')
    and not has_function_privilege('anon', proc.oid, 'EXECUTE')
  )
  from pg_proc proc
  join pg_namespace namespace on namespace.oid = proc.pronamespace
  where namespace.nspname = 'public'
    and (
      (proc.proname = 'record_supplier_need_portal_search_v1'
       and proc.pronargs = 8)
      or proc.proname = 'record_supplier_portal_catalog_taxonomy_v1'
    )
) then 1 else 0 end) as receipts_are_authenticated_only;

-- 6. La fila real de RBX quedó con su ruta y su tope. Ésta es la afirmación
--    que NO puede vivir en pgTAP: depende de datos sembrados en producción.
select 1 / (case when exists (
  select 1
  from public.supplier_portal_probes probe
  join public.suppliers supplier
    on supplier.id = probe.supplier_id
   and supplier.tenant_id = probe.tenant_id
  where supplier.name = 'RBX'
    and probe.need_search_adapter -> 'catalog_route' ->> 'page_size' = '9'
    and probe.need_search_adapter -> 'catalog_route' ->> 'url_template'
        like '%Clasificacion2={node}%'
    and (probe.need_search_adapter ->> 'result_cap')::int = 120
    and probe.need_search_adapter -> 'taxonomy_discovery' ->> 'child_field'
        = 'Clasificacion2'
) then 1 else 0 end) as rbx_route_and_cap_seeded;

-- 7. Ningún adaptador puede pedirle al cliente más filas de las que el recibo
--    acepta: el tope del cliente y el del recibo se mueven juntos.
select 1 / (case when not exists (
  select 1 from public.supplier_portal_probes probe
  where coalesce((probe.need_search_adapter ->> 'result_cap')::int, 40) > 120
) then 1 else 0 end) as no_adapter_exceeds_the_receipt_cap;
