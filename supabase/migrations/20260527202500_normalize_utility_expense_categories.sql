-- Normalize utility expense categorization:
-- Agua/Luz stay as dedicated ledger accounts, but the expense category remains
-- the broader Servicios Básicos bucket.

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

with utility_categories as (
  select
    ec.id,
    ec.tenant_id,
    services.id as services_category_id
  from public.expense_categories ec
  join public.accounts utility_account
    on utility_account.id = ec.default_account_id
   and utility_account.tenant_id = ec.tenant_id
   and utility_account.code in ('6202-01', '6202-02')
  join public.expense_categories services
    on services.tenant_id = ec.tenant_id
   and lower(services.name) = lower('Servicios Básicos')
  where lower(ec.name) in (lower('Agua'), lower('Luz'))
)
update public.expenses e
set category_id = utility_categories.services_category_id
from utility_categories
where e.category_id = utility_categories.id;

with utility_categories as (
  select
    ec.id,
    ec.tenant_id,
    services.id as services_category_id
  from public.expense_categories ec
  join public.accounts utility_account
    on utility_account.id = ec.default_account_id
   and utility_account.tenant_id = ec.tenant_id
   and utility_account.code in ('6202-01', '6202-02')
  join public.expense_categories services
    on services.tenant_id = ec.tenant_id
   and lower(services.name) = lower('Servicios Básicos')
  where lower(ec.name) in (lower('Agua'), lower('Luz'))
)
update public.expense_templates template
set
  default_category_id = case
    when template.default_category_id = utility_categories.id
      then utility_categories.services_category_id
    else template.default_category_id
  end,
  trigger_category_id = case
    when template.trigger_category_id = utility_categories.id
      then utility_categories.services_category_id
    else template.trigger_category_id
  end,
  updated_at = now()
from utility_categories
where template.tenant_id = utility_categories.tenant_id
  and (
    template.default_category_id = utility_categories.id
    or template.trigger_category_id = utility_categories.id
  );

delete from public.expense_categories ec
using public.accounts utility_account
where utility_account.id = ec.default_account_id
  and utility_account.tenant_id = ec.tenant_id
  and utility_account.code in ('6202-01', '6202-02')
  and lower(ec.name) in (lower('Agua'), lower('Luz'))
  and ec.created_at >= timestamp with time zone '2026-05-27 00:00:00+00'
  and not exists (
    select 1
    from public.expenses e
    where e.category_id = ec.id
  )
  and not exists (
    select 1
    from public.expense_templates template
    where template.default_category_id = ec.id
       or template.trigger_category_id = ec.id
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
