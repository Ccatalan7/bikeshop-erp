-- Closed, tenant-bound read projections for the eight currently advertised
-- ERP assistant tools plus the non-model workshop view-context reread.

begin;

create or replace function public.assistant_require_capability_internal_v1(
  p_capability text
)
returns table (
  tenant_id uuid,
  actor_user_id uuid,
  authority_role text,
  permissions jsonb,
  capabilities jsonb,
  authority_fingerprint text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  return query
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  from public.assistant_current_authority_internal_v1() authority
  where authority.capabilities ? p_capability;
  if not found then
    raise exception 'AI tool is not available' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assistant_require_capability_internal_v1(text)
from public, anon, authenticated, service_role;

create or replace function public.assistant_tool_envelope_internal_v1(
  p_tenant_id uuid,
  p_items jsonb,
  p_has_more boolean
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, pg_temp
as $$
  select jsonb_build_object(
    'authorityTenantId', p_tenant_id,
    'asOf', statement_timestamp(),
    'status', case when jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0
      then 'verifiedEmpty' else 'success' end,
    'items', coalesce(p_items, '[]'::jsonb),
    'resultCount', jsonb_array_length(coalesce(p_items, '[]'::jsonb)),
    'hasMore', coalesce(p_has_more, false)
  )
$$;

revoke all on function public.assistant_tool_envelope_internal_v1(uuid, jsonb, boolean)
from public, anon, authenticated, service_role;

create or replace function public.assistant_normalize_query_internal_v1(p_query text)
returns text
language sql
stable
set search_path = pg_catalog, public, pg_temp
as $$
  select btrim(regexp_replace(
    unaccent(lower(btrim(coalesce(p_query, '')))), '[^a-z0-9]+', ' ', 'g'
  ))
$$;

revoke all on function public.assistant_normalize_query_internal_v1(text)
from public, anon, authenticated, service_role;

create or replace function public.assistant_truncate_utf8_internal_v1(
  p_value text,
  p_max_bytes integer
)
returns text
language plpgsql
immutable
set search_path = pg_catalog, pg_temp
as $$
declare
  v_limit integer := p_max_bytes;
begin
  if p_value is null then return null; end if;
  if p_max_bytes is null or p_max_bytes < 0 then
    raise exception 'Invalid UTF-8 projection bound' using errcode = '22023';
  end if;
  if octet_length(p_value) <= p_max_bytes then return p_value; end if;
  while v_limit > 0 loop
    begin
      return convert_from(substring(convert_to(p_value, 'UTF8') from 1 for v_limit), 'UTF8');
    exception when character_not_in_repertoire or untranslatable_character then
      v_limit := v_limit - 1;
    end;
  end loop;
  return '';
end;
$$;

revoke all on function public.assistant_truncate_utf8_internal_v1(text, integer)
from public, anon, authenticated, service_role;

create or replace function public.assistant_search_inventory_v1(p_query text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_query text;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if octet_length(coalesce(p_query, '')) not between 1 and 240 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  with matched as materialized (
    select product.id entity_id, product.name, product.sku, product.brand, product.category_name,
      product.category, product.price, product.warehouse_location,
      product.updated_at,
      case when coalesce(product.is_set, false)
        then coalesce(product.full_sets_available, 0)
        else coalesce(product.stock_quantity, product.inventory_qty, 0)
      end as available_stock
    from public.products_with_sets product
    where product.tenant_id = v_authority.tenant_id
      and product.is_active is true
      and not exists (
        select 1
        from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', product.name, product.sku, product.barcode,
            product.brand, product.model, product.manufacturer,
            product.category_name, product.category, product.description)
        )) = 0
      )
    order by
      (public.assistant_normalize_query_internal_v1(product.sku) = v_query) desc,
      (position(v_query in public.assistant_normalize_query_internal_v1(product.name)) > 0) desc,
      product.updated_at desc nulls last, product.name
    limit 11
  ), numbered as (
    select entity_id, name, sku, brand, category_name, category, price,
      warehouse_location, available_stock,
      row_number() over (
        order by
          (public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
          (position(v_query in public.assistant_normalize_query_internal_v1(name)) > 0) desc,
          updated_at desc nulls last, name
      ) ordinal
    from matched
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160),
      'sku', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(sku, ''), 80), ''),
      'brand', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(brand, ''), 100), ''),
      'category', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(category_name, category, ''), 100), ''),
      'price', price,
      'stock', available_stock,
      'location', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(warehouse_location, ''), 120), '')
    ) order by ordinal) filter (where ordinal <= 10), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > 10
  );
