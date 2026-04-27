-- Remove broad drivetrain semantics from rear-cog ficha templates.
-- Rear cogs must stay anchored in explicit mount/body family, speed, and range fields.

delete from public.spec_template_fields stf
using public.spec_templates st, public.spec_definitions sd
where stf.template_id = st.id
  and stf.spec_definition_id = sd.id
  and st.key in ('cassette', 'freewheel', 'fixed_cog')
  and sd.key in (
    'drivetrain_primary_ecosystem',
    'drivetrain_declared_compatible_ecosystems',
    'drivetrain_platform'
  );