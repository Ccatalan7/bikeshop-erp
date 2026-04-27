begin;

select plan(8);

select ok(
  exists(
    select 1
    from public.spec_definitions
    where tenant_id is null
      and key = 'drivetrain_platform'
      and data_type = 'single_select'
      and is_compatibility_relevant
  ),
  'drivetrain_platform exists as a compatibility-relevant selector'
);

select ok(
  exists(
    select 1
    from public.spec_definitions
    where tenant_id is null
      and key = 'chain_profile_family'
      and data_type = 'multi_select'
      and is_compatibility_relevant
  ),
  'chain_profile_family exists as a compatibility-relevant multi-select'
);

select ok(
  exists(
    select 1
    from public.spec_definitions
    where tenant_id is null
      and key = 'freehub_type'
      and allowed_values ? 'SRAM XDR'
  ),
  'freehub_type includes SRAM XDR'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'chain'
      and sd.key = 'chain_profile_family'
  ),
  'chain template exposes chain_profile_family'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'cassette'
      and sd.key = 'drivetrain_platform'
  ),
  'cassette template exposes drivetrain_platform'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'rear_derailleur'
      and sd.key = 'rear_derailleur_total_capacity_teeth'
  ),
  'rear_derailleur template exposes total capacity'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'chainring'
      and sd.key = 'chain_profile_family'
  ),
  'chainring template exposes chain_profile_family'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'bottom_bracket_bearing'
      and sd.key = 'bb_bearing_width_mm'
  ),
  'bottom bracket bearing template exposes bearing width'
);

select * from finish();

rollback;
