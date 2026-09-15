-- Turn several rows from the purchase-priority feed into one replay-safe
-- search basket.
--
-- Workshop rows are already durable `supply_needs` and are only returned.
-- Stock signals become canonical ad-hoc needs through `create_supply_need_v1`,
-- preserving manual/system provenance instead of pretending the rows came
-- from an AI-authored request. One receipt owns the whole selection so a lost
-- response can be retried without duplicating any demand.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create table if not exists public.purchase_priority_batch_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  operation_key text not null check (
    btrim(operation_key) <> '' and octet_length(operation_key) <= 160
  ),
  request_snapshot jsonb not null check (
    jsonb_typeof(request_snapshot) = 'object'
    and not public.jsonb_contains_sensitive_key(request_snapshot)
  ),
  response_snapshot jsonb not null check (
    jsonb_typeof(response_snapshot) = 'object'
    and not public.jsonb_contains_sensitive_key(response_snapshot)
  ),
  created_at timestamptz not null default clock_timestamp(),
  unique (tenant_id, operation_key)
);

alter table public.purchase_priority_batch_receipts enable row level security;
revoke all on public.purchase_priority_batch_receipts
  from public, anon, authenticated, service_role;

drop trigger if exists trg_purchase_priority_batch_receipts_immutable
  on public.purchase_priority_batch_receipts;
create trigger trg_purchase_priority_batch_receipts_immutable
  before update or delete on public.purchase_priority_batch_receipts
  for each row execute function public.prevent_supply_kernel_evidence_mutation();

