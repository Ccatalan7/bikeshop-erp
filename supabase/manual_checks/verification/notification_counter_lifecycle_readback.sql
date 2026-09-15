-- Executable production read-back for 20260817170000.
-- Every assertion fails at SQL level if a Daily Briefing active metric can
-- still point at an inactive source entity or duplicate one source identity.

select 1 / (case when exists (
  select 1
  from pg_trigger trigger_row
  where trigger_row.tgrelid = 'public.erp_notifications'::regclass
    and trigger_row.tgname = 'trg_erp_notifications_lifecycle_state'
    and not trigger_row.tgisinternal
) then 1 else 0 end) as shared_lifecycle_payload_trigger_installed;

select 1 / (case when exists (
  select 1
  from pg_trigger trigger_row
  where trigger_row.tgrelid = 'public.mechanic_jobs'::regclass
    and trigger_row.tgname = 'trg_mechanic_job_erp_notification'
    and not trigger_row.tgisinternal
    and pg_get_triggerdef(trigger_row.oid)
      like '%AFTER INSERT OR DELETE OR UPDATE OF deleted_at ON public.mechanic_jobs%'
) then 1 else 0 end) as job_lifecycle_trigger_installed;

select 1 / (case when exists (
  select 1
  from pg_trigger trigger_row
  where trigger_row.tgrelid = 'public.expenses'::regclass
    and trigger_row.tgname = 'trg_expense_notification_lifecycle'
    and not trigger_row.tgisinternal
) then 1 else 0 end) as expense_lifecycle_trigger_installed;

select 1 / (case when exists (
  select 1
  from pg_trigger trigger_row
  where trigger_row.tgrelid = 'public.online_orders'::regclass
    and trigger_row.tgname = 'trg_online_order_notification_lifecycle'
    and not trigger_row.tgisinternal
) then 1 else 0 end) as order_lifecycle_trigger_installed;

select 1 / (case when
  not has_function_privilege(
    'authenticated',
    'public.normalize_erp_notification_lifecycle_state()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.create_mechanic_job_erp_notification()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.reconcile_expense_erp_notification_lifecycle()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.reconcile_online_order_erp_notification_lifecycle()',
    'EXECUTE'
  )
then 1 else 0 end) as lifecycle_trigger_functions_are_private;

select 1 / (case when not exists (
  select 1
  from public.erp_notifications notification
  left join public.mechanic_jobs job
    on notification.entity_type = 'mechanic_job'
   and job.tenant_id = notification.tenant_id
   and job.id = notification.entity_id
  left join public.sales_payments payment
    on notification.entity_type = 'sales_payment'
   and payment.tenant_id = notification.tenant_id
   and payment.id = notification.entity_id
  left join public.expenses expense
    on notification.entity_type = 'expense'
   and expense.tenant_id = notification.tenant_id
   and expense.id = notification.entity_id
  left join public.online_orders order_row
    on notification.entity_type = 'online_order'
   and order_row.tenant_id = notification.tenant_id
   and order_row.id = notification.entity_id
  where notification.type = 'mechanic_job_created'
      and (job.id is null or job.deleted_at is not null)
    or notification.type = 'sales_payment_received'
      and (payment.id is null or payment.deleted_at is not null)
    or notification.type = 'expense_recorded'
      and (expense.id is null or expense.posting_status = 'void')
    or notification.type = 'online_order_created'
      and (order_row.id is null or order_row.status = 'cancelled')
) then 1 else 0 end) as no_active_metric_type_has_an_inactive_source;

select 1 / (case when not exists (
  select 1
  from public.erp_notifications notification
  where notification.type in (
      'mechanic_job_archived',
      'sales_payment_voided',
      'expense_voided',
      'expense_deleted',
      'online_order_cancelled'
    )
    and (
      notification.severity <> 'warning'
      or notification.data @> '{"is_inactive": true}'::jsonb is not true
    )
) then 1 else 0 end) as inactive_activity_is_explicit;

select 1 / (case when not exists (
  select 1
  from public.erp_notifications notification
  where notification.type = 'mechanic_job_archived'
    and notification.title <> 'Trabajo eliminado'
     or notification.type = 'sales_payment_voided'
    and notification.title <> 'Pago anulado'
     or notification.type = 'expense_voided'
    and notification.title <> 'Gasto anulado'
     or notification.type = 'expense_deleted'
    and notification.title <> 'Gasto eliminado'
     or notification.type = 'online_order_cancelled'
    and notification.title <> 'Pedido cancelado'
) then 1 else 0 end) as inactive_activity_has_truthful_titles;

