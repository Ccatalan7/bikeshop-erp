-- Pedir una reseña de Google por WhatsApp después de entregar una bicicleta
-- (dueño, 2026-10-08: «dale con las reseñas por WhatsApp»).
--
-- Las reseñas recientes son de lo que más pesa en el ranking local de Google:
-- Viñabike salía 5.º al buscar «taller de bicicletas viña del mar» con 36
-- reseñas, detrás de talleres con 110 y 174. Unas 38 entregas al mes llevan
-- un celular chileno y nadie les pedía la reseña.
--
-- Cómo funciona:
-- * Una tarea programada mira las entregas registradas por un cambio de
--   estado (`mechanic_job_delivery_events`, `delivered`) entre 3 horas y
--   3 días atrás, sólo entre las 10:00 y las 20:00 de Chile.
-- * Por cada entrega deja una fila en `whatsapp_review_requests`: enviada, o
--   omitida con su motivo. Nunca dos por trabajo, y nunca dos al mismo
--   cliente (ni al mismo número) en 365 días.
-- * El mensaje sale por la misma cola durable que usa el equipo
--   (`enqueue_whatsapp_message_v1`), a nombre de quien entregó la bici y en la
--   conversación del cliente con el trabajo como contexto: queda en la bandeja
--   igual que si lo hubiera mandado esa persona.
-- * Se enciende por tienda con `company_settings.whatsapp_review_request_enabled
--   = 'true'` (Configuración › WhatsApp) y usa la plantilla `resena_google_v1`
--   de `supabase/functions/_shared/whatsapp_templates.ts`; el enlace sale del
--   lugar de Google del sitio (`website_settings.google_maps_place_id`).
--
-- Sin disparador en la tabla de entregas a propósito: un disparador nuevo ahí
-- tendría que registrarse en la recuperación de respaldos del taller, y esta
-- tabla queda fuera del respaldo para que restaurar no vuelva a pedir una
-- reseña ya pedida.

begin;

create table if not exists public.whatsapp_review_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  -- Ids sin llave foránea: borrar o restaurar un trabajo no debe borrar la
  -- constancia de que ya se le pidió la reseña a ese cliente.
  job_id uuid not null,
  delivery_event_id uuid not null,
  customer_id uuid,
  phone text,
  actor_id uuid,
  status text not null check (status in ('sent', 'skipped')),
  reason text,
  message_id uuid,
  created_at timestamptz not null default now(),
  unique (tenant_id, job_id)
);

create index if not exists whatsapp_review_requests_customer_recent
  on public.whatsapp_review_requests (tenant_id, customer_id, created_at desc)
  where status = 'sent';
create index if not exists whatsapp_review_requests_phone_recent
  on public.whatsapp_review_requests (tenant_id, phone, created_at desc)
  where status = 'sent';

alter table public.whatsapp_review_requests enable row level security;
revoke all on public.whatsapp_review_requests from public, anon, authenticated;
grant select on public.whatsapp_review_requests to authenticated;
grant all on public.whatsapp_review_requests to service_role;

drop policy if exists whatsapp_review_requests_staff_read on public.whatsapp_review_requests;
create policy whatsapp_review_requests_staff_read on public.whatsapp_review_requests
  for select to authenticated
  using (public.messaging_is_staff_in_tenant(tenant_id));

comment on table public.whatsapp_review_requests is
  'Un pedido de reseña de Google por entrega: enviado (message_id) u omitido (reason). Fuera del respaldo a propósito.';

