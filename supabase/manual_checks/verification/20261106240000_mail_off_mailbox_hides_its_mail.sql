-- Read-back of 20261106240000. Fails before the migration (the reads and the
-- table policies do not look at whether the mailbox is on) and passes after.

select 1 / (case when
  pg_get_functiondef('public.mail_inbox_v2(text, text, text, integer, timestamptz, text)'::regprocedure)
        like '%mb.is_active%'
  and pg_get_functiondef('public.mail_counts_v2(text)'::regprocedure) like '%''today'', coalesce((v_per%'
  and pg_get_functiondef('public.mail_message_v1(uuid)'::regprocedure) like '%mb.is_active%'
  and pg_get_functiondef('public.mail_record_messages_v1(text, uuid)'::regprocedure) like '%mb.is_active%'
  and pg_get_functiondef('public.mail_mark_v1(uuid[], text)'::regprocedure) like '%mb.is_active%'
  and pg_get_functiondef('public.mail_link_v1(uuid, text, uuid, boolean)'::regprocedure) like '%mb.is_active%'
  and pg_get_functiondef('public.mail_set_kind_v1(uuid, text, boolean)'::regprocedure) like '%mb.is_active%'
  and pg_get_functiondef('public.mail_inbox_v1(text, text, text, integer, timestamptz)'::regprocedure)
        like '%mail_inbox_v2(%'
  and pg_get_functiondef('public.mail_counts_v1()'::regprocedure) like '%mail_counts_v2(%'
  and (select qual from pg_policies where schemaname = 'public' and tablename = 'mail_messages'
         and policyname = 'mail_messages_staff_read') like '%is_active%'
  and (select qual from pg_policies where schemaname = 'public' and tablename = 'mail_message_links'
         and policyname = 'mail_message_links_staff_read') like '%is_active%'
  and has_function_privilege('authenticated', 'public.mail_counts_v2(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_counts_v2(text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.mail_message_v1(uuid)', 'EXECUTE')
then 1 else 0 end) as una_casilla_apagada_no_se_ve;
