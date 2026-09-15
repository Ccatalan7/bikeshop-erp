-- Read-back de la Fase A: la categoría sobrevive a la captura.
-- Falla a nivel SQL —división por cero o error de ejecución— si la migración
-- 20260817150000 no quedó instalada, o si quedó instalada pero rota.
--
-- Regla del contrato: todo read-back de una función LA EJECUTA. Comprobar la
-- definición sirve sólo para fijar invariantes de forma.
--
-- Las funciones públicas de esta migración exigen autoridad de asistente
-- (`assistant_require_capability_internal_v1`), que no existe fuera de una
-- sesión del gateway. Por eso lo que se ejecuta aquí es el normalizador
-- interno con un tenant explícito —el camino guardado corre con rol
-- privilegiado y sin RLS— y de las públicas se exige firma, ACL y las
-- invariantes de forma que las hacen distintas de sus `*_v1`.

-- ── 1. Presencia y firma exacta ────────────────────────────────────────────
select 1 / (case when
     to_regprocedure('public.assistant_inspect_inventory_schema_v3(text,text)') is not null
 and to_regprocedure('public.supply_request_category_scope_internal_v1(uuid,uuid)') is not null
 and to_regprocedure('public.normalize_supply_request_items_internal_v2(uuid,jsonb)') is not null
 and to_regprocedure('public.assistant_prepare_supply_request_v2(jsonb,text)') is not null
 and to_regprocedure('public.create_supply_need_batch_v2(text,jsonb,text,uuid,text)') is not null
  then 1 else 0 end) as phase_a_functions_present;

-- ── 2. ACL: personal autenticado sí, anónimo jamás ─────────────────────────
select 1 / (case when
     has_function_privilege('authenticated', 'public.assistant_inspect_inventory_schema_v3(text,text)', 'execute')
 and has_function_privilege('authenticated', 'public.assistant_prepare_supply_request_v2(jsonb,text)', 'execute')
 and has_function_privilege('authenticated', 'public.create_supply_need_batch_v2(text,jsonb,text,uuid,text)', 'execute')
 and not has_function_privilege('anon', 'public.assistant_inspect_inventory_schema_v3(text,text)', 'execute')
 and not has_function_privilege('anon', 'public.assistant_prepare_supply_request_v2(jsonb,text)', 'execute')
 and not has_function_privilege('anon', 'public.create_supply_need_batch_v2(text,jsonb,text,uuid,text)', 'execute')
  then 1 else 0 end) as phase_a_acl;

-- Los internos no se exponen a nadie del cliente.
select 1 / (case when
     not has_function_privilege('authenticated', 'public.normalize_supply_request_items_internal_v2(uuid,jsonb)', 'execute')
 and not has_function_privilege('authenticated', 'public.supply_request_category_scope_internal_v1(uuid,uuid)', 'execute')
  then 1 else 0 end) as phase_a_internals_are_internal;

-- ── 3. El resolutor de categoría se EJECUTA y devuelve identidad y ruta ────
with tenant as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), category as (
  select scope.id
  from public.product_categories scope, tenant
  where scope.tenant_id = tenant.tenant_id
    and exists (
      select 1 from public.category_tech_mappings mapping
      where mapping.category_id = scope.id and mapping.status = 'active'
    )
  order by (
    select count(*) from public.products product
    where product.category_id = scope.id and product.is_active is true
  ) desc, scope.id
  limit 1
), resolved as (
  select scope.category_id, scope.category_path, scope.technical_family,
         scope.template_id
  from tenant, category,
       public.supply_request_category_scope_internal_v1(
         tenant.tenant_id, category.id
       ) scope
)
select
  1 / (case when (select count(*) from resolved) = 1 then 1 else 0 end)
    as category_scope_executes,
  1 / (case when (select category_id from resolved) = (select id from category)
        then 1 else 0 end) as category_scope_returns_its_identity,
  1 / (case when coalesce(btrim((select category_path from resolved)), '') <> ''
        then 1 else 0 end) as category_scope_returns_a_path,
  1 / (case when (select technical_family from resolved) is not null
        then 1 else 0 end) as technical_family_is_derived;

-- ── 4. El normalizador v2 se EJECUTA y publica la procedencia ──────────────
-- Línea sin producto y sin predicados: la línea sobrevive y las tres claves de
-- procedencia viajan explícitas aunque estén vacías.
with tenant as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), plain as (
  select public.normalize_supply_request_items_internal_v2(
    tenant.tenant_id,
    jsonb_build_array(jsonb_build_object(
      'lineRef', 'line-1',
      'description', 'read-back de procedencia de categoria',
      'productId', null,
      'quantity', 1,
      'unit', 'unidad',
      'technicalPredicates', '[]'::jsonb,
      'preference', null,
      'clarification', null,
      'clarificationRequired', false
    ))
  ) as payload
  from tenant
)
select
  1 / (case when jsonb_array_length(payload) = 1 then 1 else 0 end)
    as normalizer_v2_executes,
  1 / (case when (payload -> 0) ? 'categoryId'
              and (payload -> 0) ? 'categoryPath'
              and (payload -> 0) ? 'technicalFamily'
        then 1 else 0 end) as provenance_keys_always_travel,
  1 / (case when jsonb_typeof(payload -> 0 -> 'categoryId') = 'null'
        then 1 else 0 end) as line_without_category_stays_null
