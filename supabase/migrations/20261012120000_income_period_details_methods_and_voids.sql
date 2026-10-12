-- Detalle de ingresos del panorama financiero: método de pago, cobros
-- anulados, día del taller y autoridad contable (2026-10-12).
--
-- El dueño quiere saber cuánto vendió con tarjeta (crédito + débito) desde el
-- detalle de ingresos. La función sólo devolvía el NOMBRE del método, y
-- agrupar tarjetas por nombre es adivinar: «Redcompra» no dice «tarjeta». Ahora
-- devuelve también el código, el instrumento (débito/crédito/prepago) y el
-- proveedor de liquidación, que es lo que `PaymentMethod.isCardInstrument` ya
-- usa en la caja.
--
-- De paso, tres defectos de la misma función, medidos en producción:
--
-- 1. Sumaba cobros anulados. `sales_payments.deleted_at` es el borrado lógico
--    que deja revertir una factura (20260107_payment_level_iva); el detalle no
--    lo miraba (1 cobro de julio). Las series del gráfico tampoco, así que se
--    corrigen aquí también: la barra y su detalle tienen que sumar lo mismo.
-- 2. El día salía de `sp.date::date` con la sesión en UTC: un cobro a las
--    21:30 de Santiago caía en el día siguiente. Ahora es el día del taller
--    (zona de `tenants.timezone`, como `get_expense_period_details`).
-- 3. No pedía autoridad contable: cualquier miembro del taller podía leer
--    todos los cobros con nombre de cliente, aunque el panel ya exige
--    `can_manage_tenant_accounting` (canonical-ui-surfaces, 2026-09-30). Se
--    aplica la misma compuerta que las series (`can_manage_tenant_payroll` =
--    miembro ERP + autoridad contable) y se responde 42501, que el cliente ya
--    traduce a «Lo ve quien administra la contabilidad del taller».
--
-- Compatibilidad: las columnas nuevas van al final y los clientes leen por
-- nombre, así que una app anterior sigue funcionando. Cambiar el tipo de
-- retorno obliga a DROP + CREATE, dentro de la misma transacción.
--
-- Recuperación: volver a crear la definición anterior (está en
-- supabase/sql/local_public_baseline.sql) y quitar `and sp.deleted_at is null`
-- de las dos funciones internas de series.

begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

drop function if exists public.get_income_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
);

create function public.get_income_period_details(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  id uuid,
  document_number text,
  description text,
  customer_name text,
  amount numeric,
  transaction_date date,
  source_type text,
  payment_method_id uuid,
  payment_method_code text,
  payment_instrument text,
  settlement_provider text,
  occurred_at timestamp with time zone
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_tenant_id uuid := public.erp_member_tenant_id();
  v_timezone text;
begin
  if p_start_date is null
     or p_end_date is null
     or p_start_date > p_end_date
     or p_end_date - p_start_date > interval '3660 days' then
    raise exception 'Invalid accounting date range'
      using errcode = '22023';
  end if;

  if v_tenant_id is null
     or not public.can_manage_tenant_payroll(v_tenant_id) then
    raise exception 'Accounting access denied'
      using errcode = '42501';
  end if;

  -- Una sola lectura de la zona del taller; `tenant_business_date` por fila
  -- repetiría la comprobación de membresía en cada cobro.
  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
    into v_timezone
    from public.tenants tenant
   where tenant.id = v_tenant_id;

  if p_is_cash_flow then
    -- Caja: cada cobro recibido en el período, con su método.
    return query
    select
      sp.id,
      coalesce(si.invoice_number, 'Pago')::text,
      coalesce(pm.name, 'Pago recibido')::text,
      coalesce(c.name, 'Cliente')::text,
      sp.amount::numeric(14,2),
      (sp.date at time zone v_timezone)::date,
      'sales_payment'::text,
      pm.id,
      pm.code::text,
      pm.payment_instrument::text,
      pm.settlement_provider::text,
      sp.date
    from public.sales_payments sp
    left join public.sales_invoices si
      on si.id = sp.invoice_id
     and si.tenant_id = sp.tenant_id
    left join public.customers c
      on c.id = si.customer_id
     and c.tenant_id = sp.tenant_id
    left join public.payment_methods pm
      on pm.id = sp.payment_method_id
     and pm.tenant_id = sp.tenant_id
    where sp.tenant_id = v_tenant_id
      and sp.deleted_at is null
      and sp.date >= p_start_date
      and sp.date < p_end_date
    order by sp.date desc, sp.amount desc, sp.id;
  else
    -- Devengado: ventas emitidas en el período, neto sin IVA.
    return query
    select
      si.id,
      si.invoice_number::text,
      'Venta'::text,
      coalesce(c.name, 'Cliente')::text,
      si.subtotal::numeric(14,2),
      (si.date at time zone v_timezone)::date,
      'sales_invoice'::text,
      null::uuid,
      null::text,
      null::text,
      null::text,
      si.date
    from public.sales_invoices si
    left join public.customers c
      on c.id = si.customer_id
     and c.tenant_id = si.tenant_id
    where si.tenant_id = v_tenant_id
      and si.status in ('sent', 'confirmed', 'paid')
      and si.date >= p_start_date
      and si.date < p_end_date
    order by si.date desc, si.subtotal desc, si.id;
  end if;
end;
$$;

revoke all on function public.get_income_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) from public, anon, service_role;

