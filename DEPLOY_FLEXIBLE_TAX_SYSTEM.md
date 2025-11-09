# 🚀 Deploy to Supabase: Flexible Tax System (Complete)

**Copy and run this SQL in your Supabase SQL Editor**

---

## Part 1: Suppliers Table (Add default_tax_treatment)

```sql
-- Add default_tax_treatment column to suppliers
alter table public.suppliers
  add column if not exists default_tax_treatment text not null default 'no_tax' 
    check (default_tax_treatment in ('no_tax', 'tax_included'));

comment on column suppliers.default_tax_treatment is 
  'Suggested tax treatment for purchases from this supplier. tax_included = invoice with IVA, no_tax = receipt or international purchase. User can override per transaction.';
```

---

## Part 2: Sales Invoices Table (Add tax_treatment + net_amount)

```sql
-- Add tax fields to sales_invoices
alter table public.sales_invoices
  add column if not exists tax_treatment text not null default 'no_tax' 
    check (tax_treatment in ('no_tax', 'tax_included')),
  add column if not exists net_amount numeric(12,2) not null default 0;

comment on column sales_invoices.tax_treatment is 
  'Indicates whether this invoice includes IVA. tax_included = divide by 1.19, no_tax = full amount is revenue. User controls per transaction.';

comment on column sales_invoices.net_amount is 
  'Net amount before IVA. When tax_treatment=tax_included, this is total÷1.19. When tax_treatment=no_tax, this equals total.';

-- Migration: Calculate values for existing invoices
do $$
begin
  -- Calculate net_amount from existing iva_amount
  update sales_invoices 
  set net_amount = total - iva_amount 
  where net_amount = 0 and total > 0;
  
  -- Set tax_treatment based on existing iva_amount
  update sales_invoices 
  set tax_treatment = case 
    when iva_amount > 0 then 'tax_included' 
    else 'no_tax' 
  end 
  where tax_treatment = 'no_tax' and total > 0;
end $$;
```

---

## Part 3: Payment Methods Table (Add default_tax_treatment)

```sql
-- Add default_tax_treatment column to payment_methods
alter table public.payment_methods
  add column if not exists default_tax_treatment text not null default 'no_tax' 
    check (default_tax_treatment in ('no_tax', 'tax_included'));

comment on column payment_methods.default_tax_treatment is 
  'Suggested tax treatment for this payment method. tax_included = divide by 1.19, no_tax = full amount is revenue. User can override per transaction.';

-- Migration: Update existing card methods to suggest tax
do $$
begin
  update payment_methods 
  set default_tax_treatment = 'tax_included' 
  where code = 'card' and default_tax_treatment = 'no_tax';
end $$;
```

---

## Part 4: Update seed_payment_methods_for_tenant() Function

```sql
-- Update function to include default_tax_treatment in new payment methods
create or replace function public.seed_payment_methods_for_tenant(p_tenant_id uuid)
returns void
security definer
language plpgsql
as $$
declare
  v_cash_account uuid;
  v_bank_account uuid;
begin
  -- Get account IDs (assumes accounts already seeded)
  select id into v_cash_account 
  from accounts 
  where tenant_id = p_tenant_id and code = '1101' limit 1;
  
  select id into v_bank_account 
  from accounts 
  where tenant_id = p_tenant_id and code = '1102' limit 1;
  
  if v_cash_account is null or v_bank_account is null then
    raise exception 'Cash or Bank account not found for tenant %', p_tenant_id;
  end if;
  
  -- Insert payment methods with tax defaults
  insert into payment_methods (tenant_id, code, name, account_id, requires_reference, sort_order, default_tax_treatment)
  values
    (p_tenant_id, 'cash', 'Efectivo', v_cash_account, false, 1, 'no_tax'),
    (p_tenant_id, 'transfer', 'Transferencia Bancaria', v_bank_account, true, 2, 'no_tax'),
    (p_tenant_id, 'check', 'Cheque', v_bank_account, true, 3, 'no_tax'),
    (p_tenant_id, 'card', 'Tarjeta de Crédito/Débito', v_bank_account, false, 4, 'tax_included')
  on conflict (tenant_id, code) do nothing;
  
  raise notice 'Seeded payment methods for tenant % (Efectivo=no_tax, Transferencia=no_tax, Cheque=no_tax, Tarjeta=tax_included)', p_tenant_id;
end;
$$;
```

