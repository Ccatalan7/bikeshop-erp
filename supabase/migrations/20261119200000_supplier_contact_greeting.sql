-- Proveedores: cómo se saluda a cada contacto (2026-11-19).
--
-- Los mensajes de WhatsApp a un proveedor parten «Hola <nombre>, buen día».
-- Ese nombre lo adivinaba una regla: en el chat de un proveedor, la primera
-- palabra del vendedor principal; en la orden de compra, la regla de nombres
-- compuestos; y el servidor volvía a recortar lo que llegaba. A una persona
-- que se llama por sus dos nombres le decía uno, y al revés. El dueño, con
-- un chat abierto que saludaba sólo con el primero de dos nombres: «nunca la
-- achunta… agrega un campo a los contactos de proveedores… que por default
-- sea 1er nombre, con opción para que pueda ser los 2 nombres y otro de
-- personalizado».
--
-- Cada contacto guarda cómo se le saluda:
--   first_name  la primera palabra del nombre (por defecto)
--   two_names   los dos primeros nombres, con sus «de», «del», «la», «las» y
--               «los» entremedio («María de los Ángeles»)
--   custom      el texto de greeting_custom_name, tal cual
-- El texto del saludo lo arma la app con una sola función
-- (`contactGreetingName`, lib/shared/utils/contact_greeting.dart), la misma
-- que muestra el formulario mientras se elige.
--
-- `save_supplier_contact` acepta las dos claves nuevas. Si no vienen —una
-- app sin esta versión que guarda el contacto, o «Hacer principal»— el saludo
-- elegido se conserva; nunca vuelve solo al primer nombre.

alter table public.supplier_contacts
  add column if not exists greeting_style text not null default 'first_name',
  add column if not exists greeting_custom_name text;

alter table public.supplier_contacts
  drop constraint if exists supplier_contacts_greeting_style_known;
alter table public.supplier_contacts
  add constraint supplier_contacts_greeting_style_known
    check (greeting_style in ('first_name', 'two_names', 'custom'));

-- El texto personalizado va dentro de una plantilla de WhatsApp: sin saltos
-- de línea, tabulaciones ni espacios repetidos (Meta rechaza el parámetro),
-- sin bordes en blanco y corto.
alter table public.supplier_contacts
  drop constraint if exists supplier_contacts_greeting_custom_name_shape;
alter table public.supplier_contacts
  add constraint supplier_contacts_greeting_custom_name_shape
    check (
      greeting_custom_name is null
      or (
        char_length(greeting_custom_name) <= 60
        and greeting_custom_name ~ '^\S+( \S+)*$'
        and greeting_custom_name !~ '[[:cntrl:]]'
      )
    );

alter table public.supplier_contacts
  drop constraint if exists supplier_contacts_greeting_custom_matches_style;
alter table public.supplier_contacts
  add constraint supplier_contacts_greeting_custom_matches_style
    check ((greeting_style = 'custom') = (greeting_custom_name is not null));

comment on column public.supplier_contacts.greeting_style is
  'How WhatsApp messages greet this person: first_name (default), two_names (the first two given names, keeping de/del/la/las/los between them) or custom (greeting_custom_name). The app renders the text with contactGreetingName (lib/shared/utils/contact_greeting.dart).';
comment on column public.supplier_contacts.greeting_custom_name is
  'The exact name used in the greeting when greeting_style = custom; null otherwise.';

-- ---------------------------------------------------------------------------
-- El contacto que devuelven los comandos trae su saludo.
-- ---------------------------------------------------------------------------
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
    'greeting_style', p_contact.greeting_style,
    'greeting_custom_name', p_contact.greeting_custom_name,
    'created_at', p_contact.created_at,
    'updated_at', p_contact.updated_at
  );
$$;

