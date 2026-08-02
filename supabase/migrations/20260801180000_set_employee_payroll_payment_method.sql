-- Deployment status: pending guarded production deployment and read-back.
--
-- Forward behavior:
--   Atomically changes only an employee's payroll payment configuration. The
--   server locks the employee and selected payment-method/account rows,
--   derives the legacy method code from the selected method, and rejects a
--   stale employee version before writing.
--
-- Recovery behavior:
--   Dropping this function restores the prior client-side narrow-update path.
--   No existing employee rows are backfilled or rewritten by this migration.
--
-- Lock/timeout risk:
--   Each call locks one employee plus one payment method and its backing
--   account for the duration of a single short transaction. The migration
--   itself creates only a function and performs no business-row writes.

create or replace function public.set_employee_payroll_payment_method(
  p_employee_id uuid,
  p_expected_updated_at timestamp with time zone,
  p_method_id uuid,
  p_bank_name text default null,
  p_bank_account_type text default null,
  p_bank_account_number text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  tenant_id_value uuid := public.erp_member_tenant_id();
  employee_row public.employees%rowtype;
  method_row public.payment_methods%rowtype;
  method_code text;
  clean_bank_name text := nullif(btrim(p_bank_name), '');
  clean_bank_account_type text := nullif(btrim(p_bank_account_type), '');
  clean_bank_account_number text := nullif(btrim(p_bank_account_number), '');
begin
  if p_employee_id is null
     or p_expected_updated_at is null
     or p_method_id is null then
    raise exception 'payroll_employee_payment_method_invalid'
      using errcode = '22023';
  end if;

  if tenant_id_value is null
     or not public.can_manage_tenant_hr(tenant_id_value) then
    raise exception 'payroll_employee_payment_method_not_authorized'
      using errcode = '42501';
  end if;

  select employee.*
  into employee_row
  from public.employees employee
  where employee.id = p_employee_id
    and employee.tenant_id = tenant_id_value
  for update;

  if not found then
    raise exception 'payroll_employee_payment_method_employee_not_found'
      using errcode = 'P0002';
  end if;

  if employee_row.updated_at is distinct from p_expected_updated_at then
    raise exception 'payroll_employee_payment_method_version_conflict'
      using errcode = '40001';
  end if;

  select payment_method.*
  into method_row
  from public.payment_methods payment_method
  join public.accounts backing_account
    on backing_account.id = payment_method.account_id
   and backing_account.tenant_id = tenant_id_value
   and backing_account.is_active is true
  where payment_method.id = p_method_id
    and payment_method.tenant_id = tenant_id_value
    and payment_method.is_active is true
  for share of payment_method, backing_account;

  if not found then
    raise exception 'payroll_employee_payment_method_unavailable'
      using errcode = '23503';
  end if;

  method_code := lower(btrim(method_row.code));
  if method_code not in ('cash', 'transfer') then
    raise exception 'payroll_employee_payment_method_unsupported'
      using errcode = '23514';
  end if;

  if method_code = 'transfer' then
    if clean_bank_name is null or clean_bank_account_number is null then
      raise exception 'payroll_employee_payment_method_bank_details_required'
        using errcode = '23514';
    end if;
    if clean_bank_account_type is not null
       and clean_bank_account_type not in (
         'Cuenta Corriente',
         'Cuenta Vista',
         'Cuenta de Ahorro'
       ) then
      raise exception 'payroll_employee_payment_method_bank_type_invalid'
        using errcode = '23514';
    end if;
  end if;

  update public.employees employee
  set preferred_payment_method_id = method_row.id,
      preferred_payment_method = method_code,
      bank_name = case
        when method_code = 'transfer' then clean_bank_name
        else employee.bank_name
      end,
      bank_account_type = case
        when method_code = 'transfer' then clean_bank_account_type
        else employee.bank_account_type
      end,
      bank_account_number = case
        when method_code = 'transfer' then clean_bank_account_number
        else employee.bank_account_number
      end
  where employee.id = employee_row.id
    and employee.tenant_id = tenant_id_value
  returning employee.* into employee_row;

  return jsonb_build_object(
    'id', employee_row.id,
    'tenant_id', employee_row.tenant_id,
    'updated_at', employee_row.updated_at,
    'preferred_payment_method', employee_row.preferred_payment_method,
    'preferred_payment_method_id', employee_row.preferred_payment_method_id,
    'bank_name', employee_row.bank_name,
    'bank_account_type', employee_row.bank_account_type,
    'bank_account_number', employee_row.bank_account_number
  );
end;
$$;

revoke all on function public.set_employee_payroll_payment_method(
  uuid,
  timestamp with time zone,
  uuid,
  text,
  text,
  text
) from public, anon, authenticated, service_role;

grant execute on function public.set_employee_payroll_payment_method(
  uuid,
  timestamp with time zone,
  uuid,
  text,
  text,
  text
) to authenticated;

comment on function public.set_employee_payroll_payment_method(
  uuid,
  timestamp with time zone,
  uuid,
  text,
  text,
  text
) is
  'Atomically updates one same-tenant employee payment configuration under an exact updated_at guard. The server derives cash/transfer from one active, backed tenant payment method and preserves stored bank data when cash is selected.';