end;
$$;

create or replace function public.assistant_list_attention_items_v1(p_horizon text)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare
  v_authority record;
  v_target_date date;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if p_horizon is null or p_horizon not in ('today', 'tomorrow') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_target_date := public.tenant_business_date(v_authority.tenant_id)
    + case when p_horizon = 'tomorrow' then 1 else 0 end;

  with candidates as materialized (
    select
      'workshop'::text source,
      case when public.tenant_business_date(job.tenant_id, job.deadline) < v_target_date
        then 'overdue' else 'due' end reason,
      public.assistant_truncate_utf8_internal_v1(
        concat(job.job_number, ' · ', customer.name), 160
      ) title,
      nullif(public.assistant_truncate_utf8_internal_v1(coalesce(job.client_request, ''), 500), '') detail,
      case upper(coalesce(job.priority, 'NORMAL'))
        when 'URGENTE' then 0 when 'ALTA' then 1 when 'NORMAL' then 2 else 3 end priority_rank,
      job.deadline due_at
    from public.mechanic_jobs job
    join public.customers customer
      on customer.id = job.customer_id and customer.tenant_id = job.tenant_id
    left join public.job_statuses status
      on status.id = job.status_id and status.tenant_id = job.tenant_id
    where job.tenant_id = v_authority.tenant_id
      and job.deleted_at is null
      and job.deadline is not null
      and public.tenant_business_date(job.tenant_id, job.deadline) <= v_target_date
      and job.delivered_at is null
      and job.completed_at is null
      and upper(coalesce(job.status, '')) not in (
        'COMPLETADO', 'COMPLETADA', 'FINALIZADO', 'FINALIZADA',
        'ENTREGADO', 'ENTREGADA', 'CANCELADO', 'CANCELADA',
        'COMPLETED', 'COMPLETE', 'DELIVERED', 'CANCELLED', 'CANCELED'
      )
      and coalesce(status.phase, 'in_progress') <> 'complete'
      and coalesce(status.triggers_delivery, false) is false
    union all
    select
      'task'::text source,
      case when public.tenant_business_date(task.tenant_id, task.due_date) < v_target_date
        then 'overdue' else 'due' end reason,
      public.assistant_truncate_utf8_internal_v1(task.title, 160) title,
      nullif(public.assistant_truncate_utf8_internal_v1(coalesce(task.description, ''), 500), '') detail,
      case lower(coalesce(task.priority, 'normal'))
        when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end priority_rank,
      task.due_date due_at
    from public.smart_tasks task
    where task.tenant_id = v_authority.tenant_id
      and task.status not in ('completed', 'cancelled')
      and task.due_date is not null
      and public.tenant_business_date(task.tenant_id, task.due_date) <= v_target_date
    order by priority_rank, due_at, title
    limit 7
  ), numbered as (
    select source, reason, title, detail, priority_rank, due_at,
      row_number() over (
      order by priority_rank, due_at, title
    ) ordinal from candidates
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'source', source,
      'reason', reason,
      'title', title,
      'detail', detail,
      'priorityRank', priority_rank,
      'dueAt', due_at
    ) order by ordinal) filter (where ordinal <= 6), '[]'::jsonb),
    count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > 6
  );
end;
$$;

