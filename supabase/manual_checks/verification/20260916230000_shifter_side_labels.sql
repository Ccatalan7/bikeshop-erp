-- Verifier: fails (division by zero) while the old shifter side texts survive in any of the three copies, or the new ones are missing.
select 1/(case when
  (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id and d.tenant_id is null and d.key='shifter_position' where v.label in ('Izquierdo (delantero)','Derecho (trasero)')) = 2
  and not exists (select 1 from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id and d.key='shifter_position' where v.label in ('Izquierdo / delantero','Derecho / trasero'))
  and exists (select 1 from public.spec_definitions d where d.tenant_id is null and d.key='shifter_position' and d.allowed_values @> to_jsonb(array['Izquierdo (delantero)'::text,'Derecho (trasero)'::text]) and not d.allowed_values @> to_jsonb(array['Izquierdo / delantero'::text]))
  and not exists (select 1 from public.spec_templates t where t.is_active and (t.form_contract::text like '%"Izquierdo / delantero"%' or t.form_contract::text like '%"Derecho / trasero"%'))
  then 1 else 0 end) as ok;
