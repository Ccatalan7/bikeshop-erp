-- Reglas de la cartola por empresa: «los cargos que dicen X van a la cuenta
-- Y». La tabla de comercios del conciliador es común a todas las empresas
-- (Google Play / YouTube puede ser del negocio o personal); lo que una
-- empresa decidió —en Viñabike, las suscripciones de YouTube, Google Play y
-- Meli+ son retiros del dueño (2026-09-19)— vive aquí y el conciliador lo
-- propone como sugerencia segura. El operador enseña una regla desde la fila
-- que decidió; enseñar de nuevo el mismo texto la reemplaza.

create table if not exists public.bank_reconciliation_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  pattern text not null
    check (length(pattern) between 3 and 120 and pattern = lower(pattern)),
  direction text not null check (direction in ('debit', 'credit')),
  action text not null check (action in ('post_journal', 'create_expense')),
  account_id uuid not null,
  description text not null
    check (length(trim(description)) between 2 and 200),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (tenant_id, pattern, direction),
  unique (tenant_id, id),
  constraint bank_reconciliation_rules_account_fk
    foreign key (tenant_id, account_id)
    references public.accounts(tenant_id, id) on delete restrict
);

alter table public.bank_reconciliation_rules enable row level security;

drop policy if exists bank_reconciliation_rules_accounting_read
  on public.bank_reconciliation_rules;
create policy bank_reconciliation_rules_accounting_read
  on public.bank_reconciliation_rules for select to authenticated
  using (public.can_manage_tenant_accounting(tenant_id));

revoke all on public.bank_reconciliation_rules
  from public, anon, authenticated;
grant select on public.bank_reconciliation_rules to authenticated;

-- Saves or replaces the rule for a text and direction. An expense rule needs
-- an expense account; money coming in is never an expense.
create or replace function public.save_bank_reconciliation_rule_v1(
  p_pattern text,
  p_direction text,
  p_action text,
  p_account_id uuid,
  p_description text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_user_id uuid := auth.uid();
  v_pattern text := lower(regexp_replace(trim(coalesce(p_pattern, '')), '\s+', ' ', 'g'));
  v_account record;
  v_rule public.bank_reconciliation_rules%rowtype;
begin
  if v_user_id is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  if length(v_pattern) not between 3 and 120
     or coalesce(p_direction, '') not in ('debit', 'credit')
     or coalesce(p_action, '') not in ('post_journal', 'create_expense')
     or length(trim(coalesce(p_description, ''))) not between 2 and 200
     or (p_action = 'create_expense' and p_direction <> 'debit') then
    raise exception using errcode = '22023', message = 'bank_reconciliation_rule_invalid';
  end if;
  select account.id, account.type
    into v_account
    from public.accounts account
   where account.tenant_id = v_tenant_id
     and account.id = p_account_id
     and account.is_active;
  if v_account.id is null
     or (p_action = 'create_expense' and v_account.type <> 'expense') then
    raise exception using errcode = '22023', message = 'bank_reconciliation_rule_account_invalid';
  end if;

  insert into public.bank_reconciliation_rules (
    tenant_id, pattern, direction, action, account_id, description,
    created_by, updated_by
  ) values (
    v_tenant_id, v_pattern, p_direction, p_action, p_account_id,
    trim(p_description), v_user_id, v_user_id
  )
  on conflict (tenant_id, pattern, direction) do update
    set action = excluded.action,
        account_id = excluded.account_id,
        description = excluded.description,
        updated_by = v_user_id,
        updated_at = now()
  returning * into v_rule;

  return jsonb_build_object(
    'rule_id', v_rule.id,
    'pattern', v_rule.pattern,
    'direction', v_rule.direction,
    'action', v_rule.action,
    'account_id', v_rule.account_id,
    'description', v_rule.description
  );
end;
$$;

create or replace function public.delete_bank_reconciliation_rule_v1(
  p_rule_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.user_tenant_id();
begin
  if auth.uid() is null or v_tenant_id is null
     or not public.can_manage_tenant_accounting(v_tenant_id) then
    raise exception using errcode = '42501', message = 'accounting_access_required';
  end if;
  delete from public.bank_reconciliation_rules rule
   where rule.tenant_id = v_tenant_id and rule.id = p_rule_id;
  if not found then
    raise exception using errcode = '42501', message = 'bank_reconciliation_rule_not_accessible';
  end if;
end;
$$;

revoke all on function public.save_bank_reconciliation_rule_v1(text, text, text, uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.delete_bank_reconciliation_rule_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.save_bank_reconciliation_rule_v1(text, text, text, uuid, text)
  to authenticated;
grant execute on function public.delete_bank_reconciliation_rule_v1(uuid)
  to authenticated;
