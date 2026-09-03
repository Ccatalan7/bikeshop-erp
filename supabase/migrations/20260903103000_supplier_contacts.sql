-- Contactos por proveedor: personas, con uno principal, que se desactivan y
-- nunca se borran.
--
-- Un proveedor es una empresa; el ERP le escribe por WhatsApp a personas, y
-- las personas cambian. Hasta hoy la ficha tenía un solo vendedor
-- (`suppliers.sales_rep_*`) y cada hilo de WhatsApp colgaba de un número: al
-- cambiar el vendedor, el hilo antiguo quedaba huérfano y el panel del chat
-- tenía que explicar dos números y un aviso (2026-09-02, Comercial Ciclo:
-- Fabiola contesta desde el número antiguo, Víctor es el vendedor nuevo).
--
-- Con esta migración:
--   · `supplier_contacts` guarda a cada persona: nombre, cargo, WhatsApp,
--     correo, si es la principal y si está activa. Desactivar conserva sus
--     chats y archivos.
--   · `suppliers.sales_rep_*` pasan a ser una proyección del contacto
--     principal activo, mantenida por trigger. Todo lo que hoy lee esas
--     columnas (panel de proveedores, chat, catálogo de compras con
--     `coalesce(sales_rep_phone, phone)`) sigue funcionando sin cambios.
--   · `whatsapp_conversation_bindings.supplier_contact_id` ata cada hilo a su
--     persona. Se resuelve solo cuando aparece un hilo, cuando una
--     conversación se vincula a un proveedor o cuando se agrega un contacto
--     con ese número.
--   · `update_supplier_sales_rep` conserva su firma y escribe a través de los
--     contactos: editar el vendedor desde el editor es editar al principal.
--
-- Respaldo: cada vendedor actual se convierte en contacto principal; cada
-- hilo de proveedor cuyo número no es de ningún contacto crea uno activo, no
-- principal, con el nombre de perfil de WhatsApp si lo hay. El ERP no puede
-- afirmar que alguien es «anterior»: eso lo decide el dueño desactivándolo.

begin;

-- ---------------------------------------------------------------------------
-- 1. Comparar números: los mismos dígitos, o los últimos nueve cuando ambos
--    los tienen (Chile: móviles y fijos de nueve dígitos nacionales; el
--    vínculo puede traer el país y la ficha no).
-- ---------------------------------------------------------------------------
create or replace function public.phone_digits_match(a text, b text)
returns boolean
language sql
immutable
strict
set search_path = pg_catalog, public, pg_temp
as $$
  select case
    when da = '' or db = '' then false
    when da = db then true
    when char_length(da) >= 9 and char_length(db) >= 9
      then right(da, 9) = right(db, 9)
    else false
  end
  from (
    select regexp_replace(a, '[^0-9]', '', 'g') as da,
           regexp_replace(b, '[^0-9]', '', 'g') as db
  ) digits;
$$;

comment on function public.phone_digits_match(text, text) is
  'True when two phone strings name the same line: identical digits, or the same last nine digits when both have at least nine.';

-- ---------------------------------------------------------------------------
-- 2. La tabla.
-- ---------------------------------------------------------------------------
create table if not exists public.supplier_contacts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  name text not null
    check (btrim(name) <> '' and char_length(name) <= 160),
  role text
    check (role is null or (btrim(role) <> '' and char_length(role) <= 120)),
  phone text
    check (
      phone is null
      or (char_length(phone) <= 40 and phone ~ '^[+0-9 ()./-]+$')
    ),
  phone_digits text generated always as (
    nullif(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), '')
  ) stored,
  email text
    check (
      email is null
      or (char_length(email) <= 320 and position('@' in email) > 1)
    ),
  notes text check (notes is null or char_length(notes) <= 2000),
  is_primary boolean not null default false,
  is_active boolean not null default true,
  deactivated_at timestamptz,
  source text not null default 'manual'
    check (source in ('manual', 'sales_rep_backfill', 'whatsapp_backfill')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade,
  -- El principal tiene que estar activo: a un inactivo no se le escribe.
  constraint supplier_contacts_primary_is_active
    check (not is_primary or is_active),
  constraint supplier_contacts_phone_has_digits
    check (phone is null or char_length(regexp_replace(phone, '[^0-9]', '', 'g')) >= 8),
  constraint supplier_contacts_deactivated_at_matches_state
    check ((is_active and deactivated_at is null) or (not is_active and deactivated_at is not null))
);

comment on table public.supplier_contacts is
  'People at a supplier the ERP talks to. One primary per supplier (the WhatsApp target); deactivated contacts keep their threads and files.';
comment on column public.supplier_contacts.is_primary is
  'The person the ERP messages by default. Projected into suppliers.sales_rep_* by trigger.';
