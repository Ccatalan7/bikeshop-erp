-- Deployment status: NOT DEPLOYED. Apply only after the compatible Supplier
-- editor client is published; the currently published client can submit
-- independent role/capability combinations that this migration rejects.
--
-- Forward behavior: adds the operational-resource system role and places an
-- additive server-side compatibility wrapper around the existing atomic
-- supplier profile command. No capability is required. Built-in capabilities
-- follow the closed role matrix below. Tenant extensions are accepted only
-- when both definitions are non-system and the selected custom role explicitly
-- lists the custom capability code in metadata.allowed_capability_codes.
--
-- Recovery: before any new client depends on the guard, drop the wrapper and
-- rename save_supplier_relationship_profile_v1_internal back to
-- save_supplier_relationship_profile. The seeded role is harmless to retain.
-- Once guarded writes exist, prefer a forward migration over removing the
-- invariant.
--
-- Lock/backfill risk: ALTER FUNCTION takes a brief catalog lock. The only data
-- write is one idempotent catalog upsert per tenant; no supplier assignment is
-- rewritten and no historical tag assignment is touched.

begin;

create or replace function public.validate_supplier_role_capabilities(
  p_tenant_id uuid,
  p_roles jsonb,
  p_capabilities jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_capability_code text;
  v_capability_is_system boolean;
begin
  -- The canonical command owns payload-shape and definition errors. Returning
  -- here preserves its established SQLSTATE and error ordering.
  if jsonb_typeof(coalesce(p_roles, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_capabilities, '[]'::jsonb)) <> 'array' then
    return;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_roles, '[]'::jsonb)) item
    where not exists (
      select 1
      from public.supplier_role_definitions definition
      where definition.tenant_id = p_tenant_id
        and definition.code = lower(btrim(coalesce(item->>'code', '')))
        and definition.is_active
    )
  ) or exists (
    select 1
    from jsonb_array_elements(coalesce(p_capabilities, '[]'::jsonb)) item
    where not exists (
      select 1
      from public.supplier_capability_definitions definition
      where definition.tenant_id = p_tenant_id
        and definition.code = lower(btrim(coalesce(item->>'code', '')))
        and definition.is_active
    )
  ) then
    return;
  end if;

  for v_capability_code, v_capability_is_system in
    select distinct
      definition.code,
      definition.is_system
    from jsonb_array_elements(coalesce(p_capabilities, '[]'::jsonb)) item
    join public.supplier_capability_definitions definition
      on definition.tenant_id = p_tenant_id
     and definition.code = lower(btrim(item->>'code'))
     and definition.is_active
  loop
    if not exists (
      select 1
      from jsonb_array_elements(coalesce(p_roles, '[]'::jsonb)) item
      join public.supplier_role_definitions role_definition
        on role_definition.tenant_id = p_tenant_id
       and role_definition.code = lower(btrim(item->>'code'))
       and role_definition.is_active
      where (
        v_capability_is_system
        and (role_definition.code, v_capability_code) in (
          ('goods_vendor', 'inventory_goods'),
          ('goods_vendor', 'workshop_consumables'),
          ('goods_vendor', 'purchase_invoices'),
          ('goods_vendor', 'credential_portal'),
          ('service_provider', 'purchase_invoices'),
          ('service_provider', 'credential_portal'),
          ('logistics_provider', 'freight_transport'),
          ('logistics_provider', 'purchase_invoices'),
          ('logistics_provider', 'credential_portal'),
          ('utility_provider', 'utilities'),
          ('utility_provider', 'purchase_invoices'),
          ('utility_provider', 'credential_portal'),
          ('digital_platform', 'digital_services'),
          ('digital_platform', 'purchase_invoices'),
          ('digital_platform', 'credential_portal'),
          ('landlord', 'rent_lease'),
          ('landlord', 'purchase_invoices'),
          ('landlord', 'credential_portal'),
          ('government_authority', 'tax_payments'),
          ('government_authority', 'credential_portal'),
          ('operational_resource', 'credential_portal')
        )
      ) or (
        not v_capability_is_system
        and not role_definition.is_system
        and jsonb_typeof(
          role_definition.metadata->'allowed_capability_codes'
        ) = 'array'
        and exists (
          select 1
          from jsonb_array_elements_text(
            role_definition.metadata->'allowed_capability_codes'
          ) allowed(code)
          where lower(btrim(allowed.code)) = v_capability_code
        )
      )
    ) then
      raise exception 'Supplier capability is incompatible with selected roles: %',
        v_capability_code
        using errcode = '23514';
    end if;
  end loop;
end;
$$;

comment on function public.validate_supplier_role_capabilities(
  uuid, jsonb, jsonb
) is
  'Server-only profile-payload guard. System role/capability pairs use a closed matrix; custom pairs require non-system definitions and role metadata.allowed_capability_codes.';

