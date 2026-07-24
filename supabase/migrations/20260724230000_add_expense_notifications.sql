-- Add durable expense activity to the shared ERP notification center.
--
-- Deployment status: DEPLOYED to production xzdvtzdqjeyqxnkqprtf on 2026-07-24.
-- Verification: production-derived pgTAP 14/14; live read-back confirmed the
-- owner-only SECURITY DEFINER function, one AFTER INSERT trigger, two bounded
-- backfilled events, zero duplicates/orphans, and zero recent missing events.
-- Recovery: roll back the client while leaving the additive trigger/function in
-- place, or disable only trg_expense_erp_notification if expense inserts must be
-- decoupled. Existing expense and notification history must not be deleted.

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
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;

  return NEW;
end;
$$;

revoke all on function public.create_expense_erp_notification()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_expense_erp_notification on public.expenses;
create trigger trg_expense_erp_notification
  after insert on public.expenses
  for each row execute function public.create_expense_erp_notification();

-- The daily briefing also exposes the prior six local calendar days. Backfill
-- only that bounded launch window so recent expenses become discoverable
-- without turning the notification center into a historical import.
insert into public.erp_notifications (
  tenant_id,
  type,
  title,
  body,
  route,
  entity_type,
  entity_id,
  severity,
  data,
  created_at,
  updated_at
)
select
  expense.tenant_id,
  'expense_recorded',
  'Nuevo gasto registrado',
  coalesce(nullif(trim(expense.expense_number), ''), 'Gasto')
    || ' · '
    || coalesce(
      nullif(trim(expense.supplier_name), ''),
      'Proveedor no informado'
    )
    || case
         when coalesce(expense.total_amount, 0) > 0
           then ' · $'
             || trim(to_char(expense.total_amount, 'FM999G999G999G990'))
         else ''
       end,
  '/accounting/expenses/' || expense.id::text,
  'expense',
  expense.id,
  'info',
  jsonb_build_object(
    'expense_id', expense.id,
    'expense_number', expense.expense_number,
    'supplier_id', expense.supplier_id,
    'supplier_name', expense.supplier_name,
    'supplier_rut', expense.supplier_rut,
    'document_type', expense.document_type,
    'document_number', expense.document_number,
    'issue_date', expense.issue_date,
    'subtotal', expense.subtotal,
    'tax_amount', expense.tax_amount,
    'total_amount', expense.total_amount,
    'currency', expense.currency,
    'posting_status', expense.posting_status,
    'payment_status', expense.payment_status,
    'payment_method', payment_method.name,
    'category_name', category.name,
    'recorded_by_name', public.erp_actor_display_name(
      expense.created_by,
      expense.tenant_id
    ),
    'recorded_at', expense.created_at,
    'backfilled', true
  ),
  expense.created_at,
  greatest(expense.updated_at, expense.created_at)
from public.expenses expense
left join public.payment_methods payment_method
  on payment_method.tenant_id = expense.tenant_id
 and payment_method.id = expense.payment_method_id
left join public.expense_categories category
  on category.tenant_id = expense.tenant_id
 and category.id = expense.category_id
where expense.tenant_id is not null
  and expense.created_at >= now() - interval '7 days'
on conflict (tenant_id, type, entity_type, entity_id) do nothing;
