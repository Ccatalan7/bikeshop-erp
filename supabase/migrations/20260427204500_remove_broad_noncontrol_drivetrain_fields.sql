-- Remove broad drivetrain semantics from non-control drivetrain templates.
-- Chainrings, cranksets, and chain guides should stay anchored in explicit
-- mount/profile/platform/chainline seams instead of broad ecosystem claims.

delete from public.spec_template_fields stf
using public.spec_templates st, public.spec_definitions sd
where stf.template_id = st.id
  and stf.spec_definition_id = sd.id
  and (
    (st.key in ('chainring', 'crankset')
      and sd.key in (
        'drivetrain_primary_ecosystem',
        'drivetrain_declared_compatible_ecosystems'
      ))
    or
    (st.key = 'chain_guide'
      and sd.key in (
        'drivetrain_primary_ecosystem',
        'drivetrain_declared_compatible_ecosystems',
        'drivetrain_platform'
      ))
  );