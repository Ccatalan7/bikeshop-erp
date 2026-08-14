-- Approval-gated workshop actions. The model may only prepare a frozen
-- proposal. A direct post-click endpoint consumes it once, rechecks authority,
-- optimistic revisions and financial locks, writes atomically and read-backs.

begin;

-- Keep the durable receipt ledger in lockstep with the complete model-visible
-- registry. This central contract rejects fabricated tool names and prevents
-- a newly advertised primitive from failing only after it has already run.
create or replace function assistant_runtime.assistant_tool_receipt_contract_internal_v1(
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

alter table public.assistant_approvals
  drop constraint if exists assistant_approvals_action_name_check;
alter table public.assistant_approvals
  add constraint assistant_approvals_action_name_check
  check (action_name in ('create_task','update_diagnosis','add_workshop_item'));

create or replace function public.assistant_cards_valid_v1(p_cards jsonb)
returns boolean
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_card jsonb; v_chip jsonb; v_entity_ref jsonb; v_approval_ref jsonb;
  v_list_ref jsonb; v_list_entity_id jsonb; v_list_entity_ids text[];
  v_list_result_count integer; v_list_has_more boolean;
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
       or exists (select 1 from jsonb_object_keys(v_card) key where key not in (
         'kind','title','destination','eyebrow','subtitle','description',
         'chips','entityRef','approvalRef','listRef'
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
         or (v_kind = 'purchase_invoice' and v_destination = 'purchases')
         or (v_kind = 'inventory' and v_destination = 'inventory_products')
         or (v_kind in ('task','task_preview') and v_destination = 'tasks')
         or (v_kind = 'expense' and v_destination = 'expenses')
         or (v_kind = 'conversation' and v_destination = 'conversations')
       ) or jsonb_array_length(v_card -> 'chips') > 4 then return false; end if;
    if v_card ? 'entityRef' then
      v_entity_ref := v_card -> 'entityRef';
      if v_kind in ('task_preview','diagnosis_preview','workshop_item_preview')
         or v_card ? 'listRef'
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
      if not (v_card ? 'approvalRef') or v_card ? 'listRef' then return false; end if;
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
    for v_chip in select value from jsonb_array_elements(v_card -> 'chips') element(value)
    loop
      if jsonb_typeof(v_chip) <> 'string'
         or octet_length(v_chip #>> '{}') not between 1 and 64 then return false; end if;
    end loop;
  end loop;
  return true;
end;
$$;

create or replace function public.assistant_prepare_workshop_item_v1(
  p_job_id uuid,
  p_job_bike_id uuid,
  p_catalog_item_id uuid,
  p_quantity numeric,
  p_notes text,
  p_expected_job_updated_at text,
  p_run_id uuid,
  p_provider_attempt_no integer,
  p_provider_call_hash text,
  p_arguments_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record; v_job record; v_job_bike record; v_product record;
  v_expected_job_updated_at timestamptz; v_item_type text;
  v_line_total numeric; v_payload jsonb; v_prepared jsonb; v_bike_label text;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.write.workshop') authority;
  if p_job_id is null or p_catalog_item_id is null or p_quantity is null
     or p_quantity < 0.01 or p_quantity > 999
     or octet_length(coalesce(nullif(btrim(p_notes),''),'')) > 500
     or p_expected_job_updated_at is null
     or p_expected_job_updated_at !~
       '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.]\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  begin v_expected_job_updated_at := p_expected_job_updated_at::timestamptz;
  exception when others then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end;
  select job.id,job.job_number,job.job_type,job.updated_at,job.invoice_id,
    job.deleted_at,job.delivered_at,job.completed_at,job.status,
    status.code status_code,status.phase,status.triggers_delivery,
    invoice.invoice_number,invoice.status invoice_status,invoice.paid_amount,
    case when invoice.id is null then false else exists (
      select 1 from public.sales_payments payment
      where payment.tenant_id = invoice.tenant_id
        and payment.invoice_id = invoice.id and payment.deleted_at is null
        and payment.amount > 0
    ) end has_payment
  into v_job from public.mechanic_jobs job
  left join public.job_statuses status
    on status.id = job.status_id and status.tenant_id = job.tenant_id
  left join public.sales_invoices invoice
    on invoice.id = job.invoice_id and invoice.tenant_id = job.tenant_id
  where job.id = p_job_id and job.tenant_id = v_authority.tenant_id;
  if not found or v_job.updated_at is distinct from v_expected_job_updated_at
     or v_job.deleted_at is not null or v_job.delivered_at is not null
     or v_job.completed_at is not null or coalesce(v_job.phase,'in_progress') = 'complete'
     or coalesce(v_job.triggers_delivery,false)
     or upper(coalesce(v_job.status_code,v_job.status,'')) in (
       'CANCELADO','CANCELADA','ANULADO','ANULADA','CANCELLED','CANCELED',
       'ENTREGADO','ENTREGADA','DELIVERED','COMPLETADO','COMPLETADA',
       'FINALIZADO','FINALIZADA','COMPLETED','COMPLETE'
     ) then raise exception 'Workshop target is unavailable' using errcode = '42501'; end if;
  if v_job.invoice_id is not null and (
    lower(coalesce(v_job.invoice_status,'')) in ('paid','pagado','pagada')
    or coalesce(v_job.paid_amount,0) > 0 or v_job.has_payment
  ) then raise exception 'Workshop invoice has financial history' using errcode = '42501'; end if;
  if p_job_bike_id is not null then
    select job_bike.id,
      nullif(btrim(concat_ws(' ',bike.brand,bike.model,
        case when bike.year is null then null else bike.year::text end)),'') bike_label
    into v_job_bike from public.mechanic_job_bikes job_bike
    join public.bikes bike on bike.id = job_bike.bike_id
      and bike.tenant_id = job_bike.tenant_id
    where job_bike.id = p_job_bike_id and job_bike.job_id = p_job_id
      and job_bike.tenant_id = v_authority.tenant_id;
    if not found then raise exception 'Workshop bike is unavailable' using errcode = '42501'; end if;
    v_bike_label := coalesce(v_job_bike.bike_label,'Bicicleta');
  else v_bike_label := null; end if;
  select product.id,product.name,product.sku,product.price,product.product_type,
    product.is_service,product.is_active
  into v_product from public.products product
  where product.id = p_catalog_item_id and product.tenant_id = v_authority.tenant_id;
  if not found or v_product.is_active is not true
     or coalesce(v_product.product_type,'product') not in ('product','service')
     or v_product.price is null or v_product.price < 0 then
    raise exception 'Catalog item is unavailable' using errcode = '42501';
  end if;
  v_item_type := case when coalesce(v_product.is_service,false)
    or v_product.product_type = 'service' then 'service' else 'product' end;
  v_line_total := round(p_quantity * v_product.price,2);
  v_payload := jsonb_build_object(
    'jobId',p_job_id,'jobBikeId',p_job_bike_id,'jobNumber',v_job.job_number,
    'bikeLabel',v_bike_label,'catalogItemId',p_catalog_item_id,
    'itemName',v_product.name,'itemSku',v_product.sku,'itemType',v_item_type,
    'quantity',p_quantity,'unitPrice',v_product.price,'lineTotal',v_line_total,
    'notes',nullif(btrim(p_notes),''),'invoiceId',v_job.invoice_id,
    'invoiceNumber',v_job.invoice_number,
    'expectedJobUpdatedAt',v_expected_job_updated_at
  );
  v_prepared := public.assistant_prepare_action_internal_v1(
    'add_workshop_item',v_payload,p_run_id,p_provider_attempt_no,
    p_provider_call_hash,p_arguments_hash
  );
  return jsonb_build_object(
    'authorityTenantId',v_authority.tenant_id,'asOf',statement_timestamp(),
    'status','success','items',jsonb_build_array(jsonb_build_object(
      'approvalId',v_prepared ->> 'approvalId','action',v_prepared ->> 'action',
      'state',v_prepared ->> 'state','jobId',p_job_id,'jobBikeId',p_job_bike_id,
      'jobNumber',v_job.job_number,'bikeLabel',v_bike_label,
      'catalogItemId',p_catalog_item_id,'itemName',v_product.name,
      'itemType',v_item_type,'quantity',p_quantity,'unitPrice',v_product.price,
      'lineTotal',v_line_total,'invoiceNumber',v_job.invoice_number,
      'expiresAt',v_prepared ->> 'expiresAt'
    )),'resultCount',1,'hasMore',false
  );
end;
$$;

create or replace function public.assistant_apply_approval_v2(
  p_approval_id uuid,
  p_action text,
  p_client_action_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record; v_action_name text; v_legacy jsonb; v_approval record;
  v_run record; v_payload jsonb; v_response jsonb; v_result jsonb;
  v_final_state text; v_now timestamptz := statement_timestamp();
  v_job record; v_job_bike record; v_product record; v_invoice record;
  v_sheet jsonb; v_section jsonb; v_job_item_id uuid; v_affected_id uuid;
  v_receipt_id uuid; v_receipt_ordinal integer; v_action_call_hash text;
  v_output_hash text;
begin
  select authority.tenant_id,authority.actor_user_id,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_current_authority_internal_v1() authority;
  if p_approval_id is null or p_client_action_id is null
     or p_action not in ('approve','discard') then
    raise exception 'Invalid approval action' using errcode = '22023';
  end if;
  select approval.action_name into v_action_name
  from public.assistant_approvals approval
  where approval.id = p_approval_id and approval.tenant_id = v_authority.tenant_id
    and approval.actor_user_id = v_authority.actor_user_id
    and approval.authority_fingerprint = v_authority.authority_fingerprint;
  if not found then raise exception 'Approval is unavailable' using errcode = '42501'; end if;
  if v_action_name = 'create_task' then
    v_legacy := public.assistant_apply_task_approval_v1(
      p_approval_id,p_action,p_client_action_id
    );
    return jsonb_build_object(
      'authorityTenantId',v_legacy -> 'authorityTenantId',
      'actorUserId',v_legacy -> 'actorUserId','approvalId',v_legacy -> 'approvalId',
      'clientActionId',v_legacy -> 'clientActionId',
      'approvalState',v_legacy -> 'approvalState','action','create_task',
      'result',v_legacy -> 'task'
    );
  end if;
  if v_action_name not in ('update_diagnosis','add_workshop_item') then
    raise exception 'Approval is unavailable' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:approval-action:' || v_authority.actor_user_id::text || ':'
      || p_client_action_id::text,0
  ));
  if exists (select 1 from public.assistant_approvals other
    where other.tenant_id = v_authority.tenant_id
      and other.actor_user_id = v_authority.actor_user_id
      and other.client_action_id = p_client_action_id and other.id <> p_approval_id
  ) then raise exception 'Approval action id was already used' using errcode = '22023'; end if;
  select approval.id, approval.run_id, approval.provider_attempt_id,
    approval.arguments_hash, approval.authority_fingerprint,
    approval.action_name, approval.action_payload, approval.state,
    approval.expires_at, approval.client_action_id, approval.decision,
    approval.decision_response
  into v_approval from public.assistant_approvals approval
  where approval.id = p_approval_id and approval.tenant_id = v_authority.tenant_id
    and approval.actor_user_id = v_authority.actor_user_id
  for update;
  if not found or v_approval.authority_fingerprint <>
      v_authority.authority_fingerprint then
    raise exception 'Approval is unavailable' using errcode = '42501';
  end if;
  if v_approval.state <> 'pending' then
    if v_approval.client_action_id = p_client_action_id
       and v_approval.decision = p_action
       and v_approval.decision_response is not null then
      return v_approval.decision_response;
    end if;
    raise exception 'Approval was already consumed' using errcode = '22023';
  end if;
  select run.id,run.status into v_run from public.assistant_runs run
  where run.id = v_approval.run_id and run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.authority_fingerprint = v_authority.authority_fingerprint
  for update;
  if not found or v_run.status <> 'succeeded' then
    raise exception 'Approval run is unavailable' using errcode = '42501';
  end if;
  if v_approval.expires_at <= v_now then v_final_state := 'expired';
  elsif p_action = 'discard' then v_final_state := 'discarded';
  else v_final_state := 'approved'; end if;
  if v_final_state <> 'approved' then
    v_response := jsonb_build_object(
      'authorityTenantId',v_authority.tenant_id,'actorUserId',v_authority.actor_user_id,
      'approvalId',v_approval.id,'clientActionId',p_client_action_id,
      'approvalState',v_final_state,'action',v_approval.action_name,'result',null
    );
    update public.assistant_approvals set state=v_final_state,
      client_action_id=p_client_action_id,decision=p_action,
      decision_response=v_response,decided_at=v_now,updated_at=v_now
    where id=v_approval.id;
  else
    v_payload := v_approval.action_payload;
    if jsonb_typeof(v_payload) <> 'object' then
      raise exception 'Approval payload is invalid' using errcode = '22023';
    end if;
    if v_approval.action_name = 'update_diagnosis' then
      if exists (select 1 from jsonb_object_keys(v_payload) key where key not in (
        'jobId','jobBikeId','jobNumber','bikeLabel','section','jsonKey','field',
        'fieldLabel','storedValue','previousValue','previousDisplay','newDisplay',
        'expectedUpdatedAt'
      )) then raise exception 'Approval payload is invalid' using errcode = '22023'; end if;
      select job.id,job.job_number,job.deleted_at,job.delivered_at,job.completed_at,
        job.status,status.code status_code,status.phase,status.triggers_delivery
      into v_job from public.mechanic_jobs job
      left join public.job_statuses status
        on status.id=job.status_id and status.tenant_id=job.tenant_id
      where job.id=(v_payload ->> 'jobId')::uuid
        and job.tenant_id=v_authority.tenant_id for update of job;
      if not found or v_job.job_number <> v_payload ->> 'jobNumber'
         or v_job.deleted_at is not null or v_job.delivered_at is not null
         or v_job.completed_at is not null or coalesce(v_job.phase,'in_progress')='complete'
         or coalesce(v_job.triggers_delivery,false)
         or upper(coalesce(v_job.status_code,v_job.status,'')) in (
           'CANCELADO','CANCELADA','ANULADO','ANULADA','CANCELLED','CANCELED',
           'ENTREGADO','ENTREGADA','DELIVERED','COMPLETADO','COMPLETADA',
           'FINALIZADO','FINALIZADA','COMPLETED','COMPLETE'
         ) then raise exception 'Workshop target is unavailable' using errcode='42501'; end if;
      select job_bike.id,job_bike.diagnosis_sheet_data,
        job_bike.diagnosis_sheet_updated_at
      into v_job_bike from public.mechanic_job_bikes job_bike
      where job_bike.id=(v_payload ->> 'jobBikeId')::uuid
        and job_bike.job_id=v_job.id and job_bike.tenant_id=v_authority.tenant_id
      for update;
      if not found or v_job_bike.diagnosis_sheet_updated_at is distinct from
          nullif(v_payload ->> 'expectedUpdatedAt','')::timestamptz
         or coalesce(
           coalesce(v_job_bike.diagnosis_sheet_data,'{}'::jsonb)
             #> array[v_payload ->> 'section',v_payload ->> 'jsonKey'],
           'null'::jsonb
         ) is distinct from v_payload -> 'previousValue' then
        raise exception 'Workshop diagnosis revision changed' using errcode='22023';
      end if;
      if not exists (select 1
        from public.assistant_diagnosis_field_registry_internal_v1() registry
        where registry.section_key=v_payload ->> 'section'
          and registry.json_key=v_payload ->> 'jsonKey'
          and registry.label=v_payload ->> 'fieldLabel'
      ) then raise exception 'Approval payload is invalid' using errcode='22023'; end if;
      v_sheet := case when jsonb_typeof(v_job_bike.diagnosis_sheet_data)='object'
        then v_job_bike.diagnosis_sheet_data else '{}'::jsonb end;
      v_section := case when jsonb_typeof(v_sheet -> (v_payload ->> 'section'))='object'
        then v_sheet -> (v_payload ->> 'section') else '{}'::jsonb end;
      v_section := jsonb_set(v_section,array[v_payload ->> 'jsonKey'],
        v_payload -> 'storedValue',true);
      v_sheet := jsonb_set(v_sheet,array[v_payload ->> 'section'],v_section,true);
      update public.mechanic_job_bikes set diagnosis_sheet_data=v_sheet,
        diagnosis_sheet_key=coalesce(diagnosis_sheet_key,'basic_workshop_v1'),
        diagnosis_sheet_updated_at=v_now,updated_at=v_now
      where id=v_job_bike.id;
      select jsonb_build_object(
        'entityId',v_job.id,'jobBikeId',job_bike.id,'jobNumber',v_job.job_number,
        'bikeLabel',v_payload ->> 'bikeLabel','field',v_payload ->> 'field',
        'fieldLabel',v_payload ->> 'fieldLabel','newValue',v_payload ->> 'newDisplay',
        'updatedAt',to_char(job_bike.diagnosis_sheet_updated_at at time zone 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ) into strict v_result from public.mechanic_job_bikes job_bike
      where job_bike.id=v_job_bike.id and job_bike.tenant_id=v_authority.tenant_id
        and job_bike.diagnosis_sheet_data #>
          array[v_payload ->> 'section',v_payload ->> 'jsonKey']
          = v_payload -> 'storedValue';
      v_affected_id := v_job_bike.id;
    else
      if exists (select 1 from jsonb_object_keys(v_payload) key where key not in (
        'jobId','jobBikeId','jobNumber','bikeLabel','catalogItemId','itemName',
        'itemSku','itemType','quantity','unitPrice','lineTotal','notes','invoiceId',
        'invoiceNumber','expectedJobUpdatedAt'
      )) then raise exception 'Approval payload is invalid' using errcode='22023'; end if;
      -- Respect the workshop global lock order: linked invoice, then job.
      if v_payload -> 'invoiceId' <> 'null'::jsonb then
        select invoice.id, invoice.invoice_number, invoice.status,
          invoice.paid_amount
        into v_invoice from public.sales_invoices invoice
        where invoice.id=(v_payload ->> 'invoiceId')::uuid
          and invoice.tenant_id=v_authority.tenant_id for update;
        if not found or v_invoice.invoice_number <> v_payload ->> 'invoiceNumber'
           or lower(coalesce(v_invoice.status,'')) in ('paid','pagado','pagada')
           or coalesce(v_invoice.paid_amount,0)>0
           or exists (select 1 from public.sales_payments payment
             where payment.tenant_id=v_authority.tenant_id
               and payment.invoice_id=v_invoice.id and payment.deleted_at is null
               and payment.amount>0)
          then raise exception 'Workshop invoice has financial history' using errcode='42501'; end if;
      end if;
      select job.id,job.job_number,job.updated_at,job.invoice_id,job.deleted_at,
        job.delivered_at,job.completed_at,job.status,status.code status_code,
        status.phase,status.triggers_delivery
      into v_job from public.mechanic_jobs job
      left join public.job_statuses status
        on status.id=job.status_id and status.tenant_id=job.tenant_id
      where job.id=(v_payload ->> 'jobId')::uuid
        and job.tenant_id=v_authority.tenant_id for update of job;
      if not found or v_job.job_number <> v_payload ->> 'jobNumber'
         or v_job.updated_at is distinct from
           (v_payload ->> 'expectedJobUpdatedAt')::timestamptz
         or v_job.invoice_id is distinct from nullif(v_payload ->> 'invoiceId','')::uuid
         or v_job.deleted_at is not null or v_job.delivered_at is not null
         or v_job.completed_at is not null or coalesce(v_job.phase,'in_progress')='complete'
         or coalesce(v_job.triggers_delivery,false)
         or upper(coalesce(v_job.status_code,v_job.status,'')) in (
           'CANCELADO','CANCELADA','ANULADO','ANULADA','CANCELLED','CANCELED',
           'ENTREGADO','ENTREGADA','DELIVERED','COMPLETADO','COMPLETADA',
           'FINALIZADO','FINALIZADA','COMPLETED','COMPLETE'
         ) then raise exception 'Workshop target is unavailable' using errcode='42501'; end if;
      if v_payload -> 'jobBikeId' <> 'null'::jsonb and not exists (
        select 1 from public.mechanic_job_bikes job_bike
        where job_bike.id=(v_payload ->> 'jobBikeId')::uuid
          and job_bike.job_id=v_job.id and job_bike.tenant_id=v_authority.tenant_id
      ) then raise exception 'Workshop bike is unavailable' using errcode='42501'; end if;
      select product.id,product.name,product.sku,product.price,
        case when coalesce(product.is_service,false)
          or product.product_type='service' then 'service' else 'product' end item_type
      into v_product from public.products product
      where product.id=(v_payload ->> 'catalogItemId')::uuid
        and product.tenant_id=v_authority.tenant_id and product.is_active is true
      for share;
      if not found or v_product.name <> v_payload ->> 'itemName'
         or v_product.sku is distinct from nullif(v_payload ->> 'itemSku','')
         or v_product.item_type <> v_payload ->> 'itemType'
         or v_product.price <> (v_payload ->> 'unitPrice')::numeric
         or round((v_payload ->> 'quantity')::numeric * v_product.price,2)
           <> (v_payload ->> 'lineTotal')::numeric then
        raise exception 'Catalog item changed' using errcode='22023';
      end if;
      insert into public.mechanic_job_items (
        tenant_id,job_id,job_bike_id,product_id,service_product_id,
        product_name,product_sku,quantity,unit_price,total_price,notes,
        description,item_type,created_at,updated_at
      ) values (
        v_authority.tenant_id,v_job.id,nullif(v_payload ->> 'jobBikeId','')::uuid,
        case when v_product.item_type='product' then v_product.id else null end,
        case when v_product.item_type='service' then v_product.id else null end,
        v_product.name,v_product.sku,(v_payload ->> 'quantity')::numeric,
        v_product.price,(v_payload ->> 'lineTotal')::numeric,
        v_payload ->> 'notes',v_payload ->> 'notes',v_product.item_type,v_now,v_now
      ) returning id into v_job_item_id;
      if v_job.invoice_id is not null then perform public.sync_job_to_invoice(v_job.id); end if;
      select jsonb_build_object(
        'entityId',v_job.id,'jobItemId',item.id,'jobBikeId',item.job_bike_id,
        'jobNumber',v_job.job_number,'bikeLabel',v_payload -> 'bikeLabel',
        'itemName',item.product_name,'itemType',item.item_type,
        'quantity',item.quantity,'unitPrice',item.unit_price,
        'lineTotal',item.total_price,'invoiceNumber',v_payload -> 'invoiceNumber'
      ) into strict v_result from public.mechanic_job_items item
      where item.id=v_job_item_id and item.tenant_id=v_authority.tenant_id
        and item.job_id=v_job.id and item.total_price=(v_payload ->> 'lineTotal')::numeric;
      v_affected_id := v_job_item_id;
    end if;
    v_response := jsonb_build_object(
      'authorityTenantId',v_authority.tenant_id,'actorUserId',v_authority.actor_user_id,
      'approvalId',v_approval.id,'clientActionId',p_client_action_id,
      'approvalState','approved','action',v_approval.action_name,'result',v_result
    );
    v_action_call_hash := encode(extensions.digest(convert_to(
      'assistant:approval-action:' || p_client_action_id::text,'UTF8'
    ),'sha256'),'hex');
    v_output_hash := encode(extensions.digest(convert_to(v_result::text,'UTF8'),
      'sha256'),'hex');
    select coalesce(max(receipt.ordinal),0)+1 into v_receipt_ordinal
    from public.assistant_tool_receipts receipt where receipt.run_id=v_run.id;
    insert into public.assistant_tool_receipts (
      tenant_id,actor_user_id,run_id,provider_attempt_id,ordinal,
      provider_call_hash,tool_name,tool_version,risk,policy_decision,status,
      arguments_hash,output_hash,result_count,output_bytes,approval_used,
      read_back_verified,failure_code,started_at,completed_at
    ) values (
      v_authority.tenant_id,v_authority.actor_user_id,v_run.id,
      v_approval.provider_attempt_id,v_receipt_ordinal,v_action_call_hash,
      v_approval.action_name,'v1','reversible_write','allowed','succeeded',
      v_approval.arguments_hash,v_output_hash,1,octet_length(v_response::text),
      true,true,null,v_now,v_now
    ) returning id into v_receipt_id;
    update public.assistant_approvals set state='approved',
      client_action_id=p_client_action_id,decision=p_action,
      decision_response=v_response,created_entity_id=v_affected_id,
      action_receipt_id=v_receipt_id,decided_at=v_now,updated_at=v_now
    where id=v_approval.id;
  end if;
  update public.assistant_messages message set cards=coalesce((
    select jsonb_agg(case when card.value #>> '{approvalRef,id}'=v_approval.id::text
      then jsonb_set(card.value,'{approvalRef,state}',to_jsonb(v_final_state),false)
      else card.value end order by card.ordinality)
    from jsonb_array_elements(message.cards) with ordinality card(value,ordinality)
  ),'[]'::jsonb)
  where message.run_id=v_run.id and exists (
    select 1 from jsonb_array_elements(message.cards) card
    where card #>> '{approvalRef,id}'=v_approval.id::text
  );
  return v_response;
end;
$$;

revoke all on function public.assistant_cards_valid_v1(jsonb)
from public, anon, authenticated, service_role;

create or replace function public.assistant_prepare_action_internal_v1(
  p_action_name text,
  p_action_payload jsonb,
  p_run_id uuid,
  p_provider_attempt_no integer,
  p_provider_call_hash text,
  p_arguments_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record; v_run record; v_attempt record; v_existing record;
  v_approval record;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.write.workshop') authority;
  if p_action_name not in ('update_diagnosis','add_workshop_item')
     or jsonb_typeof(p_action_payload) <> 'object'
     or p_run_id is null or p_provider_attempt_no not between 1 and 42
     or coalesce(p_provider_call_hash,'') !~ '^[0-9a-f]{64}$'
     or coalesce(p_arguments_hash,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  select run.id, run.tenant_id, run.actor_user_id, run.thread_id
  into v_run from public.assistant_runs run
  where run.id = p_run_id and run.tenant_id = v_authority.tenant_id
    and run.actor_user_id = v_authority.actor_user_id
    and run.authority_fingerprint = v_authority.authority_fingerprint
    and run.status in ('running','waiting_tool')
    and run.expires_at > statement_timestamp();
  if not found then raise exception 'Assistant run is unavailable' using errcode = '42501'; end if;
  select attempt.id into v_attempt from public.assistant_provider_attempts attempt
  where attempt.run_id = v_run.id and attempt.attempt_no = p_provider_attempt_no
    and attempt.status = 'succeeded' and attempt.finish_reason = 'tool_calls';
  if not found then
    raise exception 'Assistant provider attempt is unavailable' using errcode = '42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'assistant:prepare-action:' || v_run.id::text || ':' || p_provider_call_hash, 0
  ));
  select approval.id, approval.arguments_hash, approval.authority_fingerprint,
    approval.action_name, approval.action_payload, approval.state,
    approval.expires_at
  into v_existing from public.assistant_approvals approval
  where approval.run_id = v_run.id and approval.provider_call_hash = p_provider_call_hash
  for update;
  if found then
    if v_existing.arguments_hash <> p_arguments_hash
       or v_existing.action_name <> p_action_name
       or v_existing.action_payload <> p_action_payload
       or v_existing.authority_fingerprint <> v_authority.authority_fingerprint then
      raise exception 'AI preparation idempotency conflict' using errcode = '22023';
    end if;
    v_approval := v_existing;
  else
    insert into public.assistant_approvals (
      tenant_id,actor_user_id,thread_id,run_id,provider_attempt_id,
      provider_call_hash,arguments_hash,authority_fingerprint,
      action_name,action_payload,created_at,expires_at
    ) values (
      v_run.tenant_id,v_run.actor_user_id,v_run.thread_id,v_run.id,v_attempt.id,
      p_provider_call_hash,p_arguments_hash,v_authority.authority_fingerprint,
      p_action_name,p_action_payload,statement_timestamp(),
      statement_timestamp() + interval '10 minutes'
    ) returning id, action_name, state, expires_at into v_approval;
  end if;
  return jsonb_build_object(
    'authorityTenantId',v_authority.tenant_id,
    'approvalId',v_approval.id,'action',v_approval.action_name,
    'state',v_approval.state,
    'expiresAt',to_char(v_approval.expires_at at time zone 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  );
end;
$$;

revoke all on function public.assistant_prepare_action_internal_v1(
  text,jsonb,uuid,integer,text,text
) from public, anon, authenticated, service_role;

create or replace function public.assistant_prepare_diagnosis_update_v1(
  p_job_id uuid,
  p_job_bike_id uuid,
  p_field text,
  p_number_value numeric,
  p_text_value text,
  p_unit text,
  p_expected_updated_at text,
  p_run_id uuid,
  p_provider_attempt_no integer,
  p_provider_call_hash text,
  p_arguments_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth, extensions, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record; v_registry record; v_job record; v_job_bike record;
  v_expected_updated_at timestamptz; v_stored_value jsonb; v_previous jsonb;
  v_previous_display text; v_new_display text; v_payload jsonb; v_prepared jsonb;
  v_section text; v_json_key text; v_bike_label text;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.write.workshop') authority;
  if p_job_id is null or p_job_bike_id is null
     or p_field !~ '^[a-z][a-z0-9_]*\.[a-z][a-z0-9_]*$'
     or ((p_number_value is null) = (nullif(btrim(p_text_value),'') is null))
     or p_unit not in ('none','display_fraction','percent','millimeter')
     or octet_length(coalesce(nullif(btrim(p_text_value),''),'')) > 1000 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_section := split_part(p_field,'.',1); v_json_key := split_part(p_field,'.',2);
  select registry.label, registry.value_type, registry.stored_unit,
    registry.input_units, registry.allowed_values, registry.minimum_value,
    registry.maximum_value
  into v_registry
  from public.assistant_diagnosis_field_registry_internal_v1() registry
  where registry.section_key = v_section and registry.json_key = v_json_key;
  if not found then raise exception 'Invalid AI tool arguments' using errcode = '22023'; end if;
  if v_registry.value_type = 'number' then
    if p_number_value is null or p_text_value is not null
       or not (p_unit = any(string_to_array(v_registry.input_units, ','))) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_stored_value := to_jsonb(case when p_unit = 'display_fraction'
      then p_number_value * 100 else p_number_value end);
    if (v_stored_value #>> '{}')::numeric < v_registry.minimum_value
       or (v_stored_value #>> '{}')::numeric > v_registry.maximum_value then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_new_display := case p_unit when 'display_fraction' then
      trim(to_char(p_number_value,'FM0.00')) when 'percent' then
      trim(to_char(p_number_value,'FM999999990.##')) || '%'
      else trim(to_char(p_number_value,'FM999999990.##')) || ' mm' end;
  else
    if p_number_value is not null or p_unit <> 'none'
       or nullif(btrim(p_text_value),'') is null then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    if v_registry.allowed_values is not null and not (
      btrim(p_text_value) = any(string_to_array(v_registry.allowed_values, ','))
    ) then raise exception 'Invalid AI tool arguments' using errcode = '22023'; end if;
    v_stored_value := to_jsonb(btrim(p_text_value)); v_new_display := btrim(p_text_value);
  end if;
  if p_expected_updated_at is not null then
    if p_expected_updated_at !~
      '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}([.]\d{1,6})?(Z|[+-]\d{2}:\d{2})$' then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    begin v_expected_updated_at := p_expected_updated_at::timestamptz;
    exception when others then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end;
  end if;
  select job.id,job.job_number,job.deleted_at,job.delivered_at,job.completed_at,
    job.status,status.code status_code,status.phase,status.triggers_delivery
  into v_job from public.mechanic_jobs job
  left join public.job_statuses status
    on status.id = job.status_id and status.tenant_id = job.tenant_id
  where job.id = p_job_id and job.tenant_id = v_authority.tenant_id;
  if not found or v_job.deleted_at is not null or v_job.delivered_at is not null
     or v_job.completed_at is not null or coalesce(v_job.phase,'in_progress') = 'complete'
     or coalesce(v_job.triggers_delivery,false)
     or upper(coalesce(v_job.status_code,v_job.status,'')) in (
       'CANCELADO','CANCELADA','ANULADO','ANULADA','CANCELLED','CANCELED',
       'ENTREGADO','ENTREGADA','DELIVERED','COMPLETADO','COMPLETADA',
       'FINALIZADO','FINALIZADA','COMPLETED','COMPLETE'
     ) then raise exception 'Workshop target is unavailable' using errcode = '42501'; end if;
  select job_bike.id,job_bike.diagnosis_sheet_data,
    job_bike.diagnosis_sheet_updated_at,
    nullif(btrim(concat_ws(' ',bike.brand,bike.model,
      case when bike.year is null then null else bike.year::text end)),'') bike_label
  into v_job_bike from public.mechanic_job_bikes job_bike
  join public.bikes bike on bike.id = job_bike.bike_id
    and bike.tenant_id = job_bike.tenant_id
  where job_bike.id = p_job_bike_id and job_bike.job_id = p_job_id
    and job_bike.tenant_id = v_authority.tenant_id;
  if not found or v_job_bike.diagnosis_sheet_updated_at
       is distinct from v_expected_updated_at then
    raise exception 'Workshop diagnosis revision changed' using errcode = '22023';
  end if;
  v_bike_label := coalesce(v_job_bike.bike_label,'Bicicleta');
  v_previous := coalesce(v_job_bike.diagnosis_sheet_data,'{}'::jsonb)
    #> array[v_section,v_json_key];
  if v_previous is null or v_previous = 'null'::jsonb then
    v_previous_display := null;
  elsif v_registry.value_type = 'number' and v_registry.stored_unit = 'percent' then
    v_previous_display := trim(to_char((v_previous #>> '{}')::numeric / 100,'FM0.00'));
  elsif v_registry.value_type = 'number' then
    v_previous_display := trim(to_char((v_previous #>> '{}')::numeric,'FM999999990.##'))
      || case when v_registry.stored_unit = 'millimeter' then ' mm' else '' end;
  else v_previous_display := v_previous #>> '{}'; end if;
  v_payload := jsonb_build_object(
    'jobId',p_job_id,'jobBikeId',p_job_bike_id,'jobNumber',v_job.job_number,
    'bikeLabel',v_bike_label,'section',v_section,'jsonKey',v_json_key,
    'field',p_field,'fieldLabel',v_registry.label,'storedValue',v_stored_value,
    'previousValue',v_previous,'previousDisplay',v_previous_display,
    'newDisplay',v_new_display,'expectedUpdatedAt',v_expected_updated_at
  );
  v_prepared := public.assistant_prepare_action_internal_v1(
    'update_diagnosis',v_payload,p_run_id,p_provider_attempt_no,
    p_provider_call_hash,p_arguments_hash
  );
  return jsonb_build_object(
    'authorityTenantId',v_authority.tenant_id,'asOf',statement_timestamp(),
    'status','success','items',jsonb_build_array(jsonb_build_object(
      'approvalId',v_prepared ->> 'approvalId','action',v_prepared ->> 'action',
      'state',v_prepared ->> 'state','jobId',p_job_id,'jobBikeId',p_job_bike_id,
      'jobNumber',v_job.job_number,'bikeLabel',v_bike_label,'field',p_field,
      'fieldLabel',v_registry.label,'previousValue',v_previous_display,
      'newValue',v_new_display,'expiresAt',v_prepared ->> 'expiresAt'
    )),'resultCount',1,'hasMore',false
  );
end;
$$;

revoke all on function public.assistant_prepare_diagnosis_update_v1(
  uuid,uuid,text,numeric,text,text,text,uuid,integer,text,text
) from public, anon, authenticated, service_role;
revoke all on function public.assistant_prepare_workshop_item_v1(
  uuid,uuid,uuid,numeric,text,text,uuid,integer,text,text
) from public, anon, authenticated, service_role;
revoke all on function public.assistant_apply_approval_v2(uuid,text,uuid)
from public, anon, authenticated, service_role;

grant execute on function public.assistant_prepare_diagnosis_update_v1(
  uuid,uuid,text,numeric,text,text,text,uuid,integer,text,text
) to authenticated;
grant execute on function public.assistant_prepare_workshop_item_v1(
  uuid,uuid,uuid,numeric,text,text,uuid,integer,text,text
) to authenticated;
grant execute on function public.assistant_apply_approval_v2(uuid,text,uuid)
to authenticated;

comment on function public.assistant_prepare_diagnosis_update_v1(
  uuid,uuid,text,numeric,text,text,text,uuid,integer,text,text
) is 'Prepares one registry-backed diagnosis scalar update with an optimistic revision; never writes during the model turn.';
comment on function public.assistant_prepare_workshop_item_v1(
  uuid,uuid,uuid,numeric,text,text,uuid,integer,text,text
) is 'Prepares one server-priced catalog line for an exact mutable workshop job; never writes during the model turn.';
comment on function public.assistant_apply_approval_v2(uuid,text,uuid) is
  'Consumes task or workshop approvals once. Workshop actions recheck authority, revisions, financial locks and exact read-back before success.';
comment on function public.assistant_cards_valid_v1(jsonb) is
  'Closed durable assistant-card validator for entity, inventory-list and typed approval previews.';

commit;
