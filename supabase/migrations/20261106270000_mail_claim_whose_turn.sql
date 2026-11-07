-- Correo que trabaja: en un reclamo, de quién es el turno (2026-11-06).
--
-- 20261106260000 dejaba todo reclamo abierto en «Esperando», con un
-- recordatorio «¿Tienen novedades?». Con el correo real eso estaba mal: el
-- último correo del reclamo con Comercial Ciclo es su respuesta (dicen que el
-- despacho no les corresponde), y el turno es nuestro, no de ellos. Ahora:
--
-- * Esperamos novedades (recordatorio, «Esperando», vence a los 5 días) sólo
--   si lo último del caso lo escribimos nosotros, o si lo último de ellos es
--   un acuse de recibo («caso registrado», «estamos revisando», «número de
--   reclamo»).
-- * Si ellos respondieron, el reclamo pide «Responder» y queda en «Para hoy»
--   hasta que respondamos (entonces vuelve a esperar) o alguien lo cierre.
--
-- Como todo botón del correo, nada se guarda: se calcula del caso cada vez.

begin;

-- Un acuse de recibo: lo dice el comienzo del texto, o el asunto cuando no
-- es una respuesta (en «Re: Caso registrado…» puede venir la resolución).
create or replace function public.mail_is_acknowledgment_internal(p_subject text, p_body text)
returns boolean language sql immutable parallel safe
set search_path = pg_catalog, public
as $$
  with p as (
    select '(caso registrado|hemos recibido|recibimos (tu|su)|registramos (tu|su)|estamos revisando|en revision|numero de (caso|reclamo|solicitud|ticket)|solicitud (fue )?ingresada|reclamo (fue )?(ingresado|registrado))'::text as ack
  )
  select (coalesce(p_subject, '') !~* '^\s*(re|rv|fw|fwd)\s*:'
          and public.mail_fold_internal(p_subject) ~ p.ack)
      or public.mail_fold_internal(left(coalesce(p_body, ''), 600)) ~ p.ack
    from p;
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
  v_since timestamptz;
  v_days integer;
  v_remind_to text;
  v_last_in timestamptz;
  v_last_out timestamptz;
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
    -- Un reclamo sigue abierto hasta que una persona lo cierra. De quién es
    -- el turno lo dice su último correo: si lo escribimos nosotros, o si lo
    -- último de ellos es un acuse («caso registrado», «estamos revisando»),
    -- esperamos novedades; si ellos respondieron, nos toca responder.
    -- Cuenta sólo el último correo de ellos: los anteriores son la historia.
    select max(x.received_at) filter (where x.direction = 'in'),
           max(x.received_at) filter (where x.direction = 'out'),
           max(x.received_at)
      into v_last_in, v_last_out, v_since
      from public.mail_messages x
      join public.mail_mailboxes mb on mb.id = x.mailbox_id and mb.is_active
     where x.tenant_id = m.tenant_id
       and (x.id = m.id or (m.case_key is not null and x.case_key = m.case_key)
            or (m.provider_thread_id is not null and x.mailbox_id = m.mailbox_id
                and x.provider_thread_id = m.provider_thread_id));
    if m.received_at >= v_last_in then
      v_actionable := true;
      if (v_last_out is not null and v_last_out > m.received_at)
         or public.mail_is_acknowledgment_internal(m.subject, m.body_text) then
        v_action := 'remind';
        v_days := 5;
        -- A una dirección de no responder no se le manda el recordatorio.
        v_remind_to := case when split_part(m.from_address, '@', 1) ~ '^(no-?reply|noreply|no_responder|no-responder|donotreply)'
                            then null else m.from_address end;
      else
        v_action := 'reply';
        v_since := null;
      end if;
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

revoke all on function public.mail_is_acknowledgment_internal(text, text) from public, anon, authenticated;
revoke all on function public.mail_message_state_internal(uuid) from public, anon, authenticated, service_role;

commit;
