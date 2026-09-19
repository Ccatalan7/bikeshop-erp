-- Falla si un gasto quedó con el nombre de un trabajador de otra empresa.
select 1 / (case when (
  select count(*)
    from public.expenses expense
    join public.employees employee
      on employee.first_name || ' ' || employee.last_name = expense.supplier_name
   where expense.supplier_id is null
     and employee.tenant_id <> expense.tenant_id
     and not exists (
       select 1 from public.employees same
        where same.tenant_id = expense.tenant_id
          and same.first_name || ' ' || same.last_name = expense.supplier_name
     )
) = 0 then 1 else 0 end) as afirma_nombre_de_su_empresa;