grant execute on function public.get_income_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) to authenticated;

comment on function public.get_income_period_details(
  timestamp with time zone,
  timestamp with time zone,
  boolean
) is
  'Detalle de ingresos del panorama financiero. Caja: cobros vigentes '
  '(sin deleted_at) con método, código, instrumento y proveedor; devengado: '
  'ventas emitidas. transaction_date es el día del taller. Exige autoridad '
  'contable (42501).';

-- Series del gráfico: los mismos cuerpos vigentes en producción, con el cobro
-- anulado fuera. Nada más cambia.
create or replace function public.get_income_expense_daily_timeseries_internal(
  p_start_date timestamp with time zone,
  p_end_date timestamp with time zone,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date,
  period_end date,
  income numeric,
  expense numeric
)
language sql
security definer
set search_path to 'public'
as $function$
  with day_windows as (
    select (date_trunc('day', p_start_date)
      + make_interval(days => d.day_index))::date as period_start
      from generate_series(0, extract(days from (p_end_date-p_start_date))::integer) d(day_index)
  )
  select dw.period_start, dw.period_start,
         coalesce(case when p_is_cash_flow then (
           select sum(amount) from public.sales_payments sp
            where sp.date >= dw.period_start and sp.date < dw.period_start + interval '1 day'
              and sp.tenant_id=public.user_tenant_id()
              and sp.deleted_at is null
         ) else (
           select sum(coalesce(jl.credit_amount,0)-coalesce(jl.debit_amount,0))
             from public.journal_lines jl join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='income'
              and je.entry_date >= dw.period_start and je.entry_date < dw.period_start + interval '1 day'
              and je.tenant_id=public.user_tenant_id() and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2),
         coalesce(case when p_is_cash_flow then (
           coalesce((select sum(amount) from public.purchase_payments pp
             where pp.date >= dw.period_start and pp.date < dw.period_start + interval '1 day'
               and pp.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(amount) from public.expense_payments ep
             where ep.payment_date >= dw.period_start and ep.payment_date < dw.period_start + interval '1 day'
               and ep.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(e.total_amount) from public.expenses e
             where e.payment_status='paid'
               and e.paid_at >= dw.period_start and e.paid_at < dw.period_start + interval '1 day'
               and e.tenant_id=public.user_tenant_id()
               and not exists (select 1 from public.expense_payments ep where ep.expense_id=e.id)
               and not exists (
                 select 1
                   from public.employee_advance_allocations aa
                   join public.payroll_voucher_lines l on l.id=aa.voucher_line_id
                  where l.expense_id=e.id
               )),0)
           + coalesce((select sum(amount) from public.employee_advances ea
             where ea.paid_at >= dw.period_start and ea.paid_at < dw.period_start + interval '1 day'
               and ea.tenant_id=public.user_tenant_id() and ea.status <> 'voided'),0)
         ) else (
           select sum(coalesce(jl.debit_amount,0)-coalesce(jl.credit_amount,0))
             from public.journal_lines jl join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='expense'
              and je.entry_date >= dw.period_start and je.entry_date < dw.period_start + interval '1 day'
              and je.tenant_id=public.user_tenant_id() and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2)
    from day_windows dw order by dw.period_start;
$function$;

create or replace function public.get_income_expense_timeseries_internal(
  p_months integer default 12,
  p_is_cash_flow boolean default false
)
returns table (
  period_start date,
  period_end date,
  income numeric,
  expense numeric
)
language sql
security definer
set search_path to 'public'
as $function$
  with month_windows as (
    select date_trunc('month', current_timestamp)
      - make_interval(months => m.month_index) as period_start
      from generate_series(0, greatest(p_months, 1) - 1) as m(month_index)
  )
  select mw.period_start::date,
         (mw.period_start + interval '1 month' - interval '1 day')::date,
         coalesce(case when p_is_cash_flow then (
           select sum(amount) from public.sales_payments sp
            where sp.date >= mw.period_start and sp.date < mw.period_start + interval '1 month'
              and sp.tenant_id = public.user_tenant_id()
              and sp.deleted_at is null
         ) else (
           select sum(coalesce(jl.credit_amount,0)-coalesce(jl.debit_amount,0))
             from public.journal_lines jl
             join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='income'
              and je.entry_date >= mw.period_start and je.entry_date < mw.period_start + interval '1 month'
              and je.tenant_id=public.user_tenant_id()
              and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end, 0)::numeric(14,2),
         coalesce(case when p_is_cash_flow then (
           coalesce((select sum(amount) from public.purchase_payments pp
             where pp.date >= mw.period_start and pp.date < mw.period_start + interval '1 month'
               and pp.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(amount) from public.expense_payments ep
             where ep.payment_date >= mw.period_start and ep.payment_date < mw.period_start + interval '1 month'
               and ep.tenant_id=public.user_tenant_id()),0)
           + coalesce((select sum(e.total_amount) from public.expenses e
             where e.payment_status='paid'
               and e.paid_at >= mw.period_start and e.paid_at < mw.period_start + interval '1 month'
               and e.tenant_id=public.user_tenant_id()
               and not exists (select 1 from public.expense_payments ep where ep.expense_id=e.id)
               and not exists (
                 select 1
                   from public.employee_advance_allocations aa
                   join public.payroll_voucher_lines l on l.id=aa.voucher_line_id
                  where l.expense_id=e.id
               )),0)
           + coalesce((select sum(amount) from public.employee_advances ea
             where ea.paid_at >= mw.period_start and ea.paid_at < mw.period_start + interval '1 month'
               and ea.tenant_id=public.user_tenant_id() and ea.status <> 'voided'),0)
         ) else (
           select sum(coalesce(jl.debit_amount,0)-coalesce(jl.credit_amount,0))
             from public.journal_lines jl
             join public.journal_entries je on je.id=jl.entry_id
             join public.accounts a on a.id=jl.account_id
            where je.status='posted' and a.type='expense'
              and je.entry_date >= mw.period_start and je.entry_date < mw.period_start + interval '1 month'
              and je.tenant_id=public.user_tenant_id()
              and jl.tenant_id=public.user_tenant_id()
              and a.tenant_id=public.user_tenant_id()
         ) end,0)::numeric(14,2)
    from month_windows mw order by mw.period_start;
$function$;

commit;
