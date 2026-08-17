-- Structured, review-first AI supply requests.
--
-- Forward behavior:
--   1. Publish one read-only assistant projection that turns a model-authored
--      decomposition into a server-validated draft. Exact products arrive
--      only after the runtime resolves opaque catalog references.
--   2. Add one atomic, replay-safe batch command used only after an explicit
--      operator click. It creates 1..8 canonical supply needs and records AI
--      interpretation revisions without assigning stock, creating purchases,
--      or changing workshop status.
-- Recovery:
--   Roll the gateway/client back. The additive command, receipts and any
--   explicitly confirmed supply needs remain valid audit evidence.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

create table if not exists public.supply_need_batch_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  assistant_thread_id uuid references public.assistant_threads(id)
    on delete set null,
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

alter table public.supply_need_batch_receipts enable row level security;
revoke all on public.supply_need_batch_receipts
  from public, anon, authenticated, service_role;

drop trigger if exists trg_supply_need_batch_receipts_immutable
  on public.supply_need_batch_receipts;
create trigger trg_supply_need_batch_receipts_immutable
  before update or delete on public.supply_need_batch_receipts
  for each row execute function public.prevent_supply_kernel_evidence_mutation();

create or replace function public.normalize_supply_request_items_internal_v1(
  p_tenant_id uuid,
  p_items jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_item jsonb;
  v_predicate jsonb;
  v_value jsonb;
  v_product_id uuid;
  v_product_name text;
  v_product_sku text;
  v_identity_surface text;
  v_identity_raw text;
  v_line_refs text[] := array[]::text[];
  v_predicate_fields text[];
  v_line_ref text;
  v_description text;
  v_unit text;
  v_preference text;
  v_clarification text;
  v_field text;
  v_operator text;
  v_quantity numeric;
  v_values jsonb;
  v_values_count integer;
  v_definition record;
  v_predicate_source text;
  v_normalized jsonb := '[]'::jsonb;
  v_allowed_keys constant text[] := array[
    'lineRef', 'description', 'productId', 'quantity', 'unit',
    'technicalPredicates', 'preference', 'clarification',
    'clarificationRequired'
  ];
begin
  if p_tenant_id is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 8 then
    raise exception 'Invalid supply request items' using errcode = '22023';
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_item) <> 'object'
       or not (v_item ?& v_allowed_keys)
       or exists (
         select 1
         from jsonb_object_keys(v_item) key
         where not (key = any(v_allowed_keys))
       ) then
      raise exception 'Invalid supply request item' using errcode = '22023';
    end if;

    v_line_ref := v_item ->> 'lineRef';
    v_description := btrim(coalesce(v_item ->> 'description', ''));
    v_unit := btrim(coalesce(v_item ->> 'unit', ''));
    v_preference := nullif(btrim(coalesce(v_item ->> 'preference', '')), '');
    v_clarification :=
      nullif(btrim(coalesce(v_item ->> 'clarification', '')), '');

    if v_line_ref !~ '^line-[1-8]$'
       or v_line_ref = any(v_line_refs)
       or v_description = '' or octet_length(v_description) > 2000
       or v_unit = '' or octet_length(v_unit) > 32
       or jsonb_typeof(v_item -> 'quantity') <> 'number'
       or jsonb_typeof(v_item -> 'clarificationRequired') <> 'boolean'
       or (v_preference is not null and octet_length(v_preference) > 240)
       or (v_clarification is not null and octet_length(v_clarification) > 500)
       or (v_item -> 'preference') is null
       or jsonb_typeof(v_item -> 'preference') not in ('string', 'null')
       or (v_item -> 'clarification') is null
       or jsonb_typeof(v_item -> 'clarification') not in ('string', 'null')
       or (v_item -> 'productId') is null
       or jsonb_typeof(v_item -> 'productId') not in ('string', 'null')
       or jsonb_typeof(v_item -> 'technicalPredicates') <> 'array'
       or jsonb_array_length(v_item -> 'technicalPredicates') > 8 then
      raise exception 'Invalid supply request item' using errcode = '22023';
    end if;

    v_quantity := (v_item ->> 'quantity')::numeric;
    if v_quantity < 0.001 or v_quantity > 999999 then
      raise exception 'Invalid supply request quantity' using errcode = '22023';
    end if;

    v_product_id := null;
    v_product_name := null;
    v_product_sku := null;
    v_identity_surface := null;
    v_identity_raw := null;
    if jsonb_typeof(v_item -> 'productId') = 'string' then
      if (v_item ->> 'productId') !~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        raise exception 'Invalid catalog product' using errcode = '22023';
      end if;
      v_product_id := (v_item ->> 'productId')::uuid;
      select product.name, product.sku,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.brand, product.model, product.manufacturer,
          product.category_name, product.category
        )),
        unaccent(lower(concat_ws(' ', product.name, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category)))
      into v_product_name, v_product_sku, v_identity_surface, v_identity_raw
      from public.products product
      where product.tenant_id = p_tenant_id
        and product.id = v_product_id
        and product.is_active is true
        and not coalesce(product.is_service, false)
        and coalesce(product.product_type, 'product') <> 'service';
      if not found then
        raise exception 'Catalog product is unavailable' using errcode = '23514';
      end if;
    end if;

    if (v_item ->> 'clarificationRequired')::boolean
       and (v_clarification is null or v_product_id is not null) then
      raise exception 'Invalid blocking clarification' using errcode = '22023';
    end if;

    v_predicate_fields := array[]::text[];
    for v_predicate in
      select value from jsonb_array_elements(v_item -> 'technicalPredicates')
    loop
      if jsonb_typeof(v_predicate) <> 'object'
         or not (v_predicate ?& array['field', 'operator', 'values'])
         or exists (
           select 1 from jsonb_object_keys(v_predicate) key
           where not (key = any(array['field', 'operator', 'values']))
         )
         or coalesce(v_predicate ->> 'field', '')
              !~ '^[a-z][a-z0-9_]{1,63}$'
         or coalesce(v_predicate ->> 'operator', '') not in (
           'eq', 'neq', 'lt', 'lte', 'gt', 'gte', 'between', 'in', 'contains'
         )
         or jsonb_typeof(v_predicate -> 'values') <> 'array' then
        raise exception 'Invalid technical predicate' using errcode = '22023';
      end if;
      v_field := v_predicate ->> 'field';
      v_operator := v_predicate ->> 'operator';
      v_values := v_predicate -> 'values';
      v_values_count := jsonb_array_length(v_predicate -> 'values');
      if v_values_count not between 1 and 10
         or v_field = any(v_predicate_fields)
         or (v_operator = 'between' and v_values_count <> 2)
         or (v_operator not in ('between', 'in')
           and v_values_count <> 1) then
        raise exception 'Invalid technical predicate values'
          using errcode = '22023';
      end if;
      for v_value in
        select value from jsonb_array_elements(v_predicate -> 'values')
      loop
        if jsonb_typeof(v_value) not in ('string', 'number', 'boolean')
           or (jsonb_typeof(v_value) = 'string'
             and octet_length(v_value #>> '{}') > 160) then
          raise exception 'Invalid technical predicate value'
            using errcode = '22023';
        end if;
      end loop;

      select definition.data_type, definition.allowed_values
      into v_definition
      from public.spec_definitions definition
      where definition.key = v_field
        and (definition.tenant_id is null
          or definition.tenant_id = p_tenant_id)
        and definition.is_filterable is true
      order by (definition.tenant_id is not null) desc
      limit 1;
      if not found then
        raise exception 'Unknown technical predicate' using errcode = '22023';
      end if;

      if (v_definition.data_type = 'number' and (
          v_operator not in ('eq','neq','lt','lte','gt','gte','between','in')
          or exists (
            select 1 from jsonb_array_elements(v_values) requested(value)
            where jsonb_typeof(requested.value) <> 'number'
          )
        ))
        or (v_definition.data_type = 'boolean' and (
          v_operator not in ('eq','neq')
          or exists (
            select 1 from jsonb_array_elements(v_values) requested(value)
            where jsonb_typeof(requested.value) <> 'boolean'
          )
        ))
        or (v_definition.data_type in ('single_select','multi_select') and (
          v_operator not in ('eq','neq','in')
          or exists (
            select 1 from jsonb_array_elements(v_values) requested(value)
            where jsonb_typeof(requested.value) <> 'string'
              or (
                jsonb_array_length(v_definition.allowed_values) > 0
                and not exists (
                  select 1
                  from jsonb_array_elements(v_definition.allowed_values)
                    allowed(value)
                  where public.assistant_normalize_query_internal_v1(
                    allowed.value #>> '{}'
                  ) = public.assistant_normalize_query_internal_v1(
                    requested.value #>> '{}'
                  )
                )
              )
          )
        ))
        or (v_definition.data_type = 'text' and (
          v_operator not in ('eq','neq','in','contains')
          or exists (
            select 1 from jsonb_array_elements(v_values) requested(value)
            where jsonb_typeof(requested.value) <> 'string'
              or octet_length(requested.value #>> '{}') not between 1 and 120
          )
        ))
        or v_definition.data_type not in (
          'number','boolean','single_select','multi_select','text'
        ) then
        raise exception 'Invalid technical predicate type'
          using errcode = '22023';
      end if;

      if v_product_id is not null then
        v_predicate_source :=
          public.assistant_inventory_technical_predicate_source_internal_v1(
            p_tenant_id, v_product_id, v_field, v_operator, v_values,
            v_identity_surface, v_identity_raw
          );
        if v_predicate_source not in ('product_spec', 'identity_fallback') then
          raise exception 'Catalog product does not satisfy request'
            using errcode = '23514';
        end if;
      end if;
      v_predicate_fields := array_append(v_predicate_fields, v_field);
    end loop;

    v_line_refs := array_append(v_line_refs, v_line_ref);
    v_normalized := v_normalized || jsonb_build_array(jsonb_build_object(
      'lineRef', v_line_ref,
      'description', v_description,
      'productId', v_product_id,
      'productName', v_product_name,
      'productSku', v_product_sku,
      'identityState', case when v_product_id is null then 'unresolved'
        else 'confirmed' end,
      'quantity', v_quantity,
      'unit', v_unit,
      'technicalPredicates', v_item -> 'technicalPredicates',
      'preference', v_preference,
      'clarification', v_clarification,
      'clarificationRequired',
        (v_item ->> 'clarificationRequired')::boolean
    ));
  end loop;

  return v_normalized;
end;
$$;

revoke all on function public.normalize_supply_request_items_internal_v1(
  uuid, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.assistant_prepare_supply_request_v1(
  p_items jsonb,
  p_profile text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_inventory_authority record;
  v_normalized jsonb;
  v_items jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;

  select authority.tenant_id, authority.actor_user_id
  into strict v_inventory_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if v_inventory_authority.tenant_id <> v_authority.tenant_id
     or v_inventory_authority.actor_user_id <> v_authority.actor_user_id then
    raise exception 'Assistant authority changed during supply interpretation'
      using errcode = '42501';
  end if;
  if p_profile not in ('balanced', 'profitability', 'urgent_local') then
    raise exception 'Invalid supply request profile' using errcode = '22023';
  end if;

  v_normalized := public.normalize_supply_request_items_internal_v1(
    v_authority.tenant_id,
    p_items
  );

  select jsonb_agg(
    (item.value - 'productId') || jsonb_build_object(
      'entityId', item.value -> 'productId',
      'profile', p_profile
    )
    order by item.ordinality
  ) into v_items
  from jsonb_array_elements(v_normalized)
    with ordinality item(value, ordinality);

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    coalesce(v_items, '[]'::jsonb),
    false
  );
end;
$$;

revoke all on function public.assistant_prepare_supply_request_v1(
  jsonb, text
) from public, anon, authenticated, service_role;
grant execute on function public.assistant_prepare_supply_request_v1(
  jsonb, text
) to authenticated;

comment on function public.assistant_prepare_supply_request_v1(jsonb, text) is
  'Read-only server validation for a structured supply-request draft. Exact products must already have been resolved from opaque catalog references by the gateway runtime.';

create or replace function public.create_supply_need_batch_v1(
  p_original_request text,
  p_items jsonb,
  p_profile text,
  p_assistant_thread_id uuid,
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

  v_normalized := public.normalize_supply_request_items_internal_v1(
    v_tenant_id,
    p_items
  );
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
      identity_state, canonical_product_id, constraints, clarifications,
      evidence_snapshot, formula_version, created_by
    ) values (
      v_tenant_id, v_need.id, 1, 'ai', v_original_request,
      v_need.identity_state, v_need.product_id, v_constraints,
      v_clarifications,
      jsonb_strip_nulls(jsonb_build_object(
        'line_ref', v_item ->> 'lineRef',
        'product_name', v_item ->> 'productName',
        'product_sku', v_item ->> 'productSku',
        'assistant_thread_id', p_assistant_thread_id
      )),
      'ai-supply-request-v1', v_actor_id
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
$$;

revoke all on function public.create_supply_need_batch_v1(
  text, jsonb, text, uuid, text
) from public, anon, authenticated, service_role;
grant execute on function public.create_supply_need_batch_v1(
  text, jsonb, text, uuid, text
) to authenticated;

comment on function public.create_supply_need_batch_v1(
  text, jsonb, text, uuid, text
) is
  'Atomically creates one to eight reviewed ad-hoc supply needs from a structured assistant draft. It records AI interpretation evidence and never assigns stock or creates purchasing/accounting documents.';

create or replace function
  assistant_runtime.assistant_tool_receipt_contract_internal_v1(
    p_tool_name text
  )
returns table(risk text, policy_decision text, max_result_count integer)
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select contract.risk, contract.policy_decision, contract.max_result_count
  from (values
    ('inspect_inventory_schema', 'read', 'allowed', 40),
    ('search_inventory', 'read', 'allowed', 10),
    ('rank_purchase_candidates', 'read', 'allowed', 10),
    ('build_purchase_scenarios', 'read', 'allowed', 3),
    ('prepare_supply_request', 'read', 'allowed', 8),
    ('list_attention_items', 'read', 'allowed', 10),
    ('get_business_snapshot', 'read', 'allowed', 10),
    ('search_workshop_jobs', 'read', 'allowed', 10),
    ('get_workshop_job_context', 'read', 'allowed', 10),
    ('inspect_diagnosis_schema', 'read', 'allowed', 40),
    ('search_tasks', 'read', 'allowed', 10),
    ('search_customers', 'read', 'allowed', 10),
    ('search_suppliers', 'read', 'allowed', 10),
    ('search_sales_invoices', 'read', 'allowed', 10),
    ('search_purchase_invoices', 'read', 'allowed', 10),
    ('find_inventory_risks', 'read', 'allowed', 10),
    ('list_recent_expenses', 'read', 'allowed', 10),
    ('analyze_cash_and_receivables', 'read', 'allowed', 10),
    ('analyze_sales_period', 'read', 'allowed', 1),
    ('search_conversations', 'read', 'allowed', 10),
    ('research_public_web', 'public_research', 'allowed', 10),
    ('prepare_task', 'draft', 'approval_required', 10),
    ('prepare_diagnosis_update', 'draft', 'approval_required', 1),
    ('prepare_workshop_item', 'draft', 'approval_required', 1),
    ('report_capability_gap', 'read', 'allowed', 10)
  ) contract(tool_name, risk, policy_decision, max_result_count)
  where contract.tool_name = p_tool_name;
$$;

revoke all on function
  assistant_runtime.assistant_tool_receipt_contract_internal_v1(text)
from public, anon, authenticated, service_role;

notify pgrst, 'reload schema';

commit;
