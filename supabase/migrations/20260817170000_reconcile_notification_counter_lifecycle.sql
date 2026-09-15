-- Keep every Daily Briefing counter aligned with one active source entity.
--
-- Creation notifications are durable history, but they used to stay typed as
-- active after a workshop job was archived, an expense was voided/deleted, or
-- an online order was cancelled. That made the top counters disagree with the
-- canonical source tables. Lifecycle changes now update the existing
-- notification identity in place, preserving created_at/read_at and realtime
-- identity while removing inactive facts from the active metric types.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- One payload-state backstop for every current and future lifecycle source.
-- Source triggers still own truthful type transitions; this trigger only
-- normalizes the shared mixed-version guard on the durable notification row.
create or replace function public.normalize_erp_notification_lifecycle_state()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if NEW.type in (
    'mechanic_job_archived',
    'sales_payment_voided',
    'expense_voided',
    'expense_deleted',
    'online_order_cancelled'
  ) then
    NEW.data := coalesce(NEW.data, '{}'::jsonb)
      || jsonb_build_object('is_inactive', true);
  elsif NEW.type in (
    'mechanic_job_created',
    'sales_payment_received',
    'expense_recorded',
    'online_order_created'
  ) then
    NEW.data := coalesce(NEW.data, '{}'::jsonb) - 'is_inactive';
  end if;
  return NEW;
end;
$$;

revoke all on function public.normalize_erp_notification_lifecycle_state()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_erp_notifications_lifecycle_state
  on public.erp_notifications;
create trigger trg_erp_notifications_lifecycle_state
  before insert or update of type, data
  on public.erp_notifications
  for each row execute function public.normalize_erp_notification_lifecycle_state();

comment on function public.normalize_erp_notification_lifecycle_state() is
  'Maintains the shared is_inactive payload guard from server-owned notification lifecycle types.';

-- ============================================================
-- Workshop jobs: active creation <-> audited Eliminados state.
-- ============================================================
create or replace function public.create_mechanic_job_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_bike_label text;
  v_body text;
  v_client_request text;
  v_customer_name text;
  v_is_archive boolean := false;
  v_is_restore boolean := false;
  v_job public.mechanic_jobs%rowtype;
  v_recorded_by_name text;
  v_removed_at timestamp with time zone;
  v_removed_by_name text;
