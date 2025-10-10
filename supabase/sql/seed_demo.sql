-- Seed data for Vinabike ERP demo
-- Run after core_schema.sql once per environment.

insert into public.companies (id, name, rut, address)
values ('11111111-1111-1111-1111-111111111111', 'Vinabike Demo Ltda.', '76.123.456-7', 'Av. Providencia 1234, Santiago')
on conflict (id) do nothing;

insert into public.users_profiles (id, company_id, full_name, email, role)
select
  u.id,
  '11111111-1111-1111-1111-111111111111',
  coalesce(u.raw_user_meta_data->>'full_name', 'Admin Demo'),
  u.email,
  'admin'
from auth.users u
where u.email = 'admin@vinabike.cl'
on conflict (id) do nothing;

insert into public.customers (company_id, name, rut, email, phone, city)
values
  ('11111111-1111-1111-1111-111111111111', 'Juan Pérez', '12.345.678-9', 'juan.perez@example.com', '+56 9 9876 5432', 'Santiago'),
  ('11111111-1111-1111-1111-111111111111', 'Camila Rojas', '98.765.432-1', 'camila.rojas@example.com', '+56 9 1234 5678', 'Valparaíso')
on conflict (email) do nothing;

insert into public.products (company_id, name, sku, description, price, cost, inventory_qty)
values
  ('11111111-1111-1111-1111-111111111111', 'Bicicleta Urbana 700', 'BIKE-700', 'Bicicleta urbana de aluminio', 349990, 210000, 10),
  ('11111111-1111-1111-1111-111111111111', 'Kit Mantención Básica', 'KIT-MANT-01', 'Kit de limpieza y lubricación', 24990, 12000, 50),
  ('11111111-1111-1111-1111-111111111111', 'Servicio Ajuste Transmisión', 'SRV-DRIVETRAIN', 'Servicio de ajuste transmisión completa', 29990, 0, 0)
on conflict (sku) do nothing;

insert into public.categories (company_id, name, description)
values
  ('11111111-1111-1111-1111-111111111111', 'Bicicletas', 'Bicicletas completas'),
  ('11111111-1111-1111-1111-111111111111', 'Accesorios', 'Accesorios y complementos'),
  ('11111111-1111-1111-1111-111111111111', 'Servicios', 'Servicios técnicos')
on conflict (company_id, name) do nothing;

update public.products p
   set category_id = c.id
  from public.categories c
 where p.company_id = '11111111-1111-1111-1111-111111111111'
   and c.company_id = p.company_id
   and ((p.sku = 'BIKE-700' and c.name = 'Bicicletas')
     or (p.sku = 'KIT-MANT-01' and c.name = 'Accesorios')
     or (p.sku = 'SRV-DRIVETRAIN' and c.name = 'Servicios'));

insert into public.warehouses (company_id, name, location)
select
  '11111111-1111-1111-1111-111111111111',
  v.name,
  v.location
from (values
    ('Bodega Principal', 'Santiago'),
    ('Bodega Taller', 'Providencia')
) as v(name, location)
where not exists (
  select 1 from public.warehouses w
  where w.company_id = '11111111-1111-1111-1111-111111111111'
    and w.name = v.name
);

insert into public.sales_orders (company_id, customer_id, source, status, subtotal, tax_amount, total)
select
  '11111111-1111-1111-1111-111111111111', id, 'POS', 'issued', 299990, 56998, 356988
from public.customers
where email = 'juan.perez@example.com'
  and not exists (
    select 1 from public.sales_orders so
    where so.company_id = '11111111-1111-1111-1111-111111111111'
      and so.source = 'POS'
      and so.total = 356988
  )
limit 1;

insert into public.sales_order_items (order_id, product_id, description, quantity, unit_price, tax_rate, total)
select
  so.id,
  p.id,
  p.name,
  1,
  299990,
  19,
  299990
from public.sales_orders so
join public.products p on p.sku = 'BIKE-700'
where so.company_id = '11111111-1111-1111-1111-111111111111'
  and not exists (
    select 1 from public.sales_order_items soi
    where soi.order_id = so.id
      and soi.product_id = p.id
  )
limit 1;

insert into public.payments (order_id, amount, method)
select id, total, 'card'
from public.sales_orders
where company_id = '11111111-1111-1111-1111-111111111111'
  and not exists (
    select 1 from public.payments pay
    where pay.order_id = sales_orders.id
  )
limit 1;