create or replace function public.assistant_search_workshop_jobs_v1(
  p_query text,
  p_limit integer default 10
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
  v_query text;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if octet_length(coalesce(p_query, '')) not between 1 and 240
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  with matched as materialized (
    select job.id entity_id, job.job_number, job.priority, job.arrival_date, job.deadline,
      job.client_request, job.assigned_technician_name, job.updated_at,
      customer.name customer_name,
      coalesce(status.name, job.status) status_name
    from public.mechanic_jobs job
    join public.customers customer
      on customer.id = job.customer_id and customer.tenant_id = job.tenant_id
    left join public.bikes bike
      on bike.id = job.bike_id and bike.tenant_id = job.tenant_id
    left join public.job_statuses status
      on status.id = job.status_id and status.tenant_id = job.tenant_id
    where job.tenant_id = v_authority.tenant_id
      and job.deleted_at is null
      and not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', job.job_number, customer.name, bike.brand, bike.model,
            coalesce(status.name, job.status), job.priority,
            job.client_request, job.assigned_technician_name)
        )) = 0
      )
    order by (public.assistant_normalize_query_internal_v1(job.job_number) = v_query) desc,
      job.updated_at desc, job.job_number
    limit p_limit + 1
  ), numbered as (
    select entity_id, job_number, priority, arrival_date, deadline, client_request,
      assigned_technician_name, customer_name, status_name,
      row_number() over (
        order by
          (public.assistant_normalize_query_internal_v1(job_number) = v_query) desc,
          updated_at desc, job_number
      ) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'jobNumber', public.assistant_truncate_utf8_internal_v1(job_number, 80),
      'customerName', public.assistant_truncate_utf8_internal_v1(customer_name, 160),
      'status', public.assistant_truncate_utf8_internal_v1(status_name, 100),
      'priority', public.assistant_truncate_utf8_internal_v1(priority, 40),
      'arrivalDate', arrival_date,
      'deliveryDeadline', deadline,
      'clientRequest', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(client_request, ''), 500), ''),
      'assignedTechnicianName', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(assigned_technician_name, ''), 72), '')
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    count(*) into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$$;

create or replace function public.assistant_get_workshop_view_context_v1(
  p_job_ids uuid[]
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
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if p_job_ids is null or cardinality(p_job_ids) not between 1 and 20
     or array_position(p_job_ids, null) is not null
     or (select count(*) <> count(distinct id) from unnest(p_job_ids) id) then
    raise exception 'Invalid AI view context' using errcode = '22023';
  end if;
  with matched as (
    select job.job_number, job.priority, job.arrival_date, job.deadline,
      job.client_request, job.assigned_technician_name,
      customer.name customer_name,
      coalesce(status.name, job.status) status_name,
      input.ordinality ordinal
    from unnest(p_job_ids) with ordinality input(id, ordinality)
    join public.mechanic_jobs job on job.id = input.id
      and job.tenant_id = v_authority.tenant_id and job.deleted_at is null
    join public.customers customer on customer.id = job.customer_id
      and customer.tenant_id = job.tenant_id
    left join public.job_statuses status on status.id = job.status_id
      and status.tenant_id = job.tenant_id
    order by input.ordinality
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'jobNumber', public.assistant_truncate_utf8_internal_v1(job_number, 80),
      'customerName', public.assistant_truncate_utf8_internal_v1(customer_name, 160),
      'status', public.assistant_truncate_utf8_internal_v1(status_name, 100),
      'priority', public.assistant_truncate_utf8_internal_v1(priority, 40),
      'arrivalDate', arrival_date,
      'deliveryDeadline', deadline,
      'clientRequest', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(client_request, ''), 500), ''),
      'assignedTechnicianName', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(assigned_technician_name, ''), 72), '')
    ) order by ordinal), '[]'::jsonb), count(*)
  into v_items, v_total from matched;
  if v_total <> cardinality(p_job_ids) then
    raise exception 'AI workshop view context is unavailable'
      using errcode = '42501';
  end if;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, false
  );
