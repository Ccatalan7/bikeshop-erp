-- Un pago adicional también dice a quién se le pagó.
--
-- `20260919190000` completó los sueldos por su línea de la semana, pero un
-- concepto «adicional» no cuelga de una línea: su beneficiario vive en
-- `payroll_payment_workspace_legs.beneficiary_employee_id`. Los dos pagos
-- adicionales del dueño —las diferencias de horas que asumió en las semanas
-- 34 y 36— quedaron igual como «Proveedor no informado».
--
-- La función que los crea ya nombra al beneficiario desde ese mismo dato
-- (misma migración anterior); esto sólo completa lo ya escrito.
do $$
declare
  v_extras integer := 0;
  v_avisos integer := 0;
  v_pendientes integer := 0;
begin
  alter table public.expenses
    disable trigger trg_guard_payroll_workspace_expense;
  alter table public.expenses
    disable trigger zz_expense_trace_begin_expense;
  alter table public.expenses
    disable trigger zzz_expense_trace_complete_expense;

  with nombrados as (
    update public.expenses expense
       set supplier_name = nullif(btrim(
             coalesce(employee.first_name, '') || ' '
               || coalesce(employee.last_name, '')
           ), ''),
           updated_at = now()
      from public.payroll_payment_workspace_legs leg
      join public.employees employee
        on employee.id = leg.beneficiary_employee_id
       and employee.tenant_id = leg.tenant_id
     where leg.result_expense_id = expense.id
       and leg.tenant_id = expense.tenant_id
       and expense.supplier_id is null
       and coalesce(btrim(expense.supplier_name), '') = ''
    returning expense.id
  )
  select count(*) into v_extras from nombrados;

  alter table public.expenses
    enable trigger trg_guard_payroll_workspace_expense;
  alter table public.expenses
    enable trigger zz_expense_trace_begin_expense;
  alter table public.expenses
    enable trigger zzz_expense_trace_complete_expense;

  with corregidos as (
    update public.erp_notifications notification
       set body = replace(
             notification.body, 'Proveedor no informado', expense.supplier_name
           )
      from public.expenses expense
     where notification.entity_type = 'expense'
       and notification.entity_id = expense.id
       and notification.tenant_id = expense.tenant_id
       and notification.body like '%Proveedor no informado%'
       and coalesce(btrim(expense.supplier_name), '') <> ''
    returning notification.id
  )
  select count(*) into v_avisos from corregidos;

  select count(*) into v_pendientes
    from public.expenses expense
    join public.payroll_payment_workspace_legs leg
      on leg.result_expense_id = expense.id
     and leg.tenant_id = expense.tenant_id
     and leg.beneficiary_employee_id is not null
   where expense.supplier_id is null
     and coalesce(btrim(expense.supplier_name), '') = '';
  if v_pendientes > 0 then
    raise exception 'payroll_extra_expense_counterparty_incomplete: %',
      v_pendientes;
  end if;

  raise notice 'adicionales nombrados: %, avisos corregidos: %',
    v_extras, v_avisos;
end;
$$;
