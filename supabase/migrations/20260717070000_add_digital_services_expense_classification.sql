-- Classify website domains and hosting as digital services rather than
-- telephone/internet. The ledger account stays precise while the operational
-- category remains broad enough for related software and hosting expenses.

create or replace function public.seed_digital_services_expense_classification(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent_account_id uuid;
  v_domain_account_id uuid;
begin
  if p_tenant_id is null then
    return;
  end if;

  v_parent_account_id := public.ensure_account(
    p_tenant_id,
    '6207',
    'Servicios Digitales',
    'expense',
    'operatingExpense',
    'Software, plataformas, infraestructura web y otros servicios digitales',
    null
  );

  v_domain_account_id := public.ensure_account(
    p_tenant_id,
    '6207-01',
    'Dominios y Hosting',
    'expense',
    'operatingExpense',
    'Registro y renovación de dominios, DNS, hosting y alojamiento web',
    '6207'
  );

  perform public.ensure_expense_category(
    p_tenant_id,
    'Servicios Digitales',
    'Dominios, hosting, software, plataformas e infraestructura digital',
    v_parent_account_id
  );

  update public.expense_categories
     set description =
           'Dominios, hosting, software, plataformas e infraestructura digital',
         default_account_id = v_parent_account_id,
         default_tax_rate = 0,
         updated_at = now()
   where tenant_id = p_tenant_id
     and lower(name) = lower('Servicios Digitales');

  -- Keep the relationship exact if an earlier partial rollout created the
  -- child without its parent.
  update public.accounts
     set parent_id = v_parent_account_id,
         updated_at = now()
   where tenant_id = p_tenant_id
     and id = v_domain_account_id
     and parent_id is distinct from v_parent_account_id;
end;
$$;

revoke all on function public.seed_digital_services_expense_classification(uuid)
  from public, anon, authenticated;
grant execute on function public.seed_digital_services_expense_classification(uuid)
  to service_role;

do $$
declare
  tenant_row record;
begin
  for tenant_row in select id from public.tenants loop
    perform public.seed_digital_services_expense_classification(tenant_row.id);
  end loop;
end;
$$;

create or replace function public.handle_new_tenant_digital_expense_classification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.seed_digital_services_expense_classification(new.id);
  return new;
end;
$$;

revoke all on function public.handle_new_tenant_digital_expense_classification()
  from public, anon, authenticated;
grant execute on function public.handle_new_tenant_digital_expense_classification()
  to service_role;

drop trigger if exists trg_seed_digital_expense_classification
  on public.tenants;
create trigger trg_seed_digital_expense_classification
  after insert on public.tenants
  for each row
  execute function public.handle_new_tenant_digital_expense_classification();

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
  elsif v_base_code in ('6207', '620700') then
    return 'Servicios Digitales';
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

  if v_name like '%nómina%' or v_name like '%nomina%'
     or v_name like '%sueldo%' or v_name like '%salario%' then
    return 'Nómina';
  end if;
  if v_name like '%arriendo%' then
    return 'Arriendo';
  end if;
  if v_name like '%dominio%' or v_name like '%hosting%'
     or v_name like '%servicio digital%' or v_name like '%software%'
     or v_name like '%infraestructura web%' then
    return 'Servicios Digitales';
  end if;
  if v_name like '%internet%' or v_name like '%telefon%' then
    return 'Telefonía e Internet';
  end if;
  if v_name like '%agua%' or v_name like '%esval%' or v_name like '%aguas%'
     or v_name like '%luz%' or v_name like '%electric%'
     or v_name like '%energía%' or v_name like '%energia%'
     or v_name like '%gas%' or v_name like '%servicio básico%'
     or v_name like '%servicios básicos%' then
    return 'Servicios Básicos';
  end if;
  if v_name like '%transporte%' or v_name like '%flete%'
     or v_name like '%envío%' or v_name like '%envio%'
     or v_name like '%encomienda%' then
    return 'Gastos por Transporte';
  end if;

  return 'Otros Gastos';
end;
$$;
