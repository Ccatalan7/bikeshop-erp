-- Un chat cuyo número es de un cliente registrado es de ese cliente, aunque
-- el vínculo de WhatsApp no alcanzara a guardarlo.
--
-- 20261013190000 decidía la identidad de cliente de un chat por el vínculo,
-- los participantes, el autor y los contextos. Faltaba el caso que vio la app
-- el mismo día: un chat de un número desconocido cuya persona se registró
-- después como cliente. El webhook une al cliente por teléfono sólo en el
-- siguiente mensaje entrante, así que hasta entonces el vínculo no lo tiene,
-- y guardar ese número en un proveedor habría pasado el chat de un cliente a
-- Proveedores. Ahora cuenta también un cliente activo del tenant con ese
-- número, con la misma comparación que usa el webhook
-- (`normalize_whatsapp_phone`).

begin;

create or replace function public.conversation_has_customer_identity(
  p_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select exists (
      select 1
        from public.whatsapp_conversation_bindings binding
       where binding.conversation_id = conversation.id
         and binding.customer_id is not null
    )
    or exists (
      select 1
        from public.whatsapp_conversation_bindings binding
        join public.customers customer
          on customer.tenant_id = binding.tenant_id
         and coalesce(customer.is_active, true)
         and public.normalize_whatsapp_phone(customer.phone) =
             public.normalize_whatsapp_phone(binding.external_phone_number)
       where binding.conversation_id = conversation.id
         and binding.external_phone_number is not null
    )
    or exists (
      select 1
        from public.conversation_participants participant
        join public.customers customer
          on customer.auth_user_id = participant.user_id
         and customer.tenant_id = conversation.tenant_id
       where participant.conversation_id = conversation.id
         and not exists (
           select 1
             from public.user_profiles staff
            where staff.user_id = participant.user_id
              and staff.tenant_id = conversation.tenant_id
              and coalesce(staff.is_active, true)
         )
    )
    or exists (
      select 1
        from public.customers customer
       where customer.auth_user_id = conversation.created_by
         and customer.tenant_id = conversation.tenant_id
    )
    or (
      conversation.context_type is not null
      and conversation.context_type not in ('supplier', 'purchase_invoice')
    )
    or exists (
      select 1
        from public.conversation_contexts context
       where context.conversation_id = conversation.id
         and context.context_type not in ('supplier', 'purchase_invoice')
    )
  from public.conversations conversation
  where conversation.id = p_conversation_id;
$$;

comment on function public.conversation_has_customer_identity(uuid) is
  'True when a conversation is tied to a customer: a customer on its WhatsApp binding or with its number, a customer participant, a customer author, or a customer-side context.';

revoke all on function public.conversation_has_customer_identity(uuid)
  from public, anon, authenticated, service_role;

commit;