begin
  if TG_OP = 'DELETE' then
    v_job := OLD;
    v_is_archive := true;
  else
    v_job := NEW;
  end if;

  if TG_OP = 'UPDATE' then
    v_is_archive := OLD.deleted_at is null and NEW.deleted_at is not null;
    v_is_restore := OLD.deleted_at is not null and NEW.deleted_at is null;
    if not v_is_archive and not v_is_restore then
      return NEW;
    end if;
  end if;

  if v_is_archive then
    v_removed_at := coalesce(v_job.deleted_at, clock_timestamp());
    v_removed_by_name := public.erp_actor_display_name(
      coalesce(v_job.deleted_by, auth.uid()),
      v_job.tenant_id
    );

    update public.erp_notifications as notification
       set type = 'mechanic_job_archived',
           title = 'Trabajo eliminado',
           route = '/taller/pegas',
           severity = 'warning',
           data = notification.data || jsonb_strip_nulls(jsonb_build_object(
             'is_inactive', true,
             'inactive_reason', 'archived',
             'removed_at', v_removed_at,
             'removed_by_name', v_removed_by_name,
             'archive_reason', nullif(btrim(v_job.archive_reason), '')
           ))
     where notification.tenant_id = v_job.tenant_id
       and notification.entity_type = 'mechanic_job'
       and notification.entity_id = v_job.id
       and notification.type in (
         'mechanic_job_created',
         'mechanic_job_archived'
       );

    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;

  -- An insert already carrying deleted_at is an inactive import, not a new
  -- workshop arrival. A normal restore is handled below.
  if TG_OP = 'INSERT' and NEW.deleted_at is not null then
    return NEW;
  end if;

  select customer.name
    into v_customer_name
  from public.customers customer
  where customer.id = v_job.customer_id
    and customer.tenant_id = v_job.tenant_id;

  select nullif(trim(
           coalesce(bike.brand, '') || ' ' || coalesce(bike.model, '')
           || case
                when nullif(trim(coalesce(bike.color, '')), '') is not null
                  then ' · ' || bike.color
                else ''
              end
         ), '')
    into v_bike_label
  from public.bikes bike
  where bike.id = v_job.bike_id
    and bike.tenant_id = v_job.tenant_id;

  v_client_request := nullif(
    left(coalesce(v_job.client_request, ''), 300),
    ''
  );
  v_recorded_by_name := public.erp_actor_display_name(
    coalesce(v_job.created_by, auth.uid()),
    v_job.tenant_id
  );
  v_body := coalesce(nullif(v_job.job_number, ''), 'Trabajo')
    || ' · '
    || coalesce(nullif(v_customer_name, ''), 'Cliente');

  if v_is_restore then
    update public.erp_notifications as notification
       set type = 'mechanic_job_created',
           title = 'Nuevo trabajo',
           body = v_body,
           route = '/taller/pegas?job=' || v_job.id::text,
           severity = 'info',
           data = (
             notification.data
               - 'is_inactive'
               - 'inactive_reason'
               - 'removed_at'
               - 'removed_by_name'
               - 'archive_reason'
           ) || jsonb_strip_nulls(jsonb_build_object(
             'job_id', v_job.id,
             'job_number', v_job.job_number,
             'customer_id', v_job.customer_id,
             'customer_name', v_customer_name,
             'bike_id', v_job.bike_id,
             'bike_label', v_bike_label,
             'client_request', v_client_request,
             'recorded_by_name', v_recorded_by_name,
             'priority', v_job.priority,
             'status', v_job.status
           ))
     where notification.tenant_id = v_job.tenant_id
       and notification.entity_type = 'mechanic_job'
       and notification.entity_id = v_job.id
       and notification.type = 'mechanic_job_archived';

    if found then
      return NEW;
    end if;
  end if;

  insert into public.erp_notifications (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data
  ) values (
    v_job.tenant_id,
    'mechanic_job_created',
    'Nuevo trabajo',
    v_body,
    '/taller/pegas?job=' || v_job.id::text,
    'mechanic_job',
    v_job.id,
    'info',
    jsonb_strip_nulls(jsonb_build_object(
      'job_id', v_job.id,
      'job_number', v_job.job_number,
      'customer_id', v_job.customer_id,
      'customer_name', v_customer_name,
      'bike_id', v_job.bike_id,
      'bike_label', v_bike_label,
      'client_request', v_client_request,
      'recorded_by_name', v_recorded_by_name,
      'priority', v_job.priority,
      'status', v_job.status
    ))
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return v_job;
end;
$$;

revoke all on function public.create_mechanic_job_erp_notification()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_mechanic_job_erp_notification
  on public.mechanic_jobs;
create trigger trg_mechanic_job_erp_notification
  after insert or delete or update of deleted_at
  on public.mechanic_jobs
  for each row execute function public.create_mechanic_job_erp_notification();

comment on function public.create_mechanic_job_erp_notification() is
  'Creates one job activity identity and converts it in place between active and Eliminados lifecycle states.';

-- ============================================================
-- Expenses: active record <-> void/deleted states.
-- The existing creation trigger remains the owner of insert/date payloads;
-- this narrow trigger owns lifecycle projection only.
-- ============================================================
create or replace function public.reconcile_expense_erp_notification_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_actor_name text;
  v_expense public.expenses%rowtype;
  v_inactive_type text;
  v_is_delete boolean := TG_OP = 'DELETE';
  v_is_restore boolean := false;
  v_is_void boolean := false;
begin
  if TG_OP = 'DELETE' then
    v_expense := OLD;
  else
    v_expense := NEW;
  end if;

  if TG_OP = 'INSERT' then
    v_is_void := NEW.posting_status = 'void';
    if not v_is_void then
      return NEW;
    end if;
  elsif TG_OP = 'UPDATE' then
    v_is_void := OLD.posting_status is distinct from 'void'
      and NEW.posting_status = 'void';
    v_is_restore := OLD.posting_status = 'void'
      and NEW.posting_status is distinct from 'void';
    if not v_is_void and not v_is_restore then
      return NEW;
    end if;
  end if;

  if v_is_delete or v_is_void then
    v_inactive_type := case
      when v_is_delete then 'expense_deleted'
      else 'expense_voided'
    end;
    v_actor_name := public.erp_actor_display_name(
      auth.uid(),
      v_expense.tenant_id
    );

    update public.erp_notifications as notification
       set type = v_inactive_type,
           title = case
             when v_is_delete then 'Gasto eliminado'
             else 'Gasto anulado'
           end,
           route = case
             when v_is_delete then '/accounting/expenses'
             else '/accounting/expenses/' || v_expense.id::text
           end,
           severity = 'warning',
           data = notification.data || jsonb_strip_nulls(jsonb_build_object(
             'is_inactive', true,
             'inactive_reason', case
               when v_is_delete then 'deleted'
               else 'voided'
             end,
             case
               when v_is_delete then 'deleted_at'
               else 'voided_at'
             end, clock_timestamp(),
             case
               when v_is_delete then 'deleted_by_name'
               else 'voided_by_name'
             end, v_actor_name
           ))
     where notification.tenant_id = v_expense.tenant_id
       and notification.entity_type = 'expense'
       and notification.entity_id = v_expense.id
       and notification.type in (
         'expense_recorded',
         'expense_voided',
         'expense_deleted'
       );

    if TG_OP = 'DELETE' then
      return OLD;
    end if;
    return NEW;
  end if;

  update public.erp_notifications as notification
     set type = 'expense_recorded',
         title = 'Nuevo gasto registrado',
         route = '/accounting/expenses/' || v_expense.id::text,
         severity = 'info',
         data = notification.data
           - 'is_inactive'
           - 'inactive_reason'
           - 'voided_at'
           - 'voided_by_name'
           - 'deleted_at'
           - 'deleted_by_name'
   where notification.tenant_id = v_expense.tenant_id
     and notification.entity_type = 'expense'
     and notification.entity_id = v_expense.id
     and notification.type = 'expense_voided';

  return NEW;
end;
$$;

revoke all on function public.reconcile_expense_erp_notification_lifecycle()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_expense_notification_lifecycle
  on public.expenses;
create trigger trg_expense_notification_lifecycle
  after insert or delete or update of posting_status
  on public.expenses
  for each row execute function public.reconcile_expense_erp_notification_lifecycle();

comment on function public.reconcile_expense_erp_notification_lifecycle() is
  'Converts the one durable expense activity between recorded, voided, and deleted states without changing its event identity.';

-- ============================================================
-- Online orders: active creation <-> cancelled state.
-- ============================================================
create or replace function public.reconcile_online_order_erp_notification_lifecycle()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_cancelled_by_name text;
  v_is_cancel boolean := false;
  v_is_restore boolean := false;
begin
  if TG_OP = 'INSERT' then
    v_is_cancel := NEW.status = 'cancelled';
    if not v_is_cancel then
      return NEW;
    end if;
  else
    v_is_cancel := OLD.status is distinct from 'cancelled'
      and NEW.status = 'cancelled';
    v_is_restore := OLD.status = 'cancelled'
      and NEW.status is distinct from 'cancelled';
    if not v_is_cancel and not v_is_restore then
      return NEW;
    end if;
  end if;

  if v_is_cancel then
    v_cancelled_by_name := public.erp_actor_display_name(
      coalesce(NEW.cancelled_by, auth.uid()),
      NEW.tenant_id
    );

    update public.erp_notifications as notification
       set type = 'online_order_cancelled',
           title = 'Pedido cancelado',
           route = '/website/orders?order=' || NEW.id::text,
           severity = 'warning',
           data = notification.data || jsonb_strip_nulls(jsonb_build_object(
             'is_inactive', true,
             'inactive_reason', 'cancelled',
             'cancelled_at', NEW.cancelled_at,
             'cancelled_by_name', v_cancelled_by_name,
             'cancelled_reason', nullif(btrim(NEW.cancelled_reason), ''),
             'refund_amount', NEW.refund_amount
           ))
     where notification.tenant_id = NEW.tenant_id
       and notification.entity_type = 'online_order'
       and notification.entity_id = NEW.id
       and notification.type in (
         'online_order_created',
         'online_order_cancelled'
       );

    return NEW;
  end if;

  update public.erp_notifications as notification
     set type = 'online_order_created',
         title = 'Nueva venta online',
         route = '/website/orders?order=' || NEW.id::text,
         severity = 'success',
         data = notification.data
           - 'is_inactive'
           - 'inactive_reason'
           - 'cancelled_at'
           - 'cancelled_by_name'
           - 'cancelled_reason'
           - 'refund_amount'
   where notification.tenant_id = NEW.tenant_id
     and notification.entity_type = 'online_order'
     and notification.entity_id = NEW.id
     and notification.type = 'online_order_cancelled';

  return NEW;
end;
$$;

revoke all on function public.reconcile_online_order_erp_notification_lifecycle()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_online_order_notification_lifecycle
  on public.online_orders;
create trigger trg_online_order_notification_lifecycle
  after insert or update of status
  on public.online_orders
  for each row execute function public.reconcile_online_order_erp_notification_lifecycle();

comment on function public.reconcile_online_order_erp_notification_lifecycle()
  is 'Converts the one durable online-order activity between new and cancelled states so only active orders reach the briefing counter.';

-- ============================================================
-- Historical reconciliation. No source business row is changed.
-- ============================================================
with stale_jobs as (
  select
    notification.id,
    job.deleted_at,
    job.deleted_by,
    job.archive_reason,
    notification.tenant_id
  from public.erp_notifications notification
  left join public.mechanic_jobs job
    on job.tenant_id = notification.tenant_id
   and job.id = notification.entity_id
  where notification.type = 'mechanic_job_created'
    and notification.entity_type = 'mechanic_job'
    and (job.id is null or job.deleted_at is not null)
), resolved_jobs as (
  select
    stale_jobs.*,
    public.erp_actor_display_name(
      stale_jobs.deleted_by,
      stale_jobs.tenant_id
    ) as removed_by_name
  from stale_jobs
)
update public.erp_notifications as notification
   set type = 'mechanic_job_archived',
       title = 'Trabajo eliminado',
       route = '/taller/pegas',
       severity = 'warning',
       data = notification.data || jsonb_strip_nulls(jsonb_build_object(
         'is_inactive', true,
         'inactive_reason', 'archived',
         'removed_at', resolved_jobs.deleted_at,
         'removed_by_name', resolved_jobs.removed_by_name,
         'archive_reason', nullif(btrim(resolved_jobs.archive_reason), '')
       ))
  from resolved_jobs
 where notification.id = resolved_jobs.id;

with stale_expenses as (
  select
    notification.id,
    expense.id as expense_id
  from public.erp_notifications notification
  left join public.expenses expense
    on expense.tenant_id = notification.tenant_id
   and expense.id = notification.entity_id
  where notification.type = 'expense_recorded'
    and notification.entity_type = 'expense'
    and (expense.id is null or expense.posting_status = 'void')
)
update public.erp_notifications as notification
   set type = case
         when stale_expenses.expense_id is null then 'expense_deleted'
         else 'expense_voided'
       end,
       title = case
         when stale_expenses.expense_id is null then 'Gasto eliminado'
         else 'Gasto anulado'
       end,
       route = case
         when stale_expenses.expense_id is null then '/accounting/expenses'
         else '/accounting/expenses/' || stale_expenses.expense_id::text
       end,
       severity = 'warning',
       data = notification.data || jsonb_build_object(
         'is_inactive', true,
         'inactive_reason', case
           when stale_expenses.expense_id is null then 'deleted'
           else 'voided'
         end
       )
  from stale_expenses
 where notification.id = stale_expenses.id;

update public.erp_notifications as notification
   set type = 'online_order_cancelled',
       title = 'Pedido cancelado',
       route = '/website/orders?order=' || order_row.id::text,
       severity = 'warning',
       data = notification.data || jsonb_strip_nulls(jsonb_build_object(
         'is_inactive', true,
         'inactive_reason', 'cancelled',
         'cancelled_at', order_row.cancelled_at,
         'cancelled_by_name', public.erp_actor_display_name(
           order_row.cancelled_by,
           order_row.tenant_id
         ),
         'cancelled_reason', nullif(btrim(order_row.cancelled_reason), ''),
         'refund_amount', order_row.refund_amount
       ))
  from public.online_orders order_row
 where notification.type = 'online_order_created'
   and notification.entity_type = 'online_order'
   and order_row.tenant_id = notification.tenant_id
   and order_row.id = notification.entity_id
   and order_row.status = 'cancelled';

-- The shared defensive client guard can treat every inactive lifecycle in the
-- same way, including the payment state installed immediately before this
-- migration.
update public.erp_notifications
   set data = data || jsonb_build_object('is_inactive', true)
 where type in (
   'mechanic_job_archived',
   'sales_payment_voided',
   'expense_voided',
   'expense_deleted',
   'online_order_cancelled'
 )
   and coalesce((data->>'is_inactive')::boolean, false) is false;

notify pgrst, 'reload schema';

commit;
