-- Deployment status: PENDING.
--
-- Purpose:
--   1. Keep workshop quotations non-posting and non-taxed until their
--      conversion creates the invoice owned by the payment terminal.
--   2. Capture the exact commercial row and line snapshot accepted by the
--      customer and refuse conversion if that content has drifted.
--   3. Prevent direct workflow/status bypasses and edits to an approved quote
--      while retaining an audited reopen -> edit -> reapprove path. Legacy
--      status-only writes remain audited during client rollout; legacy direct
--      conversion is accepted only from an already-approved, unchanged quote
--      with resolved intake.
--   4. Reject bicycle/component conversions whose explicit or persisted intake
--      object is inactive or belongs to another tenant/customer, even when a
--      historical association or free-text note still exists.
--   The exact legacy quotation normalization is isolated in 20260716035000 so
--   this schema migration does not hold a writer lock while defining bodies.
--
-- Forward recovery:
--   The new guards are additive. An older client can still create jobs and
--   edit operational fields, but workflow and quotation-status transitions
--   must use the existing RPCs. If the frontend is rolled back, leave the
--   immutable snapshots and non-posting totals in place; do not delete audit
--   evidence. Reopening an approved quotation through the status RPC is the
--   supported way to revise and approve a new version.

begin;

-- The legacy recalc added 19% on top of workshop line prices even though the
-- payment terminal owns tax classification and treats those prices as the
-- document total. For unlinked work/quotes, keep a non-taxed commercial
-- preview. For linked work, update only operational parts/labour rollups and
-- leave invoice-owned financial mirrors untouched until canonical sync.
create or replace function public.recalculate_mechanic_job_costs(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_parts_cost numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_effective_discount numeric(12,2) := 0;
  v_total numeric(12,2) := 0;
begin
  if current_setting('app.syncing_invoice_to_job', true) = 'true'
     or current_setting('app.syncing_job_to_invoice', true) = 'true' then
    return;
  end if;

  if p_job_id is null then
    return;
  end if;

  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id
  for update;

  if not found then
    return;
  end if;

  select
    coalesce(sum(coalesce(
      item.total_price,
      item.quantity * item.unit_price,
      0
    )) filter (
      where coalesce(item.item_type, 'product') <> 'service'
    ), 0),
    coalesce(sum(coalesce(
      item.total_price,
      item.quantity * item.unit_price,
      0
    )) filter (
      where coalesce(item.item_type, 'product') = 'service'
    ), 0)
  into v_parts_cost, v_labor_cost
  from public.mechanic_job_items item
  where item.job_id = v_job.id
    and item.tenant_id = v_job.tenant_id;

  v_parts_cost := round(v_parts_cost, 2);
  v_labor_cost := round(v_labor_cost, 2);
  v_subtotal := round(v_parts_cost + v_labor_cost, 2);
  v_discount := round(coalesce(v_job.discount_amount, 0), 2);

  if v_discount < 0 then
    raise exception 'El descuento del trabajo no puede ser negativo.'
      using errcode = '23514';
  end if;

  -- Legacy clients persist the job before its lines. Preserve the requested
  -- discount while clamping only its temporary application; approval below
  -- rejects a final quotation whose complete subtotal still cannot cover it.
  v_effective_discount := least(v_discount, v_subtotal);
  v_total := round(v_subtotal - v_effective_discount, 2);

  if v_job.invoice_id is null then
    update public.mechanic_jobs
    set parts_cost = v_parts_cost,
        labor_cost = v_labor_cost,
        final_cost = v_total,
        tax_amount = 0,
        total_cost = v_total,
        tax_treatment = 'no_tax',
        updated_at = clock_timestamp()
    where id = v_job.id
      and tenant_id = v_job.tenant_id;
  else
    update public.mechanic_jobs
    set parts_cost = v_parts_cost,
        labor_cost = v_labor_cost,
        updated_at = clock_timestamp()
    where id = v_job.id
      and tenant_id = v_job.tenant_id;
  end if;
end;
$$;

revoke all on function public.recalculate_mechanic_job_costs(uuid)
  from public, anon, authenticated, service_role;

comment on function public.recalculate_mechanic_job_costs(uuid) is
  'Recalculates operational line rollups. Unlinked jobs remain no-tax previews; linked tax/totals remain invoice-owned.';

-- Reinstall the canonical conversion command with strict intake-subject
-- validation before invoice construction. The event guard below repeats the
-- check at commit time as defense in depth against concurrent deactivation.
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
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_event public.mechanic_job_mode_events%rowtype;
  v_target_job_type text := lower(btrim(coalesce(p_target_job_type, '')));
  v_target_intake_kind text;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_bike public.bikes%rowtype;
  v_subject public.job_subjects%rowtype;
  v_job_bike_id uuid;
  v_invoice_id uuid;
  v_operation_key text := coalesce(p_operation_key, gen_random_uuid())::text;
  v_latest_quotation_event public.mechanic_job_mode_events%rowtype;
  v_request jsonb := jsonb_build_object(
    'target_job_type', v_target_job_type,
    'reason', v_reason,
    'create_invoice', coalesce(p_create_invoice, true),
    'bike_id', p_bike_id,
    'subject_id', p_subject_id
  );
begin
  if v_target_job_type not in ('service', 'item_service') then
    raise exception 'El destino debe ser servicio de bicicleta o servicio de componente.';
  end if;
  v_target_intake_kind := case
    when v_target_job_type = 'item_service' then 'component'
    else 'bike'
  end;

  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Cotización no encontrada.';
  end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  select * into v_event
  from public.mechanic_job_mode_events
  where tenant_id = v_job.tenant_id
    and operation_key = v_operation_key;
  if found then
    if v_event.job_id <> v_job.id
       or v_event.event_type <> 'converted_to_billable'
       or v_event.metadata->'request' is distinct from v_request then
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

  -- A retry can arrive with a fresh client operation key after the original
  -- response was lost. Once the row already matches the requested converted
  -- target, return the committed result instead of creating a second invoice
  -- or event. The immutable conversion event remains the durable receipt.
  if v_job.workflow_kind = 'service'
     and v_job.job_type = v_target_job_type
     and v_job.intake_kind = v_target_intake_kind
     and v_job.converted_at is not null then
    select * into v_event
    from public.mechanic_job_mode_events
    where tenant_id = v_job.tenant_id
      and job_id = v_job.id
      and event_type = 'converted_to_billable'
    order by occurred_at desc, id desc
    limit 1;

    if not found
       or v_event.metadata->'request'->>'target_job_type'
            is distinct from v_target_job_type
       or coalesce(
            (v_event.metadata->'request'->>'create_invoice')::boolean,
            true
          ) is distinct from coalesce(p_create_invoice, true)
       or v_event.metadata->'request'->>'bike_id'
            is distinct from p_bike_id::text
       or v_event.metadata->'request'->>'subject_id'
            is distinct from p_subject_id::text then
      raise exception 'La cotización ya fue convertida con una solicitud diferente.'
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
    raise exception 'Solo una cotización puede convertirse con este comando.'
      using errcode = '23514';
  end if;
  if coalesce(v_job.quotation_status, 'pending') <> 'approved' then
    raise exception 'La cotización debe estar aprobada antes de convertirse.'
      using errcode = '23514';
  end if;
  if v_job.quotation_valid_until is not null
     and v_job.quotation_valid_until < clock_timestamp() then
    select * into v_latest_quotation_event
    from public.mechanic_job_mode_events
    where tenant_id = v_job.tenant_id
      and job_id = v_job.id
      and event_type = 'quotation_status_changed'
    order by occurred_at desc, id desc
    limit 1;

    if not found
       or v_latest_quotation_event.to_quotation_status <> 'approved'
       or not (
         v_latest_quotation_event.occurred_at <= v_job.quotation_valid_until
         or (
           coalesce(
             (v_latest_quotation_event.metadata->>'approved_after_expiry')::boolean,
             false
           )
           and nullif(btrim(coalesce(v_latest_quotation_event.reason, '')), '')
             is not null
         )
       ) then
      raise exception 'La cotización vencida necesita una aprobación tardía auditada con motivo antes de convertirse.'
        using errcode = '23514';
    end if;
  end if;

  if v_target_job_type = 'service' then
    if p_subject_id is not null then
      raise exception 'Un servicio de bicicleta no acepta un componente suelto como objeto principal.'
        using errcode = '23514';
    end if;

    if p_bike_id is not null then
      select * into v_bike
      from public.bikes
      where id = p_bike_id
        and tenant_id = v_job.tenant_id
        and customer_id = v_job.customer_id
        and is_active;
    elsif v_job.bike_id is not null then
      select * into v_bike
      from public.bikes
      where id = v_job.bike_id
        and tenant_id = v_job.tenant_id
        and customer_id = v_job.customer_id
        and is_active;
    else
      select bike.* into v_bike
      from public.mechanic_job_bikes job_bike
      join public.bikes bike
        on bike.id = job_bike.bike_id
       and bike.tenant_id = job_bike.tenant_id
      where job_bike.tenant_id = v_job.tenant_id
        and job_bike.job_id = v_job.id
        and bike.customer_id = v_job.customer_id
        and bike.is_active
      order by job_bike.order_index, job_bike.created_at, job_bike.id
      limit 1;
    end if;

    if v_bike.id is null then
      raise exception 'Selecciona una bicicleta activa del mismo cliente antes de convertir la cotización.'
        using errcode = '23514';
    end if;

    insert into public.mechanic_job_bikes (
      tenant_id, job_id, bike_id, order_index, work_requested
    ) values (
      v_job.tenant_id, v_job.id, v_bike.id, 0, v_job.client_request
    )
    on conflict (job_id, bike_id) do update
      set updated_at = excluded.updated_at
    returning id into v_job_bike_id;

    update public.mechanic_job_items
    set job_bike_id = v_job_bike_id,
        updated_at = clock_timestamp()
    where tenant_id = v_job.tenant_id
      and job_id = v_job.id
      and job_bike_id is null;
  else
    if p_bike_id is not null then
      raise exception 'Un servicio de componente no recibe la bicicleta completa.'
        using errcode = '23514';
    end if;

    if p_subject_id is not null then
      select * into v_subject
      from public.job_subjects
      where id = p_subject_id
        and tenant_id = v_job.tenant_id
        and is_active;

      if v_subject.id is null then
        raise exception 'El componente recibido debe estar activo y pertenecer al negocio del trabajo.'
          using errcode = '23514';
      end if;
    elsif v_job.subject_id is not null then
      select * into v_subject
      from public.job_subjects
      where id = v_job.subject_id
        and tenant_id = v_job.tenant_id
        and is_active;

      if v_subject.id is null then
        raise exception 'El componente recibido debe estar activo y pertenecer al negocio del trabajo.'
          using errcode = '23514';
      end if;
    elsif nullif(btrim(coalesce(v_job.subject_notes, '')), '') is null then
      raise exception 'Selecciona o describe el componente recibido antes de convertir la cotización.'
        using errcode = '23514';
    end if;
  end if;

  perform set_config('app.mechanic_job_mode_rpc', 'true', true);
  update public.mechanic_jobs
  set job_type = v_target_job_type,
      workflow_kind = 'service',
      intake_kind = v_target_intake_kind,
      bike_id = case when v_target_job_type = 'service' then v_bike.id else null end,
      subject_id = case
        when v_target_job_type = 'item_service' then coalesce(v_subject.id, subject_id)
        else null
      end,
      quotation_status = null,
      is_warranty_job = false,
      warranty_outcome = null,
      converted_at = clock_timestamp(),
      approved_by_customer = true,
      approved_at = coalesce(approved_at, clock_timestamp()),
      mode_needs_review = false,
      mode_review_reason = null,
      updated_at = clock_timestamp()
  where id = v_job.id;

  if coalesce(p_create_invoice, true) then
    v_invoice_id := public.create_billable_invoice_from_mechanic_job(v_job.id);
  else
    v_invoice_id := null;
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
    v_target_job_type,
    v_job.workflow_kind,
    'service',
    v_job.intake_kind,
    v_target_intake_kind,
    v_job.quotation_status,
    null,
    v_invoice_id,
    v_reason,
    auth.uid(),
    v_operation_key,
    jsonb_build_object(
      'quotation_snapshot', jsonb_build_object(
        'valid_until', v_job.quotation_valid_until,
        'total_cost', v_job.total_cost,
        'discount_amount', v_job.discount_amount,
        'tax_treatment', v_job.tax_treatment
      ),
      'bike_id', case when v_bike.id is null then null else v_bike.id end,
      'subject_id', case when v_subject.id is null then null else v_subject.id end,
      'invoice_created', coalesce(p_create_invoice, true),
      'request', v_request
    )
  ) returning * into v_event;
  perform set_config('app.mechanic_job_mode_rpc', '', true);

  return jsonb_build_object(
    'job_id', v_job.id,
    'job_type', v_target_job_type,
    'workflow_kind', 'service',
    'intake_kind', v_target_intake_kind,
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

comment on function public.convert_mechanic_job_to_billable(uuid, text, text, boolean, uuid, uuid, uuid) is
  'Atomically converts an approved quotation after validating active tenant-owned intake, optionally creating the invoice.';

-- Stable commercial snapshot: conversion-only intake attribution and mutable
-- lifecycle timestamps are deliberately excluded; every customer-facing field
-- and line attribute is included.
create or replace function public.mechanic_job_quotation_content_snapshot(
  p_job_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'job', jsonb_build_object(
      'id', job.id,
      'tenant_id', job.tenant_id,
      'job_number', job.job_number,
      'customer_id', job.customer_id,
      'service_package_id', job.service_package_id,
      'client_request', job.client_request,
      'diagnosis', job.diagnosis,
      'work_performed', job.work_performed,
      'notes', job.notes,
      'subject_notes', job.subject_notes,
      'estimated_cost', job.estimated_cost,
      'parts_cost', job.parts_cost,
      'labor_cost', job.labor_cost,
      'final_cost', job.final_cost,
      'discount_amount', job.discount_amount,
      'tax_amount', job.tax_amount,
      'total_cost', job.total_cost,
      'tax_treatment', job.tax_treatment,
      'quotation_valid_until', job.quotation_valid_until
    ),
    'items', coalesce((
      select jsonb_agg(
        to_jsonb(item) - array['job_bike_id', 'created_at', 'updated_at']::text[]
        order by item.created_at, item.id
      )
      from public.mechanic_job_items item
      where item.job_id = job.id
        and item.tenant_id = job.tenant_id
    ), '[]'::jsonb)
  )
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.deleted_at is null;
$$;

revoke all on function public.mechanic_job_quotation_content_snapshot(uuid)
  from public, anon, authenticated, service_role;

comment on function public.mechanic_job_quotation_content_snapshot(uuid) is
  'Private exact commercial snapshot used to prove what quotation content was approved and converted.';

create or replace function public.enrich_mechanic_job_mode_event_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_snapshot jsonb;
  v_approval_event public.mechanic_job_mode_events%rowtype;
  v_job_tenant_id uuid;
  v_job_subject_id uuid;
  v_job_subject_notes text;
  v_request_subject_id uuid;
begin
  select tenant_id, subject_id, subject_notes
  into v_job_tenant_id, v_job_subject_id, v_job_subject_notes
  from public.mechanic_jobs
  where id = new.job_id;

  if v_job_tenant_id is null
     or v_job_tenant_id is distinct from new.tenant_id then
    raise exception 'Quotation snapshot event does not match the job tenant.'
      using errcode = '23514';
  end if;

  if new.event_type = 'quotation_status_changed'
     and new.to_quotation_status in ('approved', 'rejected', 'expired') then
    v_snapshot := public.mechanic_job_quotation_content_snapshot(new.job_id);
    if v_snapshot is null then
      raise exception 'No se pudo capturar el contenido de la cotización aprobada.';
    end if;
    if new.to_quotation_status = 'approved'
       and coalesce(
         (v_snapshot->'job'->>'discount_amount')::numeric,
         0
       ) > coalesce(
         (v_snapshot->'job'->>'parts_cost')::numeric,
         0
       ) + coalesce(
         (v_snapshot->'job'->>'labor_cost')::numeric,
         0
       ) then
      raise exception 'El descuento no puede superar el subtotal antes de aprobar el presupuesto.'
        using errcode = '23514';
    end if;
    new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
      'quotation_snapshot', v_snapshot,
      'quotation_snapshot_hash',
        encode(extensions.digest(v_snapshot::text, 'sha256'), 'hex'),
      'quotation_snapshot_hash_algorithm', 'sha256',
      'snapshot_contract', 'commercial-content-v1'
    );
  elsif new.event_type = 'converted_to_billable' then
    if new.to_intake_kind = 'component' then
      v_request_subject_id := nullif(
        btrim(coalesce(new.metadata->'request'->>'subject_id', '')),
        ''
      )::uuid;

      if v_request_subject_id is not null
         and not exists (
           select 1
           from public.job_subjects subject
           where subject.id = v_request_subject_id
             and subject.tenant_id = new.tenant_id
             and subject.is_active
         ) then
        raise exception 'El componente recibido debe estar activo y pertenecer al negocio del trabajo.'
          using errcode = '23514';
      end if;

      if v_job_subject_id is not null then
        if not exists (
          select 1
          from public.job_subjects subject
          where subject.id = v_job_subject_id
            and subject.tenant_id = new.tenant_id
            and subject.is_active
        ) then
          raise exception 'El componente recibido debe estar activo y pertenecer al negocio del trabajo.'
            using errcode = '23514';
        end if;
      elsif nullif(btrim(coalesce(v_job_subject_notes, '')), '') is null then
        raise exception 'Selecciona o describe el componente recibido antes de convertir la cotización.'
          using errcode = '23514';
      end if;
    end if;

    select * into v_approval_event
    from public.mechanic_job_mode_events event
    where event.tenant_id = new.tenant_id
      and event.job_id = new.job_id
      and event.event_type = 'quotation_status_changed'
      and event.to_quotation_status = 'approved'
      and event.metadata ? 'quotation_snapshot'
    order by event.occurred_at desc, event.id desc
    limit 1;

    if not found then
      raise exception 'La aprobación no contiene una ficha inmutable; reabre y vuelve a aprobar la cotización.'
        using errcode = '23514';
    end if;

    v_snapshot := public.mechanic_job_quotation_content_snapshot(new.job_id);
    if v_snapshot is distinct from v_approval_event.metadata->'quotation_snapshot' then
      raise exception 'La cotización cambió después de aprobarse; reábrela y solicita una nueva aprobación.'
        using errcode = '23514';
    end if;

    new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
      'quotation_snapshot', v_approval_event.metadata->'quotation_snapshot',
      'quotation_snapshot_hash',
        v_approval_event.metadata->>'quotation_snapshot_hash',
      'quotation_approval_event_id', v_approval_event.id,
      'snapshot_contract', 'commercial-content-v1',
      'snapshot_verified_at_conversion', true
    );
  end if;

  return new;
