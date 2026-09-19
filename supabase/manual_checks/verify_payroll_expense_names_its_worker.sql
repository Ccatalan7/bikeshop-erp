-- Falla si un gasto de sueldo vuelve a nacer sin decir a quién se le paga, o
-- si queda alguno de los ya registrados sin su trabajador.
select 1 / (case when
  pg_get_functiondef('public.ensure_payroll_line_expense(uuid)'::regprocedure)
    like '%payment_status, supplier_name, created_by%'
  and pg_get_functiondef('public.ensure_payroll_line_expense(uuid)'::regprocedure)
    like '%v_line.employee_name, auth.uid()%'
  and pg_get_functiondef('public.apply_payroll_payment_workspace_v1(uuid,text,bigint,jsonb)'::regprocedure)
    like '%payment_status, reference, notes, supplier_name, created_by%'
then 1 else 0 end) as afirma_contraparte_al_nacer;

select 1 / (case when (
  select count(*)
    from public.expenses expense
    join public.payroll_voucher_lines line
      on line.expense_id = expense.id
     and line.tenant_id = expense.tenant_id
   where expense.supplier_id is null
     and coalesce(btrim(expense.supplier_name), '') = ''
     and coalesce(btrim(line.employee_name), '') <> ''
) = 0 then 1 else 0 end) as afirma_ningun_sueldo_sin_nombre;
