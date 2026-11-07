-- Read-back of 20261107130000. Fails before the migration (the document
-- functions and the codes table do not exist) and passes after:
-- * a real quote of Viñabike projects with its lines, total and store
--   identity, and the total equals `total_cost` on the recent quotes;
-- * the PDF templates stay off until the store draws them (the flag is off),
--   so every notice keeps its current template;
-- * the store reads with its public key and only a valid code; every helper
--   stays closed.

select 1 / (case when
  to_regclass('public.workshop_notice_document_tokens') is not null
  and to_regprocedure('public.workshop_notice_document_v1(text)') is not null
  and to_regprocedure('public.workshop_notice_template_v2_internal(uuid,text,text,boolean)') is not null
  and to_regprocedure('public.job_quote_document_projection_internal(uuid,uuid)') is not null
then 1 else 0 end) as documentos_existen;

select 1 / (case when (
  select jsonb_array_length(projection -> 'lines') > 0
     and (projection ->> 'total')::numeric > 0
     and projection #>> '{storefront,schemaVersion}' = '1'
     and projection ->> 'job_number' is not null
    from (
      select public.job_quote_document_projection_internal(job.id, job.tenant_id) as projection
        from public.mechanic_jobs job
       where job.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
         and job.deleted_at is null
         and exists (
           select 1 from public.mechanic_job_items item
            where item.job_id = job.id and item.tenant_id = job.tenant_id)
       order by job.created_at desc
       limit 1
    ) latest
) then 1 else 0 end) as presupuesto_real_se_proyecta;

select 1 / (case when not exists (
  select 1
    from public.mechanic_jobs job
   where job.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
     and job.deleted_at is null
     and job.id in (
       select transition.job_id from public.mechanic_job_status_transitions transition
        where transition.tenant_id = job.tenant_id
          and transition.to_status = 'ESPERANDO_APROBACION'
          and transition.occurred_at > now() - interval '90 days')
     and exists (
       select 1 from public.mechanic_job_items item
        where item.job_id = job.id and item.tenant_id = job.tenant_id)
     and public.workshop_notice_quote_total_internal(job) <> round(coalesce(job.total_cost, 0))
) then 1 else 0 end) as total_igual_al_del_trabajo;

select 1 / (case when
  not public.workshop_notice_documents_enabled_internal('5443b130-cc28-45af-a420-cd500b288890')
  and public.workshop_notice_template_v2_internal('5443b130-cc28-45af-a420-cd500b288890', 'quote_ready', 'bike', false)
    is distinct from 'taller_presupuesto_pdf_v1'
  and public.workshop_notice_template_internal('5443b130-cc28-45af-a420-cd500b288890', 'delivered', 'bike')
    in ('taller_entregada_v1', 'taller_entregada_v2')
then 1 else 0 end) as pdf_apagado_hasta_la_tienda;

-- A well-formed code takes its row FOR UPDATE to count the read, which a
-- read-only verification cannot do: only the malformed one is asked here
-- (it answers before any lookup). The pgTAP covers unknown, spent and
-- expired codes.
select 1 / (case when
  public.workshop_notice_document_v1('no-es-un-codigo') is null
  and has_function_privilege('anon', 'public.workshop_notice_document_v1(text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_document_token_internal(public.workshop_customer_notices, text)', 'EXECUTE')
  and not has_function_privilege('service_role',
    'public.workshop_notice_document_token_internal(public.workshop_customer_notices, text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.job_quote_document_projection_internal(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.job_quote_document_projection_internal(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_template_v2_internal(uuid, text, text, boolean)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.workshop_notice_document_ready_internal(text, public.mechanic_jobs)', 'EXECUTE')
  and not has_table_privilege('anon', 'public.workshop_notice_document_tokens', 'SELECT')
  and not has_table_privilege('authenticated', 'public.workshop_notice_document_tokens', 'SELECT')
then 1 else 0 end) as lectura_sólo_con_código;