end;
$$;

revoke all on function public.enrich_mechanic_job_mode_event_snapshot()
  from public, anon, authenticated, service_role;

create or replace function public.guard_canonical_mechanic_job_mode_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parts_cost numeric(12,2) := 0;
  v_labor_cost numeric(12,2) := 0;
  v_subtotal numeric(12,2) := 0;
  v_discount numeric(12,2) := 0;
  v_approval_event public.mechanic_job_mode_events%rowtype;
  v_current_snapshot jsonb;
  v_subject_tenant_id uuid;
  v_subject_is_active boolean;
  v_now timestamptz := clock_timestamp();
begin
  if current_setting('app.mechanic_job_mode_rpc', true) = 'true' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.workflow_kind = 'quotation'
       and coalesce(new.quotation_status, 'pending') <> 'pending' then
      raise exception 'Una cotización nueva siempre comienza pendiente; registra su decisión después de guardarla.'
        using errcode = '23514';
    end if;
  else
    if old.workflow_kind = 'quotation'
       and new.workflow_kind = 'quotation'
       and old.quotation_status is distinct from new.quotation_status then
      if new.quotation_status is null
         or new.quotation_status not in ('pending', 'approved', 'rejected', 'expired') then
        raise exception 'Estado de cotización inválido: %', new.quotation_status
          using errcode = '23514';
      end if;

      -- The deployed legacy client issues a one-column status update. Do not
      -- let that compatibility path become an approval-plus-edit command.
      if (
        to_jsonb(new) - array[
          'quotation_status', 'approved_by_customer', 'approved_at',
          'updated_at'
        ]::text[]
      ) is distinct from (
        to_jsonb(old) - array[
          'quotation_status', 'approved_by_customer', 'approved_at',
          'updated_at'
        ]::text[]
      ) then
        raise exception 'La versión anterior solo puede cambiar el estado del presupuesto; edita su contenido desde la versión actual.'
          using errcode = '23514';
      end if;

      if new.quotation_status = 'approved'
         and old.quotation_status is distinct from 'approved'
         and old.quotation_valid_until is not null
         and old.quotation_valid_until < v_now then
        raise exception 'La cotización venció; apruébala desde la versión actual para registrar el motivo.'
          using errcode = '23514';
      end if;

      new.approved_by_customer := new.quotation_status = 'approved';
      new.approved_at := case
        when new.quotation_status = 'approved' then v_now
        else null
      end;
    end if;

    if old.workflow_kind is distinct from new.workflow_kind then
      if old.workflow_kind = 'quotation' and new.workflow_kind = 'service' then
        if old.quotation_status <> 'approved' then
          raise exception 'La versión anterior solo puede convertir un presupuesto previamente aprobado; actualiza la aplicación para completar este flujo.'
            using errcode = '23514';
        end if;

        if old.invoice_id is not null
           or new.invoice_id is not null
           or coalesce(old.is_invoiced, false)
           or coalesce(new.is_invoiced, false)
           or coalesce(old.is_paid, false)
           or coalesce(new.is_paid, false) then
          raise exception 'La conversión anterior no puede vincular facturas ni pagos; la factura se crea en la acción atómica posterior.'
            using errcode = '23514';
        end if;

        -- The old client only changed the compatibility mode fields listed
        -- below. Reject every other mutation, especially customer/commercial
        -- injection, instead of silently normalizing it.
        if (
          to_jsonb(new) - array[
            'job_type', 'workflow_kind', 'intake_kind',
            'quotation_status', 'quotation_valid_until',
            'is_warranty_job', 'converted_at',
            'approved_by_customer', 'approved_at',
            'mode_needs_review', 'mode_review_reason', 'updated_at'
          ]::text[]
        ) is distinct from (
          to_jsonb(old) - array[
            'job_type', 'workflow_kind', 'intake_kind',
            'quotation_status', 'quotation_valid_until',
            'is_warranty_job', 'converted_at',
            'approved_by_customer', 'approved_at',
            'mode_needs_review', 'mode_review_reason', 'updated_at'
          ]::text[]
        ) then
          raise exception 'La conversión desde la versión anterior contiene cambios no permitidos; usa la versión actual.'
            using errcode = '23514';
        end if;

        if new.intake_kind = 'unspecified' then
          raise exception 'Selecciona la bicicleta o componente recibido desde la versión actual antes de convertir el presupuesto.'
            using errcode = '23514';
        end if;

        if new.intake_kind = 'bike' then
          if new.bike_id is null
             or new.subject_id is not null
             or not exists (
               select 1
               from public.bikes bike
               where bike.id = new.bike_id
                 and bike.tenant_id = new.tenant_id
                 and bike.customer_id = new.customer_id
                 and bike.is_active
             ) then
            raise exception 'La bicicleta recibida debe estar activa y pertenecer al cliente y negocio del trabajo.'
              using errcode = '23514';
          end if;
        elsif new.intake_kind = 'component' then
          if new.bike_id is not null then
            raise exception 'Un servicio de componente no recibe la bicicleta completa.'
              using errcode = '23514';
          end if;

          if new.subject_id is not null then
            select subject.tenant_id, subject.is_active
            into v_subject_tenant_id, v_subject_is_active
            from public.job_subjects subject
            where subject.id = new.subject_id;

            if not found
               or v_subject_tenant_id is distinct from new.tenant_id
               or not coalesce(v_subject_is_active, false) then
              raise exception 'El componente recibido debe estar activo y pertenecer al negocio del trabajo.'
                using errcode = '23514';
            end if;
          elsif nullif(btrim(coalesce(new.subject_notes, '')), '') is null then
            raise exception 'Selecciona o describe el componente recibido antes de convertir la cotización.'
              using errcode = '23514';
          end if;
        else
          raise exception 'Selecciona la bicicleta o componente recibido desde la versión actual antes de convertir el presupuesto.'
            using errcode = '23514';
        end if;

        select * into v_approval_event
        from public.mechanic_job_mode_events event
        where event.tenant_id = old.tenant_id
          and event.job_id = old.id
          and event.event_type = 'quotation_status_changed'
          and event.to_quotation_status = 'approved'
          and event.metadata ? 'quotation_snapshot'
        order by event.occurred_at desc, event.id desc
        limit 1;

        v_current_snapshot :=
          public.mechanic_job_quotation_content_snapshot(old.id);
        if not found
           or v_current_snapshot is distinct from
                v_approval_event.metadata->'quotation_snapshot' then
          raise exception 'El presupuesto cambió o no tiene una aprobación verificable; reábrelo y apruébalo desde la versión actual.'
            using errcode = '23514';
        end if;

        if old.quotation_valid_until is not null
           and old.quotation_valid_until < v_now
           and not (
             v_approval_event.occurred_at <= old.quotation_valid_until
             or (
               coalesce(
                 (v_approval_event.metadata->>'approved_after_expiry')::boolean,
                 false
               )
               and nullif(btrim(coalesce(v_approval_event.reason, '')), '')
                 is not null
             )
           ) then
          raise exception 'La cotización vencida necesita una aprobación tardía auditada con motivo antes de convertirse.'
            using errcode = '23514';
        end if;

        -- Older clients clear this field during conversion even though it is
        -- part of the approved commercial snapshot. Preserve the evidence and
        -- normalize the resulting service axes without inventing an invoice.
        new.quotation_valid_until := old.quotation_valid_until;
        new.quotation_status := null;
        new.invoice_id := null;
        new.is_invoiced := false;
        new.is_paid := false;
        new.is_warranty_job := false;
        new.approved_by_customer := true;
        new.approved_at := coalesce(old.approved_at, v_now);
        new.converted_at := v_now;
        new.mode_needs_review := false;
        new.mode_review_reason := null;
      else
        raise exception 'El modo comercial del trabajo solo puede cambiar mediante la acción auditada correspondiente.'
          using errcode = '23514';
      end if;
    end if;

    if old.workflow_kind = 'quotation'
       and coalesce(old.quotation_status, 'pending') <> 'pending'
       and (
         old.customer_id is distinct from new.customer_id
         or old.service_package_id is distinct from new.service_package_id
         or old.client_request is distinct from new.client_request
         or old.diagnosis is distinct from new.diagnosis
         or old.work_performed is distinct from new.work_performed
         or old.notes is distinct from new.notes
         or old.subject_notes is distinct from new.subject_notes
         or old.estimated_cost is distinct from new.estimated_cost
         or old.parts_cost is distinct from new.parts_cost
         or old.labor_cost is distinct from new.labor_cost
         or old.final_cost is distinct from new.final_cost
         or old.discount_amount is distinct from new.discount_amount
         or old.tax_amount is distinct from new.tax_amount
         or old.total_cost is distinct from new.total_cost
         or old.tax_treatment is distinct from new.tax_treatment
         or old.quotation_valid_until is distinct from new.quotation_valid_until
       ) then
      raise exception 'La cotización decidida es inmutable; reábrela antes de editarla.'
        using errcode = '23514';
    end if;
  end if;

  -- A pending quotation is a non-posting proposal. Treat its persisted lines
  -- as the only total source and discard financial mirrors sent by old/new
  -- clients. This keeps tax ownership in the future invoice/payment panel.
  if new.workflow_kind = 'quotation' then
    if new.invoice_id is not null
       or coalesce(new.is_invoiced, false)
       or coalesce(new.is_paid, false) then
      raise exception 'Una cotización no puede tener factura ni pago. Apruébala y conviértela primero.'
        using errcode = '23514';
    end if;

    new.quotation_status := coalesce(new.quotation_status, 'pending');
    new.requires_approval := true;
    new.is_invoiced := false;
    new.is_paid := false;
    new.approved_by_customer := new.quotation_status = 'approved';
    if new.quotation_status = 'approved' then
      new.approved_at := case
        when tg_op = 'UPDATE' then coalesce(old.approved_at, v_now)
        else v_now
      end;
    else
      new.approved_at := null;
    end if;

    select
      round(coalesce(sum(coalesce(
        item.total_price,
        item.quantity * item.unit_price,
        0
      )) filter (
        where coalesce(item.item_type, 'product') <> 'service'
      ), 0), 2),
      round(coalesce(sum(coalesce(
        item.total_price,
        item.quantity * item.unit_price,
        0
      )) filter (
        where coalesce(item.item_type, 'product') = 'service'
      ), 0), 2)
    into v_parts_cost, v_labor_cost
    from public.mechanic_job_items item
    where item.job_id = new.id
      and item.tenant_id = new.tenant_id;

    v_subtotal := round(v_parts_cost + v_labor_cost, 2);
    v_discount := round(coalesce(new.discount_amount, 0), 2);
    if v_discount < 0 then
      raise exception 'El descuento del presupuesto no puede ser negativo.'
        using errcode = '23514';
    end if;

    new.parts_cost := v_parts_cost;
    new.labor_cost := v_labor_cost;
    new.final_cost := round(v_subtotal - least(v_discount, v_subtotal), 2);
    new.tax_amount := 0;
    new.total_cost := new.final_cost;
    new.tax_treatment := 'no_tax';
  end if;

  return new;
