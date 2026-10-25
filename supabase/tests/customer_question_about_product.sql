begin;

select no_plan();

-- «Pregunta por este producto» (2026-10-24): a product page sends the
-- customer's question by the portal's chat as a consultation about that
-- product (create_customer_support_request with the `product` context), so
-- the ERP's conversation opens it. The store's own product only.

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

insert into public.tenants (id, shop_name, is_active) values
  ('a6080000-0000-4000-8000-000000000001', 'Tienda de la pregunta', true),
  ('a6080000-0000-4000-8000-000000000002', 'Otra tienda', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a6080000-0000-4000-8000-000000000191',
  'authenticated', 'authenticated', 'pregunta@example.invalid', '', now(),
  '{}'::jsonb,
  jsonb_build_object(
    'account_type', 'public_store_customer',
    'customer_tenant_id', 'a6080000-0000-4000-8000-000000000001'
  ),
  now(), now()
);

insert into public.customers (
  id, tenant_id, name, email, phone, auth_user_id, is_active
) values (
  'a6080000-0000-4000-8000-000000000111',
  'a6080000-0000-4000-8000-000000000001',
  'Cliente de prueba', 'pregunta@example.invalid', '+56900000000',
  'a6080000-0000-4000-8000-000000000191', true
);

set local session_replication_role = replica;
insert into public.products (
  id, tenant_id, name, sku, price, cost, tax_rate, product_type, is_service,
  purchase_treatment, track_stock, inventory_qty, stock_quantity, is_active
) values
  ('a6080000-0000-4000-8000-000000000701', 'a6080000-0000-4000-8000-000000000001',
   'Cámara aro 29 válvula francesa', 'A608-701', 6490, 1000, 19, 'product',
   false, 'inventory', true, 0, 0, true),
  ('a6080000-0000-4000-8000-000000000702', 'a6080000-0000-4000-8000-000000000002',
   'Cámara de otra tienda', 'A608-702', 6490, 1000, 19, 'product',
   false, 'inventory', true, 0, 0, true);
set local session_replication_role = origin;

select set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub', 'a6080000-0000-4000-8000-000000000191',
    'role', 'authenticated'
  )::text,
  true
);
select set_config(
  'request.jwt.claim.sub',
  'a6080000-0000-4000-8000-000000000191',
  true
);
set local role authenticated;

select is(
  public.create_customer_support_request(
    'a6080000-0000-4000-8000-000000000001',
    'Hola, les escribo por este producto: Cámara aro 29 válvula francesa',
    'product',
    'a6080000-0000-4000-8000-000000000701',
    'web:pregunta-producto-1'
  )->>'status',
  'pending',
  'a question from a product page opens a consultation'
);

select is(
  (select conversation.context_type || ':' || conversation.context_id
     from public.conversations conversation
    where conversation.created_by = 'a6080000-0000-4000-8000-000000000191'
      and conversation.channel = 'website_portal'),
  'product:a6080000-0000-4000-8000-000000000701',
  'the consultation is about the product the ERP opens'
);

select throws_ok(
  $$select public.create_customer_support_request(
      'a6080000-0000-4000-8000-000000000001',
      'Hola, les escribo por este producto',
      'product',
      'a6080000-0000-4000-8000-000000000702',
      'web:pregunta-producto-ajeno'
    )$$,
  '42501',
  'Customer cannot reference this messaging context',
  'another store''s product is refused'
);

reset role;

select * from finish();
rollback;
