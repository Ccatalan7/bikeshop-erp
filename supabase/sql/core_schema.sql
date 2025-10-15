-- Core data schema for Vinabike ERP.
-- Run this script in the Supabase SQL editor to provision base tables.
-- UUID columns default to gen_random_uuid(); ensure the extension is enabled first.

create extension if not exists "pgcrypto";

-- CRITICAL: Nuclear cleanup for purchase_payments type caching issue
-- This MUST run first before any table or function definitions
do $$
begin
  -- Drop all triggers
  drop trigger if exists trg_purchase_payments_change on purchase_payments cascade;
  
  -- Drop all functions (all possible signatures)
  drop function if exists handle_purchase_payment_change() cascade;
  drop function if exists create_purchase_payment_journal_entry(uuid) cascade;
  drop function if exists create_purchase_payment_journal_entry(purchase_payments) cascade;
  drop function if exists delete_purchase_payment_journal_entry(uuid) cascade;
  
  -- Drop OLD trigger version of recalculate function (the one causing the error!)
  drop function if exists recalculate_purchase_invoice_payments() cascade;
  
  -- Drop old columns if they exist
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'purchase_payments' and column_name = 'payment_date'
  ) then
    alter table purchase_payments drop column payment_date cascade;
  end if;
  
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'purchase_payments' and column_name = 'bank_account_id'
  ) then
    alter table purchase_payments drop column bank_account_id cascade;
  end if;
  
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'purchase_payments' and column_name = 'purchase_invoice_id'
  ) then
    alter table purchase_payments drop column purchase_invoice_id cascade;
  end if;
  
  raise notice 'Nuclear cleanup complete for purchase_payments';
exception
  when others then
    raise notice 'Cleanup error (may be safe to ignore): %', sqlerrm;
end $$;

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

-- Migration: Add missing columns to products table
do $$
begin
  -- Add barcode if not exists
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'barcode') then
    alter table products add column barcode text;
  end if;

  -- Add stock_quantity (alias for inventory_qty)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'stock_quantity') then
    alter table products add column stock_quantity integer not null default 0;
  end if;

  -- Add min_stock_level
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'min_stock_level') then
    alter table products add column min_stock_level integer not null default 5;
  end if;

  -- Add max_stock_level
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'max_stock_level') then
    alter table products add column max_stock_level integer not null default 100;
  end if;

  -- Add image_url
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'image_url') then
    alter table products add column image_url text;
  end if;

  -- Add image_urls array
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'image_urls') then
    alter table products add column image_urls text[] not null default array[]::text[];
  end if;

  -- Add description
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'description') then
    alter table products add column description text;
  end if;

  -- Add category (enum/text)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'category') then
    alter table products add column category text not null default 'other';
  end if;

  -- Add category_id (FK to categories table)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'category_id') then
    alter table products add column category_id uuid;
  end if;

  -- Add category_name (resolved name)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'category_name') then
    alter table products add column category_name text;
  end if;

  -- Add brand
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'brand') then
    alter table products add column brand text;
  end if;

  -- Add model
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'model') then
    alter table products add column model text;
  end if;

  -- Add specifications (jsonb)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'specifications') then
    alter table products add column specifications jsonb not null default '{}'::jsonb;
  end if;

  -- Add tags array
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'tags') then
    alter table products add column tags text[] not null default array[]::text[];
  end if;

  -- Add unit
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'unit') then
    alter table products add column unit text not null default 'unit';
  end if;

  -- Add weight
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'weight') then
    alter table products add column weight numeric(10,2) not null default 0;
  end if;

  -- Add track_stock
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'track_stock') then
    alter table products add column track_stock boolean not null default true;
  end if;

  -- Add is_active
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'is_active') then
    alter table products add column is_active boolean not null default true;
  end if;

  -- Add product_type (product or service)
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'product_type') then
    alter table products add column product_type text not null default 'product';
  end if;

  -- Add updated_at
  if not exists (select 1 from information_schema.columns where table_name = 'products' and column_name = 'updated_at') then
    alter table products add column updated_at timestamp with time zone not null default now();
  end if;

  -- Sync inventory_qty to stock_quantity for existing records
  update products set stock_quantity = inventory_qty where stock_quantity = 0 and inventory_qty > 0;
end $$;
 
create table if not exists suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  rut text,
  email text,
  phone text,
  address text,
  city text,
  region text,
  comuna text,
  contact_person text,
  website text,
  type text not null default 'local',
  bank_details jsonb not null default '{}'::jsonb,
  payment_terms text not null default 'net30',
  notes text,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

alter table public.suppliers
  add column if not exists rut text,
  add column if not exists email text,
  add column if not exists phone text,
  add column if not exists address text,
  add column if not exists city text,
  add column if not exists region text,
  add column if not exists comuna text,
  add column if not exists contact_person text,
  add column if not exists website text,
  add column if not exists type text not null default 'local',
  add column if not exists bank_details jsonb not null default '{}'::jsonb,
  add column if not exists payment_terms text not null default 'net30',
  add column if not exists notes text,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'suppliers'
      and t.tgname = 'trg_suppliers_updated_at'
  ) then
    create trigger trg_suppliers_updated_at
      before update on suppliers
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create index if not exists idx_suppliers_name on suppliers using gin (to_tsvector('spanish', coalesce(name, '')));

create table if not exists accounts (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  type text not null
    check (type in ('asset','liability','equity','income','expense','tax')),
  category text not null
    check (category in (
      'currentAsset','fixedAsset','otherAsset',
      'currentLiability','longTermLiability',
      'capital','retainedEarnings',
      'operatingIncome','nonOperatingIncome',
      'costOfGoodsSold','operatingExpense','financialExpense',
      'taxPayable','taxReceivable','taxExpense'
    )),
  description text,
  parent_id uuid references accounts(id),
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

alter table public.accounts
  add column if not exists code text,
  add column if not exists name text,
  add column if not exists type text,
  add column if not exists category text,
  add column if not exists description text,
  add column if not exists parent_id uuid,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  begin
    alter table public.accounts
      alter column code set not null;
  exception when others then
    null;
  end;

  begin
    alter table public.accounts
      alter column name set not null;
  exception when others then
    null;
  end;
end $$;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.accounts'::regclass
       and contype = 'u'
       and conname = 'accounts_code_key'
  ) then
    alter table public.accounts
      add constraint accounts_code_key unique (code);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.accounts'::regclass
       and contype = 'c'
       and conname = 'accounts_type_check'
  ) then
    alter table public.accounts
      add constraint accounts_type_check
        check (type in ('asset','liability','equity','income','expense','tax'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.accounts'::regclass
       and contype = 'c'
       and conname = 'accounts_category_check'
  ) then
    alter table public.accounts
      add constraint accounts_category_check
        check (category in (
          'currentAsset','fixedAsset','otherAsset',
          'currentLiability','longTermLiability',
          'capital','retainedEarnings',
          'operatingIncome','nonOperatingIncome',
          'costOfGoodsSold','operatingExpense','financialExpense',
          'taxPayable','taxReceivable','taxExpense'
        ));
  end if;
end $$;

do $$
begin
  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'accounts'
       and column_name = 'parent_id'
  ) then
    if not exists (
      select 1
        from pg_constraint
       where conrelid = 'public.accounts'::regclass
         and contype = 'f'
         and conname = 'accounts_parent_id_fkey'
    ) then
      alter table public.accounts
        add constraint accounts_parent_id_fkey
          foreign key (parent_id)
          references public.accounts(id)
          on delete set null;
    end if;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'accounts'
      and t.tgname = 'trg_accounts_updated_at'
  ) then
    create trigger trg_accounts_updated_at
      before update on accounts
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

do $$
begin
  begin
    alter table public.accounts drop column if exists company_id;
  exception when others then
    begin
      alter table public.accounts alter column company_id drop not null;
    exception when others then
      null;
    end;
  end;
end $$;

create or replace function public.migrate_accounts_to_uuid()
returns void as $$
declare
  v_accounts_id_is_uuid boolean;
  v_accounts_parent_type text;
  v_journal_account_type text;
begin
  select case when data_type = 'uuid' then true else false end
    into v_accounts_id_is_uuid
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'accounts'
     and column_name = 'id'
   limit 1;

  if coalesce(v_accounts_id_is_uuid, false) then
    return;
  end if;

  if not exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'accounts'
       and column_name = 'id_uuid'
  ) then
    alter table public.accounts add column id_uuid uuid;
  end if;

  update public.accounts
     set id_uuid = coalesce(id_uuid, gen_random_uuid());

  alter table public.accounts
    alter column id_uuid set not null;

  select data_type
    into v_journal_account_type
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'journal_lines'
     and column_name = 'account_id'
   limit 1;

  if v_journal_account_type is not null then
    if v_journal_account_type <> 'uuid' then
      if not exists (
        select 1
          from information_schema.columns
         where table_schema = 'public'
           and table_name = 'journal_lines'
           and column_name = 'account_id_uuid'
      ) then
        alter table public.journal_lines add column account_id_uuid uuid;
      end if;

      update public.journal_lines jl
         set account_id_uuid = a.id_uuid
        from public.accounts a
       where jl.account_id is not null
         and a.id::text = jl.account_id::text;

      alter table public.journal_lines drop column account_id;
      alter table public.journal_lines rename column account_id_uuid to account_id;
    else
      update public.journal_lines jl
         set account_id = a.id_uuid
        from public.accounts a
       where jl.account_id is not null
         and a.id::text = jl.account_id::text
         and jl.account_id <> a.id_uuid;
    end if;
  end if;

  select data_type
    into v_accounts_parent_type
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'accounts'
     and column_name = 'parent_id'
   limit 1;

  if v_accounts_parent_type is not null then
    if v_accounts_parent_type <> 'uuid' then
      if not exists (
        select 1
          from information_schema.columns
         where table_schema = 'public'
           and table_name = 'accounts'
           and column_name = 'parent_id_uuid'
      ) then
        alter table public.accounts add column parent_id_uuid uuid;
      end if;

      update public.accounts child
         set parent_id_uuid = parent.id_uuid
        from public.accounts parent
       where child.parent_id is not null
         and parent.id::text = child.parent_id::text;

      alter table public.accounts drop column parent_id;
      alter table public.accounts rename column parent_id_uuid to parent_id;
    else
      update public.accounts child
         set parent_id = parent.id_uuid
        from public.accounts parent
       where child.parent_id is not null
         and parent.id::text = child.parent_id::text
         and child.parent_id <> parent.id_uuid;
    end if;
  end if;

  if v_journal_account_type is not null then
    alter table public.journal_lines
      drop constraint if exists journal_lines_account_id_fkey;
  end if;

  if exists (
    select 1
      from pg_constraint
     where conrelid = 'public.accounts'::regclass
       and contype = 'f'
       and conname = 'accounts_parent_id_fkey'
  ) then
    alter table public.accounts
      drop constraint accounts_parent_id_fkey;
  end if;

  alter table public.accounts
    drop constraint if exists accounts_pkey;

  alter table public.accounts drop column id;
  alter table public.accounts rename column id_uuid to id;
  alter table public.accounts add primary key (id);
  alter table public.accounts alter column id set default gen_random_uuid();

  if exists (
    select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where c.relkind = 'S'
       and n.nspname = 'public'
       and c.relname = 'accounts_id_seq'
  ) then
    execute 'drop sequence public.accounts_id_seq';
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'accounts'
       and column_name = 'parent_id'
  ) then
    if not exists (
      select 1
        from pg_constraint
       where conrelid = 'public.accounts'::regclass
         and contype = 'f'
         and conname = 'accounts_parent_id_fkey'
    ) then
      alter table public.accounts
        add constraint accounts_parent_id_fkey
          foreign key (parent_id)
          references public.accounts(id)
          on delete set null;
    end if;
  end if;

  if exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'account_id'
  ) then
    if not exists (
      select 1
        from pg_constraint
       where conrelid = 'public.journal_lines'::regclass
         and contype = 'f'
         and conname = 'journal_lines_account_id_fkey'
    ) then
      alter table public.journal_lines
        add constraint journal_lines_account_id_fkey
          foreign key (account_id)
          references public.accounts(id);
    end if;
  end if;
