begin;

delete from public.product_spec_values
where spec_definition_id in (
  select id
  from public.spec_definitions
  where key = 'drivetrain_compatibility_family'
);

delete from public.spec_template_fields
where spec_definition_id in (
  select id
  from public.spec_definitions
  where key = 'drivetrain_compatibility_family'
);

delete from public.spec_definitions
where key = 'drivetrain_compatibility_family';

commit;