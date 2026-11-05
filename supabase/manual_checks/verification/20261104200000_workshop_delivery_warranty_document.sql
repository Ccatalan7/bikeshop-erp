-- Read-back of 20261104200000. Fails before the migration and passes after:
-- the policy, the documents and claim tables, the new delivery columns and the
-- portal reads do not exist before; the delivery trigger and the customer
-- identity guard only name their new pieces once it is applied.

select
  (select count(*) from public.mechanic_job_delivery_documents) as comprobantes,
  (select count(*) from public.customer_portal_claim_codes) as codigos_qr,
  (select count(*) from public.mechanic_job_delivery_events
    where parts_warranty_months_snapshot is not null) as entregas_con_garantia_de_repuestos;

-- La política de Viñabike sin ajustes guardados: 14 días y 2 meses.
select 1 / (case when (
  select service_days = 14 and parts_months = 2
    from public.workshop_warranty_policy_v1('5443b130-cc28-45af-a420-cd500b288890')
) then 1 else 0 end) as afirma_la_politica_del_duenio;

select 1 / (case when
  -- Las tablas nuevas, con RLS, y los códigos cerrados a todos menos el servidor.
  (select relrowsecurity from pg_class where oid = 'public.mechanic_job_delivery_documents'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.customer_portal_claim_codes'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.customer_portal_claim_attempts'::regclass)
  and not has_table_privilege('authenticated', 'public.customer_portal_claim_codes', 'SELECT')
  and not has_table_privilege('anon', 'public.customer_portal_claim_codes', 'SELECT')
  and not has_table_privilege('authenticated', 'public.customer_portal_claim_attempts', 'SELECT')
  and not has_table_privilege('anon', 'public.mechanic_job_delivery_documents', 'SELECT')
  and not has_table_privilege('authenticated', 'public.mechanic_job_delivery_documents', 'INSERT')
  and has_table_privilege('authenticated', 'public.mechanic_job_delivery_documents', 'SELECT')
  -- La entrega guarda la garantía de los repuestos y arma el comprobante.
  and exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'mechanic_job_delivery_events'
       and column_name = 'parts_warranty_expires_at'
  )
  and pg_get_functiondef('public.capture_mechanic_job_delivery_event()'::regprocedure)
    like '%workshop_warranty_policy_v1%'
  and pg_get_functiondef('public.capture_mechanic_job_delivery_event()'::regprocedure)
    like '%create_job_delivery_document_internal%'
  and pg_get_functiondef('public.capture_mechanic_job_delivery_event()'::regprocedure)
    not like '%interval ''14 days''%'
  -- La guardia de identidad sigue en su lugar y sólo reconoce la marca del QR.
  and pg_get_functiondef('public.guard_customer_identity_update()'::regprocedure)
    like '%vinabike.portal_claim_relink%'
  and pg_get_functiondef('public.guard_customer_identity_update()'::regprocedure)
    like '%Customer self-service may update profile fields only%'
  and exists (
    select 1 from pg_trigger
     where tgrelid = 'public.customers'::regclass
       and tgname = 'trg_guard_customer_identity_update'
       and not tgisinternal
  )
  and exists (
    select 1 from pg_trigger
     where tgrelid = 'public.mechanic_jobs'::regclass
       and tgname = 'trg_mechanic_jobs_capture_delivery'
       and not tgisinternal
  )
then 1 else 0 end) as afirma_tablas_entrega_y_guardia;

select 1 / (case when
  -- Lo que llama el ERP y el portal: con sesión, nunca sin ella.
  has_function_privilege('authenticated', 'public.ensure_job_delivery_document_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.ensure_job_delivery_document_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.issue_customer_portal_claim_code_v1(uuid, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.issue_customer_portal_claim_code_v1(uuid, text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.claim_customer_portal_code_v1(uuid, text, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.claim_customer_portal_code_v1(uuid, text, text)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.list_my_job_delivery_documents_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_my_job_delivery_documents_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.list_my_sales_invoices_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.list_my_sales_invoices_v1(uuid)', 'EXECUTE')
  -- Lo interno no se llama desde afuera.
  and not has_function_privilege('authenticated', 'public.create_job_delivery_document_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.create_job_delivery_document_internal(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.job_delivery_document_snapshot_internal(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.job_delivery_document_projection_internal(uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_permisos_de_las_funciones;
