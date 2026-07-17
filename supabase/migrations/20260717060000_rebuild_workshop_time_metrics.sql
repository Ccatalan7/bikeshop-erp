-- Canonical, provenance-aware workshop time read model plus honest sales
-- classification. Historical rows are never rewritten: legacy lifecycle
-- events are reconstructed only at read time and retain their source.
begin;

create or replace function public.get_mechanic_job_time_metrics(
  p_job_ids uuid[] default null
)
returns table (
  job_id uuid,
  approval_decision_at timestamptz,
  approval_decision text,
  approval_source text,
  started_at timestamptz,
  start_source text,
  completed_at timestamptz,
  completion_source text,
  first_delivered_at timestamptz,
  delivery_source text,
  current_is_completed boolean,
  current_is_delivered boolean,
  reopened_after_delivery boolean,
  quality_flags text[]
)
language sql
stable
security definer
set search_path = public
as $$
  with selected_jobs as (
    select job.*
    from public.mechanic_jobs job
    where job.tenant_id = public.user_tenant_id()
      and job.deleted_at is null
      and (
        p_job_ids is null
        or cardinality(p_job_ids) = 0
        or job.id = any(p_job_ids)
      )
  ),
  approval_candidates as (
    select job.id as job_id, job.approved_at as occurred_at,
      'approved'::text as decision, 'recorded_timestamp'::text as source,
      0 as source_priority
    from selected_jobs job
    where job.approved_at is not null
      and job.approved_at >= job.arrival_date
    union all
    select event.job_id, event.occurred_at,
      event.to_quotation_status, 'mode_event'::text, 1
    from public.mechanic_job_mode_events event
    join selected_jobs job on job.id = event.job_id
    where event.event_type = 'quotation_status_changed'
      and event.to_quotation_status in ('approved', 'rejected')
      and event.occurred_at >= job.arrival_date
    union all
    select timeline.job_id, timeline.created_at,
      'approved'::text, 'legacy_timeline'::text, 2
    from public.mechanic_job_timeline timeline
    join selected_jobs job on job.id = timeline.job_id
    where timeline.event_type = 'approved'
      and timeline.created_at >= job.arrival_date
  ),
  approval_milestones as (
    select distinct on (candidate.job_id)
      candidate.job_id, candidate.occurred_at, candidate.decision,
      candidate.source
    from approval_candidates candidate
    order by candidate.job_id, candidate.occurred_at, candidate.source_priority
  ),
  start_candidates as (
    select job.id as job_id, job.started_at as occurred_at,
      'recorded_timestamp'::text as source, 0 as source_priority
    from selected_jobs job
    where job.started_at is not null
      and job.started_at >= job.arrival_date
    union all
    select timeline.job_id, timeline.created_at,
      'legacy_timeline'::text, 1
    from public.mechanic_job_timeline timeline
    join selected_jobs job on job.id = timeline.job_id
    where (
        timeline.event_type = 'status_changed'
        and upper(replace(btrim(coalesce(timeline.new_value, '')), ' ', '_'))
          in ('COMENZAR', 'EN_CURSO')
      )
      and timeline.created_at >= job.arrival_date
  ),
  start_milestones as (
    select distinct on (candidate.job_id)
      candidate.job_id, candidate.occurred_at, candidate.source
    from start_candidates candidate
    order by candidate.job_id, candidate.occurred_at, candidate.source_priority
  ),
  completion_candidates as (
    select job.id as job_id, job.completed_at as occurred_at,
      'recorded_timestamp'::text as source, 0 as source_priority
    from selected_jobs job
    left join start_milestones start on start.job_id = job.id
    where job.completed_at is not null
      and job.completed_at >= coalesce(start.occurred_at, job.arrival_date)
    union all
    select timeline.job_id, timeline.created_at,
      'legacy_timeline'::text, 1
    from public.mechanic_job_timeline timeline
    join selected_jobs job on job.id = timeline.job_id
    left join start_milestones start on start.job_id = job.id
    where (
        timeline.event_type = 'completed'
        or (
          timeline.event_type = 'status_changed'
          and upper(replace(btrim(coalesce(timeline.new_value, '')), ' ', '_'))
            in ('FINALIZADO', 'TERMINADO')
        )
      )
      and timeline.created_at >= coalesce(start.occurred_at, job.arrival_date)
  ),
  completion_milestones as (
    select distinct on (candidate.job_id)
      candidate.job_id, candidate.occurred_at, candidate.source
    from completion_candidates candidate
    order by candidate.job_id, candidate.occurred_at, candidate.source_priority
  ),
  raw_deliveries as (
    select event.job_id, min(event.occurred_at) as occurred_at
    from public.mechanic_job_delivery_events event
    join selected_jobs job on job.id = event.job_id
    where event.event_kind in ('delivered', 'redelivered')
    group by event.job_id
  ),
  delivery_milestones as (
    select distinct on (event.job_id)
      event.job_id, event.occurred_at, event.source
    from public.mechanic_job_delivery_events event
    join selected_jobs job on job.id = event.job_id
    where event.event_kind in ('delivered', 'redelivered')
      and event.occurred_at >= job.arrival_date
    order by event.job_id, event.occurred_at
  ),
  resolved as (
    select
      job.*,
      approval.occurred_at as resolved_approval_at,
      approval.decision as resolved_approval_decision,
      approval.source as resolved_approval_source,
      start.occurred_at as resolved_started_at,
      start.source as resolved_start_source,
      completion.occurred_at as resolved_completed_at,
      completion.source as resolved_completion_source,
      delivery.occurred_at as resolved_delivery_at,
      delivery.source as resolved_delivery_source,
      raw_delivery.occurred_at as raw_first_delivery_at,
      public.mechanic_job_resolves_completion(job.status, job.status_id)
        as resolved_current_is_completed,
      public.mechanic_job_resolves_delivery(job.status, job.status_id)
        as resolved_current_is_delivered
    from selected_jobs job
    left join approval_milestones approval on approval.job_id = job.id
    left join start_milestones start on start.job_id = job.id
    left join completion_milestones completion on completion.job_id = job.id
    left join delivery_milestones delivery on delivery.job_id = job.id
    left join raw_deliveries raw_delivery on raw_delivery.job_id = job.id
  )
  select
    job.id,
    job.resolved_approval_at,
    job.resolved_approval_decision,
    job.resolved_approval_source,
    job.resolved_started_at,
    job.resolved_start_source,
    job.resolved_completed_at,
    job.resolved_completion_source,
    job.resolved_delivery_at,
    job.resolved_delivery_source,
    job.resolved_current_is_completed,
    job.resolved_current_is_delivered,
    job.resolved_delivery_at is not null
      and not job.resolved_current_is_delivered,
    array_remove(array[
      case when job.requires_approval
          and job.resolved_approval_at is null
        then 'approval_missing_when_required' end,
      case when job.resolved_current_is_completed
          and job.resolved_started_at is null
        then 'start_missing_when_terminal' end,
      case when job.resolved_current_is_delivered
          and job.resolved_completed_at is null
        then 'completion_missing_when_delivered' end,
      case when job.resolved_current_is_delivered
          and job.resolved_delivery_at is null
        then 'delivery_event_missing_when_delivered' end,
      case when job.raw_first_delivery_at < job.arrival_date
        then 'delivery_before_arrival' end,
      case when job.deadline < job.arrival_date
        then 'deadline_before_arrival' end,
      case when job.started_at < job.arrival_date
        then 'recorded_start_before_arrival' end,
      case when job.completed_at < coalesce(
          job.resolved_started_at, job.arrival_date
        )
        then 'recorded_completion_before_start' end,
      case when job.resolved_start_source = 'legacy_timeline'
        then 'start_reconstructed_from_timeline' end,
      case when job.resolved_completion_source = 'legacy_timeline'
        then 'completion_reconstructed_from_timeline' end,
      case when job.resolved_delivery_source in (
          'legacy_timeline', 'legacy_current_state'
        )
        then 'delivery_reconstructed_from_legacy_event' end
    ]::text[], null)
  from resolved job
  order by job.arrival_date desc, job.id;
