-- Model-first operational queries for questions that are filters, not keyword
-- searches (for example: overdue urgent workshop work or my tasks today).
-- All filters are closed enums and all results remain caller/tenant bound.

begin;

create or replace function public.assistant_query_workshop_jobs_v2(
  p_query text,
  p_horizon text,
  p_status text,
  p_priority text,
  p_limit integer
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
  v_business_date date;
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

  if octet_length(coalesce(p_query, '')) > 240
     or p_horizon is null
     or p_horizon not in ('any', 'today', 'tomorrow', 'week', 'overdue')
     or p_status is null
     or p_status not in ('any', 'open', 'completed', 'delivered', 'cancelled')
     or p_priority is null
     or p_priority not in ('any', 'urgent', 'high', 'normal', 'low')
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_business_date := public.tenant_business_date(v_authority.tenant_id);

  with candidates as materialized (
    select
      job.id entity_id,
      job.job_number,
      customer.name customer_name,
      coalesce(status.name, job.status) status_name,
      case
        when upper(coalesce(status.code, job.status, '')) in (
          'CANCELADO', 'CANCELADA', 'ANULADO', 'ANULADA',
          'CANCELLED', 'CANCELED'
        ) then 'cancelled'
        when job.delivered_at is not null
          or coalesce(status.triggers_delivery, false)
          or upper(coalesce(status.code, job.status, '')) in (
            'ENTREGADO', 'ENTREGADA', 'DELIVERED'
          )
          then 'delivered'
        when job.completed_at is not null
          or coalesce(status.phase, 'in_progress') = 'complete'
          or upper(coalesce(status.code, job.status, '')) in (
            'COMPLETADO', 'COMPLETADA', 'FINALIZADO', 'FINALIZADA',
            'COMPLETED', 'COMPLETE'
          ) then 'completed'
        else 'open'
      end lifecycle_status,
      case upper(coalesce(job.priority, 'NORMAL'))
        when 'URGENTE' then 'urgent'
        when 'ALTA' then 'high'
        when 'BAJA' then 'low'
        else 'normal'
      end normalized_priority,
      job.priority,
      job.arrival_date,
      job.deadline,
      job.client_request,
      job.updated_at,
      bike.brand bike_brand,
      bike.model bike_model
    from public.mechanic_jobs job
    join public.customers customer
      on customer.id = job.customer_id and customer.tenant_id = job.tenant_id
    left join public.bikes bike
      on bike.id = job.bike_id and bike.tenant_id = job.tenant_id
    left join public.job_statuses status
      on status.id = job.status_id and status.tenant_id = job.tenant_id
    where job.tenant_id = v_authority.tenant_id
      and job.deleted_at is null
  ), matched as materialized (
    select entity_id, job_number, customer_name, status_name,
      lifecycle_status, normalized_priority, priority, arrival_date, deadline,
      client_request, updated_at
    from candidates
    where (p_status = 'any' or lifecycle_status = p_status)
      and (p_priority = 'any' or normalized_priority = p_priority)
      and case p_horizon
        when 'any' then true
        when 'overdue' then deadline is not null and
          public.tenant_business_date(v_authority.tenant_id, deadline)
            < v_business_date
        when 'today' then deadline is not null and
          public.tenant_business_date(v_authority.tenant_id, deadline)
            = v_business_date
        when 'tomorrow' then deadline is not null and
          public.tenant_business_date(v_authority.tenant_id, deadline)
            = v_business_date + 1
        when 'week' then deadline is not null and
          public.tenant_business_date(v_authority.tenant_id, deadline)
            between v_business_date and v_business_date + 6
        else false
      end
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', job_number, customer_name, status_name, priority,
            client_request, bike_brand, bike_model)
        )) = 0
      ))
    order by
      (deadline is null), deadline,
      case normalized_priority
        when 'urgent' then 0 when 'high' then 1
        when 'normal' then 2 else 3 end,
      updated_at desc, job_number, entity_id
    limit p_limit + 1
  ), numbered as (
    select entity_id, job_number, customer_name, status_name, priority,
      arrival_date, deadline, client_request,
      row_number() over (order by
        (deadline is null), deadline,
        case normalized_priority
          when 'urgent' then 0 when 'high' then 1
          when 'normal' then 2 else 3 end,
        updated_at desc, job_number, entity_id
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
      'clientRequest', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(client_request, ''), 500), ''),
      -- Staff identities are not inferred from legacy free-text assignment.
      'assignedTechnicianName', null
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$$;

