-- An ecommerce invoice is not a workshop invoice. The July workshop identity
-- hardening asserted an authenticated workshop actor before checking whether
-- the invoice was linked to a mechanic job, which made anonymous bank-transfer
-- checkout fail atomically while inserting its internal invoice. Preserve the
-- hardened workshop implementation behind a narrow gate that returns early for
-- every non-workshop invoice.
begin;

do $$
begin
  if to_regprocedure(
    'public.sync_invoice_items_to_job_workshop_internal(uuid)'
  ) is null then
    alter function public.sync_invoice_items_to_job(uuid)
      rename to sync_invoice_items_to_job_workshop_internal;
  end if;
end $$;

revoke all on function public.sync_invoice_items_to_job_workshop_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.sync_invoice_items_to_job(
  p_invoice_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  if p_invoice_id is null then
    return;
  end if;

  select invoice.tenant_id
    into v_tenant_id
    from public.sales_invoices invoice
   where invoice.id = p_invoice_id
   for share;

  if not found then
    return;
  end if;

  -- This check is deliberately before the workshop authorization assertion.
  -- Anonymous checkout may create ecommerce invoices, but it can never invoke
  -- the workshop synchronizer for an invoice actually linked to a job.
  if not exists (
    select 1
      from public.mechanic_jobs job
     where job.invoice_id = p_invoice_id
       and job.tenant_id = v_tenant_id
  ) then
    return;
  end if;

  perform public.assert_workshop_rpc_tenant(v_tenant_id);
  perform public.sync_invoice_items_to_job_workshop_internal(p_invoice_id);
end;
$$;

revoke all on function public.sync_invoice_items_to_job(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_invoice_items_to_job(uuid)
  to authenticated;

comment on function public.sync_invoice_items_to_job(uuid) is
  'Gates invoice-to-workshop synchronization by an existing same-tenant mechanic-job link before requiring authenticated workshop access.';

do $$
begin
  if to_regprocedure(
    'public.sync_invoice_status_to_job_workshop_internal(uuid)'
  ) is null then
    alter function public.sync_invoice_status_to_job(uuid)
      rename to sync_invoice_status_to_job_workshop_internal;
  end if;
end $$;

revoke all on function public.sync_invoice_status_to_job_workshop_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.sync_invoice_status_to_job(
  p_invoice_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid;
begin
  if p_invoice_id is null then
    return;
  end if;

  select invoice.tenant_id
    into v_tenant_id
    from public.sales_invoices invoice
   where invoice.id = p_invoice_id
   for share;

  if not found then
    return;
  end if;

  if not exists (
    select 1
      from public.mechanic_jobs job
     where job.invoice_id = p_invoice_id
       and job.tenant_id = v_tenant_id
  ) then
    return;
  end if;

  perform public.assert_workshop_rpc_tenant(v_tenant_id);
  perform public.sync_invoice_status_to_job_workshop_internal(p_invoice_id);
end;
$$;

revoke all on function public.sync_invoice_status_to_job(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.sync_invoice_status_to_job(uuid)
  to authenticated;

comment on function public.sync_invoice_status_to_job(uuid) is
  'Gates invoice-status-to-workshop synchronization by an existing same-tenant mechanic-job link before requiring authenticated workshop access.';

notify pgrst, 'reload schema';

commit;
