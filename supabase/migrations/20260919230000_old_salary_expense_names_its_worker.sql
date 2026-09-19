-- Un sueldo viejo dice a quién se le pagó, si su cuenta lo nombra.
--
-- `20260919190000` completó la contraparte de los sueldos que cuelgan de una
-- semana de Nómina. Quedaron cuatro gastos de sueldo anteriores a Nómina, que
-- el dueño registró a mano en 2025-12 y 2026-02. Tres de ellos cargan la
-- cuenta de salario de un trabajador —`6101-01 Salario - Fernando José Tapia
-- Carrillo`—, y esa cuenta está enlazada en `employees.salary_account_id`:
-- ahí el ERP sí sabe a quién se le pagó, y no hace falta leer el rótulo de la
-- cuenta ni adivinar del texto.
--
-- El cuarto carga la cuenta madre `6101 Sueldos y Salarios`, que es de todos:
-- ése se queda sin contraparte, porque nada dice de quién era.
do $$
declare
  v_gastos integer := 0;
  v_avisos integer := 0;
begin
  alter table public.expenses
    disable trigger trg_guard_payroll_workspace_expense;
  alter table public.expenses
    disable trigger zz_expense_trace_begin_expense;
  alter table public.expenses
    disable trigger zzz_expense_trace_complete_expense;

  with identificados as (
    select line.expense_id,
           min(employee.first_name || ' ' || employee.last_name) as trabajador
      from public.expense_lines line
      join public.employees employee
        on employee.salary_account_id = line.account_id
       and employee.tenant_id = line.tenant_id
     group by line.expense_id
    having count(distinct employee.id) = 1
       and count(distinct line.account_id) = 1
  ), nombrados as (
    update public.expenses expense
       set supplier_name = identificados.trabajador,
           updated_at = now()
      from identificados
     where identificados.expense_id = expense.id
       and expense.supplier_id is null
       and coalesce(btrim(expense.supplier_name), '') = ''
       and (
         select count(*) from public.expense_lines line
          where line.expense_id = expense.id
       ) = 1
    returning expense.id
  )
  select count(*) into v_gastos from nombrados;

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

  raise notice 'sueldos viejos nombrados: %, avisos corregidos: %',
    v_gastos, v_avisos;
end;
$$;
