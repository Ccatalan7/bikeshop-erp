-- Production-only read-back for 20260910133000: the week the operator reported.
-- 6. The reported week, for the eye: NOM-00038 must read 66,50 h / $238.500
--    with Vicente at 34,30 h × $3.500 = $120.050.
select voucher.voucher_number, voucher.status, voucher.total_hours,
       voucher.total_amount, voucher.reconciliation_version
from public.payroll_vouchers voucher
where voucher.voucher_number = 'NOM-00038';
select 1/(case when count(*) = 1 then 1 else 0 end) as nom_00038_vicente_flat
from public.payroll_voucher_lines line
join public.payroll_vouchers voucher on voucher.id = line.voucher_id
where voucher.voucher_number = 'NOM-00038'
  and line.employee_name ilike 'vicente d%'
  and line.worked_hours = 34.30
  and line.overtime_hours = 0
  and line.overtime_amount = 0
  and line.total_amount = 120050.00;
