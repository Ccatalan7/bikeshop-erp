-- «Qué le compré a mis proveedores este mes» devolvía la respuesta automática
-- de «no tengo herramienta» y a continuación mostraba facturas de julio.
-- Compras tenía búsqueda por texto pero ningún análisis por período: el
-- equivalente de `analyze_sales_period` no existía de ese lado.
--
-- En vez de una herramienta nueva —que el modelo tendría que descubrir, y hoy
-- se demostró que no lo hace— el período y los totales verificados viven
-- dentro de `search_purchase_invoices`, que ya usa.

CREATE OR REPLACE FUNCTION public.assistant_search_purchase_invoices_v1(p_query text, p_limit integer DEFAULT 10, p_relative_period text DEFAULT 'any')
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare v_authority record; v_query text; v_items jsonb; v_total integer;
  v_timezone text; v_today date; v_start date; v_end date;
  v_matched_count integer; v_matched_total numeric; v_matched_balance numeric;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.purchases'
  ) authority;
  -- Un query vacío ya no es un error: significa «lístamelos». Sin esto,
  -- «qué proveedores tengo» era inexpresable y el asistente contestaba que
  -- no tenía herramienta, teniéndola (medido el 2026-08-21).
  if octet_length(coalesce(p_query, '')) > 240 or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  if p_relative_period is null or p_relative_period not in (
    'any', 'today', 'yesterday', 'this_week', 'last_week', 'last_7_days',
    'this_month', 'last_month', 'this_year', 'last_year'
  ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);

  -- Compras tenía búsqueda por texto pero ningún análisis por período, así que
  -- «qué le compré a mis proveedores este mes» no era expresable y el
  -- asistente contestaba que no tenía herramienta —y después mostraba facturas
  -- de otros meses—. El período y los totales verificados viven aquí, en la
  -- herramienta que el modelo ya usa para compras.
  select coalesce(nullif(btrim(tenant.timezone), ''), 'America/Santiago')
  into strict v_timezone from public.tenants tenant
  where tenant.id = v_authority.tenant_id and tenant.is_active is true;
  v_today := (statement_timestamp() at time zone v_timezone)::date;
  case p_relative_period
    when 'any' then v_start := null; v_end := null;
    when 'today' then v_start := v_today; v_end := v_today;
    when 'yesterday' then v_start := v_today - 1; v_end := v_today - 1;
    when 'this_week' then
      v_start := date_trunc('week', v_today::timestamp)::date; v_end := v_today;
    when 'last_week' then
      v_start := date_trunc('week', v_today::timestamp)::date - 7;
      v_end := date_trunc('week', v_today::timestamp)::date - 1;
    when 'last_7_days' then v_start := v_today - 6; v_end := v_today;
    when 'this_month' then
      v_start := date_trunc('month', v_today::timestamp)::date; v_end := v_today;
    when 'last_month' then
      v_start := (date_trunc('month', v_today::timestamp) - interval '1 month')::date;
      v_end := date_trunc('month', v_today::timestamp)::date - 1;
    when 'this_year' then
      v_start := date_trunc('year', v_today::timestamp)::date; v_end := v_today;
    else
      v_start := (date_trunc('year', v_today::timestamp) - interval '1 year')::date;
      v_end := date_trunc('year', v_today::timestamp)::date - 1;
  end case;

  with matched as materialized (
    select invoice.id entity_id, invoice.invoice_number, invoice.supplier_name, invoice.status,
      invoice.date, invoice.due_date, invoice.total, invoice.balance,
      invoice.receipt_state
    from public.purchase_invoice_list_read_model invoice
    where invoice.tenant_id = v_authority.tenant_id
      and (
        v_start is null
        or (invoice.date at time zone v_timezone)::date between v_start and v_end
      )
      and (v_query = '' or not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        concat_ws(' ', invoice.invoice_number, invoice.supplier_name, invoice.status,
          invoice.receipt_state)
      )) = 0))
    order by invoice.date desc, invoice.invoice_number limit p_limit + 1
  ), scope as materialized (
    -- Los totales se calculan sobre TODO lo que calza, no sobre la página.
    select count(*)::integer n, coalesce(sum(invoice.total), 0) total,
      coalesce(sum(invoice.balance), 0) balance
    from public.purchase_invoice_list_read_model invoice
    where invoice.tenant_id = v_authority.tenant_id
      and (
        v_start is null
        or (invoice.date at time zone v_timezone)::date between v_start and v_end
      )
      and (v_query = '' or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where position(token in public.assistant_normalize_query_internal_v1(
          concat_ws(' ', invoice.invoice_number, invoice.supplier_name,
            invoice.status, invoice.receipt_state)
        )) = 0))
  ), numbered as (
    select entity_id, invoice_number, supplier_name, status, date, due_date, total, balance,
      row_number() over (order by date desc, invoice_number) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'invoiceNumber', public.assistant_truncate_utf8_internal_v1(invoice_number, 100),
      'supplierName', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(supplier_name, ''), 160), ''),
      'status', public.assistant_truncate_utf8_internal_v1(status, 40), 'date', date, 'dueDate', due_date,
      'total', total, 'balance', balance,
      'matchedCount', (select n from scope),
      'matchedTotal', (select total from scope),
      'matchedBalance', (select balance from scope),
      'periodStart', v_start::text,
      'periodEnd', v_end::text
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$function$
;
