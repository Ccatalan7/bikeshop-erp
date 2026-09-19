-- Falla si un pago adicional con beneficiario queda sin decir a quién se le
-- pagó.
select 1 / (case when (
  select count(*)
    from public.expenses expense
    join public.payroll_payment_workspace_legs leg
      on leg.result_expense_id = expense.id
     and leg.tenant_id = expense.tenant_id
     and leg.beneficiary_employee_id is not null
   where expense.supplier_id is null
     and coalesce(btrim(expense.supplier_name), '') = ''
) = 0 then 1 else 0 end) as afirma_ningun_adicional_sin_nombre;
