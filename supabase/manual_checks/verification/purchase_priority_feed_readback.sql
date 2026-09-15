-- Read-back de la prioridad de compra. Falla a nivel SQL si no quedó instalada.
--
-- **Corrección 2026-08-17.** La primera versión de este archivo sólo grepeaba
-- el TEXTO de la función. Pasó en verde con una función que no compilaba su
-- consulta: `supply_needs.product_name` no existe, y el error sólo aparece al
-- ejecutarla. Una verificación que no ejecuta no verifica nada.
--
-- Por eso lo primero es correrla de verdad, con un tenant real, y exigir una
-- forma de respuesta.

-- El camino guardado de sólo-lectura no admite bloques que manejen
-- transacción, así que la ejecución va como consulta: el `from ctx` obliga a
-- que el contexto de tenant se fije antes de llamar la función.
-- Sentencia aparte: dentro de un CTE el planificador puede evaluar la función
-- antes de que el contexto quede fijado. El archivo corre en una sola
-- transacción, así que un `set_config` local previo sigue vigente.
--
-- `user_tenant_id()` compara `auth.uid()` contra `user_profiles.user_id`, y
-- exige perfil y tenant activos, y exactamente un perfil. Cualquier usuario que
-- cumpla eso sirve para probar que la función corre de verdad.
select set_config(
  'request.jwt.claim.sub',
  (select profile.user_id::text
     from public.user_profiles profile
     join public.tenants tenant
       on tenant.id = profile.tenant_id
      and tenant.is_active is true
    where profile.is_active is true
    group by profile.user_id
   having count(*) = 1
    limit 1),
  true
) as tenant_context_ready;

with feed as (
  select public.purchase_priority_feed_v1(5, 120) as payload
)
select
  1 / (case when (payload->>'status') in ('success', 'verifiedEmpty')
        then 1 else 0 end) as feed_executes,
  1 / (case when jsonb_typeof(payload->'items') = 'array'
        then 1 else 0 end) as feed_returns_a_list,
  -- Cada fila debe traer su razón: es lo que transfiere la experiencia.
  1 / (case when not exists (
        select 1 from jsonb_array_elements(payload->'items') item
        where coalesce(btrim(item.value->>'reason'), '') = ''
      ) then 1 else 0 end) as every_row_carries_its_reason
from feed;

select 1 / (case when exists (
  select 1 from pg_proc
   where proname = 'purchase_priority_feed_v1'
     and pg_get_function_identity_arguments(oid) = 'p_limit integer, p_rotation_days integer'
) then 1 else 0 end) as priority_feed_present;

-- Sólo personal autenticado. Anónimo jamás.
select 1 / (case when has_function_privilege(
  'authenticated', 'public.purchase_priority_feed_v1(integer,integer)', 'execute'
) and not has_function_privilege(
  'anon', 'public.purchase_priority_feed_v1(integer,integer)', 'execute'
) then 1 else 0 end) as priority_feed_acl;

-- El filtro que hace útil la lista: sin rotación real, un quiebre no es
-- urgencia. Sin este join la lista pasa de ~100 filas a más de 1.100.
select 1 / (case when pg_get_functiondef(
  'public.purchase_priority_feed_v1(integer,integer)'::regprocedure
) like '%join rotation on rotation.product_id = product.id%'
  then 1 else 0 end) as rotation_filter_present;

-- Nunca se propone lo que ya está tomado.
select 1 / (case when pg_get_functiondef(
  'public.purchase_priority_feed_v1(integer,integer)'::regprocedure
) like '%already_needed%' then 1 else 0 end) as open_needs_excluded;

-- Cada fila explica por qué está ahí.
select 1 / (case when pg_get_functiondef(
  'public.purchase_priority_feed_v1(integer,integer)'::regprocedure
) like '%''reason'', reason%' then 1 else 0 end) as reason_travels_with_row;
