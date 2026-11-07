-- Correo que trabaja: una transferencia es «ya pagada» sólo si calza quién
-- pagó (2026-11-06).
--
-- Con el correo real, las 14 transferencias de los últimos 45 días salían
-- «ya registradas» por calzar el monto con algún pago cercano: sólo una tenía
-- leído el nombre de quien transfiere, y seis calzaban con más de un pago.
-- Eso puede esconder una transferencia que nadie registró, justo lo que la
-- regla del dueño prohíbe. Ahora se lee el nombre como lo escribe cada banco
-- y el estado exige monto y nombre; sin nombre, la transferencia queda para
-- elegir a mano.

begin;

create or replace function public.mail_name_tokens_internal(p_name text)
returns text[] language sql immutable parallel safe
set search_path = pg_catalog, public
as $$
  select coalesce(array_agg(distinct t), '{}')
    from unnest(regexp_split_to_array(public.mail_fold_internal(p_name), '[^a-z0-9]+')) as t
   where length(t) >= 3
     and t not in ('spa', 'ltda', 'limitada', 'compania', 'sociedad', 'empresa', 'empresas',
                   'sra', 'srta', 'cliente', 'del', 'los', 'las', 'san', 'eirl', 'comercial');
$$;

-- Dos nombres son la misma persona si comparten dos palabras (o la única que
-- tenga el más corto): «Ana María Pérez Soto» y «Ana Pérez» calzan; «Ana
-- Soto» y «Juan Soto» no.
create or replace function public.mail_names_match_internal(p_a text, p_b text)
returns boolean language sql immutable parallel safe
set search_path = pg_catalog, public
as $$
  select case
    when cardinality(x) = 0 or cardinality(y) = 0 then false
    else cardinality(array(select unnest(x) intersect select unnest(y)))
         >= least(2, cardinality(x), cardinality(y))
  end
  from (select public.mail_name_tokens_internal(p_a) as x, public.mail_name_tokens_internal(p_b) as y) s;
$$;

create or replace function public.mail_extract_facts_internal(
  p_subject text, p_body text, p_from_address text
) returns jsonb language plpgsql immutable
set search_path = pg_catalog
as $$
declare
  v_subject text := coalesce(p_subject, '');
  v_text text := v_subject || E'\n' || left(coalesce(p_body, ''), 6000);
  v_local text := lower(split_part(coalesce(p_from_address, ''), '@', 1));
  v_facts jsonb := '{}'::jsonb;
  v_match text[];
  v_list jsonb;
  v_amount numeric;
