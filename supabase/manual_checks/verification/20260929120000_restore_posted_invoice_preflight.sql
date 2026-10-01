-- Read-only structural contract for the invoice DELETE guard. Before the
-- migration it must fail; local pgTAP proves the behavioral paths.
select 1 / (case when
  to_regprocedure('public.restore_backup_invoice_delete_blocker(uuid)')
    is not null
  and position('lower(coalesce(invoice.status, ''draft''))'
      in pg_get_functiondef(to_regprocedure(
        'public.restore_backup_invoice_delete_blocker(uuid)'))) > 0
  and position('public.sales_payments'
      in pg_get_functiondef(to_regprocedure(
        'public.restore_backup_invoice_delete_blocker(uuid)'))) > 0
  and position('public.purchase_payments'
      in pg_get_functiondef(to_regprocedure(
        'public.restore_backup_invoice_delete_blocker(uuid)'))) > 0
  and not has_function_privilege('anon',
      'public.restore_backup_invoice_delete_blocker(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
      'public.restore_backup_invoice_delete_blocker(uuid)', 'EXECUTE')
  and not has_function_privilege('service_role',
      'public.restore_backup_invoice_delete_blocker(uuid)', 'EXECUTE')
then 1 else 0 end) as invoice_delete_blocker_contract;

select 1 / (case when
  position('v_invoice_blocker := public.restore_backup_invoice_delete_blocker(p_tenant_id)'
      in pg_get_functiondef('public.restore_backup_preflight(uuid,uuid)'::regprocedure)) > 0
  and position('''posted_invoice_blocker'', v_invoice_blocker'
      in pg_get_functiondef('public.restore_backup_preflight(uuid,uuid)'::regprocedure)) > 0
  and position('and v_invoice_blocker is null'
      in pg_get_functiondef('public.restore_backup_preflight(uuid,uuid)'::regprocedure)) > 0
  and position('v_invoice_blocker := public.restore_backup_invoice_delete_blocker(p_tenant_id)'
      in pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure)) > 0
  and position('v_invoice_blocker ->> ''error_code'''
      in pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure)) > 0
  and position('v_invoice_blocker := public.restore_backup_invoice_delete_blocker(p_tenant_id)'
      in pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure))
    < position('v_result := public.restore_backup_internal(p_backup_id, p_tenant_id)'
      in pg_get_functiondef('public.restore_backup(uuid,uuid)'::regprocedure))
then 1 else 0 end) as restore_entrypoints_reject_before_motor;
