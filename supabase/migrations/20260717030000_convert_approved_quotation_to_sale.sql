-- Deployment status: DEPLOYED to production 2026-07-17 02:19 UTC.
-- Live read-back confirmed the public sale branch and private delegate ACLs.
-- A production BEGIN/ROLLBACK probe approved a catalog-product quotation,
-- converted/replayed it to one sale/none invoice and left zero probe rows.
--
-- Purpose:
--   Allow an approved standalone quotation containing only catalog products
--   to become a sale/none workshop wrapper and its single linked invoice in
--   one audited, idempotent transaction. The invoice remains the exclusive
--   owner of inventory, tax, accounting, receivable and payments.
--
-- Compatibility:
--   The already-deployed bicycle/component conversion body is renamed to a
--   private implementation and called unchanged for its two existing targets.
--   The public signature and grants remain stable for every deployed client.
--
-- Recovery:
--   Replace the public wrapper with a service/component-only delegate to
--   convert_mechanic_job_to_billable_service_internal. Do not delete sale
--   conversion events or linked invoices; they are durable business evidence.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

do $$
begin
  if to_regprocedure(
    'public.convert_mechanic_job_to_billable_service_internal(uuid,text,text,boolean,uuid,uuid,uuid)'
  ) is null then
    if to_regprocedure(
      'public.convert_mechanic_job_to_billable(uuid,text,text,boolean,uuid,uuid,uuid)'
    ) is null then
      raise exception 'Missing canonical quotation conversion function.';
    end if;
    alter function public.convert_mechanic_job_to_billable(
      uuid, text, text, boolean, uuid, uuid, uuid
    ) rename to convert_mechanic_job_to_billable_service_internal;
  end if;
end;
$$;

revoke all on function public.convert_mechanic_job_to_billable_service_internal(
  uuid, text, text, boolean, uuid, uuid, uuid
) from public, anon, authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'codex_test_runner') then
    execute 'revoke all on function public.convert_mechanic_job_to_billable_service_internal(uuid, text, text, boolean, uuid, uuid, uuid) from codex_test_runner';
  end if;
end;
$$;

