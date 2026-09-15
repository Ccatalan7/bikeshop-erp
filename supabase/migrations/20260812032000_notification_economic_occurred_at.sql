-- Separate notification recording time from the economic time of the event.
--
-- `created_at` remains the durable "registered now" timestamp used by the
-- notification inbox, unread state, and recent-activity timeline.
-- `occurred_at` is the business timestamp used by economic summaries. Expense
-- notifications follow expenses.issue_date and sales-payment notifications
-- follow sales_payments.date; every other source falls back to created_at.
--
-- Deployment status: applied to production on 2026-08-12. Live read-back
-- confirmed 316 non-null rows, zero source-date mismatches, both UPDATE triggers,
-- the tenant/date index, and private trigger-function ACLs.
--
-- Recovery: clients can keep reading created_at while occurred_at remains an
-- additive column. If the source-date synchronization must be paused, restore
-- the prior INSERT-only trigger definitions; preserve the backfilled column and
-- history. No expense, payment, journal, or notification row is deleted.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '30s';

alter table public.erp_notifications
  add column if not exists occurred_at timestamp with time zone;

-- The bounded existing notification history is repaired in place. This is
-- idempotent and also picks up a source-date correction if the migration is
-- replayed before history registration.
with resolved as (
  select
    notification.id,
    case
      when notification.type = 'expense_recorded'
       and notification.entity_type = 'expense'
        then coalesce(expense.issue_date, notification.created_at)
      when notification.type = 'sales_payment_received'
       and notification.entity_type = 'sales_payment'
        then coalesce(payment.date, notification.created_at)
      else notification.created_at
    end as occurred_at
  from public.erp_notifications notification
  left join public.expenses expense
    on notification.type = 'expense_recorded'
   and notification.entity_type = 'expense'
   and expense.tenant_id = notification.tenant_id
   and expense.id = notification.entity_id
  left join public.sales_payments payment
    on notification.type = 'sales_payment_received'
   and notification.entity_type = 'sales_payment'
   and payment.tenant_id = notification.tenant_id
   and payment.id = notification.entity_id
)
update public.erp_notifications notification
   set occurred_at = resolved.occurred_at
  from resolved
 where notification.id = resolved.id
   and notification.occurred_at is distinct from resolved.occurred_at;

alter table public.erp_notifications
  alter column occurred_at set default now(),
  alter column occurred_at set not null;

comment on column public.erp_notifications.occurred_at is
  'Economic event time for period summaries; created_at remains the notification recording time.';

create index if not exists idx_erp_notifications_tenant_occurred_at
  on public.erp_notifications(tenant_id, occurred_at desc);

create or replace function public.create_sales_payment_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text;
  v_payment_method text;
  v_customer_name text;
  v_recorded_by text;
begin
  -- Skip soft-deleted rows. Their existing durable notification, if any,
  -- remains historical evidence and is not manufactured or deleted here.
  if NEW.deleted_at is not null then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' and NEW.date is not distinct from OLD.date then
    return NEW;
  end if;

  select name into v_payment_method
  from public.payment_methods
  where tenant_id = NEW.tenant_id
    and id = NEW.payment_method_id;

  select customer_name into v_customer_name
  from public.sales_invoices
  where id = NEW.invoice_id;

  v_recorded_by := public.erp_actor_display_name(auth.uid(), NEW.tenant_id);

  v_body := coalesce(nullif(NEW.invoice_reference, ''), 'Pago');

  if coalesce(NEW.amount, 0) > 0 then
    v_body := v_body || ' · $' || trim(to_char(NEW.amount, 'FM999G999G999G990'));
  end if;

  insert into public.erp_notifications as existing (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data,
    occurred_at
  ) values (
    NEW.tenant_id,
    'sales_payment_received',
    'Nuevo pago recibido',
    v_body,
    '/sales/payments',
    'sales_payment',
    NEW.id,
    'success',
    jsonb_build_object(
      'payment_id', NEW.id,
      'invoice_id', NEW.invoice_id,
      'invoice_reference', NEW.invoice_reference,
      'amount', NEW.amount,
      'payment_method', v_payment_method,
      'customer_name', v_customer_name,
      'recorded_by_name', v_recorded_by,
      'recorded_at', NEW.created_at,
      'payment_date', NEW.date,
      'reference', NEW.reference
    ),
    NEW.date
  ) on conflict (tenant_id, type, entity_type, entity_id) do update
    set occurred_at = excluded.occurred_at,
        data = existing.data
          || jsonb_build_object('payment_date', NEW.date);

  return NEW;
