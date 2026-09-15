-- Dos operaciones distintas para una necesidad que ya existe.
--
-- Forward:
--   * `refine_supply_need_v1` conserva descripción/categoría y reemplaza sólo
--     los predicados técnicos por valores validados contra la ficha vigente;
--   * `replace_supply_need_v1` cambia la petición completa, limpia la identidad
--     anterior y vuelve a interpretar categoría/predicados desde el registro;
--   * una búsqueda de proveedor queda ligada a la categoría que enumeró. Al
--     refinar esa misma categoría, sus filas crudas se pueden volver a evaluar;
--     al cambiar de categoría, la lectura anterior deja de ser alcanzable.
--
-- Recovery:
--   el cliente anterior puede volver a `update_supply_need_v1`; las revisiones
--   y búsquedas ya registradas son evidencia append-only y no se eliminan.
--   Las tres columnas nuevas son aditivas y toleran recibos históricos sin
--   alcance verificable (los lectores nuevos simplemente no los reutilizan).
--
-- Lock/backfill:
--   bloqueos de catálogo breves para columnas/trigger/constraints. El backfill
--   toca sólo búsquedas posteriores a la última edición de su necesidad: ésa
--   es la prueba de que describen la interpretación actualmente vigente.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

-- -------------------------------------------------------------------------
-- 0. Una revisión dice de cuál viene y si continúa o reemplaza.
--
-- `revision_no` ya era el linaje de la interpretación, pero no decía NADA
-- sobre la relación con la anterior: había que adivinarla comparando
-- `category_id`. Sin eso no se puede responder la pregunta que el operador
-- hace en pantalla —«¿esto sigue valiendo?»— ni distinguir precisar de
-- cambiar después del hecho.
--
-- `technical_family` viaja acá y no en el recibo del portal porque el alcance
-- lo tiene que fijar el servidor: si lo declarara el cliente en cada búsqueda,
-- dos consultas de la misma revisión podrían etiquetarse distinto.
-- -------------------------------------------------------------------------

alter table public.supply_need_interpretation_revisions
  add column if not exists supersedes_revision_no bigint,
  add column if not exists continuity text,
  add column if not exists technical_family text;

comment on column public.supply_need_interpretation_revisions.continuity is
  'initial | refined (mismo alcance técnico) | replaced (otra cosa). Nulo en revisiones anteriores a este contrato.';
comment on column public.supply_need_interpretation_revisions.supersedes_revision_no
  is 'La revisión que ésta deja atrás. Permite leer el linaje sin comparar categorías a mano.';
comment on column public.supply_need_interpretation_revisions.technical_family is
  'Familia canónica que fijó el alcance enumerable. La estampa el servidor en el recibo del portal; el cliente nunca la etiqueta por su cuenta.';

-- **El backfill toca una tabla append-only, y hay que decirlo en voz alta.**
-- `trg_supply_need_interpretation_revisions_immutable` rechaza CUALQUIER
-- update con 55000. Con cero revisiones —una base local recién creada— el
-- backfill no toca filas y nadie se entera; con las 35 de producción, la
-- migración entera abortaría en el rollout. Se desactiva el disparador para
-- este backfill puntual y se vuelve a activar en la misma transacción: si algo
-- falla, el rollback restituye las dos cosas.
alter table public.supply_need_interpretation_revisions
  disable trigger trg_supply_need_interpretation_revisions_immutable;

-- 0.a La familia sale del registro, nunca de un cliente ni de una glosa.
--
-- Sin esto, un recibo histórico queda con familia nula, la primera precisión
-- le pone `tube` a la revisión nueva, y la comparación null-safe del lector
-- deja de devolver justo el feed que había que filtrar sin red. Medido en
-- producción el 2026-08-29: 13 búsquedas, 13 con categoría, y las 13 con una
-- familia autoritativa disponible en `category_tech_mappings`.
-- El mismo filtro que la autoridad canónica: categoría activa y mapping
-- `status = 'active'`. Un mapping pendiente o dado de baja no puede fijar el
-- alcance de un feed histórico.
update public.supply_need_interpretation_revisions revision
set technical_family = mapping.technical_family
from public.category_tech_mappings mapping
join public.product_categories category
  on category.tenant_id = mapping.tenant_id
 and category.id = mapping.category_id
 and category.is_active is true
where mapping.tenant_id = revision.tenant_id
  and mapping.category_id = revision.category_id
  and mapping.status = 'active'
  and revision.category_id is not null
  and revision.technical_family is null
  and mapping.technical_family is not null;

-- 0.b El linaje se deduce de EVIDENCIA, no del nombre de la operación.
--
-- «Misma categoría» no prueba continuidad: una petición se puede reemplazar
-- por otra dentro de la misma categoría —cámaras 700 por cámaras 26— y el
-- lector cruzaría un feed que ya no responde nada. Sólo se marca `refined`
-- cuando la revisión siguiente conserva la categoría **y los predicados tal
-- cual**: eso es scope demostrado, y es lo que hace `family-choice-v1`, que
-- copia `constraints` y `category_id` de la anterior para confirmar cuál
-- producto era. Toda otra transición histórica queda en `null` y falla
-- cerrada: no se puede demostrar que continúe.
with lineage as (
  select
    revision.id,
    revision.revision_no,
    revision.category_id,
    revision.constraints,
    revision.formula_version,
    lag(revision.revision_no) over w as previous_no,
    lag(revision.category_id) over w as previous_category_id,
    lag(revision.constraints) over w as previous_constraints
  from public.supply_need_interpretation_revisions revision
  window w as (
    partition by revision.tenant_id, revision.supply_need_id
    order by revision.revision_no
  )
)
update public.supply_need_interpretation_revisions revision
set supersedes_revision_no = lineage.previous_no,
    continuity = case
      when lineage.previous_no is null then 'initial'
      -- **Ni la categoría ni los predicados iguales demuestran continuidad.**
      -- Una petición poco especificada puede pasar de cámaras 700 a cámaras 26
      -- conservando `constraints` vacíos: misma categoría, mismos criterios,
      -- otra pregunta. Sólo se marca `refined` cuando además la procedencia es
      -- una operación que POR CONSTRUCCIÓN conserva el alcance. Hoy esa lista
      -- tiene un solo nombre: `family-choice-v1` copia `category_id` y
      -- `constraints` de la revisión anterior para confirmar cuál producto
      -- era, y son las 2 únicas transiciones multi-revisión que hay en
      -- producción. Todo lo demás queda nulo y falla cerrado.
      when lineage.formula_version in ('family-choice-v1')
       and lineage.category_id is not null
       and lineage.category_id = lineage.previous_category_id
       and lineage.constraints = lineage.previous_constraints then 'refined'
      else null
    end
