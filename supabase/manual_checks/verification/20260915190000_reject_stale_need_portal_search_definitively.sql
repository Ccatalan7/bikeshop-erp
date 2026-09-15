-- Read-only read-back for 20260915190000_reject_stale_need_portal_search_definitively.
--
-- Cada `select 1/(…)` falla a nivel SQL (division by zero) cuando la
-- definición esperada no está; sin `begin`/`end`, que el runner de sólo
-- lectura rechaza.

-- 1. El guardián rechaza la estampa vieja con 23514 y ya no emite 40001.
with guard as (
  select prosrc,
         proacl::text as acl,
         prosecdef,
         pg_get_userbyid(proowner) as owner_name,
         to_jsonb(proconfig) as settings
  from pg_proc
  where proname = 'supplier_need_portal_search_scope_guard'
    and pronamespace = 'public'::regnamespace
)
select 1 / (case
  when count(*) = 1
   and bool_and(prosrc like '%La necesidad cambió mientras se consultaba al proveedor;%')
   and bool_and(prosrc like '%using errcode = ''23514'',%')
   and bool_and(prosrc like '%hint = ''Vuelve a leer la necesidad%')
   and bool_and(prosrc not like '%errcode = ''40001''%')
   and bool_and(prosecdef)
   and bool_and(owner_name = 'postgres')
   and bool_and(acl = '{postgres=X/postgres}')
   and bool_and(settings = '["search_path=pg_catalog, public, pg_temp"]'::jsonb)
  then 1 else 0 end) as stale_receipt_rejected_definitively
from guard;

-- 2. El disparador sigue montado y habilitado sobre los recibos.
select 1 / (case
  when count(*) = 1 and bool_and(tgenabled = 'O') then 1 else 0 end)
  as scope_guard_trigger_enabled
from pg_trigger
where tgrelid = 'public.supplier_need_portal_searches'::regclass
  and tgname = 'supplier_need_portal_search_scope_guard'
  and not tgisinternal;