create or replace function public.process_whatsapp_review_requests_v1(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_local_hour integer := extract(hour from (p_now at time zone 'America/Santiago'))::integer;
  v_row record;
  v_phone text;
  v_place text;
  v_channel uuid;
  v_reason text;
  v_name text;
  v_link text;
  v_binding jsonb;
  v_conversation uuid;
  v_result jsonb;
  v_message uuid;
  v_sent integer := 0;
  v_skipped integer := 0;
begin
  -- Nadie recibe un pedido de reseña de noche: lo que llega fuera de la
  -- ventana espera a la siguiente pasada dentro de ella (la entrega sigue
  -- vigente 3 días).
  if v_local_hour < 10 or v_local_hour >= 20 then
    return jsonb_build_object('sent', 0, 'skipped', 0, 'outside_hours', true);
  end if;

  for v_row in
    select e.id as event_id, e.tenant_id, e.job_id, e.actor_id,
           j.status as job_status, j.customer_id,
           c.name as customer_name, c.phone as customer_phone
      from public.mechanic_job_delivery_events e
      join public.company_settings s
        on s.tenant_id = e.tenant_id
       and s.key = 'whatsapp_review_request_enabled'
       and s.value = 'true'
      join public.mechanic_jobs j
        on j.id = e.job_id and j.tenant_id = e.tenant_id
      left join public.customers c
        on c.id = j.customer_id and c.tenant_id = j.tenant_id
     where e.event_kind = 'delivered'
       and e.source = 'status_transition'
       and e.occurred_at > p_now - interval '3 days'
       and e.occurred_at <= p_now - interval '3 hours'
       and not exists (
         select 1 from public.whatsapp_review_requests r
          where r.tenant_id = e.tenant_id and r.job_id = e.job_id)
     order by e.occurred_at
     limit 20
  loop
    v_reason := null;
    v_message := null;
    v_phone := public.normalize_whatsapp_phone(v_row.customer_phone);
    v_name := nullif(btrim(coalesce(v_row.customer_name, '')), '');

    select nullif(btrim(value), '') into v_place
      from public.website_settings
     where tenant_id = v_row.tenant_id and key = 'google_maps_place_id';
    select id into v_channel
      from public.whatsapp_channels
     where tenant_id = v_row.tenant_id and is_active
     order by created_at
     limit 1;

    if v_row.job_status is distinct from 'ENTREGADO' then
      v_reason := 'job_not_delivered';
    elsif v_row.customer_id is null or v_name is null then
      v_reason := 'no_customer';
    elsif v_phone is null or v_phone !~ '^569[0-9]{8}$' then
      v_reason := 'no_mobile';
    elsif v_row.actor_id is null then
      v_reason := 'no_actor';
    elsif exists (
      select 1 from public.whatsapp_review_requests r
       where r.tenant_id = v_row.tenant_id
         and r.status = 'sent'
         and r.created_at > p_now - interval '365 days'
         and (r.customer_id = v_row.customer_id or r.phone = v_phone)) then
      v_reason := 'asked_this_year';
    elsif v_place is null or v_place !~ '^[A-Za-z0-9_-]{10,}$' then
      v_reason := 'no_review_link';
    elsif v_channel is null then
      v_reason := 'no_channel';
    end if;

    if v_reason is null then
      v_link := 'https://search.google.com/local/writereview?placeid=' || v_place;
      begin
        -- Como quien entregó la bici: la cola, la conversación y la bandeja
        -- aplican sus reglas de equipo y de tienda a esa persona.
        perform set_config('request.jwt.claims', jsonb_build_object(
          'sub', v_row.actor_id, 'role', 'authenticated')::text, true);
        perform set_config('request.jwt.claim.sub', v_row.actor_id::text, true);

        v_binding := public.ensure_whatsapp_conversation_binding(
          p_tenant_id => v_row.tenant_id,
          p_channel_id => v_channel,
          p_wa_id => v_phone,
          p_phone_number => v_phone,
          p_contact_name => v_name,
          p_customer_id => v_row.customer_id,
          p_context_type => 'job',
          p_context_id => v_row.job_id,
          p_conversation_id => null);
        v_conversation := (v_binding->>'conversation_id')::uuid;

        -- El texto es el cuerpo aprobado de `resena_google_v1` con sus dos
        -- parámetros; el envío lo acorta al nombre de pila igual que en las
        -- demás plantillas (`template_purpose`).
        v_result := public.enqueue_whatsapp_message_v1(jsonb_build_object(
          'conversationId', v_conversation,
          'phoneNumber', v_phone,
          'contactName', v_name,
          'customerId', v_row.customer_id,
          'contextType', 'job',
          'contextId', v_row.job_id,
          'type', 'template',
          'templateName', 'resena_google_v1',
          'templateLanguage', 'es_CL',
          'caption', format(
            'Hola %s, ya entregamos tu bicicleta en Viñabike. ¿Cómo te fue con el servicio? Puedes contarnos con una reseña en Google: %s Gracias por preferirnos.',
            v_name, v_link),
          'templateComponents', jsonb_build_array(jsonb_build_object(
            'type', 'body',
            'parameters', jsonb_build_array(
              jsonb_build_object('type', 'text', 'text', v_name),
              jsonb_build_object('type', 'text', 'text', v_link)))),
          'metadata', jsonb_build_object(
            'source', 'review_request',
            'client_message_id', 'review-request:' || v_row.job_id,
            'template_purpose', 'google_review_request',
            'template_name', 'resena_google_v1',
            'template_language', 'es_CL',
            'message_category', 'utility',
            'job_id', v_row.job_id)));
        v_message := nullif(v_result->>'message_id', '')::uuid;
        if v_message is null then
          v_reason := 'send_not_accepted';
        end if;
      exception when others then
        v_reason := left('send_failed: ' || sqlerrm, 240);
      end;
      perform set_config('request.jwt.claims', '', true);
      perform set_config('request.jwt.claim.sub', '', true);
    end if;

    insert into public.whatsapp_review_requests(
      tenant_id, job_id, delivery_event_id, customer_id, phone, actor_id,
      status, reason, message_id)
    values (
      v_row.tenant_id, v_row.job_id, v_row.event_id, v_row.customer_id, v_phone,
      v_row.actor_id,
      case when v_reason is null then 'sent' else 'skipped' end,
      v_reason, v_message)
    on conflict (tenant_id, job_id) do nothing;

    if v_reason is null then
      v_sent := v_sent + 1;
    else
      v_skipped := v_skipped + 1;
    end if;
  end loop;

  return jsonb_build_object('sent', v_sent, 'skipped', v_skipped);
end;
$$;

revoke all on function public.process_whatsapp_review_requests_v1(timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.process_whatsapp_review_requests_v1(timestamptz) to service_role;

comment on function public.process_whatsapp_review_requests_v1(timestamptz) is
  'Pide por WhatsApp una reseña de Google a quien retiró su bicicleta (3 h a 3 días después, 10-20 h de Chile, una vez al año por cliente).';

select cron.unschedule(jobid) from cron.job where jobname = 'vinabike_whatsapp_review_requests';
select cron.schedule('vinabike_whatsapp_review_requests', '*/10 * * * *',
  'select public.process_whatsapp_review_requests_v1();');

commit;