from lineage
where lineage.id = revision.id
  and revision.continuity is null;

alter table public.supply_need_interpretation_revisions
  enable trigger trg_supply_need_interpretation_revisions_immutable;

alter table public.supply_need_interpretation_revisions
  drop constraint if exists supply_need_interpretation_revisions_continuity_check;
alter table public.supply_need_interpretation_revisions
  add constraint supply_need_interpretation_revisions_continuity_check check (
    continuity is null or continuity in ('initial', 'refined', 'replaced')
  );

alter table public.supply_need_interpretation_revisions
  drop constraint if exists supply_need_interpretation_revisions_supersedes_check;
alter table public.supply_need_interpretation_revisions
  add constraint supply_need_interpretation_revisions_supersedes_check check (
    supersedes_revision_no is null
    or (
      supersedes_revision_no > 0
      and supersedes_revision_no < revision_no
    )
  );

-- Una revisión inicial no deja nada atrás, y una que continúa o reemplaza sí.
alter table public.supply_need_interpretation_revisions
  drop constraint if exists supply_need_interpretation_revisions_lineage_check;
alter table public.supply_need_interpretation_revisions
  add constraint supply_need_interpretation_revisions_lineage_check check (
    continuity is null
    or (continuity = 'initial' and supersedes_revision_no is null)
    or (
      continuity in ('refined', 'replaced')
      and supersedes_revision_no is not null
    )
  );

-- -------------------------------------------------------------------------
-- 1. El feed crudo del proveedor declara para qué categoría fue enumerado.
-- -------------------------------------------------------------------------

alter table public.supplier_need_portal_searches
  add column if not exists need_version_at_search bigint,
  add column if not exists interpretation_revision_no bigint,
  add column if not exists interpretation_category_id uuid,
  -- **La categoría sola no es el alcance.** Qué nodos del proveedor se
  -- enumeran lo decide la familia canónica: dos fichas de la misma categoría
  -- pueden mirar catálogos distintos, y reutilizar filas entre ellas sería
  -- afirmar cobertura sobre un universo que nunca se recorrió.
  add column if not exists interpretation_technical_family text;

alter table public.supplier_need_portal_searches
  drop constraint if exists supplier_need_portal_searches_interpretation_scope_check;
alter table public.supplier_need_portal_searches
  add constraint supplier_need_portal_searches_interpretation_scope_check check (
    (
      need_version_at_search is null
      and interpretation_revision_no is null
      and interpretation_category_id is null
    ) or (
      need_version_at_search > 0
      and interpretation_revision_no > 0
      and interpretation_category_id is not null
    )
  ) not valid;

alter table public.supplier_need_portal_searches
  drop constraint if exists supplier_need_portal_searches_category_fkey;
alter table public.supplier_need_portal_searches
  add constraint supplier_need_portal_searches_category_fkey
  foreign key (tenant_id, interpretation_category_id)
  references public.product_categories(tenant_id, id)
  on delete restrict
  not valid;

create or replace function public.supplier_need_portal_search_scope_guard()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
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

  if new.interpretation_revision_no <> v_revision_no
     or new.interpretation_category_id <> v_category_id
     or new.interpretation_technical_family is distinct from v_technical_family
     or new.need_version_at_search <> v_need_version then
    raise exception 'La necesidad cambió mientras se consultaba al proveedor; '
      'esa lectura ya no responde lo que se está preguntando.'
      using errcode = '40001';
  end if;

  return new;
end;
$$;

revoke all on function public.supplier_need_portal_search_scope_guard()
from public, anon, authenticated, service_role;

drop trigger if exists supplier_need_portal_search_scope_guard
  on public.supplier_need_portal_searches;
create trigger supplier_need_portal_search_scope_guard
  before insert on public.supplier_need_portal_searches
  for each row execute function public.supplier_need_portal_search_scope_guard();

-- Recibos anteriores que se hicieron después de la edición vigente tienen una
-- procedencia demostrable. Los que no cumplen esa relación temporal se dejan
-- sin alcance y los lectores nuevos fallan cerrados.
--
-- **Y la familia va con ellos.** Estampar categoría y revisión sin familia
-- deja el recibo con `null` mientras la primera precisión le pone `tube` a la
-- revisión nueva; la comparación null-safe del lector entonces esconde justo
-- el feed que había que filtrar sin red. La familia se toma de la MISMA
-- revisión que se le asigna al recibo —ya backfilleada desde el mapeo
-- autoritativo arriba—, nunca de algo que declare un cliente.
with current_revision as (
  select distinct on (revision.tenant_id, revision.supply_need_id)
    revision.tenant_id,
    revision.supply_need_id,
    revision.revision_no,
    revision.category_id,
    revision.technical_family
  from public.supply_need_interpretation_revisions revision
  order by revision.tenant_id, revision.supply_need_id,
    revision.revision_no desc
)
update public.supplier_need_portal_searches search
set need_version_at_search = need.version,
    interpretation_revision_no = current_revision.revision_no,
    interpretation_category_id = current_revision.category_id,
    interpretation_technical_family = current_revision.technical_family
from public.supply_needs need
join current_revision
  on current_revision.tenant_id = need.tenant_id
 and current_revision.supply_need_id = need.id
where search.tenant_id = need.tenant_id
  and search.supply_need_id = need.id
  and search.checked_at >= need.updated_at
  and current_revision.category_id is not null
  and search.interpretation_category_id is null;

alter table public.supplier_need_portal_searches
  validate constraint supplier_need_portal_searches_interpretation_scope_check;
alter table public.supplier_need_portal_searches
  validate constraint supplier_need_portal_searches_category_fkey;

comment on column public.supplier_need_portal_searches.interpretation_category_id is
  'Categoría autoritativa cuya taxonomía enumeró este feed. Permite recalcular calce al refinar y prohíbe reutilizarlo para otra necesidad.';
comment on column public.supplier_need_portal_searches.interpretation_revision_no is
  'Revisión vigente cuando se leyó el portal; es procedencia, no una obligación de repetir la búsqueda en cada refinamiento.';
comment on column public.supplier_need_portal_searches.interpretation_technical_family is
  'Familia canónica que fijó el alcance enumerable de este feed. Sale de la revisión que lo estampó; el cliente nunca la declara.';
comment on column public.supplier_need_portal_searches.need_version_at_search is
  'Versión de la necesidad al leer el portal. La categoría, no esta versión, decide si las filas crudas pueden reinterpretarse.';

-- -------------------------------------------------------------------------
-- 2. Refinar ficha: misma necesidad/categoría, nuevos predicados tipados.
-- -------------------------------------------------------------------------