end;
$$ language plpgsql;

-- Execute migration silently
do $$
begin
  perform public.migrate_accounts_to_uuid();
end $$;

insert into public.accounts (code, name, type, category, description)
values
  ('1101', 'Caja General', 'asset', 'currentAsset', 'Efectivo disponible en caja y fondos inmediatos.'),
  ('1110', 'Bancos - Cuenta Corriente', 'asset', 'currentAsset', 'Saldos disponibles en cuentas corrientes bancarias.'),
  ('1190', 'Otros Activos Corrientes', 'asset', 'currentAsset', 'Activos circulantes no clasificados en otra cuenta específica.'),
  ('1130', 'Cuentas por Cobrar Comerciales', 'asset', 'currentAsset', 'Saldos pendientes de cobro a clientes por ventas a crédito.')
on conflict (code) do update
set
  name = excluded.name,
  type = excluded.type,
  category = excluded.category,
  description = coalesce(excluded.description, accounts.description),
  is_active = true,
  updated_at = now();

create or replace function public.ensure_account(
  p_code text,
  p_name text,
  p_type text,
  p_category text,
  p_description text default null,
  p_parent_code text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account_id uuid;
  v_parent_id uuid;
begin
  perform public.migrate_accounts_to_uuid();

  if p_code is null then
    return null;
  end if;

  if p_parent_code is not null then
    select id
      into v_parent_id
      from public.accounts
     where code = p_parent_code
     limit 1;
  end if;

  insert into public.accounts (code, name, type, category, description, parent_id)
  values (p_code, p_name, p_type, p_category, p_description, v_parent_id)
  on conflict (code) do update
    set name = excluded.name,
        type = excluded.type,
        category = excluded.category,
        description = coalesce(excluded.description, accounts.description),
        parent_id = coalesce(excluded.parent_id, accounts.parent_id),
        is_active = true,
        updated_at = now()
  returning id into v_account_id;

  return v_account_id;
end;
$$;

create table if not exists sales_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null,
  customer_id uuid references customers(id) on delete set null,
  customer_name text,
  customer_rut text,
  date timestamp with time zone not null default now(),
  due_date timestamp with time zone,
  reference text,
  status text not null default 'draft'
    check (lower(status) = any (array[
      'draft','borrador',
      'sent','enviado','enviada','emitido','emitida','issued',
      'paid','pagado','pagada',
      'overdue','vencido','vencida',
      'cancelled','cancelado','cancelada','anulado','anulada'
    ])),
  subtotal numeric(12,2) not null default 0,
  iva_amount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  paid_amount numeric(12,2) not null default 0,
  balance numeric(12,2) not null default 0,
  items jsonb not null default '[]'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sales_invoices'
      and t.tgname = 'trg_sales_invoices_updated_at'
  ) then
    create trigger trg_sales_invoices_updated_at
      before update on sales_invoices
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create index if not exists idx_sales_invoices_customer_id
  on sales_invoices(customer_id);

alter table public.sales_invoices
  add column if not exists paid_amount numeric(12,2) not null default 0,
  add column if not exists balance numeric(12,2) not null default 0;

do $$
begin
  begin
    alter table public.sales_invoices
      drop constraint if exists sales_invoices_status_check;
  exception when others then
    null;
  end;

  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.sales_invoices'::regclass
       and conname = 'sales_invoices_status_check'
  ) then
    alter table public.sales_invoices
      add constraint sales_invoices_status_check
        check (lower(status) = any (array[
          'draft','borrador',
          'sent','enviado','enviada','emitido','emitida','issued',
          'confirmed','confirmado','confirmada',
          'paid','pagado','pagada',
          'overdue','vencido','vencida',
          'cancelled','cancelado','cancelada','anulado','anulada'
        ]));
  end if;
end $$;

-- ============================================================================
-- PAYMENT METHODS TABLE (Dynamic, UI-Configurable)
-- ============================================================================
-- This table allows flexible payment method configuration without code changes.
-- Each payment method is wired to a specific accounting account.
-- Users can add new methods via UI (e.g., "Transferencia BCI", "Transferencia Santander")

create table if not exists payment_methods (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  account_id uuid not null references accounts(id),
  requires_reference boolean not null default false,
  icon text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_payment_methods_code on payment_methods(code);
create index if not exists idx_payment_methods_sort_order on payment_methods(sort_order);
create index if not exists idx_payment_methods_account_id on payment_methods(account_id);

-- Seed basic payment methods (Efectivo → Caja, Transferencia/Tarjeta → Banco)
insert into payment_methods (code, name, account_id, requires_reference, icon, sort_order)
select 'cash', 'Efectivo', id, false, 'cash', 1
from accounts where code = '1101'
on conflict (code) do update set
  name = excluded.name,
  account_id = excluded.account_id,
  updated_at = now();

insert into payment_methods (code, name, account_id, requires_reference, icon, sort_order)
select 'transfer', 'Transferencia Bancaria', id, true, 'bank', 2
from accounts where code = '1110'
on conflict (code) do update set
  name = excluded.name,
  account_id = excluded.account_id,
  updated_at = now();

insert into payment_methods (code, name, account_id, requires_reference, icon, sort_order)
select 'card', 'Tarjeta de Débito/Crédito', id, false, 'credit_card', 3
from accounts where code = '1110'
on conflict (code) do update set
  name = excluded.name,
  account_id = excluded.account_id,
  updated_at = now();

insert into payment_methods (code, name, account_id, requires_reference, icon, sort_order)
select 'check', 'Cheque', id, true, 'receipt', 4
from accounts where code = '1110'
on conflict (code) do update set
  name = excluded.name,
  account_id = excluded.account_id,
  updated_at = now();

-- ============================================================================
-- SALES PAYMENTS TABLE (Updated to use payment_method_id)
-- ============================================================================
create table if not exists sales_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references sales_invoices(id) on delete cascade,
  invoice_reference text,
  payment_method_id uuid not null references payment_methods(id),
  amount numeric(12,2) not null default 0,
  date timestamp with time zone not null default now(),
  reference text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Migration: Handle existing sales_payments with old 'method' column
-- CRITICAL: This must run BEFORE creating indexes on payment_method_id
do $$
declare
  v_has_method_column boolean;
  v_has_payment_method_id boolean;
  v_cash_method_id uuid;
begin
  -- Check if payment_method_id column already exists
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sales_payments'
      and column_name = 'payment_method_id'
  ) into v_has_payment_method_id;

  -- Check if old 'method' column exists
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sales_payments'
      and column_name = 'method'
  ) into v_has_method_column;

  if v_has_method_column and not v_has_payment_method_id then
    raise notice 'Migrating sales_payments from method column to payment_method_id...';
    
    -- Get cash payment method ID as default
    select id into v_cash_method_id from payment_methods where code = 'cash' limit 1;
    
    if v_cash_method_id is null then
      raise exception 'Cash payment method not found! Ensure payment_methods table is populated.';
    end if;
    
    -- Add new column (nullable first)
    alter table sales_payments add column payment_method_id uuid;
    
    -- Migrate data: map old method values to payment_method_id
    update sales_payments sp
    set payment_method_id = pm.id
    from payment_methods pm
    where sp.payment_method_id is null
      and (
        (sp.method = 'cash' and pm.code = 'cash') or
        (sp.method = 'transfer' and pm.code = 'transfer') or
        (sp.method = 'card' and pm.code = 'card') or
        (sp.method = 'check' and pm.code = 'check') or
        (sp.method = 'other' and pm.code = 'cash')  -- Default 'other' to cash
      );
    
    -- Set default for any remaining nulls
    update sales_payments
    set payment_method_id = v_cash_method_id
    where payment_method_id is null;
    
    -- Add foreign key constraint
    alter table sales_payments 
      add constraint sales_payments_payment_method_id_fkey 
      foreign key (payment_method_id) 
      references payment_methods(id);
    
    -- Drop old method column and constraint
    alter table sales_payments drop constraint if exists sales_payments_method_check;
    alter table sales_payments drop column if exists method;
    
    -- Make payment_method_id NOT NULL
    alter table sales_payments alter column payment_method_id set not null;
    
    raise notice 'Migration complete!';
  elsif not v_has_payment_method_id then
    raise notice 'No existing sales_payments data, payment_method_id will be added by CREATE TABLE';
  else
    raise notice 'payment_method_id already exists, skipping migration';
  end if;
end $$;

create index if not exists idx_sales_payments_invoice_id
  on sales_payments(invoice_id);
create index if not exists idx_sales_payments_payment_method_id
  on sales_payments(payment_method_id);

alter table public.sales_payments
  add column if not exists invoice_reference text,
  add column if not exists notes text,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'sales_payments'
      and t.tgname = 'trg_sales_payments_updated_at'
  ) then
    create trigger trg_sales_payments_updated_at
      before update on sales_payments
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create or replace function public.recalculate_sales_invoice_payments(p_invoice_id uuid)
returns void as $$
declare
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
begin
  if p_invoice_id is null then
    return;
  end if;

  select id,
         total,
         status
    into v_invoice
    from public.sales_invoices
   where id = p_invoice_id
   for update;

  if not found then
    return;
  end if;

  select coalesce(sum(amount), 0)
    into v_total
    from public.sales_payments
   where invoice_id = p_invoice_id;

  v_balance := greatest(coalesce(v_invoice.total, 0) - v_total, 0);

  -- Determine new status based on payment totals and current status
  if v_invoice.status = 'cancelled' then
    -- Keep cancelled status
    v_new_status := v_invoice.status;
  elsif v_invoice.status = 'draft' then
    -- Draft stays draft unless fully paid
    if v_total >= coalesce(v_invoice.total, 0) and v_total > 0 then
      v_new_status := 'paid';
    else
      v_new_status := 'draft';
    end if;
  elsif v_total >= coalesce(v_invoice.total, 0) and v_total > 0 then
    -- Fully paid
    v_new_status := 'paid';
  elsif v_total > 0 and v_total < coalesce(v_invoice.total, 0) then
    -- Partially paid - keep current status if it's overdue, otherwise set to confirmed
    if v_invoice.status = 'overdue' then
      v_new_status := 'overdue';
    else
      v_new_status := 'confirmed';
    end if;
  elsif v_total = 0 then
    -- No payments
    if v_invoice.status = 'paid' then
      -- If was paid but now has no payments, revert to confirmed
      v_new_status := 'confirmed';
    else
      -- Otherwise keep current status (draft/sent/confirmed/overdue)
      v_new_status := v_invoice.status;
    end if;
  else
    -- Fallback: keep current status
    v_new_status := v_invoice.status;
  end if;

  update public.sales_invoices
     set paid_amount = v_total,
         balance = v_balance,
         status = v_new_status,
         updated_at = now()
   where id = p_invoice_id;
end;
$$ language plpgsql;

