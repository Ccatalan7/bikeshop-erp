-- Cotizaciones de clientes: productos en stock y a pedido en la misma lista,
-- confirmación con los proveedores y respuesta del cliente por enlace.
--
-- El dueño, 2026-11-02: «todos los productos agotados deberían estar
-- disponibles como agregar a una cotización para hacer pedidos… el cliente
-- arma una cotización, nos llega a nosotros, confirmamos disponibilidad
-- rápidamente con nuestros proveedores, y le enviamos una respuesta… si el
-- cliente agregó 5 productos, los proveedores sólo tengan 4… y él la puede
-- aceptar, modificar o rechazar». Plan aprobado («implementalo nomás»):
-- https://claude.ai/artifact/DNSj2Me7W9wxewsrt8V8sR
--
-- Esta migración es la etapa 1 (la base). Desde aquí:
--   * `product_on_order_terms`: un producto se vende a pedido con su
--     proveedor y su plazo. Sin términos, un producto sin stock igual se puede
--     cotizar («por confirmar»).
--   * `customer_quotes` es el agregado: número COT-AA-00001, estado, canal de
--     respuesta y versión para concurrencia optimista.
--   * Lo que pidió el cliente (`customer_quote_lines`) no se reescribe. Cada
--     respuesta del taller es una oferta con número (`customer_quote_offers`)
--     cuyas líneas se congelan al enviarla: una oferta enviada sólo cambia de
--     estado (aceptada, rechazada, reemplazada o vencida).
--   * `customer_quote_events` sólo se agrega: hora, autor (cliente con su
--     enlace, trabajador o sistema), canal y detalle. Una llave de operación
--     por cotización hace idempotente cada comando.
--   * El cliente sin cuenta entra sólo con su enlace: se guarda la huella
--     SHA-256, nunca el valor (igual que `online_order_access_tokens`).
--   * Al pedir la cotización, la base arma el borrador de la oferta: lo que
--     está en stock queda confirmado con el precio publicado, lo que tiene
--     una revisión de portal «available» reciente queda confirmado a pedido,
--     y lo demás queda pendiente en una tarea por proveedor con el mensaje
--     listo para su vendedor.
--   * Los mensajes al cliente (correo, WhatsApp y PDF), la conversión a pedido
--     web y las órdenes de compra son las etapas 3 y 5: leen estos eventos.

begin;

set local lock_timeout = '5s';
set local statement_timeout = '120s';

-- ---------------------------------------------------------------------------
-- 1. Ajustes por taller (los valores del dueño se cambian aquí, sin código)
-- ---------------------------------------------------------------------------

create table if not exists public.customer_quote_settings (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  offer_validity_hours integer not null default 72,
  reminder_hours_before integer not null default 24,
  on_order_prepay_percent integer not null default 100,
  supplier_task_due_hours integer not null default 24,
  supplier_check_fresh_hours integer not null default 48,
  notify_email text,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint customer_quote_settings_validity check (offer_validity_hours between 12 and 720),
  constraint customer_quote_settings_reminder check (reminder_hours_before between 0 and 168),
  constraint customer_quote_settings_prepay check (on_order_prepay_percent between 0 and 100),
  constraint customer_quote_settings_task_due check (supplier_task_due_hours between 1 and 168),
  constraint customer_quote_settings_check_fresh check (supplier_check_fresh_hours between 1 and 720),
  constraint customer_quote_settings_email check (
    notify_email is null or notify_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  )
);

comment on table public.customer_quote_settings is
  'Valores de las cotizaciones por taller: vigencia de una oferta, recordatorio, pago adelantado de lo que es a pedido, plazo de las tareas de proveedor y frescura de una revisión de portal. Sin fila, valen los valores por omisión.';

-- ---------------------------------------------------------------------------
-- 2. Venta a pedido por producto
-- ---------------------------------------------------------------------------

create table if not exists public.product_on_order_terms (
  product_id uuid primary key references public.products(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete set null,
  lead_days_min smallint not null default 3,
  lead_days_max smallint not null default 5,
  is_active boolean not null default true,
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint product_on_order_terms_lead check (
    lead_days_min between 0 and 120 and lead_days_max between lead_days_min and 180
  )
);

create index if not exists product_on_order_terms_tenant_idx
  on public.product_on_order_terms (tenant_id) where is_active;

comment on table public.product_on_order_terms is
  'Un producto que se vende a pedido: su proveedor y su plazo en días hábiles. Sin stock, el sitio lo muestra «A pedido» con ese plazo y la cotización lo manda a la tarea de ese proveedor.';

-- ---------------------------------------------------------------------------
-- 3. El agregado de la cotización
-- ---------------------------------------------------------------------------

create table if not exists public.customer_quotes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  quote_number text not null,
  status text not null default 'confirming',
  source text not null,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name text not null,
  customer_email text,
  customer_phone text,
  preferred_channel text not null,
  customer_notes text,
  conversation_id uuid references public.conversations(id) on delete set null,
  assigned_to uuid references auth.users(id) on delete set null,
  current_offer_id uuid,
  online_order_id uuid references public.online_orders(id) on delete restrict,
  request_idempotency_key text,
  version integer not null default 1,
  requested_at timestamptz not null default clock_timestamp(),
  offered_at timestamptz,
  expires_at timestamptz,
  reminder_sent_at timestamptz,
  accepted_at timestamptz,
  rejected_at timestamptz,
  expired_at timestamptz,
  cancelled_at timestamptz,
  closed_reason text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  constraint customer_quotes_status check (
    status in ('confirming', 'offered', 'accepted', 'rejected', 'expired', 'cancelled')
  ),
  constraint customer_quotes_source check (source in ('web', 'staff', 'whatsapp')),
  constraint customer_quotes_channel check (preferred_channel in ('email', 'whatsapp')),
  constraint customer_quotes_name check (length(btrim(customer_name)) between 2 and 120),
  constraint customer_quotes_email check (
    customer_email is null
    or customer_email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
  ),
  constraint customer_quotes_phone check (
    customer_phone is null or customer_phone ~ '^\+?[0-9]{8,15}$'
  ),
  constraint customer_quotes_reachable check (
    (preferred_channel = 'email' and customer_email is not null)
    or (preferred_channel = 'whatsapp' and customer_phone is not null)
  ),
  constraint customer_quotes_notes check (customer_notes is null or length(customer_notes) <= 2000),
  constraint customer_quotes_number_key unique (tenant_id, quote_number),
  constraint customer_quotes_request_key unique (tenant_id, request_idempotency_key),
  constraint customer_quotes_version check (version >= 1)
);

create index if not exists customer_quotes_inbox_idx
  on public.customer_quotes (tenant_id, status, updated_at desc);
create index if not exists customer_quotes_customer_idx
  on public.customer_quotes (customer_id) where customer_id is not null;

comment on table public.customer_quotes is
  'Una cotización de cliente: número, estado (confirming → offered → accepted | rejected | expired | cancelled), canal de respuesta y versión. Se escribe sólo por sus comandos.';

create table if not exists public.customer_quote_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  quote_id uuid not null references public.customer_quotes(id) on delete cascade,
  line_no smallint not null,
  product_id uuid references public.products(id) on delete restrict,
  product_sku text,
  product_name text not null,
  quantity integer not null,
  stock_at_request numeric,
  kind_at_request text not null,
  unit_price_reference numeric(12, 0),
  created_at timestamptz not null default clock_timestamp(),
  constraint customer_quote_lines_no check (line_no between 1 and 50),
  constraint customer_quote_lines_quantity check (quantity between 1 and 99),
  constraint customer_quote_lines_kind check (kind_at_request in ('in_stock', 'on_order', 'to_confirm')),
  constraint customer_quote_lines_price check (unit_price_reference is null or unit_price_reference >= 0),
  constraint customer_quote_lines_line_key unique (quote_id, line_no)
);

comment on table public.customer_quote_lines is
  'Lo que pidió el cliente, tal cual y para siempre: producto, cantidad, stock y precio publicado a esa hora.';

create table if not exists public.customer_quote_offers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  quote_id uuid not null references public.customer_quotes(id) on delete cascade,
  offer_no smallint not null,
  status text not null default 'draft',
  valid_until timestamptz,
  subtotal numeric(12, 0),
  tax_amount numeric(12, 0),
  total numeric(12, 0),
  notes_to_customer text,
  pdf_storage_path text,
  pdf_sha256 text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  sent_by uuid references auth.users(id) on delete set null,
  responded_at timestamptz,
  constraint customer_quote_offers_no check (offer_no between 1 and 50),
  constraint customer_quote_offers_status check (
    status in ('draft', 'sent', 'superseded', 'accepted', 'rejected', 'expired', 'cancelled')
  ),
  constraint customer_quote_offers_notes check (notes_to_customer is null or length(notes_to_customer) <= 2000),
  constraint customer_quote_offers_pdf check (pdf_sha256 is null or pdf_sha256 ~ '^[0-9a-f]{64}$'),
  constraint customer_quote_offers_sent_shape check (
    (status = 'draft' and sent_at is null)
    or (status = 'cancelled' and sent_at is null)
    or (status not in ('draft', 'cancelled') and sent_at is not null
        and valid_until is not null and total is not null)
  ),
  constraint customer_quote_offers_no_key unique (quote_id, offer_no)
);

create unique index if not exists customer_quote_offers_one_draft
  on public.customer_quote_offers (quote_id) where status = 'draft';

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.customer_quotes'::regclass
       and conname = 'customer_quotes_current_offer_fkey'
  ) then
    alter table public.customer_quotes
      add constraint customer_quotes_current_offer_fkey
      foreign key (current_offer_id) references public.customer_quote_offers(id)
      on delete restrict;
  end if;
end;
$$;

comment on table public.customer_quote_offers is
  'Cada respuesta del taller a una cotización, numerada. Un borrador por cotización; al enviarla se congela con su vigencia y sus totales.';

create table if not exists public.customer_quote_offer_lines (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  offer_id uuid not null references public.customer_quote_offers(id) on delete cascade,
  quote_line_id uuid references public.customer_quote_lines(id) on delete restrict,
  line_no smallint not null,
  product_id uuid references public.products(id) on delete restrict,
  product_sku text,
  product_name text not null,
  quantity_requested integer not null,
  availability text not null default 'pending',
  quantity_offered integer not null default 0,
  unit_price numeric(12, 0),
  tax_rate numeric,
  lead_days_min smallint,
  lead_days_max smallint,
  supplier_id uuid references public.suppliers(id) on delete set null,
  unit_cost_net numeric(12, 2),
  supplier_check_id uuid references public.supplier_availability_checks(id) on delete set null,
  staff_note text,
  customer_note text,
  confirmed_at timestamptz,
  confirmed_by uuid references auth.users(id) on delete set null,
  confirmed_by_system boolean not null default false,
  constraint customer_quote_offer_lines_no check (line_no between 1 and 60),
  constraint customer_quote_offer_lines_requested check (quantity_requested between 0 and 99),
  constraint customer_quote_offer_lines_offered check (quantity_offered between 0 and 99),
  constraint customer_quote_offer_lines_availability check (
    availability in ('pending', 'in_stock', 'on_order', 'unavailable')
  ),
  constraint customer_quote_offer_lines_money check (
    (unit_price is null or unit_price >= 0) and (unit_cost_net is null or unit_cost_net >= 0)
  ),
  constraint customer_quote_offer_lines_lead check (
    (lead_days_min is null and lead_days_max is null)
    or (lead_days_min between 0 and 120 and lead_days_max between lead_days_min and 180)
  ),
  constraint customer_quote_offer_lines_notes check (
    (staff_note is null or length(staff_note) <= 1000)
    and (customer_note is null or length(customer_note) <= 1000)
  ),
  constraint customer_quote_offer_lines_shape check (
    (availability = 'pending' and confirmed_at is null and quantity_offered = 0)
    or (availability = 'unavailable' and confirmed_at is not null and quantity_offered = 0)
    or (availability in ('in_stock', 'on_order') and confirmed_at is not null
        and quantity_offered > 0 and unit_price is not null)
  ),
  constraint customer_quote_offer_lines_line_key unique (offer_id, line_no)
);