end;
$$;

create or replace function public.assistant_search_tasks_v1(
  p_query text,
  p_limit integer default 10
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
  v_query text;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if octet_length(coalesce(p_query, '')) not between 1 and 240
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then raise exception 'Invalid AI tool arguments' using errcode = '22023'; end if;

  with matched as materialized (
    select task.id entity_id, task.title, task.status, task.priority, task.due_date,
      task.updated_at,
      case when task.assigned_to = v_authority.actor_user_id
        then 'Tú' else null end assignee_name,
      coalesce(job.job_number, customer.name) linked_context
    from public.smart_tasks task
    left join public.mechanic_jobs job on job.id = task.linked_job_id
      and job.tenant_id = task.tenant_id
    left join public.customers customer on customer.id = task.linked_customer_id
      and customer.tenant_id = task.tenant_id
    where task.tenant_id = v_authority.tenant_id
      and not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', task.title, task.description, task.status, task.priority,
            case when task.assigned_to = v_authority.actor_user_id then 'tu' end,
            job.job_number, customer.name)
        )) = 0
      )
    order by task.updated_at desc, task.title
    limit p_limit + 1
  ), numbered as (
    select entity_id, title, status, priority, due_date, assignee_name, linked_context,
      row_number() over (order by updated_at desc, title) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'title', public.assistant_truncate_utf8_internal_v1(title, 160),
      'status', public.assistant_truncate_utf8_internal_v1(status, 40),
      'priority', public.assistant_truncate_utf8_internal_v1(priority, 40),
      'dueDate', due_date,
      'assigneeName', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(assignee_name, ''), 160), ''),
      'linkedContext', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(linked_context, ''), 180), '')
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    count(*) into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$$;

create or replace function public.assistant_search_customers_v1(
  p_query text,
  p_limit integer default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare v_authority record; v_query text; v_items jsonb; v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;
  if octet_length(coalesce(p_query, '')) not between 1 and 240 or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then raise exception 'Invalid AI tool arguments' using errcode = '22023'; end if;
  with matched as materialized (
    select customer.id entity_id, customer.name, customer.is_active, customer.updated_at
    from public.customers customer
    where customer.tenant_id = v_authority.tenant_id and not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        customer.name
      )) = 0)
    order by customer.updated_at desc, customer.name limit p_limit + 1
  ), numbered as (
    select entity_id, name, is_active, updated_at,
      row_number() over (order by updated_at desc, name) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160), 'isActive', is_active, 'updatedAt', updated_at
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$$;

create or replace function public.assistant_search_suppliers_v1(
  p_query text,
  p_limit integer default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare v_authority record; v_query text; v_items jsonb; v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;
  if octet_length(coalesce(p_query, '')) not between 1 and 240 or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then raise exception 'Invalid AI tool arguments' using errcode = '22023'; end if;
  with matched as materialized (
    select supplier.id entity_id, supplier.name, supplier.is_active, supplier.updated_at
    from public.suppliers supplier
    where supplier.tenant_id = v_authority.tenant_id and not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        concat_ws(' ', supplier.name, supplier.legal_name, supplier.trade_name,
          array_to_string(supplier.aliases, ' '))
      )) = 0)
    order by supplier.updated_at desc, supplier.name limit p_limit + 1
  ), numbered as (
    select entity_id, name, is_active, updated_at,
      row_number() over (order by updated_at desc, name) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160), 'isActive', is_active, 'updatedAt', updated_at
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$$;

