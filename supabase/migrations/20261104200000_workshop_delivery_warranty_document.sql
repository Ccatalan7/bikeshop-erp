-- Comprobante de entrega y garantía del taller (2026-11-04).
--
-- El taller entregaba la bici con la factura, que prueba el pago pero no dice
-- qué cubre ni hasta cuándo; el compañero del taller lo pidió «para evitarse
-- problemas», y el artículo 41 de la Ley 19.496 pide dejar por escrito el plazo
-- en que el taller responde por la reparación. El ERP ya abría una ventana de
-- garantía de 14 días en cada primera entrega
-- (`capture_mechanic_job_delivery_event`), escrita a mano y sin documento.
--
-- 1. La política del taller, por tienda, en `company_settings`:
--    `workshop_service_warranty_days` (14) y `workshop_parts_warranty_months`
--    (2). La eligió el dueño: «2 semanas de servicios y 2 meses los repuestos…
--    después podemos hacer excepciones». Las excepciones del servicio ya
--    existen (`warranty_extended`).
-- 2. La primera entrega guarda además la garantía de los repuestos y deja un
--    comprobante con la foto del trabajo en ese momento
--    (`mechanic_job_delivery_documents`): lo que se hizo, los repuestos y las
--    dos fechas. Una re-entrega no abre otro. Si armarlo falla, la entrega
--    igual queda: el comprobante se arma después a pedido.
-- 3. Un código para ligar la cuenta del portal a la ficha del cliente
--    (`customer_portal_claim_codes`), que va en el QR de la recepción y del
--    comprobante. Hasta hoy el portal ligaba sólo por correo, y de 1.800
--    clientes activos 83 tienen correo y 464 sólo teléfono: quien dejó sólo su
--    número quedaba como cliente nuevo y vacío. Tener el código prueba que es
--    el cliente; si la ficha tiene teléfono, también tiene que calzar.
-- 4. El cliente con cuenta lee su comprobante y sus facturas por funciones que
--    devuelven sólo lo suyo y sólo lo que le corresponde ver: las líneas de una
--    factura guardan el costo interno (`cost`), así que la fila nunca se le
--    abre entera.

-- ---------------------------------------------------------------------------
-- 1. La política de garantía del taller
-- ---------------------------------------------------------------------------

create or replace function public.workshop_warranty_policy_v1(p_tenant_id uuid)
returns table (service_days integer, parts_months integer)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    coalesce((
      select least(greatest(trim(setting.value)::integer, 0), 365)
        from public.company_settings setting
       where setting.tenant_id = p_tenant_id
         and setting.key = 'workshop_service_warranty_days'
         and trim(setting.value) ~ '^[0-9]{1,3}$'
       order by setting.updated_at desc nulls last
       limit 1
    ), 14),
    coalesce((
      select least(greatest(trim(setting.value)::integer, 0), 24)
        from public.company_settings setting
       where setting.tenant_id = p_tenant_id
         and setting.key = 'workshop_parts_warranty_months'
         and trim(setting.value) ~ '^[0-9]{1,2}$'
       order by setting.updated_at desc nulls last
       limit 1
    ), 2);
$$;

revoke all on function public.workshop_warranty_policy_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.workshop_warranty_policy_v1(uuid)
  to authenticated, service_role;

comment on function public.workshop_warranty_policy_v1(uuid) is
  'La garantía del taller de la tienda: días del servicio (14) y meses de los repuestos (2), de company_settings.';

-- ---------------------------------------------------------------------------
-- 2. La garantía de los repuestos en la entrega
-- ---------------------------------------------------------------------------

alter table public.mechanic_job_delivery_events
  add column if not exists parts_warranty_months_snapshot integer,
  add column if not exists parts_warranty_expires_at timestamptz;

alter table public.mechanic_job_delivery_events
  drop constraint if exists mechanic_job_delivery_events_parts_warranty_check;
alter table public.mechanic_job_delivery_events
  add constraint mechanic_job_delivery_events_parts_warranty_check check (
    (parts_warranty_months_snapshot is null and parts_warranty_expires_at is null)
    or (
      parts_warranty_months_snapshot between 0 and 24
      and parts_warranty_expires_at is not null
    )
  );

comment on column public.mechanic_job_delivery_events.parts_warranty_months_snapshot is
  'Meses de garantía de los repuestos con que se entregó (la política de ese momento).';

-- ---------------------------------------------------------------------------
-- 3. El comprobante de entrega y garantía
-- ---------------------------------------------------------------------------

