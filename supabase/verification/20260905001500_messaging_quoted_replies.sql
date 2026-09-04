select 1 / ((exists (select 1 from pg_trigger where tgrelid = 'public.messages'::regclass
  and tgname = 'trg_messages_z_reply_projection' and tgenabled = 'O'))::int) as reply_trigger_enabled;
select 1 / ((position('reply_to_external_message_id' in pg_get_functiondef(
  'public.enqueue_whatsapp_message_v1(jsonb)'::regprocedure)) > 0)::int) as queued_reply_projection;
select 1 / ((not has_function_privilege('authenticated',
  'public.messaging_project_reply_v1()', 'execute'))::int) as trigger_acl;
select 1 / ((has_function_privilege('authenticated',
  'public.publish_messaging_attachment_reply_v1(uuid,text,uuid,uuid)', 'execute') and
  not has_function_privilege('anon',
  'public.publish_messaging_attachment_reply_v1(uuid,text,uuid,uuid)', 'execute'))::int) as attachment_reply_acl;