create or replace function public.refine_supply_need_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_expected_revision_no bigint,
  p_category_id uuid,
  p_technical_family text,
  p_predicates jsonb,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_claimed_family text := nullif(btrim(coalesce(p_technical_family, '')), '');
  v_family text;
  v_request jsonb;
  v_response jsonb;
  v_receipt public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_previous public.supply_need_interpretation_revisions%rowtype;
  v_normalized jsonb;
  v_nontechnical jsonb := '[]'::jsonb;
  v_constraints jsonb;
  v_next_revision bigint;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_expected_revision_no is null or p_category_id is null
     or jsonb_typeof(coalesce(p_predicates, 'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_predicates) > 8
     or octet_length(coalesce(v_claimed_family, '')) > 80
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'La precisión de la ficha no es válida.' using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'mode', 'refine',
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'expected_revision_no', p_expected_revision_no,
    'category_id', p_category_id,
    'technical_family', v_claimed_family,
    'predicates', p_predicates
  );

  select event.* into v_receipt
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action <> 'updated'
       or v_receipt.supply_need_id <> p_need_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otro cambio.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de guardar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state <> 'open' then
    raise exception 'Sólo una necesidad abierta puede precisarse.'
      using errcode = '55000';
  end if;

  select revision.* into v_previous
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supply_need_id = p_need_id
  order by revision.revision_no desc
  limit 1;
  -- **Dos cerrojos, porque son dos preguntas.** `version` dice que la fila
  -- cambió; `revision_no` dice que la pregunta cambió. Precisar sobre una
  -- ficha que alguien ya reemplazó escribiría predicados de otra categoría.
  if not found or v_previous.revision_no is distinct from p_expected_revision_no
     or v_previous.category_id is distinct from p_category_id then
    raise exception 'La ficha cambió; vuelve a abrirla antes de guardar.'
      using errcode = '40001';
  end if;

  -- **La familia la fija el registro, no el cliente.** Antes este comando
  -- aceptaba el texto que le mandaran y lo persistía tras comprobarle el
  -- largo: una familia equivocada habría marcado el alcance de todas las
  -- lecturas siguientes, que es exactamente lo que la estampa existe para
  -- impedir. Se deriva del mapeo activo de la categoría, y el valor que
  -- declaró el cliente sólo sirve para detectar que su template quedó viejo.
  -- Por la autoridad canónica, no por un `select` propio: ella exige categoría
  -- activa **y** mapping `status = 'active'`. Leer la tabla directamente
  -- aceptaba un mapping `pending` o dado de baja y estampaba con él el alcance
  -- de todas las lecturas siguientes.
  select scope.technical_family
  into v_family
  from public.supply_request_category_scope_internal_v1(
    v_tenant_id, p_category_id
  ) scope
  limit 1;

  if v_claimed_family is not null
     and v_claimed_family is distinct from v_family then
    raise exception 'La ficha técnica de esa categoría cambió; vuelve a '
      'abrirla antes de guardar.'
      using errcode = '40001';
  end if;

  -- Reutiliza el normalizador del Asistente: tipos, operadores, allowed_values,
  -- pertenencia al template y compatibilidad de un producto confirmado tienen
  -- un solo dueño en el servidor.
  v_normalized := public.normalize_supply_request_items_internal_v2(
    v_tenant_id,
    jsonb_build_array(jsonb_build_object(
      'lineRef', 'line-1',
      'description', v_need.original_description,
      'productId', to_jsonb(v_need.product_id),
      -- La cantidad NO se toca acá: tiene su propio comando porque no cambia
      -- la pregunta que se le hace al catálogo.
      'quantity', v_need.quantity,
      'unit', v_need.unit,
      'technicalPredicates', p_predicates,
      'preference', null,
      'clarification', null,
      'clarificationRequired', false,
      'categoryId', p_category_id::text
    ))
  );

  select coalesce(jsonb_agg(entry.value order by entry.ordinality), '[]'::jsonb)
  into v_nontechnical
  from jsonb_array_elements(coalesce(v_previous.constraints, '[]'::jsonb))
    with ordinality entry(value, ordinality)
  where entry.value ? 'kind';

  v_constraints := coalesce(v_normalized->0->'technicalPredicates', '[]'::jsonb)
    || v_nontechnical;
  v_changed := v_previous.constraints is distinct from v_constraints
    or v_previous.technical_family is distinct from v_family;

  if v_changed then
    update public.supply_needs need
    set version = need.version + 1,
        -- La ficha cambió, así que el conjunto elegible de bodega es otro: el
        -- rechazo anterior hablaba de productos que ya no son los candidatos.
        internal_stock_rejection_reason = null,
        internal_stock_rejected_at = null,
        internal_stock_rejected_by = null,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where need.tenant_id = v_tenant_id and need.id = p_need_id
    returning * into v_need;

    -- `revision_no` jamás se deriva de `version`: son dos relojes distintos y
    -- atarlos hace que una edición barata consuma un número de linaje.
    select coalesce(max(revision.revision_no), 0) + 1
    into v_next_revision
    from public.supply_need_interpretation_revisions revision
    where revision.tenant_id = v_tenant_id
      and revision.supply_need_id = p_need_id;

    insert into public.supply_need_interpretation_revisions (
      tenant_id, supply_need_id, revision_no, source, raw_description,
      identity_state, canonical_product_id, category_id, constraints,
      clarifications, evidence_snapshot, formula_version, created_by,
      supersedes_revision_no, continuity, technical_family
    ) values (
      v_tenant_id, p_need_id, v_next_revision, 'manual',
      v_need.original_description, v_need.identity_state, v_need.product_id,
      p_category_id, v_constraints,
      coalesce(v_previous.clarifications, '[]'::jsonb),
      jsonb_build_object('operation', 'technical_refinement'),
      'operator-refinement-v1', v_actor_id,
      v_previous.revision_no, 'refined', v_family
    );
  else
    v_next_revision := v_previous.revision_no;
  end if;

  v_response := jsonb_build_object(
    'need_id', p_need_id,
    'changed', v_changed,
    'version', v_need.version,
    'revision_no', v_next_revision,
    'category_id', p_category_id,
    'technical_family', v_family,
    'continuity', 'refined',
    'need', to_jsonb(v_need)
  );
  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, p_need_id, 'updated', v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.refine_supply_need_v1(
  uuid, bigint, bigint, uuid, text, jsonb, text
) from public, anon, authenticated, service_role;
grant execute on function public.refine_supply_need_v1(
  uuid, bigint, bigint, uuid, text, jsonb, text
) to authenticated;

comment on function public.refine_supply_need_v1(
  uuid, bigint, bigint, uuid, text, jsonb, text
) is
  'Precisa la ficha de una necesidad abierta dentro de su categoría ya resuelta. La familia técnica la deriva el servidor del mapeo de la categoría y rechaza una discrepancia del cliente. Los predicados los valida el normalizador canónico; la cantidad no viaja acá porque no cambia la pregunta al catálogo. Deja linaje explícito (refined + supersedes) y estampa la familia que fija el alcance enumerable.';

-- La firma anterior llevaba cantidad y no dejaba linaje. Se elimina para que
-- una llamada ambigua no pueda elegirla.
drop function if exists public.refine_supply_need_v1(
  uuid, bigint, uuid, jsonb, numeric, text
);

-- -------------------------------------------------------------------------
-- 2.b Cantidad: sube la fila, NO crea revisión.
--
-- «Cámaras 700, 3 unidades» y «Cámaras 700, 5 unidades» le hacen al catálogo
-- **la misma pregunta**. Antes la cantidad viajaba junto con el texto por
-- `update_supply_need_v1`, que escribía una revisión con `constraints: []` —o
-- sea, cambiar un 3 por un 4 borraba la ficha técnica—. Acá no hay revisión
-- que escribir, y por lo tanto no hay ficha que perder.
-- -------------------------------------------------------------------------

create or replace function public.set_supply_need_quantity_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_quantity numeric,
  p_unit text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_unit text := btrim(coalesce(p_unit, ''));
  v_request jsonb;
  v_response jsonb;
  v_receipt public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_revision_no bigint;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_quantity is null or p_quantity <= 0 or p_quantity > 999999
     or v_unit = '' or octet_length(v_unit) > 32
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'La cantidad no es válida.' using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'mode', 'quantity',
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'quantity', p_quantity,
    'unit', v_unit
  );

  select event.* into v_receipt
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action <> 'updated'
       or v_receipt.supply_need_id <> p_need_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otro cambio.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de guardar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state in ('covered', 'cancelled') then
    raise exception 'La necesidad ya está cerrada y no puede editarse.'
      using errcode = '55000';
  end if;

  v_changed := v_need.quantity is distinct from p_quantity
    or v_need.unit is distinct from v_unit;

  if v_changed then
    update public.supply_needs need
    set quantity = p_quantity,
        unit = v_unit,
        version = need.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where need.tenant_id = v_tenant_id and need.id = p_need_id
    returning * into v_need;
  end if;

  -- **Ninguna revisión.** Y por lo mismo, el rechazo de bodega sigue en pie:
  -- fue un juicio sobre las piezas, no sobre el número de unidades.
  select coalesce(max(revision.revision_no), 0)
  into v_revision_no
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supply_need_id = p_need_id;

  v_response := jsonb_build_object(
    'need_id', p_need_id,
    'changed', v_changed,
    'version', v_need.version,
    'revision_no', v_revision_no,
    'need', to_jsonb(v_need)
  );
  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, p_need_id, 'updated', v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.set_supply_need_quantity_v1(
  uuid, bigint, numeric, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.set_supply_need_quantity_v1(
  uuid, bigint, numeric, text, text
) to authenticated;

comment on function public.set_supply_need_quantity_v1(
  uuid, bigint, numeric, text, text
) is
  'Cambia cuántas unidades se necesitan. Sube version, NO crea revisión de interpretación y conserva identidad, categoría, ficha y el rechazo de bodega: la cantidad no es parte de la pregunta que se le hace al catálogo.';

-- -------------------------------------------------------------------------
-- 3. Cambiar petición: la identidad anterior no sobrevive por accidente.
-- -------------------------------------------------------------------------

create or replace function public.replace_supply_need_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_description text,
  p_quantity numeric,
  p_unit text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_description text := btrim(coalesce(p_description, ''));
  v_unit text := btrim(coalesce(p_unit, ''));
  v_request jsonb;
  v_response jsonb;
  v_receipt public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_previous public.supply_need_interpretation_revisions%rowtype;
  v_inferred jsonb;
  v_normalized jsonb;
  v_nontechnical jsonb := '[]'::jsonb;
  v_constraints jsonb := '[]'::jsonb;
  v_clarifications jsonb := '[]'::jsonb;
  v_evidence jsonb := '{}'::jsonb;
  v_category_id uuid;
  v_family text;
  v_next_revision bigint;
  v_identity_changed boolean;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or v_description = '' or octet_length(v_description) > 2000
     or p_quantity is null or p_quantity <= 0 or p_quantity > 999999
     or v_unit = '' or octet_length(v_unit) > 32
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'La nueva necesidad no es válida.' using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'mode', 'replace',
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'description', v_description,
    'quantity', p_quantity,
    'unit', v_unit
  );

  select event.* into v_receipt
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_receipt.action <> 'updated'
       or v_receipt.supply_need_id <> p_need_id
       or v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otro cambio.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_receipt) || v_receipt.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de guardar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state <> 'open' then
    raise exception 'Sólo una necesidad abierta puede cambiarse.'
      using errcode = '55000';
  end if;

  select revision.* into v_previous
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supply_need_id = p_need_id
  order by revision.revision_no desc
  limit 1;
  if not found then
    raise exception 'La necesidad no tiene una interpretación vigente.'
      using errcode = '55000';
  end if;

  v_identity_changed := v_need.original_description is distinct from v_description;
  if v_identity_changed then
    -- El perfil de compra y la preferencia comercial describen CÓMO comprar,
    -- no qué producto es. Sobreviven; todos los predicados técnicos se rehacen.
    select coalesce(jsonb_agg(entry.value order by entry.ordinality), '[]'::jsonb)
    into v_nontechnical
    from jsonb_array_elements(coalesce(v_previous.constraints, '[]'::jsonb))
      with ordinality entry(value, ordinality)
    where entry.value ? 'kind';

    v_inferred := public.assistant_infer_technical_predicates_internal_v1(
      v_tenant_id, v_description
    );

    -- La inferencia puede nombrar ramas hermanas. Gana la categoría activa con
    -- ficha cuyo nombre realmente aparece en la petición; después la de nombre
    -- más corto. «cámaras» no se convierte en «cámaras anti-pinchazo» sólo
    -- porque ambas compartan la palabra principal.
    select category.id
    into v_category_id
    from jsonb_array_elements_text(
      coalesce(v_inferred->'categories', '[]'::jsonb)
    ) inferred(category_id)
    join public.product_categories category
      on category.tenant_id = v_tenant_id
     and category.id = inferred.category_id::uuid
     and category.is_active is true
    join public.category_tech_mappings mapping
      on mapping.tenant_id = v_tenant_id
     and mapping.category_id = category.id
     and mapping.status = 'active'
    order by
      (position(
        public.assistant_normalize_query_internal_v1(category.name)
        in public.assistant_normalize_query_internal_v1(v_description)
      ) > 0) desc,
      length(public.assistant_normalize_query_internal_v1(category.name)),
      category.level desc,
      category.full_path
    limit 1;

    if v_category_id is not null then
      v_normalized := public.normalize_supply_request_items_internal_v2(
        v_tenant_id,
        jsonb_build_array(jsonb_build_object(
          'lineRef', 'line-1',
          'description', v_description,
          'productId', null,
          'quantity', p_quantity,
          'unit', v_unit,
          'technicalPredicates', coalesce(v_inferred->'predicates', '[]'::jsonb),
          'preference', null,
          'clarification', null,
          'clarificationRequired', false,
          'categoryId', v_category_id::text
        ))
      );
      v_constraints := coalesce(
        v_normalized->0->'technicalPredicates', '[]'::jsonb
      ) || v_nontechnical;
    else
      v_constraints := v_nontechnical;
    end if;
    -- **La familia NUEVA se deriva acá mismo.** Dejarla nula «para que la fije
    -- un refine posterior» rompe la búsqueda inmediata: el cliente arma su
    -- petición con la familia del template recién resuelto, el recibo la
    -- manda, y el guardián la compara contra una revisión sin familia → 40001.
    -- No se hereda la vieja —describía la petición que se acaba de descartar—:
    -- se deriva de la categoría nueva por la autoridad canónica.
    if v_category_id is not null then
      select scope.technical_family
      into v_family
      from public.supply_request_category_scope_internal_v1(
        v_tenant_id, v_category_id
      ) scope
      limit 1;
    else
      v_family := null;
    end if;
    v_clarifications := '[]'::jsonb;
    v_evidence := jsonb_build_object(
      'operation', 'need_replacement',
      'from_revision_no', v_previous.revision_no,
      'category_resolved', v_category_id is not null,
      'technical_family_resolved', v_family is not null
    );
  else
    -- Cantidad/unidad no cambian el producto pedido. Copiar hacia delante es
    -- obligatorio: una revisión vacía se volvería la autoridad y borraría la
    -- ficha aunque el operador jamás la tocó.
    v_category_id := v_previous.category_id;
    -- Sin cambio de identidad no hay categoría nueva que resolver: la familia
    -- sigue siendo la de antes. Devolver nulo acá haría que la respuesta
    -- mintiera sobre el alcance vigente aunque no se escriba revisión.
    v_family := v_previous.technical_family;
    v_constraints := coalesce(v_previous.constraints, '[]'::jsonb);
    v_clarifications := coalesce(v_previous.clarifications, '[]'::jsonb);
    v_evidence := coalesce(v_previous.evidence_snapshot, '{}'::jsonb);
  end if;

  v_changed := v_identity_changed
    or v_need.quantity is distinct from p_quantity
    or v_need.unit is distinct from v_unit;

  if v_changed then
    update public.supply_needs need
    set original_description = v_description,
        product_id = case when v_identity_changed then null else need.product_id end,
        identity_state = case
          when v_identity_changed then 'unresolved'
          else need.identity_state
        end,
        quantity = p_quantity,
        unit = v_unit,
        -- **Sólo un cambio de petición reabre la bodega.** Si lo único que se
        -- movió fue la cantidad, el rechazo de bodega sigue en pie: fue un
        -- juicio sobre las piezas, no sobre cuántas se necesitan.
        internal_stock_rejection_reason = case
          when v_identity_changed then null
          else need.internal_stock_rejection_reason
        end,
        internal_stock_rejected_at = case
          when v_identity_changed then null
          else need.internal_stock_rejected_at
        end,
        internal_stock_rejected_by = case
          when v_identity_changed then null
          else need.internal_stock_rejected_by
        end,
        version = need.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where need.tenant_id = v_tenant_id and need.id = p_need_id
    returning * into v_need;
  end if;

  -- **Una revisión sólo nace cuando cambia la pregunta.** Mover la cantidad
  -- por esta puerta no puede consumir un número de linaje ni volver a escribir
  -- la ficha: para eso está `set_supply_need_quantity_v1`, y esta rama existe
  -- para que un cliente que llame acá con sólo la cantidad tampoco haga daño.
  if v_identity_changed then
    select coalesce(max(revision.revision_no), 0) + 1
    into v_next_revision
    from public.supply_need_interpretation_revisions revision
    where revision.tenant_id = v_tenant_id
      and revision.supply_need_id = p_need_id;

    insert into public.supply_need_interpretation_revisions (
      tenant_id, supply_need_id, revision_no, source, raw_description,
      identity_state, canonical_product_id, category_id, constraints,
      clarifications, evidence_snapshot, formula_version, created_by,
      supersedes_revision_no, continuity, technical_family
    ) values (
      v_tenant_id, p_need_id, v_next_revision, 'manual', v_description,
      v_need.identity_state, v_need.product_id, v_category_id, v_constraints,
      v_clarifications, v_evidence, 'operator-replacement-v1', v_actor_id,
      v_previous.revision_no, 'replaced', v_family
    );
  else
    v_next_revision := v_previous.revision_no;
  end if;

  v_response := jsonb_build_object(
    'need_id', p_need_id,
    'changed', v_changed,
    'identity_changed', v_identity_changed,
    'technical_family', v_family,
    'version', v_need.version,
    'revision_no', v_next_revision,
    'category_id', v_category_id,
    'need', to_jsonb(v_need)
  );
  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, p_need_id, 'updated', v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_receipt;

  return to_jsonb(v_receipt) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.replace_supply_need_v1(
  uuid, bigint, text, numeric, text, text
) from public, anon, authenticated, service_role;
grant execute on function public.replace_supply_need_v1(
  uuid, bigint, text, numeric, text, text
) to authenticated;