create or replace function public.create_sales_payment_journal_entry(p_payment public.sales_payments)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_payment_method record;
  v_cash_account_id uuid;
  v_cash_account_code text;
  v_cash_account_name text;
  v_receivable_account_id uuid;
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_description text;
begin
  if p_payment.invoice_id is null then
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_payments'
              and source_reference = p_payment.id::text
        )
    into v_exists;

  if v_exists then
    return;
  end if;

  select id,
         invoice_number,
         customer_name,
         total
    into v_invoice
    from public.sales_invoices
   where id = p_payment.invoice_id;

  if not found then
    return;
  end if;

  -- Get payment method and its associated account (DYNAMIC!)
  select pm.id, pm.code, pm.name, a.id as account_id, a.code as account_code, a.name as account_name
    into v_payment_method
    from public.payment_methods pm
    join public.accounts a on a.id = pm.account_id
   where pm.id = p_payment.payment_method_id;

  if not found then
    raise exception 'Payment method not found for payment %', p_payment.id;
  end if;

  -- Use the account from payment method configuration
  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  v_receivable_account_id := public.ensure_account(
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_description := format('Pago factura %s - %s', 
    coalesce(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

  insert into public.journal_entries (
    id,
    entry_number,
    date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    concat('PAY-', to_char(now(), 'YYYYMMDDHH24MISS')),
    coalesce(p_payment.date, now()),
    v_description,
    'payment',
    'sales_payments',
    p_payment.id::text,
    'posted',
    p_payment.amount,
    p_payment.amount,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    format('Cobro a %s', coalesce(v_invoice.customer_name, 'Cliente')),
    p_payment.amount,
    0,
    now(),
    now()
  ), (
    gen_random_uuid(),
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    format('Pago factura %s', coalesce(v_invoice.invoice_number, v_invoice.id::text)),
    0,
    p_payment.amount,
    now(),
    now()
  );
end;
$$;

create or replace function public.delete_sales_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_payment_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'sales_payments'
     and source_reference = p_payment_id::text;
end;
$$;

-- ============================================================================
-- PURCHASE PAYMENT JOURNAL ENTRY FUNCTIONS (Mirror sales payment pattern)
-- ============================================================================

create or replace function public.recalculate_purchase_invoice_payments(p_invoice_id uuid)
returns void as $$
declare
  v_invoice record;
  v_total numeric(12,2);
  v_new_status text;
  v_balance numeric(12,2);
begin
  if p_invoice_id is null then
    return;
  end if;

  select id,
         total,
         status,
         prepayment_model
    into v_invoice
    from public.purchase_invoices
   where id = p_invoice_id
   for update;

  if not found then
    return;
  end if;

  select coalesce(sum(amount), 0)
    into v_total
    from public.purchase_payments
   where invoice_id = p_invoice_id;

  v_balance := greatest(coalesce(v_invoice.total, 0) - v_total, 0);

  -- Status transition logic based on prepayment model
  -- Standard model: Draft→Sent→Confirmed→Received→Paid
  -- Prepayment model: Draft→Sent→Confirmed→Paid→Received
  
  if v_invoice.status = 'cancelled' then
    -- Cancelled invoices stay cancelled regardless of payments
    v_new_status := 'cancelled';
    
  elsif v_invoice.status IN ('draft', 'sent') then
    -- Pre-confirmation statuses: stay as-is regardless of payments
    v_new_status := v_invoice.status;
    
  elsif v_total >= coalesce(v_invoice.total, 0) then
    -- Fully paid
    v_new_status := 'paid';
    
  elsif v_total > 0 then
    -- Partially paid
    if v_invoice.prepayment_model then
      -- Prepayment model: partial payment keeps it at 'paid' if was paid/received
      if v_invoice.status IN ('paid', 'received') then
        v_new_status := 'paid';
      else
        v_new_status := 'confirmed';
      end if;
    else
      -- Standard model: partial payment keeps it at 'received' if was received/paid
      if v_invoice.status IN ('received', 'paid') then
        v_new_status := 'received';
      else
        v_new_status := 'confirmed';
      end if;
    end if;
    
  else
    -- No payments (v_total = 0): revert to previous status in workflow
    if v_invoice.prepayment_model then
      -- Prepayment model: Confirmed→Paid→Received
      if v_invoice.status IN ('paid', 'received') then
        -- If was paid or received, revert to confirmed (no payment means not paid yet)
        v_new_status := 'confirmed';
      else
        v_new_status := v_invoice.status;
      end if;
    else
      -- Standard model: Confirmed→Received→Paid
      if v_invoice.status = 'paid' then
        -- If was paid, revert to received (goods received but payment removed)
        v_new_status := 'received';
      else
        -- If at received/confirmed, stay there (never reached paid)
        v_new_status := v_invoice.status;
      end if;
    end if;
  end if;

  update public.purchase_invoices
     set paid_amount = v_total,
         balance = v_balance,
         status = v_new_status,
         updated_at = now()
   where id = p_invoice_id;
end;
$$ language plpgsql;

-- CRITICAL: Drop ALL versions of function to clear cached type definition
-- Drop old version with uuid parameter (if exists from previous schema)
drop function if exists public.create_purchase_payment_journal_entry(uuid) cascade;
drop function if exists public.create_purchase_payment_journal_entry(p_payment_id uuid) cascade;
-- Drop new version with composite type parameter
drop function if exists public.create_purchase_payment_journal_entry(public.purchase_payments) cascade;
drop function if exists public.create_purchase_payment_journal_entry(p_payment public.purchase_payments) cascade;

-- WORKAROUND: Use payment ID instead of composite type to avoid type cache issues
create or replace function public.create_purchase_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment record;
  v_invoice record;
  v_entry_id uuid := gen_random_uuid();
  v_exists boolean;
  v_payment_method record;
  v_cash_account_id uuid;
  v_cash_account_code text;
  v_cash_account_name text;
  v_payable_account_id uuid;
  v_payable_account_code text := '2101';
  v_payable_account_name text := 'Cuentas por Pagar Proveedores';
  v_description text;
begin
  -- Fetch payment data from table instead of using composite type parameter
  select id, invoice_id, amount, date, payment_method_id
    into v_payment
    from public.purchase_payments
   where id = p_payment_id;

  if not found or v_payment.invoice_id is null then
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'purchase_payments'
              and source_reference = v_payment.id::text
        )
    into v_exists;

  if v_exists then
    return;
  end if;

  select id,
         invoice_number,
         supplier_name,
         total
    into v_invoice
    from public.purchase_invoices
   where id = v_payment.invoice_id;

  if not found then
    return;
  end if;

  -- Get payment method and its associated account (DYNAMIC!)
  select pm.id, pm.code, pm.name, a.id as account_id, a.code as account_code, a.name as account_name
    into v_payment_method
    from public.payment_methods pm
    join public.accounts a on a.id = pm.account_id
   where pm.id = v_payment.payment_method_id;

  if not found then
    raise exception 'Payment method not found for payment %', v_payment.id;
  end if;

  -- Use the account from payment method configuration
  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  v_payable_account_id := public.ensure_account(
    v_payable_account_code,
    v_payable_account_name,
    'liability',
    'currentLiability',
    'Cuentas por pagar a proveedores',
    null
  );

  v_description := format('Pago factura compra %s - %s', 
    coalesce(v_invoice.invoice_number, v_invoice.id::text),
    v_payment_method.name
  );

  insert into public.journal_entries (
    id,
    entry_number,
    date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    concat('PPAY-', to_char(now(), 'YYYYMMDDHH24MISS')),
    coalesce(v_payment.date, now()),
    v_description,
    'payment',
    'purchase_payments',
    v_payment.id::text,
    'posted',
    v_payment.amount,
    v_payment.amount,
    now(),
    now()
  );

  -- DR: Accounts Payable (reduce liability)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_payable_account_id,
    v_payable_account_code,
    v_payable_account_name,
    v_description,
    v_payment.amount,
    0,
    now(),
    now()
  );

  -- CR: Cash/Bank account (reduce asset)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_cash_account_id,
    v_cash_account_code,
    v_cash_account_name,
    v_description,
    0,
    v_payment.amount,
    now(),
    now()
  );
end;
$$;

create or replace function public.delete_purchase_payment_journal_entry(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_payment_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'purchase_payments'
     and source_reference = p_payment_id::text;
end;
$$;

-- CRITICAL: Drop trigger FIRST, then function to clear cached type definition
-- Using CASCADE to ensure all dependencies are dropped
drop trigger if exists trg_purchase_payments_change on public.purchase_payments cascade;
drop function if exists public.handle_purchase_payment_change() cascade;

create or replace function public.handle_purchase_payment_change()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'UPDATE' then
    perform public.delete_purchase_payment_journal_entry(OLD.id);
    perform public.create_purchase_payment_journal_entry(NEW.id);
    perform public.recalculate_purchase_invoice_payments(NEW.invoice_id);
  elsif TG_OP = 'DELETE' then
    perform public.delete_purchase_payment_journal_entry(OLD.id);
    perform public.recalculate_purchase_invoice_payments(OLD.invoice_id);
  end if;
  return NULL;
end;
$$ language plpgsql;

create or replace function public.consume_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_resolved_product_id uuid;
  v_quantity_int integer;
  v_status text;
  v_items_count integer;
begin
  -- Early exit if invoice ID is null
  if p_invoice.id is null then
    raise notice 'consume_sales_invoice_inventory: invoice ID is null';
    return;
  end if;

  v_status := lower(coalesce(p_invoice.status, 'draft'));
  raise notice 'consume_sales_invoice_inventory: invoice %, status %', p_invoice.id, v_status;

  -- Only process if status is posted (not draft/cancelled)
  if v_status = any (array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada']) then
    raise notice 'consume_sales_invoice_inventory: status is non-posted, skipping';
    return;
  end if;

  -- Check if inventory reduction already done
  v_reference := concat('sales_invoice:', p_invoice.id::text);
  if exists (
       select 1
         from public.stock_movements
        where reference = v_reference
          and type = 'OUT'
     ) then
    raise notice 'consume_sales_invoice_inventory: inventory already reduced for %', v_reference;
    return;
  end if;

  -- Count items
  select jsonb_array_length(coalesce(p_invoice.items, '[]'::jsonb))
    into v_items_count;
  
  raise notice 'consume_sales_invoice_inventory: processing % items', v_items_count;

  -- Process each item
  for v_item in
    select 
      (item->>'product_id')::uuid as product_id,
      (item->>'product_sku')::text as product_sku,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
  loop
    v_resolved_product_id := v_item.product_id;

    -- Try to resolve by SKU if product_id is null
    if v_resolved_product_id is null and v_item.product_sku is not null and v_item.product_sku != '' then
      select id
        into v_resolved_product_id
        from public.products
       where sku = v_item.product_sku
       limit 1;
      
      raise notice 'consume_sales_invoice_inventory: resolved product % by SKU %', v_resolved_product_id, v_item.product_sku;
    end if;

    v_quantity_int := coalesce(v_item.quantity::int, 0);

    if v_resolved_product_id is null then
      raise notice 'consume_sales_invoice_inventory: skipping item - product_id is null, sku: %', v_item.product_sku;
      continue;
    end if;

    if v_quantity_int <= 0 then
      raise notice 'consume_sales_invoice_inventory: skipping item - quantity <= 0, product: %', v_resolved_product_id;
      continue;
    end if;

    -- Reduce inventory (check both inventory_qty and stock_quantity columns)
    update public.products
       set inventory_qty = coalesce(inventory_qty, 0) - v_quantity_int,
           updated_at = now()
     where id = v_resolved_product_id
       and coalesce(is_service, false) = false;

    if found then
      raise notice 'consume_sales_invoice_inventory: reduced inventory for product % by %', v_resolved_product_id, v_quantity_int;
      
      -- Create stock movement record
      insert into public.stock_movements (
        id,
        product_id,
        warehouse_id,
        type,
        movement_type,
        quantity,
        reference,
        notes,
        date,
        created_at,
        updated_at
      ) values (
        gen_random_uuid(),
        v_resolved_product_id,
        null,
        'OUT',
        'sales_invoice',
        -v_quantity_int, -- Negative for OUT movements
        v_reference,
        format('Salida por factura %s', coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text)),
        coalesce(p_invoice.date, now()),
        now(),
        now()
      );
    else
      raise notice 'consume_sales_invoice_inventory: product % is a service or does not exist', v_resolved_product_id;
    end if;
  end loop;

  raise notice 'consume_sales_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.restore_sales_invoice_inventory(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_movement record;
  v_has_inventory_qty boolean := false;
  v_has_stock_quantity boolean := false;
  v_has_is_service boolean := false;
  v_has_track_stock boolean := false;
  v_has_updated_at boolean := false;
  v_update_assignments text := '';
  v_update_sql text;
  v_quantity_int integer;
begin
  if p_invoice.id is null then
    return;
  end if;

  v_reference := concat('sales_invoice:', p_invoice.id::text);

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'inventory_qty'
         )
    into v_has_inventory_qty;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'stock_quantity'
         )
    into v_has_stock_quantity;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'is_service'
         )
    into v_has_is_service;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'track_stock'
         )
    into v_has_track_stock;

  select exists (
           select 1
             from information_schema.columns
            where table_schema = 'public'
              and table_name = 'products'
              and column_name = 'updated_at'
         )
    into v_has_updated_at;

  if not v_has_inventory_qty and not v_has_stock_quantity then
    delete from public.stock_movements
     where reference = v_reference;
    return;
  end if;

  if v_has_inventory_qty then
    v_update_assignments := v_update_assignments || 'inventory_qty = coalesce(inventory_qty, 0) + $1';
  end if;

  if v_has_stock_quantity then
    if v_update_assignments <> '' then
      v_update_assignments := v_update_assignments || ', ';
    end if;
    v_update_assignments := v_update_assignments || 'stock_quantity = coalesce(stock_quantity, 0) + $1';
  end if;

  if v_has_updated_at then
    if v_update_assignments <> '' then
      v_update_assignments := v_update_assignments || ', ';
    end if;
    v_update_assignments := v_update_assignments || 'updated_at = now()';
  end if;

  if v_update_assignments = '' then
    delete from public.stock_movements
     where reference = v_reference;
    return;
  end if;

  v_update_sql := 'update public.products set ' || v_update_assignments || ' where id = $2';

  if v_has_is_service then
    v_update_sql := v_update_sql || ' and coalesce(is_service, false) = false';
  end if;

  if v_has_track_stock then
    v_update_sql := v_update_sql || ' and coalesce(track_stock, true) = true';
  end if;

  for v_movement in
    select product_id, quantity
      from public.stock_movements
     where reference = v_reference
  loop
    if v_movement.product_id is null or v_movement.quantity = 0 then
      continue;
    end if;

    v_quantity_int := abs(coalesce(v_movement.quantity::int, 0));

    if v_quantity_int = 0 then
      continue;
    end if;

    execute v_update_sql using v_quantity_int, v_movement.product_id;
  end loop;

  delete from public.stock_movements
   where reference = v_reference;
