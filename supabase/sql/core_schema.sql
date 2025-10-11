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

select public.migrate_accounts_to_uuid();

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
          'paid','pagado','pagada',
          'overdue','vencido','vencida',
          'cancelled','cancelado','cancelada','anulado','anulada'
        ]));
  end if;
end $$;

create table if not exists sales_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references sales_invoices(id) on delete cascade,
  invoice_reference text,
  method text not null
    check (method in ('cash','card','transfer','check','other')),
  amount numeric(12,2) not null default 0,
  date timestamp with time zone not null default now(),
  reference text,
  notes text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

create index if not exists idx_sales_payments_invoice_id
  on sales_payments(invoice_id);

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

  if v_invoice.status = 'cancelled' then
    v_new_status := v_invoice.status;
  elsif v_invoice.status = 'draft' and v_total = 0 then
    v_new_status := 'draft';
  elsif v_total >= coalesce(v_invoice.total, 0) then
    v_new_status := 'paid';
  elsif v_invoice.status = 'overdue' and v_balance > 0 then
    v_new_status := 'overdue';
  elsif v_total > 0 then
    v_new_status := 'sent';
  else
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
  v_cash_account_code text;
  v_cash_account_name text;
  v_cash_account_id uuid;
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

  case coalesce(p_payment.method, 'other')
    when 'cash' then
      v_cash_account_code := '1101';
      v_cash_account_name := 'Caja General';
    when 'card' then
      v_cash_account_code := '1110';
      v_cash_account_name := 'Bancos - Cuenta Corriente';
    when 'transfer' then
      v_cash_account_code := '1110';
      v_cash_account_name := 'Bancos - Cuenta Corriente';
    when 'check' then
      v_cash_account_code := '1110';
      v_cash_account_name := 'Bancos - Cuenta Corriente';
    else
      v_cash_account_code := '1190';
      v_cash_account_name := 'Otros Activos Corrientes';
  end case;

  v_cash_account_id := public.ensure_account(
    v_cash_account_code,
    v_cash_account_name,
    'asset',
    'currentAsset',
    v_cash_account_name,
    null
  );

  v_receivable_account_id := public.ensure_account(
    v_receivable_account_code,
    v_receivable_account_name,
    'asset',
    'currentAsset',
    'Cuentas por cobrar a clientes',
    null
  );

  v_description := format('Pago factura %s', coalesce(v_invoice.invoice_number, v_invoice.id::text));

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

    v_quantity_int := coalesce(v_movement.quantity::int, 0);

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
  v_non_posted constant text[] := array['draft','borrador','cancelled','cancelado','cancelada','anulado','anulada'];
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
    
    -- If inserted with posted status, consume inventory
    if not (v_new_status = any (v_non_posted)) then
      perform public.consume_sales_invoice_inventory(NEW);
    end if;
    
    -- Create journal entry
    perform public.create_sales_invoice_journal_entry(NEW);
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

    -- Update journal entries
    perform public.delete_sales_invoice_journal_entry(OLD.id);
    perform public.create_sales_invoice_journal_entry(NEW);
    perform public.recalculate_sales_invoice_payments(NEW.id);
    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := lower(coalesce(OLD.status, 'draft'));
    raise notice 'handle_sales_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;
    
    -- If was posted, restore inventory
    if not (v_old_status = any (v_non_posted)) then
      perform public.restore_sales_invoice_inventory(OLD);
    end if;
    
    perform public.delete_sales_invoice_journal_entry(OLD.id);
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
    check (status in ('draft','received','paid','cancelled')),
  subtotal numeric(12,2) not null default 0,
  iva_amount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
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
  add column if not exists iva_amount numeric(12,2) not null default 0,
  add column if not exists total numeric(12,2) not null default 0,
  add column if not exists items jsonb not null default '[]'::jsonb,
  add column if not exists additional_costs jsonb not null default '[]'::jsonb,
  add column if not exists created_at timestamp with time zone not null default now(),
  add column if not exists updated_at timestamp with time zone not null default now();

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
        check (status in ('draft','received','paid','cancelled'));
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

notify pgrst, 'reload schema';
