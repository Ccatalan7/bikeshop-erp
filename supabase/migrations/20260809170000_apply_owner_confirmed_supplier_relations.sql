-- Apply the supplier relationships confirmed directly by the Vinabike owner.
--
-- Forward behavior: uses the canonical atomic supplier-profile command to add
-- only the confirmed operational roles/capabilities, remove the two workshop
-- capability assignments that confused local spare parts with consumables,
-- and retire the employee-only supplier relationship without deleting history.
-- No legal/contact facts, engagements, accounting policies, credentials,
-- products, source documents, or posted accounting records are changed.
--
-- Recovery: command receipts preserve the correction evidence and every
-- retained assignment keeps its durable id. The two erroneous assignments
-- were created on the current business date, so the canonical command may
-- remove those rows instead of closing a historical range. The employee
-- relationship retirement is reversible with the same command. This migration
-- never hard-deletes or repoints a supplier, party, product, or document.
--
-- Lock/write scope: sixteen supplier aggregates in one tenant. Each write
-- follows the command's operation-lock -> supplier-lock order and submits the
-- complete current non-observed assignment snapshot. Unrelated current roles,
-- capabilities, and tags are preserved by id. The migration is atomic and
-- deterministic on replay through command receipts.

begin;

create temporary table supplier_owner_relation_manifest (
  supplier_id uuid primary key,
  expected_name text not null,
  add_roles jsonb not null,
  add_capabilities jsonb not null,
  remove_capabilities jsonb not null,
  profile_patch jsonb not null,
  reason_code text not null
) on commit drop;

insert into supplier_owner_relation_manifest (
  supplier_id,
  expected_name,
  add_roles,
  add_capabilities,
  remove_capabilities,
  profile_patch,
  reason_code
)
select
  item.supplier_id,
  item.expected_name,
  item.add_roles,
  item.add_capabilities,
  item.remove_capabilities,
  item.profile_patch,
  item.reason_code
from jsonb_to_recordset($manifest$
[
  {
    "supplier_id": "9300316d-0de9-4378-9f3c-1c3bb0cf703b",
    "expected_name": "Bakery Lynch",
    "add_roles": ["service_provider"],
    "add_capabilities": [],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_food_service"
  },
  {
    "supplier_id": "4259a875-7268-460f-bdbd-0151a0693895",
    "expected_name": "Bancook",
    "add_roles": ["service_provider"],
    "add_capabilities": [],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_food_service"
  },
  {
    "supplier_id": "bd6a063a-b36b-481f-a1c0-b122a0355c12",
    "expected_name": "Bashka",
    "add_roles": ["service_provider"],
    "add_capabilities": [],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_food_service"
  },
  {
    "supplier_id": "0c1d5ec7-cfee-4d4f-9ff7-a7a235906856",
    "expected_name": "Span y Café",
    "add_roles": ["service_provider"],
    "add_capabilities": [],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_food_service"
  },
  {
    "supplier_id": "6b20d354-1032-4a9f-816e-7f58352d2843",
    "expected_name": "Ferreteria 13 norte",
    "add_roles": ["goods_vendor"],
    "add_capabilities": ["workshop_consumables"],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_workshop_supply"
  },
  {
    "supplier_id": "fdeb3efa-0d43-437a-97d7-0bebacb71614",
    "expected_name": "Ferretería Diproi",
    "add_roles": ["goods_vendor"],
    "add_capabilities": ["workshop_consumables"],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_workshop_supply"
  },
  {
    "supplier_id": "3cf3c873-7b0d-421d-8f59-68713e6c91f5",
    "expected_name": "PerniFlex",
    "add_roles": ["goods_vendor"],
    "add_capabilities": ["workshop_consumables"],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_workshop_supply"
  },
  {
    "supplier_id": "b5c67141-ac89-4298-a01d-f13d3e36c19d",
    "expected_name": "Betta Bikes",
    "add_roles": ["goods_vendor"],
    "add_capabilities": ["inventory_goods"],
    "remove_capabilities": ["workshop_consumables"],
    "profile_patch": {},
    "reason_code": "owner_confirmed_local_spare_parts"
  },
  {
    "supplier_id": "f40377ee-375d-488f-a493-963d72dca889",
    "expected_name": "DuqueBike",
    "add_roles": ["goods_vendor"],
    "add_capabilities": ["inventory_goods"],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_local_spare_parts"
  },
  {
    "supplier_id": "8c82f929-a316-4eb4-bee0-41332832a5e1",
    "expected_name": "Bicicletas Garozzo",
    "add_roles": ["goods_vendor"],
    "add_capabilities": ["inventory_goods"],
    "remove_capabilities": ["workshop_consumables"],
    "profile_patch": {},
    "reason_code": "owner_confirmed_local_spare_parts"
  },
  {
    "supplier_id": "0d636e10-cf7d-4034-a6bd-ce57eea6aeed",
    "expected_name": "Oxford Viña del Mar",
    "add_roles": ["goods_vendor"],
    "add_capabilities": ["inventory_goods"],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_local_spare_parts"
  },
  {
    "supplier_id": "edf716cd-b1c6-421a-97af-2af401831e43",
    "expected_name": "Padro Bikes",
    "add_roles": ["goods_vendor"],
    "add_capabilities": ["inventory_goods"],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_local_spare_parts"
  },
  {
    "supplier_id": "cbed73fe-c406-451d-ba7e-6fd8f14a960d",
    "expected_name": "Copec",
    "add_roles": ["goods_vendor"],
    "add_capabilities": [],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_fuel_station"
  },
  {
    "supplier_id": "40c62a2e-56b5-4e7f-b45a-c5a17ab836e9",
    "expected_name": "CVPlot",
    "add_roles": ["service_provider"],
    "add_capabilities": [],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_graphic_service"
  },
  {
    "supplier_id": "5d6cce73-b639-4fde-9eea-f404f8a68371",
    "expected_name": "Transportes Gonzalez",
    "add_roles": ["logistics_provider"],
    "add_capabilities": ["freight_transport"],
    "remove_capabilities": [],
    "profile_patch": {},
    "reason_code": "owner_confirmed_transport"
  },
  {
    "supplier_id": "45dab4b0-43f1-413c-93f0-215296be939e",
    "expected_name": "Vicente Díaz",
    "add_roles": [],
    "add_capabilities": [],
    "remove_capabilities": [],
    "profile_patch": {"is_active": false, "party_kind": "person"},
    "reason_code": "owner_confirmed_employee_not_supplier"
  }
]
$manifest$::jsonb) as item(
  supplier_id uuid,
  expected_name text,
  add_roles jsonb,
  add_capabilities jsonb,
  remove_capabilities jsonb,
  profile_patch jsonb,
  reason_code text
);

