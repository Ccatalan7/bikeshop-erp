-- Verifier: fails (division by zero) while any global definition's rows schema still names the old shifter side texts, or the new ones are missing from shifter_units.
select 1/(case when not exists (select 1 from public.spec_definitions d where d.tenant_id is null and (d.validation_rules::text like '%Izquierdo / delantero%' or d.validation_rules::text like '%Derecho / trasero%'))
  and exists (select 1 from public.spec_definitions d where d.tenant_id is null and d.key='shifter_units' and d.validation_rules::text like '%Izquierdo (delantero)%' and d.validation_rules::text like '%Derecho (trasero)%')
  then 1 else 0 end) as ok;