comment on column public.supplier_contacts.source is
  'manual: created from the profile. sales_rep_backfill: the 2026-09-03 migration from suppliers.sales_rep_*. whatsapp_backfill: created from an existing supplier thread whose number matched nobody.';

create unique index if not exists supplier_contacts_one_primary_per_supplier
  on public.supplier_contacts (supplier_id)
  where is_primary;
create unique index if not exists supplier_contacts_phone_per_supplier
  on public.supplier_contacts (supplier_id, phone_digits)
  where phone_digits is not null;
create index if not exists supplier_contacts_tenant_supplier_idx
  on public.supplier_contacts (tenant_id, supplier_id, is_active);
create index if not exists supplier_contacts_tenant_phone_idx
  on public.supplier_contacts (tenant_id, phone_digits)
  where phone_digits is not null;

alter table public.supplier_contacts enable row level security;

drop policy if exists supplier_contacts_tenant on public.supplier_contacts;
create policy supplier_contacts_tenant
  on public.supplier_contacts
  for select
  using (tenant_id = public.user_tenant_id());

-- Se lee directo; se escribe sólo por los comandos de abajo. Los privilegios
-- por defecto de Supabase le dan todo a authenticated: se quitan primero.
revoke all on table public.supplier_contacts from public, anon, authenticated;
grant select on table public.supplier_contacts to authenticated;
grant select, insert, update, delete on table public.supplier_contacts
  to service_role;

create or replace function public.supplier_contacts_touch_updated_at()
returns trigger
language plpgsql
set search_path = pg_catalog, public, pg_temp
as $$
begin
  new.updated_at := greatest(
    clock_timestamp(),
    old.updated_at + interval '1 microsecond'
  );
  return new;
end;
$$;

drop trigger if exists trg_supplier_contacts_touch_updated_at
  on public.supplier_contacts;
create trigger trg_supplier_contacts_touch_updated_at
  before update on public.supplier_contacts
  for each row
  execute function public.supplier_contacts_touch_updated_at();