select 1 / (case when not exists (
  select 1
  from public.erp_notifications notification
  where notification.type in (
      'mechanic_job_created',
      'mechanic_job_archived',
      'sales_payment_received',
      'sales_payment_voided',
      'expense_recorded',
      'expense_voided',
      'expense_deleted',
      'online_order_created',
      'online_order_cancelled'
    )
  group by notification.tenant_id,
           notification.entity_type,
           notification.entity_id
  having count(*) <> 1
) then 1 else 0 end) as one_notification_identity_per_metric_source;

with bounds as (
  select
    timezone('America/Santiago', now())::date as business_date,
    (
      timezone('America/Santiago', now())::date::timestamp
        at time zone 'America/Santiago'
    ) as starts_at,
    (
      (timezone('America/Santiago', now())::date + 1)::timestamp
        at time zone 'America/Santiago'
    ) as ends_at
), projected as (
  select
    count(*) filter (
      where notification.type = 'mechanic_job_created'
        and notification.created_at >= bounds.starts_at
        and notification.created_at < bounds.ends_at
    ) as notification_jobs,
    count(*) filter (
      where notification.type = 'sales_payment_received'
        and notification.occurred_at >= bounds.starts_at
        and notification.occurred_at < bounds.ends_at
    ) as notification_payments,
    coalesce(sum((notification.data->>'amount')::numeric) filter (
      where notification.type = 'sales_payment_received'
        and notification.occurred_at >= bounds.starts_at
        and notification.occurred_at < bounds.ends_at
    ), 0) as notification_payment_total,
    count(*) filter (
      where notification.type = 'expense_recorded'
        and notification.occurred_at >= bounds.starts_at
        and notification.occurred_at < bounds.ends_at
    ) as notification_expenses,
    coalesce(sum((notification.data->>'total_amount')::numeric) filter (
      where notification.type = 'expense_recorded'
        and notification.occurred_at >= bounds.starts_at
        and notification.occurred_at < bounds.ends_at
    ), 0) as notification_expense_total,
    count(*) filter (
      where notification.type = 'online_order_created'
        and notification.created_at >= bounds.starts_at
        and notification.created_at < bounds.ends_at
    ) as notification_orders
  from public.erp_notifications notification
  cross join bounds
), sources as (
  select
    (
      select count(*)
      from public.mechanic_jobs job, bounds
      where job.created_at >= bounds.starts_at
        and job.created_at < bounds.ends_at
        and job.deleted_at is null
    ) as source_jobs,
    (
      select count(*)
      from public.sales_payments payment, bounds
      where payment.date >= bounds.starts_at
        and payment.date < bounds.ends_at
        and payment.deleted_at is null
    ) as source_payments,
    (
      select coalesce(sum(payment.amount), 0)
      from public.sales_payments payment, bounds
      where payment.date >= bounds.starts_at
        and payment.date < bounds.ends_at
        and payment.deleted_at is null
    ) as source_payment_total,
    (
      select count(*)
      from public.expenses expense, bounds
      where expense.issue_date >= bounds.starts_at
        and expense.issue_date < bounds.ends_at
        and expense.posting_status <> 'void'
    ) as source_expenses,
    (
      select coalesce(sum(expense.total_amount), 0)
      from public.expenses expense, bounds
      where expense.issue_date >= bounds.starts_at
        and expense.issue_date < bounds.ends_at
        and expense.posting_status <> 'void'
    ) as source_expense_total,
    (
      select count(*)
      from public.online_orders order_row, bounds
      where order_row.created_at >= bounds.starts_at
        and order_row.created_at < bounds.ends_at
        and order_row.status <> 'cancelled'
    ) as source_orders
)
select 1 / (case when
  projected.notification_jobs = sources.source_jobs
  and projected.notification_payments = sources.source_payments
  and projected.notification_payment_total = sources.source_payment_total
  and projected.notification_expenses = sources.source_expenses
  and projected.notification_expense_total = sources.source_expense_total
  and projected.notification_orders = sources.source_orders
then 1 else 0 end) as today_metric_projection_matches_active_sources
from projected
cross join sources;

select
  notification.type,
  count(*) as notifications,
  count(distinct notification.entity_id) as source_entities
from public.erp_notifications notification
where notification.type in (
  'mechanic_job_created',
  'mechanic_job_archived',
  'sales_payment_received',
  'sales_payment_voided',
  'expense_recorded',
  'expense_voided',
  'expense_deleted',
  'online_order_created',
  'online_order_cancelled'
)
group by notification.type
order by notification.type;
