-- Falla si queda un gasto de una sola línea contra la cuenta de salario de un
-- trabajador sin decir que fue para él.
select 1 / (case when (
  select count(*)
    from public.expenses expense
    join public.expense_lines line on line.expense_id = expense.id
    join public.employees employee
      on employee.salary_account_id = line.account_id
     and employee.tenant_id = line.tenant_id
   where expense.supplier_id is null
     and coalesce(btrim(expense.supplier_name), '') = ''
     and (
       select count(*) from public.expense_lines other
        where other.expense_id = expense.id
     ) = 1
) = 0 then 1 else 0 end) as afirma_sueldo_viejo_con_nombre;
