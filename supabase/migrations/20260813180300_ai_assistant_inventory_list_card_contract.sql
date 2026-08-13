-- Deployment status (2026-08-13): production-applied through the guarded
-- standalone-SQL path and registered as 20260813180300. Live read-back proved
-- the exact list accepted, count mismatch rejected, immutable invoker
-- execution, fixed search_path and no authenticated/anon EXECUTE grant.
--
-- The first inventory-list smoke proved the read RPC and both model rounds,
-- then failed durable completion because the ledger's closed card validator
-- still knew only entityRef/approvalRef. Extend that same fail-closed boundary
-- to the typed listRef; do not loosen arbitrary card JSON.
begin;

create or replace function public.assistant_cards_valid_v1(p_cards jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_card jsonb;
  v_chip jsonb;
  v_entity_ref jsonb;
  v_approval_ref jsonb;
  v_list_ref jsonb;
  v_list_entity_id jsonb;
  v_list_entity_ids text[];
  v_list_result_count integer;
  v_list_has_more boolean;
  v_kind text;
  v_destination text;
begin
  if p_cards is null or jsonb_typeof(p_cards) <> 'array'
     or jsonb_array_length(p_cards) > 6 then
    return false;
  end if;
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
       or exists (
         select 1 from jsonb_object_keys(v_card) key
         where key not in (
           'kind', 'title', 'destination', 'eyebrow', 'subtitle',
           'description', 'chips', 'entityRef', 'approvalRef', 'listRef'
         )
       ) then
      return false;
    end if;
    v_kind := v_card ->> 'kind';
    v_destination := v_card ->> 'destination';
    if v_kind !~ '^[a-z][a-z0-9_]{0,31}$'
       or octet_length(v_kind) > 32
       or octet_length(v_card ->> 'title') not between 1 and 160
       or octet_length(coalesce(v_card ->> 'eyebrow', '')) > 80
       or octet_length(coalesce(v_card ->> 'subtitle', '')) > 240
       or octet_length(coalesce(v_card ->> 'description', '')) > 500
       or not (
         (v_kind = 'customer' and v_destination = 'customers')
         or (v_kind = 'supplier' and v_destination = 'suppliers')
         or (v_kind = 'job' and v_destination = 'workshop_jobs')
         or (v_kind = 'sales_invoice' and v_destination = 'sales_invoices')
         or (v_kind = 'purchase_invoice' and v_destination = 'purchases')
         or (v_kind = 'inventory' and v_destination = 'inventory_products')
         or (v_kind in ('task', 'task_preview') and v_destination = 'tasks')
         or (v_kind = 'expense' and v_destination = 'expenses')
         or (v_kind = 'conversation' and v_destination = 'conversations')
       )
       or jsonb_array_length(v_card -> 'chips') > 4 then
      return false;
    end if;
    if v_card ? 'entityRef' then
      v_entity_ref := v_card -> 'entityRef';
      if v_kind = 'task_preview'
         or v_card ? 'listRef'
         or not (v_entity_ref ? 'kind' and v_entity_ref ? 'id')
         or jsonb_typeof(v_entity_ref -> 'kind') <> 'string'
         or jsonb_typeof(v_entity_ref -> 'id') <> 'string'
         or exists (
           select 1 from jsonb_object_keys(v_entity_ref) key
           where key not in ('kind', 'id')
         )
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
         ) then
        return false;
      end if;
    end if;
    if v_card ? 'listRef' then
      v_list_ref := v_card -> 'listRef';
      if v_kind <> 'inventory'
         or v_destination <> 'inventory_products'
         or v_card ? 'entityRef'
         or v_card ? 'approvalRef'
         or not (
           v_list_ref ? 'kind' and v_list_ref ? 'query'
           and v_list_ref ? 'availability' and v_list_ref ? 'resultCount'
           and v_list_ref ? 'hasMore' and v_list_ref ? 'entityIds'
           and v_list_ref ? 'autoOpen'
         )
         or exists (
           select 1 from jsonb_object_keys(v_list_ref) key
           where key not in (
             'kind', 'query', 'availability', 'resultCount', 'hasMore',
             'entityIds', 'autoOpen'
           )
         )
         or jsonb_typeof(v_list_ref -> 'kind') <> 'string'
         or jsonb_typeof(v_list_ref -> 'query') <> 'string'
         or jsonb_typeof(v_list_ref -> 'availability') <> 'string'
         or jsonb_typeof(v_list_ref -> 'resultCount') <> 'number'
         or jsonb_typeof(v_list_ref -> 'hasMore') <> 'boolean'
         or jsonb_typeof(v_list_ref -> 'autoOpen') <> 'boolean' then
        return false;
      end if;
      if v_list_ref ->> 'kind' <> 'inventory'
         or octet_length(btrim(v_list_ref ->> 'query')) not between 1 and 240
         or v_list_ref ->> 'availability' not in (
           'any', 'in_stock', 'low_stock', 'out_of_stock'
         )
         or v_list_ref ->> 'resultCount' !~ '^(0|[1-9]|10)$' then
        return false;
      end if;
      v_list_result_count := (v_list_ref ->> 'resultCount')::integer;
      v_list_has_more := (v_list_ref ->> 'hasMore')::boolean;
      if v_list_has_more then
        if v_list_ref -> 'entityIds' <> 'null'::jsonb then
          return false;
        end if;
      else
        if jsonb_typeof(v_list_ref -> 'entityIds') <> 'array'
           or jsonb_array_length(v_list_ref -> 'entityIds')
             <> v_list_result_count then
          return false;
        end if;
        v_list_entity_ids := array[]::text[];
        for v_list_entity_id in select value
          from jsonb_array_elements(v_list_ref -> 'entityIds') element(value)
        loop
          if jsonb_typeof(v_list_entity_id) <> 'string'
             or lower(v_list_entity_id #>> '{}') !~
               '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
             or lower(v_list_entity_id #>> '{}') = any(v_list_entity_ids) then
            return false;
          end if;
          v_list_entity_ids := array_append(
            v_list_entity_ids, lower(v_list_entity_id #>> '{}')
          );
        end loop;
      end if;
    end if;
    if v_kind = 'task_preview' then
      if not (v_card ? 'approvalRef') or v_card ? 'listRef' then
        return false;
      end if;
      v_approval_ref := v_card -> 'approvalRef';
      if not (v_approval_ref ? 'id' and v_approval_ref ? 'action'
          and v_approval_ref ? 'state' and v_approval_ref ? 'expiresAt')
         or exists (
           select 1 from jsonb_object_keys(v_approval_ref) key
           where key not in ('id', 'action', 'state', 'expiresAt')
         )
         or jsonb_typeof(v_approval_ref -> 'id') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'action') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'state') <> 'string'
         or jsonb_typeof(v_approval_ref -> 'expiresAt') <> 'string'
         or lower(v_approval_ref ->> 'id') !~
           '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
         or v_approval_ref ->> 'action' <> 'create_task'
         or v_approval_ref ->> 'state' not in (
           'pending', 'approved', 'discarded', 'expired'
         )
         or v_approval_ref ->> 'expiresAt' !~
           '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.]\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
        return false;
      end if;
    elsif v_card ? 'approvalRef' then
      return false;
    end if;
    for v_chip in select value
      from jsonb_array_elements(v_card -> 'chips') element(value)
    loop
      if jsonb_typeof(v_chip) <> 'string'
         or octet_length(v_chip #>> '{}') not between 1 and 64 then
        return false;
      end if;
    end loop;
  end loop;
  return true;
end;
$$;

revoke all on function public.assistant_cards_valid_v1(jsonb)
from public, anon, authenticated, service_role;

comment on function public.assistant_cards_valid_v1(jsonb) is
  'Closed durable assistant-card validator including exact entity, approval and inventory-list references.';

commit;