end;
$$;

revoke all on function public.guard_canonical_mechanic_job_mode_transition()
  from public, anon, authenticated, service_role;

-- Old deployed clients still write quotation status directly and convert an
-- already-approved quote in a second action. Keep those writes observable
-- during rollout. The BEFORE guard above blocks unsafe/unapproved/drifted
-- conversion; this AFTER ledger entry is enriched by the snapshot trigger.
create or replace function public.audit_direct_mechanic_job_mode_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_legacy_quotation_conversion boolean :=
    old.workflow_kind = 'quotation' and new.workflow_kind = 'service';
begin
  if current_setting('app.mechanic_job_mode_rpc', true) = 'true' then
    return new;
  end if;

  if old.job_type is distinct from new.job_type
     or old.workflow_kind is distinct from new.workflow_kind
     or old.intake_kind is distinct from new.intake_kind
     or old.quotation_status is distinct from new.quotation_status then
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
      new.tenant_id,
      new.id,
      case
        when v_is_legacy_quotation_conversion then 'converted_to_billable'
        when old.quotation_status is distinct from new.quotation_status
          and old.job_type is not distinct from new.job_type
          and old.workflow_kind is not distinct from new.workflow_kind
          and old.intake_kind is not distinct from new.intake_kind
          then 'quotation_status_changed'
        else 'classified'
      end,
      old.job_type,
      new.job_type,
      old.workflow_kind,
      new.workflow_kind,
      old.intake_kind,
      new.intake_kind,
      old.quotation_status,
      new.quotation_status,
      new.invoice_id,
      case
        when v_is_legacy_quotation_conversion
          then 'Conversión compatible desde un cliente anterior; aprobación y snapshot verificados por el servidor.'
        else 'Cambio registrado por una ruta cliente anterior al comando atómico.'
      end,
      auth.uid(),
      'legacy-direct:' || new.id || ':' || txid_current() || ':' ||
        md5(concat_ws('|', clock_timestamp()::text, random()::text)),
      jsonb_build_object(
        'compatibility_path', true,
        'legacy_bridge', case
          when v_is_legacy_quotation_conversion
            then 'approved-quotation-conversion-v1'
          else 'audited-direct-mode-v1'
        end
      ) || case
        when v_is_legacy_quotation_conversion then jsonb_build_object(
          'invoice_created', false,
          'request', jsonb_build_object(
            'target_job_type', new.job_type,
            'reason', null,
            'create_invoice', false,
            'bike_id', new.bike_id,
            'subject_id', new.subject_id
          )
        )
        else '{}'::jsonb
      end
    );
  end if;
  return new;
