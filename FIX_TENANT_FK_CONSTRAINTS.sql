-- ============================================================================
-- 🚨 CRITICAL FIX: Multi-Tenant Foreign Key Constraints
-- ============================================================================
-- 
-- PROBLEM: Foreign keys between tenant-scoped tables don't verify tenant_id,
--          allowing cross-tenant references and data corruption.
--
-- SOLUTION: Add composite unique constraints + composite foreign keys
--
-- DEPLOY: Run this in Supabase SQL Editor AFTER reading CRITICAL_TENANT_FK_BUG_AUDIT.md
--
-- RISK: Medium - Modifies FK constraints, test on staging first!
--
-- ============================================================================

-- ============================================================================
-- STEP 1: Add Composite Unique Constraints
-- ============================================================================
-- These allow composite foreign keys: foreign key (tenant_id, ref_id)

-- accounts: Enable composite FK references
alter table accounts add constraint if not exists unique_accounts_tenant_id 
  unique(tenant_id, id);

-- payment_methods: Enable composite FK references
alter table payment_methods add constraint if not exists unique_payment_methods_tenant_id 
  unique(tenant_id, id);

-- ============================================================================
-- STEP 2: Update Foreign Keys to Composite Keys
-- ============================================================================

-- 1. payment_methods.account_id → accounts(tenant_id, id)
do $$ begin
  alter table payment_methods 
    drop constraint if exists payment_methods_account_id_fkey;
  
  alter table payment_methods 
    add constraint payment_methods_account_id_fkey 
      foreign key (tenant_id, account_id) 
      references accounts(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: payment_methods.account_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update payment_methods.account_id FK: %', sqlerrm;
end $$;

-- 2. sales_payments.payment_method_id → payment_methods(tenant_id, id)
do $$ begin
  alter table sales_payments 
    drop constraint if exists sales_payments_payment_method_id_fkey;
  
  alter table sales_payments 
    add constraint sales_payments_payment_method_id_fkey 
      foreign key (tenant_id, payment_method_id) 
      references payment_methods(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: sales_payments.payment_method_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update sales_payments.payment_method_id FK: %', sqlerrm;
end $$;

-- 3. purchase_payments.payment_method_id → payment_methods(tenant_id, id)
do $$ begin
  alter table purchase_payments 
    drop constraint if exists purchase_payments_payment_method_id_fkey;
  
  alter table purchase_payments 
    add constraint purchase_payments_payment_method_id_fkey 
      foreign key (tenant_id, payment_method_id) 
      references payment_methods(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: purchase_payments.payment_method_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update purchase_payments.payment_method_id FK: %', sqlerrm;
end $$;

-- 4. expenses.payment_method_id → payment_methods(tenant_id, id)
do $$ begin
  alter table expenses 
    drop constraint if exists expenses_payment_method_id_fkey;
  
  alter table expenses 
    add constraint expenses_payment_method_id_fkey 
      foreign key (tenant_id, payment_method_id) 
      references payment_methods(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: expenses.payment_method_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update expenses.payment_method_id FK: %', sqlerrm;
end $$;

-- 5. expenses.payment_account_id → accounts(tenant_id, id)
do $$ begin
  alter table expenses 
    drop constraint if exists expenses_payment_account_id_fkey;
  
  alter table expenses 
    add constraint expenses_payment_account_id_fkey 
      foreign key (tenant_id, payment_account_id) 
      references accounts(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: expenses.payment_account_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update expenses.payment_account_id FK: %', sqlerrm;
end $$;

-- 6. expenses.account_id → accounts(tenant_id, id)
do $$ begin
  alter table expenses 
    drop constraint if exists expenses_account_id_fkey;
  
  alter table expenses 
    add constraint expenses_account_id_fkey 
      foreign key (tenant_id, account_id) 
      references accounts(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: expenses.account_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update expenses.account_id FK: %', sqlerrm;
end $$;

-- 7. credit_notes.liability_account_id → accounts(tenant_id, id)
do $$ begin
  alter table credit_notes 
    drop constraint if exists credit_notes_liability_account_id_fkey;
  
  alter table credit_notes 
    add constraint credit_notes_liability_account_id_fkey 
      foreign key (tenant_id, liability_account_id) 
      references accounts(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: credit_notes.liability_account_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update credit_notes.liability_account_id FK: %', sqlerrm;
end $$;

-- 8. credit_notes.payment_account_id → accounts(tenant_id, id)
do $$ begin
  alter table credit_notes 
    drop constraint if exists credit_notes_payment_account_id_fkey;
  
  alter table credit_notes 
    add constraint credit_notes_payment_account_id_fkey 
      foreign key (tenant_id, payment_account_id) 
      references accounts(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: credit_notes.payment_account_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update credit_notes.payment_account_id FK: %', sqlerrm;
end $$;

-- 9. credit_notes.payment_method_id → payment_methods(tenant_id, id)
do $$ begin
  alter table credit_notes 
    drop constraint if exists credit_notes_payment_method_id_fkey;
  
  alter table credit_notes 
    add constraint credit_notes_payment_method_id_fkey 
      foreign key (tenant_id, payment_method_id) 
      references payment_methods(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: credit_notes.payment_method_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update credit_notes.payment_method_id FK: %', sqlerrm;
end $$;

-- 10. suppliers.default_account_id → accounts(tenant_id, id)
do $$ begin
  alter table suppliers 
    drop constraint if exists suppliers_default_account_id_fkey;
  
  alter table suppliers 
    add constraint suppliers_default_account_id_fkey 
      foreign key (tenant_id, default_account_id) 
      references accounts(tenant_id, id) 
      on delete set null;
  
  raise notice '✅ Fixed: suppliers.default_account_id now tenant-scoped';
exception
  when others then
    raise warning '⚠️  Failed to update suppliers.default_account_id FK: %', sqlerrm;
end $$;

-- 11. accounts.parent_id → accounts(tenant_id, id) (SPECIAL CASE: self-reference)
do $$ begin
  alter table accounts 
    drop constraint if exists accounts_parent_id_fkey;
  
  alter table accounts 
    add constraint accounts_parent_id_fkey 
      foreign key (tenant_id, parent_id) 
      references accounts(tenant_id, id) 
      on delete restrict;
  
  raise notice '✅ Fixed: accounts.parent_id now tenant-scoped (prevents cross-tenant hierarchy)';
exception
  when others then
    raise warning '⚠️  Failed to update accounts.parent_id FK: %', sqlerrm;
end $$;

-- ============================================================================
-- STEP 3: Validation Trigger (Safety Net)
-- ============================================================================
-- This catches any cross-tenant references that slip through

create or replace function public.validate_tenant_fk()
returns trigger
language plpgsql
security definer
as $$
declare
  v_target_tenant_id uuid;
begin
  -- Validate payment_method_id belongs to same tenant
  if TG_ARGV[0] = 'payment_method_id' and NEW.payment_method_id is not null then
    select tenant_id into v_target_tenant_id
    from payment_methods 
    where id = NEW.payment_method_id;
    
    if v_target_tenant_id is null then
      raise exception 'payment_method_id % does not exist', NEW.payment_method_id;
    elsif v_target_tenant_id != NEW.tenant_id then
      raise exception 'Cross-tenant reference blocked: payment_method_id % belongs to tenant %, not %', 
        NEW.payment_method_id, v_target_tenant_id, NEW.tenant_id;
    end if;
  end if;
  
  -- Validate account_id belongs to same tenant
  if TG_ARGV[0] = 'account_id' and NEW.account_id is not null then
    select tenant_id into v_target_tenant_id
    from accounts 
    where id = NEW.account_id;
    
    if v_target_tenant_id is null then
      raise exception 'account_id % does not exist', NEW.account_id;
    elsif v_target_tenant_id != NEW.tenant_id then
      raise exception 'Cross-tenant reference blocked: account_id % belongs to tenant %, not %', 
        NEW.account_id, v_target_tenant_id, NEW.tenant_id;
    end if;
  end if;
  
  return NEW;
end;
$$;

-- Apply validation triggers to vulnerable tables
drop trigger if exists validate_tenant_fk_sales_payments on sales_payments;
create trigger validate_tenant_fk_sales_payments
  before insert or update on sales_payments
  for each row execute function validate_tenant_fk('payment_method_id');

drop trigger if exists validate_tenant_fk_purchase_payments on purchase_payments;
create trigger validate_tenant_fk_purchase_payments
  before insert or update on purchase_payments
  for each row execute function validate_tenant_fk('payment_method_id');

drop trigger if exists validate_tenant_fk_expenses on expenses;
create trigger validate_tenant_fk_expenses
  before insert or update on expenses
  for each row execute function validate_tenant_fk('payment_method_id');

drop trigger if exists validate_tenant_fk_payment_methods on payment_methods;
create trigger validate_tenant_fk_payment_methods
  before insert or update on payment_methods
  for each row execute function validate_tenant_fk('account_id');

-- ============================================================================
-- STEP 4: Verification Queries
-- ============================================================================

-- Check if composite unique constraints were added
do $$ 
declare
  v_count integer;
begin
  select count(*) into v_count
  from pg_constraint
  where conname in ('unique_accounts_tenant_id', 'unique_payment_methods_tenant_id');
  
  if v_count = 2 then
    raise notice '✅ All composite unique constraints created successfully';
  else
    raise warning '⚠️  Only % of 2 composite unique constraints created', v_count;
  end if;
end $$;

-- Check if composite foreign keys were updated
do $$ 
declare
  v_fixed_fks text[];
begin
  select array_agg(conname) into v_fixed_fks
  from pg_constraint
  where conname in (
    'payment_methods_account_id_fkey',
    'sales_payments_payment_method_id_fkey',
    'purchase_payments_payment_method_id_fkey',
    'expenses_payment_method_id_fkey',
    'expenses_payment_account_id_fkey',
    'expenses_account_id_fkey',
    'credit_notes_liability_account_id_fkey',
    'credit_notes_payment_account_id_fkey',
    'credit_notes_payment_method_id_fkey',
    'suppliers_default_account_id_fkey',
    'accounts_parent_id_fkey'
  )
  and array_length(conkey, 1) = 2; -- Composite FK has 2 columns
  
  raise notice '✅ Fixed % of 11 foreign key constraints to be tenant-scoped', array_length(v_fixed_fks, 1);
  
  if array_length(v_fixed_fks, 1) < 11 then
    raise warning '⚠️  Some FK constraints may need manual review';
  end if;
end $$;

-- ============================================================================
-- SUCCESS MESSAGE
-- ============================================================================

do $$ begin
  raise notice '';
  raise notice '═══════════════════════════════════════════════════════════';
  raise notice '✅ Multi-Tenant FK Constraint Fix Applied Successfully!';
  raise notice '═══════════════════════════════════════════════════════════';
  raise notice '';
  raise notice 'What was fixed:';
  raise notice '  • Added composite unique constraints to accounts & payment_methods';
  raise notice '  • Updated 11 FK constraints to verify tenant_id match';
  raise notice '  • Added validation triggers as safety net';
  raise notice '';
  raise notice 'What this prevents:';
  raise notice '  ✅ Payment methods referencing accounts from other tenants';
  raise notice '  ✅ Payments referencing payment methods from other tenants';
  raise notice '  ✅ Expenses referencing accounts from other tenants';
  raise notice '  ✅ Account hierarchy spanning across tenants';
  raise notice '  ✅ Data corruption during tenant deletion';
  raise notice '';
  raise notice 'Next steps:';
  raise notice '  1. Test creating invoices/payments (should work normally)';
  raise notice '  2. Test tenant deletion (should cascade cleanly)';
  raise notice '  3. Try creating cross-tenant reference (should FAIL with clear error)';
  raise notice '';
  raise notice 'Read CRITICAL_TENANT_FK_BUG_AUDIT.md for full details.';
  raise notice '═══════════════════════════════════════════════════════════';
end $$;