$$;

revoke all on function public.get_mechanic_job_time_metrics(uuid[])
  from public, anon;
grant execute on function public.get_mechanic_job_time_metrics(uuid[])
  to authenticated;

comment on function public.get_mechanic_job_time_metrics(uuid[]) is
  'Tenant-scoped lifecycle milestones for workshop UI. Direct timestamps and immutable events are preferred; credible legacy timeline milestones are reconstructed without rewriting history and every reconstruction is identified by source/quality flags.';

create or replace function public.get_strategic_dashboard_metrics(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_start timestamp with time zone := least(p_start_date, p_end_date);
  v_end timestamp with time zone := greatest(p_start_date, p_end_date);
begin
  if v_tenant_id is null then
    raise exception 'Authenticated tenant context is required'
      using errcode = '42501';
  end if;

  if v_end = v_start then
    v_end := v_start + interval '1 day';
  end if;

  return (
    with
    physical_jobs as (
      select job.*
      from public.mechanic_jobs job
      where job.tenant_id = v_tenant_id
        and job.deleted_at is null
        and coalesce(job.workflow_kind, 'service') in ('service', 'warranty', 'quotation')
        and coalesce(job.intake_kind, case when job.bike_id is null then 'unspecified' else 'bike' end)
          not in ('none')
    ),
    approval_decisions as (
      select
        event.job_id,
        event.to_quotation_status,
        event.occurred_at,
        extract(epoch from (event.occurred_at - job.arrival_date)) / 3600.0 as elapsed_hours
      from public.mechanic_job_mode_events event
      join physical_jobs job on job.id = event.job_id
      where event.tenant_id = v_tenant_id
        and event.event_type = 'quotation_status_changed'
        and event.to_quotation_status in ('approved', 'rejected')
        and event.occurred_at >= v_start
        and event.occurred_at < v_end
        and event.occurred_at >= job.arrival_date
    ),
    started_cycles as (
      select
        job.id,
        extract(epoch from (
          job.started_at - coalesce(job.approved_at, job.arrival_date)
        )) / 3600.0 as elapsed_hours
      from physical_jobs job
      where job.started_at >= v_start
        and job.started_at < v_end
        and job.started_at >= coalesce(job.approved_at, job.arrival_date)
    ),
    execution_cycles as (
      select
        job.id,
        extract(epoch from (job.completed_at - job.started_at)) / 3600.0 as elapsed_hours
      from physical_jobs job
      where job.completed_at >= v_start
        and job.completed_at < v_end
        and job.started_at is not null
        and job.completed_at >= job.started_at
    ),
    first_deliveries as (
      select
        event.job_id,
        min(event.occurred_at) as delivered_at
      from public.mechanic_job_delivery_events event
      where event.tenant_id = v_tenant_id
        and event.event_kind = 'delivered'
      group by event.job_id
    ),
    delivered_cycles as (
      select
        job.id,
        delivery.delivered_at,
        job.deadline,
        extract(epoch from (delivery.delivered_at - job.arrival_date)) / 3600.0 as elapsed_hours
      from physical_jobs job
      join first_deliveries delivery on delivery.job_id = job.id
      where delivery.delivered_at >= v_start
        and delivery.delivered_at < v_end
        and delivery.delivered_at >= job.arrival_date
    ),
    active_jobs as (
      select
        job.*,
        greatest(extract(epoch from (v_end - job.arrival_date)) / 86400.0, 0) as age_days
      from physical_jobs job
      where upper(coalesce(job.status, 'PENDIENTE'))
        not in ('FINALIZADO', 'ENTREGADO', 'CANCELADO')
    ),
    workshop_invoices as (
      select
        job.id as job_id,
        job.actual_labor_hours,
        job.estimated_duration_hours,
        job.labor_cost,
        invoice.id as invoice_id,
        invoice.date,
        coalesce(invoice.net_amount, invoice.subtotal, 0)::numeric as net_amount
      from physical_jobs job
      join public.sales_invoices invoice
        on invoice.id = job.invoice_id
       and invoice.tenant_id = v_tenant_id
      where invoice.date >= v_start
        and invoice.date < v_end
        and lower(coalesce(invoice.status, '')) not in ('cancelado', 'cancelled', 'canceled')
        and coalesce(job.workflow_kind, 'service') in ('service', 'warranty')
    ),
    sales_invoice_scope as (
      select
        invoice.id,
        invoice.date,
        coalesce(invoice.net_amount, invoice.subtotal, 0)::numeric as net_amount,
        invoice.items
      from public.sales_invoices invoice
      where invoice.tenant_id = v_tenant_id
        and invoice.date >= v_start
        and invoice.date < v_end
        and lower(coalesce(invoice.status, '')) not in ('cancelado', 'cancelled', 'canceled')
    ),
    invoice_items as (
      select
        invoice.id as invoice_id,
        invoice.date,
        item.value as item,
        case when line_totals.line_total > 0
          then invoice.net_amount / line_totals.line_total
          else 1 end as net_factor
      from sales_invoice_scope invoice
      cross join lateral (
        select coalesce(sum(
          case when coalesce(raw.value ->> 'line_total', '') ~ '^-?[0-9]+([.][0-9]+)?$'
            then (raw.value ->> 'line_total')::numeric else 0 end
        ), 0) as line_total
        from jsonb_array_elements(
          case when jsonb_typeof(invoice.items) = 'array' then invoice.items else '[]'::jsonb end
        ) raw(value)
      ) line_totals
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(invoice.items) = 'array' then invoice.items else '[]'::jsonb end
      ) item(value)
    ),
    classified_sales as (
      select
        invoice_id,
        date,
        nullif(item ->> 'product_id', '') as product_id,
        coalesce(nullif(item ->> 'product_name', ''), 'Producto') as product_name,
        case
          when (
            item ? 'is_service'
            and lower(coalesce(item ->> 'is_service', '')) in ('true', 't', '1')
          ) or lower(coalesce(item ->> 'item_type', '')) = 'service'
            then 'service'
          when (
            item ? 'is_service'
            and lower(coalesce(item ->> 'is_service', '')) in ('false', 'f', '0')
          ) or lower(coalesce(item ->> 'item_type', '')) in (
            'product', 'part', 'accessory'
          )
            then 'product'
          else 'unknown'
        end as sale_kind,
        case when coalesce(item ->> 'quantity', '') ~ '^-?[0-9]+([.][0-9]+)?$'
          then (item ->> 'quantity')::numeric else 0 end as quantity,
        (
          case when coalesce(item ->> 'line_total', '') ~ '^-?[0-9]+([.][0-9]+)?$'
            then (item ->> 'line_total')::numeric else 0 end
        ) * net_factor as net_sales,
        case when item ? 'cost'
          and coalesce(item ->> 'cost', '') ~ '^-?[0-9]+([.][0-9]+)?$'
          then (item ->> 'cost')::numeric
          else null end as unit_cost
      from invoice_items
    ),
    sales_mix as (
      select
        coalesce(sum(net_sales) filter (where sale_kind = 'product'), 0) as product_sales,
        coalesce(sum(net_sales) filter (where sale_kind = 'service'), 0) as service_sales,
        coalesce(sum(net_sales) filter (where sale_kind = 'unknown'), 0) as unknown_sales,
        coalesce(sum(net_sales) filter (where sale_kind = 'product' and unit_cost is not null), 0) as product_sales_with_cost,
        coalesce(sum(unit_cost * quantity) filter (where sale_kind = 'product' and unit_cost is not null), 0) as product_cogs
      from classified_sales
    ),
    workshop_sales_mix as (
      select
        coalesce(sum(line.net_sales) filter (where line.sale_kind = 'product'), 0) as product_sales,
        coalesce(sum(line.net_sales) filter (where line.sale_kind = 'service'), 0) as service_sales,
        coalesce(sum(line.net_sales) filter (where line.sale_kind = 'unknown'), 0) as unknown_sales
      from classified_sales line
      join workshop_invoices invoice on invoice.invoice_id = line.invoice_id
    ),
    product_sales as (
      select
        product_id,
        max(product_name) as product_name,
        sum(quantity) as units,
        sum(net_sales) as sales
      from classified_sales
      where product_id is not null and sale_kind = 'product'
      group by product_id
    ),
    business_hours_setting as (
      select setting.value::jsonb as value
      from public.website_settings setting
      where setting.tenant_id = v_tenant_id
        and setting.key in ('business_hours_json', 'google_business_regular_hours')
        and setting.value is not null
        and btrim(setting.value) <> ''
      order by case setting.key when 'business_hours_json' then 0 else 1 end
      limit 1
    ),
    business_periods as (
      select
        (period.value #>> '{open,day}')::integer as day_of_week,
        (
          substring(period.value #>> '{open,time}' from 1 for 2)::integer * 60
          + substring(period.value #>> '{open,time}' from 3 for 2)::integer
        ) as open_minute,
        (
          substring(period.value #>> '{close,time}' from 1 for 2)::integer * 60
          + substring(period.value #>> '{close,time}' from 3 for 2)::integer
        ) as close_minute
      from business_hours_setting setting
      cross join lateral jsonb_array_elements(
        case
          when jsonb_typeof(setting.value -> 'periods') = 'array'
            then setting.value -> 'periods'
          else '[]'::jsonb
        end
      ) period(value)
      where coalesce(period.value #>> '{open,time}', '') ~ '^[0-9]{4}$'
        and coalesce(period.value #>> '{close,time}', '') ~ '^[0-9]{4}$'
        and coalesce(period.value #>> '{open,day}', '') ~ '^[0-6]$'
    ),
    business_calendar as (
      select day::date as local_day
      from generate_series(
        (v_start at time zone 'America/Santiago')::date,
        ((v_end - interval '1 microsecond') at time zone 'America/Santiago')::date,
        interval '1 day'
      ) day
    ),
    business_capacity as (
      select coalesce(sum(
        case
          when period.close_minute >= period.open_minute
            then period.close_minute - period.open_minute
          else 1440 - period.open_minute + period.close_minute
        end
      ), 0)::numeric / 60.0 as open_hours
      from business_calendar calendar
      join business_periods period
        on period.day_of_week = extract(dow from calendar.local_day)::integer
    ),
    mechanics as (
      select employee.id, coalesce(employee.hourly_rate, 0)::numeric as hourly_rate
      from public.employees employee
      where employee.tenant_id = v_tenant_id
        and lower(coalesce(employee.status, 'active')) = 'active'
        and lower(coalesce(employee.job_title, '')) ~ '^mec[aá]nico'
    ),
    mechanic_attendance as (
      select
        attendance.employee_id,
        greatest(
          extract(epoch from (
            least(coalesce(attendance.check_out, v_end), v_end)
              - greatest(attendance.check_in, v_start)
          )) / 3600.0 - coalesce(attendance.break_minutes, 0)::numeric / 60.0,
          0
        ) as attended_hours,
        mechanic.hourly_rate
      from public.attendances attendance
      join mechanics mechanic on mechanic.id = attendance.employee_id
      where attendance.tenant_id = v_tenant_id
        and attendance.check_in < v_end
        and coalesce(attendance.check_out, v_end) > v_start
        and lower(coalesce(attendance.status, '')) not in ('rejected', 'cancelled', 'canceled')
    ),
    payroll_cost as (
      select
        coalesce(sum(
          case when lower(coalesce(voucher.status, '')) = 'paid'
            then line.total_amount * greatest(
              0,
              least(voucher.period_end, (v_end at time zone 'America/Santiago')::date - 1)
                - greatest(voucher.period_start, (v_start at time zone 'America/Santiago')::date)
                + 1
            )::numeric / greatest(1, voucher.period_end - voucher.period_start + 1)
            else 0 end
        ), 0) as paid_cost,
        coalesce(sum(
          case when lower(coalesce(voucher.status, '')) <> 'paid'
            then line.total_amount * greatest(
              0,
              least(voucher.period_end, (v_end at time zone 'America/Santiago')::date - 1)
                - greatest(voucher.period_start, (v_start at time zone 'America/Santiago')::date)
                + 1
            )::numeric / greatest(1, voucher.period_end - voucher.period_start + 1)
            else 0 end
        ), 0) as pending_cost,
        count(*) as line_count
      from public.payroll_voucher_lines line
      join public.payroll_vouchers voucher
        on voucher.id = line.voucher_id
       and voucher.tenant_id = v_tenant_id
      join mechanics mechanic on mechanic.id = line.employee_id
      where line.tenant_id = v_tenant_id
        and line.is_included = true
        and voucher.period_start < (v_end at time zone 'America/Santiago')::date
        and voucher.period_end >= (v_start at time zone 'America/Santiago')::date
    ),
    weekly_axis as (
      select generate_series(
        date_trunc('week', v_end) - interval '7 weeks',
        date_trunc('week', v_end),
        interval '1 week'
      ) as week_start
    ),
    weekly_flow as (
      select
        axis.week_start,
        (
          select count(*)::integer
          from delivered_cycles delivery
          where delivery.delivered_at >= axis.week_start
            and delivery.delivered_at < axis.week_start + interval '1 week'
        ) as deliveries,
        (
          select coalesce(sum(invoice.net_amount), 0)::numeric
          from workshop_invoices invoice
          where invoice.date >= axis.week_start
            and invoice.date < axis.week_start + interval '1 week'
        ) as net_sales
      from weekly_axis axis
      order by axis.week_start
    )
    select jsonb_build_object(
      'period', jsonb_build_object(
        'start', v_start,
        'end', v_end,
        'days', greatest(1, ceil(extract(epoch from (v_end - v_start)) / 86400.0)::integer)
      ),
      'flow', jsonb_build_object(
        'approvalMedianHours', (
          select percentile_cont(0.5) within group (order by elapsed_hours)
          from approval_decisions where to_quotation_status = 'approved'
        ),
        'approvalSamples', (
          select count(*) from approval_decisions where to_quotation_status = 'approved'
        ),
        'startMedianHours', (
          select percentile_cont(0.5) within group (order by elapsed_hours) from started_cycles
        ),
        'startSamples', (select count(*) from started_cycles),
        'executionMedianHours', (
          select percentile_cont(0.5) within group (order by elapsed_hours) from execution_cycles
        ),
        'executionSamples', (select count(*) from execution_cycles),
        'totalMedianHours', (
          select percentile_cont(0.5) within group (order by elapsed_hours) from delivered_cycles
        ),
        'totalSamples', (select count(*) from delivered_cycles),
        'deliveredCount', (select count(*) from delivered_cycles),
        'onTimeRate', (
          select case when count(*) = 0 then null
            else count(*) filter (where delivered_at <= deadline)::numeric / count(*) end
          from delivered_cycles where deadline is not null
        ),
        'onTimeSamples', (select count(*) from delivered_cycles where deadline is not null),
        'approvalRate', (
          select case when count(*) = 0 then null
            else count(*) filter (where to_quotation_status = 'approved')::numeric / count(*) end
          from approval_decisions
        ),
        'decisionSamples', (select count(*) from approval_decisions)
      ),
      'load', jsonb_build_object(
        'activeCount', (select count(*) from active_jobs),
        'overdueCount', (
          select count(*) from active_jobs where deadline is not null and deadline < v_end
        ),
        'ageBuckets', jsonb_build_array(
          jsonb_build_object('label', '0–2 días', 'count', (select count(*) from active_jobs where age_days < 3)),
          jsonb_build_object('label', '3–5 días', 'count', (select count(*) from active_jobs where age_days >= 3 and age_days < 6)),
          jsonb_build_object('label', '6–10 días', 'count', (select count(*) from active_jobs where age_days >= 6 and age_days < 11)),
          jsonb_build_object('label', '11+ días', 'count', (select count(*) from active_jobs where age_days >= 11))
        )
      ),
      'value', jsonb_build_object(
        'netSales', coalesce((select sum(net_amount) from workshop_invoices), 0),
        'averageTicket', coalesce((select avg(net_amount) from workshop_invoices), 0),
        'invoiceCount', (select count(*) from workshop_invoices),
        'serviceSales', (select service_sales from sales_mix),
        'productSales', (select product_sales from sales_mix),
        'unclassifiedSales', (select unknown_sales from sales_mix),
        'serviceSalesShare', (
          select case when service_sales + product_sales + unknown_sales <= 0 then null
            else service_sales / (service_sales + product_sales + unknown_sales) end
          from sales_mix
        ),
        'productSalesShare', (
          select case when service_sales + product_sales + unknown_sales <= 0 then null
            else product_sales / (service_sales + product_sales + unknown_sales) end
          from sales_mix
        ),
        'unclassifiedSalesShare', (
          select case when service_sales + product_sales + unknown_sales <= 0 then null
            else unknown_sales / (service_sales + product_sales + unknown_sales) end
          from sales_mix
        ),
        'classificationCoverageRate', (
          select case when service_sales + product_sales + unknown_sales <= 0 then null
            else (service_sales + product_sales)
              / (service_sales + product_sales + unknown_sales) end
          from sales_mix
        ),
        'workshopServiceSales', (select service_sales from workshop_sales_mix),
        'workshopProductSales', (select product_sales from workshop_sales_mix),
        'workshopUnclassifiedSales', (select unknown_sales from workshop_sales_mix),
        'productCostCoverageRate', (
          select case when product_sales <= 0 then null
            else product_sales_with_cost / product_sales end from sales_mix
        ),
        'productCogs', (select product_cogs from sales_mix),
        'productGrossContribution', (
          select product_sales_with_cost - product_cogs from sales_mix
        ),
        'productGrossMarginRate', (
          select case when product_sales_with_cost <= 0 then null
            else (product_sales_with_cost - product_cogs) / product_sales_with_cost end
          from sales_mix
        ),
        'actualHours', coalesce((select sum(actual_labor_hours) from workshop_invoices where actual_labor_hours > 0), 0),
        'actualHoursJobs', (select count(*) from workshop_invoices where actual_labor_hours > 0),
        'laborHourCoverageRate', (
          select case when count(*) = 0 then null
            else count(*) filter (where actual_labor_hours > 0)::numeric / count(*) end
          from workshop_invoices
        ),
        'netSalesPerLaborHour', (
          select case when coalesce(sum(actual_labor_hours) filter (where actual_labor_hours > 0), 0) = 0 then null
            else sum(net_amount) filter (where actual_labor_hours > 0)
              / sum(actual_labor_hours) filter (where actual_labor_hours > 0) end
          from workshop_invoices
        ),
        'estimateAccuracyRate', (
          select case when count(*) = 0 then null
            else count(*) filter (
              where abs(actual_labor_hours - estimated_duration_hours)
                <= estimated_duration_hours * 0.20
            )::numeric / count(*) end
          from workshop_invoices
          where actual_labor_hours > 0 and estimated_duration_hours > 0
        ),
        'estimateSamples', (
          select count(*) from workshop_invoices
          where actual_labor_hours > 0 and estimated_duration_hours > 0
        ),
        'businessOpenHours', (select open_hours from business_capacity),
        'mechanicAttendanceHours', coalesce((select sum(attended_hours) from mechanic_attendance), 0),
        'mechanicCount', (select count(*) from mechanics),
        'mechanicEquivalentCoverage', (
          select case when capacity.open_hours <= 0 then null
            else coalesce(sum(attendance.attended_hours), 0) / capacity.open_hours end
          from business_capacity capacity
          left join mechanic_attendance attendance on true
          group by capacity.open_hours
        ),
        'productiveUtilizationRate', (
          select case when coalesce(sum(attendance.attended_hours), 0) <= 0 then null
            else coalesce((
              select sum(actual_labor_hours)
              from workshop_invoices where actual_labor_hours > 0
            ), 0) / sum(attendance.attended_hours) end
          from mechanic_attendance attendance
        ),
        'netSalesPerAttendanceHour', (
          select case when coalesce(sum(attendance.attended_hours), 0) <= 0 then null
            else coalesce((select sum(net_amount) from workshop_invoices), 0)
              / sum(attendance.attended_hours) end
          from mechanic_attendance attendance
        ),
        'serviceSalesPerAttendanceHour', (
          select case when coalesce(sum(attendance.attended_hours), 0) <= 0 then null
            else coalesce((select service_sales from workshop_sales_mix), 0)
              / sum(attendance.attended_hours) end
          from mechanic_attendance attendance
        ),
        'paidMechanicCost', (select paid_cost from payroll_cost),
        'pendingMechanicCost', (select pending_cost from payroll_cost),
        'attendanceEstimatedMechanicCost', (
          select coalesce(sum(attended_hours * hourly_rate), 0) from mechanic_attendance
        ),
        'mechanicCostSource', (
          select case
            when line_count > 0 and pending_cost > 0 and paid_cost > 0 then 'paid_and_pending_payroll'
            when line_count > 0 and pending_cost > 0 then 'pending_payroll'
            when line_count > 0 then 'paid_payroll'
            else 'attendance_estimate'
          end from payroll_cost
        ),
        'mechanicCostUsed', (
          select case when line_count > 0 then paid_cost + pending_cost
            else (select coalesce(sum(attended_hours * hourly_rate), 0) from mechanic_attendance)
          end from payroll_cost
        ),
        'laborContribution', (
          select coalesce((select service_sales from workshop_sales_mix), 0)
            - case when line_count > 0 then paid_cost + pending_cost
              else (select coalesce(sum(attended_hours * hourly_rate), 0) from mechanic_attendance) end
          from payroll_cost
        ),
        'laborContributionRate', (
          select case when coalesce((select service_sales from workshop_sales_mix), 0) <= 0 then null
            else (
              coalesce((select service_sales from workshop_sales_mix), 0)
                - case when line_count > 0 then paid_cost + pending_cost
                  else (select coalesce(sum(attended_hours * hourly_rate), 0) from mechanic_attendance) end
            ) / (select service_sales from workshop_sales_mix) end
          from payroll_cost
        ),
        'jobAssignmentCoverageRate', (
          select case when count(*) = 0 then null
            else count(*) filter (
              where job.assigned_to is not null
                and exists (select 1 from mechanics mechanic where mechanic.id = job.assigned_to)
            )::numeric / count(*) end
          from physical_jobs job
          where job.arrival_date >= v_start and job.arrival_date < v_end
        )
      ),
      'inventory', jsonb_build_object(
        'soldProducts', (select count(*) from product_sales where units > 0),
        'unitsSold', coalesce((select sum(units) from product_sales where units > 0), 0),
        'stockCoverDays', (
          select case when coalesce(sum(sales.units), 0) <= 0 then null
            else sum(greatest(coalesce(product.stock_quantity, product.inventory_qty, 0), 0))::numeric
              / (sum(sales.units) / greatest(1, ceil(extract(epoch from (v_end - v_start)) / 86400.0))) end
          from product_sales sales
          join public.products product
            on product.id::text = sales.product_id
           and product.tenant_id = v_tenant_id
          where sales.units > 0
        ),
        'stagnantProductCount', (
          select count(*)
          from public.products product
          left join product_sales sales on sales.product_id = product.id::text and sales.units > 0
          where product.tenant_id = v_tenant_id
            and product.is_active = true
            and coalesce(product.is_service, false) = false
            and greatest(coalesce(product.stock_quantity, product.inventory_qty, 0), 0) > 0
            and sales.product_id is null
        ),
        'stagnantStockValue', (
          select coalesce(sum(
            greatest(coalesce(product.stock_quantity, product.inventory_qty, 0), 0)
              * coalesce(product.cost, 0)
          ), 0)
          from public.products product
          left join product_sales sales on sales.product_id = product.id::text and sales.units > 0
          where product.tenant_id = v_tenant_id
            and product.is_active = true
            and coalesce(product.is_service, false) = false
            and greatest(coalesce(product.stock_quantity, product.inventory_qty, 0), 0) > 0
            and sales.product_id is null
        ),
        'topProducts', coalesce((
          select jsonb_agg(jsonb_build_object(
            'productId', ranked.product_id,
            'name', ranked.product_name,
            'units', ranked.units,
            'sales', ranked.sales
          ) order by ranked.units desc, ranked.sales desc)
          from (
            select * from product_sales where units > 0 order by units desc, sales desc limit 5
          ) ranked
        ), '[]'::jsonb)
      ),
      'weekly', coalesce((
        select jsonb_agg(jsonb_build_object(
          'start', week_start,
          'deliveries', deliveries,
          'netSales', net_sales
        ) order by week_start)
        from weekly_flow
      ), '[]'::jsonb)
    )
  );
end;
$$;

revoke all on function public.get_strategic_dashboard_metrics(timestamp with time zone, timestamp with time zone) from public, anon;
grant execute on function public.get_strategic_dashboard_metrics(timestamp with time zone, timestamp with time zone) to authenticated;

comment on function public.get_strategic_dashboard_metrics(timestamp with time zone, timestamp with time zone) is
  'Tenant-scoped strategic workshop and inventory metrics. Product, service, and unclassified sales remain separate; every ratio includes its sample or coverage; labor productivity uses only explicitly recorded actual_labor_hours.';


commit;

