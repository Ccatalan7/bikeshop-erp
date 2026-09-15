-- «Qué proveedores tengo» devolvía la respuesta automática de «no tengo una
-- herramienta autorizada», teniendo `search_suppliers` anunciada. La causa: el
-- query era obligatorio entre 1 y 240 bytes, así que pedir el listado completo
-- —sin término de búsqueda— era inexpresable, y el modelo concluía que la
-- herramienta no servía.
--
-- Ahora un query vacío significa «lístamelos», acotado por `limit`. Mismo
-- arreglo en clientes y facturas de compra, que tenían la misma regla.

CREATE OR REPLACE FUNCTION public.assistant_search_customers_v1(p_query text, p_limit integer DEFAULT 10)
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
    'ai.read.operational'
  ) authority;
  -- Un query vacío ya no es un error: significa «lístamelos». Sin esto,
  -- «qué proveedores tengo» era inexpresable y el asistente contestaba que
  -- no tenía herramienta, teniéndola (medido el 2026-08-21).
  if octet_length(coalesce(p_query, '')) > 240 or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  with matched as materialized (
    select customer.id entity_id, customer.name, customer.is_active, customer.updated_at
    from public.customers customer
    where customer.tenant_id = v_authority.tenant_id
      and (v_query = '' or not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        customer.name
      )) = 0))
    order by customer.updated_at desc, customer.name limit p_limit + 1
  ), numbered as (
    select entity_id, name, is_active, updated_at,
      row_number() over (order by updated_at desc, name) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160), 'isActive', is_active, 'updatedAt', updated_at
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.assistant_search_purchase_invoices_v1(p_query text, p_limit integer DEFAULT 10)
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
    'ai.read.purchases'
  ) authority;
  -- Un query vacío ya no es un error: significa «lístamelos». Sin esto,
  -- «qué proveedores tengo» era inexpresable y el asistente contestaba que
  -- no tenía herramienta, teniéndola (medido el 2026-08-21).
  if octet_length(coalesce(p_query, '')) > 240 or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  with matched as materialized (
    select invoice.id entity_id, invoice.invoice_number, invoice.supplier_name, invoice.status,
      invoice.date, invoice.due_date, invoice.total, invoice.balance,
      invoice.receipt_state
    from public.purchase_invoice_list_read_model invoice
    where invoice.tenant_id = v_authority.tenant_id
      and (v_query = '' or not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        concat_ws(' ', invoice.invoice_number, invoice.supplier_name, invoice.status,
          invoice.receipt_state)
      )) = 0))
    order by invoice.date desc, invoice.invoice_number limit p_limit + 1
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
      'total', total, 'balance', balance
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$function$
;

CREATE OR REPLACE FUNCTION public.assistant_search_suppliers_v1(p_query text, p_limit integer DEFAULT 10)
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
    'ai.read.purchases'
  ) authority;
  -- Un query vacío ya no es un error: significa «lístamelos». Sin esto,
  -- «qué proveedores tengo» era inexpresable y el asistente contestaba que
  -- no tenía herramienta, teniéndola (medido el 2026-08-21).
  if octet_length(coalesce(p_query, '')) > 240 or p_limit is null or p_limit not between 1 and 10 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  with matched as materialized (
    select supplier.id entity_id, supplier.name, supplier.is_active, supplier.updated_at
    from public.suppliers supplier
    where supplier.tenant_id = v_authority.tenant_id
      and (v_query = '' or not exists (
      select 1 from regexp_split_to_table(v_query, ' +') token
      where position(token in public.assistant_normalize_query_internal_v1(
        concat_ws(' ', supplier.name, supplier.legal_name, supplier.trade_name,
          array_to_string(supplier.aliases, ' '))
      )) = 0))
    order by supplier.updated_at desc, supplier.name limit p_limit + 1
  ), numbered as (
    select entity_id, name, is_active, updated_at,
      row_number() over (order by updated_at desc, name) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160), 'isActive', is_active, 'updatedAt', updated_at
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb), count(*)
  into v_items, v_total from numbered;
  return public.assistant_tool_envelope_internal_v1(v_authority.tenant_id, v_items, v_total > p_limit);
end;
$function$
;