-- ---------------------------------------------------------------------------
-- 3. La proyección: `suppliers.sales_rep_*` = contacto principal activo.
-- ---------------------------------------------------------------------------
create or replace function public.project_supplier_primary_contact(
  p_supplier_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_name text;
  v_phone text;
  v_email text;
begin
  select contact.name, contact.phone, contact.email
  into v_name, v_phone, v_email
  from public.supplier_contacts contact
  where contact.supplier_id = p_supplier_id
    and contact.is_primary
    and contact.is_active
  limit 1;

  update public.suppliers supplier
  set sales_rep_name = v_name,
      sales_rep_phone = v_phone,
      sales_rep_email = v_email,
      updated_at = greatest(
        clock_timestamp(),
        supplier.updated_at + interval '1 microsecond'
      )
  where supplier.id = p_supplier_id
    and (
      supplier.sales_rep_name is distinct from v_name
      or supplier.sales_rep_phone is distinct from v_phone
      or supplier.sales_rep_email is distinct from v_email
    );
end;
$$;

revoke all on function public.project_supplier_primary_contact(uuid)
  from public, anon, authenticated;

create or replace function public.supplier_contacts_project_primary()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.project_supplier_primary_contact(old.supplier_id);
    return old;
  end if;
  if tg_op = 'UPDATE' and new.supplier_id is distinct from old.supplier_id then
    perform public.project_supplier_primary_contact(old.supplier_id);
  end if;
  perform public.project_supplier_primary_contact(new.supplier_id);
  return new;
end;
$$;

drop trigger if exists trg_supplier_contacts_project_primary
  on public.supplier_contacts;
create trigger trg_supplier_contacts_project_primary
  after insert or update or delete on public.supplier_contacts
  for each row
  execute function public.supplier_contacts_project_primary();

-- ---------------------------------------------------------------------------
-- 4. El vínculo hilo → persona.
-- ---------------------------------------------------------------------------
alter table public.whatsapp_conversation_bindings
  add column if not exists supplier_contact_id uuid
    references public.supplier_contacts(id) on delete set null;

comment on column public.whatsapp_conversation_bindings.supplier_contact_id is
  'The supplier contact this thread talks to. Resolved by number against the contacts of the conversation''s supplier; kept when the contact later changes number or is deactivated.';

create index if not exists idx_whatsapp_bindings_supplier_contact
  on public.whatsapp_conversation_bindings (supplier_contact_id)
  where supplier_contact_id is not null;

-- El proveedor de una conversación: contexto proveedor, o el de su compra.
create or replace function public.conversation_supplier_id(p_conversation_id uuid)
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select case conversation.context_type
    when 'supplier' then conversation.context_id
    when 'purchase_invoice' then (
      select invoice.supplier_id
      from public.purchase_invoices invoice
      where invoice.id = conversation.context_id
    )
    else null
  end
  from public.conversations conversation
  where conversation.id = p_conversation_id;
$$;

revoke all on function public.conversation_supplier_id(uuid)
  from public, anon, authenticated;

-- Resuelve el contacto de un vínculo por número. Si ya tiene uno, lo
-- conserva: la historia no se reescribe cuando alguien cambia de número.
create or replace function public.link_whatsapp_binding_supplier_contact(
  p_binding_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_binding public.whatsapp_conversation_bindings%rowtype;
  v_supplier_id uuid;
  v_contact_id uuid;
begin
  select binding.*
  into v_binding
  from public.whatsapp_conversation_bindings binding
  where binding.id = p_binding_id;
  if not found or v_binding.supplier_contact_id is not null then
    return v_binding.supplier_contact_id;
  end if;

  v_supplier_id := public.conversation_supplier_id(v_binding.conversation_id);
  if v_supplier_id is null
     or coalesce(v_binding.external_phone_number, '') = '' then
    return null;
  end if;

  select contact.id
  into v_contact_id
  from public.supplier_contacts contact
  where contact.tenant_id = v_binding.tenant_id
    and contact.supplier_id = v_supplier_id
    and contact.phone_digits is not null
    and public.phone_digits_match(
      contact.phone_digits, v_binding.external_phone_number
    )
  order by contact.is_active desc, contact.is_primary desc, contact.created_at
  limit 1;

  if v_contact_id is null then
    return null;
  end if;

  update public.whatsapp_conversation_bindings binding
  set supplier_contact_id = v_contact_id
  where binding.id = p_binding_id;
  return v_contact_id;
end;
$$;

revoke all on function public.link_whatsapp_binding_supplier_contact(uuid)
  from public, anon, authenticated;

create or replace function public.whatsapp_bindings_link_supplier_contact()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  perform public.link_whatsapp_binding_supplier_contact(new.id);
  return new;
end;
$$;

drop trigger if exists trg_whatsapp_bindings_link_supplier_contact
  on public.whatsapp_conversation_bindings;
create trigger trg_whatsapp_bindings_link_supplier_contact
  after insert or update of external_phone_number, conversation_id
  on public.whatsapp_conversation_bindings
  for each row
  when (new.supplier_contact_id is null)
  execute function public.whatsapp_bindings_link_supplier_contact();

create or replace function public.conversations_relink_supplier_contact()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_binding_id uuid;
begin
  for v_binding_id in
    select binding.id
    from public.whatsapp_conversation_bindings binding
    where binding.conversation_id = new.id
      and binding.supplier_contact_id is null
  loop
    perform public.link_whatsapp_binding_supplier_contact(v_binding_id);
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_conversations_relink_supplier_contact
  on public.conversations;
create trigger trg_conversations_relink_supplier_contact
  after update of context_type, context_id on public.conversations
  for each row
  when (new.context_id is not null)
  execute function public.conversations_relink_supplier_contact();

-- Un contacto nuevo (o con número nuevo) adopta los hilos de su proveedor que
-- todavía no tienen persona y llevan ese número.
create or replace function public.supplier_contacts_link_bindings()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  if new.phone_digits is null then
    return new;
  end if;
  update public.whatsapp_conversation_bindings binding
  set supplier_contact_id = new.id
  where binding.tenant_id = new.tenant_id
    and binding.supplier_contact_id is null
    and binding.external_phone_number is not null
    and public.phone_digits_match(binding.external_phone_number, new.phone_digits)
    and public.conversation_supplier_id(binding.conversation_id) = new.supplier_id;
  return new;
end;
$$;

drop trigger if exists trg_supplier_contacts_link_bindings
  on public.supplier_contacts;
create trigger trg_supplier_contacts_link_bindings
  after insert or update of phone on public.supplier_contacts
  for each row
  execute function public.supplier_contacts_link_bindings();

-- ---------------------------------------------------------------------------
-- 5. Recibos y comandos.
-- ---------------------------------------------------------------------------
create table if not exists public.supplier_contact_command_receipts (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  operation_id uuid not null,
  supplier_id uuid not null,
  request_fingerprint text not null check (btrim(request_fingerprint) <> ''),
  result jsonb not null check (
    jsonb_typeof(result) = 'object'
    and not public.jsonb_contains_sensitive_key(result)
  ),
  actor_id uuid references auth.users(id) on delete set null,
  applied_at timestamptz not null default clock_timestamp(),
  primary key (tenant_id, operation_id),
  foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id) on delete cascade
);

comment on table public.supplier_contact_command_receipts is
  'Private idempotency receipts for the supplier contact commands. Results contain only the canonical contact.';

alter table public.supplier_contact_command_receipts
  enable row level security;
revoke all on table public.supplier_contact_command_receipts
  from public, anon, authenticated;

create or replace function public.supplier_contact_json(
  p_contact public.supplier_contacts
)
returns jsonb
language sql
immutable
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'id', p_contact.id,
    'tenant_id', p_contact.tenant_id,
    'supplier_id', p_contact.supplier_id,
    'name', p_contact.name,
    'role', p_contact.role,
    'phone', p_contact.phone,
    'email', p_contact.email,
    'notes', p_contact.notes,
    'is_primary', p_contact.is_primary,
    'is_active', p_contact.is_active,
    'deactivated_at', p_contact.deactivated_at,
    'source', p_contact.source,
    'created_at', p_contact.created_at,
    'updated_at', p_contact.updated_at
  );
