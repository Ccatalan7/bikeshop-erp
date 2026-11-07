-- Correo que trabaja: lo que espera respuesta, el banco falso y el resumen de
-- la mañana (2026-11-06).
--
-- Etapa 4 de la propuesta aprobada («dale, construye la propuesta completa»):
--
-- 1. «Esperando» deja de ser sólo los reclamos. Un correo que mandamos y pide
--    algo (una pregunta, «quedo atento», «me confirman») espera respuesta de
--    quien lo recibe; si en 3 días nadie respondió en su hilo, vuelve a «Para
--    hoy» con un recordatorio listo. Un reclamo abierto espera novedades: sólo
--    su último correo es el que cuenta, y a los 5 días sin nada vuelve a «Para
--    hoy». Como todo botón del correo, nada se guarda: la respuesta en el hilo
--    lo da por hecho, y lo que una persona marca hecho se puede deshacer.
-- 2. Lo que mandamos queda en la ficha de quien lo recibe (cliente, proveedor
--    o courier), no sólo lo que llega.
-- 3. Un desconocido que se presenta como un banco (por el nombre del
--    remitente, o un asunto que nombra un banco y pide claves o datos) queda
--    como aviso de seguridad: los bancos de verdad llegan desde su dominio.
-- 4. El resumen de la mañana (`mail_morning_summary_v1`): lo que hay para hoy
--    y lo que entró, para Inicio.
--
-- Las vistas («Para hoy», «Esperando») y sus conteos usan la misma regla
-- (`mail_in_view_internal`), para que el número de la pestaña sea la lista.

begin;

create index if not exists mail_messages_in_reply_idx
  on public.mail_messages (tenant_id, in_reply_to) where in_reply_to is not null;

-- ---------------------------------------------------------------------------
-- 1. ¿Pide algo un correo que mandamos?
-- ---------------------------------------------------------------------------

-- Sólo cuenta lo que escribimos: se corta donde empieza la cita del correo al
-- que se responde («El … escribió:», líneas con «>», «De:», «-----Original»).
create or replace function public.mail_expects_reply_internal(p_body text)
returns boolean language sql immutable parallel safe
set search_path = pg_catalog, public
as $$
  with own_text as (
    select public.mail_fold_internal(coalesce((regexp_match(coalesce(p_body, ''),
      '^(.*?)(\n[ \t]*>|escribi[oó]:|wrote:|-{3,}[ \t]*(mensaje original|original message)|\n[ \t]*(de|from)[ \t]*:[ \t]|_{8,}|$)',
      'i'))[1], '')) as t
  )
  select t ~ '\?'
      or t ~ '(quedo atent|quedamos atent|me confirm|nos confirm|pueden confirm|puedes confirm|podrian |podrias |favor (de )?(confirmar|enviar|responder|revisar|indicar)|necesito|necesitamos|cotiza|espero (su|tu|sus) respuesta|aguardo|me avisa|nos avisa|me cuenta|nos cuenta|me indica|nos indica)'
    from own_text;
$$;

-- ---------------------------------------------------------------------------
-- 2. ¿Nombra a un banco?
-- ---------------------------------------------------------------------------

create or replace function public.mail_bank_named_internal(p_text text)
returns text language sql immutable parallel safe
set search_path = pg_catalog, public
as $$
  select b.label
    from (values
      (1, 'Banco de Chile', '(banco de chile|bancochile|banchile)'),
      (2, 'BancoEstado', '(banco ?estado|cuenta ?rut)'),
      (3, 'Santander', '\msantander\M'),
      (4, 'BCI', '\mbci\M'),
      (5, 'Scotiabank', 'scotiabank'),
      (6, 'Itaú', '\mitau\M'),
      (7, 'Banco Falabella', 'banco ?falabella'),
      (8, 'Banco Ripley', 'banco ?ripley'),
      (9, 'Banco Security', 'banco ?security'),
      (10, 'Banco BICE', 'banco ?bice'),
      (11, 'Banco Consorcio', 'banco ?consorcio'),
      (12, 'Banco Internacional', 'banco ?internacional'),
      (13, 'Coopeuch', 'coopeuch'),
      (14, 'Mercado Pago', 'mercado ?pago'),
      (15, 'MACH', '\mmach\M'),
      (16, 'Tenpo', '\mtenpo\M')
    ) as b(ord, label, pattern)
   where p_text is not null and public.mail_fold_internal(p_text) ~ b.pattern
   order by b.ord
   limit 1;
