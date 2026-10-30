-- Series del gráfico del panorama por día y mes del taller (2026-10-30).
--
-- Las dos series (`get_income_expense_daily_timeseries_internal` y
-- `get_income_expense_timeseries_internal`) comparaban los instantes de caja
-- (`sales_payments.date`, `purchase_payments.date`,
-- `expense_payments.payment_date`, `expenses.paid_at` y
-- `employee_advances.paid_at`, todos `timestamptz`) contra una fecha, que
-- Postgres convierte en la medianoche UTC de la sesión. Un cobro de las 21:30
-- de Santiago caía en la barra del día siguiente, y uno de la noche del último
-- día del mes en el mes siguiente, aunque el detalle del período
-- (20261012120000) ya lo mostraba en su día. La serie mensual además tomaba
-- «este mes» con `date_trunc('month', current_timestamp)` en UTC: desde las
-- 21:00 del último día, el mes en curso ya era el siguiente.
--
-- Ahora los límites de caja son la medianoche del taller (`tenants.timezone`,
-- como el detalle) y el mes en curso es el del reloj del taller. Devengado no
-- cambia de sentido: compara `journal_entries.entry_date`, que es `date`.
--
-- Compatibilidad: misma firma, mismas columnas y los mismos permisos
-- (`create or replace` los conserva). La ventana diaria se sigue armando con
-- `date_trunc('day', p_start_date)` en la sesión UTC porque la app manda el día
-- del calendario como medianoche sin zona (`getIncomeExpenseDailyTimeseries`);
-- un instante de la medianoche del taller (03:00 o 04:00 Z) da el mismo día.
--
-- Recuperación: volver a crear las dos funciones con el cuerpo de
-- 20261012120000.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