$$;

-- Crea o edita una persona. `is_primary: true` la vuelve la principal y baja
-- a la anterior. La validación es la misma del vendedor de ayer: un espacio
-- en blanco es «sin dato», el teléfono tiene al menos 8 dígitos.
create or replace function public.save_supplier_contact(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_contact_id uuid,
  p_expected_updated_at timestamptz,
  p_operation_id uuid,
  p_contact jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_supplier public.suppliers%rowtype;
  v_existing public.supplier_contacts%rowtype;
  v_saved public.supplier_contacts%rowtype;
  v_receipt public.supplier_contact_command_receipts%rowtype;
  v_request_fingerprint text;
  v_name text;
  v_role_label text;
  v_phone text;
  v_email text;
  v_notes text;
  v_is_primary boolean;
  v_result jsonb;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;
  if p_operation_id is null then
    raise exception 'Contact operation_id is required' using errcode = '22023';
  end if;
  if jsonb_typeof(p_contact) is distinct from 'object' then
    raise exception 'Contact must be an object' using errcode = '22023';
  end if;
  if public.jsonb_contains_sensitive_key(p_contact) then
    raise exception 'Contact must not contain sensitive keys'
      using errcode = '22023';
  end if;
  if exists (
       select 1
       from jsonb_object_keys(p_contact) key
       where key not in ('name', 'role', 'phone', 'email', 'notes', 'is_primary')
     )
     or (p_contact ? 'name'
         and jsonb_typeof(p_contact->'name') not in ('string', 'null'))
     or (p_contact ? 'role'
         and jsonb_typeof(p_contact->'role') not in ('string', 'null'))
     or (p_contact ? 'phone'
         and jsonb_typeof(p_contact->'phone') not in ('string', 'null'))
     or (p_contact ? 'email'
         and jsonb_typeof(p_contact->'email') not in ('string', 'null'))
     or (p_contact ? 'notes'
         and jsonb_typeof(p_contact->'notes') not in ('string', 'null'))
     or (p_contact ? 'is_primary'
         and jsonb_typeof(p_contact->'is_primary') not in ('boolean', 'null')) then
    raise exception 'Contact accepts name, role, phone, email, notes as text and is_primary as boolean'
      using errcode = '22023';
  end if;

  v_name := nullif(btrim(p_contact->>'name'), '');
  v_role_label := nullif(btrim(p_contact->>'role'), '');
  v_phone := nullif(btrim(p_contact->>'phone'), '');
  v_email := nullif(btrim(p_contact->>'email'), '');
  v_notes := nullif(btrim(p_contact->>'notes'), '');
  v_is_primary := coalesce((p_contact->>'is_primary')::boolean, false);

  if v_name is null then
    raise exception 'Contact name is required' using errcode = '22023';
  end if;
  if char_length(v_name) > 160 then
    raise exception 'Contact name is too long' using errcode = '22023';
  end if;
  if v_role_label is not null and char_length(v_role_label) > 120 then
    raise exception 'Contact role is too long' using errcode = '22023';
  end if;
  if v_phone is not null
     and (char_length(v_phone) > 40
          or v_phone !~ '^[+0-9 ()./-]+$'
          or char_length(regexp_replace(v_phone, '[^0-9]', '', 'g')) < 8) then
    raise exception 'Contact phone must have at least 8 digits'
      using errcode = '22023';
  end if;
  if v_email is not null
     and (char_length(v_email) > 320 or position('@' in v_email) < 2) then
    raise exception 'Contact email is not an address' using errcode = '22023';
  end if;
  if v_notes is not null and char_length(v_notes) > 2000 then
    raise exception 'Contact notes are too long' using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'contact_id', p_contact_id,
    'expected_updated_at', p_expected_updated_at,
    'contact', jsonb_build_object(
      'name', v_name, 'role', v_role_label, 'phone', v_phone,
      'email', v_email, 'notes', v_notes, 'is_primary', v_is_primary
    )
  )::text);

  select supplier.*
  into v_supplier
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id
  for update;
  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'supplier_contact_operation:' || p_tenant_id::text || ':' ||
      p_operation_id::text,
    0
  ));

  select receipt.*
  into v_receipt
  from public.supplier_contact_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = p_operation_id;
  if found then
    if v_receipt.supplier_id <> p_supplier_id
       or v_receipt.request_fingerprint <> v_request_fingerprint then
      raise exception 'Contact operation id was reused with different content'
        using errcode = '23505';
    end if;
    return v_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  if p_contact_id is not null then
    select contact.*
    into v_existing
    from public.supplier_contacts contact
    where contact.tenant_id = p_tenant_id
      and contact.supplier_id = p_supplier_id
      and contact.id = p_contact_id
    for update;
    if not found then
      raise exception 'Supplier contact not found' using errcode = 'P0002';
    end if;
    if v_role <> 'service_role' and p_expected_updated_at is null then
      raise exception 'Expected contact updated_at is required for contact update'
        using errcode = '22023';
    end if;
    if p_expected_updated_at is not null
       and v_existing.updated_at is distinct from p_expected_updated_at then
      raise exception 'Supplier contact changed concurrently'
        using errcode = '40001';
    end if;
    if v_is_primary and not v_existing.is_active then
      raise exception 'An inactive contact cannot be the primary contact'
        using errcode = '22023';
    end if;
  end if;

  if v_phone is not null and exists (
    select 1
    from public.supplier_contacts other
    where other.supplier_id = p_supplier_id
      and other.id is distinct from p_contact_id
      and other.phone_digits = regexp_replace(v_phone, '[^0-9]', '', 'g')
  ) then
    raise exception 'Another contact of this supplier already has that phone'
      using errcode = '23505';
  end if;

  if v_is_primary then
    update public.supplier_contacts contact
    set is_primary = false
    where contact.supplier_id = p_supplier_id
      and contact.is_primary
      and contact.id is distinct from p_contact_id;
  end if;

  if p_contact_id is null then
    insert into public.supplier_contacts (
      tenant_id, supplier_id, name, role, phone, email, notes, is_primary
    ) values (
      p_tenant_id, p_supplier_id, v_name, v_role_label, v_phone, v_email,
      v_notes, v_is_primary
    )
    returning * into v_saved;
  else
    update public.supplier_contacts contact
    set name = v_name,
        role = v_role_label,
        phone = v_phone,
        email = v_email,
        notes = v_notes,
        is_primary = v_is_primary or (contact.is_primary and not (p_contact ? 'is_primary'))
    where contact.id = p_contact_id
    returning * into v_saved;
  end if;

  v_result := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'supplier_id', p_supplier_id,
    'operation_id', p_operation_id,
    'contact', public.supplier_contact_json(v_saved),
    'idempotent_replay', false
  );

  insert into public.supplier_contact_command_receipts (
    tenant_id, operation_id, supplier_id, request_fingerprint, result, actor_id
  ) values (
    p_tenant_id, p_operation_id, p_supplier_id, v_request_fingerprint,
    v_result, case when v_role = 'service_role' then null else auth.uid() end
  );
  return v_result;
