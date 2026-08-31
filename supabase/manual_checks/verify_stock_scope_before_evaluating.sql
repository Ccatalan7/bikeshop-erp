-- Read-back de 20260831120000_stock_scope_before_evaluating.
-- Sólo lectura. Ejecutar con scripts/db/query.sh production --format table
-- --file supabase/manual_checks/verify_stock_scope_before_evaluating.sql.
-- Antes del cambio pasan permisos/equivalencia y FALLA el último assert.
-- Después deben pasar los tres. No confundir este caso real, deliberadamente
-- acotado, con una comprobación de todas las necesidades o con latencia HTTP.

-- La firma exacta debe existir y conservar los permisos y atributos leídos
-- antes del cambio. Un conjunto vacío no puede hacer pasar el assert.
select 1 / case when count(*) = 1 and bool_and(
  procedure.prosecdef
  and procedure.provolatile = 's'
  and procedure.prorettype = 'jsonb'::regtype
  and pg_get_userbyid(procedure.proowner) = 'postgres'
  and procedure.pronargdefaults = 1
  and pg_get_expr(procedure.proargdefaults, 0) = '400'
  and procedure.proconfig = array['search_path=pg_catalog, public, pg_temp']
  and not has_function_privilege('anon', procedure.oid, 'execute')
  and not has_function_privilege('authenticated', procedure.oid, 'execute')
  and not has_function_privilege('service_role', procedure.oid, 'execute')
  and not exists (
    select 1
    from aclexplode(coalesce(
      procedure.proacl, acldefault('f', procedure.proowner)
    )) permission
    where permission.privilege_type = 'EXECUTE'
      and permission.grantee <> procedure.proowner
  )
) then 1 else 0 end as firma_y_privilegios_conservados
from pg_proc procedure
where procedure.oid = to_regprocedure(
  'public.supply_need_eligible_products_internal_v1(uuid,uuid,integer)'
);

-- Caso observado: necesidad de pastillas del tenant de la prueba real. Se
-- exige carril familia, categoría conocida, predicados técnicos y un universo
-- no vacío dentro del techo. Si el owner cambia su identidad o contexto, el
-- assert falla y se revisa el caso; no se lo interpreta como éxito vacío.
--
-- Se compara el JSON completo (metadatos y todos los items EN ORDEN,
-- incluidos matchDetail), no sólo conteos o un hash de id/estado. El esperado
-- usa la misma autoridad de predicados pero materializa el alcance: repetir
-- la forma defectuosa en esta prueba volvería a pagar 1554 evaluaciones.
with recursive target as (
  select
    '5443b130-cc28-45af-a420-cd500b288890'::uuid as tenant_id,
    'b9484ed6-52d8-45cb-8b50-540caabf1d4e'::uuid as need_id,
    '7c580490-496d-4c12-b0ce-1239466b9359'::uuid as category_id
), context as materialized (
  select target.tenant_id, target.need_id,
    target.category_id as expected_category_id,
    resolved.category_id, resolved.product_id, resolved.identity_state,
    resolved.need_version, resolved.revision_no,
    (
      select coalesce(jsonb_agg(entry.value), '[]'::jsonb)
      from jsonb_array_elements(resolved.constraints) entry(value)
      where entry.value ? 'field' and entry.value ? 'operator'
        and entry.value ? 'values'
    ) as predicates
  from target
  cross join lateral public.supply_need_resolution_context_internal_v1(
    target.tenant_id, target.need_id
  ) resolved
), category_scope as (
  select category.id
  from public.product_categories category
  cross join context
  where category.tenant_id = context.tenant_id
    and category.id = context.category_id
    and category.is_active is true
  union all
  select child.id
  from public.product_categories child
  join category_scope parent on child.parent_id = parent.id
  cross join context
  where child.tenant_id = context.tenant_id and child.is_active is true
), scoped as materialized (
  select product.id as product_id
  from public.products product
  cross join context
  where product.tenant_id = context.tenant_id
    and product.is_active is true
    and not coalesce(product.is_service, false)
    and coalesce(product.product_type, 'product') <> 'service'
    and product.category_id in (select id from category_scope)
), evaluated as materialized (
  select scoped.product_id,
    public.supply_need_match_detail_internal_v1(
      context.tenant_id, scoped.product_id, context.predicates
    ) as match_detail
  from scoped cross join context
), stated as (
  select evaluated.product_id, evaluated.match_detail,
    public.supply_need_match_state_internal_v1(
      evaluated.match_detail, jsonb_array_length(context.predicates)
    ) as match_state
  from evaluated cross join context
), expected_items as (
  select coalesce(jsonb_agg(jsonb_build_object(
    'productId', stated.product_id,
    'matchState', stated.match_state,
    'matchDetail', stated.match_detail
  ) order by stated.product_id), '[]'::jsonb) as items
  from stated
  where stated.match_state <> 'conflict'
), comparison as materialized (
  select context.need_version, context.revision_no,
    context.product_id is null
      and context.identity_state <> 'confirmed'
      and context.category_id = context.expected_category_id
      and jsonb_array_length(context.predicates) > 0 as context_is_family,
    (select count(*) from scoped) as universe_size,
    jsonb_build_object(
      'status', 'ok',
      'lane', 'family',
      'categoryId', context.category_id,
      'universeSize', (select count(*) from scoped),
      'safeLimit', 400,
      'predicateCount', jsonb_array_length(context.predicates),
      'items', expected_items.items
    ) as expected,
    -- También ejercita que la firma usada sin tercer argumento siga viva.
    public.supply_need_eligible_products_internal_v1(
      context.tenant_id, context.need_id
    ) as actual
  from context cross join expected_items
)
select
  1 / case when count(*) = 1 and bool_and(
    context_is_family
    and universe_size between 1 and 400
    and expected = actual
  ) then 1 else 0 end as respuesta_completa_identica,
  max(need_version) as need_version,
  max(revision_no) as revision_no,
  max(universe_size) as productos_evaluados,
  max(jsonb_array_length(actual -> 'items')) as items_devueltos,
  max(md5((actual -> 'items')::text)) as huella_items_ordenados
from comparison;

-- Este último assert discrimina el cambio: la definición actual falla, la
-- corregida debe pasar. Firma inexistente/otra sobrecarga tampoco pasan.
-- La huella es del prosrc del archivo revisado y aplicado en local: poner
-- estas palabras sólo en un comentario de la definición anterior no alcanza.
select 1 / case when count(*) = 1 and bool_and(
  md5(procedure.prosrc) = '51c2d2f02e9c8c436a7a578d053991dd'
  and pg_get_functiondef(procedure.oid) like '%scoped as materialized%'
  and pg_get_functiondef(procedure.oid) like '%evaluated as materialized%'
  and pg_get_functiondef(procedure.oid) like '%from scoped%'
  and pg_get_functiondef(procedure.oid)
    not like '%p_tenant_id, product.id, v_predicates%'
) then 1 else 0 end as alcance_cerrado_antes_del_juicio
from pg_proc procedure
where procedure.oid = to_regprocedure(
  'public.supply_need_eligible_products_internal_v1(uuid,uuid,integer)'
);
