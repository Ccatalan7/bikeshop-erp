-- La tarjeta de borrador aprende la procedencia de categoría.
--
-- **El defecto que cierra.** `20260817150000` (fase A) agregó `categoryId`,
-- `categoryPath` y `technicalFamily` a cada línea del borrador de necesidades.
-- El cliente las produce y las valida, pero `assistant_cards_valid_v1` —el
-- CHECK de `assistant_messages.cards`— conserva un allowlist cerrado que no las
-- conoce, así que **guardar la respuesta viola el constraint**. El síntoma no
-- se parecía a la causa: las seis herramientas de la corrida quedaban
-- `succeeded` —incluida `prepare_supply_request`— y el operador sólo veía «El
-- análisis no pudo completarse». La vía conversacional del Asistente de
-- compras no pudo cerrar ni un borrador desde que la fase A se desplegó.
--
-- Es la regla de las migraciones aditivas leída al revés: ampliar una forma
-- obliga a migrar **a todos sus validadores**, no sólo a quien la escribe.
-- Antes de ampliar una tarjeta, haz inventario de quién la comprueba.
--
-- **Opcionales, no exigidas.** Hay 18 mensajes con tarjetas de borrador
-- anteriores a la fase A que no traen las tres claves. Exigirlas rompería filas
-- vivas, así que se admiten ausentes; presentes, se comprueban enteras:
-- `categoryId` es identidad UUID o null, ruta y familia texto acotado o null, y
-- **sin identidad no hay ruta ni familia** —la misma coherencia que el cliente
-- exige en `validateSupplyNeedDraft`—. El allowlist sigue cerrado: ninguna otra
-- clave nueva entra.
--
-- Forward-only e idempotente.

begin;

