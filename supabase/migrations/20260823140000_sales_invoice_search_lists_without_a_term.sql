-- Las facturas de venta aceptan «sin término de búsqueda», como sus hermanas.
--
-- El esquema declara `query` nullable y su descripción dice literalmente «usa
-- null para pedir el listado sin filtrar»; el ejecutor también lo permite. Pero
-- esta RPC exigía `octet_length(coalesce(p_query,'')) between 1 and 240`, así
-- que un `null` legítimo moría con SQLSTATE 22023 y el asistente reportaba
-- `tool_arguments_invalid` sobre una llamada impecable.
--
-- `assistant_search_customers_v1`, `_suppliers_v1` y `_purchase_invoices_v1` ya
-- estaban corregidas: ésta quedó atrás. Lo que se prometió en el esquema tiene
-- que cumplirlo la base, o el modelo hace todo bien y falla igual.

CREATE OR REPLACE FUNCTION public.assistant_search_sales_invoices_v1(p_query text, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare v_authority record; v_query text; v_items jsonb; v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.sales'
  ) authority;
  if octet_length(coalesce(p_query, '')) > 240
     or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  -- Una consulta vacía es «lista las últimas», no un error.
  with matched as materialized (
    select invoice.id entity_id, invoice.invoice_number, invoice.customer_name, invoice.status,
      invoice.date, invoice.due_date, invoice.total, invoice.balance
    from public.sales_invoices invoice
    where invoice.tenant_id = v_authority.tenant_id and (
      -- Sin término de búsqueda no hay nada que filtrar: salen las últimas.
      nullif(v_query, '') is null or not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        concat_ws(' ', invoice.invoice_number, invoice.customer_name, invoice.status)
      )) = 0))
    order by invoice.date desc, invoice.invoice_number limit p_limit + 1
  ), numbered as (
    select entity_id, invoice_number, customer_name, status, date, due_date, total, balance,
      row_number() over (order by date desc, invoice_number) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'invoiceNumber', public.assistant_truncate_utf8_internal_v1(invoice_number, 100),
      'customerName', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(customer_name, ''), 160), ''),
      'status', public.assistant_truncate_utf8_internal_v1(status, 40), 'date', date, 'dueDate', due_date,
      'total', total, 'balance', balance
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$function$
;
