-- The durable ERP alert of a web order that becomes paid
-- (20261009020000): one per order, a refund warning when the order was
-- already cancelled, nothing for a transfer the team confirmed, and never a
-- blocked payment. The trigger function runs on a stand-in table with the
-- columns it reads, so the rules are tested without the checkout pipeline.
begin;

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

select plan(9);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.create_online_order_paid_erp_notification()',
    'EXECUTE'
  ),
  'clients cannot invoke the paid alert function'
);

insert into public.tenants (id, shop_name)
values ('9e260000-0000-4000-8000-000000000001', 'Paid alert tenant');

create temporary table paid_alert_orders (
  id uuid primary key,
  tenant_id uuid not null,
  order_number text,
  customer_name text,
  total numeric,
  payment_method text,
  payment_status text,
  delivery_type text,
  status text
) on commit drop;

create trigger paid_alert_orders_trigger
  after update of payment_status on paid_alert_orders
  for each row
  execute function public.create_online_order_paid_erp_notification();

insert into paid_alert_orders values
  ('9e260000-0000-4000-8000-000000000011',
   '9e260000-0000-4000-8000-000000000001',
   'WEB-PAID-1', 'Camila Rojas', 45990, 'mercadopago', 'pending',
   'pickup', 'pending'),
  ('9e260000-0000-4000-8000-000000000012',
   '9e260000-0000-4000-8000-000000000001',
   'WEB-PAID-2', 'Pedro Soto', 12990, 'mercadopago', 'pending',
   'shipping', 'cancelled'),
  ('9e260000-0000-4000-8000-000000000013',
   '9e260000-0000-4000-8000-000000000001',
   'WEB-PAID-3', 'Ana Díaz', 9990, 'transfer', 'pending',
   'pickup', 'confirmed'),
  -- Unknown tenant: the alert insert fails its foreign key.
  ('9e260000-0000-4000-8000-000000000014',
   '9e260000-0000-4000-8000-0000000000ff',
   'WEB-PAID-4', 'Luis Mora', 5990, 'mercadopago', 'pending',
   'pickup', 'pending');

update paid_alert_orders
   set payment_status = 'paid'
 where id in (
   '9e260000-0000-4000-8000-000000000011',
   '9e260000-0000-4000-8000-000000000012',
   '9e260000-0000-4000-8000-000000000013'
 );

select is(
  (
    select type || '|' || title || '|' || severity || '|' || route
      from public.erp_notifications
     where entity_id = '9e260000-0000-4000-8000-000000000011'
  ),
  'online_order_paid|Venta online pagada|success|/website/orders?order=9e260000-0000-4000-8000-000000000011',
  'a paid Mercado Pago order leaves one sale alert that opens the order'
);
select ok(
  (
    select body like 'WEB-PAID-1 · Camila Rojas · $45%990'
      from public.erp_notifications
     where entity_id = '9e260000-0000-4000-8000-000000000011'
  ),
  'the alert names the order, the customer and the amount'
);
select is(
  (
    select type || '|' || severity
      from public.erp_notifications
     where entity_id = '9e260000-0000-4000-8000-000000000012'
  ),
  'online_order_paid_after_cancellation|warning',
  'a payment for a cancelled order is a refund warning, not a sale'
);
select is(
  (
    select count(*)::integer
      from public.erp_notifications
     where entity_id = '9e260000-0000-4000-8000-000000000013'
  ),
  0,
  'a transfer the team confirmed leaves no alert'
);

update paid_alert_orders
   set payment_status = 'pending'
 where id = '9e260000-0000-4000-8000-000000000011';
update paid_alert_orders
   set payment_status = 'paid'
 where id = '9e260000-0000-4000-8000-000000000011';

select is(
  (
    select count(*)::integer
      from public.erp_notifications
     where entity_id = '9e260000-0000-4000-8000-000000000011'
  ),
  1,
  'paying the same order again keeps a single alert'
);

select lives_ok(
  $$
    update paid_alert_orders
       set payment_status = 'paid'
     where id = '9e260000-0000-4000-8000-000000000014'
  $$,
  'an alert that cannot be recorded never blocks the payment'
);
select is(
  (
    select payment_status
      from paid_alert_orders
     where id = '9e260000-0000-4000-8000-000000000014'
  ),
  'paid',
  'the payment stays recorded when its alert failed'
);
select is(
  (
    select count(*)::integer
      from public.erp_notifications
     where entity_id = '9e260000-0000-4000-8000-000000000014'
  ),
  0,
  'the failed alert left nothing half written'
);

select * from finish();

rollback;