create or replace function public.take_purchase_priority_batch_v1(
  p_items jsonb,
  p_rotation_days integer,
  p_operation_key text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions, pg_temp
set lock_timeout = '750ms'
set statement_timeout = '12s'
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_actor_id uuid := auth.uid();
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_normalized_items jsonb := '[]'::jsonb;
  v_seen text[] := array[]::text[];
  v_item jsonb;
  v_source text;
  v_entity_id uuid;
  v_identity text;
  v_request jsonb;
  v_response jsonb;
  v_receipt public.purchase_priority_batch_receipts%rowtype;
  v_seed uuid;
  v_feed_items jsonb;
  v_priority_item jsonb;
  v_need public.supply_needs%rowtype;
  v_created jsonb;
  v_needs jsonb := '[]'::jsonb;
  v_created_count integer := 0;
  v_index integer := 0;
begin
  if v_tenant_id is null or v_actor_id is null then
    raise exception 'No hay una sesión de negocio activa.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 8
     or p_rotation_days not between 7 and 730
     or v_operation_key = ''
     or octet_length(v_operation_key) > 160 then
    raise exception 'La selección de prioridades no es válida.'
      using errcode = '22023';
  end if;

  -- Only opaque feed identities cross the trust boundary. Product, quantity,
  -- description and provenance are re-read from the authoritative feed.
  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object'
       or not (v_item ?& array['source', 'entityId'])
       or exists (
         select 1 from jsonb_object_keys(v_item) key
         where key not in ('source', 'entityId')
       )
       or jsonb_typeof(v_item -> 'source') <> 'string'
       or jsonb_typeof(v_item -> 'entityId') <> 'string' then
      raise exception 'La selección de prioridades no es válida.'
        using errcode = '22023';
    end if;
    v_source := v_item ->> 'source';
    if v_source not in ('workshop', 'stockout', 'below_minimum')
       or (v_item ->> 'entityId') !~*
         '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
      raise exception 'La selección de prioridades no es válida.'
        using errcode = '22023';
    end if;
    v_entity_id := (v_item ->> 'entityId')::uuid;
    v_identity := v_source || ':' || v_entity_id::text;
    if v_identity = any(v_seen) then
      raise exception 'La selección de prioridades contiene filas repetidas.'
        using errcode = '22023';
    end if;
    v_seen := array_append(v_seen, v_identity);
    v_normalized_items := v_normalized_items || jsonb_build_array(
      jsonb_build_object('source', v_source, 'entityId', v_entity_id)
    );
  end loop;

  v_request := jsonb_build_object(
    'version', 1,
    'items', v_normalized_items,
    'rotation_days', p_rotation_days
  );

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':purchase_priority_batch:' || v_operation_key, 0
  ));

  select receipt.* into v_receipt
  from public.purchase_priority_batch_receipts receipt
  where receipt.tenant_id = v_tenant_id
    and receipt.operation_key = v_operation_key;
  if found then
    if v_receipt.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación pertenece a otra selección.'
        using errcode = '23505';
    end if;
    return v_receipt.response_snapshot || jsonb_build_object('replay', true);
  end if;

  -- The seed is generated after reserving the public operation. Inner event
  -- keys cannot be pre-seeded by another member of the same tenant.
  v_seed := gen_random_uuid();
  v_feed_items := public.purchase_priority_feed_v1(
    200, p_rotation_days
  ) -> 'items';

  for v_item in select value from jsonb_array_elements(v_normalized_items) loop
    v_index := v_index + 1;
    v_source := v_item ->> 'source';
    v_entity_id := (v_item ->> 'entityId')::uuid;
    v_priority_item := null;

    select feed.value into v_priority_item
    from jsonb_array_elements(v_feed_items) feed(value)
    where feed.value ->> 'source' = v_source
      and feed.value ->> 'entityId' = v_entity_id::text
    limit 1;
    if v_priority_item is null then
      raise exception 'La prioridad cambió; vuelve a cargar la lista.'
        using errcode = '40001';
    end if;

    if v_source = 'workshop' then
      select need.* into v_need
      from public.supply_needs need
      where need.tenant_id = v_tenant_id
        and need.id = v_entity_id
        and need.origin_kind = 'mechanic_job'
        and need.supply_state = 'open'
      for share;
      if not found then
        raise exception 'La necesidad del trabajo ya no está pendiente.'
          using errcode = '40001';
      end if;
    else
      -- Two concurrent priority batches for the same catalog product converge
      -- on one open need. The feed's already-needed filter handles normal
      -- reloads; this lock closes the race between two simultaneous clicks.
      perform pg_advisory_xact_lock(hashtextextended(
        v_tenant_id::text || ':purchase_priority_product:' ||
          (v_priority_item ->> 'productId'), 0
      ));
      select need.* into v_need
      from public.supply_needs need
      where need.tenant_id = v_tenant_id
        and need.product_id = (v_priority_item ->> 'productId')::uuid
        and need.supply_state = 'open'
      order by need.created_at desc, need.id
      limit 1
      for share;

      if not found then
        v_created := public.create_supply_need_v1(
          'ad_hoc', null, null,
          v_priority_item ->> 'title',
          (v_priority_item ->> 'productId')::uuid,
          (v_priority_item ->> 'suggestedQuantity')::numeric,
          v_priority_item ->> 'unit',
          null,
          'priority-batch:' || v_seed::text || ':' || v_index::text
        );
        v_need := jsonb_populate_record(
          null::public.supply_needs, v_created -> 'need'
        );
        v_created_count := v_created_count + 1;
      end if;
    end if;

    v_needs := v_needs || jsonb_build_array(to_jsonb(v_need));
  end loop;

  v_response := jsonb_build_object(
    'batchId', v_seed,
    'changed', v_created_count > 0,
    'createdCount', v_created_count,
    'needCount', jsonb_array_length(v_needs),
    'needs', v_needs
  );

  insert into public.purchase_priority_batch_receipts (
    id, tenant_id, actor_id, operation_key,
    request_snapshot, response_snapshot
  ) values (
    v_seed, v_tenant_id, v_actor_id, v_operation_key,
    v_request, v_response
  );

  return v_response || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.take_purchase_priority_batch_v1(
  jsonb, integer, text
) from public, anon, authenticated, service_role;
grant execute on function public.take_purchase_priority_batch_v1(
  jsonb, integer, text
) to authenticated;

comment on function public.take_purchase_priority_batch_v1(
  jsonb, integer, text
) is
  'Replay-safe 1..8 row handoff from the authoritative purchase-priority feed to one purchasing basket. Existing workshop needs are returned unchanged; current stock signals create canonical manual-provenance ad-hoc needs. The command rejects stale or forged feed identities and prevents concurrent priority batches from duplicating one product.';

commit;
