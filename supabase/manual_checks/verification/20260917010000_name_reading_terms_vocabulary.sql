-- Verifier: fails (division by zero) until the second batch of reading terms is present on the global definitions.
select 1/(case
  when exists (select 1 from public.spec_definition_values v join public.spec_definitions d on d.id = v.spec_definition_id
               where d.tenant_id is null and d.key = 'shifter_position' and v.label = 'Derecho (trasero)' and 'der' = any(v.reading_terms))
   and exists (select 1 from public.spec_definition_values v join public.spec_definitions d on d.id = v.spec_definition_id
               where d.tenant_id is null and d.key = 'ball_diameter_in' and v.label = '1/4' and '1 4' = any(v.reading_terms))
   and exists (select 1 from public.spec_definition_values v join public.spec_definitions d on d.id = v.spec_definition_id
               where d.tenant_id is null and d.key = 'drivetrain_mode' and v.label = 'Derailleur' and '8v' = any(v.reading_terms))
   and exists (select 1 from public.spec_definitions d
               where d.tenant_id is null and d.key = 'saddle_cutout' and 'prostatico' = any(d.reading_terms))
   and exists (select 1 from public.spec_definitions d
               where d.tenant_id is null and d.key = 'includes_spindle' and 'hollowtech' = any(d.reading_terms_false))
  then 1 else 0 end) as ok;