---

## Part 5: Purchase Invoices Table (Add tax_treatment + net_amount)

```sql
-- Add tax fields to purchase_invoices
alter table public.purchase_invoices
  add column if not exists tax_treatment text not null default 'no_tax' 
    check (tax_treatment in ('no_tax', 'tax_included')),
  add column if not exists net_amount numeric(12,2) not null default 0;

comment on column purchase_invoices.tax_treatment is 
  'Indicates whether this purchase invoice includes IVA. tax_included = invoice with IVA (divide by 1.19 for net), no_tax = receipt or international purchase (full amount is cost). User controls per transaction.';

comment on column purchase_invoices.net_amount is 
  'Net amount before IVA. When tax_treatment=tax_included, this is total÷1.19. When tax_treatment=no_tax, this equals total.';

-- Migration: Calculate values for existing purchase invoices
do $$
begin
  -- Calculate net_amount from existing tax column
  update purchase_invoices 
  set net_amount = total - tax 
  where net_amount = 0 and total > 0;
  
  -- Set tax_treatment based on existing tax column
  update purchase_invoices 
  set tax_treatment = case 
    when tax > 0 then 'tax_included' 
    else 'no_tax' 
  end 
  where tax_treatment = 'no_tax' and total > 0;
end $$;
```

---

## Verification Queries

After deployment, run these to verify:

```sql
-- Check suppliers have default_tax_treatment column
select count(*), default_tax_treatment 
from suppliers 
group by default_tax_treatment;

-- Check payment_methods have default_tax_treatment (cards should be tax_included)
select code, name, default_tax_treatment 
from payment_methods 
order by sort_order;

-- Check sales_invoices have tax_treatment and net_amount
select count(*), tax_treatment 
from sales_invoices 
group by tax_treatment;

-- Check purchase_invoices have tax_treatment and net_amount
select count(*), tax_treatment 
from purchase_invoices 
group by tax_treatment;

-- Verify calculations (net_amount should be close to total - tax for tax_included)
select 
  invoice_number,
  total,
  iva_amount,
  net_amount,
  tax_treatment,
  (total - iva_amount) as calculated_net
from sales_invoices 
where tax_treatment = 'tax_included'
limit 5;
```

---

## Expected Results

**Suppliers:**
- All existing suppliers: `default_tax_treatment = 'no_tax'` (safe default)
- Can be updated per supplier in settings

**Payment Methods:**
- Cash, Transfer, Check: `default_tax_treatment = 'no_tax'`
- Card: `default_tax_treatment = 'tax_included'`

**Sales Invoices:**
- Existing invoices with `iva_amount > 0`: `tax_treatment = 'tax_included'`
- Existing invoices with `iva_amount = 0`: `tax_treatment = 'no_tax'`
- `net_amount` calculated from existing data

**Purchase Invoices:**
- Existing invoices with `tax > 0`: `tax_treatment = 'tax_included'`
- Existing invoices with `tax = 0`: `tax_treatment = 'no_tax'`
- `net_amount` calculated from existing data

---

## ✅ Deployment Checklist

- [ ] Run Part 1 (Suppliers)
- [ ] Run Part 2 (Sales Invoices)
- [ ] Run Part 3 (Payment Methods)
- [ ] Run Part 4 (Seed Function)
- [ ] Run Part 5 (Purchase Invoices)
- [ ] Run Verification Queries
- [ ] Check results match expected values

**No downtime required** - All migrations are backward compatible with safe defaults.