end;
$$;

comment on function public.save_supplier_contact(
  uuid, uuid, uuid, timestamptz, uuid, jsonb
) is
  'Creates or edits one supplier contact. is_primary true makes it the WhatsApp target and demotes the previous primary. Idempotent per operation id.';

revoke all on function public.save_supplier_contact(
  uuid, uuid, uuid, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.save_supplier_contact(
  uuid, uuid, uuid, timestamptz, uuid, jsonb
) to authenticated, service_role;

-- Desactivar conserva a la persona con sus hilos; sólo deja de ser
-- candidata a principal. Reactivar la devuelve sin más.
create or replace function public.set_supplier_contact_status(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_contact_id uuid,
  p_expected_updated_at timestamptz,
  p_operation_id uuid,
  p_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_supplier public.suppliers%rowtype;
  v_existing public.supplier_contacts%rowtype;
  v_saved public.supplier_contacts%rowtype;
  v_receipt public.supplier_contact_command_receipts%rowtype;
  v_request_fingerprint text;
  v_result jsonb;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;
  if p_operation_id is null or p_contact_id is null or p_is_active is null then
    raise exception 'Contact status command needs operation_id, contact_id and is_active'
      using errcode = '22023';
  end if;
  if v_role <> 'service_role' and p_expected_updated_at is null then
    raise exception 'Expected contact updated_at is required for status change'
      using errcode = '22023';
  end if;

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'contact_id', p_contact_id,
    'expected_updated_at', p_expected_updated_at,
    'is_active', p_is_active
  )::text);

  select supplier.*
  into v_supplier
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id
  for update;
  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'supplier_contact_operation:' || p_tenant_id::text || ':' ||
      p_operation_id::text,
    0
  ));

  select receipt.*
  into v_receipt
  from public.supplier_contact_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = p_operation_id;
  if found then
    if v_receipt.supplier_id <> p_supplier_id
       or v_receipt.request_fingerprint <> v_request_fingerprint then
      raise exception 'Contact operation id was reused with different content'
        using errcode = '23505';
    end if;
    return v_receipt.result || jsonb_build_object('idempotent_replay', true);
  end if;

  select contact.*
  into v_existing
  from public.supplier_contacts contact
  where contact.tenant_id = p_tenant_id
    and contact.supplier_id = p_supplier_id
    and contact.id = p_contact_id
  for update;
  if not found then
    raise exception 'Supplier contact not found' using errcode = 'P0002';
  end if;
  if p_expected_updated_at is not null
     and v_existing.updated_at is distinct from p_expected_updated_at then
    raise exception 'Supplier contact changed concurrently'
      using errcode = '40001';
  end if;

  update public.supplier_contacts contact
  set is_active = p_is_active,
      is_primary = case when p_is_active then contact.is_primary else false end,
      deactivated_at = case when p_is_active then null else clock_timestamp() end
  where contact.id = p_contact_id
  returning * into v_saved;

  v_result := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'supplier_id', p_supplier_id,
    'operation_id', p_operation_id,
    'contact', public.supplier_contact_json(v_saved),
    'idempotent_replay', false
  );

  insert into public.supplier_contact_command_receipts (
    tenant_id, operation_id, supplier_id, request_fingerprint, result, actor_id
  ) values (
    p_tenant_id, p_operation_id, p_supplier_id, v_request_fingerprint,
    v_result, case when v_role = 'service_role' then null else auth.uid() end
  );
  return v_result;