end;
$$;

create or replace function public.create_sales_invoice_journal_entry(p_invoice public.sales_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_receivable_account_code text := '1130';
  v_receivable_account_name text := 'Cuentas por Cobrar Comerciales';
  v_receivable_account_id uuid;
  v_revenue_account_code text := '4100';
  v_revenue_account_name text := 'Ingresos por Ventas';
  v_revenue_account_id uuid;
  v_iva_account_code text := '2150';
  v_iva_account_name text := 'IVA Débito Fiscal';
  v_iva_account_id uuid;
  v_inventory_account_code text := '1150';
  v_inventory_account_name text := 'Inventarios de Mercaderías';
  v_inventory_account_id uuid;
  v_cogs_account_code text := '5100';
  v_cogs_account_name text := 'Costo de Ventas';
  v_cogs_account_id uuid;
  v_invoice_number text;
  v_customer_name text;
  v_description text;
  v_subtotal numeric(12,2);
  v_iva numeric(12,2);
  v_total numeric(12,2);
  v_total_cost numeric(12,2);
begin
  if p_invoice.id is null then
    return;
  end if;

  if coalesce(p_invoice.status, 'draft') in ('draft', 'cancelled') then
    return;
  end if;

  select exists (
           select 1
             from public.journal_entries
            where source_module = 'sales_invoices'
              and source_reference = p_invoice.id::text
       )
    into v_exists;

  if v_exists then
    return;
  end if;

  v_subtotal := coalesce(p_invoice.subtotal, 0);
  v_iva := coalesce(p_invoice.iva_amount, 0);
  v_total := coalesce(p_invoice.total, v_subtotal + v_iva);

  if v_total = 0 then
    return;
  end if;

  v_receivable_account_id := public.ensure_account(
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_revenue_account_id := public.ensure_account(
    v_revenue_account_code,
    v_revenue_account_name,
    'income',
    'operatingIncome',
    'Ingresos operacionales por ventas',
    null
  );

  v_iva_account_id := public.ensure_account(
    v_iva_account_code,
    v_iva_account_name,
    'tax',
    'taxPayable',
    'IVA generado en ventas',
    null
  );

  select coalesce(sum((item->>'cost')::numeric), 0)
    into v_total_cost
    from jsonb_array_elements(coalesce(p_invoice.items, '[]'::jsonb)) item
   where (item->>'cost') is not null
     and (item->>'cost') <> '';

  if v_total_cost > 0 then
    v_inventory_account_id := public.ensure_account(
      v_inventory_account_code,
      v_inventory_account_name,
      'asset',
      'currentAsset',
      'Inventario disponible para la venta',
      null
    );

    v_cogs_account_id := public.ensure_account(
      v_cogs_account_code,
      v_cogs_account_name,
      'expense',
      'costOfGoodsSold',
      'Costo de ventas',
      null
    );
  end if;

  v_invoice_number := coalesce(nullif(p_invoice.invoice_number, ''), p_invoice.id::text);
  v_customer_name := coalesce(nullif(p_invoice.customer_name, ''), 'Cliente');
  v_description := format('Factura %s - %s', v_invoice_number, v_customer_name);

  insert into public.journal_entries (
    id,
    entry_number,
    date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    concat('INV-', to_char(now(), 'YYYYMMDDHH24MISS')),
    coalesce(p_invoice.date, now()),
    v_description,
    'sales',
    'sales_invoices',
    p_invoice.id::text,
    'posted',
    v_total,
    v_total,
    now(),
    now()
  );

  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_receivable_account_id,
    v_receivable_account_code,
    v_receivable_account_name,
    v_description,
    v_total,
    0,
    now(),
    now()
  );

  if v_subtotal <> 0 then
    insert into public.journal_lines (
      id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_entry_id,
      v_revenue_account_id,
      v_revenue_account_code,
      v_revenue_account_name,
      format('Ingreso por venta %s', v_invoice_number),
      0,
      v_subtotal,
      now(),
      now()
    );
  end if;

  if v_iva <> 0 then
    insert into public.journal_lines (
      id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_entry_id,
      v_iva_account_id,
      v_iva_account_code,
      v_iva_account_name,
      format('IVA débito factura %s', v_invoice_number),
      0,
      v_iva,
      now(),
      now()
    );
  end if;

  if v_total_cost > 0 then
    insert into public.journal_lines (
      id,
      entry_id,
      account_id,
      account_code,
      account_name,
      description,
      debit_amount,
      credit_amount,
      created_at,
      updated_at
    ) values (
      gen_random_uuid(),
      v_entry_id,
      v_cogs_account_id,
      v_cogs_account_code,
      v_cogs_account_name,
      format('Costo de ventas %s', v_invoice_number),
      v_total_cost,
      0,
      now(),
      now()
    ), (
      gen_random_uuid(),
      v_entry_id,
      v_inventory_account_id,
      v_inventory_account_code,
      v_inventory_account_name,
      format('Salida inventario factura %s', v_invoice_number),
      0,
      v_total_cost,
      now(),
      now()
    );
  end if;
end;
$$;

create or replace function public.delete_sales_invoice_journal_entry(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_invoice_id is null then
    return;
  end if;

  delete from public.journal_entries
   where source_module = 'sales_invoices'
     and source_reference = p_invoice_id::text;
end;
$$;

create or replace function public.handle_sales_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_non_posted constant text[] := array[
    'draft','borrador',
    'sent','enviado','enviada','issued','emitido','emitida',
    'cancelled','cancelado','cancelada','anulado','anulada'
  ];
  v_old_status text;
  v_new_status text;
  v_old_posted boolean;
  v_new_posted boolean;
begin
  raise notice 'handle_sales_invoice_change: TG_OP=%', TG_OP;

  -- Prevent infinite recursion
  if pg_trigger_depth() > 1 then
    raise notice 'handle_sales_invoice_change: trigger depth > 1, returning';
    if TG_OP = 'DELETE' then
      return OLD;
    else
      return NEW;
    end if;
  end if;

  if TG_OP = 'INSERT' then
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    raise notice 'handle_sales_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;
    
    -- Only process if status is "confirmed" or "paid" (NOT "draft" or "sent")
    if not (v_new_status = any (v_non_posted)) then
      raise notice 'handle_sales_invoice_change: INSERT with posted status, consuming inventory';
      perform public.consume_sales_invoice_inventory(NEW);
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      raise notice 'handle_sales_invoice_change: INSERT with non-posted status (%), skipping', v_new_status;
    end if;
    
    perform public.recalculate_sales_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    v_new_status := lower(coalesce(NEW.status, 'draft'));
    
    raise notice 'handle_sales_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    v_old_posted := not (v_old_status = any (v_non_posted));
    v_new_posted := not (v_new_status = any (v_non_posted));

    -- Handle inventory changes based on status transition
    if v_old_posted and v_new_posted then
      -- Both statuses are posted: restore old inventory, consume new
      raise notice 'handle_sales_invoice_change: both posted, restore and consume';
      perform public.restore_sales_invoice_inventory(OLD);
      perform public.consume_sales_invoice_inventory(NEW);
    elsif v_old_posted and not v_new_posted then
      -- Changed from posted to non-posted: restore inventory
      raise notice 'handle_sales_invoice_change: changed to non-posted, restore only';
      perform public.restore_sales_invoice_inventory(OLD);
    elsif not v_old_posted and v_new_posted then
      -- Changed from non-posted to posted: consume inventory
      raise notice 'handle_sales_invoice_change: changed to posted, consume';
      perform public.consume_sales_invoice_inventory(NEW);
    else
      -- Both non-posted: no inventory change
      raise notice 'handle_sales_invoice_change: both non-posted, no inventory change';
    end if;

    -- JOURNAL ENTRY HANDLING (DELETE-based reversals, Zoho Books style)
    if v_old_posted and not v_new_posted then
      -- Confirmed/Paid → Draft/Sent: DELETE journal entry
      raise notice 'handle_sales_invoice_change: reverting to non-posted, deleting journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.id::text;
        
    elsif not v_old_posted and v_new_posted then
      -- Draft/Sent → Confirmed: CREATE journal entry
      raise notice 'handle_sales_invoice_change: changing to posted, creating journal entry';
      perform public.create_sales_invoice_journal_entry(NEW);
      
    elsif v_old_posted and v_new_posted then
      -- Both posted: delete old, create new (amounts might have changed)
      raise notice 'handle_sales_invoice_change: both posted, recreating journal entry';
      delete from public.journal_entries
      where source_module = 'sales_invoices'
        and source_reference = OLD.id::text;
      perform public.create_sales_invoice_journal_entry(NEW);
    else
      -- Both non-posted: no journal entry action
      raise notice 'handle_sales_invoice_change: both non-posted, no journal entry action';
    end if;
    
    perform public.recalculate_sales_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    raise notice 'handle_sales_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;
    
    -- If was posted, restore inventory
    if not (v_old_status = any (v_non_posted)) then
      perform public.restore_sales_invoice_inventory(OLD);
    end if;
    
    -- DELETE journal entry
    delete from public.journal_entries
    where source_module = 'sales_invoices'
      and source_reference = OLD.id::text;
    
    return OLD;
  end if;

  return NULL;
end;
$$;

do $$
begin
  -- Drop and recreate trigger to ensure it uses latest function
  drop trigger if exists trg_sales_invoices_change on public.sales_invoices;
  
  create trigger trg_sales_invoices_change
    after insert or update or delete on public.sales_invoices
    for each row execute procedure public.handle_sales_invoice_change();
    
  raise notice 'Trigger trg_sales_invoices_change created successfully';
exception
  when others then
    raise notice 'Error creating trigger: %', SQLERRM;
end $$;

create or replace function public.handle_sales_payment_change()
returns trigger as $$
begin
  if TG_OP = 'INSERT' then
    perform public.recalculate_sales_invoice_payments(NEW.invoice_id);
    perform public.create_sales_payment_journal_entry(NEW);
    return NEW;
  elsif TG_OP = 'UPDATE' then
    if NEW.invoice_id is distinct from OLD.invoice_id then
      perform public.recalculate_sales_invoice_payments(OLD.invoice_id);
    end if;
    perform public.delete_sales_payment_journal_entry(OLD.id);
    perform public.recalculate_sales_invoice_payments(NEW.invoice_id);
    perform public.create_sales_payment_journal_entry(NEW);
    return NEW;
  elsif TG_OP = 'DELETE' then
    perform public.delete_sales_payment_journal_entry(OLD.id);
    perform public.recalculate_sales_invoice_payments(OLD.invoice_id);
    return OLD;
  end if;
  return NULL;
end;
$$ language plpgsql;

do $$
begin
  if not exists (
    select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname = 'sales_payments'
       and t.tgname = 'trg_sales_payments_change'
  ) then
    create trigger trg_sales_payments_change
      after insert or update or delete on public.sales_payments
      for each row execute procedure public.handle_sales_payment_change();
  end if;
end $$;

create table if not exists purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null,
  supplier_id uuid references suppliers(id) on delete set null,
  supplier_name text,
  supplier_rut text,
  date timestamp with time zone not null default now(),
  due_date timestamp with time zone,
  reference text,
  notes text,
  status text not null default 'draft'
    check (status in ('draft','sent','confirmed','received','paid','cancelled')),
  subtotal numeric(12,2) not null default 0,
  tax numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  paid_amount numeric(12,2) not null default 0,
  balance numeric(12,2) not null default 0,
  prepayment_model boolean not null default false,
  items jsonb not null default '[]'::jsonb,
  additional_costs jsonb not null default '[]'::jsonb,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

alter table public.purchase_invoices
  add column if not exists invoice_number text not null,
  add column if not exists supplier_id uuid references public.suppliers(id) on delete set null,
  add column if not exists supplier_name text,
  add column if not exists supplier_rut text,
  add column if not exists date timestamp with time zone not null default now(),
  add column if not exists due_date timestamp with time zone,
  add column if not exists reference text,
  add column if not exists notes text,
  add column if not exists status text not null default 'draft',
  add column if not exists subtotal numeric(12,2) not null default 0,
  add column if not exists tax numeric(12,2) not null default 0,
  add column if not exists total numeric(12,2) not null default 0,
  add column if not exists paid_amount numeric(12,2) not null default 0,
  add column if not exists balance numeric(12,2) not null default 0,
  add column if not exists prepayment_model boolean not null default false,
  add column if not exists items jsonb not null default '[]'::jsonb,
  add column if not exists additional_costs jsonb not null default '[]'::jsonb,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now(),
  add column if not exists tax numeric(12,2) not null default 0,
  add column if not exists paid_amount numeric(12,2) not null default 0,
  add column if not exists balance numeric(12,2) not null default 0,
  add column if not exists prepayment_model boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.purchase_invoices'::regclass
       and contype = 'c'
       and conname = 'purchase_invoices_status_check'
  ) then
    alter table public.purchase_invoices
      add constraint purchase_invoices_status_check
        check (status in ('draft','sent','confirmed','received','paid','cancelled'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'purchase_invoices'
      and t.tgname = 'trg_purchase_invoices_updated_at'
  ) then
    create trigger trg_purchase_invoices_updated_at
      before update on purchase_invoices
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create index if not exists idx_purchase_invoices_supplier_id
  on purchase_invoices(supplier_id);

create index if not exists idx_purchase_invoices_date
  on purchase_invoices(date);

create index if not exists idx_purchase_invoices_invoice_number
  on purchase_invoices(invoice_number);

-- ============================================================================
-- PURCHASE PAYMENTS TABLE (Uses payment_method_id for dynamic configuration)
-- ============================================================================
create table if not exists purchase_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references purchase_invoices(id) on delete cascade,
  invoice_reference text,
  payment_method_id uuid not null references payment_methods(id),
  amount numeric(12,2) not null default 0,
  date timestamp with time zone not null default now(),
  reference text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Migration: Handle existing purchase_payments with old column names
-- CRITICAL: This must run BEFORE creating indexes
do $$
declare
  v_has_invoice_id boolean;
  v_has_old_invoice_id boolean;
  v_has_payment_method_id boolean;
  v_has_old_method boolean;
  v_has_date boolean;
  v_cash_method_id uuid;
begin
  -- Check if columns exist
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'invoice_id'
  ) into v_has_invoice_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'purchase_invoice_id'
  ) into v_has_old_invoice_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'payment_method_id'
  ) into v_has_payment_method_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name in ('method', 'payment_method')
  ) into v_has_old_method;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'date'
  ) into v_has_date;

  -- Add date column if missing
  if not v_has_date then
    raise notice 'Adding date column to purchase_payments...';
    alter table purchase_payments add column date timestamp with time zone not null default now();
  end if;

  -- Check for old payment_date column and migrate
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'payment_date'
  ) then
    raise notice 'Found old payment_date column, migrating to date...';
    -- Copy data if date is default and payment_date has real data
    update purchase_payments 
    set date = payment_date 
    where payment_date != date;
    -- Drop old column
    alter table purchase_payments drop column payment_date;
  end if;

  -- Check for old bank_account_id column and drop it
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'purchase_payments'
      and column_name = 'bank_account_id'
  ) then
    raise notice 'Found old bank_account_id column, dropping it (use payment_method_id instead)...';
    alter table purchase_payments drop column bank_account_id;
  end if;

  -- Migrate invoice_id column name
  if v_has_old_invoice_id and v_has_invoice_id then
    -- BOTH columns exist - this shouldn't happen, but let's fix it
    raise notice 'WARNING: Both purchase_invoice_id and invoice_id exist! Copying data and dropping old column...';
    -- Copy data from old column to new column if new is null
    update purchase_payments set invoice_id = purchase_invoice_id where invoice_id is null;
    -- Drop the old column
    alter table purchase_payments drop column purchase_invoice_id;
    v_has_old_invoice_id := false;
  elsif v_has_old_invoice_id and not v_has_invoice_id then
    raise notice 'Renaming purchase_invoice_id to invoice_id...';
    alter table purchase_payments rename column purchase_invoice_id to invoice_id;
    v_has_invoice_id := true;
  elsif not v_has_invoice_id then
    raise notice 'ERROR: Neither purchase_invoice_id nor invoice_id exists!';
  end if;

  -- Add invoice_id if it doesn't exist at all
  if not v_has_invoice_id then
    raise notice 'Adding invoice_id column to purchase_payments...';
    alter table purchase_payments add column invoice_id uuid not null references purchase_invoices(id) on delete cascade;
  end if;

  -- Migrate payment method column
  if v_has_old_method and not v_has_payment_method_id then
    raise notice 'Migrating purchase_payments payment method to payment_method_id...';
    
    -- Get cash payment method ID as default
    select id into v_cash_method_id from payment_methods where code = 'cash' limit 1;
    
    if v_cash_method_id is null then
      raise exception 'Cash payment method not found! Ensure payment_methods table is populated.';
    end if;
    
    -- Add new column (nullable first)
    alter table purchase_payments add column payment_method_id uuid;
    
    -- Try to migrate from 'method' column
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'purchase_payments'
        and column_name = 'method'
    ) then
      update purchase_payments pp
      set payment_method_id = pm.id
      from payment_methods pm
      where pp.payment_method_id is null
        and (
          (lower(pp.method) = 'cash' and pm.code = 'cash') or
          (lower(pp.method) in ('transfer', 'transferencia') and pm.code = 'transfer') or
          (lower(pp.method) in ('card', 'tarjeta') and pm.code = 'card') or
          (lower(pp.method) in ('check', 'cheque') and pm.code = 'check')
        );
      alter table purchase_payments drop column method;
    end if;

    -- Try to migrate from 'payment_method' column
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'purchase_payments'
        and column_name = 'payment_method'
    ) then
      update purchase_payments pp
      set payment_method_id = pm.id
      from payment_methods pm
      where pp.payment_method_id is null
        and (
          (lower(pp.payment_method) = 'cash' and pm.code = 'cash') or
          (lower(pp.payment_method) in ('transfer', 'transferencia') and pm.code = 'transfer') or
          (lower(pp.payment_method) in ('card', 'tarjeta') and pm.code = 'card') or
          (lower(pp.payment_method) in ('check', 'cheque') and pm.code = 'check')
        );
      alter table purchase_payments drop column payment_method;
    end if;
    
    -- Set default for any remaining nulls
    update purchase_payments
    set payment_method_id = v_cash_method_id
    where payment_method_id is null;
    
    -- Add foreign key constraint
    alter table purchase_payments 
      add constraint purchase_payments_payment_method_id_fkey 
      foreign key (payment_method_id) 
      references payment_methods(id);
    
    -- Make payment_method_id NOT NULL
    alter table purchase_payments alter column payment_method_id set not null;
    
    raise notice 'Migration complete for purchase_payments!';
  elsif not v_has_payment_method_id then
    raise notice 'Adding payment_method_id to purchase_payments...';
    alter table purchase_payments add column payment_method_id uuid not null references payment_methods(id);
  end if;

  raise notice 'purchase_payments migration check complete';
