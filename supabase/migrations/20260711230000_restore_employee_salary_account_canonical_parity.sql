-- Deployment status: NOT DEPLOYED. Additive canonical parity guard.
-- The payroll settlement functions already depend on this nullable employee
-- account link, and older production history may already have installed it.

begin;

alter table public.employees
  add column if not exists salary_account_id uuid
  references public.accounts(id);

create index if not exists idx_employees_salary_account
  on public.employees(salary_account_id);

commit;