end;
$$;

comment on function public.set_supplier_contact_status(
  uuid, uuid, uuid, timestamptz, uuid, boolean
) is
  'Deactivates (keeping threads and files, dropping primary) or reactivates one supplier contact. Idempotent per operation id.';

revoke all on function public.set_supplier_contact_status(
  uuid, uuid, uuid, timestamptz, uuid, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.set_supplier_contact_status(
  uuid, uuid, uuid, timestamptz, uuid, boolean
) to authenticated, service_role;

-- El comando del vendedor conserva su firma y ahora escribe a través de los
-- contactos: edita al principal; si no hay, lo crea (o promueve al contacto
-- activo que ya tenga ese número); vacío del todo, lo desactiva. La
-- proyección a `sales_rep_*` la hace el trigger.
create or replace function public.update_supplier_sales_rep(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_expected_updated_at timestamptz,
  p_operation_id uuid,
  p_sales_rep jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_supplier public.suppliers%rowtype;
  v_primary public.supplier_contacts%rowtype;
  v_receipt public.supplier_sales_rep_command_receipts%rowtype;
  v_request_fingerprint text;
  v_name text;
  v_phone text;
  v_email text;
  v_phone_digits text;
  v_result jsonb;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    raise exception 'Active tenant membership required'
      using errcode = '42501';
  end if;

  if p_operation_id is null then
    raise exception 'Sales rep operation_id is required'
      using errcode = '22023';
  end if;

  if v_role <> 'service_role' and p_expected_updated_at is null then
    raise exception 'Expected supplier updated_at is required for sales rep update'
      using errcode = '22023';
  end if;

  if jsonb_typeof(p_sales_rep) is distinct from 'object' then
    raise exception 'Sales rep must be an object'
      using errcode = '22023';
  end if;

  if public.jsonb_contains_sensitive_key(p_sales_rep) then
    raise exception 'Sales rep must not contain sensitive keys'
      using errcode = '22023';
  end if;

  if exists (
       select 1
       from jsonb_object_keys(p_sales_rep) key
       where key not in ('name', 'phone', 'email')
     )
     or (p_sales_rep ? 'name'
         and jsonb_typeof(p_sales_rep->'name') not in ('string', 'null'))
     or (p_sales_rep ? 'phone'
         and jsonb_typeof(p_sales_rep->'phone') not in ('string', 'null'))
     or (p_sales_rep ? 'email'
         and jsonb_typeof(p_sales_rep->'email') not in ('string', 'null')) then
    raise exception 'Sales rep accepts only name, phone and email as text'
      using errcode = '22023';
  end if;

  v_name := nullif(btrim(p_sales_rep->>'name'), '');
  v_phone := nullif(btrim(p_sales_rep->>'phone'), '');
  v_email := nullif(btrim(p_sales_rep->>'email'), '');

  if v_name is not null and char_length(v_name) > 160 then
    raise exception 'Sales rep name is too long' using errcode = '22023';
  end if;
  if v_phone is not null
     and (char_length(v_phone) > 40
          or v_phone !~ '^[+0-9 ()./-]+$'
          or char_length(regexp_replace(v_phone, '[^0-9]', '', 'g')) < 8) then
    raise exception 'Sales rep phone must have at least 8 digits'
      using errcode = '22023';
  end if;
  if v_email is not null
     and (char_length(v_email) > 320 or position('@' in v_email) < 2) then
    raise exception 'Sales rep email is not an address'
      using errcode = '22023';
  end if;
  v_phone_digits := case
    when v_phone is null then null
    else regexp_replace(v_phone, '[^0-9]', '', 'g')
  end;

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'expected_updated_at', p_expected_updated_at,
    'sales_rep', jsonb_build_object(
      'name', v_name, 'phone', v_phone, 'email', v_email
    )
  )::text);

  select supplier.*
  into v_supplier
  from public.suppliers supplier
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id
  for update;

  if not found then
    raise exception 'Supplier not found in tenant' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'supplier_sales_rep_operation:' || p_tenant_id::text || ':' ||
      p_operation_id::text,
    0
  ));

  select receipt.*
  into v_receipt
  from public.supplier_sales_rep_command_receipts receipt
  where receipt.tenant_id = p_tenant_id
    and receipt.operation_id = p_operation_id;

  if found then
    if v_receipt.supplier_id <> p_supplier_id
       or v_receipt.request_fingerprint <> v_request_fingerprint then
      raise exception 'Sales rep operation id was reused with different content'
        using errcode = '23505';
    end if;

    return v_receipt.result || jsonb_build_object(
      'idempotent_replay', true
    );
  end if;

  if p_expected_updated_at is not null
     and v_supplier.updated_at is distinct from p_expected_updated_at then
    raise exception 'Supplier changed concurrently'
      using errcode = '40001';
  end if;

  select contact.*
  into v_primary
  from public.supplier_contacts contact
  where contact.supplier_id = p_supplier_id
    and contact.is_primary
    and contact.is_active
  for update;

  if v_name is null and v_phone is null and v_email is null then
    if v_primary.id is not null then
      update public.supplier_contacts contact
      set is_active = false,
          is_primary = false,
          deactivated_at = clock_timestamp()
      where contact.id = v_primary.id;
    end if;
  else
    -- Otro contacto activo con ese número: es la misma persona, se promueve.
    if v_primary.id is null and v_phone_digits is not null then
      select contact.*
      into v_primary
      from public.supplier_contacts contact
      where contact.supplier_id = p_supplier_id
        and contact.is_active
        and contact.phone_digits = v_phone_digits
      for update;
    end if;

    if v_primary.id is null then
      insert into public.supplier_contacts (
        tenant_id, supplier_id, name, phone, email, is_primary
      ) values (
        p_tenant_id, p_supplier_id, coalesce(v_name, 'Vendedor'), v_phone,
        v_email, true
      );
    else
      if v_phone_digits is not null and exists (
        select 1
        from public.supplier_contacts other
        where other.supplier_id = p_supplier_id
          and other.id <> v_primary.id
          and other.phone_digits = v_phone_digits
      ) then
        raise exception 'Another contact of this supplier already has that phone'
          using errcode = '23505';
      end if;
      update public.supplier_contacts contact
      set name = coalesce(v_name, contact.name),
          phone = v_phone,
          email = v_email,
          is_primary = true
      where contact.id = v_primary.id;
    end if;
  end if;

  -- El trigger ya proyectó `sales_rep_*`; el shell del proveedor sube su
  -- `updated_at` como antes para que el siguiente escritor lo vea.
  update public.suppliers supplier
  set updated_at = greatest(
        clock_timestamp(),
        supplier.updated_at + interval '1 microsecond'
      )
  where supplier.tenant_id = p_tenant_id
    and supplier.id = p_supplier_id
  returning * into v_supplier;

  v_result := jsonb_build_object(
    'tenant_id', p_tenant_id,
    'supplier_id', p_supplier_id,
    'operation_id', p_operation_id,
    'updated_at', v_supplier.updated_at,
    'sales_rep', jsonb_build_object(
      'name', v_supplier.sales_rep_name,
      'phone', v_supplier.sales_rep_phone,
      'email', v_supplier.sales_rep_email
    ),
    'idempotent_replay', false
  );

  insert into public.supplier_sales_rep_command_receipts (
    tenant_id,
    operation_id,
    supplier_id,
    request_fingerprint,
    result,
    actor_id
  ) values (
    p_tenant_id,
    p_operation_id,
    p_supplier_id,
    v_request_fingerprint,
    v_result,
    case when v_role = 'service_role' then null else auth.uid() end
  );

  return v_result;
