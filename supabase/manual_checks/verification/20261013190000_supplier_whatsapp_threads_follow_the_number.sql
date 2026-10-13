-- Read-back de 20261013190000: el comando del chat existe sólo para usuarios
-- autenticados, los disparadores de contacto y de ficha están puestos, el chat
-- del vendedor nuevo de Comercial Ciclo quedó en Proveedores con su persona, y
-- no queda ningún chat de cliente sin identidad cuyo número sea de un solo
-- proveedor.

select conversation.counterparty_type, conversation.context_type,
       supplier.name as supplier, contact.name as contact
  from public.conversations conversation
  left join public.suppliers supplier on supplier.id = conversation.context_id
  left join public.whatsapp_conversation_bindings binding
    on binding.conversation_id = conversation.id
  left join public.supplier_contacts contact on contact.id = binding.supplier_contact_id
 where conversation.id = '065de635-3dd6-43c0-9d1e-7b7f08cbb78a';

select 1 / case
  when has_function_privilege('authenticated', 'public.assign_whatsapp_conversation_to_supplier(uuid,uuid,uuid,jsonb)', 'execute')
   and not has_function_privilege('anon', 'public.assign_whatsapp_conversation_to_supplier(uuid,uuid,uuid,jsonb)', 'execute')
   and not has_function_privilege('authenticated', 'public.move_whatsapp_conversation_to_supplier_internal(uuid,uuid,uuid,text)', 'execute')
   and exists (
     select 1 from pg_trigger
      where tgrelid = 'public.supplier_contacts'::regclass
        and tgname = 'trg_supplier_contacts_claim_customer_threads'
   )
   and exists (
     select 1 from pg_trigger
      where tgrelid = 'public.suppliers'::regclass
        and tgname = 'trg_suppliers_claim_customer_threads'
   )
   and pg_get_functiondef('public.ingest_whatsapp_inbound_message(text,text,text,text,text,text,text,jsonb,text,uuid)'::regprocedure)
       like '%whatsapp_number_supplier%'
   and exists (
     select 1
       from public.conversations conversation
       join public.suppliers supplier
         on supplier.id = conversation.context_id
        and supplier.tenant_id = conversation.tenant_id
       join public.whatsapp_conversation_bindings binding
         on binding.conversation_id = conversation.id
      where conversation.id = '065de635-3dd6-43c0-9d1e-7b7f08cbb78a'
        and conversation.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
        and conversation.counterparty_type = 'supplier'
        and conversation.context_type = 'supplier'
        and supplier.name = 'Comercial Ciclo'
        and binding.supplier_contact_id = '893815a8-61a2-49fe-aaf0-20b323e0a6f3'
   )
   and not exists (
     select 1
       from public.whatsapp_conversation_bindings binding
       join public.conversations conversation
         on conversation.id = binding.conversation_id
       cross join lateral public.whatsapp_number_supplier(
         binding.tenant_id, binding.external_phone_number
       ) number_supplier
      where conversation.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
        and conversation.counterparty_type = 'customer'
        and not public.conversation_has_customer_identity(conversation.id)
   )
  then 1 else 0 end as supplier_threads_follow_the_number;
