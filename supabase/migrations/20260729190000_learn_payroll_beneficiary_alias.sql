-- Audited RPC-only writer for payroll beneficiary aliases.
--
-- Deployment status: NOT DEPLOYED. Production deployment only through the
-- owner-authorized checkpoint in docs/development/PAYROLL_COMPLETION_PLAN.md.
-- Atomicity: this file runs as one explicit transaction; a mid-file failure
-- rolls back every change (no CONCURRENTLY/VACUUM/enum-value statements).
-- Recovery: drop the learn function and restore the prior alias-table ACL
-- from the immediately preceding snapshot; no data rewrite occurs.

begin;

-- Alias learning is an explicit, post-payment opt-in. The command is
-- idempotent for the same employee and never reassigns an existing normalized
-- bank identity to somebody else.
drop function if exists public.learn_payroll_beneficiary_alias(uuid, text);

create function public.learn_payroll_beneficiary_alias(
  p_employee_id uuid,
  p_alias text
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  actor_id_value uuid := auth.uid();
  tenant_id_value uuid;
  alias_value text := btrim(coalesce(p_alias, ''));
  normalized_alias_value text;
  existing_alias public.payroll_beneficiary_aliases%rowtype;
  inserted_alias public.payroll_beneficiary_aliases%rowtype;
begin
  if actor_id_value is null then
    raise exception 'payroll_alias_authentication_required'
      using errcode = '28000';
  end if;

  tenant_id_value := public.erp_member_tenant_id();
  if tenant_id_value is null
     or not public.can_manage_tenant_payroll(tenant_id_value) then
    raise exception 'payroll_alias_not_authorized'
      using errcode = '42501';
  end if;

  normalized_alias_value :=
    public.normalize_payroll_statement_text(alias_value);
  if p_employee_id is null
     or char_length(alias_value) not between 2 and 160
     or normalized_alias_value is null then
    raise exception 'payroll_alias_invalid'
      using errcode = '22023';
  end if;

  perform 1
  from public.employees employee
  where employee.tenant_id = tenant_id_value
    and employee.id = p_employee_id;
  if not found then
    raise exception 'payroll_alias_employee_not_found'
      using errcode = '23503';
  end if;

  select alias_row.*
  into existing_alias
  from public.payroll_beneficiary_aliases alias_row
  where alias_row.tenant_id = tenant_id_value
    and alias_row.normalized_alias = normalized_alias_value;

  if found then
    if existing_alias.employee_id <> p_employee_id then
      return jsonb_build_object(
        'status', 'conflict',
        'employee_id', p_employee_id,
        'alias', alias_value,
        'normalized_alias', normalized_alias_value
      );
    end if;
    return jsonb_build_object(
      'status', 'existing',
      'alias_id', existing_alias.id,
      'employee_id', existing_alias.employee_id,
      'alias', existing_alias.alias,
      'normalized_alias', existing_alias.normalized_alias
    );
  end if;

  insert into public.payroll_beneficiary_aliases (
    tenant_id,
    employee_id,
    alias,
    normalized_alias,
    created_by
  )
  values (
    tenant_id_value,
    p_employee_id,
    alias_value,
    normalized_alias_value,
    actor_id_value
  )
  on conflict (tenant_id, normalized_alias) do nothing
  returning * into inserted_alias;

  if found then
    return jsonb_build_object(
      'status', 'created',
      'alias_id', inserted_alias.id,
      'employee_id', inserted_alias.employee_id,
      'alias', inserted_alias.alias,
      'normalized_alias', inserted_alias.normalized_alias
    );
  end if;

  -- A concurrent writer won the unique key. Resolve the resulting identity
  -- without updating or reassigning it.
  select alias_row.*
  into existing_alias
  from public.payroll_beneficiary_aliases alias_row
  where alias_row.tenant_id = tenant_id_value
    and alias_row.normalized_alias = normalized_alias_value;

  if existing_alias.employee_id = p_employee_id then
    return jsonb_build_object(
      'status', 'existing',
      'alias_id', existing_alias.id,
      'employee_id', existing_alias.employee_id,
      'alias', existing_alias.alias,
      'normalized_alias', existing_alias.normalized_alias
    );
  end if;

  return jsonb_build_object(
    'status', 'conflict',
    'employee_id', p_employee_id,
    'alias', alias_value,
    'normalized_alias', normalized_alias_value
  );
end;
$$;

revoke all on function public.learn_payroll_beneficiary_alias(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.learn_payroll_beneficiary_alias(uuid, text)
  to authenticated;

revoke insert, update, delete
  on table public.payroll_beneficiary_aliases
  from authenticated;
grant select on table public.payroll_beneficiary_aliases to authenticated;

comment on function public.learn_payroll_beneficiary_alias(uuid, text) is
  'Idempotently remembers one explicitly approved normalized bank beneficiary for one tenant employee without permitting reassignment.';

commit;