create or replace function public.assistant_search_sales_invoices_v1(
  p_query text,
  p_limit integer default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare v_authority record; v_query text; v_items jsonb; v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.sales'
  ) authority;
  if octet_length(coalesce(p_query, '')) not between 1 and 240 or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then raise exception 'Invalid AI tool arguments' using errcode = '22023'; end if;
  with matched as materialized (
    select invoice.id entity_id, invoice.invoice_number, invoice.customer_name, invoice.status,
      invoice.date, invoice.due_date, invoice.total, invoice.balance
    from public.sales_invoices invoice
    where invoice.tenant_id = v_authority.tenant_id and not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        concat_ws(' ', invoice.invoice_number, invoice.customer_name, invoice.status)
      )) = 0)
    order by invoice.date desc, invoice.invoice_number limit p_limit + 1
  ), numbered as (
    select entity_id, invoice_number, customer_name, status, date, due_date, total, balance,
      row_number() over (order by date desc, invoice_number) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'invoiceNumber', public.assistant_truncate_utf8_internal_v1(invoice_number, 100),
      'customerName', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(customer_name, ''), 160), ''),
      'status', public.assistant_truncate_utf8_internal_v1(status, 40), 'date', date, 'dueDate', due_date,
      'total', total, 'balance', balance
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$$;

create or replace function public.assistant_search_purchase_invoices_v1(
  p_query text,
  p_limit integer default 10
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
set statement_timeout = '4500ms'
as $$
declare v_authority record; v_query text; v_items jsonb; v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;
  if octet_length(coalesce(p_query, '')) not between 1 and 240 or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  if v_query = '' then raise exception 'Invalid AI tool arguments' using errcode = '22023'; end if;
  with matched as materialized (
    select invoice.id entity_id, invoice.invoice_number, invoice.supplier_name, invoice.status,
      invoice.date, invoice.due_date, invoice.total, invoice.balance,
      invoice.receipt_state
    from public.purchase_invoice_list_read_model invoice
    where invoice.tenant_id = v_authority.tenant_id and not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        concat_ws(' ', invoice.invoice_number, invoice.supplier_name, invoice.status,
          invoice.receipt_state)
      )) = 0)
    order by invoice.date desc, invoice.invoice_number limit p_limit + 1
  ), numbered as (
    select entity_id, invoice_number, supplier_name, status, date, due_date, total, balance,
      row_number() over (order by date desc, invoice_number) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'invoiceNumber', public.assistant_truncate_utf8_internal_v1(invoice_number, 100),
      'supplierName', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(supplier_name, ''), 160), ''),
      'status', public.assistant_truncate_utf8_internal_v1(status, 40), 'date', date, 'dueDate', due_date,
      'total', total, 'balance', balance
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$$;

revoke all on function public.assistant_search_inventory_v1(text)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_list_attention_items_v1(text)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_search_workshop_jobs_v1(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_get_workshop_view_context_v1(uuid[])
from public, anon, authenticated, service_role;
revoke all on function public.assistant_search_tasks_v1(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_search_customers_v1(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_search_suppliers_v1(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_search_sales_invoices_v1(text, integer)
from public, anon, authenticated, service_role;
revoke all on function public.assistant_search_purchase_invoices_v1(text, integer)
from public, anon, authenticated, service_role;

grant execute on function public.assistant_search_inventory_v1(text) to authenticated;
grant execute on function public.assistant_list_attention_items_v1(text) to authenticated;
grant execute on function public.assistant_search_workshop_jobs_v1(text, integer) to authenticated;
grant execute on function public.assistant_get_workshop_view_context_v1(uuid[]) to authenticated;
grant execute on function public.assistant_search_tasks_v1(text, integer) to authenticated;
grant execute on function public.assistant_search_customers_v1(text, integer) to authenticated;
grant execute on function public.assistant_search_suppliers_v1(text, integer) to authenticated;
grant execute on function public.assistant_search_sales_invoices_v1(text, integer) to authenticated;
grant execute on function public.assistant_search_purchase_invoices_v1(text, integer) to authenticated;

comment on function public.assistant_search_suppliers_v1(text, integer) is
  'Tenant-bound assistant supplier projection. It never returns contact, bank, portal or credential fields.';
comment on function public.assistant_get_workshop_view_context_v1(uuid[]) is
  'Non-model tool: rereads caller-supplied visible job ids inside the current authenticated tenant and emits no ids.';

commit;