$$;

-- ---------------------------------------------------------------------------
-- 3. Clasificación: con quién es lo que mandamos, y el banco falso
-- ---------------------------------------------------------------------------

create or replace function public.mail_classify_message_internal(p_message_id uuid)
returns text language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  m public.mail_messages%rowtype;
  v_sender record;
  v_facts jsonb;
  v_subject text;
  v_kind text;
  v_case text;
  v_attach_xml boolean;
  v_job uuid;
  v_order uuid;
  v_invoice uuid;
  v_expense uuid;
  v_customer uuid;
  v_value text;
  v_has_primary boolean := false;
  v_addr text;
  v_party record;
  v_bank text;
begin
  select * into m from public.mail_messages where id = p_message_id for update;
  if not found then return null; end if;

  select * into v_sender from public.mail_resolve_sender_internal(m.tenant_id, m.from_address);
  v_facts := public.mail_extract_facts_internal(m.subject, m.body_text, m.from_address);
  v_subject := public.mail_fold_internal(m.subject);
  -- Lo que mandamos: con quién es (el primero de los destinatarios que no es
  -- de la casa), para ligarlo a su ficha y saber de quién se espera respuesta.
  if m.direction = 'out' then
    foreach v_addr in array (m.to_addresses || m.cc_addresses) loop
      select * into v_party from public.mail_resolve_sender_internal(m.tenant_id, v_addr);
      if v_party.party_type is distinct from 'own' then
        v_facts := v_facts || jsonb_build_object('to_party', jsonb_strip_nulls(jsonb_build_object(
          'address', v_addr, 'type', v_party.party_type, 'id', v_party.party_id, 'label', v_party.label)));
        exit;
      end if;
    end loop;
  end if;

  -- Un desconocido que se presenta como un banco: el nombre del remitente es
  -- el de un banco, o el asunto nombra uno y pide claves o datos. Los bancos
  -- de verdad llegan desde su dominio (mail_senders, tipo «bank»).
  if m.direction = 'in' and coalesce(v_sender.party_type, 'unknown') in ('unknown', 'person') then
    v_bank := coalesce(public.mail_bank_named_internal(m.from_name),
      case when public.mail_fold_internal(m.subject)
                ~ '(bloque|suspend|actualiz|verific|\mclave|token|valida|desactiv|inusual|reactiv|datos de (tu|su) cuenta)'
           then public.mail_bank_named_internal(m.subject) end);
  end if;

  v_attach_xml := exists (
    select 1 from jsonb_array_elements(m.attachments) a
     where lower(coalesce(a->>'filename', '')) like '%.xml'
        or lower(coalesce(a->>'mime_type', '')) in ('text/xml', 'application/xml'));

  if m.kind_source = 'person' then
    v_kind := m.kind;
  elsif v_sender.party_type = 'own' then
    v_kind := case when v_facts ? 'web_orders' then 'web_order' else 'own' end;
  elsif v_sender.kind_hint = 'noise' or v_sender.party_type = 'noise' then
    v_kind := 'noise';
  elsif v_bank is not null then
    v_kind := 'security';
    v_facts := v_facts || jsonb_build_object('fake_bank', true, 'bank_name', v_bank);
  elsif v_subject ~ '(alerta de seguridad|security alert|inicio de sesion|nuevo inicio|was recovered|contrasena|verifica tu|codigo de verificacion|new sign-in|sign-in attempt)' then
    v_kind := 'security';
  elsif v_sender.party_type = 'bank' then
    v_kind := case
      when v_subject like '%cartola%' then 'statement'
      when v_subject ~ '(transferencia|deposito|abono|pago recibido|recibiste)' then 'transfer'
      else 'bank' end;
  elsif v_facts ? 'folio' and (v_attach_xml or v_subject ~ '(documento tributario|factura electronica|documento electronico|factura de la compra)') then
    v_kind := case
      when v_sender.party_type = 'courier' then 'freight_invoice'
      when v_sender.party_type = 'platform' then 'service_invoice'
      else 'supplier_invoice' end;
  elsif v_subject ~ '(envio de documento electronico|documento tributario electronico)' then
    v_kind := 'supplier_invoice';
  elsif v_sender.party_type = 'courier' then
    v_kind := case
      when v_facts ? 'case_ref' or v_subject ~ '(reclamo|cobro indebido)' then 'claim'
      when v_subject ~ '(entregad|en camino|despacho|orden de flete|tu pedido|tu envio|retira|sucursal|recibimos)' then 'shipment'
      else 'shipment' end;
  elsif v_sender.party_type = 'platform' then
    v_kind := case
      when m.from_address ilike 'businessprofile-noreply@%' and v_subject ~ '(review|resena|opinion)' then 'review'
      when m.from_address ~* '^(sc-noreply|googlebase-noreply|merchant|search-console)' or v_subject ~ '(indexed|indexad|search console|merchant center|conversiones|performance report|search performance)' then 'site'
      when v_subject ~ '(recibo|receipt|factura|invoice)' then 'service_invoice'
      when m.is_bulk then 'promo'
      else 'platform' end;
  elsif v_sender.party_type = 'supplier' then
    v_kind := case
      when v_subject ~ '(reclamo|fallo|problema|cobro indebido|garantia|devolucion)' then 'claim'
      when v_subject ~ '(pedido|orden|order|compra|compraste|factur|despach|envio|cotiz|messages from sellers|mensajes de|tu paquete|llego|en camino)' or v_subject ~ '^(re|rv|fw|fwd)\s*:' then 'supplier_order'
      else 'promo' end;
  elsif v_sender.party_type = 'promo' then
    v_kind := 'promo';
  elsif v_sender.party_type = 'customer' then
    v_kind := 'customer';
  elsif v_sender.party_type = 'person' then
    v_kind := case when m.is_bulk then 'promo' else 'customer' end;
  elsif m.is_bulk then
    v_kind := 'promo';
  elsif v_subject ~ '(oferta|descuento|promo|webinar|newsletter|prueba gratis|gratis|credito pre|aprovecha|una idea para|automatiza|introduction|optimiza)' then
    v_kind := 'noise';
  else
    v_kind := 'other';
  end if;

  v_case := case
    when v_facts ? 'freight_order' then 'flete:' || (v_facts->>'freight_order')
    when v_facts ? 'tracking' and v_sender.party_type = 'courier' then 'envio:' || (v_facts->>'tracking')
    when v_facts ? 'case_ref' then 'caso:' || (v_facts->>'case_ref')
    when v_kind = 'supplier_order' and v_facts ? 'order_refs' and v_sender.party_id is not null
      then 'pedido:' || v_sender.party_id::text || ':' || (v_facts->'order_refs'->>0)
    when m.provider_thread_id is not null then 'hilo:' || m.mailbox_id::text || ':' || m.provider_thread_id
  end;

  update public.mail_messages
     set sender_party_type = coalesce(v_sender.party_type, 'unknown'),
         sender_party_id = v_sender.party_id,
         sender_label = v_sender.label,
         kind = v_kind,
         facts = v_facts,
         case_key = v_case,
         archived_at = case when v_kind = 'noise' and archived_at is null then m.received_at else archived_at end,
         archive_reason = case when v_kind = 'noise' and archived_at is null then 'noise' else archive_reason end,
         classified_at = clock_timestamp()
   where id = m.id;

  -- Vínculos: se rehacen los de reglas; los de una persona o de la IA quedan.
  delete from public.mail_message_links
   where message_id = m.id and source in ('sender', 'number', 'document', 'thread');

  -- Lo que mandamos queda en la ficha de quien lo recibe.
  if m.direction = 'out' and v_facts->'to_party'->>'type' in ('customer', 'supplier', 'courier')
     and v_facts->'to_party' ? 'id' then
    insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, source)
    values (m.tenant_id, m.id,
            case when v_facts->'to_party'->>'type' = 'customer' then 'customer' else 'supplier' end,
            (v_facts->'to_party'->>'id')::uuid, 'sender')
    on conflict (message_id, record_type, record_id) do nothing;
  end if;

  if v_sender.party_type in ('customer', 'supplier', 'courier') and v_sender.party_id is not null then
    insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, source)
    values (m.tenant_id, m.id, case when v_sender.party_type = 'customer' then 'customer' else 'supplier' end,
            v_sender.party_id, 'sender')
    on conflict (message_id, record_type, record_id) do nothing;
  end if;

  for v_value in select jsonb_array_elements_text(coalesce(v_facts->'job_numbers', '[]'::jsonb)) loop
    select j.id, j.customer_id into v_job, v_customer from public.mechanic_jobs j
     where j.tenant_id = m.tenant_id and upper(j.job_number) = v_value and j.deleted_at is null
     limit 1;
    if v_job is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
      values (m.tenant_id, m.id, 'job', v_job, not v_has_primary, 'number')
      on conflict (message_id, record_type, record_id) do nothing;
      v_has_primary := true;
    end if;
  end loop;

  for v_value in select jsonb_array_elements_text(coalesce(v_facts->'web_orders', '[]'::jsonb)) loop
    select o.id into v_order from public.online_orders o
     where o.tenant_id = m.tenant_id and upper(o.order_number) = v_value
     limit 1;
    if v_order is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
      values (m.tenant_id, m.id, 'online_order', v_order, not v_has_primary, 'number')
      on conflict (message_id, record_type, record_id) do nothing;
      v_has_primary := true;
    end if;
  end loop;

  if v_facts ? 'folio' then
    select pi.id into v_invoice from public.purchase_invoices pi
     where pi.tenant_id = m.tenant_id
       and regexp_replace(coalesce(pi.invoice_number, ''), '\D', '', 'g') = (v_facts->>'folio')
       and (pi.supplier_id = v_sender.party_id
            or (v_facts ? 'rut' and exists (
              select 1 from public.suppliers s
               where s.id = pi.supplier_id and s.tenant_id = pi.tenant_id
                 and public.mail_rut_key_internal(s.rut) = public.mail_rut_key_internal(v_facts->>'rut'))))
     order by pi.created_at desc limit 1;
    if v_invoice is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
      values (m.tenant_id, m.id, 'purchase_invoice', v_invoice, not v_has_primary, 'document')
      on conflict (message_id, record_type, record_id) do nothing;
      v_has_primary := true;
    end if;
    select e.id into v_expense from public.expenses e
     where e.tenant_id = m.tenant_id
       and regexp_replace(coalesce(e.document_number, ''), '\D', '', 'g') = (v_facts->>'folio')
       and (e.supplier_id = v_sender.party_id or v_sender.party_id is null
            or public.mail_fold_internal(e.supplier_name) = public.mail_fold_internal(v_sender.label))
     order by e.created_at desc limit 1;
    if v_expense is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
      values (m.tenant_id, m.id, 'expense', v_expense, not v_has_primary, 'document')
      on conflict (message_id, record_type, record_id) do nothing;
      v_has_primary := true;
    end if;
  end if;

  -- Una respuesta hereda los registros del correo al que responde.
  if m.in_reply_to is not null or cardinality(m.reference_ids) > 0 or m.provider_thread_id is not null then
    insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source)
    select distinct on (l.record_type, l.record_id)
           m.tenant_id, m.id, l.record_type, l.record_id, false, 'thread'
      from public.mail_messages other
      join public.mail_message_links l on l.message_id = other.id
     where other.tenant_id = m.tenant_id and other.id <> m.id
       and l.record_type in ('job', 'online_order', 'purchase_invoice', 'customer', 'supplier')
       and ((other.rfc_message_id is not null
             and (other.rfc_message_id = m.in_reply_to or other.rfc_message_id = any (m.reference_ids)))
         or (m.provider_thread_id is not null and other.mailbox_id = m.mailbox_id
             and other.provider_thread_id = m.provider_thread_id))
    on conflict (message_id, record_type, record_id) do nothing;
  end if;

  -- El cliente con un solo trabajo abierto: su correo es de ese trabajo.
  if v_kind = 'customer' and v_sender.party_type = 'customer' and not exists (
    select 1 from public.mail_message_links l where l.message_id = m.id and l.record_type = 'job') then
    select case when count(*) = 1 then (array_agg(j.id))[1] end into v_job
      from public.mechanic_jobs j
     where j.tenant_id = m.tenant_id and j.customer_id = v_sender.party_id and j.deleted_at is null
       and j.delivered_at is null and j.created_at > m.received_at - interval '90 days';
    if v_job is not null then
      insert into public.mail_message_links (tenant_id, message_id, record_type, record_id, is_primary, source, confidence)
      values (m.tenant_id, m.id, 'job', v_job, not v_has_primary, 'sender', 0.7)
      on conflict (message_id, record_type, record_id) do nothing;
    end if;
  end if;

  if not exists (select 1 from public.mail_message_links where message_id = m.id and is_primary) then
    update public.mail_message_links set is_primary = true
     where id = (select id from public.mail_message_links where message_id = m.id
                  order by case record_type when 'job' then 1 when 'online_order' then 2
                    when 'purchase_invoice' then 3 when 'expense' then 4 when 'supplier' then 5
                    when 'customer' then 6 else 7 end, created_at limit 1);
  end if;

  return v_kind;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. El estado del botón: también lo que espera respuesta
