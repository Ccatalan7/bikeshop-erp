-- «¿Qué cliente me compró más este mes?» no tenía herramienta: la RPC de
-- ventas devuelve un solo agregado del período y la factura más alta, sin
-- desglose por cliente. El asistente lo reconocía en vez de inventarlo, que es
-- lo correcto, pero la respuesta faltaba.
--
-- Reusa el mismo cálculo de período y la misma distinción emitido/cobrado que
-- `assistant_analyze_sales_period_v1`, para que dos preguntas del mismo día no
-- puedan contradecirse.

create or replace function public.assistant_rank_sales_customers_v1(
  p_basis text,
  p_range_mode text,
  p_relative_period text,
  p_start_date text,
  p_end_date text,
  p_limit integer
) returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
set statement_timeout to '4500ms'
as $function$
declare
  v_authority record;
  v_timezone text;
  v_business_date date;
  v_start_date date;
  v_end_date date;
  v_items jsonb;
  v_total numeric;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.sales') authority;

  if p_basis not in ('issued', 'collected')
     or p_range_mode not in ('relative', 'absolute')
     or p_limit is null or p_limit < 1 or p_limit > 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
  into strict v_timezone from public.tenants tenant
  where tenant.id = v_authority.tenant_id and tenant.is_active is true;
  if not exists (
    select 1 from pg_timezone_names zone where zone.name = v_timezone
  ) then
    raise exception 'Tenant timezone is invalid' using errcode = '42501';
  end if;
  v_business_date := (statement_timestamp() at time zone v_timezone)::date;

  if p_range_mode = 'relative' then
    if p_relative_period not in ('today', 'yesterday', 'this_week', 'last_week',
        'last_7_days', 'this_month', 'last_month', 'this_year', 'last_year')
       or p_start_date is not null or p_end_date is not null then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    case p_relative_period
      when 'today' then
        v_start_date := v_business_date; v_end_date := v_business_date;
      when 'yesterday' then
        v_start_date := v_business_date - 1; v_end_date := v_business_date - 1;
      when 'this_week' then
        v_start_date := date_trunc('week', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      when 'last_week' then
        v_start_date := date_trunc('week', v_business_date::timestamp)::date - 7;
        v_end_date := date_trunc('week', v_business_date::timestamp)::date - 1;
      when 'last_7_days' then
        v_start_date := v_business_date - 6; v_end_date := v_business_date;
      when 'this_month' then
        v_start_date := date_trunc('month', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      when 'last_month' then
        v_start_date := (
          date_trunc('month', v_business_date::timestamp) - interval '1 month'
        )::date;
        v_end_date := date_trunc('month', v_business_date::timestamp)::date - 1;
      when 'this_year' then
        v_start_date := date_trunc('year', v_business_date::timestamp)::date;
        v_end_date := v_business_date;
      else
        v_start_date := (
          date_trunc('year', v_business_date::timestamp) - interval '1 year'
        )::date;
        v_end_date := date_trunc('year', v_business_date::timestamp)::date - 1;
    end case;
  else
    if p_relative_period is not null or p_start_date is null or p_end_date is null
       or p_start_date !~ '^\d{4}-\d{2}-\d{2}$'
       or p_end_date !~ '^\d{4}-\d{2}-\d{2}$' then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    begin
      v_start_date := p_start_date::date; v_end_date := p_end_date::date;
    exception when others then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end;
    if v_start_date > v_end_date or v_end_date - v_start_date > 366 then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
  end if;

  with invoice_state as materialized (
    select invoice.id, invoice.customer_id, invoice.customer_name,
      invoice.total, invoice.date
    from public.sales_invoices invoice
    where invoice.tenant_id = v_authority.tenant_id
      and lower(coalesce(invoice.status, '')) not in (
        'draft', 'borrador', 'cancelled', 'cancelado', 'cancelada',
        'anulado', 'anulada'
      )
  ), period_rows as materialized (
    select invoice.id, invoice.customer_id, invoice.customer_name,
      case when p_basis = 'issued' then invoice.total
        else coalesce(sum(payment.amount), 0) end period_amount
    from invoice_state invoice
    left join public.sales_payments payment
      on p_basis = 'collected'
     and payment.invoice_id = invoice.id
     and payment.tenant_id = v_authority.tenant_id
     and payment.deleted_at is null and payment.amount > 0
     and (payment.date at time zone v_timezone)::date
       between v_start_date and v_end_date
    where (
      (p_basis = 'issued' and (invoice.date at time zone v_timezone)::date
        between v_start_date and v_end_date)
      or p_basis = 'collected'
    )
    group by invoice.id, invoice.customer_id, invoice.customer_name,
      invoice.total
    having p_basis = 'issued' or count(payment.id) > 0
  ), by_customer as materialized (
    -- El mostrador no tiene ficha de cliente y aun así es «un cliente» para
    -- esta pregunta: se agrupa por identidad cuando existe, y por nombre
    -- cuando no.
    select coalesce(customer_id::text, lower(btrim(coalesce(customer_name, ''))))
        grouping_key,
      min(customer_id::text) customer_id,
      coalesce(
        nullif(btrim(min(customer_name)), ''), 'Sin cliente registrado'
      ) customer_name,
      sum(period_amount) amount,
      count(*)::integer invoice_count
    from period_rows
    group by 1
    having sum(period_amount) > 0
  ), ranked as materialized (
    select by_customer.*, row_number() over (
      order by amount desc, invoice_count desc, customer_name
    ) ordinal
    from by_customer
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'rank', ordinal,
      'customerId', customer_id,
      'customerName', public.assistant_truncate_utf8_internal_v1(
        customer_name, 160
      ),
      'amount', amount,
      'invoiceCount', invoice_count,
      'basis', p_basis,
      'startDate', v_start_date::text,
      'endDate', v_end_date::text
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    coalesce(sum(amount), 0)
  into v_items, v_total
  from ranked;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items,
    (select count(*) from ranked) > p_limit
  );
end;
$function$;

revoke all on function public.assistant_rank_sales_customers_v1(
  text, text, text, text, text, integer
) from public;
grant execute on function public.assistant_rank_sales_customers_v1(
  text, text, text, text, text, integer
) to authenticated;
