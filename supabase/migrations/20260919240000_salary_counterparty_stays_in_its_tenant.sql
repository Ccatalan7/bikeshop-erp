-- El nombre de un sueldo viejo no cruza de empresa.
--
-- `20260919230000` unía la línea del gasto con el trabajador por el tenant de
-- la línea, pero pegaba el nombre en el gasto uniendo sólo por `expense_id`:
-- la FK de `expense_lines` referencia `expenses(id)` y no el par con tenant,
-- así que una línea mal grabada de otra empresa podía ponerle a un gasto el
-- nombre de un trabajador ajeno. Hoy no hay ninguna línea cruzada en
-- producción —se comprobó antes de escribir esto—, pero la consulta que queda
-- en el repositorio tiene que ser la correcta. Lo encontró Codex revisando.
--
-- Vuelve a correr el relleno exigiendo el mismo tenant en los tres lados;
-- sobre los datos actuales no cambia nada.
do $$
declare
  v_gastos integer := 0;
begin
  alter table public.expenses
    disable trigger trg_guard_payroll_workspace_expense;
  alter table public.expenses
    disable trigger zz_expense_trace_begin_expense;
  alter table public.expenses
    disable trigger zzz_expense_trace_complete_expense;

  with identificados as (
    select line.expense_id,
           line.tenant_id,
           min(employee.first_name || ' ' || employee.last_name) as trabajador
      from public.expense_lines line
      join public.employees employee
        on employee.salary_account_id = line.account_id
       and employee.tenant_id = line.tenant_id
     group by line.expense_id, line.tenant_id
    having count(distinct employee.id) = 1
       and count(distinct line.account_id) = 1
  ), nombrados as (
    update public.expenses expense
       set supplier_name = identificados.trabajador,
           updated_at = now()
      from identificados
     where identificados.expense_id = expense.id
       and identificados.tenant_id = expense.tenant_id
       and expense.supplier_id is null
       and coalesce(btrim(expense.supplier_name), '') = ''
       and (
         select count(*) from public.expense_lines line
          where line.expense_id = expense.id
            and line.tenant_id = expense.tenant_id
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

  raise notice 'sueldos viejos nombrados en esta pasada: %', v_gastos;
end;
$$;
