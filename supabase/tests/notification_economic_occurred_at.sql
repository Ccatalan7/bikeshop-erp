begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
select set_config('app.inventory_operation_id', '', true);
select set_config('app.inventory_source_document_type', '', true);
select set_config('app.inventory_source_document_id', '', true);
select set_config('app.inventory_source_channel', '', true);
select set_config('app.inventory_trace_context_stack', '[]', true);

select plan(26);

select has_column(
  'public',
  'erp_notifications',
  'occurred_at',
  'notifications expose a first-class economic timestamp'
);

select col_type_is(
  'public',
  'erp_notifications',
  'occurred_at',
  'timestamp with time zone',
  'economic notification time keeps timezone evidence'
);

select ok(
  (
    select attribute.attnotnull
    from pg_attribute attribute
    where attribute.attrelid = 'public.erp_notifications'::regclass
      and attribute.attname = 'occurred_at'
      and not attribute.attisdropped
  ),
  'every durable notification has an economic timestamp'
);

select is(
  (
    select pg_get_expr(default_row.adbin, default_row.adrelid)
    from pg_attrdef default_row
    join pg_attribute attribute
      on attribute.attrelid = default_row.adrelid
     and attribute.attnum = default_row.adnum
    where default_row.adrelid = 'public.erp_notifications'::regclass
      and attribute.attname = 'occurred_at'
  ),
  'now()',
  'non-economic notification sources fall back to recording time'
);

select has_index(
  'public',
  'erp_notifications',
  'idx_erp_notifications_tenant_occurred_at',
  'tenant economic-period reads have a bounded index'
);

select ok(
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.sales_payments'::regclass
      and trigger_row.tgname = 'trg_sales_payment_erp_notification'
      and not trigger_row.tgisinternal
      and pg_get_triggerdef(trigger_row.oid)
        like '%AFTER INSERT OR UPDATE OF date ON public.sales_payments%'
  ),
  'sales-payment notifications synchronize when the payment date changes'
);

select ok(
  exists (
    select 1
    from pg_trigger trigger_row
    where trigger_row.tgrelid = 'public.expenses'::regclass
      and trigger_row.tgname = 'trg_expense_erp_notification'
      and not trigger_row.tgisinternal
      and pg_get_triggerdef(trigger_row.oid)
        like '%AFTER INSERT OR UPDATE OF issue_date ON public.expenses%'
  ),
  'expense notifications synchronize when the issue date changes'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  ),
  'anonymous callers cannot invoke the sales-payment trigger function'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  ),
  'authenticated callers cannot invoke the sales-payment trigger function'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.create_sales_payment_erp_notification()',
    'EXECUTE'
  ),
  'service role cannot invoke the sales-payment trigger function directly'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.create_expense_erp_notification()',
    'EXECUTE'
  ),
  'anonymous callers cannot invoke the expense trigger function'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_expense_erp_notification()',
    'EXECUTE'
  ),
  'authenticated callers cannot invoke the expense trigger function'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.create_expense_erp_notification()',
    'EXECUTE'
  ),
  'service role cannot invoke the expense trigger function directly'
);

insert into public.tenants (id, shop_name)
values (
  '98620000-0000-4000-8000-000000000001',
  'Notification Economic Date Test'
);

-- Tenant bootstrap helpers can set a transaction-local subject. The fixture
-- writes intentionally run as postgres without an employee identity.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

create temp table selected_notification_method on commit drop as
select id
from public.payment_methods
where tenant_id = '98620000-0000-4000-8000-000000000001'
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
  '98620000-0000-4000-8000-000000000010',
  '98620000-0000-4000-8000-000000000001',
  'FV-NOTIFY-DATE-001',
  'Cliente fecha económica',
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