end $$;

create index if not exists idx_purchase_payments_invoice_id
  on purchase_payments(invoice_id);
create index if not exists idx_purchase_payments_payment_method_id
  on purchase_payments(payment_method_id);

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'purchase_payments'
      and t.tgname = 'trg_purchase_payments_updated_at'
  ) then
    create trigger trg_purchase_payments_updated_at
      before update on purchase_payments
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

-- Trigger already dropped and function recreated earlier (line ~1367)
-- Now just create the trigger with the refreshed function
create trigger trg_purchase_payments_change
  after insert or update or delete on public.purchase_payments
  for each row execute procedure public.handle_purchase_payment_change();

create table if not exists stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  warehouse_id uuid,
  type text not null check (type in ('IN','OUT','INVENTORY_ADJUST','TRANSFER_OUT','TRANSFER_IN')),
  movement_type text,
  quantity numeric(12,2) not null,
  reference text,
  notes text,
  date timestamp with time zone not null default now(),
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists journal_entries (
  id uuid primary key default gen_random_uuid(),
  entry_number text not null,
  date timestamp with time zone not null default now(),
  description text not null,
  type text not null,
  source_module text,
  source_reference text,
  status text not null default 'draft',
  total_debit numeric(14,2) not null default 0,
  total_credit numeric(14,2) not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create table if not exists journal_lines (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid not null references journal_entries(id) on delete cascade,
  account_id uuid not null,
  account_code text not null,
  account_name text not null,
  description text,
  debit_amount numeric(14,2) not null default 0,
  credit_amount numeric(14,2) not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

do $$
begin
  begin
    alter table public.customers drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.products drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.sales_invoices drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.sales_payments drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.stock_movements drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.journal_entries drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.journal_lines drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.suppliers drop column if exists company_id;
  exception when others then
    null;
  end;

  begin
    alter table public.accounts drop column if exists company_id;
  exception when others then
    null;
  end;
end $$;

do $$
declare
  v_account_id_is_uuid boolean;
begin
  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'account_id'
       and data_type = 'uuid'
  ) into v_account_id_is_uuid;

  if not v_account_id_is_uuid then
    begin
      alter table public.journal_lines drop column account_id;
    exception when undefined_column then
      null;
    end;

    alter table public.journal_lines
      add column account_id uuid;
  end if;
end $$;

do $$
begin
  begin
    alter table public.journal_lines
      alter column account_id set not null;
  exception when others then
    null;
  end;
end $$;

do $$
declare
  v_has_old_entry_column boolean;
  v_has_new_entry_column boolean;
  rec record;
begin
  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'journal_entry_id'
  ) into v_has_old_entry_column;

  select exists (
    select 1
      from information_schema.columns
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'entry_id'
  ) into v_has_new_entry_column;

  if not v_has_old_entry_column then
    return;
  end if;

  if not v_has_new_entry_column then
    alter table public.journal_lines rename column journal_entry_id to entry_id;
    return;
  end if;

  execute 'update public.journal_lines set entry_id = journal_entry_id where entry_id is null';

  for rec in (
    select constraint_name
      from information_schema.constraint_column_usage
     where table_schema = 'public'
       and table_name = 'journal_lines'
       and column_name = 'journal_entry_id'
  ) loop
    execute format('alter table public.journal_lines drop constraint %I', rec.constraint_name);
  end loop;

  alter table public.journal_lines drop column journal_entry_id;

  begin
    alter table public.journal_lines
      alter column entry_id set not null;
  exception when others then
    null;
  end;
