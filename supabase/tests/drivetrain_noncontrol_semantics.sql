begin;

select plan(3);

select ok(
  not exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key in ('chainring', 'crankset')
      and sd.key in (
        'drivetrain_primary_ecosystem',
        'drivetrain_declared_compatible_ecosystems'
      )
  ),
  'chainring and crankset templates do not expose broad ecosystem fields'
);

select ok(
  not exists(
    select 1
    from public.spec_template_fields stf
    join public.spec_templates st on st.id = stf.template_id
    join public.spec_definitions sd on sd.id = stf.spec_definition_id
    where st.tenant_id is null
      and st.key = 'chain_guide'
      and sd.key in (
        'drivetrain_primary_ecosystem',
        'drivetrain_declared_compatible_ecosystems',
        'drivetrain_platform'
      )
  ),
  'chain guide template does not expose broad ecosystem or platform fields'
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
  'chainring keeps exact downstream profile truth'
);

select * from finish();

rollback;