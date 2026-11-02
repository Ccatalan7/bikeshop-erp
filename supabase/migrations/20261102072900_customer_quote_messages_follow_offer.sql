-- Un mensaje de oferta sigue a su oferta (corrige 20261102063700).
--
-- Una oferta que deja de estar vigente —aceptada, rechazada, reemplazada por
-- un pedido de cambios o una corrección, vencida o anulada— ya no se manda:
-- su correo pendiente y su WhatsApp «Por enviar» (oferta o recordatorio)
-- quedan omitidos con el motivo, y el aviso que le pedía al equipo mandarlo
-- queda leído. Sin esto, el ERP seguía pidiendo mandar por WhatsApp una
-- oferta que el cliente ya había aceptado, y el worker podía mandar por correo
-- una oferta anulada. Un mensaje que el worker tiene arrendado se deja: su
-- envío ya está en curso.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function public.customer_quote_offers_close_messages()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_skipped uuid[];
begin
  if old.status = 'sent' and new.status is distinct from 'sent' then
    with closed as (
      update public.customer_quote_messages m
         set state = 'skipped',
             last_error = 'La oferta ya no está vigente (' || new.status || ')',
             updated_at = clock_timestamp()
       where m.offer_id = new.id
         and m.kind in ('offer', 'reminder')
         and m.state in ('pending', 'needs_staff')
      returning m.id
    )
    select array_agg(id) into v_skipped from closed;

    if v_skipped is not null then
      update public.erp_notifications n
         set read_at = coalesce(n.read_at, clock_timestamp())
       where n.tenant_id = new.tenant_id
         and n.type = 'customer_quote_whatsapp_pending'
         and n.entity_type = 'customer_quote_message'
         and n.entity_id = any (v_skipped);
    end if;
  end if;
  return null;
end;
$$;

revoke all on function public.customer_quote_offers_close_messages()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_customer_quote_offers_close_messages on public.customer_quote_offers;
create trigger trg_customer_quote_offers_close_messages
  after update of status on public.customer_quote_offers
  for each row
  when (old.status = 'sent' and new.status is distinct from 'sent')
  execute function public.customer_quote_offers_close_messages();

commit;