CREATE OR REPLACE FUNCTION public.get_income_expense_daily_timeseries_internal(p_start_date timestamp with time zone, p_end_date timestamp with time zone, p_is_cash_flow boolean DEFAULT false)
 RETURNS TABLE(period_start date, period_end date, income numeric, expense numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with shop as (
    select coalesce(
      (select nullif(btrim(t.timezone), '')
         from public.tenants t
        where t.id = public.user_tenant_id()),
      'America/Santiago'
    ) as zone
  ),
  day_windows as (
    select (date_trunc('day', p_start_date)
      + make_interval(days => d.day_index))::date as period_start
      from generate_series(0, extract(days from (p_end_date-p_start_date))::integer) d(day_index)
  ),
  windows as (
    select dw.period_start,
           dw.period_start::timestamp at time zone shop.zone as starts_at,
           (dw.period_start + 1)::timestamp at time zone shop.zone as ends_at
      from day_windows dw cross join shop
  )
  select w.period_start, w.period_start,
         coalesce(case when p_is_cash_flow then (
           select sum(amount) from public.sales_payments sp
            where sp.date >= w.starts_at and sp.date < w.ends_at
              and sp.tenant_id=public.user_tenant_id()
              and sp.deleted_at is null
         ) else (
           select sum(coalesce(jl.credit_amount,0)-coalesce(jl.debit_amount,0))
             from public.journal_lines jl join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='income'
              and je.entry_date >= w.period_start and je.entry_date < w.period_start + 1
              and je.tenant_id=public.user_tenant_id() and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2),
         coalesce(case when p_is_cash_flow then (
           coalesce((select sum(amount) from public.purchase_payments pp
             where pp.date >= w.starts_at and pp.date < w.ends_at
               and pp.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(amount) from public.expense_payments ep
             where ep.payment_date >= w.starts_at and ep.payment_date < w.ends_at
               and ep.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(e.total_amount) from public.expenses e
             where e.payment_status='paid'
               and e.paid_at >= w.starts_at and e.paid_at < w.ends_at
               and e.tenant_id=public.user_tenant_id()
               and not exists (select 1 from public.expense_payments ep where ep.expense_id=e.id)
               and not exists (
                 select 1
                   from public.employee_advance_allocations aa
                   join public.payroll_voucher_lines l on l.id=aa.voucher_line_id
                  where l.expense_id=e.id
               )),0)
           + coalesce((select sum(amount) from public.employee_advances ea
             where ea.paid_at >= w.starts_at and ea.paid_at < w.ends_at
               and ea.tenant_id=public.user_tenant_id() and ea.status <> 'voided'),0)
         ) else (
           select sum(coalesce(jl.debit_amount,0)-coalesce(jl.credit_amount,0))
             from public.journal_lines jl join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='expense'
              and je.entry_date >= w.period_start and je.entry_date < w.period_start + 1
              and je.tenant_id=public.user_tenant_id() and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2)
    from windows w order by w.period_start;
$function$;

CREATE OR REPLACE FUNCTION public.get_income_expense_timeseries_internal(p_months integer DEFAULT 12, p_is_cash_flow boolean DEFAULT false)
 RETURNS TABLE(period_start date, period_end date, income numeric, expense numeric)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with shop as (
    select coalesce(
      (select nullif(btrim(t.timezone), '')
         from public.tenants t
        where t.id = public.user_tenant_id()),
      'America/Santiago'
    ) as zone
  ),
  month_windows as (
    select date_trunc('month', current_timestamp at time zone shop.zone)
      - make_interval(months => m.month_index) as month_start,
           shop.zone
      from shop
      cross join generate_series(0, greatest(p_months, 1) - 1) as m(month_index)
  ),
  windows as (
    select mw.month_start::date as period_start,
           (mw.month_start + interval '1 month')::date as next_start,
           mw.month_start at time zone mw.zone as starts_at,
           (mw.month_start + interval '1 month') at time zone mw.zone as ends_at
      from month_windows mw
  )
  select w.period_start,
         w.next_start - 1,
         coalesce(case when p_is_cash_flow then (
           select sum(amount) from public.sales_payments sp
            where sp.date >= w.starts_at and sp.date < w.ends_at
              and sp.tenant_id = public.user_tenant_id()
              and sp.deleted_at is null
         ) else (
           select sum(coalesce(jl.credit_amount,0)-coalesce(jl.debit_amount,0))
             from public.journal_lines jl
             join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='income'
              and je.entry_date >= w.period_start and je.entry_date < w.next_start
              and je.tenant_id=public.user_tenant_id()
              and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end, 0)::numeric(14,2),
         coalesce(case when p_is_cash_flow then (
           coalesce((select sum(amount) from public.purchase_payments pp
             where pp.date >= w.starts_at and pp.date < w.ends_at
               and pp.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(amount) from public.expense_payments ep
             where ep.payment_date >= w.starts_at and ep.payment_date < w.ends_at
               and ep.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(e.total_amount) from public.expenses e
             where e.payment_status='paid'
               and e.paid_at >= w.starts_at and e.paid_at < w.ends_at
               and e.tenant_id=public.user_tenant_id()
               and not exists (select 1 from public.expense_payments ep where ep.expense_id=e.id)
               and not exists (
                 select 1
                   from public.employee_advance_allocations aa
                   join public.payroll_voucher_lines l on l.id=aa.voucher_line_id
                  where l.expense_id=e.id
               )),0)
           + coalesce((select sum(amount) from public.employee_advances ea
             where ea.paid_at >= w.starts_at and ea.paid_at < w.ends_at
               and ea.tenant_id=public.user_tenant_id() and ea.status <> 'voided'),0)
         ) else (
           select sum(coalesce(jl.debit_amount,0)-coalesce(jl.credit_amount,0))
             from public.journal_lines jl
             join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='expense'
              and je.entry_date >= w.period_start and je.entry_date < w.next_start
              and je.tenant_id=public.user_tenant_id()
              and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2)
    from windows w order by w.period_start;
$function$;

commit;