end;
$$;

revoke all on function public.create_sales_payment_erp_notification()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_sales_payment_erp_notification
  on public.sales_payments;
create trigger trg_sales_payment_erp_notification
  after insert or update of date on public.sales_payments
  for each row execute function public.create_sales_payment_erp_notification();

create or replace function public.create_expense_erp_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text;
  v_category_name text;
  v_payment_method text;
  v_recorded_by text;
  v_supplier_name text;
begin
  -- Legacy imports may still contain rows without a tenant. Notification
  -- persistence must never make those compatibility writes fail.
  if NEW.tenant_id is null then
    return NEW;
  end if;

  if TG_OP = 'UPDATE'
     and NEW.issue_date is not distinct from OLD.issue_date then
    return NEW;
  end if;

  select name
    into v_category_name
  from public.expense_categories
  where tenant_id = NEW.tenant_id
    and id = NEW.category_id;

  select name
    into v_payment_method
  from public.payment_methods
  where tenant_id = NEW.tenant_id
    and id = NEW.payment_method_id;

  v_recorded_by := public.erp_actor_display_name(
    coalesce(NEW.created_by, auth.uid()),
    NEW.tenant_id
  );
  v_supplier_name := coalesce(
    nullif(trim(NEW.supplier_name), ''),
    'Proveedor no informado'
  );
  v_body := coalesce(nullif(trim(NEW.expense_number), ''), 'Gasto')
    || ' · '
    || v_supplier_name;

  if coalesce(NEW.total_amount, 0) > 0 then
    v_body := v_body
      || ' · $'
      || trim(to_char(NEW.total_amount, 'FM999G999G999G990'));
  end if;

  insert into public.erp_notifications as existing (
    tenant_id,
    type,
    title,
    body,
    route,
    entity_type,
    entity_id,
    severity,
    data,
    occurred_at
  ) values (
    NEW.tenant_id,
    'expense_recorded',
    'Nuevo gasto registrado',
    v_body,
    '/accounting/expenses/' || NEW.id::text,
    'expense',
    NEW.id,
    'info',
    jsonb_build_object(
      'expense_id', NEW.id,
      'expense_number', NEW.expense_number,
      'supplier_id', NEW.supplier_id,
      'supplier_name', NEW.supplier_name,
      'supplier_rut', NEW.supplier_rut,
      'document_type', NEW.document_type,
      'document_number', NEW.document_number,
      'issue_date', NEW.issue_date,
      'subtotal', NEW.subtotal,
      'tax_amount', NEW.tax_amount,
      'total_amount', NEW.total_amount,
      'currency', NEW.currency,
      'posting_status', NEW.posting_status,
      'payment_status', NEW.payment_status,
      'payment_method', v_payment_method,
      'category_name', v_category_name,
      'recorded_by_name', v_recorded_by,
      'recorded_at', NEW.created_at
    ),
    NEW.issue_date
  ) on conflict (tenant_id, type, entity_type, entity_id) do update
    set occurred_at = excluded.occurred_at,
        data = existing.data
          || jsonb_build_object('issue_date', NEW.issue_date);

  return NEW;
end;
$$;

revoke all on function public.create_expense_erp_notification()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_expense_erp_notification on public.expenses;
create trigger trg_expense_erp_notification
  after insert or update of issue_date on public.expenses
  for each row execute function public.create_expense_erp_notification();

commit;
