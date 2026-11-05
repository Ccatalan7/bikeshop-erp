-- Read-back of 20261104210000. Fails before the migration (the snapshot has no
-- diagnosis key) and passes after.

select 1 / (case when
  pg_get_functiondef('public.job_delivery_document_snapshot_internal(uuid, uuid)'::regprocedure)
    like '%''diagnosis'', nullif(trim(job.diagnosis)%'
  and pg_get_functiondef('public.job_delivery_document_snapshot_internal(uuid, uuid)'::regprocedure)
    like '%''client_request'', nullif(trim(job.client_request)%'
  and not has_function_privilege('authenticated',
    'public.job_delivery_document_snapshot_internal(uuid, uuid)', 'EXECUTE')
  and not has_function_privilege('anon',
    'public.job_delivery_document_snapshot_internal(uuid, uuid)', 'EXECUTE')
then 1 else 0 end) as afirma_solicitud_y_diagnostico_en_el_comprobante;

-- La foto de los trabajos entregados de Viñabike se arma igual que antes.
select 1 / (case when (
  select count(*) filter (where s ? 'diagnosis' and s ? 'client_request' and s ? 'lines')
       = count(*)
    from (
      select public.job_delivery_document_snapshot_internal(job.tenant_id, job.id) as s
        from public.mechanic_jobs job
       where job.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
         and job.status = 'ENTREGADO'
       order by job.updated_at desc nulls last
       limit 40
    ) snap
) then 1 else 0 end) as afirma_la_foto_con_datos_reales;
