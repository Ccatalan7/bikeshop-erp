-- Avisos del taller al cliente, por correo y por WhatsApp (2026-11-05).
--
-- El dueño, sobre la recepción: «te llegará un mail de confirmación que
-- dejaste la bicicleta y ahí puedes revisar cuántos días lleva, los estatus,
-- que le lleguen notificaciones, todo eso», y sobre el canal: «correo y
-- WhatsApp las dos, dale con todo». Cuatro momentos: la bici recibida, el
-- presupuesto listo, la bici lista para retirar y la entrega con su
-- comprobante y su garantía.
--
-- Cómo funciona:
-- * Una pasada por minuto (`process_workshop_customer_notices_v1`) mira lo que
--   pasó desde que la tienda los encendió (`workshop_notices_started_at`) y en
--   las últimas 12 horas: los trabajos creados (`mechanic_job_creations`), los
--   cambios de estado (`mechanic_job_status_transitions`) y las entregas
--   (`mechanic_job_delivery_events`). Cada momento deja una fila por canal en
--   `workshop_customer_notices`, una sola por trabajo, momento y canal: un
--   trabajo que vuelve a «lista» no avisa dos veces.
-- * Cada aviso espera unos minutos (2 la recepción y la entrega, 5 el
--   presupuesto, 10 la bici lista) y al salir se vuelve a mirar el trabajo: si
--   la retiraron antes, el «está lista» no sale; si el cliente ya aprobó, el
--   presupuesto tampoco.
-- * El correo lo manda el worker que ya manda los del pedido y los de las
--   cotizaciones (`send-transactional-order-email`, cada minuto), con el mismo
--   remitente y la marca del sitio. El enlace se emite al reclamarlo y viaja
--   sólo al worker; la base guarda su huella.
-- * El WhatsApp sale por la cola durable del equipo (`enqueue_whatsapp_message_v1`)
--   a nombre de quien hizo el cambio, en la conversación del cliente con el
--   trabajo como contexto, entre las 9:00 y las 21:00 de Chile. Usa las
--   plantillas `taller_*_v1` cuando Meta ya las aprobó
--   (`whatsapp_template_reviews`); mientras tanto, el presupuesto y la bici
--   lista salen con las que ya estaban aprobadas, y la recepción y la entrega
--   esperan su plantilla hasta que el aviso vence.
-- * El enlace lleva a la ficha del cliente en la tienda; a quien todavía no
--   tiene cuenta, con un código para crearla ligada a su ficha
--   (`customer_portal_claim_codes`, 20261104200000).
-- * El cliente con cuenta elige en su perfil por dónde le avisamos
--   (`customer_workshop_notice_preferences`); sin elegir, por los dos.
-- * Fuera del respaldo a propósito, como `whatsapp_review_requests`: restaurar
--   un respaldo reinserta los cambios de estado con su hora original y no
--   debe volver a mandar lo ya mandado.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. Lo que Meta dice de cada plantilla
-- ---------------------------------------------------------------------------

-- La base no puede preguntarle a Meta; el gestor de plantillas
-- (`whatsapp-template-manager`) deja aquí lo que Meta respondió cada vez que
-- lista, y el worker de correo lo refresca cada media hora. Así una plantilla
-- recién aprobada empieza a usarse sola.
create table if not exists public.whatsapp_template_reviews (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  template_name text not null,
  template_language text not null,
  status text not null,
  category text,
  rejected_reason text,
  checked_at timestamptz not null default clock_timestamp(),
  primary key (tenant_id, template_name, template_language),
  constraint whatsapp_template_reviews_name check (
    template_name ~ '^[a-z0-9_]+$' and length(template_name) <= 512
  ),
  constraint whatsapp_template_reviews_language check (template_language ~ '^[a-z]{2,3}(_[A-Z]{2})?$'),
  constraint whatsapp_template_reviews_status check (status ~ '^[A-Z_]{1,40}$'),
  constraint whatsapp_template_reviews_reason check (rejected_reason is null or length(rejected_reason) <= 200)
);

comment on table public.whatsapp_template_reviews is
  'Lo último que Meta dijo de cada plantilla de WhatsApp de la tienda (APPROVED, PENDING, REJECTED…), con la hora de la consulta. Lo escribe el gestor de plantillas.';

alter table public.whatsapp_template_reviews enable row level security;
revoke all on public.whatsapp_template_reviews from public, anon, authenticated;
grant select on public.whatsapp_template_reviews to authenticated;
grant all on public.whatsapp_template_reviews to service_role;
drop policy if exists whatsapp_template_reviews_staff_read on public.whatsapp_template_reviews;
create policy whatsapp_template_reviews_staff_read on public.whatsapp_template_reviews
  for select to authenticated
  using (public.messaging_is_staff_in_tenant(tenant_id));

