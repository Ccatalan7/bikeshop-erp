begin;

select plan(10);

select has_table('public', 'spec_definitions', 'spec_definitions table exists');
select has_table('public', 'spec_templates', 'spec_templates table exists');
select has_table('public', 'spec_template_fields', 'spec_template_fields table exists');
select has_table('public', 'category_tech_mappings', 'category_tech_mappings table exists');

select ok(
  (
    select count(*)
    from public.spec_templates
    where tenant_id is null
      and key in (
        'chain',
        'chain_link',
        'cassette',
        'freewheel',
        'fixed_cog',
        'rear_derailleur',
        'front_derailleur',
        'shifter',
        'derailleur_hanger',
        'derailleur_pulley',
        'bottom_bracket',
        'bottom_bracket_axle',
        'bottom_bracket_cup',
        'bottom_bracket_bearing',
        'crankset',
        'crank_arm',
        'chainring',
        'chain_guide',
        'cassette_spacer',
        'drivetrain_kit'
      )
  ) = 20,
  'all first-wave drivetrain system templates exist'
);

select ok(
  exists(
    select 1
    from public.spec_definitions
    where tenant_id is null
      and key = 'drivetrain_speeds'
      and data_type = 'multi_select'
      and is_compatibility_relevant
  ),
  'drivetrain_speeds is a compatibility-relevant multi-select'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'chain'
      and sd.key = 'chain_speeds'
      and stf.is_required
  ),
  'chain template requires chain_speeds'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'cassette'
      and sd.key = 'freehub_type'
      and stf.is_required
  ),
  'cassette template requires freehub_type'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'bottom_bracket'
      and sd.key = 'bottom_bracket_family'
      and stf.is_required
  ),
  'bottom_bracket template requires bottom_bracket_family'
);

select ok(
  exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'shifter'
      and sd.key = 'shifter_position'
      and stf.is_required
  ),
  'shifter template requires shifter_position'
);

select * from finish();

rollback;