from plain;

-- Línea sin producto CON categoría del modelo: la categoría gobierna y su ruta
-- y familia se resuelven en el servidor.
with tenant as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), category as (
  select scope.id
  from public.product_categories scope, tenant
  where scope.tenant_id = tenant.tenant_id
    and exists (
      select 1 from public.category_tech_mappings mapping
      where mapping.category_id = scope.id and mapping.status = 'active'
    )
  order by (
    select count(*) from public.products product
    where product.category_id = scope.id and product.is_active is true
  ) desc, scope.id
  limit 1
), typed as (
  select category.id as expected_category,
    public.normalize_supply_request_items_internal_v2(
      tenant.tenant_id,
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'read-back de procedencia con categoria',
        'productId', null,
        'categoryId', category.id::text,
        'quantity', 2,
        'unit', 'unidad',
        'technicalPredicates', '[]'::jsonb,
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      ))
    ) as payload
  from tenant, category
)
select
  1 / (case when (payload -> 0 ->> 'categoryId')::uuid = expected_category
        then 1 else 0 end) as model_category_governs_a_line_without_product,
  1 / (case when coalesce(btrim(payload -> 0 ->> 'categoryPath'), '') <> ''
        then 1 else 0 end) as category_path_is_server_resolved,
  1 / (case when (payload -> 0 ->> 'technicalFamily') is not null
        then 1 else 0 end) as technical_family_travels_derived
from typed;

-- Producto exacto: la categoría la pone el servidor desde la ficha, no el
-- llamador. Se toma un producto real del catálogo del tenant.
with tenant as (
  select need.tenant_id
  from public.supply_needs need
  order by need.created_at desc
  limit 1
), item as (
  select product.id, product.category_id
  from public.products product, tenant
  where product.tenant_id = tenant.tenant_id
    and product.is_active is true
    and not coalesce(product.is_service, false)
    and coalesce(product.product_type, 'product') <> 'service'
    and product.category_id is not null
  order by product.id
  limit 1
), owned as (
  select item.category_id as expected_category,
    public.normalize_supply_request_items_internal_v2(
      tenant.tenant_id,
      jsonb_build_array(jsonb_build_object(
        'lineRef', 'line-1',
        'description', 'read-back de autoridad del producto exacto',
        'productId', item.id::text,
        'quantity', 1,
        'unit', 'unidad',
        'technicalPredicates', '[]'::jsonb,
        'preference', null,
        'clarification', null,
        'clarificationRequired', false
      ))
    ) as payload
  from tenant, item
)
select 1 / (case when (payload -> 0 ->> 'categoryId')::uuid = expected_category
      then 1 else 0 end) as exact_product_owns_its_category
from owned;

-- ── 5. Invariantes de forma que separan v2 de v1 ───────────────────────────
-- Sin categoría no entra ningún criterio técnico: se conserva el rechazo.
select 1 / (case when pg_get_functiondef(
  'public.normalize_supply_request_items_internal_v2(uuid,jsonb)'::regprocedure
) like '%Technical predicates require a resolved category%'
  then 1 else 0 end) as predicates_require_a_category;

-- Y sin plantilla activa tampoco: no hay repliegue a `is_filterable` global.
select 1 / (case when pg_get_functiondef(
  'public.normalize_supply_request_items_internal_v2(uuid,jsonb)'::regprocedure
) like '%Technical predicates require an active category template%'
  and pg_get_functiondef(
  'public.normalize_supply_request_items_internal_v2(uuid,jsonb)'::regprocedure
) like '%spec_template_fields%'
  then 1 else 0 end) as predicates_are_bounded_by_the_template;

-- Una categoría que contradice la ficha del producto es un error, no una
-- preferencia.
select 1 / (case when pg_get_functiondef(
  'public.normalize_supply_request_items_internal_v2(uuid,jsonb)'::regprocedure
) like '%does not belong to the requested category%'
  then 1 else 0 end) as contradictory_category_is_rejected;

-- El UUID de categoría nunca sale hacia el modelo: el proyector lo quita.
select 1 / (case when pg_get_functiondef(
  'public.assistant_prepare_supply_request_v2(jsonb,text)'::regprocedure
) like '%normalize_supply_request_items_internal_v2%'
  then 1 else 0 end) as draft_uses_the_provenance_normalizer;

-- El comando durable escribe la ranura que existía vacía desde el kernel.
select 1 / (case when pg_get_functiondef(
  'public.create_supply_need_batch_v2(text,jsonb,text,uuid,text)'::regprocedure
) like '%supply_need_interpretation_revisions%'
  and pg_get_functiondef(
  'public.create_supply_need_batch_v2(text,jsonb,text,uuid,text)'::regprocedure
) like '%category_id%'
  then 1 else 0 end) as batch_v2_persists_the_category;

-- `technical_family` se deriva en cada lectura; no se persiste una copia.
select 1 / (case when not exists (
  select 1 from information_schema.columns
  where table_schema = 'public'
    and table_name = 'supply_need_interpretation_revisions'
    and column_name = 'technical_family'
) then 1 else 0 end) as technical_family_is_never_stored;