-- ---------------------------------------------------------------------------

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
  v_since timestamptz;
  v_days integer;
  v_remind_to text;
  v_last_in timestamptz;
begin
  select * into m from public.mail_messages where id = p_message_id;
  if not found then return null; end if;
  v_folio := m.facts->>'folio';

  if m.direction = 'out' then
    -- Lo que mandamos y pide algo espera respuesta de quien lo recibió. Si
    -- después mandamos otro en el mismo hilo, el que espera es ese.
    if m.facts->'to_party'->>'type' in ('customer', 'supplier', 'courier', 'person', 'unknown', 'bank')
       and public.mail_expects_reply_internal(m.body_text)
       -- En el hilo de un reclamo, el que espera es el reclamo.
       and not exists (
         select 1 from public.mail_messages x
          where x.tenant_id = m.tenant_id and x.kind = 'claim'
            and m.provider_thread_id is not null and x.mailbox_id = m.mailbox_id
            and x.provider_thread_id = m.provider_thread_id)
       and not exists (
         select 1 from public.mail_messages x
          where x.tenant_id = m.tenant_id and x.id <> m.id and x.direction = 'out'
            and x.received_at > m.received_at
            and ((m.provider_thread_id is not null and x.mailbox_id = m.mailbox_id
                  and x.provider_thread_id = m.provider_thread_id)
              or (m.rfc_message_id is not null
                  and (x.in_reply_to = m.rfc_message_id or m.rfc_message_id = any (x.reference_ids))))) then
      v_actionable := true;
      v_action := 'remind';
      v_since := m.received_at;
      v_days := 3;
      v_remind_to := m.facts->'to_party'->>'address';
      select min(x.received_at) into v_at
        from public.mail_messages x
       where x.tenant_id = m.tenant_id and x.direction = 'in' and x.received_at > m.received_at
         and ((m.provider_thread_id is not null and x.mailbox_id = m.mailbox_id
               and x.provider_thread_id = m.provider_thread_id)
           or (m.rfc_message_id is not null
               and (x.in_reply_to = m.rfc_message_id or m.rfc_message_id = any (x.reference_ids))));
      if v_at is not null then
        v_done := true;
        v_text := 'Ya respondieron';
      end if;
    end if;
  elsif m.kind in ('supplier_invoice', 'freight_invoice', 'service_invoice') then
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
  elsif m.kind = 'claim' then
    -- Un reclamo abierto espera novedades. Cuenta sólo su último correo: los
    -- anteriores son la historia del caso.
    select max(x.received_at) into v_last_in
      from public.mail_messages x
      join public.mail_mailboxes mb on mb.id = x.mailbox_id and mb.is_active
     where x.tenant_id = m.tenant_id and x.direction = 'in'
       and (x.id = m.id or (m.case_key is not null and x.case_key = m.case_key)
            or (m.provider_thread_id is not null and x.mailbox_id = m.mailbox_id
                and x.provider_thread_id = m.provider_thread_id));
    if m.received_at >= v_last_in then
      v_actionable := true;
      v_action := 'remind';
      v_days := 5;
      select max(x.received_at) into v_since
        from public.mail_messages x
        join public.mail_mailboxes mb on mb.id = x.mailbox_id and mb.is_active
       where x.tenant_id = m.tenant_id
         and (x.id = m.id or (m.case_key is not null and x.case_key = m.case_key)
              or (m.provider_thread_id is not null and x.mailbox_id = m.mailbox_id
                  and x.provider_thread_id = m.provider_thread_id));
      -- A una dirección de no responder no se le manda el recordatorio.
      v_remind_to := case when split_part(m.from_address, '@', 1) ~ '^(no-?reply|noreply|no_responder|no-responder|donotreply)'
                          then null else m.from_address end;
    end if;
  elsif m.kind in ('review', 'shipment', 'security', 'supplier_order', 'web_order') then
    v_actionable := m.kind in ('review', 'security');
    v_action := case m.kind when 'review' then 'reply_review' when 'security' then 'review' else null end;
  end if;

  if not v_done and m.done_at is not null then
    v_done := true; v_at := m.done_at; v_who := m.done_by; v_text := 'Marcado como hecho';
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'actionable', v_actionable,
    'action', v_action,
    'done', v_done,
    'done_text', v_text,
    'done_at', v_at,
    'done_by', case when v_who is not null then public.erp_actor_display_name(v_who, m.tenant_id) end,
    'waiting_since', v_since,
    'overdue', case when v_since is not null and not v_done
                    then v_since < now() - make_interval(days => v_days) end,
    'remind_to', v_remind_to
  ));
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Una sola regla para la lista y su número
-- ---------------------------------------------------------------------------