insert into public.expenses (
  id,
  tenant_id,
  expense_number,
  supplier_name,
  document_type,
  issue_date,
  posting_status,
  payment_status,
  subtotal,
  tax_amount,
  total_amount,
  amount_paid,
  balance,
  created_at
) values (
  '98620000-0000-4000-8000-000000000020',
  '98620000-0000-4000-8000-000000000001',
  'GTO-NOTIFY-DATE-001',
  'Proveedor fecha económica',
  'invoice',
  '2026-08-02 15:00:00+00',
  'draft',
  'pending',
  10000,
  0,
  10000,
  0,
  10000,
  '2026-08-12 15:00:00+00'
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
  '98620000-0000-4000-8000-000000000030',
  '98620000-0000-4000-8000-000000000001',
  '98620000-0000-4000-8000-000000000010',
  'FV-NOTIFY-DATE-001',
  method.id,
  'notify-economic-date-payment',
  5000,
  '2026-08-01 16:00:00+00',
  'PAY-NOTIFY-DATE-001',
  '2026-08-12 16:00:00+00'
from selected_notification_method method;

select is(
  (
    select occurred_at
    from public.erp_notifications
    where entity_type = 'expense'
      and entity_id = '98620000-0000-4000-8000-000000000020'
  ),
  '2026-08-02 15:00:00+00'::timestamptz,
  'a backdated expense keeps its issue date as economic time'
);

select ok(
  (
    select created_at > occurred_at
    from public.erp_notifications
    where entity_type = 'expense'
      and entity_id = '98620000-0000-4000-8000-000000000020'
  ),
  'a backdated expense remains registered in the current notification timeline'
);

select is(
  (
    select occurred_at
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98620000-0000-4000-8000-000000000030'
  ),
  '2026-08-01 16:00:00+00'::timestamptz,
  'a backdated sales payment keeps its payment date as economic time'
);

select ok(
  (
    select created_at > occurred_at
    from public.erp_notifications
    where entity_type = 'sales_payment'
      and entity_id = '98620000-0000-4000-8000-000000000030'
  ),
  'a backdated sales payment remains registered in the current notification timeline'
);

update public.erp_notifications
set read_at = '2026-08-12 20:00:00+00'
where tenant_id = '98620000-0000-4000-8000-000000000001'
  and entity_id in (
    '98620000-0000-4000-8000-000000000020',
    '98620000-0000-4000-8000-000000000030'
  );

create temp table notification_recording_baseline on commit drop as
select entity_id, created_at, read_at
from public.erp_notifications
where tenant_id = '98620000-0000-4000-8000-000000000001'
  and entity_id in (
    '98620000-0000-4000-8000-000000000020',
    '98620000-0000-4000-8000-000000000030'
  );

update public.expenses
set issue_date = '2026-08-03 17:00:00+00'
where id = '98620000-0000-4000-8000-000000000020';

update public.sales_payments
set date = '2026-08-04 18:00:00+00'
where id = '98620000-0000-4000-8000-000000000030';

select is(
  (
    select occurred_at
    from public.erp_notifications
    where entity_id = '98620000-0000-4000-8000-000000000020'
  ),
  '2026-08-03 17:00:00+00'::timestamptz,
  'correcting an expense date synchronizes its economic timestamp'
);

select is(
  (
    select (data->>'issue_date')::timestamptz
    from public.erp_notifications
    where entity_id = '98620000-0000-4000-8000-000000000020'
  ),
  '2026-08-03 17:00:00+00'::timestamptz,
  'correcting an expense date synchronizes its disclosure payload'
);

select ok(
  (
    select notification.created_at = baseline.created_at
       and notification.read_at = baseline.read_at
    from public.erp_notifications notification
    join notification_recording_baseline baseline
      on baseline.entity_id = notification.entity_id
    where notification.entity_id =
      '98620000-0000-4000-8000-000000000020'
  ),
  'expense date correction preserves registration time and read state'
);

select is(
  (
    select occurred_at
    from public.erp_notifications
    where entity_id = '98620000-0000-4000-8000-000000000030'
  ),
  '2026-08-04 18:00:00+00'::timestamptz,
  'correcting a sales-payment date synchronizes its economic timestamp'
);

select is(
  (
    select (data->>'payment_date')::timestamptz
    from public.erp_notifications
    where entity_id = '98620000-0000-4000-8000-000000000030'
  ),
  '2026-08-04 18:00:00+00'::timestamptz,
  'correcting a sales-payment date synchronizes its disclosure payload'
);

select ok(
  (
    select notification.created_at = baseline.created_at
       and notification.read_at = baseline.read_at
    from public.erp_notifications notification
    join notification_recording_baseline baseline
      on baseline.entity_id = notification.entity_id
    where notification.entity_id =
      '98620000-0000-4000-8000-000000000030'
  ),
  'sales-payment date correction preserves registration time and read state'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where tenant_id = '98620000-0000-4000-8000-000000000001'
      and entity_id = '98620000-0000-4000-8000-000000000020'
  ),
  1,
  'an expense date correction does not duplicate its notification'
);

select is(
  (
    select count(*)::integer
    from public.erp_notifications
    where tenant_id = '98620000-0000-4000-8000-000000000001'
      and entity_id = '98620000-0000-4000-8000-000000000030'
  ),
  1,
  'a sales-payment date correction does not duplicate its notification'
);

insert into public.erp_notifications (
  tenant_id,
  type,
  title,
  entity_type,
  entity_id
) values (
  '98620000-0000-4000-8000-000000000001',
  'test_registered_event',
  'Evento no económico',
  'test_event',
  '98620000-0000-4000-8000-000000000040'
);

select is(
  (
    select occurred_at
    from public.erp_notifications
    where entity_id = '98620000-0000-4000-8000-000000000040'
  ),
  (
    select created_at
    from public.erp_notifications
    where entity_id = '98620000-0000-4000-8000-000000000040'
  ),
  'a non-economic source defaults occurred_at to its registration time'
);

select * from finish();
rollback;
