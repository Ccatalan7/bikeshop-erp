-- Read-back de 20261013200000: un chat cuyo número es de un cliente registrado
-- cuenta como de ese cliente aunque el vínculo no lo tenga (el chat de marzo
-- del 56998357797, cuyo cliente se registró después), y la función sigue
-- siendo interna.

select 1 / case
  when public.conversation_has_customer_identity('57244577-1896-470a-b5fa-1ce17536124c')
   and not has_function_privilege('authenticated', 'public.conversation_has_customer_identity(uuid)', 'execute')
   and not exists (
     select 1
       from public.messaging_counterparty_moves move
       join public.whatsapp_conversation_bindings binding
         on binding.conversation_id = move.conversation_id
       join public.customers customer
         on customer.tenant_id = binding.tenant_id
        and public.normalize_whatsapp_phone(customer.phone) =
            public.normalize_whatsapp_phone(binding.external_phone_number)
      where move.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
   )
  then 1 else 0 end as supplier_threads_respect_customer_phone;