end $$;

alter table public.stock_movements
  add column if not exists date timestamp with time zone not null default now(),
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now(),
  add column if not exists type text,
  add column if not exists movement_type text,
  add column if not exists quantity numeric(12,2),
  add column if not exists reference text,
  add column if not exists notes text;

do $$
begin
  begin
    alter table public.stock_movements
      alter column warehouse_id drop not null;
  exception when others then
    null;
  end;

  begin
    alter table public.stock_movements
      alter column movement_type drop not null;
  exception when others then
    null;
  end;
end $$;

alter table public.journal_entries
  add column if not exists entry_number text,
  add column if not exists date timestamp with time zone not null default now(),
  add column if not exists description text,
  add column if not exists type text,
  add column if not exists source_module text,
  add column if not exists source_reference text,
  add column if not exists status text not null default 'draft',
  add column if not exists total_debit numeric(14,2) not null default 0,
  add column if not exists total_credit numeric(14,2) not null default 0,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

alter table public.journal_lines
  add column if not exists entry_id uuid,
  add column if not exists account_id uuid,
  add column if not exists account_code text,
  add column if not exists account_name text,
  add column if not exists description text,
  add column if not exists debit_amount numeric(14,2) not null default 0,
  add column if not exists credit_amount numeric(14,2) not null default 0,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.journal_lines'::regclass
      and contype = 'f'
      and conname = 'journal_lines_entry_id_fkey'
  ) then
    alter table public.journal_lines
      add constraint journal_lines_entry_id_fkey
        foreign key (entry_id)
        references public.journal_entries(id)
        on delete cascade;
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.journal_lines'::regclass
      and contype = 'f'
      and conname = 'journal_lines_account_id_fkey'
  ) then
    alter table public.journal_lines
      add constraint journal_lines_account_id_fkey
        foreign key (account_id)
        references public.accounts(id);
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'stock_movements'
      and t.tgname = 'trg_stock_movements_updated_at'
  ) then
    create trigger trg_stock_movements_updated_at
      before update on stock_movements
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'journal_entries'
      and t.tgname = 'trg_journal_entries_updated_at'
  ) then
    create trigger trg_journal_entries_updated_at
      before update on journal_entries
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'journal_lines'
      and t.tgname = 'trg_journal_lines_updated_at'
  ) then
    create trigger trg_journal_lines_updated_at
      before update on journal_lines
      for each row execute procedure public.set_updated_at();
  end if;
end $$;

create index if not exists idx_stock_movements_product_id
  on stock_movements(product_id);

create index if not exists idx_journal_entries_entry_number
  on journal_entries(entry_number);

create index if not exists idx_journal_entries_date
  on journal_entries(date);

create index if not exists idx_journal_lines_entry_id
  on journal_lines(entry_id);

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

do $$
begin
  if not exists (
    select 1 from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'order_items'
      and t.tgname = 'trg_order_item_insert'
  ) then
    create trigger trg_order_item_insert
      after insert on order_items
      for each row execute procedure public.handle_order_item_insert();
  end if;
end $$;

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

-- ============================================================================
-- PURCHASE INVOICE WORKFLOW FUNCTIONS (Mirror sales invoice pattern)
-- ============================================================================

create or replace function public.consume_purchase_invoice_inventory(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_items jsonb;
  v_resolved_product_id uuid;
  v_quantity_numeric numeric;
  v_quantity_int integer;
begin
  if p_invoice.id is null then
    raise notice 'consume_purchase_invoice_inventory: invoice ID is null, returning';
    return;
  end if;

  v_items := p_invoice.items;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise notice 'consume_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    return;
  end if;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      (item->>'product_name')::text as product_name,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(v_items) as item
  loop
    v_resolved_product_id := v_item.product_id;
    if v_resolved_product_id is null then
      raise notice 'consume_purchase_invoice_inventory: skipping item with null product_id';
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      raise notice 'consume_purchase_invoice_inventory: skipping item % with zero quantity', v_resolved_product_id;
      continue;
    end if;

    -- INCREASE inventory (purchase = IN movement)
    update public.products
    set inventory_qty = inventory_qty + v_quantity_int
    where id = v_resolved_product_id;

    -- Record stock movement
    insert into public.stock_movements (
      product_id,
      quantity,
      movement_type,
      type,
      reference,
      notes,
      date,
      created_at,
      updated_at
    ) values (
      v_resolved_product_id,
      v_quantity_int,
      'purchase_invoice',
      'IN',
      v_reference,
      format('Entrada según factura compra %s', p_invoice.invoice_number),
      p_invoice.date,
      now(),
      now()
    );
  end loop;

  raise notice 'consume_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.restore_purchase_invoice_inventory(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reference text;
  v_item record;
  v_items jsonb;
  v_resolved_product_id uuid;
  v_quantity_numeric numeric;
  v_quantity_int integer;
begin
  if p_invoice.id is null then
    raise notice 'restore_purchase_invoice_inventory: invoice ID is null, returning';
    return;
  end if;

  v_items := p_invoice.items;
  if v_items is null or jsonb_array_length(v_items) = 0 then
    raise notice 'restore_purchase_invoice_inventory: no items for invoice %', p_invoice.id;
    return;
  end if;

  v_reference := format('purchase_invoice:%s', p_invoice.id);

  -- Delete stock movements (same pattern as sales)
  delete from public.stock_movements
  where reference = v_reference;

  -- DECREASE inventory (restore = undo IN movement)
  for v_item in
    select
      (item->>'product_id')::uuid as product_id,
      (item->>'quantity')::numeric as quantity
    from jsonb_array_elements(v_items) as item
  loop
    v_resolved_product_id := v_item.product_id;
    if v_resolved_product_id is null then
      continue;
    end if;

    v_quantity_numeric := coalesce(v_item.quantity, 0);
    v_quantity_int := abs(v_quantity_numeric::integer);

    if v_quantity_int = 0 then
      continue;
    end if;

    update public.products
    set inventory_qty = greatest(inventory_qty - v_quantity_int, 0)
    where id = v_resolved_product_id;
  end loop;

  raise notice 'restore_purchase_invoice_inventory: completed for invoice %', p_invoice.id;
end;
$$;

create or replace function public.create_purchase_invoice_journal_entry(p_invoice public.purchase_invoices)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_exists boolean;
  v_entry_id uuid := gen_random_uuid();
  v_inventory_account_id uuid;
  v_iva_account_id uuid;
  v_payable_account_id uuid;
  v_description text;
begin
  if p_invoice.id is null then
    raise notice 'create_purchase_invoice_journal_entry: invoice ID is null, returning';
    return;
  end if;

  -- Check if journal entry already exists
  select exists (
    select 1
    from public.journal_entries
    where source_module = 'purchase_invoices'
      and source_reference = p_invoice.id::text
  ) into v_exists;

  if v_exists then
    raise notice 'create_purchase_invoice_journal_entry: entry already exists for invoice %', p_invoice.id;
    return;
  end if;

  -- Ensure accounts exist
  v_inventory_account_id := public.ensure_account(
    '1105',
    'Inventarios',
    'asset',
    'currentAsset',
    'Valor del inventario de productos',
    null
  );

  v_iva_account_id := public.ensure_account(
    '1107',
    'IVA Crédito Fiscal',
    'asset',
    'currentAsset',
    'IVA pagado en compras, recuperable',
    null
  );

  v_payable_account_id := public.ensure_account(
    '2101',
    'Cuentas por Pagar Proveedores',
    'liability',
    'currentLiability',
    'Obligaciones con proveedores',
    null
  );

  v_description := format('Factura compra %s - %s', 
    p_invoice.invoice_number, 
    coalesce(p_invoice.supplier_name, 'Proveedor')
  );

  -- Create journal entry header
  insert into public.journal_entries (
    id,
    entry_number,
    date,
    description,
    type,
    source_module,
    source_reference,
    status,
    total_debit,
    total_credit,
    created_at,
    updated_at
  ) values (
    v_entry_id,
    concat('PINV-', to_char(now(), 'YYYYMMDDHH24MISS')),
    coalesce(p_invoice.date, now()),
    v_description,
    'purchase',
    'purchase_invoices',
    p_invoice.id::text,
    'posted',
    p_invoice.total,
    p_invoice.total,
    now(),
    now()
  );

  -- DR: Inventory (increase asset)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_inventory_account_id,
    '1105',
    'Inventarios',
    v_description,
    p_invoice.subtotal,
    0,
    now(),
    now()
  );

  -- DR: IVA Crédito (increase asset, recoverable tax)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_iva_account_id,
    '1107',
    'IVA Crédito Fiscal',
    v_description,
    p_invoice.iva_amount,
    0,
    now(),
    now()
  );

  -- CR: Accounts Payable (increase liability)
  insert into public.journal_lines (
    id,
    entry_id,
    account_id,
    account_code,
    account_name,
    description,
    debit_amount,
    credit_amount,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    v_entry_id,
    v_payable_account_id,
    '2101',
    'Cuentas por Pagar Proveedores',
    v_description,
    0,
    p_invoice.total,
    now(),
    now()
  );

  raise notice 'create_purchase_invoice_journal_entry: created entry for invoice %', p_invoice.id;
end;
$$;

