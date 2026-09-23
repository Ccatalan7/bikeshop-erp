begin;

select no_plan();

-- Quien tiene el enlace de un pedido ve el contacto público de la tienda, nunca
-- el correo o teléfono internos de la empresa ni el correo del dueño
-- (20260923200000, hallazgo de la revisión de Codex).

select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);

-- Sin los disparadores de alta, que siembran ajustes del sitio por su cuenta.
set local session_replication_role = replica;

insert into public.tenants (id, shop_name, owner_email, is_active)
values
  ('a17b0000-0000-4000-8000-000000000001', 'Tienda sin contacto público',
   'dueno-privado@example.invalid', true),
  ('a17b0000-0000-4000-8000-000000000002', 'Tienda con contacto público',
   'otro-dueno-privado@example.invalid', true);

set local session_replication_role = origin;

insert into public.companies (tenant_id, name, email, phone, is_default)
values
  ('a17b0000-0000-4000-8000-000000000001', 'Empresa A',
   'interno-a@example.invalid', '+56 9 1111 1111', true),
  ('a17b0000-0000-4000-8000-000000000002', 'Empresa B',
   'interno-b@example.invalid', '+56 9 2222 2222', true);

insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  'a17b0000-0000-4000-8000-000000000099', 'authenticated', 'authenticated',
  'staff-contacto@example.invalid', '', now(), '{}'::jsonb, '{}'::jsonb,
  now(), now()
);

delete from public.user_profiles
where user_id = 'a17b0000-0000-4000-8000-000000000099';
insert into public.user_profiles (user_id, tenant_id, role, permissions,
  is_active)
values ('a17b0000-0000-4000-8000-000000000099',
  'a17b0000-0000-4000-8000-000000000001', 'admin', '{}'::jsonb, true);

-- El disparador de stock anota el ajuste con auth.uid().
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', 'a17b0000-0000-4000-8000-000000000099',
  'role', 'authenticated')::text, true);
select set_config('request.jwt.claim.sub',
  'a17b0000-0000-4000-8000-000000000099', true);

insert into public.products (
  id, tenant_id, name, sku, price, website_price, cost, tax_rate,
  product_type, is_service, purchase_treatment, track_stock,
  inventory_qty, stock_quantity, min_stock_level, max_stock_level,
  is_active, is_published, show_on_website
) values
  ('a17b0000-0000-4000-8000-000000000011',
   'a17b0000-0000-4000-8000-000000000001', 'Cámara A', 'CONT-A', 1190, 990,
   400, 19, 'product', false, 'inventory', true, 10, 10, 0, 100, true, true,
   true),
  ('a17b0000-0000-4000-8000-000000000012',
   'a17b0000-0000-4000-8000-000000000002', 'Cámara B', 'CONT-B', 1190, 990,
   400, 19, 'product', false, 'inventory', true, 10, 10, 0, 100, true, true,
   true);

insert into public.website_settings (tenant_id, key, value)
select tenant_id, setting.key, setting.value
from (values
  ('a17b0000-0000-4000-8000-000000000001'::uuid),
  ('a17b0000-0000-4000-8000-000000000002'::uuid)
) tenant(tenant_id)
cross join (values
  ('payment_transfer_bank_name', 'Banco de prueba'),
  ('payment_transfer_account_type', 'Cuenta corriente'),
  ('payment_transfer_account_number', '000111222'),
  ('payment_transfer_account_holder', 'Titular de prueba'),
  ('payment_transfer_rut', '11.111.111-1')
) setting(key, value);

insert into public.website_settings (tenant_id, key, value)
values
  ('a17b0000-0000-4000-8000-000000000002', 'contact_email',
   'ventas-b@example.invalid'),
  ('a17b0000-0000-4000-8000-000000000002', 'contact_phone',
   '+56 32 333 3333');

create temp table contacto_resultados (
  name text primary key,
  value jsonb not null
) on commit drop;
grant select, insert on contacto_resultados to anon;

-- El comprador llega sin sesión.
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
set local role anon;

insert into contacto_resultados (name, value)
select 'pedido_a', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', 'a17b0000-0000-4000-8000-000000000001',
    'checkout_idempotency_key', 'a17b0000-0000-4000-8000-00000000a001',
    'customer_email', 'comprador-a@example.invalid',
    'customer_name', 'Comprador A',
    'delivery_type', 'pickup',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', 'a17b0000-0000-4000-8000-000000000011', 'quantity', 1))
);

insert into contacto_resultados (name, value)
select 'pedido_b', public.create_public_online_order_with_access(
  jsonb_build_object(
    'tenant_id', 'a17b0000-0000-4000-8000-000000000002',
    'checkout_idempotency_key', 'a17b0000-0000-4000-8000-00000000b001',
    'customer_email', 'comprador-b@example.invalid',
    'customer_name', 'Comprador B',
    'delivery_type', 'pickup',
    'payment_method', 'transfer'
  ),
  jsonb_build_array(jsonb_build_object(
    'product_id', 'a17b0000-0000-4000-8000-000000000012', 'quantity', 1))
);

insert into contacto_resultados (name, value)
select 'lectura_a', public.get_public_online_order_by_access_token(
  (select value->>'access_token' from contacto_resultados
    where name = 'pedido_a'));

insert into contacto_resultados (name, value)
select 'lectura_b', public.get_public_online_order_by_access_token(
  (select value->>'access_token' from contacto_resultados
    where name = 'pedido_b'));

reset role;

select ok(
  (select value->'storefront' ? 'displayName'
     and not (value->'storefront' ? 'supportEmail')
     and not (value->'storefront' ? 'supportPhone')
   from contacto_resultados where name = 'lectura_a'),
  'sin contacto público, el pedido no muestra correo ni teléfono');

select ok(
  (select value::text not like '%dueno-privado@example.invalid%'
     and value::text not like '%interno-a@example.invalid%'
     and value::text not like '%1111 1111%'
   from contacto_resultados where name = 'lectura_a'),
  'ni el correo del dueño ni el contacto interno de la empresa salen al enlace');

select is(
  (select value #>> '{storefront,supportEmail}'
   from contacto_resultados where name = 'lectura_b'),
  'ventas-b@example.invalid',
  'con contacto público, el pedido muestra ese correo');

select is(
  (select value #>> '{storefront,supportPhone}'
   from contacto_resultados where name = 'lectura_b'),
  '+56 32 333 3333',
  'con contacto público, el pedido muestra ese teléfono');

select ok(
  (select value::text not like '%interno-b@example.invalid%'
     and value::text not like '%otro-dueno-privado@example.invalid%'
   from contacto_resultados where name = 'lectura_b'),
  'aun con contacto público, los datos internos no salen');

select * from finish();
rollback;