end;
$$;

revoke all on function public.audit_direct_mechanic_job_mode_transition()
  from public, anon, authenticated, service_role;

create or replace function public.guard_final_quotation_item_mutation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parent record;
  v_old_is_final boolean := false;
  v_new_is_final boolean := false;
  v_old_is_approved boolean := false;
begin
  if current_setting('app.mechanic_job_mode_rpc', true) = 'true' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- Serialize line changes with approval/reopen/conversion on the parent job.
  -- Without this lock, a concurrent line write could observe the old pending
  -- status and commit after the approval snapshot had already been captured.
  for v_parent in
    select job.id, job.workflow_kind, job.quotation_status
    from public.mechanic_jobs job
    where job.id in (
      case when tg_op = 'INSERT' then new.job_id else old.job_id end,
      case when tg_op = 'DELETE' then old.job_id else new.job_id end
    )
    order by job.id
    for update
  loop
    if tg_op <> 'INSERT' and v_parent.id = old.job_id then
      v_old_is_final := v_parent.workflow_kind = 'quotation'
        and coalesce(v_parent.quotation_status, 'pending') <> 'pending';
      v_old_is_approved := v_parent.workflow_kind = 'quotation'
        and v_parent.quotation_status = 'approved';
    end if;
    if tg_op <> 'DELETE' and v_parent.id = new.job_id then
      v_new_is_final := v_parent.workflow_kind = 'quotation'
        and coalesce(v_parent.quotation_status, 'pending') <> 'pending';
    end if;
  end loop;

  if not v_old_is_final and not v_new_is_final then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- Bicycle attribution is assigned by the existing conversion command before
  -- it flips the job workflow. It does not alter the approved commercial line.
  if tg_op = 'UPDATE'
     and old.job_id is not distinct from new.job_id
     and v_old_is_approved
     and (
       to_jsonb(new) - array['job_bike_id', 'updated_at']::text[]
     ) is not distinct from (
       to_jsonb(old) - array['job_bike_id', 'updated_at']::text[]
     ) then
    return new;
  end if;

  raise exception 'Los ítems de una cotización decidida son inmutables; reábrela antes de editarlos.'
    using errcode = '23514';