comment on function public.replace_supply_need_v1(
  uuid, bigint, text, numeric, text, text
) is
  'Replaces the operator request of one open need. A rewritten description clears prior product identity and rebuilds category/predicates from the authoritative registry; a quantity-only edit copies interpretation forward unchanged.';

-- -------------------------------------------------------------------------
-- 4. La última búsqueda sólo cruza el límite de revisión si la categoría es
--    la misma. Sus filas se reinterpretan en el cliente con la ficha vigente.
-- -------------------------------------------------------------------------

create or replace function public.supplier_last_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_result jsonb;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.suppliers supplier
    where supplier.id = p_supplier_id and supplier.tenant_id = v_tenant_id
  ) or not exists (
    select 1 from public.supply_needs need
    where need.id = p_supply_need_id and need.tenant_id = v_tenant_id
  ) then
    raise exception 'Search scope not found' using errcode = 'P0002';
  end if;

  with latest_revision as (
    select
      revision.revision_no,
      revision.category_id,
      revision.technical_family
    from public.supply_need_interpretation_revisions revision
    where revision.tenant_id = v_tenant_id
      and revision.supply_need_id = p_supply_need_id
    order by revision.revision_no desc
    limit 1
  )
  select jsonb_build_object(
    'status', search.status,
    'searchQuery', search.search_query,
    'checkedAt', search.checked_at,
    'sourceUrl', search.source_url,
    'results', search.results,
    'coverage', search.coverage,
    -- Las dos revisiones viajan juntas para que el cliente no tenga que
    -- deducir la frescura: iguales es vigente, distintas es «ficha anterior».
    'searchRevisionNo', search.interpretation_revision_no,
    'currentRevisionNo', latest_revision.revision_no,
    'categoryId', search.interpretation_category_id,
    'technicalFamily', search.interpretation_technical_family
  )
  into v_result
  from latest_revision
  join public.supplier_need_portal_searches search
    on search.tenant_id = v_tenant_id
   and search.supplier_id = p_supplier_id
   and search.supply_need_id = p_supply_need_id
   -- **El alcance es categoría Y familia.** Cruzar el límite de revisión sólo
   -- se permite cuando las filas crudas describen el mismo universo; con otra
   -- familia se habrían enumerado otros nodos y la cobertura guardada no
   -- respondería por ellos. `is not distinct from` para que dos revisiones sin
   -- familia declarada se comparen como iguales en vez de como desconocidas.
   and search.interpretation_category_id = latest_revision.category_id
   and search.interpretation_technical_family
       is not distinct from latest_revision.technical_family
   -- **Una petición reemplazada no se cruza, aunque caiga en la misma
   -- categoría.** Categoría + familia iguales NO alcanzan: pedir «cámaras 700»
   -- y después «cámaras 26» son dos preguntas distintas dentro de la misma
   -- categoría, y con familia nula heredada de un recibo legacy se veían
   -- idénticas. Sólo se puede cruzar hacia adelante si CADA revisión
   -- intermedia continuó la anterior; una sola `replaced` corta el puente, y
   -- una continuidad desconocida —`null`, de antes de este contrato— también,
   -- porque no se puede demostrar que continúe.
   and not exists (
     select 1
     from public.supply_need_interpretation_revisions intermediate
     where intermediate.tenant_id = v_tenant_id
       and intermediate.supply_need_id = p_supply_need_id
       and intermediate.revision_no > search.interpretation_revision_no
       and intermediate.revision_no <= latest_revision.revision_no
       and coalesce(intermediate.continuity, 'unknown') <> 'refined'
   )
  where latest_revision.category_id is not null
  order by search.checked_at desc
  limit 1;

  return coalesce(v_result, jsonb_build_object('status', 'never_searched'));