create or replace function public.delete_purchase_invoice_journal_entry(p_invoice_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_invoice_id is null then
    return;
  end if;

  delete from public.journal_entries
  where source_module = 'purchase_invoices'
    and source_reference = p_invoice_id::text;

  raise notice 'delete_purchase_invoice_journal_entry: deleted entry for invoice %', p_invoice_id;
end;
$$;

create or replace function public.handle_purchase_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status text;
  v_new_status text;
begin
  raise notice 'handle_purchase_invoice_change: TG_OP=%', TG_OP;

  if TG_OP = 'INSERT' then
    v_new_status := NEW.status;
    raise notice 'handle_purchase_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;
    
    -- Inventory: ONLY if inserted directly as 'received' (rare case)
    if v_new_status = 'received' then
      raise notice 'handle_purchase_invoice_change: INSERT at received, consuming inventory';
      perform public.consume_purchase_invoice_inventory(NEW);
    end if;
    
    -- Journal: If inserted at 'confirmed' or later
    if v_new_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: INSERT at confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
    end if;
    
    perform public.recalculate_purchase_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status;
    v_new_status := NEW.status;
    
    raise notice 'handle_purchase_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    -- INVENTORY HANDLING: ONLY at 'received' status
    -- Different logic for standard vs prepayment models:
    --
    -- STANDARD MODEL: Draft→Confirmed→RECEIVED→Paid
    --   Inventory added at 'received', stays through 'paid'
    --   So: received<->paid transitions do NOT change inventory
    --
    -- PREPAYMENT MODEL: Draft→Confirmed→Paid→RECEIVED
    --   Inventory added at 'received' (after payment)
    --   So: received<->paid transitions DO change inventory
    
    if NEW.prepayment_model then
      -- PREPAYMENT MODEL: Inventory changes whenever entering/leaving 'received'
      if v_old_status != 'received' AND v_new_status = 'received' then
        -- Transitioning TO received (from any status): add inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);
        
      elsif v_old_status = 'received' AND v_new_status != 'received' then
        -- Transitioning FROM received (to any status): remove inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);
        
      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Staying at received but invoice data changed: update inventory
        raise notice 'handle_purchase_invoice_change: [PREPAYMENT] staying at received, updating inventory';
        perform public.restore_purchase_invoice_inventory(OLD);
        perform public.consume_purchase_invoice_inventory(NEW);
      end if;
      
    else
      -- STANDARD MODEL: Inventory changes only when entering/leaving 'received' from/to non-paid statuses
      if v_old_status NOT IN ('received', 'paid') AND v_new_status = 'received' then
        -- Transitioning TO received from confirmed/sent/draft: add inventory
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning TO received from %, consuming inventory', v_old_status;
        perform public.consume_purchase_invoice_inventory(NEW);
        
      elsif v_old_status = 'received' AND v_new_status NOT IN ('received', 'paid') then
        -- Transitioning FROM received to confirmed/sent/draft: remove inventory
        -- Note: received→paid does NOT remove (goods stay in standard flow)
        raise notice 'handle_purchase_invoice_change: [STANDARD] transitioning FROM received to %, restoring inventory', v_new_status;
        perform public.restore_purchase_invoice_inventory(OLD);
        
      elsif v_old_status = 'received' AND v_new_status = 'received' then
        -- Staying at received but invoice data changed: update inventory
        raise notice 'handle_purchase_invoice_change: [STANDARD] staying at received, updating inventory';
        perform public.restore_purchase_invoice_inventory(OLD);
        perform public.consume_purchase_invoice_inventory(NEW);
      end if;
    end if;

    -- JOURNAL ENTRY HANDLING: Create ONCE at 'confirmed', delete when reverting
    -- The journal entry represents the purchase transaction (Dr Inventory / Cr Accounts Payable)
    -- It should NOT be recreated when moving between confirmed→received→paid
    -- It should ONLY be recreated if staying at same status but amounts changed
    
    if v_old_status IN ('draft', 'sent', 'cancelled') AND v_new_status IN ('confirmed', 'received', 'paid') then
      -- Transitioning TO confirmed/received/paid: create journal entry
      raise notice 'handle_purchase_invoice_change: transitioning TO confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
      
    elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('draft', 'sent', 'cancelled') then
      -- Transitioning FROM confirmed/received/paid to draft/sent/cancelled: delete journal entry
      raise notice 'handle_purchase_invoice_change: transitioning FROM confirmed/received/paid, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.id);
      
    elsif v_old_status = v_new_status AND v_old_status IN ('confirmed', 'received', 'paid') then
      -- Staying at same confirmed+ status but invoice data might have changed
      -- Only recreate journal if amounts changed (not just status transition)
      if OLD.subtotal IS DISTINCT FROM NEW.subtotal OR 
         OLD.tax IS DISTINCT FROM NEW.tax OR 
         OLD.total IS DISTINCT FROM NEW.total OR
         OLD.supplier_id IS DISTINCT FROM NEW.supplier_id then
        raise notice 'handle_purchase_invoice_change: amounts changed at same status, recreating journal entry';
        perform public.delete_purchase_invoice_journal_entry(OLD.id);
        perform public.create_purchase_invoice_journal_entry(NEW);
      end if;
    end if;
    
    -- Only recalculate if this is NOT a payment-only update (prevents infinite recursion)
    -- If only paid_amount, balance, or status changed → skip recalculate (it's from recalculate itself)
    -- If items, total, subtotal, tax, or other fields changed → call recalculate
    if OLD.items IS DISTINCT FROM NEW.items OR
       OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
       OLD.tax IS DISTINCT FROM NEW.tax OR
       OLD.total IS DISTINCT FROM NEW.total OR
       OLD.supplier_id IS DISTINCT FROM NEW.supplier_id OR
       OLD.prepayment_model IS DISTINCT FROM NEW.prepayment_model then
      raise notice 'handle_purchase_invoice_change: invoice data changed, recalculating payments';
      perform public.recalculate_purchase_invoice_payments(NEW.id);
    else
      raise notice 'handle_purchase_invoice_change: only payment fields changed, skipping recalculate to avoid recursion';
    end if;
    
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := OLD.status;
    raise notice 'handle_purchase_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;
    
    -- Restore inventory if was received
    if v_old_status = 'received' then
      raise notice 'handle_purchase_invoice_change: deleting received invoice, restoring inventory';
      perform public.restore_purchase_invoice_inventory(OLD);
    end if;
    
    -- Delete journal entry if was confirmed or later
    if v_old_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: deleting confirmed/received/paid invoice, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.id);
    end if;
    
    return OLD;
  end if;

  return NULL;
end;
$$;

do $$
begin
  drop trigger if exists trg_purchase_invoices_change on public.purchase_invoices;
  
  create trigger trg_purchase_invoices_change
    after insert or update or delete on public.purchase_invoices
    for each row execute procedure public.handle_purchase_invoice_change();
    
  raise notice 'Trigger trg_purchase_invoices_change created successfully';
exception
  when others then
    raise notice 'Error creating trigger: %', SQLERRM;
end $$;

-- Basic RLS scaffolding: enable on each table; policies to be tailored per role.
alter table customers enable row level security;
alter table products enable row level security;
alter table sales_invoices enable row level security;
alter table sales_payments enable row level security;
alter table stock_movements enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table journal_entries enable row level security;
alter table journal_lines enable row level security;
alter table suppliers enable row level security;
alter table purchase_invoices enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'Authenticated accounts read'
  ) then
    create policy "Authenticated accounts read"
      on accounts
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'Authenticated accounts insert'
  ) then
    create policy "Authenticated accounts insert"
      on accounts
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'Authenticated accounts update'
  ) then
    create policy "Authenticated accounts update"
      on accounts
      for update
      to authenticated
      using (auth.role() = 'authenticated')
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'accounts'
      and policyname = 'Authenticated accounts delete'
  ) then
    create policy "Authenticated accounts delete"
      on accounts
      for delete
      to authenticated
      using (auth.role() = 'authenticated');
  end if;
end $$;

-- Example policies; replace with final role-aware versions.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'customers'
      and policyname = 'Authenticated customers read'
  ) then
    create policy "Authenticated customers read"
      on customers
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'suppliers'
      and policyname = 'Authenticated suppliers read'
  ) then
    create policy "Authenticated suppliers read"
      on suppliers
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'suppliers'
      and policyname = 'Authenticated suppliers insert'
  ) then
    create policy "Authenticated suppliers insert"
      on suppliers
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'suppliers'
      and policyname = 'Authenticated suppliers update'
  ) then
    create policy "Authenticated suppliers update"
      on suppliers
      for update
      to authenticated
      using (auth.role() = 'authenticated')
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'suppliers'
      and policyname = 'Authenticated suppliers delete'
  ) then
    create policy "Authenticated suppliers delete"
      on suppliers
      for delete
      to authenticated
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'purchase_invoices'
      and policyname = 'Authenticated purchase_invoices read'
  ) then
    create policy "Authenticated purchase_invoices read"
      on purchase_invoices
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'purchase_invoices'
      and policyname = 'Authenticated purchase_invoices insert'
  ) then
    create policy "Authenticated purchase_invoices insert"
      on purchase_invoices
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'purchase_invoices'
      and policyname = 'Authenticated purchase_invoices update'
  ) then
    create policy "Authenticated purchase_invoices update"
      on purchase_invoices
      for update
      to authenticated
      using (auth.role() = 'authenticated')
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'purchase_invoices'
      and policyname = 'Authenticated purchase_invoices delete'
  ) then
    create policy "Authenticated purchase_invoices delete"
      on purchase_invoices
      for delete
      to authenticated
      using (auth.role() = 'authenticated');
  end if;
end $$;


do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'journal_entries'
      and policyname = 'Authenticated journal_entries read'
  ) then
    create policy "Authenticated journal_entries read"
      on journal_entries
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'journal_entries'
      and policyname = 'Authenticated journal_entries insert'
  ) then
    create policy "Authenticated journal_entries insert"
      on journal_entries
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'journal_entries'
      and policyname = 'Authenticated journal_entries update'
  ) then
    create policy "Authenticated journal_entries update"
      on journal_entries
      for update
      to authenticated
      using (auth.role() = 'authenticated')
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'journal_entries'
      and policyname = 'Authenticated journal_entries delete'
  ) then
    create policy "Authenticated journal_entries delete"
      on journal_entries
      for delete
      to authenticated
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'journal_lines'
      and policyname = 'Authenticated journal_lines read'
  ) then
    create policy "Authenticated journal_lines read"
      on journal_lines
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'journal_lines'
      and policyname = 'Authenticated journal_lines insert'
  ) then
    create policy "Authenticated journal_lines insert"
      on journal_lines
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'journal_lines'
      and policyname = 'Authenticated journal_lines update'
  ) then
    create policy "Authenticated journal_lines update"
      on journal_lines
      for update
      to authenticated
      using (auth.role() = 'authenticated')
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'journal_lines'
      and policyname = 'Authenticated journal_lines delete'
  ) then
    create policy "Authenticated journal_lines delete"
      on journal_lines
      for delete
      to authenticated
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'products'
      and policyname = 'Authenticated products read'
  ) then
    create policy "Authenticated products read"
      on products
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_invoices'
      and policyname = 'Authenticated invoices read'
  ) then
    create policy "Authenticated invoices read"
      on sales_invoices
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_invoices'
      and policyname = 'Authenticated invoices insert'
  ) then
    create policy "Authenticated invoices insert"
      on sales_invoices
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_invoices'
      and policyname = 'Authenticated invoices update'
  ) then
    create policy "Authenticated invoices update"
      on sales_invoices
      for update
      to authenticated
      using (auth.role() = 'authenticated')
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_invoices'
      and policyname = 'Authenticated invoices delete'
  ) then
    create policy "Authenticated invoices delete"
      on sales_invoices
      for delete
      to authenticated
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_payments'
      and policyname = 'Authenticated payments read'
  ) then
    create policy "Authenticated payments read"
      on sales_payments
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_payments'
      and policyname = 'Authenticated payments insert'
  ) then
    create policy "Authenticated payments insert"
      on sales_payments
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_payments'
      and policyname = 'Authenticated payments update'
  ) then
    create policy "Authenticated payments update"
      on sales_payments
      for update
      to authenticated
      using (auth.role() = 'authenticated')
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'sales_payments'
      and policyname = 'Authenticated payments delete'
  ) then
    create policy "Authenticated payments delete"
      on sales_payments
      for delete
      to authenticated
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'products'
      and policyname = 'Authenticated products insert'
  ) then
    create policy "Authenticated products insert"
      on products
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'products'
      and policyname = 'Authenticated products update'
  ) then
    create policy "Authenticated products update"
      on products
      for update
      to authenticated
      using (auth.role() = 'authenticated')
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'products'
      and policyname = 'Authenticated products delete'
  ) then
    create policy "Authenticated products delete"
      on products
      for delete
      to authenticated
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'stock_movements'
      and policyname = 'Authenticated stock_movements read'
  ) then
    create policy "Authenticated stock_movements read"
      on stock_movements
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'stock_movements'
      and policyname = 'Authenticated stock_movements insert'
  ) then
    create policy "Authenticated stock_movements insert"
      on stock_movements
      for insert
      to authenticated
      with check (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'orders'
      and policyname = 'Authenticated orders read'
  ) then
    create policy "Authenticated orders read"
      on orders
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'order_items'
      and policyname = 'Authenticated order_items read'
  ) then
    create policy "Authenticated order_items read"
      on order_items
      for select
      using (auth.role() = 'authenticated');
  end if;
end $$;

-- TODO: add role-specific policies matching Sales, Inventory, HR, Mechanic, Cashier profiles.

-- ============================================================================
-- FINANCIAL REPORTING FUNCTIONS
-- Professional accounting reports for Chilean GAAP compliance
-- ============================================================================