end;
$$;

revoke all on function public.guard_final_quotation_item_mutation()
  from public, anon, authenticated, service_role;

-- Keep the operational lock window at the very end of the migration. Every
-- function body above is ready before we request table locks. If any reader or
-- writer is active, NOWAIT aborts this whole transaction instead of queueing
-- behind the shop or making later workers queue behind an ACCESS EXCLUSIVE
-- request. The separate 20260716035000 migration owns the surgical data
-- normalization under a weaker read-friendly writer lock.
set local lock_timeout = '750ms';
set local statement_timeout = '20s';
lock table
  public.mechanic_job_mode_events,
  public.mechanic_jobs,
  public.mechanic_job_items
  in access exclusive mode nowait;

-- The event type is consumed by the evidence-preserving normalization in the
-- immediately following migration.
alter table public.mechanic_job_mode_events
  drop constraint if exists mechanic_job_mode_events_event_type_check;
alter table public.mechanic_job_mode_events
  add constraint mechanic_job_mode_events_event_type_check
  check (event_type in (
    'classified',
    'review_flagged',
    'quotation_status_changed',
    'converted_to_billable',
    'legacy_quote_invoice_detached',
    'quotation_non_posting_normalized'
  ));

drop trigger if exists trg_mechanic_job_mode_event_snapshot
  on public.mechanic_job_mode_events;