-- ---------------------------------------------------------------------------
-- Crear o editar una persona, ahora con su saludo.
-- ---------------------------------------------------------------------------
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
  v_greeting_sent boolean;
  v_greeting_style text;
  v_greeting_custom text;
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
       where key not in (
         'name', 'role', 'phone', 'email', 'notes', 'is_primary',
         'greeting_style', 'greeting_custom_name'
       )
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
         and jsonb_typeof(p_contact->'is_primary') not in ('boolean', 'null'))
     or (p_contact ? 'greeting_style'
         and jsonb_typeof(p_contact->'greeting_style') not in ('string', 'null'))
     or (p_contact ? 'greeting_custom_name'
         and jsonb_typeof(p_contact->'greeting_custom_name') not in ('string', 'null')) then
    raise exception 'Contact accepts name, role, phone, email, notes, greeting_style and greeting_custom_name as text and is_primary as boolean'
      using errcode = '22023';
  end if;

  v_name := nullif(btrim(p_contact->>'name'), '');
  v_role_label := nullif(btrim(p_contact->>'role'), '');
  v_phone := nullif(btrim(p_contact->>'phone'), '');
  v_email := nullif(btrim(p_contact->>'email'), '');
  v_notes := nullif(btrim(p_contact->>'notes'), '');
  v_is_primary := coalesce((p_contact->>'is_primary')::boolean, false);

  -- El saludo viaja sólo cuando el formulario lo trae. Un null explícito
  -- vuelve al primer nombre; una clave ausente deja el que había.
  v_greeting_sent := p_contact ? 'greeting_style'
    or p_contact ? 'greeting_custom_name';
  if p_contact ? 'greeting_style' then
    v_greeting_style := coalesce(
      nullif(btrim(p_contact->>'greeting_style'), ''),
      'first_name'
    );
    if v_greeting_style not in ('first_name', 'two_names', 'custom') then
      raise exception 'Contact greeting_style must be first_name, two_names or custom'
        using errcode = '22023';
    end if;
  end if;
  v_greeting_custom := nullif(btrim(regexp_replace(
    coalesce(p_contact->>'greeting_custom_name', ''), '\s+', ' ', 'g'
  )), '');
  if v_greeting_custom is not null
     and (char_length(v_greeting_custom) > 60
          or v_greeting_custom ~ '[[:cntrl:]]') then
    raise exception 'Contact greeting name must be one short line'
      using errcode = '22023';
  end if;

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

  -- La huella de un pedido sin saludo es la misma de antes de esta versión:
  -- un reintento de una app vieja reconoce su recibo.
  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'contact_id', p_contact_id,
    'expected_updated_at', p_expected_updated_at,
    'contact', jsonb_build_object(
      'name', v_name, 'role', v_role_label, 'phone', v_phone,
      'email', v_email, 'notes', v_notes, 'is_primary', v_is_primary
    ) || case
      when v_greeting_sent then jsonb_build_object(
        'greeting_style', v_greeting_style,
        'greeting_custom_name', v_greeting_custom
      )
      else '{}'::jsonb
    end
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

  -- El saludo efectivo: lo que vino, o lo que había, o el primer nombre.
  v_greeting_style := coalesce(
    v_greeting_style,
    v_existing.greeting_style,
    'first_name'
  );
  if v_greeting_style = 'custom' then
    v_greeting_custom := coalesce(
      v_greeting_custom,
      case
        when not (p_contact ? 'greeting_custom_name')
        then v_existing.greeting_custom_name
      end
    );
    if v_greeting_custom is null then
      raise exception 'A custom greeting needs the name to use'
        using errcode = '22023';
    end if;
  else
    v_greeting_custom := null;
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
      tenant_id, supplier_id, name, role, phone, email, notes, is_primary,
      greeting_style, greeting_custom_name
    ) values (
      p_tenant_id, p_supplier_id, v_name, v_role_label, v_phone, v_email,
      v_notes, v_is_primary, v_greeting_style, v_greeting_custom
    )
    returning * into v_saved;
  else
    update public.supplier_contacts contact
    set name = v_name,
        role = v_role_label,
        phone = v_phone,
        email = v_email,
        notes = v_notes,
        is_primary = v_is_primary or (contact.is_primary and not (p_contact ? 'is_primary')),
        greeting_style = v_greeting_style,
        greeting_custom_name = v_greeting_custom
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
  'Creates or edits one supplier contact. is_primary true makes it the WhatsApp target and demotes the previous primary. greeting_style/greeting_custom_name set how messages greet the person; when absent the saved greeting is kept. Idempotent per operation id.';

revoke all on function public.save_supplier_contact(
  uuid, uuid, uuid, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.save_supplier_contact(
  uuid, uuid, uuid, timestamptz, uuid, jsonb
) to authenticated, service_role;
