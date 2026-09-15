-- El vendedor de un proveedor vuelve a ser editable.
--
-- `suppliers.sales_rep_name / sales_rep_phone / sales_rep_email` son el
-- contacto al que se le escribe por WhatsApp (el panel de proveedores, el chat
-- y el catálogo de compras prefieren `sales_rep_phone` y caen a `phone`). La
-- ficha nueva de proveedores (2026-08-08) dejó de mostrarlos y su comando de
-- perfil, `save_supplier_relationship_profile`, no los acepta: quedaron
-- congelados en la base y el dueño no tenía dónde cambiarlos. Editaba el
-- Teléfono y el WhatsApp seguía apuntando al vendedor antiguo.
--
-- Se repone con un comando estrecho, calcado del de la plantilla OCR: mismo
-- borde de tenant, misma concurrencia optimista, mismo recibo idempotente.
-- No se toca `save_supplier_relationship_profile` (724 líneas) para tres
-- columnas.

create table if not exists public.supplier_sales_rep_command_receipts (
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

comment on table public.supplier_sales_rep_command_receipts is
  'Private idempotency receipts for the narrow supplier sales-rep command. Results contain only the canonical sales-rep contact.';

alter table public.supplier_sales_rep_command_receipts
  enable row level security;
revoke all on table public.supplier_sales_rep_command_receipts
  from public, anon, authenticated;

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
  v_receipt public.supplier_sales_rep_command_receipts%rowtype;
  v_request_fingerprint text;
  v_name text;
  v_phone text;
  v_email text;
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

  -- Sólo las tres claves del vendedor; cada una texto o null. Un espacio en
  -- blanco es «sin dato», no un dato.
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

  v_request_fingerprint := md5(jsonb_build_object(
    'supplier_id', p_supplier_id,
    'expected_updated_at', p_expected_updated_at,
    'sales_rep', jsonb_build_object(
      'name', v_name, 'phone', v_phone, 'email', v_email
    )
  )::text);

  -- El shell del proveedor es el primer bloqueo durable de todo escritor.
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

  update public.suppliers supplier
  set sales_rep_name = v_name,
      sales_rep_phone = v_phone,
      sales_rep_email = v_email,
      updated_at = greatest(
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
  'Narrow optimistic command for the supplier sales-rep contact (name, phone, email): the person the ERP messages on WhatsApp. Idempotent per operation id.';

revoke all on function public.update_supplier_sales_rep(
  uuid, uuid, timestamptz, uuid, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.update_supplier_sales_rep(
  uuid, uuid, timestamptz, uuid, jsonb
) to authenticated, service_role;
