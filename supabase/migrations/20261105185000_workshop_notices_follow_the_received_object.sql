-- Los avisos del taller siguen a lo que el taller recibió, no al modo
-- comercial del trabajo (2026-11-05).
--
-- 20261105130000 avisaba sólo los trabajos `workflow_kind = service` para no
-- avisar una cotización suelta. Pero en Viñabike casi todo trabajo nace con
-- «Presupuestar primero» (`quotation` con la bici recibida) y sigue así hasta
-- que se factura. En los 60 días anteriores, medidos con el modo que tenía el
-- trabajo en cada momento: 64 de 71 recepciones, 17 de 18 «Esperando
-- aprobación», 55 de 87 «Terminado» y 31 de 108 «Entregado» ocurrieron con el
-- trabajo en `quotation`. Con ese filtro, la mayoría de los avisos no salía.
-- Lo destapó la prueba de punta a punta con el cliente «Test»: el trabajo
-- creado desde «Nuevo trabajo» nació `quotation`.
--
-- Una cotización suelta se distingue porque no hay nada en el taller
-- (`intake_kind = unspecified`), y una venta tampoco recibe nada (`none`).
-- Ahora avisa todo trabajo con una bici o un componente recibido, en cualquier
-- modo salvo la venta. Y un presupuesto que el cliente ya aprobó o rechazó, o
-- que venció, no se anuncia como listo aunque el estado siga en «Esperando
-- aprobación».
--
-- Los cambios ocurridos desde que se encendieron los avisos y que este filtro
-- dejó fuera se anotan en la próxima pasada, si todavía están dentro de su
-- plazo (6 horas la recepción, 24 los demás) y el trabajo sigue en ese paso.

begin;

create or replace function public.workshop_notice_stale_reason_internal(
  p_kind text,
  p_job public.mechanic_jobs
)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_status text := upper(btrim(coalesce(p_job.status, '')));
  v_completion boolean := false;
  v_delivery boolean := false;
begin
  if p_job.id is null or p_job.deleted_at is not null then
    return 'job_deleted';
  end if;
  select coalesce(status.triggers_completion, false), coalesce(status.triggers_delivery, false)
    into v_completion, v_delivery
    from public.job_statuses status
   where status.id = p_job.status_id
     and status.tenant_id = p_job.tenant_id;
  v_completion := coalesce(v_completion, false) or v_status in ('FINALIZADO', 'PROBADO');
  v_delivery := coalesce(v_delivery, false) or v_status = 'ENTREGADO';

  if p_kind = 'received' then
    if v_delivery or v_status in ('CANCELADO', 'RETIRO_SIN_SERVICIO') then
      return 'job_moved_on';
    end if;
  elsif p_kind = 'quote_ready' then
    -- Un trabajo en `quotation` decide su presupuesto en `quotation_status`;
    -- `approved_by_customer` se marca recién al pasar a `service`.
    if v_status <> 'ESPERANDO_APROBACION'
       or p_job.approved_by_customer is true
       or coalesce(p_job.quotation_status, '') in ('approved', 'rejected', 'expired') then
      return 'job_moved_on';
    end if;
  elsif p_kind = 'ready' then
    if v_delivery or v_status in ('CANCELADO', 'RETIRO_SIN_SERVICIO') then
      return 'already_delivered';
    end if;
    if not v_completion then
      return 'job_moved_on';
    end if;
  elsif p_kind = 'delivered' then
    if not v_delivery then
      return 'job_moved_on';
    end if;
  end if;
  return null;
end;
$$;

revoke all on function public.workshop_notice_stale_reason_internal(text, public.mechanic_jobs)
  from public, anon, authenticated, service_role;

create or replace function public.workshop_notice_enqueue_internal(
  p_tenant_id uuid,
  p_job_id uuid,
  p_kind text,
  p_source_id uuid,
  p_source_at timestamptz,
  p_actor uuid,
  p_email boolean,
  p_whatsapp boolean
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_preference public.customer_workshop_notice_preferences%rowtype;
  v_email text;
  v_phone text;
  v_count integer := 0;
  v_channel text;
  v_recipient text;
  v_reason text;
  v_inserted integer;
begin
  select * into v_job
    from public.mechanic_jobs job
   where job.id = p_job_id and job.tenant_id = p_tenant_id;
  -- Avisa lo que el taller recibió: una bici o un componente, en cualquier
  -- modo. Casi todo trabajo vive en `quotation` hasta facturarse; una
  -- cotización suelta (`unspecified`) y una venta (`none`) no reciben nada.
  if not found
     or v_job.intake_kind not in ('bike', 'component')
     or v_job.workflow_kind = 'sale' then
    return 0;
  end if;
  select * into v_customer
    from public.customers customer
   where customer.id = v_job.customer_id
     and customer.tenant_id = p_tenant_id;
  if found then
    v_email := lower(btrim(v_customer.email));
    if v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      v_email := null;
    end if;
    v_phone := public.normalize_whatsapp_phone(v_customer.phone);
    if v_phone !~ '^569[0-9]{8}$' then
      v_phone := null;
    end if;
    select * into v_preference
      from public.customer_workshop_notice_preferences preference
     where preference.tenant_id = p_tenant_id
       and preference.customer_id = v_customer.id;
  end if;

  foreach v_channel in array array_remove(array[
    case when p_email then 'email' end,
    case when p_whatsapp then 'whatsapp' end
  ], null)
  loop
    v_recipient := case v_channel when 'email' then v_email else v_phone end;
    v_reason := case
      when v_customer.id is null or v_customer.is_active is not true then 'no_customer'
      when v_recipient is null then case v_channel when 'email' then 'no_email' else 'no_mobile' end
      when v_channel = 'email' and v_preference.email_enabled is false then 'customer_opted_out'
      when v_channel = 'whatsapp' and v_preference.whatsapp_enabled is false then 'customer_opted_out'
    end;
    insert into public.workshop_customer_notices (
      tenant_id, job_id, customer_id, kind, channel, source_id, source_at, actor_id,
      recipient, state, reason, available_at, expires_at
    ) values (
      p_tenant_id, p_job_id, v_customer.id, p_kind, v_channel, p_source_id, p_source_at, p_actor,
      v_recipient,
      case when v_reason is null then 'pending' else 'skipped' end,
      v_reason,
      p_source_at + public.workshop_notice_delay_internal(p_kind),
      p_source_at + public.workshop_notice_lifetime_internal(p_kind)
    )
    on conflict on constraint workshop_customer_notices_once do nothing;
    get diagnostics v_inserted = row_count;
    v_count := v_count + v_inserted;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.workshop_notice_enqueue_internal(uuid, uuid, text, uuid, timestamptz, uuid, boolean, boolean)
  from public, anon, authenticated, service_role;

commit;