create or replace function public.convert_mechanic_job_to_billable(
  p_job_id uuid,
  p_target_job_type text,
  p_reason text default null,
  p_create_invoice boolean default true,
  p_bike_id uuid default null,
  p_subject_id uuid default null,
  p_operation_key uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
set lock_timeout = '750ms'
as $$
declare
  v_target text := lower(btrim(coalesce(p_target_job_type, '')));
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_operation_key text := coalesce(p_operation_key, gen_random_uuid())::text;
  v_request jsonb := jsonb_build_object(
    'target_job_type', v_target,
    'reason', v_reason,
    'create_invoice', coalesce(p_create_invoice, true),
    'bike_id', p_bike_id,
    'subject_id', p_subject_id
  );
  v_job public.mechanic_jobs%rowtype;
  v_event public.mechanic_job_mode_events%rowtype;
  v_approval_event public.mechanic_job_mode_events%rowtype;
  v_current_snapshot jsonb;
  v_invoice_id uuid;
begin
  if v_target in ('service', 'item_service') then
    return public.convert_mechanic_job_to_billable_service_internal(
      p_job_id,
      v_target,
      p_reason,
      p_create_invoice,
      p_bike_id,
      p_subject_id,
      p_operation_key
    );
  end if;

  if v_target <> 'sale' then
    raise exception 'El destino debe ser venta, servicio de bicicleta o servicio de componente.'
      using errcode = '23514';
  end if;
  if not coalesce(p_create_invoice, true) then
    raise exception 'Facturar como venta requiere crear su factura vinculada.'
      using errcode = '23514';
  end if;
  if p_bike_id is not null or p_subject_id is not null then
    raise exception 'Una venta de productos no recibe bicicleta ni componente.'
      using errcode = '23514';
  end if;

  select job.* into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.deleted_at is null
  for update;

  if not found then
    raise exception 'Cotización no encontrada.';
  end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  select event.* into v_event
  from public.mechanic_job_mode_events event
  where event.tenant_id = v_job.tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.job_id is distinct from v_job.id
       or v_event.event_type <> 'converted_to_billable'
       or v_event.metadata->'request' is distinct from v_request
       or v_event.to_job_type <> 'service'
       or v_event.to_workflow_kind <> 'sale'
       or v_event.to_intake_kind <> 'none'
       or v_event.invoice_id is null then
      raise exception 'La clave de operación ya pertenece a otra transición de trabajo.'
        using errcode = '23505';
    end if;
    return jsonb_build_object(
      'job_id', v_event.job_id,
      'job_type', v_event.to_job_type,
      'workflow_kind', v_event.to_workflow_kind,
      'intake_kind', v_event.to_intake_kind,
      'quotation_status', v_event.to_quotation_status,
      'invoice_id', v_event.invoice_id,
      'event_id', v_event.id
    );
  end if;

  -- A retry with a fresh key must still resolve to the exact committed sale
  -- rather than create a second invoice.
  if v_job.job_type = 'service'
     and v_job.workflow_kind = 'sale'
     and v_job.intake_kind = 'none'
     and v_job.converted_at is not null
     and v_job.invoice_id is not null then
    select event.* into v_event
    from public.mechanic_job_mode_events event
    where event.tenant_id = v_job.tenant_id
      and event.job_id = v_job.id
      and event.event_type = 'converted_to_billable'
      and event.to_workflow_kind = 'sale'
      and event.to_intake_kind = 'none'
      and event.metadata->'request'->>'target_job_type' = 'sale'
    order by event.occurred_at desc, event.id desc
    limit 1;
    if not found or v_event.invoice_id is distinct from v_job.invoice_id then
      raise exception 'La venta convertida no tiene un comprobante de conversión coherente.'
        using errcode = '23514';
    end if;
    return jsonb_build_object(
      'job_id', v_job.id,
      'job_type', v_job.job_type,
      'workflow_kind', v_job.workflow_kind,
      'intake_kind', v_job.intake_kind,
      'quotation_status', v_job.quotation_status,
      'invoice_id', v_job.invoice_id,
      'event_id', v_event.id
    );
  end if;

  if v_job.workflow_kind <> 'quotation' or v_job.job_type <> 'quotation' then
    raise exception 'Solo una cotización puede facturarse como venta.'
      using errcode = '23514';
  end if;
  if coalesce(v_job.quotation_status, 'pending') <> 'approved' then
    raise exception 'La cotización debe estar aprobada antes de facturarse.'
      using errcode = '23514';
  end if;
  if v_job.invoice_id is not null
     or coalesce(v_job.is_invoiced, false)
     or coalesce(v_job.is_paid, false) then
    raise exception 'La cotización ya tiene evidencia financiera incompatible.'
      using errcode = '23514';
  end if;
  if v_job.intake_kind not in ('none', 'unspecified')
     or v_job.bike_id is not null
     or v_job.subject_id is not null
     or v_job.service_package_id is not null
     or exists (
       select 1
       from public.mechanic_job_bikes job_bike
       where job_bike.tenant_id = v_job.tenant_id
         and job_bike.job_id = v_job.id
     ) then
    raise exception 'Facturar como venta solo aplica cuando no se recibió bicicleta ni componente.'
      using errcode = '23514';
  end if;

  perform item.id
  from public.mechanic_job_items item
  where item.tenant_id = v_job.tenant_id
    and item.job_id = v_job.id
  order by item.id
  for update;

  if not exists (
    select 1
    from public.mechanic_job_items item
    where item.tenant_id = v_job.tenant_id
      and item.job_id = v_job.id
  ) then
    raise exception 'La venta necesita al menos un producto de catálogo.'
      using errcode = '23514';
  end if;
  if exists (
    select 1
    from public.mechanic_job_items item
    where item.tenant_id = v_job.tenant_id
      and item.job_id = v_job.id
      and (
        item.item_type is distinct from 'product'
        or item.product_id is null
      )
  ) then
    raise exception 'Facturar como venta exige que todas las líneas sean productos de catálogo, sin servicios.'
      using errcode = '23514';
  end if;

  select event.* into v_approval_event
  from public.mechanic_job_mode_events event
  where event.tenant_id = v_job.tenant_id
    and event.job_id = v_job.id
    and event.event_type = 'quotation_status_changed'
    and event.to_quotation_status = 'approved'
    and event.metadata ? 'quotation_snapshot'
  order by event.occurred_at desc, event.id desc
  limit 1;

  if not found then
    raise exception 'La aprobación no contiene una ficha inmutable; reabre y vuelve a aprobar la cotización.'
      using errcode = '23514';
  end if;
  v_current_snapshot :=
    public.mechanic_job_quotation_content_snapshot(v_job.id);
  if v_current_snapshot is distinct from
       v_approval_event.metadata->'quotation_snapshot' then
    raise exception 'La cotización cambió después de aprobarse; reábrela y solicita una nueva aprobación.'
      using errcode = '23514';
  end if;
  if v_job.quotation_valid_until is not null
     and v_job.quotation_valid_until < clock_timestamp()
     and not (
       v_approval_event.occurred_at <= v_job.quotation_valid_until
       or (
         coalesce(
           (v_approval_event.metadata->>'approved_after_expiry')::boolean,
           false
         )
         and nullif(btrim(coalesce(v_approval_event.reason, '')), '')
           is not null
       )
     ) then
    raise exception 'La cotización vencida necesita una aprobación tardía auditada con motivo antes de facturarse.'
      using errcode = '23514';
  end if;

  perform set_config('app.mechanic_job_mode_rpc', 'true', true);
  update public.mechanic_jobs job
  set job_type = 'service',
      workflow_kind = 'sale',
      intake_kind = 'none',
      bike_id = null,
      subject_id = null,
      service_package_id = null,
      quotation_status = null,
      is_warranty_job = false,
      warranty_outcome = null,
      converted_at = clock_timestamp(),
      approved_by_customer = true,
      approved_at = coalesce(job.approved_at, clock_timestamp()),
      requires_approval = false,
      mode_needs_review = false,
      mode_review_reason = null,
      updated_at = clock_timestamp()
  where job.id = v_job.id
    and job.tenant_id = v_job.tenant_id;

  v_invoice_id := public.create_billable_invoice_from_mechanic_job(v_job.id);
  if v_invoice_id is null then
    raise exception 'No se pudo crear la factura vinculada de la venta.';
  end if;

  insert into public.mechanic_job_mode_events (
    tenant_id,
    job_id,
    event_type,
    from_job_type,
    to_job_type,
    from_workflow_kind,
    to_workflow_kind,
    from_intake_kind,
    to_intake_kind,
    from_quotation_status,
    to_quotation_status,
    invoice_id,
    reason,
    actor_id,
    operation_key,
    metadata
  ) values (
    v_job.tenant_id,
    v_job.id,
    'converted_to_billable',
    v_job.job_type,
    'service',
    v_job.workflow_kind,
    'sale',
    v_job.intake_kind,
    'none',
    v_job.quotation_status,
    null,
    v_invoice_id,
    coalesce(v_reason, 'Cotización aprobada facturada como venta de productos.'),
    auth.uid(),
    v_operation_key,
    jsonb_build_object(
      'request', v_request,
      'invoice_created', true,
      'financial_owner', 'sales_invoice',
      'physical_intake_created', false
    )
  ) returning * into v_event;

  perform set_config('app.mechanic_job_mode_rpc', '', true);
  return jsonb_build_object(
    'job_id', v_job.id,
    'job_type', 'service',
    'workflow_kind', 'sale',
    'intake_kind', 'none',
    'quotation_status', null,
    'invoice_id', v_invoice_id,
    'event_id', v_event.id
  );
exception
  when others then
    perform set_config('app.mechanic_job_mode_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.convert_mechanic_job_to_billable(
  uuid, text, text, boolean, uuid, uuid, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.convert_mechanic_job_to_billable(
  uuid, text, text, boolean, uuid, uuid, uuid
) to authenticated;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'codex_test_runner') then
    execute 'grant execute on function public.convert_mechanic_job_to_billable(uuid, text, text, boolean, uuid, uuid, uuid) to codex_test_runner';
  end if;
end;
$$;

comment on function public.convert_mechanic_job_to_billable(
  uuid, text, text, boolean, uuid, uuid, uuid
) is
  'Atomically converts an approved quotation into a bicycle service, component service, or product-only sale with one audited invoice link.';

commit;