create index if not exists customer_quote_offer_lines_offer_idx
  on public.customer_quote_offer_lines (offer_id);

comment on table public.customer_quote_offer_lines is
  'Las líneas de una oferta: lo que hay (en stock o a pedido), cuánto, a qué precio y en qué plazo, o «no disponible». El proveedor, el costo y la nota interna no salen al cliente.';

create table if not exists public.customer_quote_supplier_tasks (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  quote_id uuid not null references public.customer_quotes(id) on delete cascade,
  offer_id uuid not null references public.customer_quote_offers(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete set null,
  status text not null default 'open',
  due_at timestamptz not null,
  message_draft text not null,
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  completed_by uuid references auth.users(id) on delete set null,
  constraint customer_quote_supplier_tasks_status check (status in ('open', 'done', 'cancelled')),
  constraint customer_quote_supplier_tasks_shape check (
    (status = 'open' and completed_at is null) or (status <> 'open' and completed_at is not null)
  )
);

create unique index if not exists customer_quote_supplier_tasks_offer_supplier
  on public.customer_quote_supplier_tasks (
    offer_id, coalesce(supplier_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );
create index if not exists customer_quote_supplier_tasks_open_idx
  on public.customer_quote_supplier_tasks (tenant_id, due_at) where status = 'open';

comment on table public.customer_quote_supplier_tasks is
  'Una tarea por proveedor para confirmar las líneas pendientes de un borrador, con el mensaje listo para su vendedor. Se cierra sola cuando todas sus líneas quedan confirmadas.';

create table if not exists public.customer_quote_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  quote_id uuid not null references public.customer_quotes(id) on delete cascade,
  offer_id uuid references public.customer_quote_offers(id) on delete restrict,
  event_type text not null,
  actor_kind text not null,
  actor_id uuid,
  channel text,
  operation_key text,
  detail jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default clock_timestamp(),
  constraint customer_quote_events_type check (
    event_type in (
      'requested', 'offer_prepared', 'offer_revised', 'line_confirmed', 'line_added',
      'supplier_task_opened', 'supplier_task_done', 'offer_sent', 'viewed',
      'accepted', 'changes_requested', 'rejected', 'expired', 'cancelled',
      'reminder_sent', 'message_queued', 'note'
    )
  ),
  constraint customer_quote_events_actor check (actor_kind in ('customer', 'staff', 'system')),
  constraint customer_quote_events_channel check (
    channel is null or channel in ('web', 'email', 'whatsapp', 'erp', 'system')
  ),
  constraint customer_quote_events_detail check (jsonb_typeof(detail) = 'object')
);

create unique index if not exists customer_quote_events_operation_key
  on public.customer_quote_events (quote_id, operation_key) where operation_key is not null;
create index if not exists customer_quote_events_quote_idx
  on public.customer_quote_events (quote_id, id);

comment on table public.customer_quote_events is
  'Historia de cada cotización, sólo se agrega: qué pasó, cuándo, quién (cliente, trabajador o sistema) y por qué canal. La llave de operación hace idempotente cada comando.';

create table if not exists public.customer_quote_access_tokens (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete restrict,
  quote_id uuid not null references public.customer_quotes(id) on delete restrict,
  token_sha256 text not null,
  scopes text[] not null,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_reason text,
  last_used_at timestamptz,
  use_count integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  created_by uuid references auth.users(id) on delete set null,
  constraint customer_quote_access_tokens_hash check (token_sha256 ~ '^[0-9a-f]{64}$'),
  constraint customer_quote_access_tokens_hash_key unique (token_sha256),
  constraint customer_quote_access_tokens_scopes check (
    cardinality(scopes) > 0 and scopes <@ array['view_quote', 'respond_quote']::text[]
  ),
  constraint customer_quote_access_tokens_revoke_shape check (
    revoked_at is null or nullif(btrim(revoked_reason), '') is not null
  ),
  constraint customer_quote_access_tokens_use_count check (use_count >= 0)
);

create index if not exists customer_quote_access_tokens_quote_idx
  on public.customer_quote_access_tokens (quote_id);

comment on table public.customer_quote_access_tokens is
  'Enlaces del cliente a su cotización: sólo la huella SHA-256, el vencimiento y el alcance (ver, responder).';

-- ---------------------------------------------------------------------------
-- 4. Lo enviado no se reescribe y la historia sólo se agrega
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_events_append_only()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- Borrar la cotización completa (cascada) es la única excepción, y ningún
  -- comando lo hace: queda para una limpieza de pruebas.
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 then
    return old;
  end if;
  raise exception 'customer_quote_events is append-only' using errcode = '42501';
end;
$$;

revoke all on function public.customer_quote_events_append_only()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_customer_quote_events_append_only on public.customer_quote_events;
create trigger trg_customer_quote_events_append_only
  before update or delete on public.customer_quote_events
  for each row execute function public.customer_quote_events_append_only();

create or replace function public.customer_quote_offer_lines_frozen()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_status text;
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() > 1 then
      return old;
    end if;
    select o.status into v_status from public.customer_quote_offers o where o.id = old.offer_id;
  else
    select o.status into v_status from public.customer_quote_offers o where o.id = new.offer_id;
  end if;
  if v_status is distinct from 'draft' then
    raise exception 'A sent quote offer is frozen' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.offer_id is distinct from old.offer_id then
    raise exception 'An offer line cannot move to another offer' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.customer_quote_offer_lines_frozen()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_customer_quote_offer_lines_frozen on public.customer_quote_offer_lines;
create trigger trg_customer_quote_offer_lines_frozen
  before insert or update or delete on public.customer_quote_offer_lines
  for each row execute function public.customer_quote_offer_lines_frozen();

create or replace function public.customer_quote_offers_frozen()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    if pg_trigger_depth() > 1 then
      return old;
    end if;
    raise exception 'A quote offer is never deleted' using errcode = '42501';
  end if;
  if old.status = 'draft' then
    return new;
  end if;
  -- Una oferta enviada sólo cambia de estado y de hora de respuesta.
  if new.offer_no is distinct from old.offer_no
     or new.quote_id is distinct from old.quote_id
     or new.valid_until is distinct from old.valid_until
     or new.subtotal is distinct from old.subtotal
     or new.tax_amount is distinct from old.tax_amount
     or new.total is distinct from old.total
     or new.notes_to_customer is distinct from old.notes_to_customer
     or new.sent_at is distinct from old.sent_at
     or new.sent_by is distinct from old.sent_by
     or (old.pdf_sha256 is not null and new.pdf_sha256 is distinct from old.pdf_sha256)
     or (old.pdf_storage_path is not null and new.pdf_storage_path is distinct from old.pdf_storage_path)
  then
    raise exception 'A sent quote offer is frozen' using errcode = '42501';
  end if;
  if not (
    (old.status = 'sent' and new.status in ('sent', 'superseded', 'accepted', 'rejected', 'expired'))
    or new.status = old.status
  ) then
    raise exception 'Invalid quote offer transition % -> %', old.status, new.status
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.customer_quote_offers_frozen()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_customer_quote_offers_frozen on public.customer_quote_offers;
create trigger trg_customer_quote_offers_frozen
  before update or delete on public.customer_quote_offers
  for each row execute function public.customer_quote_offers_frozen();

-- ---------------------------------------------------------------------------
-- 5. Seguridad: lectura del equipo por RLS; escritura sólo por comandos
-- ---------------------------------------------------------------------------

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'customer_quote_settings', 'product_on_order_terms', 'customer_quotes',
    'customer_quote_lines', 'customer_quote_offers', 'customer_quote_offer_lines',
    'customer_quote_supplier_tasks', 'customer_quote_events', 'customer_quote_access_tokens'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on public.%I from public, anon, authenticated', v_table);
  end loop;
end;
$$;

-- El equipo lee su taller (el ERP también lee por los comandos de abajo).
-- Los enlaces del cliente no se leen nunca por la API: sólo su huella existe.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'customer_quote_settings', 'product_on_order_terms', 'customer_quotes',
    'customer_quote_lines', 'customer_quote_offers', 'customer_quote_offer_lines',
    'customer_quote_supplier_tasks', 'customer_quote_events'
  ] loop
    execute format('grant select on public.%I to authenticated', v_table);
    execute format('drop policy if exists %I on public.%I', v_table || '_tenant_read', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (tenant_id = (select public.user_tenant_id()))',
      v_table || '_tenant_read', v_table
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Piezas internas (sin grants: sólo las llaman los comandos)
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_settings_internal(p_tenant_id uuid)
returns public.customer_quote_settings
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(
    (select s from public.customer_quote_settings s where s.tenant_id = p_tenant_id),
    row(p_tenant_id, 72, 24, 100, 24, 48, null::text, null::timestamptz, null::uuid)::public.customer_quote_settings
  );
$$;

revoke all on function public.customer_quote_settings_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.customer_quote_next_number_internal(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_year text := to_char(clock_timestamp() at time zone 'America/Santiago', 'YY');
  v_next integer;
begin
  insert into public.document_sequences (tenant_id, document_type, last_number)
  values (p_tenant_id, 'customer_quote_' || v_year, 1)
  on conflict (tenant_id, document_type)
  do update set last_number = public.document_sequences.last_number + 1,
                updated_at = now()
  returning last_number into v_next;
  return 'COT-' || v_year || '-' || lpad(v_next::text, 5, '0');
end;
$$;

revoke all on function public.customer_quote_next_number_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.customer_quote_log_internal(
  p_quote_id uuid,
  p_event_type text,
  p_actor_kind text,
  p_actor_id uuid,
  p_channel text,
  p_offer_id uuid default null,
  p_operation_key text default null,
  p_detail jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id bigint;
begin
  insert into public.customer_quote_events (
    tenant_id, quote_id, offer_id, event_type, actor_kind, actor_id, channel,
    operation_key, detail
  )
  select q.tenant_id, q.id, p_offer_id, p_event_type, p_actor_kind, p_actor_id,
         p_channel, p_operation_key, coalesce(p_detail, '{}'::jsonb)
    from public.customer_quotes q
   where q.id = p_quote_id
  returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.customer_quote_log_internal(uuid, text, text, uuid, text, uuid, text, jsonb)
  from public, anon, authenticated, service_role;

create or replace function public.customer_quote_issue_token_internal(
  p_quote_id uuid,
  p_scopes text[],
  p_expires_at timestamptz,
  p_actor uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_raw text;
begin
  if p_expires_at <= clock_timestamp() or p_expires_at > clock_timestamp() + interval '120 days' then
    raise exception 'Quote access-token expiry must be within the next 120 days' using errcode = '22023';
  end if;
  select * into v_quote from public.customer_quotes where id = p_quote_id;
  if not found then
    raise exception 'Quote not found' using errcode = 'P0002';
  end if;
  v_raw := rtrim(translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/', '-_'), '=');
  insert into public.customer_quote_access_tokens (
    tenant_id, quote_id, token_sha256, scopes, expires_at, created_by
  ) values (
    v_quote.tenant_id, v_quote.id,
    encode(extensions.digest(convert_to(v_raw, 'UTF8'), 'sha256'), 'hex'),
    p_scopes, p_expires_at, p_actor
  );
  return jsonb_build_object('token', v_raw, 'expires_at', p_expires_at, 'scopes', to_jsonb(p_scopes));
end;
$$;

revoke all on function public.customer_quote_issue_token_internal(uuid, text[], timestamptz, uuid)
  from public, anon, authenticated, service_role;

-- Resuelve un enlace del cliente. Devuelve null si no vale (no explica por qué).
create or replace function public.customer_quote_token_internal(p_token text, p_scope text)
returns public.customer_quote_access_tokens
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_access public.customer_quote_access_tokens%rowtype;
begin
  if length(coalesce(p_token, '')) < 40 or length(p_token) > 128 then
    return null;
  end if;
  select a.* into v_access
    from public.customer_quote_access_tokens a
   where a.token_sha256 = encode(extensions.digest(convert_to(p_token, 'UTF8'), 'sha256'), 'hex')
     and a.revoked_at is null
     and a.expires_at > clock_timestamp()
     and a.scopes @> array[p_scope]::text[]
   for update;
  if not found then
    return null;
  end if;
  update public.customer_quote_access_tokens
     set last_used_at = clock_timestamp(), use_count = use_count + 1
   where id = v_access.id;
  return v_access;
end;
$$;

revoke all on function public.customer_quote_token_internal(text, text)
  from public, anon, authenticated, service_role;

-- Precio publicado de un producto (el mismo que muestra el sitio).
create or replace function public.customer_quote_public_price_internal(p public.products)
returns numeric
language sql
stable
as $$
  select public.clp_round(coalesce(p.website_price, p.price, 0));
$$;

revoke all on function public.customer_quote_public_price_internal(public.products)
  from public, anon, authenticated, service_role;

-- Lo que se puede prometer hoy: el stock menos lo apartado para pedidos web
-- (vigente o en consumo). Un producto sin control de stock no cuenta como
-- disponible: lo confirma una persona.
create or replace function public.customer_quote_available_stock_internal(
  p_tenant_id uuid,
  p_product_id uuid
)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when not coalesce(p.track_stock, true) then 0
    else greatest(0, coalesce(p.inventory_qty, 0) - coalesce((
      select sum(r.quantity)::integer
        from public.online_order_inventory_reservations r
       where r.tenant_id = p_tenant_id
         and r.product_id = p_product_id
         and (r.state = 'consuming' or (r.state = 'active' and r.expires_at > clock_timestamp()))
    ), 0))
  end
    from public.products p
   where p.id = p_product_id and p.tenant_id = p_tenant_id;
$$;

revoke all on function public.customer_quote_available_stock_internal(uuid, uuid)
  from public, anon, authenticated, service_role;

-- Aviso durable para el equipo en el ERP. Nunca hace fallar el comando.
create or replace function public.customer_quote_notify_internal(
  p_quote_id uuid,
  p_type text,
  p_title text,
  p_entity_type text,
  p_entity_id uuid,
  p_severity text default 'info'
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_lines integer;
begin
  select * into v_quote from public.customer_quotes where id = p_quote_id;
  if not found then
    return;
  end if;
  select count(*) into v_lines from public.customer_quote_lines where quote_id = p_quote_id;
  insert into public.erp_notifications (
    tenant_id, type, title, body, route, entity_type, entity_id, severity, data
  ) values (
    v_quote.tenant_id,
    p_type,
    p_title,
    v_quote.quote_number || ' · ' || v_quote.customer_name || ' · '
      || v_lines || case when v_lines = 1 then ' producto' else ' productos' end,
    '/sales/quotes/' || v_quote.id::text,
    p_entity_type,
    p_entity_id,
    p_severity,
    jsonb_build_object(
      'quote_id', v_quote.id,
      'quote_number', v_quote.quote_number,
      'customer_name', v_quote.customer_name,
      'status', v_quote.status
    )
  ) on conflict (tenant_id, type, entity_type, entity_id) do nothing;
exception
  when others then
    raise warning 'Customer quote notification could not be recorded';
end;
$$;

revoke all on function public.customer_quote_notify_internal(uuid, text, text, text, uuid, text)
  from public, anon, authenticated, service_role;

-- Arma el borrador de una oferta.
--   * Sin oferta anterior, parte de lo que pidió el cliente.
--   * Con p_base_offer_id (el cliente pidió cambios, o el equipo revisa una
--     oferta enviada), parte de esa oferta: p_quantities (número de línea →
--     cantidad) cambia cantidades; una línea que no nombra conserva lo
--     ofrecido (lo «no disponible» sale) y lo confirmado hace menos de
--     supplier_check_fresh_hours no se vuelve a preguntar si no sube.
-- Lo demás se confirma solo cuando se puede (stock disponible hoy, o una
-- revisión «available» reciente del portal del proveedor) y lo que queda va
-- a una tarea por proveedor con el mensaje para su vendedor.
create or replace function public.customer_quote_prepare_offer_internal(
  p_quote_id uuid,
  p_actor_kind text,
  p_actor_id uuid,
  p_base_offer_id uuid default null,
  p_quantities jsonb default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_settings public.customer_quote_settings;
  v_offer_id uuid;
  v_offer_no smallint;
  v_line record;
  v_product public.products%rowtype;
  v_terms public.product_on_order_terms%rowtype;
  v_check public.supplier_availability_checks%rowtype;
  v_qty integer;
  v_available integer;
  v_supplier uuid;
  v_task record;
  v_confirmed integer := 0;
  v_pending integer := 0;
  v_line_no smallint := 0;
  v_fresh timestamptz;
begin
  select * into v_quote from public.customer_quotes where id = p_quote_id for update;
  if not found then
    raise exception 'Quote not found' using errcode = 'P0002';
  end if;
  v_settings := public.customer_quote_settings_internal(v_quote.tenant_id);
  v_fresh := clock_timestamp() - make_interval(hours => v_settings.supplier_check_fresh_hours);

  -- Un borrador abierto se descarta: la oferta nueva parte de cero.
  update public.customer_quote_supplier_tasks t
     set status = 'cancelled', completed_at = clock_timestamp()
   where t.quote_id = p_quote_id and t.status = 'open';
  update public.customer_quote_offers o
     set status = 'cancelled'
   where o.quote_id = p_quote_id and o.status = 'draft';

  select coalesce(max(o.offer_no), 0) + 1 into v_offer_no
    from public.customer_quote_offers o where o.quote_id = p_quote_id;

  insert into public.customer_quote_offers (tenant_id, quote_id, offer_no, status, created_by)
  values (v_quote.tenant_id, p_quote_id, v_offer_no, 'draft', p_actor_id)
  returning id into v_offer_id;

  for v_line in
    select ql.id as quote_line_id, ql.product_id, ql.product_sku, ql.product_name,
           ql.quantity, ql.line_no,
           null::text as base_availability, null::integer as base_offered,
           null::numeric as base_price, null::smallint as base_lead_min,
           null::smallint as base_lead_max, null::uuid as base_supplier,
           null::numeric as base_cost, null::uuid as base_check,
           null::timestamptz as base_confirmed_at, null::text as base_customer_note
      from public.customer_quote_lines ql
     where ql.quote_id = p_quote_id and p_base_offer_id is null
    union all
    select bl.quote_line_id, bl.product_id, bl.product_sku, bl.product_name,
           case
             when p_quantities ? bl.line_no::text
               then greatest(0, least(99, (p_quantities ->> bl.line_no::text)::integer))
             else bl.quantity_offered
           end,
           bl.line_no,
           bl.availability, bl.quantity_offered, bl.unit_price, bl.lead_days_min,
           bl.lead_days_max, bl.supplier_id, bl.unit_cost_net, bl.supplier_check_id,
           bl.confirmed_at, bl.customer_note
      from public.customer_quote_offer_lines bl
     where bl.offer_id = p_base_offer_id
    order by line_no
  loop
    v_qty := v_line.quantity;
    if v_qty is null or v_qty <= 0 then
      continue;
    end if;
    v_line_no := v_line_no + 1;

    v_product := null;
    v_terms := null;
    v_check := null;
    v_available := 0;
    if v_line.product_id is not null then
      select * into v_product from public.products p
       where p.id = v_line.product_id and p.tenant_id = v_quote.tenant_id;
      select * into v_terms from public.product_on_order_terms t
       where t.product_id = v_line.product_id and t.is_active;
      v_available := coalesce(public.customer_quote_available_stock_internal(v_quote.tenant_id, v_line.product_id), 0);
    end if;
    v_supplier := coalesce(v_line.base_supplier, v_terms.supplier_id, v_product.supplier_id);

    -- Lo ya confirmado en la oferta base, si no sube y sigue fresco.
    if v_line.base_availability in ('in_stock', 'on_order')
       and v_qty <= v_line.base_offered
       and v_line.base_confirmed_at > v_fresh
       and (v_line.base_availability = 'on_order' or v_available >= v_qty) then
      insert into public.customer_quote_offer_lines (
        tenant_id, offer_id, quote_line_id, line_no, product_id, product_sku, product_name,
        quantity_requested, availability, quantity_offered, unit_price, tax_rate,
        lead_days_min, lead_days_max, supplier_id, unit_cost_net, supplier_check_id,
        customer_note, confirmed_at, confirmed_by_system
      ) values (
        v_quote.tenant_id, v_offer_id, v_line.quote_line_id, v_line_no, v_line.product_id,
        v_line.product_sku, v_line.product_name, v_qty, v_line.base_availability, v_qty,
        v_line.base_price, v_product.tax_rate, v_line.base_lead_min, v_line.base_lead_max,
        v_supplier, v_line.base_cost, v_line.base_check, v_line.base_customer_note,
        v_line.base_confirmed_at, true
      );
      v_confirmed := v_confirmed + 1;
      continue;
    end if;

    -- Lo que está en stock se confirma con el precio publicado.
    if v_product.id is not null and v_available >= v_qty then
      insert into public.customer_quote_offer_lines (
        tenant_id, offer_id, quote_line_id, line_no, product_id, product_sku, product_name,
        quantity_requested, availability, quantity_offered, unit_price, tax_rate,
        confirmed_at, confirmed_by_system
      ) values (
        v_quote.tenant_id, v_offer_id, v_line.quote_line_id, v_line_no, v_line.product_id,
        v_line.product_sku, v_line.product_name, v_qty, 'in_stock', v_qty,
        public.customer_quote_public_price_internal(v_product), v_product.tax_rate,
        clock_timestamp(), true
      );
      v_confirmed := v_confirmed + 1;
      continue;
    end if;

    -- Una revisión reciente del portal del proveedor que dice «available».
    if v_product.id is not null and v_supplier is not null and v_terms.product_id is not null then
      select c.* into v_check
        from public.supplier_availability_checks c
       where c.tenant_id = v_quote.tenant_id
         and c.product_id = v_product.id
         and c.supplier_id = v_supplier
         and c.status = 'available'
         and c.checked_at > v_fresh
         and (c.stock_quantity is null or c.stock_quantity >= v_qty)
       order by c.checked_at desc
       limit 1;
    end if;

    if v_check.id is not null
       and public.customer_quote_public_price_internal(v_product) > 0 then
      insert into public.customer_quote_offer_lines (
        tenant_id, offer_id, quote_line_id, line_no, product_id, product_sku, product_name,
        quantity_requested, availability, quantity_offered, unit_price, tax_rate,
        lead_days_min, lead_days_max, supplier_id, unit_cost_net, supplier_check_id,
        confirmed_at, confirmed_by_system
      ) values (
        v_quote.tenant_id, v_offer_id, v_line.quote_line_id, v_line_no, v_line.product_id,
        v_line.product_sku, v_line.product_name, v_qty, 'on_order', v_qty,
        public.customer_quote_public_price_internal(v_product), v_product.tax_rate,
        v_terms.lead_days_min, v_terms.lead_days_max, v_supplier, v_check.price_net, v_check.id,
        clock_timestamp(), true
      );
      v_confirmed := v_confirmed + 1;
    else
      insert into public.customer_quote_offer_lines (
        tenant_id, offer_id, quote_line_id, line_no, product_id, product_sku, product_name,
        quantity_requested, tax_rate, lead_days_min, lead_days_max, supplier_id
      ) values (
        v_quote.tenant_id, v_offer_id, v_line.quote_line_id, v_line_no, v_line.product_id,
        v_line.product_sku, v_line.product_name, v_qty, v_product.tax_rate,
        v_terms.lead_days_min, v_terms.lead_days_max, v_supplier
      );
      v_pending := v_pending + 1;
    end if;
  end loop;

  -- Una tarea por proveedor con el mensaje para su vendedor.
  for v_task in
    select l.supplier_id,
           string_agg(
             '- ' || l.quantity_requested || ' × ' || l.product_name
               || coalesce(' (código ' || nullif(btrim(coalesce(p.supplier_code, p.supplier_reference, '')), '') || ')', ''),
             E'\n' order by l.line_no
           ) as lines
      from public.customer_quote_offer_lines l
      left join public.products p on p.id = l.product_id
     where l.offer_id = v_offer_id and l.availability = 'pending'
     group by l.supplier_id
  loop
    insert into public.customer_quote_supplier_tasks (
      tenant_id, quote_id, offer_id, supplier_id, due_at, message_draft
    ) values (
      v_quote.tenant_id, p_quote_id, v_offer_id, v_task.supplier_id,
      clock_timestamp() + make_interval(hours => v_settings.supplier_task_due_hours),
      'Hola, necesito confirmar disponibilidad, precio y plazo de:' || E'\n'
        || v_task.lines || E'\n' || 'Gracias.'
    );
  end loop;

  update public.customer_quotes q
     set status = 'confirming',
         expires_at = null,
         updated_at = clock_timestamp(),
         version = q.version + 1
   where q.id = p_quote_id;

  perform public.customer_quote_log_internal(
    p_quote_id, 'offer_prepared', p_actor_kind, p_actor_id, 'system', v_offer_id, null,
    jsonb_build_object('offer_no', v_offer_no, 'confirmed', v_confirmed, 'pending', v_pending,
                       'base_offer_id', p_base_offer_id)
  );
  if v_pending > 0 then
    perform public.customer_quote_log_internal(
      p_quote_id, 'supplier_task_opened', 'system', null, 'system', v_offer_id, null,
      jsonb_build_object(
        'tasks', (select count(*) from public.customer_quote_supplier_tasks t
                   where t.offer_id = v_offer_id and t.status = 'open')
      )
    );
  end if;

  return v_offer_id;
end;
$$;

revoke all on function public.customer_quote_prepare_offer_internal(uuid, text, uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;

-- Valida y normaliza los productos pedidos: [{product_id, quantity}], 1 a 50
-- productos distintos. Desde el sitio, cada uno vendible en la web (la misma
-- regla que el sitio, salvo el stock: lo agotado también se cotiza); desde el
-- ERP, cualquier producto del taller que no sea un servicio.
create or replace function public.customer_quote_insert_lines_internal(
  p_quote_id uuid,
  p_items jsonb,
  p_web_rule boolean
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_policy jsonb;
  v_item record;
  v_product public.products%rowtype;
  v_terms public.product_on_order_terms%rowtype;
  v_line_no smallint := 0;
  v_kind text;
  v_available integer;
begin
  select * into v_quote from public.customer_quotes where id = p_quote_id;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'quote_items_required' using errcode = '22023';
  end if;
  v_policy := public.catalog_web_policy_v1(v_quote.tenant_id);

  for v_item in
    select (e ->> 'product_id')::uuid as product_id,
           sum(greatest(1, least(99, coalesce((e ->> 'quantity')::integer, 1))))::integer as quantity,
           min(ord) as first_ord
      from jsonb_array_elements(p_items) with ordinality as x(e, ord)
     group by 1
     order by 3
  loop
    if v_line_no >= 50 then
      raise exception 'quote_too_many_items' using errcode = '22023';
    end if;
    select * into v_product from public.products p
     where p.id = v_item.product_id and p.tenant_id = v_quote.tenant_id;
    if not found
       or coalesce(v_product.product_type, 'product') = 'service'
       or (p_web_rule and public.catalog_product_web_block_v1(v_product, v_policy) is not null) then
      raise exception 'quote_product_not_available' using errcode = '22023',
        detail = coalesce(v_item.product_id::text, '');
    end if;
    select * into v_terms from public.product_on_order_terms t
     where t.product_id = v_product.id and t.is_active;
    v_available := coalesce(public.customer_quote_available_stock_internal(v_quote.tenant_id, v_product.id), 0);
    v_kind := case
      when v_available >= least(v_item.quantity, 99) then 'in_stock'
      when v_terms.product_id is not null then 'on_order'
      else 'to_confirm'
    end;
    v_line_no := v_line_no + 1;
    insert into public.customer_quote_lines (
      tenant_id, quote_id, line_no, product_id, product_sku, product_name, quantity,
      stock_at_request, kind_at_request, unit_price_reference
    ) values (
      v_quote.tenant_id, p_quote_id, v_line_no, v_product.id, v_product.sku,
      coalesce(nullif(btrim(v_product.website_name), ''), v_product.name),
      least(v_item.quantity, 99), v_available, v_kind,
      public.customer_quote_public_price_internal(v_product)
    );
  end loop;
  return v_line_no;
end;
$$;

revoke all on function public.customer_quote_insert_lines_internal(uuid, jsonb, boolean)
  from public, anon, authenticated, service_role;

-- Datos de contacto normalizados: nombre, correo, teléfono (sólo dígitos y +).
create or replace function public.customer_quote_contact_internal(p_request jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_name text := btrim(coalesce(p_request ->> 'customer_name', ''));
  v_email text := lower(nullif(btrim(coalesce(p_request ->> 'customer_email', '')), ''));
  v_phone text := nullif(regexp_replace(coalesce(p_request ->> 'customer_phone', ''), '[^0-9+]', '', 'g'), '');
  v_channel text := coalesce(nullif(p_request ->> 'preferred_channel', ''),
                             case when v_email is not null then 'email' else 'whatsapp' end);
  v_notes text := nullif(btrim(coalesce(p_request ->> 'customer_notes', '')), '');
begin
  -- Un celular chileno escrito sin el +56 (9 1234 5678 o 56 9 1234 5678).
  if v_phone ~ '^9[0-9]{8}$' then
    v_phone := '+56' || v_phone;
  elsif v_phone ~ '^56[0-9]{9}$' then
    v_phone := '+' || v_phone;
  end if;
  return jsonb_build_object(
    'customer_name', v_name, 'customer_email', v_email, 'customer_phone', v_phone,
    'preferred_channel', v_channel, 'customer_notes', v_notes
  );
end;
$$;

revoke all on function public.customer_quote_contact_internal(jsonb)
  from public, anon, authenticated, service_role;

-- Un dato de contacto que no sirve se rechaza con su nombre de campo, para que
-- el formulario lo marque (en vez de un error de restricción).
create or replace function public.customer_quote_validate_contact_internal(p_contact jsonb)
returns void
language plpgsql
immutable
as $$
declare
  v_field text;
begin
  v_field := case
    when length(coalesce(p_contact ->> 'customer_name', '')) not between 2 and 120 then 'customer_name'
    when coalesce(p_contact ->> 'preferred_channel', '') not in ('email', 'whatsapp') then 'preferred_channel'
    when p_contact ->> 'customer_email' is not null
         and (p_contact ->> 'customer_email') !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then 'customer_email'
    when p_contact ->> 'customer_phone' is not null
         and (p_contact ->> 'customer_phone') !~ '^\+?[0-9]{8,15}$' then 'customer_phone'
    when p_contact ->> 'preferred_channel' = 'email' and p_contact ->> 'customer_email' is null then 'customer_email'
    when p_contact ->> 'preferred_channel' = 'whatsapp' and p_contact ->> 'customer_phone' is null then 'customer_phone'
    when length(coalesce(p_contact ->> 'customer_notes', '')) > 2000 then 'customer_notes'
  end;
  if v_field is not null then
    raise exception 'quote_contact_invalid' using errcode = '22023', detail = v_field;
  end if;
end;
$$;

revoke all on function public.customer_quote_validate_contact_internal(jsonb)
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 7. El cliente en el sitio (sin cuenta, sólo con su enlace)
-- ---------------------------------------------------------------------------

create or replace function public.request_public_customer_quote_v1(
  p_tenant_id uuid,
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_key text;
  v_contact jsonb;
  v_existing public.customer_quotes%rowtype;
  v_quote_id uuid;
  v_number text;
  v_access jsonb;
  v_customer uuid;
begin
  if p_tenant_id is null or p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Invalid quote request' using errcode = '22023';
  end if;
  if not exists (select 1 from public.tenants t where t.id = p_tenant_id) then
    raise exception 'Invalid tenant_id' using errcode = '22023';
  end if;

  v_key := lower(btrim(coalesce(p_request ->> 'request_idempotency_key', '')));
  if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'A random request idempotency key is required' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_tenant_id::text || ':quote:' || v_key, 0));

  select * into v_existing from public.customer_quotes q
   where q.tenant_id = p_tenant_id and q.request_idempotency_key = v_key;
  if found then
    -- La repetición devuelve la misma cotización con un enlace nuevo: el
    -- valor del anterior nunca se guardó.
    v_access := public.customer_quote_issue_token_internal(
      v_existing.id, array['view_quote', 'respond_quote'], clock_timestamp() + interval '60 days'
    );
    return jsonb_build_object(
      'quote_id', v_existing.id, 'quote_number', v_existing.quote_number,
      'access_token', v_access ->> 'token', 'expires_at', v_access ->> 'expires_at',
      'replay', true
    );
  end if;

  v_contact := public.customer_quote_contact_internal(p_request);
  perform public.customer_quote_validate_contact_internal(v_contact);

  -- Freno a un formulario automatizado: 10 por contacto al día y 60 por hora
  -- en todo el sitio (un taller recibe unas pocas al día).
  if (select count(*) from public.customer_quotes q
       where q.tenant_id = p_tenant_id and q.source = 'web'
         and q.requested_at > clock_timestamp() - interval '1 hour') >= 60
     or (select count(*) from public.customer_quotes q
          where q.tenant_id = p_tenant_id and q.source = 'web'
            and q.requested_at > clock_timestamp() - interval '1 day'
            and (q.customer_email = v_contact ->> 'customer_email'
                 or q.customer_phone = v_contact ->> 'customer_phone')) >= 10 then
    raise exception 'quote_rate_limited' using errcode = '54000';
  end if;

  -- El cliente con sesión queda unido a su ficha.
  select c.id into v_customer from public.customers c
   where c.tenant_id = p_tenant_id and c.auth_user_id = auth.uid() and auth.uid() is not null
   limit 1;

  v_number := public.customer_quote_next_number_internal(p_tenant_id);
  insert into public.customer_quotes (
    tenant_id, quote_number, status, source, customer_id, customer_name, customer_email,
    customer_phone, preferred_channel, customer_notes, request_idempotency_key
  ) values (
    p_tenant_id, v_number, 'confirming', 'web', v_customer,
    v_contact ->> 'customer_name', v_contact ->> 'customer_email', v_contact ->> 'customer_phone',
    v_contact ->> 'preferred_channel', v_contact ->> 'customer_notes', v_key
  ) returning id into v_quote_id;

  perform public.customer_quote_insert_lines_internal(v_quote_id, p_request -> 'items', true);
  perform public.customer_quote_log_internal(
    v_quote_id, 'requested', 'customer', auth.uid(), 'web', null, null,
    jsonb_build_object('lines', (select count(*) from public.customer_quote_lines where quote_id = v_quote_id),
                       'preferred_channel', v_contact ->> 'preferred_channel')
  );
  perform public.customer_quote_prepare_offer_internal(v_quote_id, 'system', null, null, null);
  perform public.customer_quote_notify_internal(
    v_quote_id, 'customer_quote_requested', 'Cotización nueva', 'customer_quote', v_quote_id, 'info'
  );

  v_access := public.customer_quote_issue_token_internal(
    v_quote_id, array['view_quote', 'respond_quote'], clock_timestamp() + interval '60 days'
  );
  return jsonb_build_object(
    'quote_id', v_quote_id, 'quote_number', v_number,
    'access_token', v_access ->> 'token', 'expires_at', v_access ->> 'expires_at',
    'replay', false
  );
end;
$$;

revoke all on function public.request_public_customer_quote_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.request_public_customer_quote_v1(uuid, jsonb)
  to anon, authenticated, service_role;

comment on function public.request_public_customer_quote_v1(uuid, jsonb) is
  'El cliente pide una cotización desde el sitio: {request_idempotency_key (UUIDv4), customer_name, customer_email, customer_phone, preferred_channel email|whatsapp, customer_notes, items: [{product_id, quantity}]}. Devuelve el número y un enlace de 60 días (sólo se guarda su huella). La base arma el borrador de la oferta y avisa al equipo.';

-- Proyección para el cliente: nunca proveedor, costo, nota interna ni datos de
-- otras cotizaciones.
create or replace function public.customer_quote_public_projection_internal(p_quote_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with q as (
    select * from public.customer_quotes where id = p_quote_id
  ), offer as (
    select o.* from public.customer_quote_offers o, q
     where o.id = q.current_offer_id
  )
  select jsonb_build_object(
    'quote', (select jsonb_strip_nulls(jsonb_build_object(
      'number', q.quote_number,
      'status', q.status,
      'customerName', q.customer_name,
      'preferredChannel', q.preferred_channel,
      'requestedAt', q.requested_at,
      'offeredAt', q.offered_at,
      'expiresAt', q.expires_at,
      'acceptedAt', q.accepted_at,
      'rejectedAt', q.rejected_at,
      'expiredAt', q.expired_at,
      'cancelledAt', q.cancelled_at
    )) from q),
    'requested', coalesce((
      select jsonb_agg(jsonb_build_object(
        'lineNo', l.line_no, 'name', l.product_name, 'sku', l.product_sku,
        'quantity', l.quantity, 'kind', l.kind_at_request
      ) order by l.line_no)
        from public.customer_quote_lines l where l.quote_id = p_quote_id
    ), '[]'::jsonb),
    'offer', (select jsonb_strip_nulls(jsonb_build_object(
      'id', offer.id,
      'number', offer.offer_no,
      'status', offer.status,
      'sentAt', offer.sent_at,
      'validUntil', offer.valid_until,
      'subtotal', offer.subtotal,
      'taxAmount', offer.tax_amount,
      'total', offer.total,
      'notes', offer.notes_to_customer,
      'lines', coalesce((
        select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
          'id', ol.id, 'lineNo', ol.line_no, 'name', ol.product_name, 'sku', ol.product_sku,
          'quantityRequested', ol.quantity_requested, 'quantity', ol.quantity_offered,
          'availability', ol.availability, 'unitPrice', ol.unit_price,
          'lineTotal', case when ol.quantity_offered > 0 then ol.unit_price * ol.quantity_offered end,
          'leadDaysMin', ol.lead_days_min, 'leadDaysMax', ol.lead_days_max,
          'note', ol.customer_note
        )) order by ol.line_no)
          from public.customer_quote_offer_lines ol where ol.offer_id = offer.id
      ), '[]'::jsonb)
    )) from offer where offer.status <> 'draft'),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object('type', e.event_type, 'at', e.occurred_at) order by e.id)
        from public.customer_quote_events e
       where e.quote_id = p_quote_id
         and e.event_type in ('requested', 'offer_sent', 'accepted', 'changes_requested', 'rejected', 'expired', 'cancelled')
    ), '[]'::jsonb)
  );
$$;

revoke all on function public.customer_quote_public_projection_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.get_public_customer_quote_v1(p_token text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_access public.customer_quote_access_tokens;
  v_quote public.customer_quotes%rowtype;
  v_can_respond boolean;
begin
  v_access := public.customer_quote_token_internal(p_token, 'view_quote');
  if v_access.id is null then
    return null;
  end if;
  select * into v_quote from public.customer_quotes
   where id = v_access.quote_id and tenant_id = v_access.tenant_id;
  if not found then
    return null;
  end if;

  -- La primera vista de una oferta enviada queda en la historia.
  if v_quote.status = 'offered' and not exists (
    select 1 from public.customer_quote_events e
     where e.quote_id = v_quote.id and e.event_type = 'viewed' and e.offer_id = v_quote.current_offer_id
  ) then
    perform public.customer_quote_log_internal(
      v_quote.id, 'viewed', 'customer', null, 'web', v_quote.current_offer_id
    );
  end if;

  v_can_respond := v_quote.status = 'offered'
    and v_access.scopes @> array['respond_quote']::text[]
    and v_quote.expires_at > clock_timestamp();

  return public.customer_quote_public_projection_internal(v_quote.id)
    || jsonb_build_object('actions', jsonb_build_object(
      'accept', v_can_respond,
      'requestChanges', v_can_respond,
      'reject', v_can_respond,
      'onOrderPrepayPercent', (public.customer_quote_settings_internal(v_quote.tenant_id)).on_order_prepay_percent
    ));
end;
$$;

revoke all on function public.get_public_customer_quote_v1(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_customer_quote_v1(text)
  to anon, authenticated, service_role;

comment on function public.get_public_customer_quote_v1(text) is
  'La cotización vista con su enlace: estado, lo pedido, la oferta vigente con sus líneas y totales, la historia visible y qué puede hacer el cliente. Sin proveedor, costo ni notas internas.';

create or replace function public.respond_public_customer_quote_v1(
  p_token text,
  p_response jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_access public.customer_quote_access_tokens;
  v_quote public.customer_quotes%rowtype;
  v_offer public.customer_quote_offers%rowtype;
  v_action text := p_response ->> 'action';
  v_key text := lower(btrim(coalesce(p_response ->> 'operation_key', '')));
  v_note text := nullif(btrim(coalesce(p_response ->> 'note', '')), '');
  v_quantities jsonb;
  v_event public.customer_quote_events%rowtype;
begin
  if p_response is null or jsonb_typeof(p_response) <> 'object'
     or v_action not in ('accept', 'request_changes', 'reject') then
    raise exception 'Invalid quote response' using errcode = '22023';
  end if;
  if v_key !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'A random operation key is required' using errcode = '22023';
  end if;
  if v_note is not null and length(v_note) > 2000 then
    raise exception 'quote_note_too_long' using errcode = '22023';
  end if;

  v_access := public.customer_quote_token_internal(p_token, 'respond_quote');
  if v_access.id is null then
    raise exception 'quote_link_invalid' using errcode = '42501';
  end if;

  select * into v_quote from public.customer_quotes
   where id = v_access.quote_id and tenant_id = v_access.tenant_id
   for update;

  -- La misma respuesta repetida devuelve lo mismo.
  select * into v_event from public.customer_quote_events e
   where e.quote_id = v_quote.id and e.operation_key = v_key;
  if found then
    return public.customer_quote_public_projection_internal(v_quote.id)
      || jsonb_build_object('replay', true);
  end if;

  if v_quote.status <> 'offered' then
    raise exception 'quote_not_open' using errcode = '55000', detail = v_quote.status;
  end if;
  select * into v_offer from public.customer_quote_offers where id = v_quote.current_offer_id for update;
  if (p_response ->> 'offer_id') is not null and (p_response ->> 'offer_id')::uuid is distinct from v_offer.id then
    raise exception 'quote_offer_outdated' using errcode = '40001';
  end if;
  if v_offer.valid_until <= clock_timestamp() then
    raise exception 'quote_offer_expired' using errcode = '55000';
  end if;

  if v_action = 'accept' then
    update public.customer_quote_offers set status = 'accepted', responded_at = clock_timestamp()
     where id = v_offer.id;
    update public.customer_quotes
       set status = 'accepted', accepted_at = clock_timestamp(),
           updated_at = clock_timestamp(), version = version + 1
     where id = v_quote.id;
    perform public.customer_quote_log_internal(
      v_quote.id, 'accepted', 'customer', null, 'web', v_offer.id, v_key,
      jsonb_build_object('total', v_offer.total, 'note', v_note)
    );
    perform public.customer_quote_notify_internal(
      v_quote.id, 'customer_quote_accepted', 'Cotización aceptada', 'customer_quote_offer', v_offer.id, 'success'
    );
  elsif v_action = 'reject' then
    update public.customer_quote_offers set status = 'rejected', responded_at = clock_timestamp()
     where id = v_offer.id;
    update public.customer_quotes
       set status = 'rejected', rejected_at = clock_timestamp(), closed_reason = v_note,
           updated_at = clock_timestamp(), version = version + 1
     where id = v_quote.id;
    perform public.customer_quote_log_internal(
      v_quote.id, 'rejected', 'customer', null, 'web', v_offer.id, v_key,
      jsonb_build_object('note', v_note)
    );
    perform public.customer_quote_notify_internal(
      v_quote.id, 'customer_quote_rejected', 'Cotización rechazada', 'customer_quote_offer', v_offer.id, 'warning'
    );
  else
    -- Pedir cambios: cantidades nuevas por número de línea (0 = quitarla).
    select coalesce(jsonb_object_agg(x ->> 'line_no', greatest(0, least(99, (x ->> 'quantity')::integer))), '{}'::jsonb)
      into v_quantities
      from jsonb_array_elements(coalesce(p_response -> 'lines', '[]'::jsonb)) x
     where (x ->> 'line_no') ~ '^[0-9]{1,2}$' and (x ->> 'quantity') ~ '^[0-9]{1,2}$';
    if v_note is null and v_quantities = '{}'::jsonb then
      raise exception 'quote_changes_required' using errcode = '22023';
    end if;
    update public.customer_quote_offers set status = 'superseded', responded_at = clock_timestamp()
     where id = v_offer.id;
    perform public.customer_quote_log_internal(
      v_quote.id, 'changes_requested', 'customer', null, 'web', v_offer.id, v_key,
      jsonb_build_object('note', v_note, 'quantities', v_quantities)
    );
    perform public.customer_quote_prepare_offer_internal(v_quote.id, 'customer', null, v_offer.id, v_quantities);
    perform public.customer_quote_notify_internal(
      v_quote.id, 'customer_quote_changes_requested', 'Cliente pidió cambios', 'customer_quote_offer', v_offer.id, 'info'
    );
  end if;

  return public.customer_quote_public_projection_internal(v_quote.id) || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.respond_public_customer_quote_v1(text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.respond_public_customer_quote_v1(text, jsonb)
  to anon, authenticated, service_role;

comment on function public.respond_public_customer_quote_v1(text, jsonb) is
  'El cliente responde con su enlace: {action accept|request_changes|reject, operation_key (UUIDv4), offer_id, note, lines: [{line_no, quantity}]}. Aceptar y rechazar cierran la oferta vigente; pedir cambios la reemplaza y la base arma un borrador nuevo. Idempotente por llave.';

-- Para el sitio: qué productos se venden a pedido y en qué plazo.
create or replace function public.get_public_on_order_terms_v1(
  p_tenant_id uuid,
  p_product_ids uuid[]
)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with policy as (select public.catalog_web_policy_v1(p_tenant_id) as v)
  select coalesce(jsonb_object_agg(t.product_id::text, jsonb_build_object(
    'leadDaysMin', t.lead_days_min, 'leadDaysMax', t.lead_days_max
  )), '{}'::jsonb)
    from public.product_on_order_terms t
    join public.products p on p.id = t.product_id and p.tenant_id = t.tenant_id
    cross join policy
   where t.tenant_id = p_tenant_id
     and t.is_active
     and t.product_id = any ((coalesce(p_product_ids, array[]::uuid[]))[1:200])
     and public.catalog_product_web_block_v1(p, policy.v) is null;
$$;

revoke all on function public.get_public_on_order_terms_v1(uuid, uuid[])
  from public, anon, authenticated, service_role;
grant execute on function public.get_public_on_order_terms_v1(uuid, uuid[])
  to anon, authenticated, service_role;

comment on function public.get_public_on_order_terms_v1(uuid, uuid[]) is
  'Plazo «a pedido» de hasta 200 productos que el sitio vende (id → {leadDaysMin, leadDaysMax}). No expone el proveedor.';

-- ---------------------------------------------------------------------------
-- 8. El equipo en el ERP
-- ---------------------------------------------------------------------------

create or replace function public.customer_quote_assert_staff_internal(p_tenant_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or p_tenant_id is null or p_tenant_id is distinct from public.user_tenant_id() then
    raise exception 'Quote not found or not accessible' using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

revoke all on function public.customer_quote_assert_staff_internal(uuid)
  from public, anon, authenticated, service_role;

create or replace function public.create_staff_customer_quote_v1(
  p_tenant_id uuid,
  p_request jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_contact jsonb;
  v_customer public.customers%rowtype;
  v_conversation uuid := nullif(p_request ->> 'conversation_id', '')::uuid;
  v_quote_id uuid;
  v_number text;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    raise exception 'Invalid quote request' using errcode = '22023';
  end if;
  -- Con una ficha de cliente, lo que no viene en el pedido sale de la ficha.
  if nullif(p_request ->> 'customer_id', '') is not null then
    select * into v_customer from public.customers c
     where c.id = (p_request ->> 'customer_id')::uuid and c.tenant_id = p_tenant_id;
    if not found then
      raise exception 'Customer not found' using errcode = 'P0002';
    end if;
    v_contact := public.customer_quote_contact_internal(p_request || jsonb_build_object(
      'customer_name', coalesce(nullif(btrim(p_request ->> 'customer_name'), ''), v_customer.name),
      'customer_email', coalesce(nullif(btrim(p_request ->> 'customer_email'), ''), v_customer.email),
      'customer_phone', coalesce(nullif(btrim(p_request ->> 'customer_phone'), ''), v_customer.phone)
    ));
  else
    v_contact := public.customer_quote_contact_internal(p_request);
  end if;
  perform public.customer_quote_validate_contact_internal(v_contact);
  if v_conversation is not null and not exists (
    select 1 from public.conversations c where c.id = v_conversation and c.tenant_id = p_tenant_id
  ) then
    raise exception 'Conversation not found' using errcode = 'P0002';
  end if;

  v_number := public.customer_quote_next_number_internal(p_tenant_id);
  insert into public.customer_quotes (
    tenant_id, quote_number, status, source, customer_id, customer_name, customer_email,
    customer_phone, preferred_channel, customer_notes, conversation_id, assigned_to, created_by
  ) values (
    p_tenant_id, v_number, 'confirming',
    case when v_conversation is not null then 'whatsapp' else 'staff' end,
    v_customer.id, v_contact ->> 'customer_name', v_contact ->> 'customer_email',
    v_contact ->> 'customer_phone', v_contact ->> 'preferred_channel', v_contact ->> 'customer_notes',
    v_conversation, v_actor, v_actor
  ) returning id into v_quote_id;

  perform public.customer_quote_insert_lines_internal(v_quote_id, p_request -> 'items', false);
  perform public.customer_quote_log_internal(
    v_quote_id, 'requested', 'staff', v_actor, 'erp', null, null,
    jsonb_build_object('lines', (select count(*) from public.customer_quote_lines where quote_id = v_quote_id))
  );
  perform public.customer_quote_prepare_offer_internal(v_quote_id, 'staff', v_actor, null, null);

  return jsonb_build_object('quote_id', v_quote_id, 'quote_number', v_number);
end;
$$;

revoke all on function public.create_staff_customer_quote_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.create_staff_customer_quote_v1(uuid, jsonb) to authenticated;

comment on function public.create_staff_customer_quote_v1(uuid, jsonb) is
  'Un trabajador arma una cotización en el ERP (mesón, teléfono o desde una conversación de WhatsApp con conversation_id): mismos productos que el sitio; customer_id opcional completa los datos de contacto.';

create or replace function public.customer_quote_inbox_v1(
  p_tenant_id uuid,
  p_status text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  return jsonb_build_object(
    'counts', (
      select coalesce(jsonb_object_agg(s.status, s.n), '{}'::jsonb)
        from (select q.status, count(*) as n from public.customer_quotes q
               where q.tenant_id = p_tenant_id group by q.status) s
    ),
    'quotes', coalesce((
      select jsonb_agg(row_to_json(r)::jsonb order by r.sort_at desc)
        from (
          select q.id, q.quote_number as number, q.status, q.source,
                 q.customer_name as "customerName", q.preferred_channel as "preferredChannel",
                 q.requested_at as "requestedAt", q.updated_at as "updatedAt",
                 q.expires_at as "expiresAt", q.updated_at as sort_at,
                 (select count(*) from public.customer_quote_lines l where l.quote_id = q.id) as lines,
                 (select o.total from public.customer_quote_offers o where o.id = q.current_offer_id) as total,
                 (select count(*) from public.customer_quote_supplier_tasks t
                   where t.quote_id = q.id and t.status = 'open') as "openTasks",
                 (select min(t.due_at) from public.customer_quote_supplier_tasks t
                   where t.quote_id = q.id and t.status = 'open') as "nextDueAt"
            from public.customer_quotes q
           where q.tenant_id = p_tenant_id
             and (p_status is null or q.status = p_status)
           order by q.updated_at desc
           limit greatest(1, least(coalesce(p_limit, 50), 200))
          offset greatest(0, coalesce(p_offset, 0))
        ) r
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.customer_quote_inbox_v1(uuid, text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_inbox_v1(uuid, text, integer, integer) to authenticated;

create or replace function public.customer_quote_detail_v1(p_tenant_id uuid, p_quote_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote public.customer_quotes%rowtype;
  v_draft uuid;
begin
  perform public.customer_quote_assert_staff_internal(p_tenant_id);
  select * into v_quote from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  select o.id into v_draft from public.customer_quote_offers o
   where o.quote_id = p_quote_id and o.status = 'draft';

  return jsonb_build_object(
    'quote', to_jsonb(v_quote) - 'request_idempotency_key',
    'settings', to_jsonb(public.customer_quote_settings_internal(p_tenant_id)),
    'requested', coalesce((select jsonb_agg(to_jsonb(l) order by l.line_no)
                             from public.customer_quote_lines l where l.quote_id = p_quote_id), '[]'::jsonb),
    'offers', coalesce((
      select jsonb_agg(to_jsonb(o) || jsonb_build_object(
        'lines', coalesce((
          select jsonb_agg(to_jsonb(ol) || jsonb_build_object(
            'supplier_name', s.name,
            'stock_now', p.inventory_qty
          ) order by ol.line_no)
            from public.customer_quote_offer_lines ol
            left join public.suppliers s on s.id = ol.supplier_id
            left join public.products p on p.id = ol.product_id
           where ol.offer_id = o.id
        ), '[]'::jsonb)
      ) order by o.offer_no desc)
        from public.customer_quote_offers o
       where o.quote_id = p_quote_id and o.status <> 'cancelled'
    ), '[]'::jsonb),
    'draftOfferId', v_draft,
    'tasks', coalesce((
      select jsonb_agg(to_jsonb(t) || jsonb_build_object(
        'supplier_name', s.name,
        'sales_rep_name', s.sales_rep_name,
        'sales_rep_phone', s.sales_rep_phone
      ) order by t.created_at)
        from public.customer_quote_supplier_tasks t
        left join public.suppliers s on s.id = t.supplier_id
       where t.quote_id = p_quote_id and t.status <> 'cancelled'
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(to_jsonb(e) order by e.id)
        from public.customer_quote_events e where e.quote_id = p_quote_id
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.customer_quote_detail_v1(uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_detail_v1(uuid, uuid) to authenticated;

create or replace function public.customer_quote_confirm_line_v1(
  p_tenant_id uuid,
  p_offer_line_id uuid,
  p_line jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_line public.customer_quote_offer_lines%rowtype;
  v_offer public.customer_quote_offers%rowtype;
  v_product public.products%rowtype;
  v_availability text := p_line ->> 'availability';
  v_qty integer;
  v_price numeric;
begin
  select l.* into v_line from public.customer_quote_offer_lines l
   where l.id = p_offer_line_id and l.tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Quote line not found or not accessible' using errcode = 'P0002';
  end if;
  select * into v_offer from public.customer_quote_offers where id = v_line.offer_id for update;
  if v_offer.status <> 'draft' then
    raise exception 'quote_offer_not_draft' using errcode = '55000';
  end if;
  if v_availability not in ('in_stock', 'on_order', 'unavailable', 'pending') then
    raise exception 'Invalid availability' using errcode = '22023';
  end if;
  select * into v_product from public.products where id = v_line.product_id;

  if v_availability = 'pending' then
    update public.customer_quote_offer_lines
       set availability = 'pending', quantity_offered = 0, unit_price = null,
           confirmed_at = null, confirmed_by = null, confirmed_by_system = false,
           staff_note = nullif(btrim(coalesce(p_line ->> 'staff_note', staff_note, '')), '')
     where id = v_line.id;
  elsif v_availability = 'unavailable' then
    update public.customer_quote_offer_lines
       set availability = 'unavailable', quantity_offered = 0, unit_price = null,
           customer_note = nullif(btrim(coalesce(p_line ->> 'customer_note', '')), ''),
           staff_note = nullif(btrim(coalesce(p_line ->> 'staff_note', '')), ''),
           confirmed_at = clock_timestamp(), confirmed_by = v_actor, confirmed_by_system = false
     where id = v_line.id;
  else
    v_qty := coalesce((p_line ->> 'quantity_offered')::integer, v_line.quantity_requested);
    v_price := coalesce((p_line ->> 'unit_price')::numeric, public.customer_quote_public_price_internal(v_product));
    if v_qty < 1 or v_qty > 99 then
      raise exception 'Invalid quantity' using errcode = '22023';
    end if;
    if v_price is null or v_price <= 0 then
      raise exception 'quote_line_price_required' using errcode = '22023';
    end if;
    update public.customer_quote_offer_lines
       set availability = v_availability,
           quantity_offered = v_qty,
           unit_price = public.clp_round(v_price),
           lead_days_min = case when v_availability = 'on_order'
                             then coalesce((p_line ->> 'lead_days_min')::smallint, lead_days_min, 3) end,
           lead_days_max = case when v_availability = 'on_order'
                             then coalesce((p_line ->> 'lead_days_max')::smallint, lead_days_max,
                                           greatest(coalesce((p_line ->> 'lead_days_min')::smallint, lead_days_min, 3), 5)) end,
           supplier_id = coalesce((p_line ->> 'supplier_id')::uuid, supplier_id),
           unit_cost_net = coalesce((p_line ->> 'unit_cost_net')::numeric, unit_cost_net),
           customer_note = nullif(btrim(coalesce(p_line ->> 'customer_note', '')), ''),
           staff_note = nullif(btrim(coalesce(p_line ->> 'staff_note', '')), ''),
           confirmed_at = clock_timestamp(), confirmed_by = v_actor, confirmed_by_system = false
     where id = v_line.id;
  end if;

  perform public.customer_quote_log_internal(
    v_offer.quote_id, 'line_confirmed', 'staff', v_actor, 'erp', v_offer.id, null,
    jsonb_build_object('line_no', v_line.line_no, 'availability', v_availability)
  );

  -- Una tarea se cierra sola cuando todas sus líneas quedan confirmadas.
  update public.customer_quote_supplier_tasks t
     set status = 'done', completed_at = clock_timestamp(), completed_by = v_actor
   where t.offer_id = v_offer.id
     and t.status = 'open'
     and not exists (
       select 1 from public.customer_quote_offer_lines l
        where l.offer_id = v_offer.id and l.availability = 'pending'
          and l.supplier_id is not distinct from t.supplier_id
     );
  if found then
    perform public.customer_quote_log_internal(
      v_offer.quote_id, 'supplier_task_done', 'staff', v_actor, 'erp', v_offer.id
    );
  end if;

  update public.customer_quotes set updated_at = clock_timestamp(), version = version + 1
   where id = v_offer.quote_id;

  return public.customer_quote_detail_v1(p_tenant_id, v_offer.quote_id);
end;
$$;

revoke all on function public.customer_quote_confirm_line_v1(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_confirm_line_v1(uuid, uuid, jsonb) to authenticated;

comment on function public.customer_quote_confirm_line_v1(uuid, uuid, jsonb) is
  'Un trabajador confirma una línea del borrador: {availability in_stock|on_order|unavailable|pending, quantity_offered, unit_price, lead_days_min, lead_days_max, unit_cost_net, supplier_id, customer_note, staff_note}. Cierra la tarea del proveedor cuando no le quedan líneas pendientes.';

create or replace function public.customer_quote_add_line_v1(
  p_tenant_id uuid,
  p_quote_id uuid,
  p_product_id uuid,
  p_quantity integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_offer public.customer_quote_offers%rowtype;
  v_product public.products%rowtype;
  v_terms public.product_on_order_terms%rowtype;
  v_line_no smallint;
begin
  select o.* into v_offer from public.customer_quote_offers o
   where o.quote_id = p_quote_id and o.tenant_id = p_tenant_id and o.status = 'draft'
   for update;
  if not found then
    raise exception 'quote_offer_not_draft' using errcode = '55000';
  end if;
  select * into v_product from public.products p
   where p.id = p_product_id and p.tenant_id = p_tenant_id;
  if not found then
    raise exception 'Product not found' using errcode = 'P0002';
  end if;
  select * into v_terms from public.product_on_order_terms t where t.product_id = p_product_id and t.is_active;
  select coalesce(max(l.line_no), 0) + 1 into v_line_no
    from public.customer_quote_offer_lines l where l.offer_id = v_offer.id;
  insert into public.customer_quote_offer_lines (
    tenant_id, offer_id, line_no, product_id, product_sku, product_name, quantity_requested,
    tax_rate, lead_days_min, lead_days_max, supplier_id
  ) values (
    p_tenant_id, v_offer.id, v_line_no, v_product.id, v_product.sku,
    coalesce(nullif(btrim(v_product.website_name), ''), v_product.name),
    greatest(1, least(99, coalesce(p_quantity, 1))), v_product.tax_rate,
    v_terms.lead_days_min, v_terms.lead_days_max, coalesce(v_terms.supplier_id, v_product.supplier_id)
  );
  perform public.customer_quote_log_internal(
    p_quote_id, 'line_added', 'staff', v_actor, 'erp', v_offer.id, null,
    jsonb_build_object('line_no', v_line_no, 'product_id', p_product_id)
  );
  update public.customer_quotes set updated_at = clock_timestamp(), version = version + 1
   where id = p_quote_id;
  return public.customer_quote_detail_v1(p_tenant_id, p_quote_id);
end;
$$;

revoke all on function public.customer_quote_add_line_v1(uuid, uuid, uuid, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_add_line_v1(uuid, uuid, uuid, integer) to authenticated;

comment on function public.customer_quote_add_line_v1(uuid, uuid, uuid, integer) is
  'Un trabajador agrega al borrador una línea más, por ejemplo una alternativa de la misma medida y otra marca. Queda pendiente hasta que la confirme.';

create or replace function public.customer_quote_send_offer_v1(
  p_tenant_id uuid,
  p_quote_id uuid,
  p_operation_key uuid,
  p_notes_to_customer text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_quote public.customer_quotes%rowtype;
  v_offer public.customer_quote_offers%rowtype;
  v_settings public.customer_quote_settings;
  v_total numeric;
  v_tax numeric;
  v_valid timestamptz;
begin
  if p_operation_key is null then
    raise exception 'An operation key is required' using errcode = '22023';
  end if;
  select * into v_quote from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.customer_quote_events e
              where e.quote_id = p_quote_id and e.operation_key = p_operation_key::text) then
    return public.customer_quote_detail_v1(p_tenant_id, p_quote_id) || jsonb_build_object('replay', true);
  end if;
  if v_quote.status <> 'confirming' then
    raise exception 'quote_not_confirming' using errcode = '55000', detail = v_quote.status;
  end if;
  select * into v_offer from public.customer_quote_offers o
   where o.quote_id = p_quote_id and o.status = 'draft'
   for update;
  if not found then
    raise exception 'quote_offer_not_draft' using errcode = '55000';
  end if;
  if exists (select 1 from public.customer_quote_offer_lines l
              where l.offer_id = v_offer.id and l.availability = 'pending') then
    raise exception 'quote_lines_pending' using errcode = '55000';
  end if;
  if not exists (select 1 from public.customer_quote_offer_lines l
                  where l.offer_id = v_offer.id and l.quantity_offered > 0) then
    raise exception 'quote_offer_empty' using errcode = '55000';
  end if;

  select sum(l.unit_price * l.quantity_offered),
         sum(public.clp_round(l.unit_price * l.quantity_offered
             - l.unit_price * l.quantity_offered / public.catalog_tax_factor_v1(l.tax_rate)))
    into v_total, v_tax
    from public.customer_quote_offer_lines l
   where l.offer_id = v_offer.id and l.quantity_offered > 0;

  v_settings := public.customer_quote_settings_internal(p_tenant_id);
  v_valid := clock_timestamp() + make_interval(hours => v_settings.offer_validity_hours);

  update public.customer_quote_offers
     set status = 'sent', sent_at = clock_timestamp(), sent_by = v_actor,
         valid_until = v_valid, total = public.clp_round(v_total),
         tax_amount = public.clp_round(coalesce(v_tax, 0)),
         subtotal = public.clp_round(v_total) - public.clp_round(coalesce(v_tax, 0)),
         notes_to_customer = nullif(btrim(coalesce(p_notes_to_customer, '')), '')
   where id = v_offer.id;
  update public.customer_quote_offers
     set status = 'superseded'
   where quote_id = p_quote_id and status = 'sent' and id <> v_offer.id;

  update public.customer_quotes
     set status = 'offered', current_offer_id = v_offer.id, offered_at = clock_timestamp(),
         expires_at = v_valid, reminder_sent_at = null,
         updated_at = clock_timestamp(), version = version + 1
   where id = p_quote_id;

  perform public.customer_quote_log_internal(
    p_quote_id, 'offer_sent', 'staff', v_actor, 'erp', v_offer.id, p_operation_key::text,
    jsonb_build_object('offer_no', v_offer.offer_no, 'total', public.clp_round(v_total),
                       'valid_until', v_valid, 'channel', v_quote.preferred_channel)
  );

  return public.customer_quote_detail_v1(p_tenant_id, p_quote_id) || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.customer_quote_send_offer_v1(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_send_offer_v1(uuid, uuid, uuid, text) to authenticated;

comment on function public.customer_quote_send_offer_v1(uuid, uuid, uuid, text) is
  'Envía el borrador como oferta: exige todas las líneas confirmadas y al menos una con cantidad; congela totales (IVA incluido) y vigencia según los ajustes, reemplaza la oferta anterior y deja el evento offer_sent que dispara los mensajes al cliente. Idempotente por llave.';

-- El equipo corrige una oferta ya enviada (un precio, un plazo, una
-- alternativa) o reabre una vencida: la enviada queda reemplazada y se arma
-- un borrador nuevo desde ella, con lo confirmado y fresco ya confirmado.
create or replace function public.customer_quote_revise_offer_v1(
  p_tenant_id uuid,
  p_quote_id uuid,
  p_operation_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_quote public.customer_quotes%rowtype;
  v_base public.customer_quote_offers%rowtype;
  v_offer_id uuid;
begin
  if p_operation_key is null then
    raise exception 'An operation key is required' using errcode = '22023';
  end if;
  select * into v_quote from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.customer_quote_events e
              where e.quote_id = p_quote_id and e.operation_key = p_operation_key::text) then
    return public.customer_quote_detail_v1(p_tenant_id, p_quote_id) || jsonb_build_object('replay', true);
  end if;
  if v_quote.status not in ('offered', 'expired') then
    raise exception 'quote_not_revisable' using errcode = '55000', detail = v_quote.status;
  end if;
  select * into v_base from public.customer_quote_offers o where o.id = v_quote.current_offer_id for update;
  if v_base.status = 'sent' then
    update public.customer_quote_offers set status = 'superseded' where id = v_base.id;
  end if;
  v_offer_id := public.customer_quote_prepare_offer_internal(
    p_quote_id, 'staff', v_actor, v_base.id, '{}'::jsonb
  );
  perform public.customer_quote_log_internal(
    p_quote_id, 'offer_revised', 'staff', v_actor, 'erp', v_offer_id, p_operation_key::text,
    jsonb_build_object('from_offer_no', v_base.offer_no, 'previous_status', v_quote.status)
  );
  return public.customer_quote_detail_v1(p_tenant_id, p_quote_id) || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.customer_quote_revise_offer_v1(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_revise_offer_v1(uuid, uuid, uuid) to authenticated;

create or replace function public.customer_quote_cancel_v1(
  p_tenant_id uuid,
  p_quote_id uuid,
  p_operation_key uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_quote public.customer_quotes%rowtype;
begin
  if p_operation_key is null or nullif(btrim(coalesce(p_reason, '')), '') is null then
    raise exception 'An operation key and a reason are required' using errcode = '22023';
  end if;
  select * into v_quote from public.customer_quotes q
   where q.id = p_quote_id and q.tenant_id = p_tenant_id
   for update;
  if not found then
    raise exception 'Quote not found or not accessible' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.customer_quote_events e
              where e.quote_id = p_quote_id and e.operation_key = p_operation_key::text) then
    return public.customer_quote_detail_v1(p_tenant_id, p_quote_id) || jsonb_build_object('replay', true);
  end if;
  if v_quote.status not in ('confirming', 'offered') then
    raise exception 'quote_not_open' using errcode = '55000', detail = v_quote.status;
  end if;
  update public.customer_quote_supplier_tasks
     set status = 'cancelled', completed_at = clock_timestamp(), completed_by = v_actor
   where quote_id = p_quote_id and status = 'open';
  update public.customer_quote_offers set status = 'cancelled'
   where quote_id = p_quote_id and status = 'draft';
  update public.customer_quote_offers set status = 'superseded'
   where quote_id = p_quote_id and status = 'sent';
  update public.customer_quotes
     set status = 'cancelled', cancelled_at = clock_timestamp(), closed_reason = btrim(p_reason),
         updated_at = clock_timestamp(), version = version + 1
   where id = p_quote_id;
  perform public.customer_quote_log_internal(
    p_quote_id, 'cancelled', 'staff', v_actor, 'erp', null, p_operation_key::text,
    jsonb_build_object('reason', btrim(p_reason))
  );
  return public.customer_quote_detail_v1(p_tenant_id, p_quote_id) || jsonb_build_object('replay', false);
end;
$$;

revoke all on function public.customer_quote_cancel_v1(uuid, uuid, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.customer_quote_cancel_v1(uuid, uuid, uuid, text) to authenticated;

create or replace function public.set_product_on_order_terms_v1(
  p_tenant_id uuid,
  p_product_id uuid,
  p_terms jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_row public.product_on_order_terms%rowtype;
  v_supplier uuid := nullif(p_terms ->> 'supplier_id', '')::uuid;
begin
  if not exists (select 1 from public.products p where p.id = p_product_id and p.tenant_id = p_tenant_id) then
    raise exception 'Product not found or not accessible' using errcode = 'P0002';
  end if;
  if v_supplier is not null and not exists (
    select 1 from public.suppliers s where s.id = v_supplier and s.tenant_id = p_tenant_id
  ) then
    raise exception 'Supplier not found' using errcode = 'P0002';
  end if;
  insert into public.product_on_order_terms (
    product_id, tenant_id, supplier_id, lead_days_min, lead_days_max, is_active, updated_by
  ) values (
    p_product_id, p_tenant_id, v_supplier,
    coalesce((p_terms ->> 'lead_days_min')::smallint, 3),
    coalesce((p_terms ->> 'lead_days_max')::smallint, 5),
    coalesce((p_terms ->> 'is_active')::boolean, true),
    v_actor
  )
  on conflict (product_id) do update
     set supplier_id = excluded.supplier_id,
         lead_days_min = excluded.lead_days_min,
         lead_days_max = excluded.lead_days_max,
         is_active = excluded.is_active,
         updated_at = clock_timestamp(),
         updated_by = v_actor
   where public.product_on_order_terms.tenant_id = p_tenant_id
  returning * into v_row;
  if v_row.product_id is null then
    raise exception 'Product not found or not accessible' using errcode = '42501';
  end if;
  return to_jsonb(v_row);
end;
$$;

revoke all on function public.set_product_on_order_terms_v1(uuid, uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.set_product_on_order_terms_v1(uuid, uuid, jsonb) to authenticated;

comment on function public.set_product_on_order_terms_v1(uuid, uuid, jsonb) is
  'Marca un producto como «se vende a pedido»: {supplier_id, lead_days_min, lead_days_max, is_active}.';

create or replace function public.update_customer_quote_settings_v1(
  p_tenant_id uuid,
  p_settings jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := public.customer_quote_assert_staff_internal(p_tenant_id);
  v_current public.customer_quote_settings := public.customer_quote_settings_internal(p_tenant_id);
  v_row public.customer_quote_settings%rowtype;
begin
  insert into public.customer_quote_settings (
    tenant_id, offer_validity_hours, reminder_hours_before, on_order_prepay_percent,
    supplier_task_due_hours, supplier_check_fresh_hours, notify_email, updated_by
  ) values (
    p_tenant_id,
    coalesce((p_settings ->> 'offer_validity_hours')::integer, v_current.offer_validity_hours),
    coalesce((p_settings ->> 'reminder_hours_before')::integer, v_current.reminder_hours_before),
    coalesce((p_settings ->> 'on_order_prepay_percent')::integer, v_current.on_order_prepay_percent),
    coalesce((p_settings ->> 'supplier_task_due_hours')::integer, v_current.supplier_task_due_hours),
    coalesce((p_settings ->> 'supplier_check_fresh_hours')::integer, v_current.supplier_check_fresh_hours),
    case when p_settings ? 'notify_email'
         then lower(nullif(btrim(coalesce(p_settings ->> 'notify_email', '')), ''))
         else v_current.notify_email end,
    v_actor
  )
  on conflict (tenant_id) do update
     set offer_validity_hours = excluded.offer_validity_hours,
         reminder_hours_before = excluded.reminder_hours_before,
         on_order_prepay_percent = excluded.on_order_prepay_percent,
         supplier_task_due_hours = excluded.supplier_task_due_hours,
         supplier_check_fresh_hours = excluded.supplier_check_fresh_hours,
         notify_email = excluded.notify_email,
         updated_at = clock_timestamp(),
         updated_by = v_actor
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

revoke all on function public.update_customer_quote_settings_v1(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.update_customer_quote_settings_v1(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- 9. Vencimiento (lo corre una tarea programada)
-- ---------------------------------------------------------------------------

create or replace function public.expire_customer_quote_offers_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_quote record;
  v_count integer := 0;
begin
  for v_quote in
    select q.id, q.current_offer_id
      from public.customer_quotes q
      join public.customer_quote_offers o on o.id = q.current_offer_id
     where q.status = 'offered'
       and o.status = 'sent'
       and o.valid_until <= clock_timestamp()
     for update of q skip locked
  loop
    update public.customer_quote_offers set status = 'expired' where id = v_quote.current_offer_id;
    update public.customer_quotes
       set status = 'expired', expired_at = clock_timestamp(),
           updated_at = clock_timestamp(), version = version + 1
     where id = v_quote.id;
    perform public.customer_quote_log_internal(
      v_quote.id, 'expired', 'system', null, 'system', v_quote.current_offer_id
    );
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.expire_customer_quote_offers_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.expire_customer_quote_offers_v1() to service_role;

comment on function public.expire_customer_quote_offers_v1() is
  'Vence las ofertas enviadas cuya vigencia pasó: la oferta y la cotización quedan «expired» con su evento. La corre pg_cron cada 15 minutos.';

do $$
declare
  v_job record;
begin
  if to_regprocedure('cron.schedule(text,text,text)') is null then
    raise notice 'pg_cron unavailable; quote expiry was not scheduled';
    return;
  end if;
  for v_job in
    select jobid from cron.job where jobname = 'vinabike_expire_customer_quote_offers'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
  perform cron.schedule(
    'vinabike_expire_customer_quote_offers',
    '7,22,37,52 * * * *',
    $job$select public.expire_customer_quote_offers_v1()$job$
  );
end
$$;

commit;
