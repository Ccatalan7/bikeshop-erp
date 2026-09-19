-- What the week ended up with: only Nómina's payment, and the review's
-- decision nowhere.
select
  (select count(*) from public.expense_payments
    where tenant_id = 'e9000000-0000-4000-8000-000000000001') as pagos,
  (select coalesce(sum(amount), 0) from public.expense_payments
    where tenant_id = 'e9000000-0000-4000-8000-000000000001') as pagado,
  (select count(*) from public.bank_reconciliation_row_decisions
    where tenant_id = 'e9000000-0000-4000-8000-000000000001') as decisiones,
  (select count(*) from public.bank_reconciliation_operations
    where tenant_id = 'e9000000-0000-4000-8000-000000000001') as operaciones;