-- Reemplaza lo que se sabe de la tienda por la lista que acaba de dar Meta:
-- una plantilla que ya no está en la lista deja de contar como aprobada.
create or replace function public.record_whatsapp_template_reviews_v1(
  p_tenant_id uuid,
  p_templates jsonb
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_count integer := 0;
begin
  if p_tenant_id is null or jsonb_typeof(p_templates) is distinct from 'array' then
    raise exception 'A tenant and a template list are required' using errcode = '22023';
  end if;

  -- Una sola sentencia: lo que salió de la lista se borra y lo demás se
  -- escribe; las dos partes tocan filas distintas.
  with incoming as (
    select distinct on (name, language) name, language, status, category, rejected_reason
      from (
        select nullif(btrim(item->>'name'), '') as name,
               nullif(btrim(item->>'language'), '') as language,
               upper(nullif(btrim(item->>'status'), '')) as status,
               upper(nullif(btrim(item->>'category'), '')) as category,
               left(nullif(btrim(item->>'rejected_reason'), ''), 200) as rejected_reason
          from jsonb_array_elements(p_templates) item
         where jsonb_typeof(item) = 'object'
      ) raw
     where name ~ '^[a-z0-9_]+$'
       and length(name) <= 512
       and language ~ '^[a-z]{2,3}(_[A-Z]{2})?$'
       and status ~ '^[A-Z_]{1,40}$'
     order by name, language
  ), removed as (
    delete from public.whatsapp_template_reviews review
     where review.tenant_id = p_tenant_id
       and not exists (
         select 1 from incoming
          where incoming.name = review.template_name
            and incoming.language = review.template_language)
    returning 1
  )
  insert into public.whatsapp_template_reviews (
    tenant_id, template_name, template_language, status, category, rejected_reason, checked_at
  )
  select p_tenant_id, incoming.name, incoming.language, incoming.status,
         case when incoming.category ~ '^[A-Z_]{1,40}$' then incoming.category end,
         case when incoming.rejected_reason <> 'NONE' then incoming.rejected_reason end,
         clock_timestamp()
    from incoming
  on conflict (tenant_id, template_name, template_language) do update
     set status = excluded.status,
         category = excluded.category,
         rejected_reason = excluded.rejected_reason,
         checked_at = excluded.checked_at;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.record_whatsapp_template_reviews_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.record_whatsapp_template_reviews_v1(uuid, jsonb) to service_role;

comment on function public.record_whatsapp_template_reviews_v1(uuid, jsonb) is
  'El gestor de plantillas deja lo que Meta respondió: la lista completa de la tienda reemplaza a la anterior.';

-- Aprobada y consultada en la última semana: si la consulta lleva días
-- fallando, mejor no mandar con una plantilla que quizás Meta pausó.
create or replace function public.whatsapp_template_approved_internal(
  p_tenant_id uuid,
  p_name text,
  p_language text default 'es_CL'
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.whatsapp_template_reviews review
     where review.tenant_id = p_tenant_id
       and review.template_name = p_name
       and review.template_language = coalesce(p_language, 'es_CL')
       and review.status = 'APPROVED'
       and review.checked_at > clock_timestamp() - interval '7 days');
$$;

revoke all on function public.whatsapp_template_approved_internal(uuid, text, text)
  from public, anon, authenticated, service_role;

-- Cuándo fue la última consulta, para que el worker sepa si refrescar.
create or replace function public.whatsapp_template_reviews_checked_at_v1(p_tenant_id uuid)
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select max(review.checked_at)
    from public.whatsapp_template_reviews review
   where review.tenant_id = p_tenant_id;
$$;

revoke all on function public.whatsapp_template_reviews_checked_at_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.whatsapp_template_reviews_checked_at_v1(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 2. Por dónde quiere el cliente que le avisemos
-- ---------------------------------------------------------------------------

-- Sin llave foránea a `customers`, como los pedidos de reseña: restaurar un
-- respaldo borra y reinserta las fichas, y un borrado en cascada se llevaría
-- lo que el cliente eligió.
create table if not exists public.customer_workshop_notice_preferences (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  customer_id uuid not null,
  email_enabled boolean not null default true,
  whatsapp_enabled boolean not null default true,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (tenant_id, customer_id)
);

comment on table public.customer_workshop_notice_preferences is
  'Lo que eligió el cliente con cuenta en su perfil: si recibe los avisos del taller por correo, por WhatsApp o por los dos. Sin fila, por los dos.';

alter table public.customer_workshop_notice_preferences enable row level security;
revoke all on public.customer_workshop_notice_preferences from public, anon, authenticated;
grant select on public.customer_workshop_notice_preferences to authenticated;
grant all on public.customer_workshop_notice_preferences to service_role;
drop policy if exists customer_workshop_notice_preferences_staff_read
  on public.customer_workshop_notice_preferences;
create policy customer_workshop_notice_preferences_staff_read
  on public.customer_workshop_notice_preferences
  for select to authenticated
  using (public.messaging_is_staff_in_tenant(tenant_id));

-- La ficha de quien entró a la tienda: la suya y de esa tienda.
create or replace function public.my_workshop_notice_customer_internal(p_tenant_id uuid)
returns public.customers
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select customer.*
    from public.customers customer
   where customer.tenant_id = p_tenant_id
     and customer.auth_user_id = auth.uid()
     and auth.uid() is not null
     and customer.is_active is true
   order by customer.updated_at desc nulls last, customer.created_at desc nulls last
   limit 1;
$$;

revoke all on function public.my_workshop_notice_customer_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.get_my_workshop_notice_preferences_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_customer public.customers%rowtype;
  v_preference public.customer_workshop_notice_preferences%rowtype;
begin
  v_customer := public.my_workshop_notice_customer_internal(p_tenant_id);
  if v_customer.id is null then
    return jsonb_build_object('status', 'not_linked');
  end if;
  select * into v_preference
    from public.customer_workshop_notice_preferences preference
   where preference.tenant_id = p_tenant_id
     and preference.customer_id = v_customer.id;
  return jsonb_build_object(
    'status', 'linked',
    'email_enabled', coalesce(v_preference.email_enabled, true),
    'whatsapp_enabled', coalesce(v_preference.whatsapp_enabled, true),
    'has_email', coalesce(btrim(v_customer.email) ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$', false),
    'has_mobile', coalesce(public.normalize_whatsapp_phone(v_customer.phone) ~ '^569[0-9]{8}$', false)
  );
end;
$$;

revoke all on function public.get_my_workshop_notice_preferences_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_workshop_notice_preferences_v1(uuid) to authenticated;

comment on function public.get_my_workshop_notice_preferences_v1(uuid) is
  'El cliente con cuenta: por dónde recibe los avisos del taller y qué datos de contacto tiene su ficha.';

create or replace function public.set_my_workshop_notice_preferences_v1(
  p_tenant_id uuid,
  p_email_enabled boolean,
  p_whatsapp_enabled boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_customer public.customers%rowtype;
begin
  if p_email_enabled is null or p_whatsapp_enabled is null then
    raise exception 'workshop_notice_preferences_invalid' using errcode = '22023';
  end if;
  v_customer := public.my_workshop_notice_customer_internal(p_tenant_id);
  if v_customer.id is null then
    raise exception 'workshop_notice_preferences_not_linked' using errcode = '42501';
  end if;
  insert into public.customer_workshop_notice_preferences (
    tenant_id, customer_id, email_enabled, whatsapp_enabled, updated_at, updated_by
  ) values (
    p_tenant_id, v_customer.id, p_email_enabled, p_whatsapp_enabled, clock_timestamp(), auth.uid()
  )
  on conflict (tenant_id, customer_id) do update
     set email_enabled = excluded.email_enabled,
         whatsapp_enabled = excluded.whatsapp_enabled,
         updated_at = excluded.updated_at,
         updated_by = excluded.updated_by;
  return public.get_my_workshop_notice_preferences_v1(p_tenant_id);
end;
$$;

revoke all on function public.set_my_workshop_notice_preferences_v1(uuid, boolean, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.set_my_workshop_notice_preferences_v1(uuid, boolean, boolean)
  to authenticated;

comment on function public.set_my_workshop_notice_preferences_v1(uuid, boolean, boolean) is
  'El cliente con cuenta elige si recibe los avisos del taller por correo, por WhatsApp o por los dos.';

-- ---------------------------------------------------------------------------
-- 3. Los avisos
-- ---------------------------------------------------------------------------

create table if not exists public.workshop_customer_notices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  -- Ids sin llave foránea, como `whatsapp_review_requests`: borrar o
  -- restaurar un trabajo no borra la constancia de lo que ya se avisó.
  job_id uuid not null,
  customer_id uuid,
  kind text not null,
  channel text not null,
  source_id uuid not null,
  source_at timestamptz not null,
  actor_id uuid,
  recipient text,
  state text not null default 'pending',
  reason text,
  template_name text,
  attempt_count integer not null default 0,
  max_attempts integer not null default 6,
  available_at timestamptz not null,
  expires_at timestamptz not null,
  lease_owner text,
  lease_until timestamptz,
  provider_message_id text,
  message_id uuid,
  sent_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint workshop_customer_notices_kind check (kind in ('received', 'quote_ready', 'ready', 'delivered')),
  constraint workshop_customer_notices_channel check (channel in ('email', 'whatsapp')),
  constraint workshop_customer_notices_state check (state in ('pending', 'sending', 'sent', 'skipped', 'failed')),
  constraint workshop_customer_notices_sent_shape check ((state = 'sent') = (sent_at is not null)),
  constraint workshop_customer_notices_lease_shape check (
    (state = 'sending') = (lease_owner is not null and lease_until is not null)
  ),
  constraint workshop_customer_notices_window check (expires_at > available_at),
  constraint workshop_customer_notices_reason check (reason is null or length(reason) <= 300),
  constraint workshop_customer_notices_attempts check (attempt_count >= 0 and max_attempts between 1 and 20),
  constraint workshop_customer_notices_once unique (tenant_id, job_id, kind, channel)
);

create index if not exists workshop_customer_notices_due_idx
  on public.workshop_customer_notices (tenant_id, channel, available_at)
  where state in ('pending', 'sending');
create index if not exists workshop_customer_notices_job_idx
  on public.workshop_customer_notices (tenant_id, job_id, created_at);
create index if not exists workshop_customer_notices_recent_idx
  on public.workshop_customer_notices (tenant_id, created_at desc);

comment on table public.workshop_customer_notices is
  'Los avisos del taller al cliente (recibida, presupuesto listo, lista para retirar, entregada) por correo o WhatsApp: enviados, omitidos con su motivo o por enviar. Uno por trabajo, momento y canal. Fuera del respaldo a propósito.';

alter table public.workshop_customer_notices enable row level security;
revoke all on public.workshop_customer_notices from public, anon, authenticated;
grant select on public.workshop_customer_notices to authenticated;
grant all on public.workshop_customer_notices to service_role;
drop policy if exists workshop_customer_notices_staff_read on public.workshop_customer_notices;
create policy workshop_customer_notices_staff_read on public.workshop_customer_notices
  for select to authenticated
  using (public.messaging_is_staff_in_tenant(tenant_id));

-- Las pasadas miran ventanas de 12 horas por tienda.
create index if not exists idx_mechanic_job_creations_tenant_completed
  on public.mechanic_job_creations (tenant_id, completed_at);
create index if not exists idx_mechanic_job_delivery_events_tenant_time
  on public.mechanic_job_delivery_events (tenant_id, occurred_at);

-- ---------------------------------------------------------------------------
-- 4. Lo que encendió la tienda
-- ---------------------------------------------------------------------------

-- Encendidos por omisión (el dueño los pidió); `false` apaga un canal. Sin
-- `workshop_notices_started_at` la tienda no avisa nada: al publicar esto no
-- salen avisos de trabajos viejos.
create or replace function public.workshop_notice_settings_internal(p_tenant_id uuid)
returns table (started_at timestamptz, email_enabled boolean, whatsapp_enabled boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    (select case
              when btrim(setting.value) ~ '^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}'
                then btrim(setting.value)::timestamptz
            end
       from public.company_settings setting
      where setting.tenant_id = p_tenant_id
        and setting.key = 'workshop_notices_started_at'),
    coalesce((
      select btrim(setting.value) <> 'false'
        from public.company_settings setting
       where setting.tenant_id = p_tenant_id
         and setting.key = 'workshop_notices_email_enabled'
    ), true)
    and exists (
      select 1 from public.transactional_email_settings email
       where email.tenant_id = p_tenant_id
         and email.enabled
         and email.delivery_mode = 'send'
         and email.from_email is not null),
    coalesce((
      select btrim(setting.value) <> 'false'
        from public.company_settings setting
       where setting.tenant_id = p_tenant_id
         and setting.key = 'workshop_notices_whatsapp_enabled'
    ), true)
    and exists (
      select 1 from public.whatsapp_channels channel
       where channel.tenant_id = p_tenant_id
         and channel.is_active);
$$;

revoke all on function public.workshop_notice_settings_internal(uuid)
  from public, anon, authenticated, service_role;

-- Espera antes de salir y plazo para salir, por momento.
create or replace function public.workshop_notice_delay_internal(p_kind text)
returns interval
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select case p_kind
    when 'received' then interval '2 minutes'
    when 'quote_ready' then interval '5 minutes'
    when 'ready' then interval '10 minutes'
    when 'delivered' then interval '2 minutes'
  end;
$$;

create or replace function public.workshop_notice_lifetime_internal(p_kind text)
returns interval
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select case p_kind
    when 'received' then interval '6 hours'
    else interval '24 hours'
  end;
$$;

revoke all on function public.workshop_notice_delay_internal(text),
  public.workshop_notice_lifetime_internal(text)
  from public, anon, authenticated, service_role;

-- Si el aviso todavía corresponde: el motivo para no mandarlo, o null.
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
    if v_status <> 'ESPERANDO_APROBACION' or p_job.approved_by_customer is true then
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

-- Lo que recibimos, dicho al cliente: la bici con marca y modelo, o el
-- elemento del catálogo para un trabajo de componente.
create or replace function public.workshop_notice_item_internal(p_job public.mechanic_jobs)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_item text;
begin
  select nullif(btrim(concat_ws(' ', nullif(btrim(bike.brand), ''), nullif(btrim(bike.model), ''))), '')
    into v_item
    from public.mechanic_job_bikes job_bike
    join public.bikes bike
      on bike.id = job_bike.bike_id
     and bike.tenant_id = job_bike.tenant_id
   where job_bike.tenant_id = p_job.tenant_id
     and job_bike.job_id = p_job.id
   order by job_bike.order_index, job_bike.created_at
   limit 1;
  if v_item is null and p_job.bike_id is not null then
    select nullif(btrim(concat_ws(' ', nullif(btrim(bike.brand), ''), nullif(btrim(bike.model), ''))), '')
      into v_item
      from public.bikes bike
     where bike.id = p_job.bike_id
       and bike.tenant_id = p_job.tenant_id;
  end if;
  if v_item is null and p_job.intake_kind = 'component' and p_job.subject_id is not null then
    select lower(nullif(btrim(subject.name), ''))
      into v_item
      from public.job_subjects subject
     where subject.id = p_job.subject_id
       and subject.tenant_id = p_job.tenant_id;
  end if;
  return coalesce(v_item, case when p_job.intake_kind = 'component' then 'componente' else 'bicicleta' end);
end;
$$;

revoke all on function public.workshop_notice_item_internal(public.mechanic_jobs)
  from public, anon, authenticated, service_role;

-- La dirección de la tienda, la misma del QR de la recepción.
create or replace function public.workshop_notice_store_url_internal(p_tenant_id uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select rtrim(coalesce(
    (select nullif(btrim(setting.value), '')
       from public.website_settings setting
      where setting.tenant_id = p_tenant_id
        and setting.key = 'store_url'
        and btrim(setting.value) ~* '^https://[^[:space:]/]+'),
    public.transactional_email_store_url(
      (select email.public_store_url from public.transactional_email_settings email
        where email.tenant_id = p_tenant_id),
      (select tenant.custom_domain from public.tenants tenant where tenant.id = p_tenant_id))
  ), '/');
$$;

revoke all on function public.workshop_notice_store_url_internal(uuid)
  from public, anon, authenticated, service_role;

-- Adónde lleva el aviso: a la ficha del cliente en la tienda, o a crear la
-- cuenta ligada a ella con un código nuevo (120 días, como el del QR).
create or replace function public.workshop_notice_link_internal(
  p_job public.mechanic_jobs,
  p_kind text,
  p_actor uuid
)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_customer public.customers%rowtype;
  v_store text := public.workshop_notice_store_url_internal(p_job.tenant_id);
  v_raw text;
begin
  if v_store is null then
    return null;
  end if;
  select * into v_customer
    from public.customers customer
   where customer.id = p_job.customer_id
     and customer.tenant_id = p_job.tenant_id;
  if not found or v_customer.is_active is not true or v_customer.auth_user_id is not null then
    return v_store || '/cuenta/servicios';
  end if;

  v_raw := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.customer_portal_claim_codes (
    tenant_id, customer_id, job_id, purpose, code_sha256, expires_at, created_by
  ) values (
    p_job.tenant_id,
    v_customer.id,
    p_job.id,
    case when p_kind = 'delivered' then 'delivery' else 'reception' end,
    encode(extensions.digest(convert_to(v_raw, 'UTF8'), 'sha256'), 'hex'),
    clock_timestamp() + interval '120 days',
    p_actor
  );
  return v_store || '/cuenta/vincular#c=' || v_raw;
end;
$$;

revoke all on function public.workshop_notice_link_internal(public.mechanic_jobs, text, uuid)
  from public, anon, authenticated, service_role;

-- Quien hace el envío: el que hizo el cambio si sigue en el equipo; si no,
-- quien creó el trabajo.
create or replace function public.workshop_notice_actor_internal(
  p_tenant_id uuid,
  p_actor uuid,
  p_fallback uuid
)
returns uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select candidate.user_id
    from (values (1, p_actor), (2, p_fallback)) candidate(ord, user_id)
    join public.user_profiles profile
      on profile.user_id = candidate.user_id
     and profile.tenant_id = p_tenant_id
     and profile.is_active is true
   where candidate.user_id is not null
   order by candidate.ord
   limit 1;
$$;

revoke all on function public.workshop_notice_actor_internal(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 5. La pasada: anotar los avisos y mandar los de WhatsApp
-- ---------------------------------------------------------------------------

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
  -- Una cotización suelta no es una bici en el taller.
  if not found or coalesce(v_job.workflow_kind, 'service') <> 'service' then
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

-- La plantilla con que sale un aviso: la del taller si Meta la aprobó; si
-- no, la aprobada de antes para el presupuesto y la bici lista; si no, null
-- (el aviso espera).
create or replace function public.workshop_notice_template_internal(
  p_tenant_id uuid,
  p_kind text,
  p_intake_kind text
)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_primary text := case p_kind
    when 'received' then 'taller_recibida_v1'
    when 'quote_ready' then 'taller_presupuesto_v1'
    when 'ready' then 'taller_lista_v1'
    when 'delivered' then 'taller_entregada_v1'
  end;
begin
  if v_primary is not null and public.whatsapp_template_approved_internal(p_tenant_id, v_primary) then
    return v_primary;
  end if;
  if p_kind = 'quote_ready'
     and public.whatsapp_template_approved_internal(p_tenant_id, 'seguimiento_presupuesto_bicicleta') then
    return 'seguimiento_presupuesto_bicicleta';
  end if;
  -- «tu bicicleta está lista»: sólo cuando lo que dejó es una bici.
  if p_kind = 'ready'
     and coalesce(p_intake_kind, 'bike') <> 'component'
     and public.whatsapp_template_approved_internal(p_tenant_id, 'bicicleta_lista_retiro') then
    return 'bicicleta_lista_retiro';
  end if;
  return null;
end;
$$;

revoke all on function public.workshop_notice_template_internal(uuid, text, text)
  from public, anon, authenticated, service_role;

-- La fecha de la garantía como se lee: «19 de noviembre».
create or replace function public.workshop_notice_date_internal(p_at timestamptz)
returns text
language sql
immutable
set search_path = pg_catalog, pg_temp
as $$
  select case when p_at is null then null else
    extract(day from (p_at at time zone 'America/Santiago'))::integer::text || ' de ' ||
    (array['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
           'septiembre', 'octubre', 'noviembre', 'diciembre'])[
      extract(month from (p_at at time zone 'America/Santiago'))::integer]
  end;
$$;

revoke all on function public.workshop_notice_date_internal(timestamptz)
  from public, anon, authenticated, service_role;

-- Manda un aviso de WhatsApp ya vencida su espera. Devuelve el estado en que
-- queda: `sent`, `skipped`, `failed` o `pending` si todavía espera (de noche
-- o por la plantilla).
create or replace function public.workshop_notice_dispatch_whatsapp_internal(
  p_notice_id uuid,
  p_now timestamptz,
  p_in_hours boolean
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_notice public.workshop_customer_notices%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_reason text;
  v_template text;
  v_actor uuid;
  v_channel uuid;
  v_link text;
  v_name text;
  v_item text;
  v_number text;
  v_until text;
  v_params text[];
  v_caption text;
  v_binding jsonb;
  v_conversation uuid;
  v_result jsonb;
  v_message uuid;
begin
  select * into v_notice
    from public.workshop_customer_notices notice
   where notice.id = p_notice_id
     and notice.channel = 'whatsapp'
     and notice.state = 'pending'
   for update skip locked;
  if not found then
    return null;
  end if;

  select * into v_job
    from public.mechanic_jobs job
   where job.id = v_notice.job_id and job.tenant_id = v_notice.tenant_id;
  v_reason := public.workshop_notice_stale_reason_internal(v_notice.kind, v_job);
  v_template := case when v_reason is null
    then public.workshop_notice_template_internal(v_notice.tenant_id, v_notice.kind, v_job.intake_kind)
  end;

  if v_reason is null and p_now >= v_notice.expires_at then
    v_reason := case when v_template is null then 'template_not_approved' else 'expired' end;
  end if;
  if v_reason is not null then
    update public.workshop_customer_notices
       set state = 'skipped', reason = v_reason, updated_at = clock_timestamp()
     where id = v_notice.id;
    return 'skipped';
  end if;
  -- De noche, o sin plantilla aprobada todavía: espera la siguiente pasada.
  if not p_in_hours or v_template is null then
    return 'pending';
  end if;

  select * into v_customer
    from public.customers customer
   where customer.id = v_job.customer_id and customer.tenant_id = v_job.tenant_id;
  v_name := nullif(btrim(coalesce(v_customer.name, '')), '');
  v_actor := public.workshop_notice_actor_internal(v_notice.tenant_id, v_notice.actor_id, v_job.created_by);
  select channel.id into v_channel
    from public.whatsapp_channels channel
   where channel.tenant_id = v_notice.tenant_id and channel.is_active
   order by channel.created_at
   limit 1;

  v_reason := case
    when v_name is null then 'no_customer'
    when v_actor is null then 'no_actor'
    when v_channel is null then 'no_channel'
  end;

  if v_reason is null then
    v_number := coalesce(nullif(btrim(v_job.job_number), ''), 'de taller');
    v_item := public.workshop_notice_item_internal(v_job);
    if v_template in ('taller_recibida_v1', 'taller_presupuesto_v1', 'taller_lista_v1', 'taller_entregada_v1') then
      v_link := public.workshop_notice_link_internal(v_job, v_notice.kind, v_actor);
      if v_link is null then
        v_reason := 'no_store_url';
      end if;
    end if;
  end if;

  if v_reason is null then
    if v_template = 'taller_recibida_v1' then
      v_params := array[v_name, v_item, v_number, v_link];
      v_caption := format(
        'Hola %s, recibimos tu %s en Viñabike. Tu número de trabajo es %s y aquí puedes seguir su estado: %s Te avisaremos por este medio cuando esté listo.',
        v_name, v_item, v_number, v_link);
    elsif v_template = 'taller_presupuesto_v1' then
      v_params := array[v_name, v_number, v_link];
      v_caption := format(
        'Hola %s, el presupuesto de tu trabajo %s está listo. Puedes verlo aquí: %s Para aprobarlo o hacer una consulta, responde este mensaje.',
        v_name, v_number, v_link);
    elsif v_template = 'taller_lista_v1' then
      v_params := array[v_name, v_number, v_link];
      v_caption := format(
        'Hola %s, tu trabajo %s está listo para retirar en Viñabike. El detalle está aquí: %s Si necesitas coordinar el retiro, responde este mensaje.',
        v_name, v_number, v_link);
    elsif v_template = 'taller_entregada_v1' then
      select public.workshop_notice_date_internal(document.service_warranty_expires_at)
        into v_until
        from public.mechanic_job_delivery_documents document
       where document.tenant_id = v_job.tenant_id and document.job_id = v_job.id;
      if v_until is null then
        select public.workshop_notice_date_internal(event.warranty_expires_at)
          into v_until
          from public.mechanic_job_delivery_events event
         where event.id = v_notice.source_id;
      end if;
      if v_until is null then
        v_reason := 'no_warranty';
      else
        v_params := array[v_name, v_number, v_until, v_link];
        v_caption := format(
          'Hola %s, gracias por retirar tu trabajo %s. La garantía del servicio vale hasta el %s y tu comprobante está aquí: %s Gracias por confiar en Viñabike.',
          v_name, v_number, v_until, v_link);
      end if;
    elsif v_template = 'seguimiento_presupuesto_bicicleta' then
      v_params := array[v_name, 'Viñabike'];
      v_caption := format(
        'Hola %s, necesitamos tu respuesta sobre un presupuesto o aprobación pendiente en %s. Responde este mensaje para continuar.',
        v_name, 'Viñabike');
    elsif v_template = 'bicicleta_lista_retiro' then
      v_params := array[v_name, 'Viñabike'];
      v_caption := format(
        'Hola %s, tu bicicleta está lista para retiro en %s. Responde este mensaje si necesitas coordinar algo.',
        v_name, 'Viñabike');
    end if;
  end if;

  if v_reason is null then
    begin
      -- Como quien hizo el cambio: la cola, la conversación y la bandeja
      -- aplican sus reglas de equipo y de tienda a esa persona.
      perform set_config('request.jwt.claims', jsonb_build_object(
        'sub', v_actor, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', v_actor::text, true);

      v_binding := public.ensure_whatsapp_conversation_binding(
        p_tenant_id => v_notice.tenant_id,
        p_channel_id => v_channel,
        p_wa_id => v_notice.recipient,
        p_phone_number => v_notice.recipient,
        p_contact_name => v_name,
        p_customer_id => v_customer.id,
        p_context_type => 'job',
        p_context_id => v_job.id,
        p_conversation_id => null);
      v_conversation := (v_binding->>'conversation_id')::uuid;

      v_result := public.enqueue_whatsapp_message_v1(jsonb_build_object(
        'conversationId', v_conversation,
        'phoneNumber', v_notice.recipient,
        'contactName', v_name,
        'customerId', v_customer.id,
        'contextType', 'job',
        'contextId', v_job.id,
        'type', 'template',
        'templateName', v_template,
        'templateLanguage', 'es_CL',
        'caption', v_caption,
        'templateComponents', jsonb_build_array(jsonb_build_object(
          'type', 'body',
          'parameters', (
            select jsonb_agg(jsonb_build_object('type', 'text', 'text', value) order by ord)
              from unnest(v_params) with ordinality as param(value, ord)
          ))),
        'metadata', jsonb_build_object(
          'source', 'workshop_notice',
          'client_message_id', 'workshop-notice:' || v_notice.id,
          'template_purpose', 'workshop_' || v_notice.kind,
          'template_name', v_template,
          'template_language', 'es_CL',
          'message_category', 'utility',
          'workshop_notice_id', v_notice.id,
          'job_id', v_job.id)));
      v_message := nullif(v_result->>'message_id', '')::uuid;
      if v_message is null then
        v_reason := 'send_not_accepted';
      end if;
    exception when others then
      v_reason := left('send_failed: ' || sqlerrm, 280);
    end;
    perform set_config('request.jwt.claims', '', true);
    perform set_config('request.jwt.claim.sub', '', true);
  end if;

  if v_message is not null then
    update public.workshop_customer_notices
       set state = 'sent', sent_at = clock_timestamp(), template_name = v_template,
           message_id = v_message, attempt_count = attempt_count + 1,
           reason = null, updated_at = clock_timestamp()
     where id = v_notice.id;
    return 'sent';
  end if;

  update public.workshop_customer_notices
     set state = case when v_reason like 'send_%' then 'failed' else 'skipped' end,
         reason = v_reason, template_name = v_template,
         attempt_count = attempt_count + 1, updated_at = clock_timestamp()
   where id = v_notice.id;
  return case when v_reason like 'send_%' then 'failed' else 'skipped' end;
end;
$$;

revoke all on function public.workshop_notice_dispatch_whatsapp_internal(uuid, timestamptz, boolean)
  from public, anon, authenticated, service_role;

create or replace function public.process_workshop_customer_notices_v1(
  p_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_local_hour integer := extract(hour from (p_now at time zone 'America/Santiago'))::integer;
  v_in_hours boolean := v_local_hour >= 9 and v_local_hour < 21;
  v_tenant record;
  v_source record;
  v_notice record;
  v_state text;
  v_created integer := 0;
  v_sent integer := 0;
  v_skipped integer := 0;
  v_waiting integer := 0;
begin
  for v_tenant in
    select tenant.id as tenant_id, settings.started_at, settings.email_enabled, settings.whatsapp_enabled
      from public.tenants tenant
      cross join lateral public.workshop_notice_settings_internal(tenant.id) settings
     where settings.started_at is not null
  loop
    for v_source in
      select 'received'::text as kind, creation.job_id, creation.id as source_id,
             creation.completed_at as source_at, creation.created_by as actor_id
        from public.mechanic_job_creations creation
       where creation.tenant_id = v_tenant.tenant_id
         and creation.job_id is not null
         and creation.completed_at >= v_tenant.started_at
         and creation.completed_at > p_now - interval '12 hours'
         and creation.completed_at <= p_now
      union all
      select case
               when transition.to_status = 'ESPERANDO_APROBACION' then 'quote_ready'
               else 'ready'
             end,
             transition.job_id, transition.id, transition.occurred_at, transition.actor_user_id
        from public.mechanic_job_status_transitions transition
       where transition.tenant_id = v_tenant.tenant_id
         and transition.occurred_at >= v_tenant.started_at
         and transition.occurred_at > p_now - interval '12 hours'
         and transition.occurred_at <= p_now
         and transition.from_status is distinct from transition.to_status
         and (
           transition.to_status = 'ESPERANDO_APROBACION'
           or (
             (transition.to_triggers_completion or transition.to_status in ('FINALIZADO', 'PROBADO'))
             and not transition.to_triggers_delivery
           )
         )
      union all
      select 'delivered', delivery.job_id, delivery.id, delivery.occurred_at, delivery.actor_id
        from public.mechanic_job_delivery_events delivery
       where delivery.tenant_id = v_tenant.tenant_id
         and delivery.event_kind = 'delivered'
         and delivery.source = 'status_transition'
         and delivery.occurred_at >= v_tenant.started_at
         and delivery.occurred_at > p_now - interval '12 hours'
         and delivery.occurred_at <= p_now
    loop
      -- Lo ya anotado se salta sin escribir.
      continue when not (v_tenant.email_enabled or v_tenant.whatsapp_enabled)
        or (
          select count(*) from public.workshop_customer_notices notice
           where notice.tenant_id = v_tenant.tenant_id
             and notice.job_id = v_source.job_id
             and notice.kind = v_source.kind
        ) >= (v_tenant.email_enabled::integer + v_tenant.whatsapp_enabled::integer);
      v_created := v_created + public.workshop_notice_enqueue_internal(
        v_tenant.tenant_id, v_source.job_id, v_source.kind, v_source.source_id,
        v_source.source_at, v_source.actor_id, v_tenant.email_enabled, v_tenant.whatsapp_enabled);
    end loop;

    -- WhatsApp apagado (o sin canal): lo que estaba por salir no sale.
    if not v_tenant.whatsapp_enabled then
      with off as (
        update public.workshop_customer_notices notice
           set state = 'skipped', reason = 'channel_off', updated_at = clock_timestamp()
         where notice.tenant_id = v_tenant.tenant_id
           and notice.channel = 'whatsapp'
           and notice.state = 'pending'
        returning 1
      )
      select v_skipped + count(*) into v_skipped from off;
      continue;
    end if;

    for v_notice in
      select notice.id
        from public.workshop_customer_notices notice
       where notice.tenant_id = v_tenant.tenant_id
         and notice.channel = 'whatsapp'
         and notice.state = 'pending'
         and notice.available_at <= p_now
       order by notice.available_at
       limit 50
    loop
      v_state := public.workshop_notice_dispatch_whatsapp_internal(v_notice.id, p_now, v_in_hours);
      if v_state = 'sent' then
        v_sent := v_sent + 1;
      elsif v_state in ('skipped', 'failed') then
        v_skipped := v_skipped + 1;
      elsif v_state = 'pending' then
        v_waiting := v_waiting + 1;
      end if;
    end loop;
  end loop;

  return jsonb_build_object(
    'created', v_created,
    'whatsapp_sent', v_sent,
    'skipped', v_skipped,
    'waiting', v_waiting,
    'in_hours', v_in_hours);
end;
$$;

revoke all on function public.process_workshop_customer_notices_v1(timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.process_workshop_customer_notices_v1(timestamptz) to service_role;

comment on function public.process_workshop_customer_notices_v1(timestamptz) is
  'Anota los avisos del taller al cliente (recibida, presupuesto listo, lista, entregada) y manda los de WhatsApp que ya tocan, de 9 a 21 de Chile.';

-- ---------------------------------------------------------------------------
-- 6. El correo: lo reclama y lo cierra el worker
-- ---------------------------------------------------------------------------

create or replace function public.workshop_notice_email_payload_internal(p_notice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_notice public.workshop_customer_notices%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_tenant public.tenants%rowtype;
  v_settings public.transactional_email_settings%rowtype;
  v_document public.mechanic_job_delivery_documents%rowtype;
  v_store text;
  v_link text;
  v_has_parts boolean := false;
begin
  select * into v_notice from public.workshop_customer_notices where id = p_notice_id;
  select * into v_job from public.mechanic_jobs
   where id = v_notice.job_id and tenant_id = v_notice.tenant_id;
  select * into v_customer from public.customers
   where id = v_job.customer_id and tenant_id = v_job.tenant_id;
  select * into v_tenant from public.tenants where id = v_notice.tenant_id;
  select * into v_settings from public.transactional_email_settings where tenant_id = v_notice.tenant_id;
  v_store := public.workshop_notice_store_url_internal(v_notice.tenant_id);
  v_link := public.workshop_notice_link_internal(v_job, v_notice.kind, v_notice.actor_id);
  if v_notice.kind = 'delivered' then
    select * into v_document from public.mechanic_job_delivery_documents
     where tenant_id = v_job.tenant_id and job_id = v_job.id;
    v_has_parts := coalesce((
      select bool_or(line->>'kind' = 'part')
        from jsonb_array_elements(coalesce(v_document.snapshot->'lines', '[]'::jsonb)) line
    ), false);
  end if;

  return jsonb_build_object(
    'noticeId', v_notice.id,
    'kind', v_notice.kind,
    'recipient', v_notice.recipient,
    'sender', jsonb_strip_nulls(jsonb_build_object(
      'enabled', coalesce(v_settings.enabled, false) and v_settings.delivery_mode = 'send',
      'name', v_settings.from_name,
      'email', v_settings.from_email,
      'replyTo', v_settings.reply_to_email
    )),
    'store', jsonb_strip_nulls(jsonb_build_object(
      'name', v_tenant.shop_name,
      'logoUrl', case
        when v_tenant.logo_url ~* '^https://[^[:space:]]+$' then v_tenant.logo_url
        else (
          select setting.value from public.website_settings setting
           where setting.tenant_id = v_notice.tenant_id
             and setting.key = 'company_logo_url'
             and setting.value ~* '^https://[^[:space:]]+$'
           limit 1
        )
      end,
      'storeUrl', v_store,
      'timezone', coalesce(v_tenant.timezone, 'America/Santiago'),
      'brandColor', (
        select case
          when setting.value ~ '^#[0-9A-Fa-f]{6}$' then upper(setting.value)
          when setting.value ~ '^[0-9]{1,10}$'
            then '#' || upper(lpad(to_hex(setting.value::bigint & 16777215), 6, '0'))
        end
          from public.website_settings setting
         where setting.tenant_id = v_notice.tenant_id and setting.key = 'theme_primary_color'
         limit 1
      )
    )),
    'job', jsonb_strip_nulls(jsonb_build_object(
      'number', v_job.job_number,
      -- Entero: el correo saluda con el nombre de pila, nombres compuestos
      -- incluidos, con la misma regla que las plantillas de WhatsApp.
      'customerName', nullif(btrim(v_customer.name), ''),
      'item', public.workshop_notice_item_internal(v_job),
      'intake', coalesce(v_job.intake_kind, 'bike'),
      'request', nullif(btrim(v_job.client_request), ''),
      'receivedAt', coalesce(v_job.arrival_date, v_job.created_at),
      'total', case
        when v_notice.kind = 'quote_ready' and coalesce(v_job.total_cost, 0) > 0 then v_job.total_cost
      end
    )),
    'delivery', case when v_notice.kind = 'delivered' and v_document.id is not null then
      jsonb_strip_nulls(jsonb_build_object(
        'deliveredAt', v_document.delivered_at,
        'workPerformed', coalesce(
          nullif(btrim(v_document.snapshot->>'work_performed'), ''),
          nullif(btrim(v_job.work_performed), '')),
        'serviceWarrantyUntil', case
          when v_document.service_warranty_days > 0 then v_document.service_warranty_expires_at
        end,
        'partsWarrantyUntil', case
          when v_has_parts and v_document.parts_warranty_months > 0 then v_document.parts_warranty_expires_at
        end
      ))
    end,
    'link', v_link,
    'linkKind', case when v_link like '%/cuenta/vincular#c=%' then 'claim' else 'portal' end,
    'preferencesLink', case when v_store is null then null else v_store || '/cuenta/perfil' end
  );
end;
$$;

revoke all on function public.workshop_notice_email_payload_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.claim_workshop_customer_notices_v1(
  p_tenant_id uuid,
  p_worker_id text,
  p_limit integer default 10,
  p_now timestamptz default clock_timestamp()
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_candidate record;
  v_job public.mechanic_jobs%rowtype;
  v_reason text;
  v_ids uuid[] := array[]::uuid[];
  v_limit integer := greatest(1, least(coalesce(p_limit, 10), 25));
begin
  if p_tenant_id is null or nullif(btrim(coalesce(p_worker_id, '')), '') is null then
    raise exception 'A tenant and a worker id are required' using errcode = '22023';
  end if;

  -- Correo apagado: lo que estaba por salir no sale.
  if not coalesce((select settings.email_enabled
                     from public.workshop_notice_settings_internal(p_tenant_id) settings), false) then
    update public.workshop_customer_notices notice
       set state = 'skipped', reason = 'channel_off', updated_at = clock_timestamp()
     where notice.tenant_id = p_tenant_id
       and notice.channel = 'email'
       and notice.state = 'pending';
    return '[]'::jsonb;
  end if;

  for v_candidate in
    select notice.id, notice.job_id, notice.kind, notice.expires_at
      from public.workshop_customer_notices notice
     where notice.tenant_id = p_tenant_id
       and notice.channel = 'email'
       and notice.attempt_count < notice.max_attempts
       and notice.available_at <= p_now
       and (notice.state = 'pending'
            or (notice.state = 'sending' and notice.lease_until < clock_timestamp()))
     order by notice.available_at
     limit v_limit
     for update skip locked
  loop
    select * into v_job from public.mechanic_jobs
     where id = v_candidate.job_id and tenant_id = p_tenant_id;
    v_reason := public.workshop_notice_stale_reason_internal(v_candidate.kind, v_job);
    if v_reason is null and p_now >= v_candidate.expires_at then
      v_reason := 'expired';
    end if;
    if v_reason is not null then
      update public.workshop_customer_notices
         set state = 'skipped', reason = v_reason, lease_owner = null, lease_until = null,
             updated_at = clock_timestamp()
       where id = v_candidate.id;
      continue;
    end if;
    update public.workshop_customer_notices
       set state = 'sending',
           lease_owner = p_worker_id,
           lease_until = clock_timestamp() + interval '120 seconds',
           attempt_count = attempt_count + 1,
           updated_at = clock_timestamp()
     where id = v_candidate.id;
    v_ids := v_ids || v_candidate.id;
  end loop;

  return coalesce((
    select jsonb_agg(public.workshop_notice_email_payload_internal(id))
      from unnest(v_ids) as id
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.claim_workshop_customer_notices_v1(uuid, text, integer, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_workshop_customer_notices_v1(uuid, text, integer, timestamptz) to service_role;

comment on function public.claim_workshop_customer_notices_v1(uuid, text, integer, timestamptz) is
  'El worker de correo toma los avisos del taller que ya tocan, con el enlace recién emitido. Lo que dejó de corresponder se omite con su motivo.';

create or replace function public.complete_workshop_customer_notice_v1(
  p_notice_id uuid,
  p_worker_id text,
  p_outcome text,
  p_provider_message_id text default null,
  p_error text default null
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_notice public.workshop_customer_notices%rowtype;
begin
  select * into v_notice from public.workshop_customer_notices
   where id = p_notice_id and lease_owner = p_worker_id and state = 'sending'
   for update;
  if not found then
    return 'not_leased';
  end if;
  if p_outcome = 'sent' then
    update public.workshop_customer_notices
       set state = 'sent', sent_at = clock_timestamp(),
           provider_message_id = left(p_provider_message_id, 200),
           lease_owner = null, lease_until = null, reason = null, updated_at = clock_timestamp()
     where id = p_notice_id;
  elsif p_outcome = 'retry' and v_notice.attempt_count < v_notice.max_attempts then
    update public.workshop_customer_notices
       set state = 'pending', lease_owner = null, lease_until = null,
           available_at = clock_timestamp()
             + make_interval(mins => least(60, 2 ^ v_notice.attempt_count)::integer),
           reason = left(p_error, 300), updated_at = clock_timestamp()
     where id = p_notice_id;
  elsif p_outcome = 'skipped' then
    update public.workshop_customer_notices
       set state = 'skipped', lease_owner = null, lease_until = null,
           reason = left(coalesce(p_error, 'skipped'), 300), updated_at = clock_timestamp()
     where id = p_notice_id;
  else
    update public.workshop_customer_notices
       set state = 'failed', lease_owner = null, lease_until = null,
           reason = left(coalesce(p_error, 'failed'), 300), updated_at = clock_timestamp()
     where id = p_notice_id;
  end if;
  return (select state from public.workshop_customer_notices where id = p_notice_id);
end;
$$;

revoke all on function public.complete_workshop_customer_notice_v1(uuid, text, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.complete_workshop_customer_notice_v1(uuid, text, text, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- 7. Lo que ve el ERP: la tarjeta de Avisos y garantía
-- ---------------------------------------------------------------------------

create or replace function public.workshop_customer_notice_overview_v1(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_settings record;
begin
  if not public.messaging_is_staff_in_tenant(p_tenant_id) then
    raise exception 'workshop_notices_not_allowed' using errcode = '42501';
  end if;
  select * into v_settings from public.workshop_notice_settings_internal(p_tenant_id);
  return jsonb_build_object(
    'started_at', v_settings.started_at,
    'can_edit', public.can_edit_tenant_settings(p_tenant_id),
    'email_switch', coalesce((
      select btrim(setting.value) <> 'false' from public.company_settings setting
       where setting.tenant_id = p_tenant_id and setting.key = 'workshop_notices_email_enabled'
    ), true),
    'whatsapp_switch', coalesce((
      select btrim(setting.value) <> 'false' from public.company_settings setting
       where setting.tenant_id = p_tenant_id and setting.key = 'workshop_notices_whatsapp_enabled'
    ), true),
    'email_ready', exists (
      select 1 from public.transactional_email_settings email
       where email.tenant_id = p_tenant_id and email.enabled
         and email.delivery_mode = 'send' and email.from_email is not null),
    'whatsapp_ready', exists (
      select 1 from public.whatsapp_channels channel
       where channel.tenant_id = p_tenant_id and channel.is_active),
    'counts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'kind', kind, 'channel', channel, 'state', state, 'reason', reason, 'count', total)
             order by kind, channel, state, reason)
        from (
          select notice.kind, notice.channel, notice.state, notice.reason, count(*) as total
            from public.workshop_customer_notices notice
           where notice.tenant_id = p_tenant_id
             and notice.created_at > clock_timestamp() - interval '30 days'
           group by 1, 2, 3, 4
        ) grouped
    ), '[]'::jsonb),
    'last_sent_at', (
      select max(notice.sent_at) from public.workshop_customer_notices notice
       where notice.tenant_id = p_tenant_id and notice.state = 'sent'),
    'templates', coalesce((
      select jsonb_agg(jsonb_build_object(
               'name', review.template_name, 'status', review.status,
               'rejected_reason', review.rejected_reason, 'checked_at', review.checked_at)
             order by review.template_name)
        from public.whatsapp_template_reviews review
       where review.tenant_id = p_tenant_id
         and review.template_language = 'es_CL'
         and review.template_name in (
           'taller_recibida_v1', 'taller_presupuesto_v1', 'taller_lista_v1', 'taller_entregada_v1',
           'seguimiento_presupuesto_bicicleta', 'bicicleta_lista_retiro')
    ), '[]'::jsonb),
    'warranty', (
      select jsonb_build_object('service_days', policy.service_days, 'parts_months', policy.parts_months)
        from public.workshop_warranty_policy_v1(p_tenant_id) policy
    )
  );
end;
$$;

revoke all on function public.workshop_customer_notice_overview_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.workshop_customer_notice_overview_v1(uuid) to authenticated;

comment on function public.workshop_customer_notice_overview_v1(uuid) is
  'La tarjeta de Avisos y garantía del ERP: qué está encendido, qué salió en 30 días por momento y canal, cómo están las plantillas en Meta y la garantía vigente.';

-- Encender o apagar un canal, y la garantía del taller: quien puede editar
-- la configuración de la tienda.
create or replace function public.update_workshop_customer_notice_settings_v1(
  p_tenant_id uuid,
  p_settings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_service integer;
  v_parts integer;
  v_key text;
  v_value text;
begin
  if not public.can_edit_tenant_settings(p_tenant_id) then
    raise exception 'workshop_notices_not_allowed' using errcode = '42501';
  end if;
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'workshop_notices_invalid' using errcode = '22023', detail = 'settings';
  end if;

  if p_settings ? 'email_enabled' then
    if jsonb_typeof(p_settings->'email_enabled') <> 'boolean' then
      raise exception 'workshop_notices_invalid' using errcode = '22023', detail = 'email_enabled';
    end if;
  end if;
  if p_settings ? 'whatsapp_enabled' then
    if jsonb_typeof(p_settings->'whatsapp_enabled') <> 'boolean' then
      raise exception 'workshop_notices_invalid' using errcode = '22023', detail = 'whatsapp_enabled';
    end if;
  end if;
  if p_settings ? 'service_warranty_days' then
    if jsonb_typeof(p_settings->'service_warranty_days') <> 'number'
       or (p_settings->>'service_warranty_days') !~ '^[0-9]{1,3}$' then
      raise exception 'workshop_notices_invalid' using errcode = '22023', detail = 'service_warranty_days';
    end if;
    v_service := (p_settings->>'service_warranty_days')::integer;
    if v_service not between 0 and 365 then
      raise exception 'workshop_notices_invalid' using errcode = '22023', detail = 'service_warranty_days';
    end if;
  end if;
  if p_settings ? 'parts_warranty_months' then
    if jsonb_typeof(p_settings->'parts_warranty_months') <> 'number'
       or (p_settings->>'parts_warranty_months') !~ '^[0-9]{1,2}$' then
      raise exception 'workshop_notices_invalid' using errcode = '22023', detail = 'parts_warranty_months';
    end if;
    v_parts := (p_settings->>'parts_warranty_months')::integer;
    if v_parts not between 0 and 24 then
      raise exception 'workshop_notices_invalid' using errcode = '22023', detail = 'parts_warranty_months';
    end if;
  end if;

  for v_key, v_value in
    select key, value from (values
      ('workshop_notices_email_enabled', p_settings->>'email_enabled'),
      ('workshop_notices_whatsapp_enabled', p_settings->>'whatsapp_enabled'),
      ('workshop_service_warranty_days', v_service::text),
      ('workshop_parts_warranty_months', v_parts::text)
    ) pair(key, value)
     where value is not null
  loop
    insert into public.company_settings (tenant_id, key, value, updated_at)
    values (p_tenant_id, v_key, v_value, clock_timestamp())
    on conflict (tenant_id, key) do update
       set value = excluded.value, updated_at = excluded.updated_at;
  end loop;

  -- Una tienda que los enciende por primera vez avisa desde ahora, nunca por
  -- lo de antes.
  if (p_settings->>'email_enabled' = 'true' or p_settings->>'whatsapp_enabled' = 'true') then
    insert into public.company_settings (tenant_id, key, value, updated_at)
    values (p_tenant_id, 'workshop_notices_started_at',
            to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
            clock_timestamp())
    on conflict (tenant_id, key) do nothing;
  end if;

  return public.workshop_customer_notice_overview_v1(p_tenant_id);
end;
$$;

revoke all on function public.update_workshop_customer_notice_settings_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.update_workshop_customer_notice_settings_v1(uuid, jsonb) to authenticated;

comment on function public.update_workshop_customer_notice_settings_v1(uuid, jsonb) is
  'Enciende o apaga los avisos del taller por correo o WhatsApp y cambia la garantía (días del servicio, meses de los repuestos). Una entrega ya hecha conserva la suya.';

-- ---------------------------------------------------------------------------
-- 8. Encender
-- ---------------------------------------------------------------------------

-- Desde ahora: lo que pasó antes de este momento no avisa.
insert into public.company_settings (tenant_id, key, value, updated_at)
select tenant.id, 'workshop_notices_started_at',
       to_char(clock_timestamp() at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
       clock_timestamp()
  from public.tenants tenant
on conflict (tenant_id, key) do nothing;

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; workshop customer notices were not scheduled';
    return;
  end if;
  for v_job in
    select jobid from cron.job where jobname = 'vinabike_workshop_customer_notices'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'vinabike_workshop_customer_notices',
    '* * * * *',
    $job$select public.process_workshop_customer_notices_v1()$job$
  );
end
$$;

commit;
