-- Each denominator is catalog-derived: an absent gate fails SQL.
select 1 / count(*)::integer as acceptance_proves_identity_without_upkeep
from pg_proc where oid = 'public.enqueue_whatsapp_message_v1(jsonb)'::regprocedure
  and prosecdef
  and has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%and channel_id = v_channel.id and external_wa_id = v_phone) then%'
  and pg_get_functiondef(oid) like '%v_binding := jsonb_build_object(''conversation_id'', v_conversation);%'
  and pg_get_functiondef(oid) like '%v_binding := public.ensure_whatsapp_conversation_binding(%'
  and pg_get_functiondef(oid) like '%request_hash <> v_hash%'
  and pg_get_functiondef(oid) like '%WhatsApp recipient does not match conversation%';