create table if not exists public.mechanic_job_delivery_documents (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  job_id uuid not null references public.mechanic_jobs(id) on delete restrict,
  delivery_event_id uuid not null
    references public.mechanic_job_delivery_events(id) on delete restrict,
  job_number text,
  delivered_at timestamptz not null,
  service_warranty_days integer not null
    check (service_warranty_days between 0 and 365),
  service_warranty_expires_at timestamptz not null,
  parts_warranty_months integer not null
    check (parts_warranty_months between 0 and 24),
  parts_warranty_expires_at timestamptz not null,
  snapshot jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid references auth.users(id) on delete set null,
  constraint mechanic_job_delivery_documents_one_per_job unique (tenant_id, job_id),
  constraint mechanic_job_delivery_documents_event_key unique (delivery_event_id),
  constraint mechanic_job_delivery_documents_snapshot_object
    check (jsonb_typeof(snapshot) = 'object')
);

alter table public.mechanic_job_delivery_documents enable row level security;

drop policy if exists mechanic_job_delivery_documents_select
  on public.mechanic_job_delivery_documents;
create policy mechanic_job_delivery_documents_select
  on public.mechanic_job_delivery_documents
  for select
  to authenticated
  using (public.is_active_tenant_member(tenant_id));

revoke all on table public.mechanic_job_delivery_documents from anon, authenticated;
grant select on table public.mechanic_job_delivery_documents to authenticated;
grant all on table public.mechanic_job_delivery_documents to service_role;

comment on table public.mechanic_job_delivery_documents is
  'Comprobante de entrega y garantía: la foto del trabajo en su primera entrega. Lo crea la entrega; nadie lo escribe a mano.';

-- La foto del trabajo para el cliente: quién, qué bicis, qué se hizo y con qué
-- repuestos. Sin precios (están en la factura) ni datos internos.
create or replace function public.job_delivery_document_snapshot_internal(
  p_tenant_id uuid,
  p_job_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'job_number', job.job_number,
    'customer', jsonb_build_object('name', nullif(trim(customer.name), '')),
    'work_performed', nullif(trim(job.work_performed), ''),
    'subject_notes', nullif(trim(job.subject_notes), ''),
    'bikes', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'job_bike_id', job_bike.id,
            'brand', nullif(trim(bike.brand), ''),
            'model', nullif(trim(bike.model), ''),
            'year', bike.year,
            'color', nullif(trim(bike.color), ''),
            'serial_number', nullif(trim(bike.serial_number), ''),
            'work_requested', nullif(trim(job_bike.work_requested), ''),
            'work_performed', nullif(trim(job_bike.work_performed), '')
          )
          order by job_bike.order_index, job_bike.created_at
        )
          from public.mechanic_job_bikes job_bike
          left join public.bikes bike
            on bike.id = job_bike.bike_id
           and bike.tenant_id = job_bike.tenant_id
         where job_bike.tenant_id = job.tenant_id
           and job_bike.job_id = job.id
      ),
      (
        select jsonb_build_array(
          jsonb_build_object(
            'job_bike_id', null,
            'brand', nullif(trim(bike.brand), ''),
            'model', nullif(trim(bike.model), ''),
            'year', bike.year,
            'color', nullif(trim(bike.color), ''),
            'serial_number', nullif(trim(bike.serial_number), ''),
            'work_requested', nullif(trim(job.client_request), ''),
            'work_performed', nullif(trim(job.work_performed), '')
          )
        )
          from public.bikes bike
         where bike.id = job.bike_id
           and bike.tenant_id = job.tenant_id
      ),
      '[]'::jsonb
    ),
    'lines', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'kind', case item.item_type
              when 'service' then 'service'
              when 'product' then 'part'
              else 'other'
            end,
            'name', coalesce(
              nullif(trim(item.product_name), ''),
              nullif(trim(item.description), '')
            ),
            'quantity', item.quantity,
            'job_bike_id', item.job_bike_id
          )
          order by item.created_at, item.id
        )
          from public.mechanic_job_items item
         where item.tenant_id = job.tenant_id
           and item.job_id = job.id
      ),
      '[]'::jsonb
    )
  )
    from public.mechanic_jobs job
    left join public.customers customer
      on customer.id = job.customer_id
     and customer.tenant_id = job.tenant_id
   where job.tenant_id = p_tenant_id
     and job.id = p_job_id;
$$;