do $owner_confirmed_supplier_relations$
declare
  v_tenant_id constant uuid := '5443b130-cc28-45af-a420-cd500b288890';
  v_row record;
  v_supplier record;
  v_operation_id uuid;
  v_roles jsonb;
  v_capabilities jsonb;
  v_tags jsonb;
  v_profile jsonb;
  v_evidence jsonb;
  v_engagement_count_before bigint;
  v_policy_count_before bigint;
  v_credential_count_before bigint;
  v_product_count_before bigint;
  v_employee_count_before bigint;
begin
  if not exists (
    select 1 from public.tenants tenant where tenant.id = v_tenant_id
  ) then
    raise notice 'Vinabike tenant absent; owner-confirmed supplier relations are a no-op';
    return;
  end if;

  if (select count(*) from supplier_owner_relation_manifest) <> 16 then
    raise exception 'Owner-confirmed supplier manifest must contain 16 rows'
      using errcode = '23514';
  end if;

  if exists (
    select 1
    from supplier_owner_relation_manifest manifest
    left join public.suppliers supplier
      on supplier.tenant_id = v_tenant_id
     and supplier.id = manifest.supplier_id
     and supplier.name = manifest.expected_name
    where supplier.id is null
  ) then
    raise exception 'Owner-confirmed supplier manifest no longer matches production identity'
      using errcode = 'P0002';
  end if;

  if exists (
    select 1
    from supplier_owner_relation_manifest manifest
    join public.supplier_profile_command_receipts receipt
      on receipt.tenant_id = v_tenant_id
     and receipt.operation_id = md5(
       'vinabike_supplier_owner_relations_20260809_profile:' ||
       manifest.supplier_id::text
     )::uuid
    where receipt.supplier_id <> manifest.supplier_id
  ) then
    raise exception 'Owner-confirmed supplier operation receipt has the wrong aggregate'
      using errcode = '23505';
  end if;

  select count(*)
  into v_engagement_count_before
  from public.supplier_engagements engagement
  join supplier_owner_relation_manifest manifest
    on manifest.supplier_id = engagement.supplier_id
  where engagement.tenant_id = v_tenant_id;

  select count(*)
  into v_policy_count_before
  from public.supplier_accounting_policies policy
  join supplier_owner_relation_manifest manifest
    on manifest.supplier_id = policy.supplier_id
  where policy.tenant_id = v_tenant_id;

  select count(*)
  into v_credential_count_before
  from public.supplier_credentials credential
  join supplier_owner_relation_manifest manifest
    on manifest.supplier_id = credential.supplier_id
  where credential.tenant_id = v_tenant_id;

  select count(*)
  into v_product_count_before
  from public.products product
  join supplier_owner_relation_manifest manifest
    on manifest.supplier_id = product.supplier_id
  where product.tenant_id = v_tenant_id;

  select count(*)
  into v_employee_count_before
  from public.employees employee
  where employee.tenant_id = v_tenant_id
    and employee.status = 'active'
    and lower(btrim(employee.first_name || ' ' || employee.last_name)) =
      lower('Vicente Díaz');

  if v_employee_count_before <> 1 or (
    select count(*)
    from public.products product
    where product.tenant_id = v_tenant_id
      and product.supplier_id =
        '45dab4b0-43f1-413c-93f0-215296be939e'::uuid
  ) <> 1 or not exists (
    select 1
    from public.products product
    where product.tenant_id = v_tenant_id
      and product.id = '366c174c-9984-4fcd-a3cb-3340f3f6cab3'::uuid
      and product.supplier_id =
        '45dab4b0-43f1-413c-93f0-215296be939e'::uuid
  ) then
    raise exception 'Employee-only supplier evidence changed before correction'
      using errcode = 'P0002';
  end if;

  perform set_config(
    'request.jwt.claims',
    '{"role":"service_role"}',
    true
  );

  for v_row in
    select
      manifest.supplier_id,
      manifest.expected_name,
      manifest.add_roles,
      manifest.add_capabilities,
      manifest.remove_capabilities,
      manifest.profile_patch,
      manifest.reason_code
    from supplier_owner_relation_manifest manifest
    order by manifest.supplier_id
  loop
    v_operation_id := md5(
      'vinabike_supplier_owner_relations_20260809_profile:' ||
      v_row.supplier_id::text
    )::uuid;

    perform pg_advisory_xact_lock(hashtextextended(
      'supplier_profile_operation:' || v_tenant_id::text || ':' ||
      v_operation_id::text,
      0
    ));

    if exists (
      select 1
      from public.supplier_profile_command_receipts receipt
      where receipt.tenant_id = v_tenant_id
        and receipt.operation_id = v_operation_id
        and receipt.supplier_id = v_row.supplier_id
    ) then
      continue;
    end if;

    perform pg_advisory_xact_lock(hashtextextended(
      'supplier_profile:' || v_tenant_id::text || ':' ||
      v_row.supplier_id::text,
      0
    ));

    select supplier.party_id, supplier.updated_at
    into strict v_supplier
    from public.suppliers supplier
    where supplier.tenant_id = v_tenant_id
      and supplier.id = v_row.supplier_id
      and supplier.name = v_row.expected_name;

    if v_row.reason_code = 'owner_confirmed_employee_not_supplier'
       and (
         exists (
           select 1
           from public.supplier_relationship_roles assignment
           where assignment.tenant_id = v_tenant_id
             and assignment.supplier_id = v_row.supplier_id
             and assignment.valid_to is null
         )
         or exists (
           select 1
           from public.supplier_relationship_capabilities assignment
           where assignment.tenant_id = v_tenant_id
             and assignment.supplier_id = v_row.supplier_id
             and assignment.valid_to is null
         )
         or exists (
           select 1
           from public.supplier_relationship_tags assignment
           where assignment.tenant_id = v_tenant_id
             and assignment.supplier_id = v_row.supplier_id
             and assignment.valid_to is null
         )
       ) then
      raise exception 'Employee-only record acquired a supplier classification'
        using errcode = '40001';
    end if;

    v_evidence := jsonb_build_object(
      'source', 'owner_confirmation',
      'confirmed_on', '2026-08-09',
      'reason_code', v_row.reason_code,
      'batch', 'supplier_owner_relations_20260809'
    );

    select coalesce(jsonb_agg(item order by code), '[]'::jsonb)
    into v_roles
    from (
      select
        assignment.role_code as code,
        jsonb_build_object(
          'id', assignment.id,
          'code', assignment.role_code,
          'metadata', assignment.metadata
        ) as item
      from public.supplier_relationship_roles assignment
      where assignment.tenant_id = v_tenant_id
        and assignment.supplier_id = v_row.supplier_id
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
      union all
      select
        target.code,
        jsonb_build_object(
          'code', target.code,
          'metadata', v_evidence
        )
      from jsonb_array_elements_text(v_row.add_roles) target(code)
      where not exists (
        select 1
        from public.supplier_relationship_roles assignment
        where assignment.tenant_id = v_tenant_id
          and assignment.supplier_id = v_row.supplier_id
          and assignment.role_code = target.code
          and assignment.assignment_source <> 'observed'
          and assignment.valid_to is null
      )
    ) role_items;

    select coalesce(jsonb_agg(item order by code), '[]'::jsonb)
    into v_capabilities
    from (
      select
        assignment.capability_code as code,
        jsonb_build_object(
          'id', assignment.id,
          'code', assignment.capability_code,
          'metadata', assignment.metadata
        ) as item
      from public.supplier_relationship_capabilities assignment
      where assignment.tenant_id = v_tenant_id
        and assignment.supplier_id = v_row.supplier_id
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
        and not exists (
          select 1
          from jsonb_array_elements_text(
            v_row.remove_capabilities
          ) removed(code)
          where removed.code = assignment.capability_code
        )
      union all
      select
        target.code,
        jsonb_build_object(
          'code', target.code,
          'metadata', v_evidence
        )
      from jsonb_array_elements_text(v_row.add_capabilities) target(code)
      where not exists (
        select 1
        from public.supplier_relationship_capabilities assignment
        where assignment.tenant_id = v_tenant_id
          and assignment.supplier_id = v_row.supplier_id
          and assignment.capability_code = target.code
          and assignment.assignment_source <> 'observed'
          and assignment.valid_to is null
      )
    ) capability_items;

    select coalesce(
      jsonb_agg(
        jsonb_build_object(
          'id', assignment.id,
          'code', assignment.tag_code,
          'metadata', assignment.metadata
        ) order by assignment.tag_code
      ),
      '[]'::jsonb
    )
    into v_tags
    from public.supplier_relationship_tags assignment
    where assignment.tenant_id = v_tenant_id
      and assignment.supplier_id = v_row.supplier_id
      and assignment.assignment_source <> 'observed'
      and assignment.valid_to is null;

    v_profile := jsonb_build_object('operation_id', v_operation_id)
      || v_row.profile_patch;

    perform public.save_supplier_relationship_profile(
      v_tenant_id,
      v_row.supplier_id,
      v_supplier.updated_at,
      v_profile,
      v_roles,
      v_capabilities,
      v_tags
    );
  end loop;

  if exists (
    select 1
    from supplier_owner_relation_manifest manifest
    cross join lateral jsonb_array_elements_text(manifest.add_roles) target(code)
    where not exists (
      select 1
      from public.supplier_relationship_roles assignment
      where assignment.tenant_id = v_tenant_id
        and assignment.supplier_id = manifest.supplier_id
        and assignment.role_code = target.code
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
    )
  ) then
    raise exception 'Owner-confirmed supplier role read-back failed'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from supplier_owner_relation_manifest manifest
    cross join lateral jsonb_array_elements_text(
      manifest.add_capabilities
    ) target(code)
    where not exists (
      select 1
      from public.supplier_relationship_capabilities assignment
      where assignment.tenant_id = v_tenant_id
        and assignment.supplier_id = manifest.supplier_id
        and assignment.capability_code = target.code
        and assignment.assignment_source <> 'observed'
        and assignment.valid_to is null
    )
  ) then
    raise exception 'Owner-confirmed supplier capability read-back failed'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from supplier_owner_relation_manifest manifest
    cross join lateral jsonb_array_elements_text(
      manifest.remove_capabilities
    ) target(code)
    join public.supplier_relationship_capabilities assignment
      on assignment.tenant_id = v_tenant_id
     and assignment.supplier_id = manifest.supplier_id
     and assignment.capability_code = target.code
     and assignment.assignment_source <> 'observed'
     and assignment.valid_to is null
  ) then
    raise exception 'Owner-rejected supplier capability remains current'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from supplier_owner_relation_manifest manifest
    join public.suppliers supplier
      on supplier.tenant_id = v_tenant_id
     and supplier.id = manifest.supplier_id
    join public.external_parties party
      on party.tenant_id = v_tenant_id
     and party.id = supplier.party_id
    where manifest.profile_patch ? 'is_active'
      and (
        supplier.is_active is distinct from
          (manifest.profile_patch->>'is_active')::boolean
        or party.is_active is distinct from
          (manifest.profile_patch->>'is_active')::boolean
      )
  ) then
    raise exception 'Owner-confirmed supplier retirement read-back failed'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1
    from public.external_parties party
    join public.suppliers supplier
      on supplier.tenant_id = party.tenant_id
     and supplier.party_id = party.id
    where supplier.tenant_id = v_tenant_id
      and supplier.id = '45dab4b0-43f1-413c-93f0-215296be939e'::uuid
      and party.party_kind = 'person'
  ) then
    raise exception 'Employee counterparty kind read-back failed'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.supplier_relationship_roles assignment
    where assignment.tenant_id = v_tenant_id
      and assignment.supplier_id =
        '45dab4b0-43f1-413c-93f0-215296be939e'::uuid
      and assignment.valid_to is null
  ) or exists (
    select 1
    from public.supplier_relationship_capabilities assignment
    where assignment.tenant_id = v_tenant_id
      and assignment.supplier_id =
        '45dab4b0-43f1-413c-93f0-215296be939e'::uuid
      and assignment.valid_to is null
  ) or exists (
    select 1
    from public.supplier_relationship_tags assignment
    where assignment.tenant_id = v_tenant_id
      and assignment.supplier_id =
        '45dab4b0-43f1-413c-93f0-215296be939e'::uuid
      and assignment.valid_to is null
  ) then
    raise exception 'Employee-only record still has supplier classifications'
      using errcode = 'P0001';
  end if;

  if not exists (
    select 1 from public.supplier_relationship_roles
    where id in (
      '035c78d9-b70b-4042-aae6-cc09ffa3271c'::uuid,
      'db21c472-9bc8-4ec4-a4f7-41ff0523f59d'::uuid
    ) and valid_to is null
    group by tenant_id
    having tenant_id = v_tenant_id and count(*) = 2
  ) or not exists (
    select 1 from public.supplier_relationship_capabilities
    where id in (
      '43b54bf0-ded3-4d96-af4b-fb0f86d33e82'::uuid,
      'fd46b62e-4769-4751-8f7a-431d330cba2f'::uuid,
      '9fdaa21e-6fde-4880-86ab-c6b8024f7601'::uuid
    ) and valid_to is null
    group by tenant_id
    having tenant_id = v_tenant_id and count(*) = 3
  ) then
    raise exception 'Pre-existing supplier assignment identity was not preserved'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1
    from public.supplier_relationship_capabilities assignment
    where assignment.id in (
      '2067b032-25fa-44be-97e3-2758c7ac6ee2'::uuid,
      'a1fd3100-b243-4f92-aa94-6351a8723cc1'::uuid
    )
      and assignment.valid_to is null
  ) then
    raise exception 'Rejected workshop assignment was not retired'
      using errcode = 'P0001';
  end if;

  if (
    select count(*)
    from supplier_owner_relation_manifest manifest
    join public.supplier_profile_command_receipts receipt
      on receipt.tenant_id = v_tenant_id
     and receipt.supplier_id = manifest.supplier_id
     and receipt.operation_id = md5(
       'vinabike_supplier_owner_relations_20260809_profile:' ||
       manifest.supplier_id::text
     )::uuid
  ) <> 16 then
    raise exception 'Owner-confirmed supplier command receipt read-back failed'
      using errcode = 'P0001';
  end if;

  if v_engagement_count_before <> (
    select count(*)
    from public.supplier_engagements engagement
    join supplier_owner_relation_manifest manifest
      on manifest.supplier_id = engagement.supplier_id
    where engagement.tenant_id = v_tenant_id
  ) or v_policy_count_before <> (
    select count(*)
    from public.supplier_accounting_policies policy
    join supplier_owner_relation_manifest manifest
      on manifest.supplier_id = policy.supplier_id
    where policy.tenant_id = v_tenant_id
  ) or v_credential_count_before <> (
    select count(*)
    from public.supplier_credentials credential
    join supplier_owner_relation_manifest manifest
      on manifest.supplier_id = credential.supplier_id
    where credential.tenant_id = v_tenant_id
  ) or v_product_count_before <> (
    select count(*)
    from public.products product
    join supplier_owner_relation_manifest manifest
      on manifest.supplier_id = product.supplier_id
    where product.tenant_id = v_tenant_id
  ) or v_employee_count_before <> (
    select count(*)
    from public.employees employee
    where employee.tenant_id = v_tenant_id
      and employee.status = 'active'
      and lower(btrim(employee.first_name || ' ' || employee.last_name)) =
        lower('Vicente Díaz')
  ) or not exists (
    select 1
    from public.products product
    where product.tenant_id = v_tenant_id
      and product.id = '366c174c-9984-4fcd-a3cb-3340f3f6cab3'::uuid
      and product.supplier_id =
        '45dab4b0-43f1-413c-93f0-215296be939e'::uuid
  ) then
    raise exception 'Supplier owner correction changed an unrelated aggregate'
      using errcode = 'P0001';
  end if;
end;
$owner_confirmed_supplier_relations$;

commit;