end;
$$;

revoke all on function public.supplier_last_need_portal_search_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.supplier_last_need_portal_search_v1(uuid, uuid)
  to authenticated;

-- -------------------------------------------------------------------------
-- 5. El camino antiguo deja de borrar la ficha.
--
-- `update_supply_need_v1` escribía una revisión con `constraints: []` y sin
-- `category_id` ante CUALQUIER cambio: cambiar un 3 por un 4 apagaba los
-- criterios y la categoría de una necesidad ya interpretada, en silencio y sin
-- vuelta atrás desde la interfaz. Medido en producción el 2026-08-29 el daño
-- aún no había ocurrido —las 7 revisiones `manual-v1` son todas `revision_no
-- = 1`, necesidades escritas a mano— pero estaba armado, y el editor nuevo lo
-- dispararía en el primer uso.
--
-- No basta con que el UI nuevo llame a otro comando: mientras esta función
-- exista con ese cuerpo, cualquier cliente sin actualizar sigue borrando.
-- -------------------------------------------------------------------------

create or replace function public.update_supply_need_v1(
  p_need_id uuid,
  p_expected_version bigint,
  p_description text,
  p_product_id uuid,
  p_quantity numeric,
  p_unit text,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_unit text := btrim(coalesce(p_unit, ''));
  v_request jsonb;
  v_response jsonb;
  v_event public.supply_need_events%rowtype;
  v_need public.supply_needs%rowtype;
  v_previous public.supply_need_interpretation_revisions%rowtype;
  v_identity_state text;
  v_next_revision bigint;
  v_text_changed boolean;
  v_changed boolean;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if p_need_id is null or p_expected_version is null
     or p_description is null or btrim(p_description) = ''
     or octet_length(p_description) > 2000
     or p_quantity is null or p_quantity <= 0 or p_quantity > 999999
     or v_unit = '' or octet_length(v_unit) > 32
     or v_operation_key = '' or octet_length(v_operation_key) > 200 then
    raise exception 'Los datos de la necesidad no son válidos.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'need_id', p_need_id,
    'expected_version', p_expected_version,
    'description', p_description,
    'product_id', p_product_id,
    'quantity', p_quantity,
    'unit', v_unit
  );

  select event.* into v_event
  from public.supply_need_events event
  where event.tenant_id = v_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.action <> 'updated'
       or v_event.supply_need_id <> p_need_id
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otro cambio.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event) || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select need.* into v_need
  from public.supply_needs need
  where need.tenant_id = v_tenant_id and need.id = p_need_id
  for update;
  if not found then
    raise exception 'Necesidad no encontrada.' using errcode = 'P0002';
  end if;
  if v_need.version <> p_expected_version then
    raise exception 'La necesidad cambió; vuelve a cargarla antes de guardar.'
      using errcode = '40001';
  end if;
  if v_need.supply_state in ('covered', 'cancelled') then
    raise exception 'La necesidad ya está cerrada y no puede editarse.'
      using errcode = '55000';
  end if;
  if v_need.supply_state = 'committed'
     and v_need.product_id is distinct from p_product_id then
    raise exception 'Libera primero el stock asignado antes de cambiar el producto.'
      using errcode = '55000';
  end if;

  if p_product_id is not null and not exists (
    select 1 from public.products product
    where product.tenant_id = v_tenant_id
      and product.id = p_product_id
      and product.is_active is true
      and not coalesce(product.is_service, false)
      and coalesce(product.product_type, 'product') <> 'service'
  ) then
    raise exception 'El producto no existe, está inactivo o no es un repuesto.'
      using errcode = '23514';
  end if;

  select revision.* into v_previous
  from public.supply_need_interpretation_revisions revision
  where revision.tenant_id = v_tenant_id
    and revision.supply_need_id = p_need_id
  order by revision.revision_no desc
  limit 1;

  v_identity_state := case
    when p_product_id is null then 'unresolved'
    else 'confirmed'
  end;
  v_text_changed := v_need.original_description is distinct from p_description;
  v_changed := v_text_changed
    or v_need.product_id is distinct from p_product_id
    or v_need.quantity is distinct from p_quantity
    or v_need.unit is distinct from v_unit
    or v_need.identity_state is distinct from v_identity_state;

  if v_changed then
    update public.supply_needs need
    set original_description = p_description,
        product_id = p_product_id,
        quantity = p_quantity,
        unit = v_unit,
        identity_state = v_identity_state,
        internal_stock_rejection_reason = case
          when need.product_id is distinct from p_product_id
            then null
          else need.internal_stock_rejection_reason
        end,
        internal_stock_rejected_at = case
          when need.product_id is distinct from p_product_id
            then null
          else need.internal_stock_rejected_at
        end,
        internal_stock_rejected_by = case
          when need.product_id is distinct from p_product_id
            then null
          else need.internal_stock_rejected_by
        end,
        version = need.version + 1,
        updated_by = v_actor_id,
        updated_at = clock_timestamp()
    where need.tenant_id = v_tenant_id and need.id = p_need_id
    returning * into v_need;
  end if;

  -- **Sólo el texto crea revisión, y la ficha viaja con ella.** Antes bastaba
  -- cualquier cambio y la revisión nacía vacía; ahora una cantidad no toca el
  -- linaje, y un texto corregido conserva categoría, criterios y aclaraciones
  -- en vez de apagarlos.
  if v_text_changed then
    select coalesce(max(revision.revision_no), 0) + 1
    into v_next_revision
    from public.supply_need_interpretation_revisions revision
    where revision.tenant_id = v_tenant_id
      and revision.supply_need_id = p_need_id;

    insert into public.supply_need_interpretation_revisions (
      tenant_id, supply_need_id, revision_no, source, raw_description,
      identity_state, canonical_product_id, category_id, constraints,
      clarifications, evidence_snapshot, formula_version, created_by,
      supersedes_revision_no, continuity, technical_family
    ) values (
      v_tenant_id, v_need.id, v_next_revision, 'manual', p_description,
      v_identity_state, p_product_id,
      v_previous.category_id,
      coalesce(v_previous.constraints, '[]'::jsonb),
      coalesce(v_previous.clarifications, '[]'::jsonb),
      jsonb_build_object('operation', 'legacy_text_edit'),
      'manual-v1', v_actor_id,
      v_previous.revision_no,
      -- **Conservar la ficha no es lo mismo que demostrar continuidad.**
      -- Copiar categoría y criterios hacia delante existe para NO borrarlos;
      -- el texto, en cambio, sí cambió, y por esta puerta no hay forma de
      -- saber si fue corregir una tilde o pedir otra cosa. Marcarlo `refined`
      -- dejaría al lector cruzar el feed anterior de «cámaras 700» hacia una
      -- petición que ahora dice «cámaras 26», y además contradice la lista de
      -- procedencias demostrables. `null` dice lo único cierto: no se sabe.
      -- La app vieja sigue guardando; sólo deja de reutilizar evidencia que
      -- nadie puede respaldar.
      case when v_previous.revision_no is null then 'initial' else null end,
      v_previous.technical_family
    );
  else
    v_next_revision := v_previous.revision_no;
  end if;

  v_response := jsonb_build_object(
    'need_id', v_need.id,
    'changed', v_changed,
    'version', v_need.version,
    'revision_no', v_next_revision,
    'need', to_jsonb(v_need)
  );

  insert into public.supply_need_events (
    tenant_id, supply_need_id, action, changed, actor_id, operation_key,
    request_snapshot, response_snapshot, occurred_at
  ) values (
    v_tenant_id, v_need.id, 'updated', v_changed, v_actor_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  ) returning * into v_event;

  return to_jsonb(v_event) || v_response
    || jsonb_build_object('replay', false);