begin
  select jsonb_agg(distinct upper(m[1])) into v_list
    from regexp_matches(v_text, '\m(PG-\d{5})\M', 'gi') as m;
  if v_list is not null then v_facts := v_facts || jsonb_build_object('job_numbers', v_list); end if;

  select jsonb_agg(distinct upper(m[1])) into v_list
    from regexp_matches(v_text, '\m(WEB-\d{2}-\d{5})\M', 'gi') as m;
  if v_list is not null then v_facts := v_facts || jsonb_build_object('web_orders', v_list); end if;

  v_match := regexp_match(v_subject, 'documento tributario electr.nico\s+n(?:ro|°|º)?\.?\s*(\d{2,12})', 'i');
  if v_match is null then
    v_match := regexp_match(v_subject, 'factura electr.nica\s*:?\s*(?:n(?:ro|°|º)?\.?\s*)?(\d{3,12})', 'i');
  end if;
  if v_match is null then
    v_match := regexp_match(v_subject, 'factura de la compra\s*#?\s*(\d{6,20})', 'i');
  end if;
  if v_match is not null then v_facts := v_facts || jsonb_build_object('folio', v_match[1]); end if;

  if v_local ~ '^\d{7,8}-[0-9k]$' then
    v_facts := v_facts || jsonb_build_object('rut', upper(v_local));
  else
    v_match := regexp_match(v_text, 'r\.?\s?u\.?\s?t\.?\s*(?:emisor)?\s*:?\s*(\d{1,2}\.?\d{3}\.?\d{3}-[0-9kK])', 'i');
    if v_match is not null then v_facts := v_facts || jsonb_build_object('rut', upper(v_match[1])); end if;
  end if;

  v_match := regexp_match(v_text, '\mOF\s*:?\s*(\d{6,12})\M');
  if v_match is null then
    v_match := regexp_match(v_text, 'orden de flete\D{0,25}(\d{6,12})', 'i');
  end if;
  if v_match is not null then v_facts := v_facts || jsonb_build_object('freight_order', v_match[1]); end if;

  v_match := regexp_match(v_text, 'pedido\s+n\s*[°º.]?\s*(\d{8,12})', 'i');
  if v_match is not null then v_facts := v_facts || jsonb_build_object('tracking', v_match[1]); end if;

  select jsonb_agg(distinct m[1]) into v_list
    from regexp_matches(v_subject, '(?:orden de pedido|pedido)\s*[:#]?\s*(?:n\s*[°º.]?\s*)?#?\s*([A-Z]{0,2}\d{4,10})', 'gi') as m;
  if v_list is not null then v_facts := v_facts || jsonb_build_object('order_refs', v_list); end if;

  v_match := regexp_match(v_subject, 'caso registrado\s*:?\s*([A-Z0-9][A-Z0-9-]{5,})', 'i');
  if v_match is not null then v_facts := v_facts || jsonb_build_object('case_ref', upper(v_match[1])); end if;

  v_match := regexp_match(v_text, 'monto[^0-9$\n]{0,40}\$?\s?(\d{1,3}(?:\.\d{3})+|\d{3,9})', 'i');
  if v_match is not null then
    v_amount := public.mail_amount_internal(v_match[1]);
  end if;
  if v_amount is null then
    v_match := regexp_match(v_text, '\$\s?(\d{1,3}(?:\.\d{3})+)');
    if v_match is not null then v_amount := public.mail_amount_internal(v_match[1]); end if;
  end if;
  if v_amount is not null and v_amount > 0 then
    v_facts := v_facts || jsonb_build_object('amount', v_amount);
  end if;

  -- Quién transfiere, como lo escribe cada banco (2026-11-06, medido en los
  -- avisos reales): «nuestro(a) cliente X ha instruido/efectuado…»,
  -- «X le ha transferido», «transferencia de fondos de X hacia…», «por parte
  -- de: Nombre: X», y las etiquetas de originante u ordenante.
  v_match := regexp_match(v_subject, '(?:recibiste|te enviaron|te transfiri.)\s+(?:una\s+)?transferencia de\s+(.{3,80})$', 'i');
  if v_match is null then
    v_match := regexp_match(coalesce(p_body, ''),
      'nuestro(?:\s*\(a\))?\s+cliente\s+(?:el\s+)?(?:sr\.?\s*(?:\(a\))?\s+|sra\.?\s+)?([^,\n\r]{3,80}?)\s*[,.]?\s+(?:ha\s+(?:efectuado|instruido|realizado)|realiz[oó]|,?\s*le\s+informamos)', 'i');
  end if;
  if v_match is null then
    v_match := regexp_match(coalesce(p_body, ''),
      '(?:le|te)\s+informamos\s+que\s+([^,\n\r]{3,80}?)\s+(?:le|te)\s+ha\s+transferido', 'i');
  end if;
  if v_match is null then
    v_match := regexp_match(coalesce(p_body, ''),
      'transferencia\s+de\s+fondos\s+de\s+([^\n\r]{3,80}?)\s+hacia', 'i');
  end if;
  if v_match is null then
    v_match := regexp_match(coalesce(p_body, ''),
      'por\s+parte\s+de\s*:?\s*(?:nombre\s*:?\s*)?([^\n\r:,]{3,80})', 'i');
  end if;
  if v_match is null then
    v_match := regexp_match(coalesce(p_body, ''), '(?:nombre (?:del )?(?:originante|ordenante|remitente|titular)|de parte de|originante|ordenante)\s*:?\s*([^\n\r]{3,80})', 'i');
  end if;
  if v_match is not null then
    v_facts := v_facts || jsonb_build_object('payer', btrim(v_match[1], E' \t.:'));
  end if;

  return v_facts;
end;
$$;