-- «Para hoy»: lo que pide algo y nadie hizo. Un seguimiento entra sólo cuando
-- venció, o cuando el reclamo trae una novedad sin leer.
create or replace function public.mail_in_view_internal(p_view text, m public.mail_messages, p_st jsonb)
returns boolean language sql stable
set search_path = pg_catalog, public
as $$
  select case p_view
    when 'today' then m.archived_at is null
      and m.received_at > now() - interval '45 days'
      and coalesce((p_st->>'actionable')::boolean, false)
      and not coalesce((p_st->>'done')::boolean, false)
      and case when p_st->>'action' = 'remind'
            then coalesce((p_st->>'overdue')::boolean, false)
                 or (m.direction = 'in' and m.read_at is null and not m.provider_read)
            else m.direction = 'in' end
    when 'waiting' then m.archived_at is null
      and m.received_at > now() - interval '120 days'
      and p_st->>'action' = 'remind'
      and coalesce((p_st->>'actionable')::boolean, false)
      and not coalesce((p_st->>'done')::boolean, false)
    when 'archived' then m.archived_at is not null
      or (m.kind = 'promo' and m.received_at < now() - interval '7 days')
    else m.archived_at is null and not (m.kind = 'promo' and m.received_at < now() - interval '7 days')
  end;
