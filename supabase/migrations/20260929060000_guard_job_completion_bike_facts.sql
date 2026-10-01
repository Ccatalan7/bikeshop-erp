-- A marked installed part and the finished job must agree with the bike ficha.
-- Fail the whole transition atomically on an actionable mismatch. Historical
-- notices and undecided compatibility remain visible in the success receipt.
-- The command outbox retains the key for transient patch failures.

CREATE OR REPLACE FUNCTION public.transition_mechanic_job_status(p_job_id uuid, p_status_id uuid, p_operation_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '750ms'
AS $function$
declare
  v_preflight_tenant_id uuid;
  v_preflight_invoice_id uuid;
  v_job public.mechanic_jobs%rowtype;
  v_updated_job public.mechanic_jobs%rowtype;
  v_status public.job_statuses%rowtype;
  v_invoice public.sales_invoices%rowtype;
  v_event public.mechanic_job_status_transition_events%rowtype;
  v_operation_key text := btrim(coalesce(p_operation_key, ''));
  v_target_legacy_status text;
  v_request jsonb;
  v_response jsonb;
  v_changed boolean;
  v_now timestamptz;
  v_is_start boolean;
  v_is_complete boolean;
  v_is_delivered boolean;
  v_has_payment_evidence boolean := false;
  v_installed jsonb;
  v_blocking jsonb;
  v_first_problem jsonb;
  v_transient_problem boolean;
begin
  if p_job_id is null or p_status_id is null then
    raise exception 'El trabajo y el estado son obligatorios.'
      using errcode = '22004';
  end if;
  if v_operation_key = '' then
    raise exception 'El cambio de estado requiere una clave de operación.'
      using errcode = '22023';
  end if;

  v_request := jsonb_build_object(
    'job_id', p_job_id,
    'status_id', p_status_id
  );

  -- Authorize from current job ownership before reading a receipt. A replay
  -- remains available after soft deletion because its committed result is
  -- immutable evidence, but a new command below rejects deleted work.
  select job.tenant_id, job.invoice_id
    into v_preflight_tenant_id, v_preflight_invoice_id
  from public.mechanic_jobs job
  where job.id = p_job_id;
  if not found then
    raise exception 'Trabajo no encontrado.' using errcode = 'P0002';
  end if;
  perform public.assert_workshop_rpc_tenant(v_preflight_tenant_id);

  select event.* into v_event
  from public.mechanic_job_status_transition_events event
  where event.tenant_id = v_preflight_tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.job_id is distinct from p_job_id
       or v_event.to_status_id is distinct from p_status_id
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otro cambio de estado.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  -- Payment posting locks invoice before job. Follow that global order, then
  -- revalidate the preflight relationship so a concurrent link/unlink cannot
  -- redirect this transition to an invoice that was never serialized here.
  if v_preflight_invoice_id is not null then
    select invoice.* into v_invoice
    from public.sales_invoices invoice
    where invoice.id = v_preflight_invoice_id
      and invoice.tenant_id = v_preflight_tenant_id
    for update;
    if not found then
      raise exception 'La factura vinculada al trabajo no existe.'
        using errcode = '55000';
    end if;
  end if;

  select job.* into v_job
  from public.mechanic_jobs job
  where job.id = p_job_id
    and job.tenant_id = v_preflight_tenant_id
    and job.deleted_at is null
  for update;
  if not found then
    raise exception 'Trabajo no encontrado o eliminado.' using errcode = 'P0002';
  end if;
  if v_job.invoice_id is distinct from v_preflight_invoice_id then
    -- PT409 y no 40001: PostgREST 14 reintenta un 40001 sin fin y el
    -- cliente recibe un 504 (20260928052000).
    raise exception 'El vínculo financiero del trabajo cambió durante la transición; vuelve a intentarlo.'
      using errcode = 'PT409';
  end if;

  -- Another request with the same key may have committed while this call was
  -- waiting for the job. Re-read the exact receipt under the serialized lock.
  select event.* into v_event
  from public.mechanic_job_status_transition_events event
  where event.tenant_id = v_job.tenant_id
    and event.operation_key = v_operation_key;
  if found then
    if v_event.job_id is distinct from p_job_id
       or v_event.to_status_id is distinct from p_status_id
       or v_event.request_snapshot is distinct from v_request then
      raise exception 'La clave de operación ya pertenece a otro cambio de estado.'
        using errcode = '23505';
    end if;
    return to_jsonb(v_event)
      || v_event.response_snapshot
      || jsonb_build_object('replay', true);
  end if;

  select status.* into v_status
  from public.job_statuses status
  where status.id = p_status_id
    and status.tenant_id = v_job.tenant_id
    and status.is_active
  for share;
  if not found then
    raise exception 'El estado no existe, está inactivo o pertenece a otro negocio.'
      using errcode = '23514';
  end if;

  v_target_legacy_status := upper(btrim(v_status.code));
  if v_target_legacy_status = '' then
    raise exception 'El estado seleccionado no tiene un código operativo válido.'
      using errcode = '23514';
  end if;

  v_changed := v_job.status_id is distinct from v_status.id
    or v_job.status is distinct from v_target_legacy_status;

  -- An exact same-state command is a durable no-op receipt. It deliberately
  -- does not include status/status_id in an UPDATE, so no lifecycle,
  -- inventory or accounting trigger can run.
  if not v_changed then
    v_updated_job := v_job;
  else
    -- Covered warranty status changes can post or reverse their internal
    -- invoice. Fail closed on any settlement evidence while holding the
    -- invoice lock; no trigger is allowed to run before this guard succeeds.
    if (v_job.workflow_kind = 'warranty' or v_job.job_type = 'warranty')
       and v_job.warranty_outcome = 'covered' then
      if v_job.invoice_id is null or v_invoice.id is null then
        raise exception 'La garantía cubierta no tiene un respaldo financiero verificable; no se cambió su estado.'
          using errcode = '55000';
      end if;

      select
        lower(coalesce(v_invoice.status, '')) in ('paid', 'pagado', 'pagada')
        or coalesce(v_invoice.paid_amount, 0) > 0
        or exists (
          select 1
          from public.sales_payments payment
          where payment.tenant_id = v_job.tenant_id
            and payment.invoice_id = v_job.invoice_id
            and payment.deleted_at is null
            and coalesce(payment.amount, 0) > 0
        )
      into v_has_payment_evidence;

      if v_has_payment_evidence then
        raise exception 'La garantía cubierta tiene evidencia de pago. Corrige primero la factura desde el flujo financiero auditado.'
          using errcode = '55000';
      end if;
    end if;

    v_now := clock_timestamp();
    v_is_start := coalesce(v_status.triggers_start, false)
      or v_target_legacy_status = 'EN_CURSO';
    v_is_complete := coalesce(v_status.triggers_completion, false)
      or coalesce(v_status.triggers_delivery, false)
      or v_target_legacy_status in ('FINALIZADO', 'ENTREGADO');
    v_is_delivered := coalesce(v_status.triggers_delivery, false)
      or v_target_legacy_status = 'ENTREGADO';

    perform set_config('app.mechanic_job_status_rpc', 'true', true);
    update public.mechanic_jobs job
    set status_id = v_status.id,
        status = v_target_legacy_status,
        started_at = case
          when v_is_start then coalesce(job.started_at, v_now)
          else job.started_at
        end,
        completed_at = case
          when v_is_complete then coalesce(job.completed_at, v_now)
          else job.completed_at
        end,
        delivered_at = case
          when v_is_delivered then coalesce(job.delivered_at, v_now)
          else null
        end,
        updated_at = v_now
    where job.id = v_job.id
      and job.tenant_id = v_job.tenant_id
    returning job.* into v_updated_job;
    perform set_config('app.mechanic_job_status_rpc', '', true);
  end if;

  -- La línea y la ficha quedan en la misma transacción. Si una pieza marcada
  -- no calza o no tiene destino inequívoco, se deshacen el estado, las
  -- aplicaciones parciales, los eventos y el recibo; el trabajador corrige la
  -- línea y vuelve a cerrar. Un aviso histórico o un calce todavía pendiente
  -- se devuelve como aviso, sin presentarlo como un hecho confirmado.
  if v_updated_job.status in ('FINALIZADO', 'ENTREGADO') then
    v_installed := public.apply_job_installed_bike_facts_internal(
      v_updated_job.tenant_id,
      v_updated_job.id
    );

    select coalesce(jsonb_agg(problem order by ord), '[]'::jsonb)
      into v_blocking
      from jsonb_array_elements(coalesce(v_installed->'problems', '[]'::jsonb))
           with ordinality as problems(problem, ord)
     where problem->>'reason' in (
       'rejected', 'out_of_range', 'no_wheel', 'invalid_value',
       'line_without_bike', 'incompatible', 'stale_change', 'mixed_change',
       'conflicting_build'
     );
    if jsonb_array_length(v_blocking) > 0 then
      -- Un error de transporte, recursos o bloqueo no pide corregir una
      -- pieza. Conserva la llave del outbox para reintentar el mismo comando.
      -- Nunca se reexpone 40001: PostgREST 14 lo reintenta hasta agotar 504.
      select problem,
             problem->>'reason' = 'rejected'
               and (left(coalesce(problem->>'code', ''), 2) in ('08', '53', '57')
                    or problem->>'code' in ('40P01', '55P03', '40001'))
        into v_first_problem, v_transient_problem
        from jsonb_array_elements(v_blocking) with ordinality as problems(problem, ord)
       order by case
                  when problem->>'reason' <> 'rejected' then 0
                  when left(coalesce(problem->>'code', ''), 2) in ('08', '53', '57')
                    or problem->>'code' in ('40P01', '55P03', '40001') then 2
                  else 1
                end,
                ord
       limit 1;
      if v_transient_problem then
        raise exception 'La ficha de la bici no respondió al cierre; el cambio sigue pendiente y se reintentará.'
          using errcode = '55P03', hint = 'job_completion_retry';
      end if;
      raise exception 'No se cerró el trabajo: «%» necesita corrección en la ficha o en su línea.',
          coalesce(nullif(btrim(v_first_problem->>'item_name'), ''), 'Una línea')
        using errcode = '23514',
              hint = 'job_completion_blocked',
              detail = jsonb_build_object('problems', v_blocking)::text;
    end if;
  end if;

  v_response := jsonb_build_object(
    'job_id', v_updated_job.id,
    'status_id', v_updated_job.status_id,
    'status', v_updated_job.status,
    'changed', v_changed,
    'status_updated_at', v_updated_job.status_updated_at,
    'job', to_jsonb(v_updated_job),
    'installed_bike_facts', v_installed
  );

  insert into public.mechanic_job_status_transition_events (
    tenant_id,
    job_id,
    from_status_id,
    to_status_id,
    from_legacy_status,
    to_legacy_status,
    changed,
    actor_id,
    operation_key,
    request_snapshot,
    response_snapshot,
    occurred_at
  ) values (
    v_job.tenant_id,
    v_job.id,
    v_job.status_id,
    v_status.id,
    v_job.status,
    v_target_legacy_status,
    v_changed,
    auth.uid(),
    v_operation_key,
    v_request,
    v_response,
    clock_timestamp()
  ) returning * into v_event;

  perform set_config('app.mechanic_job_status_rpc', '', true);
  return to_jsonb(v_event)
    || v_response
    || jsonb_build_object('replay', false);
exception
  when others then
    perform set_config('app.mechanic_job_status_rpc', '', true);
    raise;
end;
$function$;

comment on function public.transition_mechanic_job_status(uuid, uuid, text) is
  'Cambia estado con recibo idempotente. Al finalizar o entregar, bloquea un cambio instalado incompatible o sin bici/rueda inequívoca; estado, ficha e historial quedan atómicos. Los avisos históricos y calces pendientes vuelven en el recibo.';
