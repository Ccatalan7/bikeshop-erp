-- Deployment status: PENDING.
--
-- Purpose:
--   Give the existing one-table workshop UI an audited, tenant-safe command
--   for resolving conservative legacy rows marked mode_needs_review. This
--   command classifies only the physical intake (complete bicycle or loose
--   component); it never creates or changes invoices, payments, stock or
--   accounting entries.
--
-- Recovery:
--   The function is additive. An older client simply does not call it. If the
--   new client is rolled back, completed classifications and their immutable
--   events remain valid business evidence and must not be reversed blindly.

begin;

create or replace function public.classify_mechanic_job_intake(
  p_job_id uuid,
  p_intake_kind text,
  p_bike_id uuid default null,
  p_subject_id uuid default null,
  p_subject_notes text default null,
  p_reason text default null,
  p_operation_key uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_updated public.mechanic_jobs%rowtype;
  v_event public.mechanic_job_mode_events%rowtype;
  v_bike public.bikes%rowtype;
  v_subject public.job_subjects%rowtype;
  v_job_bike_id uuid;
  v_intake_kind text := lower(btrim(coalesce(p_intake_kind, '')));
  v_subject_notes text := nullif(btrim(coalesce(p_subject_notes, '')), '');
  v_reason text := coalesce(
    nullif(btrim(coalesce(p_reason, '')), ''),
    'Clasificación manual de recepción confirmada por un trabajador.'
  );
  v_operation_key text := coalesce(p_operation_key, gen_random_uuid())::text;
  v_request jsonb := jsonb_build_object(
    'intake_kind', lower(btrim(coalesce(p_intake_kind, ''))),
    'bike_id', p_bike_id,
    'subject_id', p_subject_id,
    'subject_notes', nullif(btrim(coalesce(p_subject_notes, '')), ''),
    'reason', nullif(btrim(coalesce(p_reason, '')), '')
  );
begin
  if v_intake_kind not in ('bike', 'component') then
    raise exception 'La recepción debe clasificarse como bicicleta completa o componente suelto.'
      using errcode = '23514';
  end if;

  select * into v_job
  from public.mechanic_jobs
  where id = p_job_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'Trabajo no encontrado.';
  end if;
  perform public.assert_workshop_rpc_tenant(v_job.tenant_id);

  select * into v_event
  from public.mechanic_job_mode_events event
  where event.tenant_id = v_job.tenant_id
    and event.operation_key = v_operation_key;

  if found then
    if v_event.job_id <> v_job.id
       or v_event.event_type <> 'classified'
       or v_event.metadata->'request' is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otra clasificación de trabajo.'
        using errcode = '23505';
    end if;

    return jsonb_build_object(
      'job_id', v_event.job_id,
      'job_type', v_event.to_job_type,
      'workflow_kind', v_event.to_workflow_kind,
      'intake_kind', v_event.to_intake_kind,
      'event_id', v_event.id,
      'replayed', true
    );
  end if;

  if v_job.workflow_kind not in ('service', 'warranty') then
    raise exception 'Los presupuestos se clasifican al convertirlos, no mediante esta revisión.'
      using errcode = '23514';
  end if;

  if not v_job.mode_needs_review then
    raise exception 'Este trabajo ya tiene una recepción clasificada.'
      using errcode = '23514';
  end if;

  if v_intake_kind = 'bike' then
    if p_bike_id is null then
      raise exception 'Selecciona la bicicleta completa que quedó en el taller.'
        using errcode = '23514';
    end if;
    if p_subject_id is not null then
      raise exception 'Una recepción de bicicleta completa no acepta un componente suelto como objeto principal.'
        using errcode = '23514';
    end if;

    select * into v_bike
    from public.bikes bike
    where bike.id = p_bike_id
      and bike.tenant_id = v_job.tenant_id
      and bike.customer_id = v_job.customer_id
      and bike.is_active;

    if v_bike.id is null then
      raise exception 'La bicicleta debe estar activa y pertenecer al cliente y negocio del trabajo.'
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

    update public.mechanic_job_items item
    set job_bike_id = v_job_bike_id,
        updated_at = clock_timestamp()
    where item.tenant_id = v_job.tenant_id
      and item.job_id = v_job.id
      and item.job_bike_id is null;
  else
    if p_bike_id is not null then
      raise exception 'Un componente suelto no recibe la bicicleta completa.'
        using errcode = '23514';
    end if;

    if v_job.bike_id is not null
       or exists (
         select 1
         from public.mechanic_job_bikes job_bike
         where job_bike.tenant_id = v_job.tenant_id
           and job_bike.job_id = v_job.id
       ) then
      raise exception 'El trabajo ya tiene una bicicleta asociada; revísala antes de clasificarlo como componente suelto.'
        using errcode = '23514';
    end if;

    if p_subject_id is not null then
      select * into v_subject
      from public.job_subjects subject
      where subject.id = p_subject_id
        and subject.tenant_id = v_job.tenant_id
        and subject.is_active;

      if v_subject.id is null then
        raise exception 'El componente debe estar activo y pertenecer al negocio del trabajo.'
          using errcode = '23514';
      end if;
    end if;

    v_subject_notes := coalesce(v_subject_notes, v_job.subject_notes);
    if v_subject.id is null
       and nullif(btrim(coalesce(v_subject_notes, '')), '') is null then
      raise exception 'Selecciona o describe el componente que quedó en el taller.'
        using errcode = '23514';
    end if;
  end if;

  perform set_config('app.mechanic_job_mode_rpc', 'true', true);
  update public.mechanic_jobs
  set intake_kind = v_intake_kind,
      bike_id = case when v_intake_kind = 'bike' then v_bike.id else null end,
      subject_id = case
        when v_intake_kind = 'component' then v_subject.id
        else null
      end,
      subject_notes = case
        when v_intake_kind = 'component' then v_subject_notes
        else subject_notes
      end,
      mode_needs_review = false,
      mode_review_reason = null,
      updated_at = clock_timestamp()
  where id = v_job.id
    and tenant_id = v_job.tenant_id
  returning * into v_updated;

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
    v_updated.tenant_id,
    v_updated.id,
    'classified',
    v_job.job_type,
    v_updated.job_type,
    v_job.workflow_kind,
    v_updated.workflow_kind,
    v_job.intake_kind,
    v_updated.intake_kind,
    v_job.quotation_status,
    v_updated.quotation_status,
    v_updated.invoice_id,
    v_reason,
    auth.uid(),
    v_operation_key,
    jsonb_build_object(
      'request', v_request,
      'classification_source', 'manual-review-v1',
      'previous_review_reason', v_job.mode_review_reason,
      'bike_id', v_updated.bike_id,
      'subject_id', v_updated.subject_id,
      'financial_effects_created', false
    )
  ) returning * into v_event;
  perform set_config('app.mechanic_job_mode_rpc', '', true);

  return jsonb_build_object(
    'job_id', v_updated.id,
    'job_type', v_updated.job_type,
    'workflow_kind', v_updated.workflow_kind,
    'intake_kind', v_updated.intake_kind,
    'event_id', v_event.id,
    'replayed', false
  );
exception
  when others then
    perform set_config('app.mechanic_job_mode_rpc', '', true);
    raise;
end;
$$;

revoke all on function public.classify_mechanic_job_intake(
  uuid, text, uuid, uuid, text, text, uuid
) from public, anon, authenticated, service_role;
grant execute on function public.classify_mechanic_job_intake(
  uuid, text, uuid, uuid, text, text, uuid
) to authenticated;

comment on function public.classify_mechanic_job_intake(
  uuid, text, uuid, uuid, text, text, uuid
) is
  'Audited idempotent command that resolves a flagged workshop intake as an active tenant-owned bicycle or loose component without financial posting.';

notify pgrst, 'reload schema';

commit;