create or replace function public.mail_message_state_internal(p_message_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  m public.mail_messages%rowtype;
  v_folio text;
  v_row record;
  v_done boolean := false;
  v_text text;
  v_at timestamptz;
  v_who uuid;
  v_action text;
  v_actionable boolean := false;
begin
  select * into m from public.mail_messages where id = p_message_id;
  if not found then return null; end if;
  v_folio := m.facts->>'folio';

  if m.kind in ('supplier_invoice', 'freight_invoice', 'service_invoice') then
    v_actionable := true;
    v_action := case when m.kind = 'supplier_invoice' then 'register_purchase' else 'register_expense' end;
    if v_folio is not null then
      select pi.id, pi.created_at, pi.created_by, pi.invoice_number into v_row
        from public.purchase_invoices pi
       where pi.tenant_id = m.tenant_id
         and regexp_replace(coalesce(pi.invoice_number, ''), '\D', '', 'g') = v_folio
         and (m.sender_party_id is null or pi.supplier_id = m.sender_party_id
              or (m.facts ? 'rut' and exists (select 1 from public.suppliers s
                    where s.id = pi.supplier_id and s.tenant_id = pi.tenant_id
                      and public.mail_rut_key_internal(s.rut) = public.mail_rut_key_internal(m.facts->>'rut'))))
       order by pi.created_at desc limit 1;
      if found then
        v_done := true; v_at := v_row.created_at; v_who := v_row.created_by;
        v_text := 'Ya registrada en Compras';
      else
        select e.id, e.created_at, e.created_by into v_row
          from public.expenses e
         where e.tenant_id = m.tenant_id
           and regexp_replace(coalesce(e.document_number, ''), '\D', '', 'g') = v_folio
         order by e.created_at desc limit 1;
        if found then
          v_done := true; v_at := v_row.created_at; v_who := v_row.created_by;
          v_text := 'Ya está en Gastos';
        end if;
      end if;
    end if;
  elsif m.kind = 'statement' then
    v_actionable := true;
    v_action := 'import_statement';
    select i.created_at, i.created_by into v_row
      from public.bank_statement_imports i
     where i.tenant_id = m.tenant_id and i.created_at >= m.received_at
     order by i.created_at limit 1;
    if found then
      v_done := true; v_at := v_row.created_at; v_who := v_row.created_by;
      v_text := 'Ya importada en Conciliación';
    end if;
  elsif m.kind = 'transfer' then
    v_actionable := true;
    v_action := 'register_payment';
    -- Hecho sólo si calzan el monto y el nombre de quien transfiere: un pago
    -- del mismo monto de otra persona no prueba nada (dueño, 2026-11-06:
    -- nunca esconder algo que falta hacer). Sin nombre, queda para elegir.
    if (m.facts->>'amount') is not null and nullif(m.facts->>'payer', '') is not null then
      select sp.created_at, coalesce(c.name, '') as who into v_row
        from public.sales_payments sp
        join public.sales_invoices si on si.id = sp.invoice_id and si.tenant_id = sp.tenant_id
        left join public.customers c on c.id = si.customer_id and c.tenant_id = si.tenant_id
       where sp.tenant_id = m.tenant_id and sp.deleted_at is null
         and sp.amount = (m.facts->>'amount')::numeric
         and sp.date >= m.received_at - interval '3 days'
         and sp.date < m.received_at + interval '10 days'
         and public.mail_names_match_internal(m.facts->>'payer', c.name)
       order by abs(extract(epoch from (sp.created_at - m.received_at))) limit 1;
      if found then
        v_done := true; v_at := v_row.created_at;
        v_text := 'Ya registrado: pago de ' || v_row.who;
      else
        select o.paid_at, o.order_number into v_row
          from public.online_orders o
         where o.tenant_id = m.tenant_id and coalesce(o.is_test, false) = false
           and o.total = (m.facts->>'amount')::numeric and o.paid_at is not null
           and o.paid_at between m.received_at - interval '3 days' and m.received_at + interval '10 days'
           and public.mail_names_match_internal(m.facts->>'payer', o.customer_name)
         order by o.paid_at limit 1;
        if found then
          v_done := true; v_at := v_row.paid_at;
          v_text := 'Ya pagado: ' || v_row.order_number;
        end if;
      end if;
    end if;
  elsif m.kind = 'customer' and m.direction = 'in' then
    v_actionable := true;
    v_action := 'reply';
    select x.received_at into v_at from public.mail_messages x
     where x.mailbox_id = m.mailbox_id and x.provider_thread_id = m.provider_thread_id
       and x.direction = 'out' and x.received_at > m.received_at
     order by x.received_at limit 1;
    if v_at is not null then
      v_done := true; v_text := 'Ya respondido';
    end if;
  elsif m.kind in ('review', 'claim', 'shipment', 'security', 'supplier_order', 'web_order') then
    v_actionable := m.kind in ('review', 'claim', 'security');
    v_action := case m.kind when 'review' then 'reply_review' when 'claim' then 'follow_up' when 'security' then 'review' else null end;
  end if;

  if not v_done and m.done_at is not null then
    v_done := true; v_at := m.done_at; v_who := m.done_by; v_text := 'Marcado como hecho';
  end if;

  return jsonb_build_object(
    'actionable', v_actionable,
    'action', v_action,
    'done', v_done,
    'done_text', v_text,
    'done_at', v_at,
    'done_by', case when v_who is not null then public.erp_actor_display_name(v_who, m.tenant_id) end
  );
end;
$$;

revoke all on function public.mail_name_tokens_internal(text) from public, anon, authenticated;
revoke all on function public.mail_names_match_internal(text, text) from public, anon, authenticated;
revoke all on function public.mail_extract_facts_internal(text, text, text) from public, anon, authenticated;
revoke all on function public.mail_message_state_internal(uuid) from public, anon, authenticated, service_role;

-- Los avisos de banco ya guardados se vuelven a leer con los patrones nuevos.
do $$
declare
  v_id uuid;
begin
  for v_id in select id from public.mail_messages
               where sender_party_type = 'bank' or kind in ('transfer', 'bank', 'statement') loop
    perform public.mail_classify_message_internal(v_id);
  end loop;
end;
$$;

commit;
