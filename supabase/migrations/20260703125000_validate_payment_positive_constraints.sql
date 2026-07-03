do $$
begin
  if exists (
    select 1
      from pg_constraint
     where conrelid = 'public.sales_payments'::regclass
       and conname = 'sales_payments_amount_positive'
  ) then
    alter table public.sales_payments
      validate constraint sales_payments_amount_positive;
  end if;

  if exists (
    select 1
      from pg_constraint
     where conrelid = 'public.purchase_payments'::regclass
       and conname = 'purchase_payments_amount_positive'
  ) then
    alter table public.purchase_payments
      validate constraint purchase_payments_amount_positive;
  end if;
end $$;