end;
$$;

comment on function public.update_supply_need_v1(
  uuid, bigint, text, uuid, numeric, text, text
) is
  'Edición genérica heredada. Endurecida el 2026-08-29: una cantidad ya no crea revisión, y un texto corregido arrastra categoría, criterios y aclaraciones en vez de borrarlos pero deja la continuidad nula, así que su feed anterior deja de reutilizarse.';

-- -------------------------------------------------------------------------
-- 6. El recibo del portal declara qué interpretación estaba respondiendo.
--
-- La firma de 8 argumentos dejaba que el disparador pusiera la estampa al
-- momento del `insert`, que es justamente el instante equivocado: entre que un
-- recorrido empieza y termina pueden pasar minutos y una edición.
-- -------------------------------------------------------------------------

drop function if exists public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
);
-- `create or replace` no puede quitarle los defaults a una función que ya
-- existe, y acá quitarlos es el punto: sin eso absorbería las llamadas cortas.
drop function if exists public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb, bigint, bigint, uuid, text
);

create or replace function public.record_supplier_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid,
  p_search_query text,
  p_status text,
  p_source_url text,
  p_results jsonb,
  p_evidence jsonb,
  -- **Sin defaults, a propósito.** Con ellos, una llamada de 7 u 8 argumentos
  -- del cliente instalado calzaría acá rellenando nulos y moriría en `23514`.
  -- Sin ellos, esta firma sólo la alcanza quien manda los doce, y las cortas
  -- caen en su propio no-op de abajo.
  p_coverage jsonb,
  p_expected_need_version bigint,
  p_expected_revision_no bigint,
  p_expected_category_id uuid,
  p_expected_technical_family text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set statement_timeout = '9000ms'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_query text := btrim(coalesce(p_search_query, ''));
  v_limit integer;
  v_adapter jsonb;
  v_result_cap integer;
  v_coverage jsonb := coalesce(p_coverage, '{}'::jsonb);
  v_source_url text := nullif(btrim(coalesce(p_source_url, '')), '');
  v_id uuid;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;

  select probe.need_search_term_limit, probe.need_search_adapter
  into v_limit, v_adapter
  from public.supplier_portal_probes probe
  where probe.tenant_id = v_tenant_id
    and probe.supplier_id = p_supplier_id
    and probe.is_enabled
    and probe.need_search_url_template is not null;

  if v_limit is null
     or v_adapter is null
     or jsonb_typeof(v_adapter) <> 'object'
     or v_adapter->>'version' <> '1' then
    raise exception 'Need search is not configured' using errcode = 'P0002';
  end if;

  -- **El tope del cliente y el del recibo son el mismo número.** El adaptador
  -- lo publica y la app lo lee: por eso acá se valida contra él y no contra
  -- una constante que quedaría desalineada en la siguiente subida.
  v_result_cap := least(
    greatest(coalesce((v_adapter->>'result_cap')::integer, 40), 1),
    120
  );

  if char_length(v_query) not between 1 and v_limit
     or p_status not in (
       'completed', 'no_matches', 'session_expired', 'unreadable'
     )
     or jsonb_typeof(coalesce(p_results, 'null'::jsonb)) <> 'array'
     or jsonb_array_length(p_results) > v_result_cap
     or (p_status <> 'completed' and jsonb_array_length(p_results) > 0)
     or octet_length(p_results::text) > 98304
     or jsonb_typeof(coalesce(p_evidence, 'null'::jsonb)) <> 'object'
     or octet_length(p_evidence::text) > 8192
     or octet_length(coalesce(v_source_url, '')) > 500
     or (
       v_source_url is not null
       and (
         v_source_url !~ '^https?://'
         or position('?' in v_source_url) > 0
         or position('#' in v_source_url) > 0
         or position('@' in v_source_url) > 0
       )
     ) then
    raise exception 'Invalid need portal search' using errcode = '22023';
  end if;

  -- **La estampa la captura quien INICIA el recorrido, no quien lo guarda.**
  -- Un crawl que empezó en la revisión N y termina después de que alguien
  -- guardó N+1 tiene que perderse, no reetiquetarse: sus filas se leyeron
  -- contra otra ficha. El disparador compara esto contra la revisión vigente
  -- y rechaza la diferencia.
  if p_expected_need_version is null
     or p_expected_revision_no is null
     or p_expected_category_id is null
     or p_expected_need_version <= 0
     or p_expected_revision_no <= 0
     or octet_length(coalesce(p_expected_technical_family, '')) > 80 then
    raise exception 'Need search must declare the interpretation it answered'
      using errcode = '23514';
  end if;

  if jsonb_typeof(v_coverage) <> 'object'
     or octet_length(v_coverage::text) > 4096
     or (
       v_coverage <> '{}'::jsonb
       and (
         coalesce(v_coverage ->> 'method', '') not in (
           'taxonomy', 'word_search', 'none'
         )
         or coalesce(v_coverage ->> 'limit', '') not in (
           'enumerated', 'max_nodes', 'max_pages', 'max_rows', 'wall_clock',
           'storage_cap', 'loop_detected', 'session_expired', 'parser_drift',
           'encoding', 'transport', 'word_search_only', 'not_attempted'
         )
         or jsonb_typeof(v_coverage -> 'complete') <> 'boolean'
       )
     ) then
    raise exception 'Invalid need portal coverage' using errcode = '22023';
  end if;

  -- Una cobertura completa sólo la produce una enumeración terminada, y
  -- jamás el buscador por palabra ni una corrida que no concluyó.
  if v_coverage ->> 'complete' = 'true'
     and (
       v_coverage ->> 'limit' <> 'enumerated'
       or v_coverage ->> 'method' <> 'taxonomy'
       or p_status in ('session_expired', 'unreadable')
     ) then
    raise exception 'Coverage cannot claim a complete catalogue'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_results) result
    where jsonb_typeof(result) <> 'object'
       or coalesce(result->>'matchState', '') not in (
         'exact', 'possible', 'conflict'
       )
       or octet_length(coalesce(result->>'code', '')) > 80
       or octet_length(coalesce(result->>'name', '')) > 240
       or (
         result ? 'observedFacts'
         and jsonb_typeof(result->'observedFacts') <> 'object'
       )
  ) then
    raise exception 'Invalid need portal result' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.supply_needs need
    where need.id = p_supply_need_id and need.tenant_id = v_tenant_id
  ) then
    raise exception 'Supply need not found' using errcode = 'P0002';
  end if;

  insert into public.supplier_need_portal_searches (
    tenant_id, supplier_id, supply_need_id, search_query, status,
    source_url, results, evidence, coverage, created_by,
    need_version_at_search, interpretation_revision_no,
    interpretation_category_id, interpretation_technical_family
  ) values (
    v_tenant_id, p_supplier_id, p_supply_need_id, v_query, p_status,
    v_source_url, p_results, p_evidence, v_coverage, auth.uid(),
    p_expected_need_version, p_expected_revision_no,
    p_expected_category_id, p_expected_technical_family
  )
  returning id into v_id;

  return jsonb_build_object('status', 'recorded', 'searchId', v_id);
