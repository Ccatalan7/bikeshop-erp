-- La rama se deduce de la descripción; no se le exige al modelo.
--
-- Una necesidad se guardaba con `category_id` nulo porque el modelo nunca
-- resuelve una referencia de categoría. De ese nulo colgaban TRES fallas que el
-- dueño encontró seguidas en la app real, con «Cámaras 29 Schrader»:
--
--   · «Stock interno» completamente vacío, teniendo 7 unidades en bodega
--   · «Falta decir qué categoría es» en el paso Proveedores
--   · «No se pudo fijar el producto de la necesidad» al elegir uno de bodega,
--     porque `confirm_supply_need_family_choice_v1` exige un conjunto elegible
--     y sin categoría no existe ninguno
--
-- Su frase resume el defecto: «claramente la categoría es cámara». La
-- categoría es un dato del catálogo, no una decisión del operador ni del
-- modelo. Se deduce con el mismo resolvedor que usa el ranking, y sólo cuando
-- hay una rama dominante.

begin;

CREATE OR REPLACE FUNCTION public.create_supply_need_batch_v2(p_original_request text, p_items jsonb, p_profile text, p_assistant_thread_id uuid, p_operation_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET lock_timeout TO '750ms'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_original_request text := btrim(coalesce(p_original_request, ''));
  v_request jsonb;
  v_response jsonb;
  v_normalized jsonb;
  v_item jsonb;
  v_need public.supply_needs%rowtype;
  v_receipt public.supply_need_batch_receipts%rowtype;
  v_constraints jsonb;
  v_clarifications jsonb;
  v_needs jsonb := '[]'::jsonb;
  v_batch_id uuid := gen_random_uuid();
  v_line_operation_key text;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if v_original_request = '' or octet_length(v_original_request) > 2000
     or v_operation_key = '' or octet_length(v_operation_key) > 160 then
    raise exception 'La petición de abastecimiento no es válida.'
      using errcode = '22023';
  end if;
  if p_profile not in ('balanced', 'profitability', 'urgent_local') then
    raise exception 'El objetivo de abastecimiento no es válido.'
      using errcode = '22023';
  end if;
  if p_assistant_thread_id is not null and not exists (
    select 1 from public.assistant_threads thread
    where thread.tenant_id = v_tenant_id
      and thread.actor_user_id = v_actor_id
      and thread.id = p_assistant_thread_id
      and thread.state <> 'deleted'
  ) then
    raise exception 'La conversación de IA no pertenece a esta sesión.'
      using errcode = '42501';
  end if;

  v_normalized := public.normalize_supply_request_items_internal_v2(
    v_tenant_id,
    p_items
  );

  -- **Las etiquetas derivadas no entran a nada durable.** `categoryPath` sale
  -- de `product_categories.full_path` y `technicalFamily` de
  -- `category_tech_mappings`: las dos cambian cuando alguien reorganiza el
  -- árbol o remapea una familia, sin que la petición del operador haya
  -- cambiado en nada. Guardarlas rompería el replay —la misma clave de
  -- operación dejaría de coincidir consigo misma tras un rename— y dejaría en
  -- el ledger una copia que envejece al lado de su fuente. La identidad
  -- estable, `categoryId`, es la que se conserva; la glosa se deriva cuando se
  -- necesite mostrar.
  select jsonb_agg(
    item.value - 'categoryPath' - 'technicalFamily'
    order by item.ordinality
  ) into v_normalized
  from jsonb_array_elements(v_normalized)
    with ordinality item(value, ordinality);

  v_request := jsonb_build_object(
    'original_request', v_original_request,
    'items', v_normalized,
    'profile', p_profile,
    'assistant_thread_id', p_assistant_thread_id
  );

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':supply_need_batch:' || v_operation_key,
    0
  ));

  select receipt.* into v_receipt
  from public.supply_need_batch_receipts receipt
  where receipt.tenant_id = v_tenant_id
    and receipt.operation_key = v_operation_key;
  if found then
    if v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otra petición.'
        using errcode = '23505';
    end if;
    return v_receipt.response_snapshot || jsonb_build_object('replay', true);
  end if;

  for v_item in
    select value from jsonb_array_elements(v_normalized)
  loop
    v_constraints := coalesce(v_item -> 'technicalPredicates', '[]'::jsonb);
    v_constraints := v_constraints || jsonb_build_array(jsonb_build_object(
      'kind', 'ranking_profile',
      'value', p_profile
    ));
    if v_item ->> 'preference' is not null then
      v_constraints := v_constraints || jsonb_build_array(jsonb_build_object(
        'kind', 'commercial_preference',
        'value', v_item ->> 'preference'
      ));
    end if;
    v_clarifications := case
      when v_item ->> 'clarification' is null then '[]'::jsonb
      else jsonb_build_array(jsonb_build_object(
        'question', v_item ->> 'clarification',
        'blocking', (v_item ->> 'clarificationRequired')::boolean
      ))
    end;

    insert into public.supply_needs (
      tenant_id, origin_kind, assistant_thread_id, original_description,
      product_id, quantity, unit, identity_state, supply_state, usage_state,
      version, created_by, updated_by, created_at, updated_at
    ) values (
      v_tenant_id, 'ad_hoc', p_assistant_thread_id,
      v_item ->> 'description', nullif(v_item ->> 'productId', '')::uuid,
      (v_item ->> 'quantity')::numeric, v_item ->> 'unit',
      v_item ->> 'identityState', 'open', 'not_applicable',
      1, v_actor_id, v_actor_id, clock_timestamp(), clock_timestamp()
    ) returning * into v_need;

    insert into public.supply_need_interpretation_revisions (
      tenant_id, supply_need_id, revision_no, source, raw_description,
      identity_state, canonical_product_id, category_id, constraints,
      clarifications, evidence_snapshot, formula_version, created_by
    ) values (
      v_tenant_id, v_need.id, 1, 'ai', v_original_request,
      v_need.identity_state, v_need.product_id,
      -- La ranura estaba desde el kernel y nunca se llenó. La familia técnica
      -- **no** se guarda: se deriva de `category_tech_mappings` en cada
      -- lectura, para que no envejezca una copia.
      -- **La rama se deduce; no se le exige al modelo.**
      --
      -- Esta ranura esperaba una referencia de categoría resuelta que el modelo
      -- casi nunca trae, y de su nulo colgaba todo: «Stock interno» vacío,
      -- «Falta decir qué categoría es» en Proveedores, y «No se pudo fijar el
      -- producto» al elegir uno de bodega —porque sin categoría no hay conjunto
      -- elegible que confirmar—. El dueño lo dijo mirando la pantalla:
      -- «claramente la categoría es cámara».
      --
      -- La categoría es un dato del catálogo, no una decisión del operador. Se
      -- deduce de los productos a los que resuelve la descripción, y sólo
      -- cuando hay una rama dominante: repartida, se conserva el nulo, porque
      -- inventarla sacaría el conjunto elegible del lugar equivocado.
      coalesce(
        nullif(v_item ->> 'categoryId', '')::uuid,
        public.supply_need_category_for_phrase_internal_v1(
          v_tenant_id, v_item ->> 'description'
        )
      ),
      v_constraints, v_clarifications,
      -- Sin `category_path` ni `technical_family`: son derivadas y su dueño
      -- —`product_categories` y `category_tech_mappings`— responde por ellas
      -- en cada lectura. `category_id` de arriba es la identidad que las
      -- reconstruye.
      jsonb_strip_nulls(jsonb_build_object(
        'line_ref', v_item ->> 'lineRef',
        'product_name', v_item ->> 'productName',
        'product_sku', v_item ->> 'productSku',
        'assistant_thread_id', p_assistant_thread_id
      )),
      'ai-supply-request-v2', v_actor_id
    );

    v_line_operation_key := v_operation_key || ':' || (v_item ->> 'lineRef');
    v_response := jsonb_build_object(
      'need_id', v_need.id,
      'changed', true,
      'version', v_need.version,
      'need', to_jsonb(v_need),
      'line_ref', v_item ->> 'lineRef',
      'batch_id', v_batch_id
    );
    insert into public.supply_need_events (
      tenant_id, supply_need_id, action, changed, actor_id, operation_key,
      request_snapshot, response_snapshot, occurred_at
    ) values (
      v_tenant_id, v_need.id, 'created', true, v_actor_id,
      v_line_operation_key,
      jsonb_build_object(
        'origin_kind', 'ad_hoc',
        'description', v_item ->> 'description',
        'product_id', v_item -> 'productId',
        -- Única adición al evento: de dónde salió la categoría de la línea.
        'category_id', v_item -> 'categoryId',
        'quantity', v_item -> 'quantity',
        'unit', v_item ->> 'unit',
        'assistant_thread_id', p_assistant_thread_id,
        'batch_id', v_batch_id,
        'line_ref', v_item ->> 'lineRef'
      ),
      v_response,
      clock_timestamp()
    );
    v_needs := v_needs || jsonb_build_array(
      to_jsonb(v_need) || jsonb_build_object('line_ref', v_item ->> 'lineRef')
    );
  end loop;

  v_response := jsonb_build_object(
    'batch_id', v_batch_id,
    'changed', true,
    'needs', v_needs,
    'need_count', jsonb_array_length(v_needs)
  );
  insert into public.supply_need_batch_receipts (
    id, tenant_id, actor_id, assistant_thread_id, operation_key,
    request_snapshot, response_snapshot, created_at
  ) values (
    v_batch_id, v_tenant_id, v_actor_id, p_assistant_thread_id,
    v_operation_key, v_request, v_response, clock_timestamp()
  );

  return v_response || jsonb_build_object('replay', false);
end;
$function$
;

commit;
