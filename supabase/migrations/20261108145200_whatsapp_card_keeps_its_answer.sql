-- Una tarjeta de presupuesto enviada por la bandeja de salida de WhatsApp
-- quedaba con `metadata.status = 'accepted'` apenas Meta aceptaba el envío.
-- En una tarjeta (`action_request`) ese campo es la respuesta del cliente
-- (pending -> accepted/declined): lo leen `apply_whatsapp_job_action`,
-- `respond_to_action_request` y la tarjeta del chat del ERP. La bandeja
-- escribía ahí su propio estado de envío, que ya guarda en `whatsapp_status`.
--
-- Resultado, el 2026-11-08 con PG-00672 (la primera tarjeta que salió por la
-- bandeja): el toque de «Aprobar presupuesto» llegó, la base lo rechazó con
-- «already has a terminal response» y el chat del ERP mostraba la tarjeta
-- como aprobada sin que nadie la aprobara.
--
-- Desde aquí, cuando Meta acepta el envío de una tarjeta, su `status` sigue
-- siendo la respuesta: `pending` mientras el cliente no responda
-- (`responded_at`). Los demás mensajes y los envíos fallidos o inciertos se
-- completan igual que antes.

do $$
begin
  -- El cuerpo que se reemplaza es el de 20260903220000, sin cambios desde
  -- entonces. Si alguien lo cambió, se revisa antes de pisarlo.
  if (select md5(p.prosrc)
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = 'finish_whatsapp_outbox_v1')
     is distinct from '0b5c4a3f3a6ec19fbc6d7103ef663f37' then
    raise exception 'finish_whatsapp_outbox_v1 cambió desde 20260903220000; revisarla antes de reemplazarla';
  end if;
end $$;

create or replace function public.finish_whatsapp_outbox_v1(
  p_message_id uuid, p_token text, p_status text, p_patch jsonb default '{}'::jsonb
)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_job public.whatsapp_outbox%rowtype;
  v_status text := p_status;
  v_external_id text := nullif(p_patch->>'external_message_id', '');
  v_metadata jsonb := coalesce(p_patch->'metadata', '{}'::jsonb);
begin
  if v_status not in ('accepted', 'failed', 'outcome_unknown', 'retry') then
    raise exception 'Invalid outbox completion' using errcode = '22023';
  end if;
  select * into v_job from public.whatsapp_outbox
  where message_id = p_message_id
    and token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') for update;
  if not found or v_job.state not in ('processing', 'sending', 'outcome_unknown') then return false; end if;
  if v_job.state = 'outcome_unknown' and v_status <> 'accepted' then return false; end if;
  if v_status = 'accepted' and (v_external_id is null or v_job.state = 'processing') then
    raise exception 'Provider acceptance requires a fenced send and provider id' using errcode = '22023';
  end if;
  if v_status = 'retry' then
    v_status := case when v_job.attempts < 3 then 'queued' else 'failed' end;
  end if;
  update public.whatsapp_outbox set state = v_status, updated_at = now(),
    available_at = now() + make_interval(secs => 30 * greatest(v_job.attempts, 1)),
    lease_until = null,
    token_hash = case when v_status = 'queued' then null else token_hash end,
    last_error = p_patch->>'error'
  where message_id = p_message_id;
  update public.messages m set
    content = coalesce(p_patch->>'content', m.content),
    type = coalesce(nullif(p_patch->>'type', 'audio'), m.type),
    external_message_id = coalesce(v_external_id, m.external_message_id),
    external_status = case
      when m.external_status in ('sent', 'delivered', 'read') then m.external_status
      when v_status = 'outcome_unknown' then null else v_status end,
    metadata = m.metadata || v_metadata || jsonb_build_object(
      'status', v_status, 'whatsapp_status', v_status, 'pending', false,
      'outcome_unknown', v_status = 'outcome_unknown',
      'retry_disabled', v_status = 'outcome_unknown', 'server_ack_durable', true)
      -- En una tarjeta, `status` es la respuesta del cliente, no el envío.
      || case
        when v_status = 'accepted'
         and coalesce(nullif(p_patch->>'type', 'audio'), m.type) = 'action_request'
        then jsonb_build_object('status', case
          when m.metadata ? 'responded_at' then coalesce(m.metadata->>'status', 'pending')
          else 'pending'
        end)
        else '{}'::jsonb
      end
  where m.id = p_message_id;
  if v_status = 'failed' then
    update public.messaging_attachments set status = 'failed', failed_at = now(),
      failure_code = coalesce(p_patch->>'error', 'whatsapp_send_failed'), updated_at = now()
    where message_id = p_message_id and status = 'attached';
  end if;
  return true;
end;
$$;

revoke all on function public.finish_whatsapp_outbox_v1(uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.finish_whatsapp_outbox_v1(uuid, text, text, jsonb) to service_role;

-- La tarjeta que alcanzó a quedar pisada vuelve a esperar la respuesta del
-- cliente. Una respuesta real siempre deja `responded_at`, así que una tarjeta
-- «accepted» sin esa marca sólo pudo escribirla la bandeja. Al 2026-11-08 es
-- una sola: la de PG-00672.
update public.messages m
set metadata = m.metadata || jsonb_build_object('status', 'pending')
where m.type = 'action_request'
  and m.message_direction = 'outbound'
  and m.external_provider = 'whatsapp'
  and m.metadata->>'status' = 'accepted'
  and not (m.metadata ? 'responded_at')
  and coalesce(m.external_status, '') <> 'failed';
