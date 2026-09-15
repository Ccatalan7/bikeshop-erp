begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.inventory_operation_id', '', true);
select set_config('app.inventory_source_document_type', '', true);
select set_config('app.inventory_source_document_id', '', true);
select set_config('app.inventory_source_channel', '', true);
select set_config('app.inventory_trace_context_stack', '[]', true);

select plan(19);

select ok(
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.sales_payments'::regclass
      and trigger_row.tgname = 'trg_sales_payment_erp_notification'
      and not trigger_row.tgisinternal
      and pg_get_triggerdef(trigger_row.oid)
        like '%AFTER INSERT OR DELETE OR UPDATE OF date, deleted_at ON public.sales_payments%'
  ),
  'the payment notification trigger observes hard and soft reversals'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  ),
  'anonymous callers cannot invoke the notification trigger function'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  ),
  'authenticated callers cannot invoke the notification trigger function'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  ),
  'service role cannot invoke the notification trigger function directly'
);

insert into public.tenants (id, shop_name)
values (
  '98630000-0000-4000-8000-000000000001',
  'Voided Payment Notification Test'
);

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create temp table selected_void_notification_method on commit drop as
select id
from public.payment_methods
where tenant_id = '98630000-0000-4000-8000-000000000001'
order by created_at, id
limit 1;

insert into public.sales_invoices (
  id,
  tenant_id,
  invoice_number,
  customer_name,
  source,
  status,
  subtotal,
  net_amount,
  iva_amount,
  total,
  paid_amount,
  balance,
  tax_treatment,
  items
) values (
  '98630000-0000-4000-8000-000000000010',
  '98630000-0000-4000-8000-000000000001',
  'FV-NOTIFY-VOID-001',
  'Cliente pago anulado',
  'manual_sale',
  'confirmed',
  20000,
  20000,
  0,
  20000,
  0,
  20000,
  'no_tax',
  '[]'::jsonb
);

insert into public.sales_payments (
  id,
  tenant_id,
  invoice_id,
  invoice_reference,
  payment_method_id,
  idempotency_key,
  amount,
  date,
  reference,
  created_at
)
select
  '98630000-0000-4000-8000-000000000030',
  '98630000-0000-4000-8000-000000000001',
  '98630000-0000-4000-8000-000000000010',
  'FV-NOTIFY-VOID-001',
  method.id,
  'notify-void-payment',
  5000,
  '2026-08-17 18:00:00+00',
  'PAY-NOTIFY-VOID-001',
  '2026-08-17 18:01:00+00'
from selected_void_notification_method method;

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  'sales_payment_received',
  'an active payment starts as received activity'
);

select is(
  (
    select title
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  'Nuevo pago recibido',
  'the active payment keeps the received title'
);

update public.erp_notifications
set read_at = '2026-08-17 19:00:00+00'
where entity_type = 'sales_payment'
  and entity_id = '98630000-0000-4000-8000-000000000030';

create temp table void_notification_baseline on commit drop as
select id, created_at, read_at
from public.erp_notifications
where entity_type = 'sales_payment'
  and entity_id = '98630000-0000-4000-8000-000000000030';

delete from public.sales_payments
where id = '98630000-0000-4000-8000-000000000030';

select is(
  (
    select count(*)::integer
    from public.sales_payments
    where id = '98630000-0000-4000-8000-000000000030'
  ),
  0,
  'the audited reversal removes the active payment fact'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  1,
  'reversing a payment keeps one notification identity'
);

select is(
  (
    select type
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  'sales_payment_voided',
  'the durable activity becomes non-financial voided activity'
);

select is(
  (
    select title
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  'Pago anulado',
  'the reversed activity has the requested operator-facing title'
);

select is(
  (
    select severity
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  'warning',
  'a reversal no longer carries received-payment success semantics'
);

select is(
  (
    select route
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  '/sales/invoices/98630000-0000-4000-8000-000000000010',
  'the reversal opens its surviving invoice instead of a deleted payment'
);

select ok(
  (
    select data @> '{"is_voided": true}'::jsonb
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  'the payload explicitly identifies the payment as voided'
);

select ok(
  (
    select nullif(data->>'voided_at', '') is not null
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  'the cancellation timestamp is durable'
);

select ok(
  (
    select notification.created_at = baseline.created_at
       and notification.read_at = baseline.read_at
    from public.erp_notifications notification
    join void_notification_baseline baseline
      on baseline.id = notification.id
  ),
  'conversion preserves immutable recording time and read state'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
      and type = 'sales_payment_received'
  ),
  0,
  'no received-payment row survives to inflate briefing totals'
);

select is(
  (
    select coalesce(sum(amount), 0)::numeric
    from public.sales_payments
    where tenant_id = '98630000-0000-4000-8000-000000000001'
      and deleted_at is null
  ),
  0::numeric,
  'active sales-payment totals exclude the reversed payment'
);

select is(
  (
    select count(*)::integer
    from public.inventory_accounting_operations operation
    where operation.tenant_id = '98630000-0000-4000-8000-000000000001'
      and operation.document_type = 'sales_payment'
      and operation.document_id = '98630000-0000-4000-8000-000000000030'
      and operation.action = 'delete'
      and operation.outcome = 'completed'
  ),
  1,
  'the payment cancellation remains linked to its completed audit operation'
);

select is(
  (
    select data->>'customer_name'
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98630000-0000-4000-8000-000000000030'
  ),
  'Cliente pago anulado',
  'conversion preserves the received-payment disclosure context'
);

select * from finish();
rollback;
