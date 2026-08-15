-- Deployment status: NOT DEPLOYED.
--
-- A decided service budget already owns its complete received-bike graph.
-- Conversion must preserve that graph and every line attribution byte for
-- byte, including intentional General lines whose job_bike_id is NULL.
-- Standalone quotations still attach their unscoped lines to the bicycle
-- selected at conversion time, but only inside the audited RPC scope.
--
-- This migration changes functions and ACLs only. There is deliberately no
-- business-data backfill: historical NULL job_bike_id rows are ambiguous and
-- remain valid job-wide work unless a human classifies them in context.

begin;

set local lock_timeout = '750ms';
set local statement_timeout = '30s';

do $$
begin
  if to_regprocedure(
    'public.convert_mechanic_job_to_billable_service_internal(uuid,text,text,boolean,uuid,uuid,uuid)'
  ) is null then
    raise exception 'Missing private bicycle/component quotation conversion delegate.';
  end if;
end;
$$;

create or replace function public.convert_mechanic_job_to_billable_service_internal(
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
  v_is_service_budget boolean := false;
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

  v_is_service_budget := v_job.intake_kind = 'bike';

  if v_target_job_type = 'service' then
    if p_subject_id is not null then
      raise exception 'Un servicio de bicicleta no acepta un componente suelto como objeto principal.'
        using errcode = '23514';
    end if;

    if v_is_service_budget then
      -- A service budget is already a received-bike aggregate. Validate the
      -- complete frozen graph, then choose its persisted primary bicycle
      -- without inserting/upserting a relationship or changing any line.
      if not exists (
        select 1
        from public.mechanic_job_bikes job_bike
        where job_bike.tenant_id = v_job.tenant_id
          and job_bike.job_id = v_job.id
      ) then
        raise exception 'El presupuesto de servicio no conserva ninguna bicicleta recibida; reábrelo y corrige la ficha antes de convertirlo.'
          using errcode = '23514';
      end if;

      if exists (
        select 1
        from public.mechanic_job_bikes job_bike
        left join public.bikes bike
          on bike.id = job_bike.bike_id
         and bike.tenant_id = job_bike.tenant_id
        where job_bike.job_id = v_job.id
          and (
            job_bike.tenant_id is distinct from v_job.tenant_id
            or bike.id is null
            or bike.customer_id is distinct from v_job.customer_id
            or not coalesce(bike.is_active, false)
          )
      ) then
        raise exception 'Las bicicletas recibidas deben estar activas y pertenecer al cliente y negocio del presupuesto.'
          using errcode = '23514';
      end if;

      if exists (
        select 1
        from public.mechanic_job_items item
        left join public.mechanic_job_bikes job_bike
          on job_bike.id = item.job_bike_id
         and job_bike.job_id = item.job_id
         and job_bike.tenant_id = item.tenant_id
        where item.tenant_id = v_job.tenant_id
          and item.job_id = v_job.id
          and item.job_bike_id is not null
          and job_bike.id is null
      ) then
        raise exception 'La atribución de bicicletas del presupuesto es inconsistente; reábrelo y corrige sus líneas antes de convertirlo.'
          using errcode = '23514';
      end if;

      if p_bike_id is not null then
        select bike.* into v_bike
        from public.mechanic_job_bikes job_bike
        join public.bikes bike
          on bike.id = job_bike.bike_id
         and bike.tenant_id = job_bike.tenant_id
        where job_bike.tenant_id = v_job.tenant_id
          and job_bike.job_id = v_job.id
          and job_bike.bike_id = p_bike_id
          and bike.customer_id = v_job.customer_id
          and bike.is_active;
      elsif v_job.bike_id is not null then
        select bike.* into v_bike
        from public.mechanic_job_bikes job_bike
        join public.bikes bike
          on bike.id = job_bike.bike_id
         and bike.tenant_id = job_bike.tenant_id
        where job_bike.tenant_id = v_job.tenant_id
          and job_bike.job_id = v_job.id
          and job_bike.bike_id = v_job.bike_id
          and bike.customer_id = v_job.customer_id
          and bike.is_active;
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
        raise exception 'La bicicleta principal debe pertenecer a la ficha recibida del presupuesto.'
          using errcode = '23514';
      end if;
    else
      -- A standalone quotation has no received-bike aggregate yet. It may
      -- resolve one active customer bicycle at conversion time.
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
    end if;
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

  -- Every conversion mutation is now inside the audited scope. This is
  -- required for standalone quotation attribution and lets the item guard
  -- reject the same direct client write after approval.
  perform set_config('app.mechanic_job_mode_rpc', 'true', true);

  if v_target_job_type = 'service' and not v_is_service_budget then
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
  end if;

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

comment on function public.convert_mechanic_job_to_billable_service_internal(
  uuid, text, text, boolean, uuid, uuid, uuid
) is
  'Private approved-quotation conversion delegate. Service budgets preserve every received-bike link and line attribution, including NULL General scope; standalone quotations may attribute unscoped lines inside the audited command.';

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
    end if;
    if tg_op <> 'DELETE' and v_parent.id = new.job_id then
      v_new_is_final := v_parent.workflow_kind = 'quotation'
        and coalesce(v_parent.quotation_status, 'pending') <> 'pending';
    end if;
  end loop;

  if not v_old_is_final and not v_new_is_final then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  raise exception 'Los ítems de una cotización decidida son inmutables; reábrela antes de editarlos.'
    using errcode = '23514';
end;
$$;

revoke all on function public.guard_final_quotation_item_mutation()
  from public, anon, authenticated, service_role;

comment on function public.guard_final_quotation_item_mutation() is
  'Freezes every decided-quotation line field, including job_bike_id. Only the audited mechanic-job mode RPC scope may mutate conversion attribution.';

commit;