$$;

-- ---------------------------------------------------------------------------
-- 6. La bandeja y sus conteos, con esa regla
-- ---------------------------------------------------------------------------

create or replace function public.mail_inbox_v2(
  p_view text default 'today',
  p_space text default null,
  p_query text default null,
  p_limit integer default 120,
  p_before timestamptz default null,
  p_mailbox text default null
) returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_limit integer := least(greatest(coalesce(p_limit, 120), 1), 300);
  v_query text := nullif(btrim(coalesce(p_query, '')), '');
  v_digits text := nullif(regexp_replace(coalesce(p_query, ''), '\D', '', 'g'), '');
  v_result jsonb;
  v_mailbox uuid;
begin
  if nullif(btrim(coalesce(p_mailbox, '')), '') is not null then
    select mb.id into v_mailbox from public.mail_mailboxes mb
     where mb.tenant_id = v_tenant and mb.address = lower(btrim(p_mailbox)) and mb.is_active;
    if v_mailbox is null then return '[]'::jsonb; end if;
  end if;
  with base as (
    select m as msg, m.received_at, public.mail_message_state_internal(m.id) as st
      from public.mail_messages m
      join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
     where m.tenant_id = v_tenant
       and (v_mailbox is null or m.mailbox_id = v_mailbox)
       and (p_before is null or m.received_at < p_before)
       -- «Esperando» sólo mira lo que puede esperar: lo mandado y los reclamos.
       and (p_view is distinct from 'waiting'
            or (m.received_at > now() - interval '120 days' and (m.direction = 'out' or m.kind = 'claim')))
       and (p_space is null or public.mail_space_internal(m.kind, m.sender_party_type) = p_space)
       and (v_query is null
            or m.search @@ websearch_to_tsquery('spanish'::regconfig, v_query)
            or m.subject ilike '%' || v_query || '%'
            or m.from_address ilike '%' || v_query || '%'
            or coalesce(m.sender_label, '') ilike '%' || v_query || '%'
            or (length(v_digits) >= 4 and (m.facts::text like '%' || v_digits || '%'
                  or regexp_replace(m.subject, '\D', '', 'g') like '%' || v_digits || '%'))
            or exists (select 1 from jsonb_array_elements(public.mail_links_json_internal(m.id)) lk
                        where lk->>'label' ilike '%' || v_query || '%'))
     order by m.received_at desc
     limit case when p_view in ('today', 'waiting') then 400 else v_limit end
  ), picked as (
    select b.* from base b
     where public.mail_in_view_internal(p_view, b.msg, b.st)
     order by b.received_at desc
     limit v_limit
  )
  select coalesce(jsonb_agg(public.mail_message_json_internal(p.msg, false) order by p.received_at desc), '[]'::jsonb)
    into v_result
    from picked p;
  return v_result;
