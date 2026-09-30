-- Read-back of 20260929230000_whatsapp_outbox_document_template.sql.
-- Each denominator is catalog-derived: an absent gate fails SQL.
select 1 / count(*)::integer as template_with_pdf_reserves_attachment
from pg_proc where oid = 'public.enqueue_whatsapp_message_v1(jsonb)'::regprocedure
  and prosecdef
  and has_function_privilege('authenticated', oid, 'execute')
  and not has_function_privilege('anon', oid, 'execute')
  and pg_get_functiondef(oid) like '%v_has_attachment boolean := p_request->>''type'' in (''image'', ''document'', ''audio'')%'
  and pg_get_functiondef(oid) like '%or (p_request->>''type'' = ''template''%'
  and pg_get_functiondef(oid) like '%if v_has_attachment then%'
  and pg_get_functiondef(oid) like '%when v_type in (''document'', ''audio'') or v_attachment.id is not null then ''file''%'
  -- The previous guarantees stay in the new definition.
  and pg_get_functiondef(oid) like '%and created_by = v_actor and status = ''reserved'' for update;%'
  and pg_get_functiondef(oid) like '%and channel_id = v_channel.id and external_wa_id = v_phone) then%'
  and pg_get_functiondef(oid) like '%request_hash <> v_hash%'
  and pg_get_functiondef(oid) like '%WhatsApp recipient does not match conversation%';