create or replace function public.assistant_query_tasks_v2(
  p_query text,
  p_horizon text,
  p_status text,
  p_priority text,
  p_assignee text,
  p_limit integer
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
  v_business_date date;
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

  if octet_length(coalesce(p_query, '')) > 240
     or p_horizon is null
     or p_horizon not in ('any', 'today', 'tomorrow', 'week', 'overdue')
     or p_status is null
     or p_status not in ('any', 'pending', 'in_progress', 'completed', 'cancelled')
     or p_priority is null
     or p_priority not in ('any', 'urgent', 'high', 'normal', 'low')
     or p_assignee is null
     or p_assignee not in ('any', 'me', 'unassigned')
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_business_date := public.tenant_business_date(v_authority.tenant_id);

  with matched as materialized (
    select task.id entity_id, task.title, lower(task.status) status,
      lower(task.priority) priority, task.due_date, task.updated_at,
      case when task.assigned_to = v_authority.actor_user_id
        then 'Tú' else null end assignee_name,
      job.job_number linked_context
    from public.smart_tasks task
    left join public.mechanic_jobs job
      on job.id = task.linked_job_id and job.tenant_id = task.tenant_id
    where task.tenant_id = v_authority.tenant_id
      and (p_status = 'any' or lower(task.status) = p_status)
      and (p_priority = 'any' or lower(task.priority) = p_priority)
      and case p_assignee
        when 'any' then true
        when 'me' then task.assigned_to = v_authority.actor_user_id
        when 'unassigned' then task.assigned_to is null
        else false
      end
      and case p_horizon
        when 'any' then true
        when 'overdue' then task.due_date is not null and
          public.tenant_business_date(v_authority.tenant_id, task.due_date)
            < v_business_date
        when 'today' then task.due_date is not null and
          public.tenant_business_date(v_authority.tenant_id, task.due_date)
            = v_business_date
        when 'tomorrow' then task.due_date is not null and
          public.tenant_business_date(v_authority.tenant_id, task.due_date)
            = v_business_date + 1
        when 'week' then task.due_date is not null and
          public.tenant_business_date(v_authority.tenant_id, task.due_date)
            between v_business_date and v_business_date + 6
        else false
      end
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', task.title, task.description, task.status,
            task.priority, job.job_number,
            case when task.assigned_to = v_authority.actor_user_id
              then 'tu' end)
        )) = 0
      ))
    order by (task.due_date is null), task.due_date,
      case lower(task.priority)
        when 'urgent' then 0 when 'high' then 1
        when 'normal' then 2 else 3 end,
      task.updated_at desc, task.title, task.id
    limit p_limit + 1
  ), numbered as (
    select entity_id, title, status, priority, due_date, assignee_name,
      linked_context,
      row_number() over (order by (due_date is null), due_date,
        case priority
          when 'urgent' then 0 when 'high' then 1
          when 'normal' then 2 else 3 end,
        updated_at desc, title, entity_id
      ) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'title', public.assistant_truncate_utf8_internal_v1(title, 160),
      'status', public.assistant_truncate_utf8_internal_v1(status, 40),
      'priority', public.assistant_truncate_utf8_internal_v1(priority, 40),
      'dueDate', due_date,
      'assigneeName', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(assignee_name, ''), 160), ''),
      'linkedContext', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(linked_context, ''), 180), '')
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > p_limit
  );
end;
$$;

revoke all on function public.assistant_query_workshop_jobs_v2(
  text, text, text, text, integer
) from public, anon, authenticated, service_role;
revoke all on function public.assistant_query_tasks_v2(
  text, text, text, text, text, integer
) from public, anon, authenticated, service_role;

grant execute on function public.assistant_query_workshop_jobs_v2(
  text, text, text, text, integer
) to authenticated;
grant execute on function public.assistant_query_tasks_v2(
  text, text, text, text, text, integer
) to authenticated;

comment on function public.assistant_query_workshop_jobs_v2(
  text, text, text, text, integer
) is 'Tenant-bound workshop query with optional keywords and closed lifecycle, priority and business-date filters.';
comment on function public.assistant_query_tasks_v2(
  text, text, text, text, text, integer
) is 'Tenant-bound task query with optional keywords and closed lifecycle, priority, business-date and self-assignment filters.';

commit;
