do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conrelid = 'public.accounts'::regclass
       and contype = 'u'
       and conname = 'accounts_tenant_id_id_key'
  ) then
    alter table public.accounts
      add constraint accounts_tenant_id_id_key unique (tenant_id, id);
  end if;
end $$;

alter table public.expense_categories
  drop constraint if exists expense_categories_default_account_id_fkey;

alter table public.expense_categories
  add constraint expense_categories_default_account_id_fkey
  foreign key (tenant_id, default_account_id)
  references public.accounts(tenant_id, id)
  on delete set null;