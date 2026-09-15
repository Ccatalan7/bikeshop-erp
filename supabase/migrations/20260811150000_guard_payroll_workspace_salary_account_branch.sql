begin;

-- Deployment status: local/off-production candidate; not deployed.
-- Forward behavior: rejects new or changed additional-expense workspace legs
-- when their account belongs to the connected tree branch of a tenant salary
-- account, including its parents, siblings, and descendants.
-- Existing rows are not rewritten or backfilled.
-- Recovery: drop the trigger, then the function; no business data changes are
-- required because every rejection rolls back with the caller transaction.
-- Lock risk: CREATE FUNCTION plus DROP/CREATE TRIGGER take brief catalog locks
-- on payroll_payment_workspace_legs and perform no table scan or backfill.

create or replace function
  public.guard_payroll_workspace_additional_expense_salary_branch()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.leg_type is distinct from 'additional_expense' then
    return new;
  end if;

  if exists (
    with recursive
    salary_accounts(account_id) as (
      select employee.salary_account_id
      from public.employees employee
      where employee.tenant_id = new.tenant_id
        and employee.salary_account_id is not null
      union
      select voucher_line.salary_account_id
      from public.payroll_voucher_lines voucher_line
      where voucher_line.tenant_id = new.tenant_id
        and voucher_line.salary_account_id is not null
    ),
    account_edges(account_id, connected_account_id) as (
      select account.id, account.parent_id
      from public.accounts account
      where account.tenant_id = new.tenant_id
        and account.parent_id is not null

      union all

      select account.parent_id, account.id
      from public.accounts account
      where account.tenant_id = new.tenant_id
        and account.parent_id is not null
    ),
    salary_branch(account_id) as (
      select salary.account_id
      from salary_accounts salary

      union

      select edge.connected_account_id
      from salary_branch branch
      join account_edges edge
        on edge.account_id = branch.account_id
    )
    select 1
    from salary_branch branch
    where branch.account_id = new.expense_account_id
  ) then
    raise exception 'payroll_workspace_salary_account_branch_forbidden'
      using
        errcode = '23514',
        constraint =
          'payroll_workspace_additional_expense_salary_branch_check';
  end if;

  return new;
end;
$$;

revoke all on function
  public.guard_payroll_workspace_additional_expense_salary_branch()
  from public, anon, authenticated, service_role;

drop trigger if exists
  trg_guard_payroll_workspace_additional_expense_salary_branch
  on public.payroll_payment_workspace_legs;
create trigger trg_guard_payroll_workspace_additional_expense_salary_branch
  before insert or update on public.payroll_payment_workspace_legs
  for each row execute function
    public.guard_payroll_workspace_additional_expense_salary_branch();

comment on function
  public.guard_payroll_workspace_additional_expense_salary_branch() is
  'Rejects additional-expense workspace legs in the connected account-tree branch of any tenant salary account, including parents, siblings, and descendants.';

commit;
