-- Preserve expense-category ownership when its optional default account is
-- deleted.
-- Deployment status: NOT DEPLOYED.
-- Recovery: replace the constraint with ON DELETE RESTRICT if account deletion
-- must be stopped while category ownership is investigated.
-- Lock/backfill risk: brief catalog lock while one validated FK is replaced;
-- no table rewrite or data backfill.

alter table public.expense_categories
  drop constraint if exists expense_categories_default_account_id_fkey;

alter table public.expense_categories
  add constraint expense_categories_default_account_id_fkey
  foreign key (tenant_id, default_account_id)
  references public.accounts(tenant_id, id)
  on delete set null (default_account_id);