create trigger trg_mechanic_job_mode_event_snapshot
  before insert on public.mechanic_job_mode_events
  for each row execute function public.enrich_mechanic_job_mode_event_snapshot();

-- Runs after the compatibility normalizer so a legacy job_type-only
-- cross-workflow update cannot hide the resulting workflow_kind mutation.
drop trigger if exists zzzz_mechanic_jobs_guard_canonical_mode_transition
  on public.mechanic_jobs;
create trigger zzzz_mechanic_jobs_guard_canonical_mode_transition
  before update of
    job_type,
    workflow_kind,
    intake_kind,
    quotation_status,
    invoice_id,
    is_invoiced,
    is_paid,
    requires_approval,
    approved_by_customer,
    approved_at,
    converted_at,
    customer_id,
    service_package_id,
    client_request,
    diagnosis,
    work_performed,
    notes,
    subject_notes,
    estimated_cost,
    parts_cost,
    labor_cost,
    final_cost,
    discount_amount,
    tax_amount,
    total_cost,
    tax_treatment,
    quotation_valid_until
  on public.mechanic_jobs
  for each row execute function public.guard_canonical_mechanic_job_mode_transition();

drop trigger if exists zzzz_mechanic_jobs_guard_canonical_mode_insert
  on public.mechanic_jobs;
