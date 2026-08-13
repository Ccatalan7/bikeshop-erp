-- General, model-first operational context for the ERP assistant.
--
-- This is deliberately a closed scalar snapshot rather than authored advice:
-- the model decides what matters for the operator. Each source reports its own
-- success/verified-empty/unavailable state so an unavailable source is never
-- interpreted as a verified zero. No row identifiers, people, free text or
-- financial data leave this projection.

begin;

create or replace function public.assistant_get_business_snapshot_v1(
  p_horizon text
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
  v_business_date date;
  v_end_date date;
  v_workshop jsonb;
  v_tasks jsonb;
  v_inventory jsonb;
  v_open_count bigint;
  v_overdue_count bigint;
  v_due_count bigint;
  v_urgent_count bigint;
  v_awaiting_approval_count bigint;
  v_assigned_to_me_count bigint;
  v_tracked_item_count bigint;
  v_low_stock_count bigint;
  v_out_of_stock_count bigint;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  if p_horizon is null
     or p_horizon not in ('today', 'tomorrow', 'next_7_days') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  v_business_date := public.tenant_business_date(v_authority.tenant_id);
  v_end_date := v_business_date + case p_horizon
    when 'today' then 0
    when 'tomorrow' then 1
    else 6
  end;

  begin
    with active_jobs as materialized (
      select job.deadline, job.priority, job.requires_approval,
        job.approved_by_customer
      from public.mechanic_jobs job
      left join public.job_statuses status
        on status.id = job.status_id and status.tenant_id = job.tenant_id
      where job.tenant_id = v_authority.tenant_id
        and job.deleted_at is null
        and job.delivered_at is null
        and job.completed_at is null
        and upper(coalesce(job.status, '')) not in (
          'COMPLETADO', 'COMPLETADA', 'FINALIZADO', 'FINALIZADA',
          'ENTREGADO', 'ENTREGADA', 'CANCELADO', 'CANCELADA',
          'COMPLETED', 'COMPLETE', 'DELIVERED', 'CANCELLED', 'CANCELED'
        )
        and coalesce(status.phase, 'in_progress') <> 'complete'
        and coalesce(status.triggers_delivery, false) is false
    )
    select count(*),
      count(*) filter (
        where deadline is not null
          and public.tenant_business_date(v_authority.tenant_id, deadline)
            < v_business_date
      ),
      count(*) filter (
        where deadline is not null
          and public.tenant_business_date(v_authority.tenant_id, deadline)
            between v_business_date and v_end_date
      ),
      count(*) filter (where upper(coalesce(priority, '')) = 'URGENTE'),
      count(*) filter (
        where coalesce(requires_approval, false)
          and not coalesce(approved_by_customer, false)
      )
    into v_open_count, v_overdue_count, v_due_count, v_urgent_count,
      v_awaiting_approval_count
    from active_jobs;

    v_workshop := jsonb_build_object(
      'source', 'workshop_jobs',
      'sourceStatus', case when v_open_count = 0
        then 'verifiedEmpty' else 'success' end,
      'horizon', p_horizon,
      'openCount', v_open_count,
      'overdueCount', v_overdue_count,
      'dueInHorizonCount', v_due_count,
      'urgentCount', v_urgent_count,
      'awaitingApprovalCount', v_awaiting_approval_count,
      'assignedToMeCount', null,
      'trackedItemCount', null,
      'lowStockCount', null,
      'outOfStockCount', null
    );
  exception when others then
    v_workshop := jsonb_build_object(
      'source', 'workshop_jobs', 'sourceStatus', 'unavailable',
      'horizon', p_horizon, 'openCount', null, 'overdueCount', null,
      'dueInHorizonCount', null, 'urgentCount', null,
      'awaitingApprovalCount', null, 'assignedToMeCount', null,
      'trackedItemCount', null, 'lowStockCount', null,
      'outOfStockCount', null
    );
  end;

  begin
    with active_tasks as materialized (
      select task.due_date, task.priority, task.assigned_to
      from public.smart_tasks task
      where task.tenant_id = v_authority.tenant_id
        and lower(coalesce(task.status, '')) not in ('completed', 'cancelled')
    )
    select count(*),
      count(*) filter (
        where due_date is not null
          and public.tenant_business_date(v_authority.tenant_id, due_date)
            < v_business_date
      ),
      count(*) filter (
        where due_date is not null
          and public.tenant_business_date(v_authority.tenant_id, due_date)
            between v_business_date and v_end_date
      ),
      count(*) filter (where lower(coalesce(priority, '')) = 'urgent'),
      count(*) filter (where assigned_to = v_authority.actor_user_id)
    into v_open_count, v_overdue_count, v_due_count, v_urgent_count,
      v_assigned_to_me_count
    from active_tasks;

    v_tasks := jsonb_build_object(
      'source', 'tasks',
      'sourceStatus', case when v_open_count = 0
        then 'verifiedEmpty' else 'success' end,
      'horizon', p_horizon,
      'openCount', v_open_count,
      'overdueCount', v_overdue_count,
      'dueInHorizonCount', v_due_count,
      'urgentCount', v_urgent_count,
      'awaitingApprovalCount', null,
      'assignedToMeCount', v_assigned_to_me_count,
      'trackedItemCount', null,
      'lowStockCount', null,
      'outOfStockCount', null
    );
  exception when others then
    v_tasks := jsonb_build_object(
      'source', 'tasks', 'sourceStatus', 'unavailable',
      'horizon', p_horizon, 'openCount', null, 'overdueCount', null,
      'dueInHorizonCount', null, 'urgentCount', null,
      'awaitingApprovalCount', null, 'assignedToMeCount', null,
      'trackedItemCount', null, 'lowStockCount', null,
      'outOfStockCount', null
    );
  end;

  begin
    with tracked_inventory as materialized (
      select case when coalesce(product.is_set, false)
          then public.get_full_sets_count(product.id)
          else coalesce(product.stock_quantity, product.inventory_qty, 0)
        end as available_stock,
        greatest(coalesce(product.min_stock_level, 0), 0) as minimum_stock
      from public.products product
      where product.tenant_id = v_authority.tenant_id
        and product.is_active is true
        and coalesce(product.track_stock, true) is true
        and coalesce(product.is_service, false) is false
        and coalesce(product.purchase_treatment, 'inventory') = 'inventory'
    )
    select count(*),
      count(*) filter (where available_stock > 0 and available_stock <= minimum_stock),
      count(*) filter (where available_stock <= 0)
    into v_tracked_item_count, v_low_stock_count, v_out_of_stock_count
    from tracked_inventory;

    v_inventory := jsonb_build_object(
      'source', 'inventory',
      'sourceStatus', case when v_tracked_item_count = 0
        then 'verifiedEmpty' else 'success' end,
      'horizon', p_horizon,
      'openCount', null,
      'overdueCount', null,
      'dueInHorizonCount', null,
      'urgentCount', null,
      'awaitingApprovalCount', null,
      'assignedToMeCount', null,
      'trackedItemCount', v_tracked_item_count,
      'lowStockCount', v_low_stock_count,
      'outOfStockCount', v_out_of_stock_count
    );
  exception when others then
    v_inventory := jsonb_build_object(
      'source', 'inventory', 'sourceStatus', 'unavailable',
      'horizon', p_horizon, 'openCount', null, 'overdueCount', null,
      'dueInHorizonCount', null, 'urgentCount', null,
      'awaitingApprovalCount', null, 'assignedToMeCount', null,
      'trackedItemCount', null, 'lowStockCount', null,
      'outOfStockCount', null
    );
  end;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    jsonb_build_array(v_workshop, v_tasks, v_inventory),
    false
  );
end;
$$;

revoke all on function public.assistant_get_business_snapshot_v1(text)
from public, anon, authenticated, service_role;
grant execute on function public.assistant_get_business_snapshot_v1(text)
to authenticated;

comment on function public.assistant_get_business_snapshot_v1(text) is
  'Caller-bound, tenant-scoped operational scalar snapshot for model planning. No identifiers, people, free text or financial data are returned.';

commit;