end;
$$;

create or replace function public.mail_counts_v2(p_mailbox text default null)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_wanted text := nullif(lower(btrim(coalesce(p_mailbox, ''))), '');
  v_mailbox uuid;
  v_today integer;
  v_waiting integer;
  v_unread integer;
  v_archived integer;
  v_per jsonb;
  v_spaces jsonb;
begin
  if v_wanted is not null then
    select mb.id into v_mailbox from public.mail_mailboxes mb
     where mb.tenant_id = v_tenant and mb.address = v_wanted and mb.is_active;
  end if;

  -- Una pasada por casilla encendida: lo de cada una para el selector y, para
  -- las pestañas, la suma (o sólo la elegida).
  with per as (
    select m.mailbox_id,
           count(*) filter (where public.mail_in_view_internal('today', m, s.st)) as today,
           count(*) filter (where public.mail_in_view_internal('waiting', m, s.st)) as waiting,
           count(*) filter (where m.read_at is null and not m.provider_read and m.archived_at is null
             and m.direction = 'in' and m.kind not in ('promo', 'noise')) as unread,
           count(*) filter (where public.mail_in_view_internal('archived', m, s.st)) as archived
      from public.mail_messages m
      join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
     cross join lateral (select public.mail_message_state_internal(m.id) as st) s
     where m.tenant_id = v_tenant and m.received_at > now() - interval '120 days'
     group by m.mailbox_id
  )
  select coalesce(sum(p.today) filter (where v_wanted is null or p.mailbox_id = v_mailbox), 0),
         coalesce(sum(p.waiting) filter (where v_wanted is null or p.mailbox_id = v_mailbox), 0),
         coalesce(sum(p.unread) filter (where v_wanted is null or p.mailbox_id = v_mailbox), 0),
         coalesce(sum(p.archived) filter (where v_wanted is null or p.mailbox_id = v_mailbox), 0),
         coalesce(jsonb_object_agg(p.mailbox_id::text, p.today), '{}'::jsonb)
    into v_today, v_waiting, v_unread, v_archived, v_per
    from per p;

  select coalesce(jsonb_object_agg(space, n), '{}'::jsonb) into v_spaces
    from (
      select public.mail_space_internal(m.kind, m.sender_party_type) as space, count(*) as n
        from public.mail_messages m
        join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
       where m.tenant_id = v_tenant and m.archived_at is null
         and (v_wanted is null or m.mailbox_id = v_mailbox)
         and not (m.kind = 'promo' and m.received_at < now() - interval '7 days')
         and m.received_at > now() - interval '60 days'
       group by 1
    ) s;

  return jsonb_build_object('today', v_today, 'waiting', v_waiting, 'unread', v_unread,
    'archived', v_archived, 'spaces', v_spaces,
    'mailboxes', (select coalesce(jsonb_agg(jsonb_build_object(
        'address', mb.address, 'provider', mb.provider, 'last_synced_at', mb.last_synced_at,
        'error', mb.last_sync_error is not null,
        'today', coalesce((v_per->>mb.id::text)::integer, 0)) order by mb.address), '[]'::jsonb)
      from public.mail_mailboxes mb where mb.tenant_id = v_tenant and mb.is_active));
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. El resumen de la mañana
-- ---------------------------------------------------------------------------

