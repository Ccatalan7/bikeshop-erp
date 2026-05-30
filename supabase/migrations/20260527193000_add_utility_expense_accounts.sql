-- Add dedicated utility expense accounts for quick expense OCR.
-- These sit under Servicios Básicos so existing reports keep grouping them
-- correctly, while quick capture can post Agua and Luz separately.

with utility_accounts(code, name, description) as (
  values
    (
      '6202-01',
      'Agua',
      'Pagos de agua potable, alcantarillado y servicios sanitarios'
    ),
    (
      '6202-02',
      'Luz',
      'Pagos de electricidad y servicios de energía eléctrica'
    )
)
insert into public.accounts (
  tenant_id,
  code,
  name,
  type,
  category,
  description,
  parent_id,
  is_active
)
select
  t.id,
  ua.code,
  ua.name,
  'expense',
  'operatingExpense',
  ua.description,
  parent_account.id,
  true
from public.tenants t
cross join utility_accounts ua
left join public.accounts parent_account
  on parent_account.tenant_id = t.id
 and parent_account.code = '6202'
where not exists (
  select 1
  from public.accounts existing
  where existing.tenant_id = t.id
    and existing.code = ua.code
);

-- Keep categories broad: Agua/Luz are ledger subaccounts, while
-- Servicios Básicos is the operational reporting category.
insert into public.expense_categories (
  tenant_id,
  name,
  description,
  default_account_id,
  default_tax_rate
)
select
  parent_account.tenant_id,
  'Servicios Básicos',
  'Electricidad, agua, gas y otros servicios básicos',
  parent_account.id,
  0
from public.accounts parent_account
where parent_account.code = '6202'
  and not exists (
    select 1
    from public.expense_categories existing
    where existing.tenant_id = parent_account.tenant_id
      and lower(existing.name) = lower('Servicios Básicos')
  );

update public.expense_categories ec
set
  default_account_id = parent_account.id,
  description = coalesce(
    nullif(ec.description, ''),
    'Electricidad, agua, gas y otros servicios básicos'
  ),
  updated_at = now()
from public.accounts parent_account
where parent_account.tenant_id = ec.tenant_id
  and parent_account.code = '6202'
  and lower(ec.name) = lower('Servicios Básicos')
  and (
    ec.default_account_id is distinct from parent_account.id
    or coalesce(ec.description, '') = ''
  );

create or replace function public.get_expense_category_name_for_account(
  p_account_code text,
  p_account_name text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := coalesce(p_account_code, '');
  v_base_code text;
  v_name text := lower(coalesce(p_account_name, ''));
begin
  v_base_code := regexp_replace(v_code, '-.*$', '');

  if v_base_code like '51%' then
    return 'Costo de Ventas';
  end if;

  if v_base_code like '610%' then
    return 'Nómina';
  end if;

  if v_base_code = '6201' then
    return 'Arriendo';
  elsif v_base_code = '6202' then
    return 'Servicios Básicos';
  elsif v_base_code = '6203' then
    return 'Telefonía e Internet';
  elsif v_base_code = '6204' then
    return 'Mantención y Reparaciones';
  elsif v_base_code = '6205' then
    return 'Suministros de Oficina';
  end if;

  if v_base_code = '6301' then
    return 'Marketing y Publicidad';
  elsif v_base_code = '6302' then
    return 'Comisiones de Venta';
  end if;

  if v_base_code = '6401' then
    return 'Gastos de Viaje';
  elsif v_base_code = '6402' then
    return 'Gastos por Transporte';
  end if;

  if v_base_code = '6501' then
    return 'Seguros';
  elsif v_base_code = '6502' then
    return 'Patentes y Contribuciones';
  end if;

  if v_base_code = '6601' then
    return 'Gastos Financieros';
  end if;

  if v_base_code = '6701' then
    return 'Depreciación';
  end if;

  if v_base_code = '6801' then
    return 'Gastos Varios';
  end if;

  if v_name like '%nómina%' or v_name like '%nomina%' or v_name like '%sueldo%' or v_name like '%salario%' then
    return 'Nómina';
  end if;
  if v_name like '%arriendo%' then
    return 'Arriendo';
  end if;
  if v_name like '%internet%' or v_name like '%telefon%' then
    return 'Telefonía e Internet';
  end if;
  if v_name like '%agua%' or v_name like '%esval%' or v_name like '%aguas%' or v_name like '%luz%' or v_name like '%electric%' or v_name like '%energía%' or v_name like '%energia%' or v_name like '%gas%' or v_name like '%servicio básico%' or v_name like '%servicios básicos%' then
    return 'Servicios Básicos';
  end if;

  if v_name like '%transporte%' or v_name like '%flete%' or v_name like '%envío%' or v_name like '%envio%' or v_name like '%encomienda%' then
    return 'Gastos por Transporte';
  end if;

  return 'Otros Gastos';
end;
$$;
