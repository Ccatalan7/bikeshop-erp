-- Core data schema for Vinabike ERP.
-- Run this script in the Supabase SQL editor to provision base tables.
-- UUID columns default to gen_random_uuid(); ensure the extension is enabled first.

create extension if not exists "pgcrypto";

create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  email text unique,
  created_at timestamp with time zone not null default now()
);

create table if not exists products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sku text unique,
  price numeric(12,2) not null default 0,
  cost numeric(12,2) not null default 0,
  inventory_qty integer not null default 0,
  created_at timestamp with time zone not null default now()
);

create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references customers(id) on delete set null,
  source text not null check (source in ('POS', 'Website')),
  order_date timestamp with time zone not null default now(),
  total numeric(12,2) not null default 0,
  created_at timestamp with time zone not null default now()
);

create table if not exists order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  product_id uuid not null references products(id) on delete restrict,
  quantity integer not null,
  price numeric(12,2) not null,
  created_at timestamp with time zone not null default now()
);

create or replace function public.handle_order_item_insert()
returns trigger as $$
begin
  update products
     set inventory_qty = inventory_qty - new.quantity
   where id = new.product_id;
  return new;
end;
$$ language plpgsql;

create or replace trigger trg_order_item_insert
  after insert on order_items
  for each row execute procedure public.handle_order_item_insert();

-- Function to handle sales item updates
create or replace function public.handle_sales_item()
returns trigger as $$
declare
  v_company_id uuid;
  v_warehouse_id uuid;
begin
  select company_id
    into v_company_id
    from public.sales_orders
   where id = new.order_id;

  select w.id
    into v_warehouse_id
    from public.warehouses w
   where w.company_id = v_company_id
   order by w.created_at
   limit 1;

  if v_warehouse_id is null then
    raise exception 'No default warehouse configured for company %', v_company_id;
  end if;

  update public.products
     set inventory_qty = inventory_qty - new.quantity
   where id = new.product_id
     and is_service = false;

  insert into public.stock_movements (product_id, warehouse_id, movement_type, quantity, reference)
  values (new.product_id, v_warehouse_id, 'outbound', new.quantity, 'sales_order:' || new.order_id);

  return new;
end;
$$ language plpgsql;

-- Function to handle purchase item updates
create or replace function public.handle_purchase_item()
returns trigger as $$
declare
  v_company_id uuid;
  v_warehouse_id uuid;
begin
  select company_id
    into v_company_id
    from public.purchase_orders
   where id = new.purchase_order_id;

  select w.id
    into v_warehouse_id
    from public.warehouses w
   where w.company_id = v_company_id
   order by w.created_at
   limit 1;

  if v_warehouse_id is null then
    raise exception 'No default warehouse configured for company %', v_company_id;
  end if;

  update public.products
     set inventory_qty = inventory_qty + new.quantity
   where id = new.product_id
     and is_service = false;

  insert into public.stock_movements (product_id, warehouse_id, movement_type, quantity, reference)
  values (new.product_id, v_warehouse_id, 'inbound', new.quantity, 'purchase_order:' || new.purchase_order_id);

  return new;
end;
$$ language plpgsql;
-- Basic RLS scaffolding: enable on each table; policies to be tailored per role.
alter table customers enable row level security;
alter table products enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;

-- Example policies; replace with final role-aware versions.
create policy "Admins read all" on customers
  for select using (auth.role() = 'authenticated');
create policy "Admins read all" on products
  for select using (auth.role() = 'authenticated');
create policy "Admins read all" on orders
  for select using (auth.role() = 'authenticated');
create policy "Admins read all" on order_items
  for select using (auth.role() = 'authenticated');

-- TODO: add role-specific policies matching Sales, Inventory, HR, Mechanic, Cashier profiles.
