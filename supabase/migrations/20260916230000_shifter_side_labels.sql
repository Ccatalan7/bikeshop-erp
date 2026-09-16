-- «Lado» of a shifter: the slash read like two alternatives («Izquierdo / delantero»);
-- the shop says «Izquierdo (delantero)» / «Derecho (trasero)». The distributed Dart client
-- canonicalises these texts by the words izquierdo/derecho/delantero/trasero
-- (drivetrain_canonical_data.dart, bike_product_compatibility_service.dart), so the rename
-- needs no release. Three copies in one transaction: option row, allowed_values, contract text.
begin;
set local lock_timeout='5s';
update public.spec_definition_values v set label='Izquierdo (delantero)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='shifter_position' and v.label='Izquierdo / delantero';
update public.spec_definitions d set allowed_values=(select jsonb_agg(case when e=to_jsonb('Izquierdo / delantero'::text) then to_jsonb('Izquierdo (delantero)'::text) else e end order by ord) from jsonb_array_elements(d.allowed_values) with ordinality as t(e, ord)), updated_at=now() where d.tenant_id is null and d.key='shifter_position' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Izquierdo / delantero'::text]);
update public.spec_definition_values v set label='Derecho (trasero)', updated_at=now() from public.spec_definitions d where d.id=v.spec_definition_id and d.tenant_id is null and d.key='shifter_position' and v.label='Derecho / trasero';
update public.spec_definitions d set allowed_values=(select jsonb_agg(case when e=to_jsonb('Derecho / trasero'::text) then to_jsonb('Derecho (trasero)'::text) else e end order by ord) from jsonb_array_elements(d.allowed_values) with ordinality as t(e, ord)), updated_at=now() where d.tenant_id is null and d.key='shifter_position' and jsonb_typeof(d.allowed_values)='array' and d.allowed_values @> to_jsonb(array['Derecho / trasero'::text]);
update public.spec_templates t set form_contract=replace(t.form_contract::text, '"Izquierdo / delantero"', '"Izquierdo (delantero)"')::jsonb, updated_at=now() where t.tenant_id is null and t.is_active and position('"Izquierdo / delantero"' in t.form_contract::text)>0;
update public.spec_templates t set form_contract=replace(t.form_contract::text, '"Derecho / trasero"', '"Derecho (trasero)"')::jsonb, updated_at=now() where t.tenant_id is null and t.is_active and position('"Derecho / trasero"' in t.form_contract::text)>0;
commit;