end;
$$;

revoke all on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb, bigint, bigint, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb, bigint, bigint, uuid, text
) to authenticated;

comment on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb, bigint, bigint, uuid, text
) is
  'Guarda lo que contestó el catálogo de un proveedor a una necesidad. La estampa de interpretación la captura quien inicia el recorrido y el disparador la valida contra la revisión vigente: una lectura que quedó vieja mientras corría se rechaza, nunca se reetiqueta.';

-- -------------------------------------------------------------------------
-- 7. El cliente instalado no se rompe, pero tampoco guarda evidencia vigente.
--
-- Desplegar este backend con la app anterior en los equipos es el caso normal,
-- no el excepcional: la app se actualiza después. Ese cliente llama la firma
-- de 7 argumentos —o de 8, si la migración de cobertura salió primero— y no
-- tiene forma de mandar la estampa de interpretación.
--
-- Fallar **cerrado y en silencio** es lo correcto acá: se responde
-- `client_upgrade_required`, no se inserta nada, y por lo tanto ese portal
-- queda «sin consultar» en vez de mostrar un feed que nadie puede fechar
-- contra una ficha. Lanzar una excepción rompería un flujo que hoy funciona;
-- guardar la fila sin estampa reintroduciría exactamente el defecto que este
-- bloque vino a cerrar.
-- -------------------------------------------------------------------------