revoke all on function public.validate_supplier_role_capabilities(
  uuid, jsonb, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.seed_supplier_classification_definitions(
  p_tenant_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
begin
  insert into public.supplier_role_definitions (
    tenant_id, code, label, description, is_system
  ) values
    (p_tenant_id, 'goods_vendor', 'Proveedor de bienes',
      'Suministra bienes físicos para inventario u operación.', true),
    (p_tenant_id, 'service_provider', 'Proveedor de servicios',
      'Presta servicios operativos o profesionales.', true),
    (p_tenant_id, 'logistics_provider', 'Transporte y logística',
      'Mueve o entrega bienes.', true),
    (p_tenant_id, 'utility_provider', 'Servicios básicos',
      'Suministra servicios básicos del local.', true),
    (p_tenant_id, 'landlord', 'Arrendador',
      'Contraparte de arriendo o uso de inmueble.', true),
    (p_tenant_id, 'government_authority', 'Organismo público',
      'Autoridad, impuesto, tasa u obligación pública.', true),
    (p_tenant_id, 'operational_resource', 'Recurso o portal operativo',
      'Mantiene acceso, enlaces o credenciales sin una relación comercial.',
      true),
    (p_tenant_id, 'digital_platform', 'Plataforma digital',
      'Servicio de red, dominio, publicidad o software.', true)
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();

  insert into public.supplier_capability_definitions (
    tenant_id, code, label, description, is_system
  ) values
    (p_tenant_id, 'purchase_invoices', 'Emite documentos de compra',
      'Puede originar facturas u otros documentos de compra.', true),
    (p_tenant_id, 'inventory_goods', 'Bienes de inventario',
      'Suministra bienes destinados a inventario y reventa.', true),
    (p_tenant_id, 'workshop_consumables', 'Insumos de taller',
      'Suministra consumibles utilizados en servicios de taller.', true),
    (p_tenant_id, 'freight_transport', 'Flete o transporte',
      'Presta transporte, despacho o última milla.', true),
    (p_tenant_id, 'digital_services', 'Servicios digitales',
      'Presta software, dominio, red, publicidad o plataforma.', true),
    (p_tenant_id, 'utilities', 'Suministros básicos',
      'Presta electricidad, agua u otro suministro básico.', true),
    (p_tenant_id, 'rent_lease', 'Arriendo',
      'Origina obligaciones de arriendo.', true),
    (p_tenant_id, 'tax_payments', 'Impuestos y tasas',
      'Recibe impuestos, tasas u obligaciones públicas.', true),
    (p_tenant_id, 'credential_portal', 'Portal o credencial',
      'Mantiene un portal, cuenta o credencial operativa.', true)
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();

  insert into public.supplier_tag_definitions (
    tenant_id, code, label, description, is_system
  ) values
    (p_tenant_id, 'bike_industry', 'Rubro bicicleta',
      'Contraparte directamente vinculada al rubro bicicleta.', true),
    (p_tenant_id, 'recurring', 'Recurrente',
      'Relación con recurrencia operativa o contractual.', true),
    (p_tenant_id, 'essential_service', 'Servicio esencial',
      'Servicio necesario para operar el local.', true),
    (p_tenant_id, 'government', 'Gobierno',
      'Contraparte perteneciente al sector público.', true),
    (p_tenant_id, 'digital', 'Digital',
      'Relación principalmente digital.', true),
    (p_tenant_id, 'facility', 'Infraestructura del local',
      'Relación vinculada al inmueble o infraestructura.', true),
    (p_tenant_id, 'transport', 'Transporte',
      'Relación vinculada a transporte o logística.', true)
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();

  insert into public.operational_nature_definitions (
    tenant_id, code, label, nature_group, description, is_system
  ) values
    (p_tenant_id, 'inventory_goods', 'Bienes para inventario', 'inventory',
      'Bienes destinados a inventario o reventa.', true),
    (p_tenant_id, 'workshop_consumables', 'Insumos de taller', 'inventory',
      'Consumibles incorporados a servicios de taller.', true),
    (p_tenant_id, 'freight_logistics', 'Flete y logística', 'service',
      'Transporte, despacho y logística.', true),
    (p_tenant_id, 'digital_services', 'Servicios digitales', 'service',
      'Software, dominios, redes, publicidad y plataformas.', true),
    (p_tenant_id, 'utilities', 'Servicios básicos', 'operating_expense',
      'Electricidad, agua y suministros básicos.', true),
    (p_tenant_id, 'rent_lease', 'Arriendo', 'operating_expense',
      'Arriendo de inmueble o activo operativo.', true),
    (p_tenant_id, 'taxes_fees', 'Impuestos y tasas', 'tax',
      'Impuestos, tasas y obligaciones públicas.', true),
    (p_tenant_id, 'professional_services', 'Servicios profesionales', 'service',
      'Servicios profesionales o especializados.', true),
    (p_tenant_id, 'capital_assets', 'Activo de capital', 'asset',
      'Adquisición capitalizable.', true),
    (p_tenant_id, 'other_operating_expense', 'Otro gasto operacional',
      'other', 'Clasificación explícita para otros gastos operativos.', true)
  on conflict (tenant_id, code) do update
  set label = excluded.label,
      nature_group = excluded.nature_group,
      description = excluded.description,
      is_system = true,
      updated_at = clock_timestamp();
end;
$$;

revoke all on function public.seed_supplier_classification_definitions(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.seed_supplier_classification_definitions(uuid)
  to service_role;

insert into public.supplier_role_definitions (
  tenant_id,
  code,
  label,
  description,
  is_system
)
select
  tenant.id,
  'operational_resource',
  'Recurso o portal operativo',
  'Mantiene acceso, enlaces o credenciales sin una relación comercial.',
  true
from public.tenants tenant
on conflict (tenant_id, code) do update
set label = excluded.label,
    description = excluded.description,
    is_system = true,
    updated_at = clock_timestamp();

do $$
begin
  if to_regprocedure(
    'public.save_supplier_relationship_profile_v1_internal(uuid,uuid,timestamp with time zone,jsonb,jsonb,jsonb,jsonb)'
  ) is null then
    if to_regprocedure(
      'public.save_supplier_relationship_profile(uuid,uuid,timestamp with time zone,jsonb,jsonb,jsonb,jsonb)'
    ) is null then
      raise exception 'Canonical supplier profile command is missing'
        using errcode = '42883';
    end if;

    alter function public.save_supplier_relationship_profile(
      uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb
    ) rename to save_supplier_relationship_profile_v1_internal;
  end if;
end;
$$;

revoke all on function public.save_supplier_relationship_profile_v1_internal(
  uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;

create or replace function public.save_supplier_relationship_profile(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_expected_updated_at timestamptz,
  p_profile jsonb,
  p_roles jsonb,
  p_capabilities jsonb,
  p_tags jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_role text := coalesce(auth.jwt()->>'role', auth.role(), '');
  v_operation_id uuid;
begin
  if v_role <> 'service_role'
     and not public.is_active_tenant_member(p_tenant_id) then
    return public.save_supplier_relationship_profile_v1_internal(
      p_tenant_id, p_supplier_id, p_expected_updated_at, p_profile,
      p_roles, p_capabilities, p_tags
    );
  end if;

  -- Preserve the canonical command's established validation/error ordering.
  if jsonb_typeof(p_profile) <> 'object'
     or jsonb_typeof(coalesce(p_roles, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_capabilities, '[]'::jsonb)) <> 'array'
     or jsonb_typeof(coalesce(p_tags, '[]'::jsonb)) <> 'array' then
    return public.save_supplier_relationship_profile_v1_internal(
      p_tenant_id, p_supplier_id, p_expected_updated_at, p_profile,
      p_roles, p_capabilities, p_tags
    );
  end if;

  begin
    v_operation_id := nullif(p_profile->>'operation_id', '')::uuid;
  exception
    when invalid_text_representation then
      return public.save_supplier_relationship_profile_v1_internal(
        p_tenant_id, p_supplier_id, p_expected_updated_at, p_profile,
        p_roles, p_capabilities, p_tags
      );
  end;

  if v_operation_id is null or exists (
    select 1
    from public.supplier_profile_command_receipts receipt
    where receipt.tenant_id = p_tenant_id
      and receipt.operation_id = v_operation_id
  ) or exists (
    select 1
    from jsonb_array_elements(coalesce(p_roles, '[]'::jsonb)) item
    group by lower(btrim(item->>'code'))
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(coalesce(p_capabilities, '[]'::jsonb)) item
    group by lower(btrim(item->>'code'))
    having count(*) > 1
  ) or exists (
    select 1
    from jsonb_array_elements(coalesce(p_tags, '[]'::jsonb)) item
    group by lower(btrim(item->>'code'))
    having count(*) > 1
  ) then
    return public.save_supplier_relationship_profile_v1_internal(
      p_tenant_id, p_supplier_id, p_expected_updated_at, p_profile,
      p_roles, p_capabilities, p_tags
    );
  end if;

  perform public.validate_supplier_role_capabilities(
    p_tenant_id,
    p_roles,
    p_capabilities
  );

  return public.save_supplier_relationship_profile_v1_internal(
    p_tenant_id, p_supplier_id, p_expected_updated_at, p_profile,
    p_roles, p_capabilities, p_tags
  );
end;
$$;

comment on function public.save_supplier_relationship_profile(
  uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb
) is
  'Canonical supplier profile command with server-owned role/capability compatibility validation. Historical exact operation replays remain idempotent.';

revoke all on function public.save_supplier_relationship_profile(
  uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb
) from public, anon, authenticated, service_role;
grant execute on function public.save_supplier_relationship_profile(
  uuid, uuid, timestamptz, jsonb, jsonb, jsonb, jsonb
) to authenticated, service_role;

commit;