end;
$$;

comment on function public.update_supplier_sales_rep(
  uuid, uuid, timestamptz, uuid, jsonb
) is
  'Narrow optimistic command for the supplier primary contact (name, phone, email). Since 2026-09-03 it writes through supplier_contacts; suppliers.sales_rep_* is the projection.';

-- ---------------------------------------------------------------------------
-- 6. Respaldo de los datos existentes.
-- ---------------------------------------------------------------------------
-- 6.a El vendedor de cada proveedor es su contacto principal. Sin número de
--     vendedor, hereda el Teléfono de la ficha: es el número al que el ERP le
--     escribía de todas formas (`coalesce(sales_rep_phone, phone)`).
insert into public.supplier_contacts (
  tenant_id, supplier_id, name, phone, email, is_primary, source
)
select
  supplier.tenant_id,
  supplier.id,
  left(coalesce(
    nullif(btrim(supplier.sales_rep_name), ''),
    nullif(btrim(supplier.contact_person), ''),
    'Vendedor'
  ), 160),
  candidate.phone,
  case
    when nullif(btrim(supplier.sales_rep_email), '') is not null
         and char_length(supplier.sales_rep_email) <= 320
         and position('@' in supplier.sales_rep_email) > 1
      then btrim(supplier.sales_rep_email)
    else null
  end,
  true,
  'sales_rep_backfill'
