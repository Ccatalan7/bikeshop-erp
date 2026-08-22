-- El ranking por cliente pasa a vivir DENTRO de `analyze_sales_period`.
--
-- Existió como herramienta aparte, `rank_sales_customers`: desplegada,
-- alcanzable, registrada en el contrato de recibos y anunciada al modelo —que
-- la nombraba sola cuando se le preguntaba qué herramientas de ventas tenía—.
-- Aun así, ante «quién fue mi mejor cliente este mes» llamaba a
-- `report_capability_gap` y jamás la ejecutó: cero llamadas en
-- `pg_stat_statements` tras cuatro intentos de corregirlo por descripción,
-- instrucción del sistema y contrato.
--
-- La lección: una capacidad nueva que depende de que el modelo la DESCUBRA es
-- frágil. Colgada de la herramienta que ya usa para todas las preguntas de
-- ventas del período, no hay decisión nueva que tomar y los montos no pueden
-- contradecirse porque salen del mismo cálculo.

CREATE OR REPLACE FUNCTION public.assistant_analyze_sales_period_v1(p_basis text, p_range_mode text, p_relative_period text, p_start_date text, p_end_date text, p_invoice_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_timezone text;
  v_business_date date;
  v_start_date date;
  v_end_date date;
  v_item jsonb;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.sales') authority;
  if p_basis not in ('issued','collected')
     or p_range_mode not in ('relative','absolute')
     or p_invoice_status not in ('any','open','paid','cancelled') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
  into strict v_timezone from public.tenants tenant
  where tenant.id = v_authority.tenant_id and tenant.is_active is true;
  if not exists (select 1 from pg_timezone_names zone where zone.name = v_timezone) then
    raise exception 'Tenant timezone is invalid' using errcode = '42501';
  end if;
  v_business_date := (statement_timestamp() at time zone v_timezone)::date;
  if p_range_mode = 'relative' then
    if p_relative_period not in ('today','yesterday','this_week','last_week',
        'last_7_days','this_month','last_month','this_year','last_year')
       or p_start_date is not null or p_end_date is not null then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    case p_relative_period
      when 'today' then v_start_date := v_business_date; v_end_date := v_business_date;
      when 'yesterday' then v_start_date := v_business_date - 1; v_end_date := v_business_date - 1;
      when 'this_week' then
        v_start_date := date_trunc('week', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      when 'last_week' then
        v_start_date := date_trunc('week', v_business_date::timestamp)::date - 7;
        v_end_date := date_trunc('week', v_business_date::timestamp)::date - 1;
      when 'last_7_days' then v_start_date := v_business_date - 6; v_end_date := v_business_date;
      when 'this_month' then
        v_start_date := date_trunc('month', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      when 'last_month' then
        v_start_date := (date_trunc('month', v_business_date::timestamp) - interval '1 month')::date;
        v_end_date := date_trunc('month', v_business_date::timestamp)::date - 1;
      when 'this_year' then
        v_start_date := date_trunc('year', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      else
        v_start_date := (date_trunc('year', v_business_date::timestamp) - interval '1 year')::date;
        v_end_date := date_trunc('year', v_business_date::timestamp)::date - 1;
    end case;
  else
    if p_relative_period is not null or p_start_date is null or p_end_date is null
       or p_start_date !~ '^\d{4}-\d{2}-\d{2}$'
       or p_end_date !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    begin v_start_date := p_start_date::date; v_end_date := p_end_date::date;
    exception when others then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end;
    if v_start_date > v_end_date or v_end_date - v_start_date > 366 then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
  end if;

  with invoice_state as materialized (
    select invoice.id, invoice.invoice_number, invoice.customer_name,
      invoice.total, invoice.date, invoice.status,
      case
        when lower(coalesce(invoice.status, '')) in (
          'cancelled','cancelado','cancelada','anulado','anulada'
        ) then 'cancelled'
        when lower(coalesce(invoice.status, '')) in ('paid','pagado','pagada')
          or coalesce(invoice.balance, 0) <= 0 then 'paid'
        else 'open' end normalized_status
    from public.sales_invoices invoice
    where invoice.tenant_id = v_authority.tenant_id
      and lower(coalesce(invoice.status, '')) not in ('draft','borrador')
  ), period_rows as materialized (
    select invoice.id, invoice.invoice_number, invoice.customer_name,
      invoice.total invoice_total,
      case when p_basis = 'issued' then invoice.total
        else coalesce(sum(payment.amount), 0) end period_amount,
      case when p_basis = 'issued' then 1::bigint
        else count(payment.id) end event_count
    from invoice_state invoice
    left join public.sales_payments payment
      on p_basis = 'collected'
     and payment.invoice_id = invoice.id
     and payment.tenant_id = v_authority.tenant_id
     and payment.deleted_at is null and payment.amount > 0
     and (payment.date at time zone v_timezone)::date
       between v_start_date and v_end_date
    where (p_invoice_status = 'any' or invoice.normalized_status = p_invoice_status)
      and (
        (p_basis = 'issued' and (invoice.date at time zone v_timezone)::date
          between v_start_date and v_end_date)
        or p_basis = 'collected'
      )
    group by invoice.id, invoice.invoice_number, invoice.customer_name,
      invoice.total, invoice.date
    having p_basis = 'issued' or count(payment.id) > 0
  ), ranked as materialized (
    select period_rows.id, period_rows.invoice_number,
      period_rows.customer_name, period_rows.invoice_total,
      period_rows.period_amount, period_rows.event_count,
      row_number() over (order by period_amount desc, invoice_total desc,
        invoice_number, id) ordinal
    from period_rows
  ), by_customer as materialized (
    -- El desglose por cliente vive DENTRO de esta herramienta a propósito.
    -- Existió como herramienta aparte —`rank_sales_customers`— y el modelo,
    -- teniéndola anunciada y nombrándola cuando se le preguntaba qué tenía,
    -- igual contestaba «no tengo herramienta» y nunca la ejecutó ni una vez
    -- (2026-08-21). Aquí no hay ninguna decisión nueva que tomar: es la misma
    -- herramienta que ya usa para cualquier pregunta de ventas del período.
    select coalesce(
        nullif(btrim(period_rows.customer_name), ''), 'Sin cliente registrado'
      ) customer_name,
      sum(period_rows.period_amount) amount,
      count(*)::integer invoice_count
    from period_rows
    group by 1
    having sum(period_rows.period_amount) > 0
  ), customer_rank as materialized (
    select customer_name, amount, invoice_count,
      row_number() over (order by amount desc, invoice_count desc, customer_name) ordinal
    from by_customer
  ), customer_summary as (
    select count(*)::integer customer_count,
      max(customer_name) filter (where ordinal = 1) top_customer_name,
      max(amount) filter (where ordinal = 1) top_customer_amount,
      max(invoice_count) filter (where ordinal = 1) top_customer_invoice_count,
      string_agg(
        customer_name || ' ' || to_char(amount, 'FM999G999G999') ||
          ' (' || invoice_count || ')',
        ' · ' order by ordinal
      ) filter (where ordinal <= 5) top_customers
    from customer_rank
  ), totals as (
    select count(*)::integer invoice_count,
      coalesce(sum(event_count), 0)::integer event_count,
      coalesce(sum(period_amount), 0) total_amount,
      coalesce(avg(period_amount), 0) average_per_invoice
    from ranked
  )
  select jsonb_build_object(
    'basis', p_basis,
    'startDate', v_start_date,
    'endDate', v_end_date,
    'invoiceStatus', p_invoice_status,
    'invoiceCount', totals.invoice_count,
    'eventCount', totals.event_count,
    'totalAmount', totals.total_amount,
    'averagePerInvoice', totals.average_per_invoice,
    'highestInvoiceId', highest.id,
    'highestInvoiceNumber', highest.invoice_number,
    'highestInvoiceCustomerName', highest.customer_name,
    'highestInvoiceTotal', highest.invoice_total,
    'highestPeriodAmount', highest.period_amount,
    'customerCount', coalesce(customers.customer_count, 0),
    'topCustomerName', customers.top_customer_name,
    'topCustomerAmount', customers.top_customer_amount,
    'topCustomerInvoiceCount', coalesce(customers.top_customer_invoice_count, 0),
    'topCustomers', nullif(public.assistant_truncate_utf8_internal_v1(
      coalesce(customers.top_customers, ''), 480
    ), '')
  ) into v_item
  from totals
  left join ranked highest on highest.ordinal = 1
  left join customer_summary customers on true;
  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, jsonb_build_array(v_item), false
  );
end;
$function$
;