-- Function 1: Get account balance for a specific period
-- Returns the net balance (debits - credits for assets/expenses, credits - debits for liabilities/equity/income)
create or replace function public.get_account_balance(
  p_account_id uuid,
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns numeric(14,2)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account record;
  v_total_debit numeric(14,2) := 0;
  v_total_credit numeric(14,2) := 0;
  v_balance numeric(14,2) := 0;
begin
  -- Get account type to determine balance calculation
  select type into v_account
  from accounts
  where id = p_account_id;
  
  if not found then
    raise exception 'Account not found: %', p_account_id;
  end if;
  
  -- Sum debits and credits for this account in the period
  select
    coalesce(sum(debit_amount), 0),
    coalesce(sum(credit_amount), 0)
  into v_total_debit, v_total_credit
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  where jl.account_id = p_account_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted';
  
  -- Calculate balance based on account type
  -- Assets and Expenses: Debit increases balance (debit - credit)
  -- Liabilities, Equity, Income: Credit increases balance (credit - debit)
  if v_account.type in ('asset', 'expense') then
    v_balance := v_total_debit - v_total_credit;
  else
    v_balance := v_total_credit - v_total_debit;
  end if;
  
  return v_balance;
end;
$$;

-- Function 2: Get balances by account type with details
-- Returns all accounts of a specific type with their balances for a period
create or replace function public.get_balances_by_type(
  p_account_type text,
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  account_category text,
  parent_id uuid,
  debit_total numeric(14,2),
  credit_total numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id as account_id,
    a.code as account_code,
    a.name as account_name,
    a.category as account_category,
    a.parent_id,
    coalesce(sum(jl.debit_amount), 0)::numeric(14,2) as debit_total,
    coalesce(sum(jl.credit_amount), 0)::numeric(14,2) as credit_total,
    case
      -- Assets and Expenses: Debit balance
      when a.type in ('asset', 'expense') then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      -- Liabilities, Equity, Income: Credit balance
      else
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
    end::numeric(14,2) as balance
  from accounts a
  left join journal_lines jl on jl.account_id = a.id
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
  where a.type = p_account_type
    and a.is_active = true
  group by a.id, a.code, a.name, a.category, a.parent_id, a.type
  order by a.code;
end;
$$;

-- Function 3: Get balances by category (more granular than type)
-- Useful for grouping in financial statements
create or replace function public.get_balances_by_category(
  p_account_category text,
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  account_type text,
  parent_id uuid,
  debit_total numeric(14,2),
  credit_total numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id as account_id,
    a.code as account_code,
    a.name as account_name,
    a.type as account_type,
    a.parent_id,
    coalesce(sum(jl.debit_amount), 0)::numeric(14,2) as debit_total,
    coalesce(sum(jl.credit_amount), 0)::numeric(14,2) as credit_total,
    case
      when a.type in ('asset', 'expense') then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      else
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
    end::numeric(14,2) as balance
  from accounts a
  left join journal_lines jl on jl.account_id = a.id
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
  where a.category = p_account_category
    and a.is_active = true
  group by a.id, a.code, a.name, a.type, a.parent_id
  order by a.code;
end;
$$;

-- Function 4: Get trial balance (all accounts with balances)
-- Essential for verifying that debits = credits
create or replace function public.get_trial_balance(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns table (
  account_code text,
  account_name text,
  account_type text,
  account_category text,
  debit_total numeric(14,2),
  credit_total numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.code as account_code,
    a.name as account_name,
    a.type as account_type,
    a.category as account_category,
    coalesce(sum(jl.debit_amount), 0)::numeric(14,2) as debit_total,
    coalesce(sum(jl.credit_amount), 0)::numeric(14,2) as credit_total,
    case
      when a.type in ('asset', 'expense') then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      else
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
    end::numeric(14,2) as balance
  from accounts a
  left join journal_lines jl on jl.account_id = a.id
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
  where a.is_active = true
  group by a.id, a.code, a.name, a.type, a.category
  having coalesce(sum(jl.debit_amount), 0) <> 0 
      or coalesce(sum(jl.credit_amount), 0) <> 0
  order by a.code;
end;
$$;

-- Function 5: Calculate net income for a period
-- Income Statement bottom line: Total Income - Total Expenses
create or replace function public.calculate_net_income(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns numeric(14,2)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_income numeric(14,2) := 0;
  v_total_expense numeric(14,2) := 0;
  v_net_income numeric(14,2) := 0;
begin
  -- Calculate total income (credit balance for income accounts)
  select coalesce(sum(
    case
      when a.type = 'income' then
        coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0)
      else 0
    end
  ), 0)
  into v_total_income
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
    and a.type = 'income';
  
  -- Calculate total expenses (debit balance for expense accounts)
  select coalesce(sum(
    case
      when a.type = 'expense' then
        coalesce(jl.debit_amount, 0) - coalesce(jl.credit_amount, 0)
      else 0
    end
  ), 0)
  into v_total_expense
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
    and a.type = 'expense';
  
  -- Net Income = Income - Expenses
  v_net_income := v_total_income - v_total_expense;
  
  return v_net_income;
end;
$$;

-- Function 6: Get cumulative balance (for Balance Sheet - all transactions up to date)
-- Unlike period balance, this includes ALL transactions from the beginning of time
create or replace function public.get_cumulative_balance(
  p_account_id uuid,
  p_as_of_date timestamp with time zone
)
returns numeric(14,2)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account record;
  v_total_debit numeric(14,2) := 0;
  v_total_credit numeric(14,2) := 0;
  v_balance numeric(14,2) := 0;
begin
  select type into v_account
  from accounts
  where id = p_account_id;
  
  if not found then
    raise exception 'Account not found: %', p_account_id;
  end if;
  
  -- Sum all debits and credits up to the date
  select
    coalesce(sum(debit_amount), 0),
    coalesce(sum(credit_amount), 0)
  into v_total_debit, v_total_credit
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  where jl.account_id = p_account_id
    and je.entry_date <= p_as_of_date
    and je.status = 'posted';
  
  -- Calculate balance based on account type
  if v_account.type in ('asset', 'expense') then
    v_balance := v_total_debit - v_total_credit;
  else
    v_balance := v_total_credit - v_total_debit;
  end if;
  
  return v_balance;
end;
$$;

-- Function 7: Get cumulative balances by type (for Balance Sheet)
create or replace function public.get_cumulative_balances_by_type(
  p_account_type text,
  p_as_of_date timestamp with time zone
)
returns table (
  account_id uuid,
  account_code text,
  account_name text,
  account_category text,
  parent_id uuid,
  debit_total numeric(14,2),
  credit_total numeric(14,2),
  balance numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id as account_id,
    a.code as account_code,
    a.name as account_name,
    a.category as account_category,
    a.parent_id,
    coalesce(sum(jl.debit_amount), 0)::numeric(14,2) as debit_total,
    coalesce(sum(jl.credit_amount), 0)::numeric(14,2) as credit_total,
    case
      when a.type in ('asset', 'expense') then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      else
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
    end::numeric(14,2) as balance
  from accounts a
  left join journal_lines jl on jl.account_id = a.id
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date <= p_as_of_date
    and je.status = 'posted'
  where a.type = p_account_type
    and a.is_active = true
  group by a.id, a.code, a.name, a.category, a.parent_id, a.type
  order by a.code;
end;
$$;

-- Function 8: Verify accounting equation (Assets = Liabilities + Equity)
-- Returns true if balanced, false if not (with difference amount)
create or replace function public.verify_accounting_equation(
  p_as_of_date timestamp with time zone
)
returns table (
  is_balanced boolean,
  total_assets numeric(14,2),
  total_liabilities numeric(14,2),
  total_equity numeric(14,2),
  difference numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assets numeric(14,2) := 0;
  v_liabilities numeric(14,2) := 0;
  v_equity numeric(14,2) := 0;
  v_diff numeric(14,2) := 0;
  v_is_balanced boolean := false;
begin
  -- Calculate total assets
  select coalesce(sum(
    coalesce(jl.debit_amount, 0) - coalesce(jl.credit_amount, 0)
  ), 0)
  into v_assets
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and a.type = 'asset';
  
  -- Calculate total liabilities
  select coalesce(sum(
    coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0)
  ), 0)
  into v_liabilities
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and a.type = 'liability';
  
  -- Calculate total equity
  select coalesce(sum(
    coalesce(jl.credit_amount, 0) - coalesce(jl.debit_amount, 0)
  ), 0)
  into v_equity
  from journal_lines jl
  inner join journal_entries je on je.id = jl.entry_id
  inner join accounts a on a.id = jl.account_id
  where je.entry_date <= p_as_of_date
    and je.status = 'posted'
    and a.type = 'equity';
  
  -- Calculate difference (should be near zero)
  v_diff := v_assets - (v_liabilities + v_equity);
  
  -- Consider balanced if difference is less than 1 peso (rounding tolerance)
  v_is_balanced := abs(v_diff) < 1.00;
  
  return query
  select v_is_balanced, v_assets, v_liabilities, v_equity, v_diff;
end;
$$;

-- Function 9: Get income statement data grouped by category
-- Returns structured data ready for Income Statement report
create or replace function public.get_income_statement_data(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone
)
returns table (
  category text,
  category_label text,
  account_code text,
  account_name text,
  amount numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.category,
    case a.category
      when 'operatingIncome' then 'Ingresos Operacionales'
      when 'nonOperatingIncome' then 'Ingresos No Operacionales'
      when 'costOfGoodsSold' then 'Costo de Ventas'
      when 'operatingExpense' then 'Gastos Operacionales'
      when 'financialExpense' then 'Gastos Financieros'
      when 'taxExpense' then 'Impuestos'
      else a.category
    end as category_label,
    a.code as account_code,
    a.name as account_name,
    case
      when a.type = 'income' then
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
      when a.type = 'expense' then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      else 0
    end::numeric(14,2) as amount
  from accounts a
  left join journal_lines jl on jl.account_id = a.id
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date >= p_start_date
    and je.entry_date <= p_end_date
    and je.status = 'posted'
  where a.type in ('income', 'expense')
    and a.is_active = true
  group by a.id, a.code, a.name, a.type, a.category
  having (coalesce(sum(jl.debit_amount), 0) <> 0 
       or coalesce(sum(jl.credit_amount), 0) <> 0)
  order by 
    case a.type 
      when 'income' then 1 
      when 'expense' then 2 
      else 3 
    end,
    a.category,
    a.code;
end;
$$;

-- Function 10: Get balance sheet data grouped by category
-- Returns structured data ready for Balance Sheet report
create or replace function public.get_balance_sheet_data(
  p_as_of_date timestamp with time zone
)
returns table (
  account_type text,
  type_label text,
  category text,
  category_label text,
  account_code text,
  account_name text,
  amount numeric(14,2)
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.type as account_type,
    case a.type
      when 'asset' then 'ACTIVOS'
      when 'liability' then 'PASIVOS'
      when 'equity' then 'PATRIMONIO'
      else a.type
    end as type_label,
    a.category,
    case a.category
      when 'currentAsset' then 'Activos Circulantes'
      when 'fixedAsset' then 'Activos Fijos'
      when 'otherAsset' then 'Otros Activos'
      when 'currentLiability' then 'Pasivos Circulantes'
      when 'longTermLiability' then 'Pasivos Largo Plazo'
      when 'capital' then 'Capital'
      when 'retainedEarnings' then 'Utilidades Retenidas'
      else a.category
    end as category_label,
    a.code as account_code,
    a.name as account_name,
    case
      when a.type = 'asset' then
        coalesce(sum(jl.debit_amount), 0) - coalesce(sum(jl.credit_amount), 0)
      when a.type in ('liability', 'equity') then
        coalesce(sum(jl.credit_amount), 0) - coalesce(sum(jl.debit_amount), 0)
      else 0
    end::numeric(14,2) as amount
  from accounts a
  left join journal_lines jl on jl.account_id = a.id
  left join journal_entries je on je.id = jl.entry_id
    and je.entry_date <= p_as_of_date
    and je.status = 'posted'
  where a.type in ('asset', 'liability', 'equity')
    and a.is_active = true
  group by a.id, a.code, a.name, a.type, a.category
  having (coalesce(sum(jl.debit_amount), 0) <> 0 
       or coalesce(sum(jl.credit_amount), 0) <> 0)
  order by 
    case a.type 
      when 'asset' then 1 
      when 'liability' then 2 
      when 'equity' then 3 
      else 4 
    end,
    a.category,
    a.code;
end;
$$;

notify pgrst, 'reload schema';