from public.suppliers supplier
cross join lateral (
  select (
    select raw
    from unnest(array[supplier.sales_rep_phone, supplier.phone]) with ordinality as candidates(raw, position)
    where raw is not null
      and char_length(btrim(raw)) <= 40
      and btrim(raw) ~ '^[+0-9 ()./-]+$'
      and char_length(regexp_replace(raw, '[^0-9]', '', 'g')) >= 8
    order by position
    limit 1
  ) as phone
) candidate
where nullif(btrim(supplier.sales_rep_name), '') is not null
   or (
     nullif(btrim(supplier.sales_rep_phone), '') is not null
     and char_length(regexp_replace(supplier.sales_rep_phone, '[^0-9]', '', 'g')) >= 8
   )
   or (
     nullif(btrim(supplier.contact_person), '') is not null
     and candidate.phone is not null
   );

-- 6.b Cada hilo de proveedor con un número que no es de nadie crea una
--     persona activa, no principal. Nombre: el de perfil de WhatsApp si no es
--     la empresa ni un número; si no, «Contacto de WhatsApp».
insert into public.supplier_contacts (
  tenant_id, supplier_id, name, phone, is_primary, source
)
select distinct on (thread.supplier_id, regexp_replace(thread.external_phone_number, '[^0-9]', '', 'g'))
  thread.tenant_id,
  thread.supplier_id,
  case
    when nullif(btrim(thread.contact_name), '') is null then 'Contacto de WhatsApp'
    when lower(btrim(thread.contact_name)) = lower(btrim(thread.supplier_name))
      then 'Contacto de WhatsApp'
    when regexp_replace(thread.contact_name, '[^0-9]', '', 'g')
         = regexp_replace(thread.contact_name, '[\s+().-]', '', 'g')
      then 'Contacto de WhatsApp'
    else left(btrim(thread.contact_name), 160)
  end,
  '+' || regexp_replace(thread.external_phone_number, '[^0-9]', '', 'g'),
  false,
  'whatsapp_backfill'
from (
  select binding.tenant_id,
         binding.external_phone_number,
         binding.contact_name,
         binding.created_at,
         public.conversation_supplier_id(binding.conversation_id) as supplier_id,
         supplier.name as supplier_name
  from public.whatsapp_conversation_bindings binding
  join public.suppliers supplier
    on supplier.id = public.conversation_supplier_id(binding.conversation_id)
   and supplier.tenant_id = binding.tenant_id
  where binding.external_phone_number is not null
    and char_length(regexp_replace(binding.external_phone_number, '[^0-9]', '', 'g')) >= 8
) thread
where not exists (
  select 1
  from public.supplier_contacts contact
  where contact.supplier_id = thread.supplier_id
    and contact.phone_digits is not null
    and public.phone_digits_match(contact.phone_digits, thread.external_phone_number)
)
order by thread.supplier_id,
         regexp_replace(thread.external_phone_number, '[^0-9]', '', 'g'),
         thread.created_at;

-- 6.c Todo hilo de proveedor queda atado a su persona.
select public.link_whatsapp_binding_supplier_contact(binding.id)
from public.whatsapp_conversation_bindings binding
where binding.supplier_contact_id is null
  and public.conversation_supplier_id(binding.conversation_id) is not null;

commit;
