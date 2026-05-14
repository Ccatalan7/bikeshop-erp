-- Align public workshop wording with the app language standard.
-- Legacy database identifiers and enum values stay unchanged for compatibility.

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.create_invoice_from_mechanic_job(uuid)'::regprocedure)
  into v_definition;

  v_definition := replace(
    v_definition,
    '''Pega '' || v_job.job_number',
    '''Trabajo '' || v_job.job_number'
  );

  execute v_definition;
end $$;

update public.sales_invoices
set reference = regexp_replace(reference, '^Pega ', 'Trabajo ')
where reference ~ '^Pega '
  and (
    source = 'mechanic_job'
    or exists (
      select 1
      from public.mechanic_jobs mj
      where mj.invoice_id = sales_invoices.id
    )
  );
