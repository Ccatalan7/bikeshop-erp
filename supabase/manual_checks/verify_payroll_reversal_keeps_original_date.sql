-- Falla si una reversa vuelve a fecharse el día en que se corrige, o si
-- queda alguna con fecha distinta a la del movimiento que anula.
select 1 / (case when
  pg_get_functiondef('public.reverse_payroll_settlement_v1(uuid,text,uuid,text,text,bigint)'::regprocedure)
    like '%original_payment.payment_date,%'
  and pg_get_functiondef('public.reverse_payroll_settlement_v1(uuid,text,uuid,text,text,bigint)'::regprocedure)
    like '%original_allocation.applied_at,%'
then 1 else 0 end) as afirma_fecha_del_original;

select 1 / (case when (
  select count(*)
    from public.expense_payments reversal
    join public.expense_payments original
      on original.id = reversal.reversal_of_id
     and original.tenant_id = reversal.tenant_id
   where reversal.payment_date <> original.payment_date
) = 0 then 1 else 0 end) as afirma_ninguna_reversa_descolocada;

select 1 / (case when (
  select count(*)
    from public.employee_advance_allocations reversal
    join public.employee_advance_allocations original
      on original.id = reversal.reversal_of_id
     and original.tenant_id = reversal.tenant_id
   where reversal.applied_at <> original.applied_at
) = 0 then 1 else 0 end) as afirma_ningun_anticipo_descolocado;