create or replace function public.record_supplier_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid,
  p_search_query text,
  p_status text,
  p_source_url text,
  p_results jsonb,
  p_evidence jsonb
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'status', 'client_upgrade_required',
    'recorded', false,
    'reason', 'La app instalada no puede declarar qué ficha estaba '
      || 'respondiendo esta lectura.'
  );
$$;

create or replace function public.record_supplier_need_portal_search_v1(
  p_supplier_id uuid,
  p_supply_need_id uuid,
  p_search_query text,
  p_status text,
  p_source_url text,
  p_results jsonb,
  p_evidence jsonb,
  p_coverage jsonb
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'status', 'client_upgrade_required',
    'recorded', false,
    'reason', 'La app instalada no puede declarar qué ficha estaba '
      || 'respondiendo esta lectura.'
  );
$$;

revoke all on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
) to authenticated;

revoke all on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
) to authenticated;

comment on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb
) is
  'Compatibilidad con la app instalada. No guarda nada y lo dice: una lectura sin estampa de interpretación no puede presentarse como vigente. Actualizar el cliente habilita la firma de doce argumentos.';
comment on function public.record_supplier_need_portal_search_v1(
  uuid, uuid, text, text, text, jsonb, jsonb, jsonb
) is
  'Ídem, para el cliente que ya mandaba cobertura pero todavía no la estampa.';

commit;
