-- Read-back of 20261121150000. Fails before the migration and passes after.

select
  exists (select 1 from pg_trigger
           where tgrelid = 'public.payroll_vouchers'::regclass
             and tgname = 'trg_payroll_vouchers_push_alert'
             and not tgisinternal and tgenabled = 'O')
    as nomina_suena_el_telefono,
  exists (select 1 from vault.decrypted_secrets
           where name = 'push_notification_webhook_secret'
             and nullif(decrypted_secret, '') is not null)
    as hay_secreto_del_aviso;

select 1 / (case when
  exists (select 1 from pg_trigger
           where tgrelid = 'public.payroll_vouchers'::regclass
             and tgname = 'trg_payroll_vouchers_push_alert'
             and not tgisinternal and tgenabled = 'O'
             and pg_get_triggerdef(oid) like '%AFTER INSERT%'
             and pg_get_triggerdef(oid) like '%draft%')
  and not has_function_privilege('anon', 'public.invoke_push_notification_for_payroll_voucher()', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.invoke_push_notification_for_payroll_voucher()', 'EXECUTE')
  and pg_get_functiondef('public.invoke_push_notification_for_payroll_voucher()'::regprocedure)
    like '%PAYROLL_VOUCHER%'
  and pg_get_functiondef('public.invoke_push_notification_for_payroll_voucher()'::regprocedure)
    like '%interval ''1 hour''%'
  and exists (select 1 from vault.decrypted_secrets
               where name = 'push_notification_webhook_secret'
                 and nullif(decrypted_secret, '') is not null)
then 1 else 0 end) as afirma_aviso_de_nomina;