CREATE OR REPLACE FUNCTION public.assistant_cards_valid_v1(p_cards jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
declare
  v_card jsonb; v_chip jsonb; v_entity_ref jsonb; v_approval_ref jsonb;
  v_list_ref jsonb; v_list_entity_id jsonb; v_list_entity_ids text[];
  v_list_result_count integer; v_list_has_more boolean;
  v_supply_draft jsonb; v_supply_line jsonb; v_supply_predicate jsonb;
  v_supply_value jsonb; v_supply_line_refs text[]; v_supply_fields text[];
  v_kind text; v_destination text; v_expected_action text;
begin
  if p_cards is null or jsonb_typeof(p_cards) <> 'array'
     or jsonb_array_length(p_cards) > 6 then return false; end if;
  for v_card in select value from jsonb_array_elements(p_cards) element(value)
  loop
    if jsonb_typeof(v_card) <> 'object'
       or not (v_card ? 'kind' and v_card ? 'title'
         and v_card ? 'destination' and v_card ? 'chips')
       or jsonb_typeof(v_card -> 'kind') <> 'string'
       or jsonb_typeof(v_card -> 'title') <> 'string'
       or jsonb_typeof(v_card -> 'destination') <> 'string'
       or jsonb_typeof(v_card -> 'chips') <> 'array'
       or (v_card ? 'eyebrow' and jsonb_typeof(v_card -> 'eyebrow') <> 'string')
       or (v_card ? 'subtitle' and jsonb_typeof(v_card -> 'subtitle') <> 'string')
       or (v_card ? 'description' and jsonb_typeof(v_card -> 'description') <> 'string')
       or (v_card ? 'entityRef' and jsonb_typeof(v_card -> 'entityRef') <> 'object')
       or (v_card ? 'approvalRef' and jsonb_typeof(v_card -> 'approvalRef') <> 'object')
       or (v_card ? 'listRef' and jsonb_typeof(v_card -> 'listRef') <> 'object')
       or (v_card ? 'supplyNeedDraft'
         and jsonb_typeof(v_card -> 'supplyNeedDraft') <> 'object')
       or exists (select 1 from jsonb_object_keys(v_card) key where key not in (
         'kind','title','destination','eyebrow','subtitle','description',
         'chips','entityRef','approvalRef','listRef','supplyNeedDraft'
       )) then return false; end if;
    v_kind := v_card ->> 'kind'; v_destination := v_card ->> 'destination';
    if v_kind !~ '^[a-z][a-z0-9_]{0,31}$'
       or octet_length(v_kind) > 32
       or octet_length(v_card ->> 'title') not between 1 and 160
       or octet_length(coalesce(v_card ->> 'eyebrow','')) > 80
       or octet_length(coalesce(v_card ->> 'subtitle','')) > 240
       or octet_length(coalesce(v_card ->> 'description','')) > 500
       or not (
         (v_kind = 'customer' and v_destination = 'customers')
         or (v_kind = 'supplier' and v_destination = 'suppliers')
         or (v_kind in ('job','diagnosis_preview','workshop_item_preview')
           and v_destination = 'workshop_jobs')
         or (v_kind = 'sales_invoice' and v_destination = 'sales_invoices')
         or (v_kind in ('purchase_invoice','supply_need_draft')
           and v_destination = 'purchases')
         or (v_kind = 'inventory' and v_destination = 'inventory_products')
         or (v_kind in ('task','task_preview') and v_destination = 'tasks')
         or (v_kind = 'expense' and v_destination = 'expenses')
         or (v_kind = 'conversation' and v_destination = 'conversations')
       ) or jsonb_array_length(v_card -> 'chips') > 4 then return false; end if;
    if v_card ? 'entityRef' then
      v_entity_ref := v_card -> 'entityRef';
      if v_kind in (
           'task_preview','diagnosis_preview','workshop_item_preview',
           'supply_need_draft'
         ) or v_card ? 'listRef' or v_card ? 'supplyNeedDraft'
         or not (v_entity_ref ? 'kind' and v_entity_ref ? 'id')
         or jsonb_typeof(v_entity_ref -> 'kind') <> 'string'
         or jsonb_typeof(v_entity_ref -> 'id') <> 'string'
         or exists (select 1 from jsonb_object_keys(v_entity_ref) key
           where key not in ('kind','id'))
         or lower(v_entity_ref ->> 'id') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or not (
           (v_kind = 'customer' and v_entity_ref ->> 'kind' = 'customer')
           or (v_kind = 'supplier' and v_entity_ref ->> 'kind' = 'supplier')
           or (v_kind = 'job' and v_entity_ref ->> 'kind' = 'workshopJob')
           or (v_kind = 'sales_invoice' and v_entity_ref ->> 'kind' = 'salesInvoice')
           or (v_kind = 'purchase_invoice' and v_entity_ref ->> 'kind' = 'purchaseInvoice')
           or (v_kind = 'inventory' and v_entity_ref ->> 'kind' = 'product')
           or (v_kind = 'expense' and v_entity_ref ->> 'kind' = 'expense')
           or (v_kind = 'conversation' and v_entity_ref ->> 'kind' = 'conversation')
         ) then return false; end if;
    end if;
    if v_card ? 'listRef' then
      v_list_ref := v_card -> 'listRef';
      if v_kind <> 'inventory' or v_destination <> 'inventory_products'
         or v_card ? 'entityRef' or v_card ? 'approvalRef'
         or v_card ? 'supplyNeedDraft'
         or not (v_list_ref ? 'kind' and v_list_ref ? 'query'
           and v_list_ref ? 'availability' and v_list_ref ? 'resultCount'
           and v_list_ref ? 'hasMore' and v_list_ref ? 'entityIds'
           and v_list_ref ? 'autoOpen')
         or exists (select 1 from jsonb_object_keys(v_list_ref) key where key not in (
           'kind','query','availability','resultCount','hasMore','entityIds','autoOpen'
         ))
         or jsonb_typeof(v_list_ref -> 'kind') <> 'string'
         or jsonb_typeof(v_list_ref -> 'query') <> 'string'
         or jsonb_typeof(v_list_ref -> 'availability') <> 'string'
         or jsonb_typeof(v_list_ref -> 'resultCount') <> 'number'
         or jsonb_typeof(v_list_ref -> 'hasMore') <> 'boolean'
         or jsonb_typeof(v_list_ref -> 'autoOpen') <> 'boolean'
         or v_list_ref ->> 'kind' <> 'inventory'
         or octet_length(btrim(v_list_ref ->> 'query')) not between 1 and 240
         or v_list_ref ->> 'availability' not in (
           'any','in_stock','low_stock','out_of_stock'
         ) or v_list_ref ->> 'resultCount' !~ '^(0|[1-9]|10)$' then
        return false;
      end if;
      v_list_result_count := (v_list_ref ->> 'resultCount')::integer;
      v_list_has_more := (v_list_ref ->> 'hasMore')::boolean;
      if v_list_has_more then
        if v_list_ref -> 'entityIds' <> 'null'::jsonb then return false; end if;
      else
        if jsonb_typeof(v_list_ref -> 'entityIds') <> 'array'
           or jsonb_array_length(v_list_ref -> 'entityIds') <> v_list_result_count
          then return false; end if;
        v_list_entity_ids := array[]::text[];
        for v_list_entity_id in select value
          from jsonb_array_elements(v_list_ref -> 'entityIds') element(value)
        loop
          if jsonb_typeof(v_list_entity_id) <> 'string'
             or lower(v_list_entity_id #>> '{}') !~
               '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
             or lower(v_list_entity_id #>> '{}') = any(v_list_entity_ids)
            then return false; end if;
          v_list_entity_ids := array_append(
            v_list_entity_ids, lower(v_list_entity_id #>> '{}')
          );
        end loop;
      end if;
    end if;
    v_expected_action := case v_kind
      when 'task_preview' then 'create_task'
      when 'diagnosis_preview' then 'update_diagnosis'
      when 'workshop_item_preview' then 'add_workshop_item'
      else null end;
    if v_expected_action is not null then
      if not (v_card ? 'approvalRef') or v_card ? 'listRef'
         or v_card ? 'supplyNeedDraft' then return false; end if;
      v_approval_ref := v_card -> 'approvalRef';
      if not (v_approval_ref ? 'id' and v_approval_ref ? 'action'
          and v_approval_ref ? 'state' and v_approval_ref ? 'expiresAt')
         or exists (select 1 from jsonb_object_keys(v_approval_ref) key
           where key not in ('id','action','state','expiresAt'))
         or jsonb_typeof(v_approval_ref -> 'id') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'action') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'state') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'expiresAt') <> 'string'
         or lower(v_approval_ref ->> 'id') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or v_approval_ref ->> 'action' <> v_expected_action
         or v_approval_ref ->> 'state' not in ('pending','approved','discarded','expired')
         or v_approval_ref ->> 'expiresAt' !~
           '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.]\d{1,6})?(Z|[+-]\d{2}:\d{2})$'
        then return false; end if;
    elsif v_card ? 'approvalRef' then return false; end if;

    if v_kind = 'supply_need_draft' then
      if not (v_card ? 'supplyNeedDraft') or v_card ? 'entityRef'
         or v_card ? 'approvalRef' or v_card ? 'listRef' then return false; end if;
      v_supply_draft := v_card -> 'supplyNeedDraft';
      if not (v_supply_draft ? 'profile' and v_supply_draft ? 'lines')
         or exists (select 1 from jsonb_object_keys(v_supply_draft) key
           where key not in ('profile','lines'))
         or jsonb_typeof(v_supply_draft -> 'profile') <> 'string'
         or v_supply_draft ->> 'profile' not in (
           'balanced','profitability','urgent_local'
         )
         or jsonb_typeof(v_supply_draft -> 'lines') <> 'array'
         or jsonb_array_length(v_supply_draft -> 'lines') not between 1 and 8
        then return false; end if;
      v_supply_line_refs := array[]::text[];
      for v_supply_line in select value
        from jsonb_array_elements(v_supply_draft -> 'lines') element(value)
      loop
        if jsonb_typeof(v_supply_line) <> 'object'
           or not (
             v_supply_line ? 'lineRef' and v_supply_line ? 'description'
             and v_supply_line ? 'productId' and v_supply_line ? 'productName'
             and v_supply_line ? 'productSku' and v_supply_line ? 'identityState'
             and v_supply_line ? 'quantity' and v_supply_line ? 'unit'
             and v_supply_line ? 'technicalPredicates'
             and v_supply_line ? 'preference' and v_supply_line ? 'clarification'
             and v_supply_line ? 'clarificationRequired'
           )
           or exists (select 1 from jsonb_object_keys(v_supply_line) key where key not in (
             'lineRef','description','productId','productName','productSku',
             'identityState','quantity','unit','technicalPredicates','preference',
             'clarification','clarificationRequired',
             -- Procedencia de categoria (fase A, 20260817150000).
             'categoryId','categoryPath','technicalFamily'
           ))
           -- **Opcionales, no exigidas.** Las 18 tarjetas ya persistidas son
           -- anteriores a la fase A y no las traen; exigirlas convertiria esta
           -- migracion en una que rompe filas vivas. Presentes, se comprueban
           -- entera y explicitamente: la ausencia se distingue del null.
           or (v_supply_line ? 'categoryId' and not (
             jsonb_typeof(v_supply_line -> 'categoryId') = 'null'
             or (jsonb_typeof(v_supply_line -> 'categoryId') = 'string'
               and lower(v_supply_line ->> 'categoryId') ~
                 '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
           ))
           or (v_supply_line ? 'categoryPath' and (
             jsonb_typeof(v_supply_line -> 'categoryPath') not in ('null','string')
             or (jsonb_typeof(v_supply_line -> 'categoryPath') = 'string'
               and octet_length(btrim(v_supply_line ->> 'categoryPath'))
                 not between 1 and 500)
           ))
           or (v_supply_line ? 'technicalFamily' and (
             jsonb_typeof(v_supply_line -> 'technicalFamily') not in ('null','string')
             or (jsonb_typeof(v_supply_line -> 'technicalFamily') = 'string'
               and octet_length(btrim(v_supply_line ->> 'technicalFamily'))
                 not between 1 and 120)
           ))
           -- Sin identidad de categoria no hay ruta ni familia: una glosa sin
           -- nada detras seria una afirmacion que nada respalda. Misma regla
           -- que el cliente aplica en `validateSupplyNeedDraft`.
           or (coalesce(jsonb_typeof(v_supply_line -> 'categoryId'), 'null') = 'null'
             and (
               coalesce(jsonb_typeof(v_supply_line -> 'categoryPath'), 'null') <> 'null'
               or coalesce(jsonb_typeof(v_supply_line -> 'technicalFamily'), 'null') <> 'null'
             ))
           or jsonb_typeof(v_supply_line -> 'lineRef') <> 'string'
           or v_supply_line ->> 'lineRef' !~ '^line-[1-8]$'
           or v_supply_line ->> 'lineRef' = any(v_supply_line_refs)
           or jsonb_typeof(v_supply_line -> 'description') <> 'string'
           or octet_length(btrim(v_supply_line ->> 'description')) not between 1 and 2000
           or not (
             jsonb_typeof(v_supply_line -> 'productId') = 'null'
             or (jsonb_typeof(v_supply_line -> 'productId') = 'string'
               and lower(v_supply_line ->> 'productId') ~
                 '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
           )
           or jsonb_typeof(v_supply_line -> 'productName') not in ('null','string')
           or jsonb_typeof(v_supply_line -> 'productSku') not in ('null','string')
           or jsonb_typeof(v_supply_line -> 'identityState') <> 'string'
           or v_supply_line ->> 'identityState' not in ('unresolved','confirmed')
           or jsonb_typeof(v_supply_line -> 'quantity') <> 'number'
           or (v_supply_line ->> 'quantity')::numeric not between 0.001 and 999999
           or jsonb_typeof(v_supply_line -> 'unit') <> 'string'
           or octet_length(btrim(v_supply_line ->> 'unit')) not between 1 and 32
           or jsonb_typeof(v_supply_line -> 'technicalPredicates') <> 'array'
           or jsonb_array_length(v_supply_line -> 'technicalPredicates') > 8
           or jsonb_typeof(v_supply_line -> 'preference') not in ('null','string')
           or (jsonb_typeof(v_supply_line -> 'preference') = 'string'
             and octet_length(btrim(v_supply_line ->> 'preference')) not between 1 and 240)
           or jsonb_typeof(v_supply_line -> 'clarification') not in ('null','string')
           or (jsonb_typeof(v_supply_line -> 'clarification') = 'string'
             and octet_length(btrim(v_supply_line ->> 'clarification')) not between 1 and 500)
           or jsonb_typeof(v_supply_line -> 'clarificationRequired') <> 'boolean'
          then return false; end if;

        if v_supply_line ->> 'identityState' = 'unresolved' then
          if jsonb_typeof(v_supply_line -> 'productId') <> 'null'
             or jsonb_typeof(v_supply_line -> 'productName') <> 'null'
             or jsonb_typeof(v_supply_line -> 'productSku') <> 'null'
            then return false; end if;
        else
          if jsonb_typeof(v_supply_line -> 'productId') <> 'string'
             or jsonb_typeof(v_supply_line -> 'productName') <> 'string'
             or octet_length(btrim(v_supply_line ->> 'productName')) not between 1 and 500
             or (jsonb_typeof(v_supply_line -> 'productSku') = 'string'
               and octet_length(btrim(v_supply_line ->> 'productSku')) not between 1 and 160)
            then return false; end if;
        end if;
        if (v_supply_line ->> 'clarificationRequired')::boolean
           and (jsonb_typeof(v_supply_line -> 'clarification') <> 'string'
             or jsonb_typeof(v_supply_line -> 'productId') <> 'null')
          then return false; end if;

        v_supply_fields := array[]::text[];
        for v_supply_predicate in select value
          from jsonb_array_elements(v_supply_line -> 'technicalPredicates') element(value)
        loop
          if jsonb_typeof(v_supply_predicate) <> 'object'
             or not (v_supply_predicate ? 'field'
               and v_supply_predicate ? 'operator' and v_supply_predicate ? 'values')
             or exists (select 1 from jsonb_object_keys(v_supply_predicate) key
               where key not in ('field','operator','values'))
             or jsonb_typeof(v_supply_predicate -> 'field') <> 'string'
             or v_supply_predicate ->> 'field' !~ '^[a-z][a-z0-9_]{1,63}$'
             or v_supply_predicate ->> 'field' = any(v_supply_fields)
             or jsonb_typeof(v_supply_predicate -> 'operator') <> 'string'
             or v_supply_predicate ->> 'operator' not in (
               'eq','neq','lt','lte','gt','gte','between','in','contains'
             )
             or jsonb_typeof(v_supply_predicate -> 'values') <> 'array'
             or jsonb_array_length(v_supply_predicate -> 'values') not between 1 and 10
             or (v_supply_predicate ->> 'operator' = 'between'
               and jsonb_array_length(v_supply_predicate -> 'values') <> 2)
             or (v_supply_predicate ->> 'operator' not in ('between','in')
               and jsonb_array_length(v_supply_predicate -> 'values') <> 1)
            then return false; end if;
          for v_supply_value in select value
            from jsonb_array_elements(v_supply_predicate -> 'values') element(value)
          loop
            if jsonb_typeof(v_supply_value) not in ('string','number','boolean')
               or (jsonb_typeof(v_supply_value) = 'string'
                 and octet_length(v_supply_value #>> '{}') > 160)
              then return false; end if;
          end loop;
          v_supply_fields := array_append(
            v_supply_fields, v_supply_predicate ->> 'field'
          );
        end loop;
        v_supply_line_refs := array_append(
          v_supply_line_refs, v_supply_line ->> 'lineRef'
        );
      end loop;
    elsif v_card ? 'supplyNeedDraft' then return false; end if;

    for v_chip in select value from jsonb_array_elements(v_card -> 'chips') element(value)
    loop
      if jsonb_typeof(v_chip) <> 'string'
         or octet_length(v_chip #>> '{}') not between 1 and 64 then return false; end if;
    end loop;
  end loop;
  return true;
end;
$function$
;

comment on function public.assistant_cards_valid_v1(jsonb) is
  'Closed validator for persisted assistant cards. Supply-need draft lines may carry category provenance since phase A (20260817150000): categoryId is a UUID identity or null, path and family are bounded text or null, and neither may appear without the identity behind them. The three keys are optional so pre-phase-A cards stay valid.';

commit;
