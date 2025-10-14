-- ============================================================================
-- FIX: Add payment_method_id to existing sales_payments table
-- Run this ONCE before deploying core_schema.sql
-- ============================================================================

-- Step 1: Add payment_method_id column if it doesn't exist
do $$
declare
  v_has_payment_method_id boolean;
  v_has_method_column boolean;
  v_cash_method_id uuid;
begin
  -- Check if payment_method_id already exists
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sales_payments'
      and column_name = 'payment_method_id'
  ) into v_has_payment_method_id;

  if v_has_payment_method_id then
    raise notice 'payment_method_id column already exists, skipping migration';
    return;
  end if;

  -- Check if old 'method' column exists
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'sales_payments'
      and column_name = 'method'
  ) into v_has_method_column;

  if not v_has_method_column then
    raise notice 'No old method column found, sales_payments might be empty';
  end if;

  raise notice 'Adding payment_method_id column to sales_payments...';

  -- Add new column (nullable first)
  alter table sales_payments add column payment_method_id uuid;

  -- Get cash payment method ID as default
  select id into v_cash_method_id from payment_methods where code = 'cash' limit 1;

  if v_cash_method_id is null then
    raise exception 'Cash payment method not found! Run core_schema.sql payment_methods section first.';
  end if;

  -- Migrate data: map old method values to payment_method_id
  if v_has_method_column then
    update sales_payments sp
    set payment_method_id = pm.id
    from payment_methods pm
    where sp.payment_method_id is null
      and (
        (lower(sp.method) = 'cash' and pm.code = 'cash') or
        (lower(sp.method) in ('transfer', 'transferencia') and pm.code = 'transfer') or
        (lower(sp.method) in ('card', 'tarjeta') and pm.code = 'card') or
        (lower(sp.method) in ('check', 'cheque') and pm.code = 'check')
      );
  end if;

  -- Set default for any remaining nulls
  update sales_payments
  set payment_method_id = v_cash_method_id
  where payment_method_id is null;

  -- Add foreign key constraint
  alter table sales_payments 
    add constraint sales_payments_payment_method_id_fkey 
    foreign key (payment_method_id) 
    references payment_methods(id);

  -- Make payment_method_id NOT NULL
  alter table sales_payments alter column payment_method_id set not null;

  -- Drop old method column and constraint if exists
  alter table sales_payments drop constraint if exists sales_payments_method_check;
  alter table sales_payments drop column if exists method;

  raise notice 'Migration complete! payment_method_id added successfully.';
end $$;

-- Step 2: Create indexes if they don't exist
create index if not exists idx_sales_payments_payment_method_id
  on sales_payments(payment_method_id);

-- Step 3: Same fix for purchase_payments (invoice_id + payment_method_id)
do $$
declare
  v_table_exists boolean;
  v_has_invoice_id boolean;
  v_has_old_invoice_id boolean;
  v_has_payment_method_id boolean;
  v_has_old_method boolean;
  v_cash_method_id uuid;
begin
  -- Check if purchase_payments table exists
  select exists (
    select 1 from information_schema.tables
    where table_schema = 'public'
      and table_name = 'purchase_payments'
  ) into v_table_exists;

  if not v_table_exists then
    raise notice 'purchase_payments table does not exist yet, skipping migration';
    return;
  end if;
  -- Check current state
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

  raise notice 'purchase_payments state: invoice_id=%, old_invoice_id=%, payment_method_id=%, old_method=%',
    v_has_invoice_id, v_has_old_invoice_id, v_has_payment_method_id, v_has_old_method;

  -- Fix invoice_id column name
  if v_has_old_invoice_id and not v_has_invoice_id then
    raise notice 'Renaming purchase_invoice_id to invoice_id...';
    alter table purchase_payments rename column purchase_invoice_id to invoice_id;
    v_has_invoice_id := true;
  elsif not v_has_invoice_id then
    raise notice 'Adding invoice_id column...';
    alter table purchase_payments add column invoice_id uuid not null references purchase_invoices(id) on delete cascade;
    v_has_invoice_id := true;
  end if;

  -- Fix payment_method_id
  if not v_has_payment_method_id then
    raise notice 'Adding payment_method_id column to purchase_payments...';

    -- Get cash payment method ID as default
    select id into v_cash_method_id from payment_methods where code = 'cash' limit 1;

    if v_cash_method_id is null then
      raise exception 'Cash payment method not found!';
    end if;

    -- Add new column (nullable first)
    alter table purchase_payments add column payment_method_id uuid;

    -- Migrate from 'method' if exists
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

    -- Migrate from 'payment_method' if exists
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

    raise notice 'Migration complete! purchase_payments.payment_method_id added successfully.';
  else
    raise notice 'purchase_payments.payment_method_id already exists, skipping';
  end if;
end $$;

-- Step 4: Create index for purchase_payments
create index if not exists idx_purchase_payments_payment_method_id
  on purchase_payments(payment_method_id);

-- Verification queries
select 'sales_payments column check' as check_name, 
       exists(select 1 from information_schema.columns 
              where table_name = 'sales_payments' 
              and column_name = 'payment_method_id') as has_column;

select 'purchase_payments column check' as check_name,
       exists(select 1 from information_schema.columns 
              where table_name = 'purchase_payments' 
              and column_name = 'payment_method_id') as has_column;

select 'sales_payments record count' as info, count(*) as total from sales_payments;
select 'purchase_payments record count' as info, count(*) as total from purchase_payments;

raise notice '✅ Migration complete! You can now run core_schema.sql safely.';