-- Lo que hay para hoy, por tipo, y lo que entró en las últimas 24 horas. Lo
-- lee Inicio; cada línea abre su grupo en «Para hoy».
create or replace function public.mail_morning_summary_v1()
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  v_result jsonb;
begin
  with base as (
    select m as msg, m.received_at, m.kind, m.direction, m.facts,
           public.mail_message_state_internal(m.id) as st
      from public.mail_messages m
      join public.mail_mailboxes mb on mb.id = m.mailbox_id and mb.is_active
     where m.tenant_id = v_tenant and m.received_at > now() - interval '45 days'
  ), today as (
    select b.* from base b where public.mail_in_view_internal('today', b.msg, b.st)
  ), amounts as (
    select b.*, case when coalesce(b.facts->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
                     then (b.facts->>'amount')::numeric end as amount
      from base b
     where b.kind = 'transfer'
  )
  select jsonb_build_object(
    'today', (select count(*) from today),
    'payments', (select count(*) from today where st->>'action' = 'register_payment'),
    'payments_amount', (select coalesce(sum(a.amount), 0) from amounts a
                         where public.mail_in_view_internal('today', a.msg, a.st)),
    'invoices', (select count(*) from today where st->>'action' in ('register_purchase', 'register_expense')),
    'statements', (select count(*) from today where st->>'action' = 'import_statement'),
    'customers', (select count(*) from today where st->>'action' = 'reply'),
    'customers_since', (select min(received_at) from today where st->>'action' = 'reply'),
    'follow_ups', (select count(*) from today where st->>'action' = 'remind'),
    'reviews', (select count(*) from today where st->>'action' = 'reply_review'),
    'security', (select count(*) from today where st->>'action' = 'review'),
    'transfers_24h', (select count(*) from amounts where received_at > now() - interval '24 hours'),
    'transfers_24h_amount', (select coalesce(sum(amount), 0) from amounts
                              where received_at > now() - interval '24 hours'),
    'transfers_24h_done', (select count(*) from amounts where received_at > now() - interval '24 hours'
                            and coalesce((st->>'done')::boolean, false)),
    'arrived_24h', (select count(*) from base where direction = 'in'
                     and received_at > now() - interval '24 hours' and kind not in ('promo', 'noise')),
    'archived_week', (select count(*) from base where direction = 'in'
                       and received_at > now() - interval '7 days' and kind in ('promo', 'noise'))
  ) into v_result;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Acceso
-- ---------------------------------------------------------------------------

revoke all on function public.mail_expects_reply_internal(text) from public, anon, authenticated;
revoke all on function public.mail_bank_named_internal(text) from public, anon, authenticated;
revoke all on function public.mail_classify_message_internal(uuid) from public, anon, authenticated;
revoke all on function public.mail_message_state_internal(uuid) from public, anon, authenticated, service_role;
revoke all on function public.mail_in_view_internal(text, public.mail_messages, jsonb) from public, anon, authenticated;
revoke all on function public.mail_inbox_v2(text, text, text, integer, timestamptz, text) from public, anon;
grant execute on function public.mail_inbox_v2(text, text, text, integer, timestamptz, text) to authenticated;
revoke all on function public.mail_counts_v2(text) from public, anon;
grant execute on function public.mail_counts_v2(text) to authenticated;
revoke all on function public.mail_morning_summary_v1() from public, anon;
grant execute on function public.mail_morning_summary_v1() to authenticated;

-- Lo ya guardado se vuelve a leer: lo mandado gana su destinatario y su
-- ficha, y un desconocido que dice ser un banco queda como aviso.
do $$
declare
  v_id uuid;
begin
  for v_id in select id from public.mail_messages
               where direction = 'out' or coalesce(sender_party_type, 'unknown') in ('unknown', 'person') loop
    perform public.mail_classify_message_internal(v_id);
  end loop;
end;
$$;

commit;
