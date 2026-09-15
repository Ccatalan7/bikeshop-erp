-- 2026-09-15 · A stale supplier-need portal search is rejected definitively.
--
-- `supplier_need_portal_search_scope_guard()` rejected a receipt whose stamped
-- interpretation no longer matched the need with errcode 40001
-- (serialization_failure). To every client that code means «retry the same
-- transaction», and the ERP does exactly that. A retry of the same receipt can
-- never succeed, so one client retried it ~900 times per second for 16 days:
-- 1.14 billion aborted transactions, PostgREST's pool saturated, and Supabase's
-- «high CPU usage» alert every week. Class 23 is what the ERP classifies as a
-- rejection that is not retried (see classifyStoreFailure in
-- lib/modules/hr/services/payroll_employee_payment_method_command.dart).
--
-- Deployed live on 2026-09-15 19:01 UTC through the owner-authorised Supabase
-- MCP connector; the storm stopped within the same minute. The feature's own
-- migrations are not in this repository's governed stream (they were deployed
-- from another checkout), so this file only replaces the function when the
-- feature's tables exist and is a no-op elsewhere. The checkout that owns the
-- feature must carry the same body.

do $migration$
begin
  if to_regclass('public.supplier_need_portal_searches') is null
     or to_regclass('public.supply_needs') is null
     or to_regclass('public.supply_need_interpretation_revisions') is null then
    raise notice
      'supplier need portal search feature absent; scope guard not touched';
    return;
  end if;

  execute $fn$
create or replace function public.supplier_need_portal_search_scope_guard()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
declare
  v_need_version bigint;
  v_revision_no bigint;
  v_category_id uuid;
  v_technical_family text;
begin
  select need.version
  into v_need_version
  from public.supply_needs need
  where need.tenant_id = new.tenant_id
    and need.id = new.supply_need_id;
  if not found then
    raise exception 'Supply need not found' using errcode = 'P0002';
  end if;

  select revision.revision_no, revision.category_id, revision.technical_family
  into v_revision_no, v_category_id, v_technical_family
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = new.tenant_id
    and revision.supply_need_id = new.supply_need_id
  order by revision.revision_no desc
  limit 1;

  if v_revision_no is null or v_category_id is null then
    raise exception 'Need search requires a resolved category'
      using errcode = '23514';
  end if;

  -- **Validar, no reetiquetar.** Antes este disparador SOBRESCRIBÍA la estampa
  -- con la revisión vigente al momento del `insert`. Un recorrido que empezó
  -- en la revisión N y termina después de que alguien guardó N+1 quedaba
  -- marcado como N+1: filas leídas contra una ficha, presentadas como
  -- respuesta de otra, y sin ninguna señal de que eso pasó. El estampado lo
  -- captura quien inicia el recorrido y acá se COMPRUEBA; si no calza, el
  -- recibo se rechaza y esa lectura se pierde, que es el resultado correcto.
  if new.need_version_at_search is null
     or new.interpretation_revision_no is null
     or new.interpretation_category_id is null then
    raise exception 'Need search must declare the interpretation it answered'
      using errcode = '23514';
  end if;

  -- **Rechazo definitivo, no `40001`.** `serialization_failure` le dice a
  -- cualquier cliente «reintenta la misma transacción». Un recibo estampado
  -- con una interpretación que ya no existe no puede aceptarse nunca, así que
  -- reintentarlo sólo repite el rechazo. 2026-09-15: un cliente reintentó este
  -- rechazo ~900 veces por segundo durante 16 días (1.14 mil millones de
  -- transacciones abortadas) y sostuvo la base sobre el 80 % de CPU. La
  -- clase 23 es la que el ERP clasifica como rechazo que no se reintenta.
  if new.interpretation_revision_no <> v_revision_no
     or new.interpretation_category_id <> v_category_id
     or new.interpretation_technical_family is distinct from v_technical_family
     or new.need_version_at_search <> v_need_version then
    raise exception 'La necesidad cambió mientras se consultaba al proveedor; '
      'esa lectura ya no responde lo que se está preguntando.'
      using errcode = '23514',
        detail = format(
          'supply_need=%s expected version %s revision %s, current version %s revision %s',
          new.supply_need_id, new.need_version_at_search,
          new.interpretation_revision_no, v_need_version, v_revision_no
        ),
        hint = 'Vuelve a leer la necesidad y repite la búsqueda contra su interpretación vigente.';
  end if;

  return new;
end;
$function$
  $fn$;

  if not exists (
    select 1
    from pg_trigger
    where tgrelid = 'public.supplier_need_portal_searches'::regclass
      and tgname = 'supplier_need_portal_search_scope_guard'
  ) then
    execute 'create trigger supplier_need_portal_search_scope_guard '
      'before insert on public.supplier_need_portal_searches '
      'for each row execute function public.supplier_need_portal_search_scope_guard()';
  end if;
end
$migration$;
