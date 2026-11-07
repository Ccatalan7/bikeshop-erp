-- Correo que trabaja: a qué cobro corresponde una transferencia (2026-11-06).
--
-- Etapa 3 de la propuesta aprobada: el aviso de una transferencia ofrece
-- «Registrar pago» y, hasta hoy, sólo llevaba a la lista de pagos. Ahora el
-- correo propone dónde registrarla: las facturas con saldo del cliente que
-- transfirió y los pedidos web sin pagar del mismo monto. El nombre manda:
-- si el aviso dice quién transfirió, sólo se proponen cobros de esa persona;
-- si no lo dice, sólo los de saldo exacto, para que el operador elija. Nada
-- se registra solo: el operador abre el cobro, revisa y confirma.

begin;

create or replace function public.mail_payment_candidates_v1(p_message_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public
as $$
declare
  v_tenant uuid := public.mail_require_staff_internal();
  m public.mail_messages%rowtype;
  v_amount numeric;
  v_payer text;
  v_result jsonb;
begin
  select msg.* into m from public.mail_messages msg
    join public.mail_mailboxes mb on mb.id = msg.mailbox_id and mb.is_active
   where msg.id = p_message_id and msg.tenant_id = v_tenant;
  if not found then raise exception 'mail_not_found' using errcode = 'P0002'; end if;
  if m.kind <> 'transfer' then return '[]'::jsonb; end if;

  v_amount := case when coalesce(m.facts->>'amount', '') ~ '^[0-9]+(\.[0-9]+)?$'
                   then (m.facts->>'amount')::numeric end;
  v_payer := nullif(btrim(coalesce(m.facts->>'payer', '')), '');
  if v_amount is null or v_amount <= 0 then return '[]'::jsonb; end if;

  with pool as (
    select 'sales_invoice'::text as type, si.id, si.invoice_number as label,
           coalesce(c.name, si.customer_name) as who, si.date as at,
           si.total, si.balance,
           si.balance = v_amount as exact,
           v_payer is not null
             and public.mail_names_match_internal(v_payer, coalesce(c.name, si.customer_name)) as named
      from public.sales_invoices si
      left join public.customers c on c.id = si.customer_id and c.tenant_id = si.tenant_id
     where si.tenant_id = v_tenant
       and coalesce(si.status, '') not in ('draft', 'cancelado', 'cancelled', 'paid')
       and coalesce(si.balance, 0) >= v_amount
       and si.date > m.received_at - interval '180 days'
       and si.date < m.received_at + interval '10 days'
    union all
    select 'online_order'::text, o.id, o.order_number, o.customer_name, o.created_at,
           o.total, o.total, true,
           v_payer is not null and public.mail_names_match_internal(v_payer, o.customer_name)
      from public.online_orders o
     where o.tenant_id = v_tenant and coalesce(o.is_test, false) = false
       and o.paid_at is null
       and coalesce(o.status, '') not in ('cancelled', 'canceled', 'cancelado')
       and o.total = v_amount
       and o.created_at > m.received_at - interval '60 days'
       and o.created_at < m.received_at + interval '10 days'
  ), chosen as (
    -- Con nombre, sólo los de esa persona; sin nombre (o sin ninguno suyo),
    -- sólo los de saldo exacto.
    select * from pool p
     where p.named
        or (p.exact and not exists (select 1 from pool q where q.named))
     order by p.named desc, p.exact desc, abs(extract(epoch from (p.at - m.received_at)))
     limit 6
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'type', c.type, 'id', c.id, 'label', c.label, 'who', c.who, 'at', c.at,
           'total', c.total, 'balance', c.balance, 'exact', c.exact, 'named', c.named)
           order by c.named desc, c.exact desc, abs(extract(epoch from (c.at - m.received_at)))), '[]'::jsonb)
    into v_result
    from chosen c;
  return v_result;
end;
$$;

revoke all on function public.mail_payment_candidates_v1(uuid) from public, anon;
grant execute on function public.mail_payment_candidates_v1(uuid) to authenticated;

commit;