revoke all on function public.job_delivery_document_snapshot_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Arma el comprobante de una primera entrega. Devuelve su id, o null si esa
-- entrega no abre garantía (re-entrega, venta).
create or replace function public.create_job_delivery_document_internal(p_event_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_event public.mechanic_job_delivery_events%rowtype;
  v_job public.mechanic_jobs%rowtype;
  v_parts_months integer;
  v_parts_expires timestamptz;
  v_id uuid;
begin
  select * into v_event
    from public.mechanic_job_delivery_events
   where id = p_event_id;
  if not found
     or not v_event.starts_warranty_window
     or v_event.event_kind <> 'delivered' then
    return null;
  end if;

  select * into v_job
    from public.mechanic_jobs
   where id = v_event.job_id
     and tenant_id = v_event.tenant_id;
  if not found or v_job.workflow_kind = 'sale' then
    return null;
  end if;

  -- Una entrega de antes de esta migración no anotó los repuestos: va la
  -- política de hoy, contada desde esa entrega.
  v_parts_months := coalesce(
    v_event.parts_warranty_months_snapshot,
    (select policy.parts_months
       from public.workshop_warranty_policy_v1(v_event.tenant_id) policy)
  );
  v_parts_expires := coalesce(
    v_event.parts_warranty_expires_at,
    v_event.warranty_started_at + make_interval(months => v_parts_months)
  );

  insert into public.mechanic_job_delivery_documents (
    tenant_id,
    job_id,
    delivery_event_id,
    job_number,
    delivered_at,
    service_warranty_days,
    service_warranty_expires_at,
    parts_warranty_months,
    parts_warranty_expires_at,
    snapshot,
    created_by
  ) values (
    v_event.tenant_id,
    v_job.id,
    v_event.id,
    v_job.job_number,
    v_event.warranty_started_at,
    v_event.warranty_days_snapshot,
    v_event.warranty_expires_at,
    v_parts_months,
    v_parts_expires,
    public.job_delivery_document_snapshot_internal(v_event.tenant_id, v_job.id),
    auth.uid()
  )
  on conflict (tenant_id, job_id) do nothing
  returning id into v_id;

  if v_id is null then
    select document.id into v_id
      from public.mechanic_job_delivery_documents document
     where document.tenant_id = v_event.tenant_id
       and document.job_id = v_job.id;
  end if;
  return v_id;
end;
$$;

revoke all on function public.create_job_delivery_document_internal(uuid)
  from public, anon, authenticated, service_role;

-- La entrega, ahora con la política de la tienda y el comprobante. Igual que
-- la versión de producción salvo: los días salen de la política, se anotan los
-- repuestos y se arma el comprobante. Armarlo nunca impide entregar.
create or replace function public.capture_mechanic_job_delivery_event()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_old_delivered boolean := false;
  v_new_delivered boolean;
  v_has_delivery boolean;
  v_starts_warranty boolean;
  v_occurred_at timestamptz := clock_timestamp();
  v_service_days integer;
  v_parts_months integer;
  v_event_id uuid;
begin
  if tg_op = 'UPDATE' then
    v_old_delivered := public.mechanic_job_resolves_delivery(
      old.status,
      old.status_id
    );
  end if;

  v_new_delivered := public.mechanic_job_resolves_delivery(
    new.status,
    new.status_id
  );

  if v_old_delivered or not v_new_delivered then
    return new;
  end if;

  select exists (
    select 1
    from public.mechanic_job_delivery_events event
    where event.tenant_id = new.tenant_id
      and event.job_id = new.id
      and event.event_kind in ('delivered', 'redelivered')
  ) into v_has_delivery;

  v_starts_warranty := not v_has_delivery
    and new.workflow_kind <> 'sale';

  if v_starts_warranty then
    select policy.service_days, policy.parts_months
      into v_service_days, v_parts_months
      from public.workshop_warranty_policy_v1(new.tenant_id) policy;
  end if;

  insert into public.mechanic_job_delivery_events (
    tenant_id,
    job_id,
    event_kind,
    occurred_at,
    actor_id,
    starts_warranty_window,
    warranty_days_snapshot,
    warranty_started_at,
    warranty_expires_at,
    parts_warranty_months_snapshot,
    parts_warranty_expires_at,
    source,
    operation_key,
    metadata
  ) values (
    new.tenant_id,
    new.id,
    case when v_has_delivery then 'redelivered' else 'delivered' end,
    v_occurred_at,
    auth.uid(),
    v_starts_warranty,
    case when v_starts_warranty then v_service_days else null end,
    case when v_starts_warranty then v_occurred_at else null end,
    case when v_starts_warranty
      then v_occurred_at + make_interval(days => v_service_days)
      else null
    end,
    case when v_starts_warranty then v_parts_months else null end,
    case when v_starts_warranty
      then v_occurred_at + make_interval(months => v_parts_months)
      else null
    end,
    'status_transition',
    format(
      'delivery:auto:%s:%s:%s',
      new.id,
      txid_current(),
      gen_random_uuid()
    ),
    jsonb_build_object(
      'legacy_status', new.status,
      'custom_status_id', new.status_id,
      'warranty_reset', v_starts_warranty,
      'workflow_kind', new.workflow_kind,
      'sale_collection', new.workflow_kind = 'sale'
    )
  )
  returning id into v_event_id;

  if v_starts_warranty then
    begin
      perform public.create_job_delivery_document_internal(v_event_id);
    exception when others then
      -- La bici ya se entregó: el comprobante se arma después, a pedido
      -- (ensure_job_delivery_document_v1).
      raise warning 'delivery document for job % not created: %', new.id, sqlerrm;
    end;
  end if;

  return new;
end;
$function$;

-- Lo que se muestra de un comprobante, al equipo y al cliente. La garantía del
-- servicio es la vigente (una extensión la cambia); la de los repuestos, la
-- del comprobante.
create or replace function public.job_delivery_document_projection_internal(p_document_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'id', document.id,
    'job_id', document.job_id,
    'job_number', document.job_number,
    'delivered_at', document.delivered_at,
    'service_warranty_days', document.service_warranty_days,
    'service_warranty_expires_at',
      coalesce(warranty.warranty_expires_at, document.service_warranty_expires_at),
    'service_warranty_days_remaining', greatest(
      ceil(extract(epoch from (
        coalesce(warranty.warranty_expires_at, document.service_warranty_expires_at)
        - clock_timestamp()
      )) / 86400.0),
      0
    )::integer,
    'parts_warranty_months', document.parts_warranty_months,
    'parts_warranty_expires_at', document.parts_warranty_expires_at,
    'parts_warranty_days_remaining', greatest(
      ceil(extract(epoch from (document.parts_warranty_expires_at - clock_timestamp())) / 86400.0),
      0
    )::integer,
    'invoice_id', job.invoice_id,
    'snapshot', document.snapshot
  )
    from public.mechanic_job_delivery_documents document
    join public.mechanic_jobs job
      on job.id = document.job_id
     and job.tenant_id = document.tenant_id
    left join public.mechanic_job_service_warranty_view warranty
      on warranty.job_id = document.job_id
     and warranty.tenant_id = document.tenant_id
   where document.id = p_document_id;
$$;

revoke all on function public.job_delivery_document_projection_internal(uuid)
  from public, anon, authenticated, service_role;

-- El equipo pide el comprobante de un trabajo entregado: si no existe (se
-- entregó antes de esta migración, o armarlo falló al entregar), se arma
-- ahora con la entrega original.
create or replace function public.ensure_job_delivery_document_v1(p_job_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_event_id uuid;
  v_document_id uuid;
  v_customer public.customers%rowtype;
begin
  select * into v_job from public.mechanic_jobs where id = p_job_id;
  if not found or not public.is_active_tenant_member(v_job.tenant_id) then
    raise exception 'Job not found or not accessible' using errcode = 'P0002';
  end if;

  select document.id into v_document_id
    from public.mechanic_job_delivery_documents document
   where document.tenant_id = v_job.tenant_id
     and document.job_id = v_job.id;

  if v_document_id is null then
    select event.id into v_event_id
      from public.mechanic_job_delivery_events event
     where event.tenant_id = v_job.tenant_id
       and event.job_id = v_job.id
       and event.event_kind = 'delivered'
       and event.starts_warranty_window
     order by event.occurred_at asc, event.recorded_at asc, event.id asc
     limit 1;
    if v_event_id is null then
      raise exception 'job_not_delivered' using errcode = 'P0001';
    end if;
    v_document_id := public.create_job_delivery_document_internal(v_event_id);
    if v_document_id is null then
      raise exception 'job_without_warranty' using errcode = 'P0001';
    end if;
  end if;

  select * into v_customer
    from public.customers
   where id = v_job.customer_id
     and tenant_id = v_job.tenant_id;

  return public.job_delivery_document_projection_internal(v_document_id)
    || jsonb_build_object(
      'customer_has_account', coalesce(v_customer.auth_user_id is not null, false),
      'customer_phone', nullif(trim(v_customer.phone), ''),
      'customer_email', nullif(trim(v_customer.email), '')
    );
end;
$$;

revoke all on function public.ensure_job_delivery_document_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.ensure_job_delivery_document_v1(uuid)
  to authenticated, service_role;

comment on function public.ensure_job_delivery_document_v1(uuid) is
  'El comprobante de entrega y garantía de un trabajo entregado, para el equipo; lo arma si falta.';

-- ---------------------------------------------------------------------------
-- 4. Ligar la cuenta del portal a la ficha con el QR
-- ---------------------------------------------------------------------------

create table if not exists public.customer_portal_claim_codes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete cascade,
  job_id uuid references public.mechanic_jobs(id) on delete set null,
  purpose text not null check (purpose in ('reception', 'delivery', 'manual')),
  code_sha256 text not null,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  claimed_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid references auth.users(id) on delete set null,
  constraint customer_portal_claim_codes_hash check (code_sha256 ~ '^[0-9a-f]{64}$'),
  constraint customer_portal_claim_codes_hash_key unique (code_sha256)
);

create index if not exists idx_customer_portal_claim_codes_open
  on public.customer_portal_claim_codes (tenant_id, customer_id)
  where claimed_at is null and revoked_at is null;

alter table public.customer_portal_claim_codes enable row level security;
revoke all on table public.customer_portal_claim_codes from anon, authenticated;
grant all on table public.customer_portal_claim_codes to service_role;

comment on table public.customer_portal_claim_codes is
  'Códigos del QR que ligan una cuenta del portal a la ficha del cliente. Sólo se guarda su huella; se leen por funciones.';

create table if not exists public.customer_portal_claim_attempts (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  auth_user_id uuid not null,
  outcome text not null,
  attempted_at timestamptz not null default clock_timestamp()
);

create index if not exists idx_customer_portal_claim_attempts_user
  on public.customer_portal_claim_attempts (auth_user_id, attempted_at desc);

alter table public.customer_portal_claim_attempts enable row level security;
revoke all on table public.customer_portal_claim_attempts from anon, authenticated;
grant all on table public.customer_portal_claim_attempts to service_role;

-- El equipo saca un código para el QR de un trabajo. No hace falta si el
-- cliente ya tiene cuenta: entonces dice «already_linked».
create or replace function public.issue_customer_portal_claim_code_v1(
  p_job_id uuid,
  p_purpose text default 'reception'
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_job public.mechanic_jobs%rowtype;
  v_customer public.customers%rowtype;
  v_raw text;
  v_expires timestamptz := clock_timestamp() + interval '120 days';
begin
  if p_purpose is null or p_purpose not in ('reception', 'delivery', 'manual') then
    raise exception 'Invalid claim-code purpose' using errcode = '22023';
  end if;

  select * into v_job from public.mechanic_jobs where id = p_job_id;
  if not found or not public.is_active_tenant_member(v_job.tenant_id) then
    raise exception 'Job not found or not accessible' using errcode = 'P0002';
  end if;

  select * into v_customer
    from public.customers
   where id = v_job.customer_id
     and tenant_id = v_job.tenant_id;
  if not found or v_customer.is_active is not true then
    return jsonb_build_object('status', 'no_customer');
  end if;
  if v_customer.auth_user_id is not null then
    return jsonb_build_object('status', 'already_linked');
  end if;

  v_raw := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.customer_portal_claim_codes (
    tenant_id, customer_id, job_id, purpose, code_sha256, expires_at, created_by
  ) values (
    v_job.tenant_id,
    v_customer.id,
    v_job.id,
    p_purpose,
    encode(extensions.digest(convert_to(v_raw, 'UTF8'), 'sha256'), 'hex'),
    v_expires,
    auth.uid()
  );

  return jsonb_build_object('status', 'issued', 'code', v_raw, 'expires_at', v_expires);
end;
$$;

revoke all on function public.issue_customer_portal_claim_code_v1(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.issue_customer_portal_claim_code_v1(uuid, text)
  to authenticated, service_role;

comment on function public.issue_customer_portal_claim_code_v1(uuid, text) is
  'Código de 120 días para el QR que liga la cuenta del portal a la ficha del cliente del trabajo.';

-- La guardia de identidad del cliente no dejaba cambiar la cuenta de una ficha
-- a nadie con sesión. Ligar con el QR es la única excepción, y la reconoce por
-- una marca privada que pone sólo claim_customer_portal_code_v1, para esta
-- transacción y esta ficha: nunca por algo que mande quien llama. Igual que la
-- versión de producción salvo esa excepción.
create or replace function public.guard_customer_identity_update()
returns trigger
language plpgsql
security definer
set search_path to 'pg_catalog', 'public', 'pg_temp'
as $function$
begin
  if auth.uid() is null or auth.role() is distinct from 'authenticated' then
    return new;
  end if;

  if new.tenant_id is distinct from old.tenant_id
     or new.auth_user_id is distinct from old.auth_user_id then
    if new.tenant_id is not distinct from old.tenant_id
       and coalesce(current_setting('vinabike.portal_claim_relink', true), '')
         = txid_current()::text || ':' || old.id::text then
      return new;
    end if;
    raise exception 'Customer tenant and Auth identity are immutable'
      using errcode = '42501';
  end if;

  if old.auth_user_id = auth.uid()
     and not public.is_active_tenant_member(old.tenant_id)
     and (
       to_jsonb(new) - array[
         'name',
         'phone',
         'rut',
         'image_url',
         'updated_at'
       ]::text[]
     ) is distinct from (
       to_jsonb(old) - array[
         'name',
         'phone',
         'rut',
         'image_url',
         'updated_at'
       ]::text[]
     ) then
    raise exception 'Customer self-service may update profile fields only'
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

-- El cliente, con su cuenta y su correo confirmado, usa el código del QR.
--
-- Estados: linked, already_yours, invalid, expired, phone_mismatch,
-- linked_elsewhere (la ficha ya es de otra cuenta), account_has_history (su
-- cuenta ya tiene trabajos o compras en otra ficha: lo une el equipo),
-- email_in_other_record (su correo está en otra ficha de la tienda: también lo
-- une el equipo) y too_many_attempts (10 fallos en una hora).
--
-- La ficha del taller queda con el correo confirmado de la cuenta, y la
-- cuenta se termina de preparar con provision_current_public_store_customer,
-- que es quien la arma cada vez que el cliente entra: ese camino pone el
-- correo de la cuenta en su ficha y la guardia no deja que el cliente cambie
-- su correo, así que si la ficha quedara con otro, el portal fallaría en su
-- próxima entrada.
create or replace function public.claim_customer_portal_code_v1(
  p_tenant_id uuid,
  p_code text,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_email text;
  v_code public.customer_portal_claim_codes%rowtype;
  v_customer public.customers%rowtype;
  v_current public.customers%rowtype;
  v_has_current boolean := false;
  v_typed_digits text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_record_digits text;
  v_failures integer;
  v_outcome text;
begin
  if v_uid is null then
    raise exception 'claim_account_required' using errcode = '42501';
  end if;

  select lower(nullif(trim(auth_user.email), '')) into v_email
    from auth.users auth_user
   where auth_user.id = v_uid
     and auth_user.email_confirmed_at is not null;
  if v_email is null then
    raise exception 'A confirmed Auth email is required' using errcode = '42501';
  end if;

  select count(*) into v_failures
    from public.customer_portal_claim_attempts attempt
   where attempt.auth_user_id = v_uid
     and attempt.attempted_at > clock_timestamp() - interval '1 hour'
     and attempt.outcome not in ('linked', 'already_yours');
  if v_failures >= 10 then
    return jsonb_build_object('status', 'too_many_attempts');
  end if;

  if length(coalesce(p_code, '')) < 40 or length(p_code) > 128 then
    v_outcome := 'invalid';
  else
    select * into v_code
      from public.customer_portal_claim_codes code
     where code.tenant_id = p_tenant_id
       and code.code_sha256 = encode(extensions.digest(convert_to(p_code, 'UTF8'), 'sha256'), 'hex')
     for update;
    if not found or v_code.revoked_at is not null then
      v_outcome := 'invalid';
    elsif v_code.expires_at <= clock_timestamp() then
      v_outcome := 'expired';
    end if;
  end if;

  if v_outcome is null then
    select * into v_customer
      from public.customers
     where id = v_code.customer_id
       and tenant_id = p_tenant_id
     for update;
    if not found or v_customer.is_active is not true then
      v_outcome := 'invalid';
    elsif v_customer.auth_user_id = v_uid then
      v_outcome := 'already_yours';
    elsif v_customer.auth_user_id is not null then
      v_outcome := 'linked_elsewhere';
    else
      v_record_digits := regexp_replace(coalesce(v_customer.phone, ''), '[^0-9]', '', 'g');
      if length(v_record_digits) >= 8
         and (length(v_typed_digits) < 8
              or right(v_typed_digits, 8) <> right(v_record_digits, 8)) then
        v_outcome := 'phone_mismatch';
      end if;
    end if;
  end if;

  if v_outcome is null then
    -- Al crear la cuenta el portal ya pudo dejarle una ficha propia, vacía:
    -- se suelta y se archiva para que la cuenta quede con la del taller.
    select * into v_current
      from public.customers
     where tenant_id = p_tenant_id
       and auth_user_id = v_uid
     for update;
    v_has_current := found;
    -- Todo lo que apunta a una ficha de cliente, salvo sus direcciones (que
    -- se copian): si la ficha propia tiene algo, no se archiva sola.
    if v_has_current and (
      exists (select 1 from public.mechanic_jobs job
               where job.tenant_id = p_tenant_id and job.customer_id = v_current.id)
      or exists (select 1 from public.sales_invoices invoice
                  where invoice.tenant_id = p_tenant_id and invoice.customer_id = v_current.id)
      or exists (select 1 from public.online_orders online_order
                  where online_order.tenant_id = p_tenant_id and online_order.customer_id = v_current.id)
      or exists (select 1 from public.bikes bike
                  where bike.tenant_id = p_tenant_id and bike.customer_id = v_current.id)
      or exists (select 1 from public.customer_quotes quote
                  where quote.tenant_id = p_tenant_id and quote.customer_id = v_current.id)
      or exists (select 1 from public.sales_orders sales_order
                  where sales_order.tenant_id = p_tenant_id and sales_order.customer_id = v_current.id)
      or exists (select 1 from public.orders legacy_order
                  where legacy_order.tenant_id = p_tenant_id and legacy_order.customer_id = v_current.id)
      or exists (select 1 from public.work_orders work_order
                  where work_order.tenant_id = p_tenant_id and work_order.customer_id = v_current.id)
      or exists (select 1 from public.vehicles vehicle
                  where vehicle.tenant_id = p_tenant_id and vehicle.customer_id = v_current.id)
      or exists (select 1 from public.loyalty loyalty_row
                  where loyalty_row.tenant_id = p_tenant_id and loyalty_row.customer_id = v_current.id)
      or exists (select 1 from public.smart_tasks task
                  where task.tenant_id = p_tenant_id and task.linked_customer_id = v_current.id)
      or exists (select 1 from public.whatsapp_conversation_bindings binding
                  where binding.tenant_id = p_tenant_id and binding.customer_id = v_current.id)
      or exists (select 1 from public.workshop_legacy_asset_copies legacy_copy
                  where legacy_copy.tenant_id = p_tenant_id and legacy_copy.customer_id = v_current.id)
    ) then
      v_outcome := 'account_has_history';
    end if;
  end if;

  if v_outcome is null and exists (
    select 1 from public.customers other
     where other.tenant_id = p_tenant_id
       and other.id <> v_customer.id
       and (not v_has_current or other.id <> v_current.id)
       and lower(other.email) = v_email
  ) then
    v_outcome := 'email_in_other_record';
  end if;

  if v_outcome is not null then
    insert into public.customer_portal_claim_attempts (tenant_id, auth_user_id, outcome)
    values (p_tenant_id, v_uid, v_outcome);
    return jsonb_build_object('status', v_outcome);
  end if;

  if v_has_current then
    -- Lo que alcanzó a guardar en su ficha vacía (direcciones) se copia: la
    -- identidad de una dirección no cambia de cliente
    -- (`guard_customer_address_identity_update`). La principal sigue siendo
    -- principal sólo si la ficha del taller no tenía ninguna.
    insert into public.customer_addresses (
      tenant_id, customer_id, label, recipient_name, phone, street_address,
      street_number, apartment, comuna, city, region, postal_code,
      additional_info, is_default
    )
    select address.tenant_id, v_customer.id, address.label, address.recipient_name,
           address.phone, address.street_address, address.street_number,
           address.apartment, address.comuna, address.city, address.region,
           address.postal_code, address.additional_info,
           address.is_default and not exists (
             select 1 from public.customer_addresses existing
              where existing.tenant_id = p_tenant_id
                and existing.customer_id = v_customer.id
           )
      from public.customer_addresses address
     where address.tenant_id = p_tenant_id
       and address.customer_id = v_current.id;
    perform set_config(
      'vinabike.portal_claim_relink',
      txid_current()::text || ':' || v_current.id::text,
      true
    );
    update public.customers
       set auth_user_id = null,
           email = null,
           is_active = false,
           notes = concat_ws(
             E'\n',
             nullif(notes, ''),
             format('Cuenta del portal unida a la ficha %s con el QR (%s).',
                    v_customer.id, to_char(clock_timestamp(), 'YYYY-MM-DD'))
           ),
           updated_at = clock_timestamp()
     where id = v_current.id
       and tenant_id = p_tenant_id;
  end if;

  perform set_config(
    'vinabike.portal_claim_relink',
    txid_current()::text || ':' || v_customer.id::text,
    true
  );
  update public.customers
     set auth_user_id = v_uid,
         email = v_email,
         phone = coalesce(nullif(trim(phone), ''), nullif(trim(p_phone), '')),
         notes = case
           when nullif(trim(email), '') is null or lower(trim(email)) = v_email then notes
           else concat_ws(
             E'\n',
             nullif(notes, ''),
             format('Correo anterior a la cuenta del portal: %s (%s).',
                    trim(email), to_char(clock_timestamp(), 'YYYY-MM-DD'))
           )
         end,
         updated_at = clock_timestamp()
   where id = v_customer.id
     and tenant_id = p_tenant_id;
  perform set_config('vinabike.portal_claim_relink', '', true);

  -- La membresía de la cuenta (app_metadata) y los pedidos web de su correo
  -- los pone el mismo camino de siempre.
  perform public.provision_current_public_store_customer(p_tenant_id);

  update public.customer_portal_claim_codes
     set claimed_at = clock_timestamp(),
         claimed_by = v_uid
   where tenant_id = p_tenant_id
     and customer_id = v_customer.id
     and claimed_at is null
     and revoked_at is null;

  insert into public.customer_portal_claim_attempts (tenant_id, auth_user_id, outcome)
  values (p_tenant_id, v_uid, 'linked');

  return jsonb_build_object('status', 'linked', 'customer_id', v_customer.id);
end;
$$;

revoke all on function public.claim_customer_portal_code_v1(uuid, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.claim_customer_portal_code_v1(uuid, text, text)
  to authenticated, service_role;

comment on function public.claim_customer_portal_code_v1(uuid, text, text) is
  'El cliente con cuenta usa el código del QR: su cuenta queda ligada a su ficha del taller (con teléfono que calce si la ficha lo tiene).';

-- ---------------------------------------------------------------------------
-- 5. Lo que el cliente con cuenta lee
-- ---------------------------------------------------------------------------

create or replace function public.list_my_job_delivery_documents_v1(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    jsonb_agg(
      public.job_delivery_document_projection_internal(mine.id)
      order by mine.delivered_at desc
    ),
    '[]'::jsonb
  )
    from (
      select document.id, document.delivered_at
        from public.mechanic_job_delivery_documents document
        join public.mechanic_jobs job
          on job.id = document.job_id
         and job.tenant_id = document.tenant_id
        join public.customers customer
          on customer.id = job.customer_id
         and customer.tenant_id = job.tenant_id
       where document.tenant_id = p_tenant_id
         and auth.uid() is not null
         and customer.auth_user_id = auth.uid()
         and customer.is_active is true
         and public.is_tenant_active(customer.tenant_id)
         and job.deleted_at is null
       order by document.delivered_at desc
       limit 100
    ) mine;
$$;

revoke all on function public.list_my_job_delivery_documents_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.list_my_job_delivery_documents_v1(uuid)
  to authenticated, service_role;

comment on function public.list_my_job_delivery_documents_v1(uuid) is
  'Los comprobantes de entrega y garantía del cliente con sesión (hasta 100), con los días de garantía que quedan.';

-- Las facturas del cliente con sesión: sólo lo que dice una factura (número,
-- fecha, estado, totales y líneas con nombre, cantidad y precio). Nunca el
-- costo, las notas internas ni los borradores.
create or replace function public.list_my_sales_invoices_v1(p_tenant_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', mine.id,
        'invoice_number', mine.invoice_number,
        'date', mine.date,
        'status', mine.status,
        'tax_treatment', mine.tax_treatment,
        'subtotal', mine.subtotal,
        'iva_amount', mine.iva_amount,
        'total', mine.total,
        'paid_amount', mine.paid_amount,
        'balance', mine.balance,
        'job_number', mine.job_number,
        'items', coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'name', coalesce(
                  nullif(trim(item ->> 'product_name'), ''),
                  nullif(trim(item ->> 'description'), '')
                ),
                'quantity', item -> 'quantity',
                'unit_price', item -> 'unit_price',
                'discount', item -> 'discount',
                'line_total', item -> 'line_total',
                'is_service', item -> 'is_service',
                'bike_name', item -> 'bike_name'
              )
              order by line.n
            )
              from jsonb_array_elements(
                case when jsonb_typeof(mine.items) = 'array' then mine.items else '[]'::jsonb end
              ) with ordinality as line(item, n)
          ),
          '[]'::jsonb
        )
      )
      order by mine.date desc
    ),
    '[]'::jsonb
  )
    from (
      select invoice.*
        from public.sales_invoices invoice
        join public.customers customer
          on customer.id = invoice.customer_id
         and customer.tenant_id = invoice.tenant_id
       where invoice.tenant_id = p_tenant_id
         and auth.uid() is not null
         and customer.auth_user_id = auth.uid()
         and customer.is_active is true
         and public.is_tenant_active(customer.tenant_id)
         -- Los estados viejos en castellano siguen en la base (24 «cancelado»).
         and coalesce(invoice.status, '') not in ('draft', 'borrador', 'cancelled', 'cancelado')
       order by invoice.date desc
       limit 100
    ) mine;
$$;

revoke all on function public.list_my_sales_invoices_v1(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.list_my_sales_invoices_v1(uuid)
  to authenticated, service_role;

comment on function public.list_my_sales_invoices_v1(uuid) is
  'Las facturas del cliente con sesión (hasta 100), sin borradores ni anuladas, con líneas sin costo ni notas internas.';
