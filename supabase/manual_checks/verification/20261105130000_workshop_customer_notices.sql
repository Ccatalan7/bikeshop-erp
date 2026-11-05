-- Read-back of 20261105130000. Fails before the migration (no notices, no
-- template reviews, no preferences, no pass scheduled) and passes after: the
-- three tables exist with row security and no customer write, the commands
-- carry the grants each caller needs and nothing more, the pass runs every
-- minute, and every shop starts from now (nothing older notices).

select 1 / (case when
  (select relrowsecurity from pg_class where oid = 'public.workshop_customer_notices'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.whatsapp_template_reviews'::regclass)
  and (select relrowsecurity from pg_class
        where oid = 'public.customer_workshop_notice_preferences'::regclass)
  and not has_table_privilege('authenticated', 'public.workshop_customer_notices', 'INSERT')
  and not has_table_privilege('authenticated', 'public.workshop_customer_notices', 'UPDATE')
  and not has_table_privilege('anon', 'public.workshop_customer_notices', 'SELECT')
  and not has_table_privilege('authenticated', 'public.customer_workshop_notice_preferences', 'INSERT')
  and not has_table_privilege('authenticated', 'public.whatsapp_template_reviews', 'INSERT')
  and has_function_privilege('service_role',
    'public.process_workshop_customer_notices_v1(timestamptz)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.process_workshop_customer_notices_v1(timestamptz)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.claim_workshop_customer_notices_v1(uuid, text, integer, timestamptz)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.claim_workshop_customer_notices_v1(uuid, text, integer, timestamptz)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.complete_workshop_customer_notice_v1(uuid, text, text, text, text)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.record_whatsapp_template_reviews_v1(uuid, jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.record_whatsapp_template_reviews_v1(uuid, jsonb)', 'EXECUTE')
  and has_function_privilege('service_role',
    'public.whatsapp_template_reviews_checked_at_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.workshop_customer_notice_overview_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.update_workshop_customer_notice_settings_v1(uuid, jsonb)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.get_my_workshop_notice_preferences_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated',
    'public.set_my_workshop_notice_preferences_v1(uuid, boolean, boolean)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.set_my_workshop_notice_preferences_v1(uuid, boolean, boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_link_internal(public.mechanic_jobs, text, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_dispatch_whatsapp_internal(uuid, timestamptz, boolean)', 'EXECUTE')
  and exists (
    select 1 from cron.job
     where jobname = 'vinabike_workshop_customer_notices'
       and schedule = '* * * * *'
       and command like '%process_workshop_customer_notices_v1%'
       and active)
  and not exists (
    select 1 from public.tenants tenant
     where not exists (
       select 1 from public.company_settings setting
        where setting.tenant_id = tenant.id
          and setting.key = 'workshop_notices_started_at'))
then 1 else 0 end) as avisos_del_taller;