create trigger zzzz_mechanic_jobs_guard_canonical_mode_insert
  before insert on public.mechanic_jobs
  for each row execute function public.guard_canonical_mechanic_job_mode_transition();

drop trigger if exists trg_mechanic_job_items_guard_approved_quotation
  on public.mechanic_job_items;
drop trigger if exists trg_mechanic_job_items_guard_final_quotation
  on public.mechanic_job_items;
create trigger trg_mechanic_job_items_guard_final_quotation
  before insert or update or delete on public.mechanic_job_items
  for each row execute function public.guard_final_quotation_item_mutation();

drop function if exists public.guard_approved_quotation_item_mutation();

comment on trigger trg_mechanic_job_mode_event_snapshot
  on public.mechanic_job_mode_events is
  'Captures the exact approved commercial snapshot and verifies it again during conversion.';
comment on trigger zzzz_mechanic_jobs_guard_canonical_mode_transition
  on public.mechanic_jobs is
  'Prevents direct cross-workflow/status bypasses and commercial edits to approved quotations.';
comment on trigger zzzz_mechanic_jobs_guard_canonical_mode_insert
  on public.mechanic_jobs is
  'Ensures every new quotation starts pending before any audited customer decision.';
comment on trigger trg_mechanic_job_items_guard_final_quotation
  on public.mechanic_job_items is
  'Serializes quotation line writes with decisions and prevents final-quotation drift while allowing conversion-only bicycle attribution.';

commit;
