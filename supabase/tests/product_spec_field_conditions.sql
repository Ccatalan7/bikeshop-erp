begin;
set local client_min_messages=error;
select no_plan();
select is(public.spec_template_condition_internal_v1($case${"kind": "always"}$case$::jsonb,$case${}$case$::jsonb),true,'always');
select is(public.spec_template_condition_internal_v1($case${"kind": "never"}$case$::jsonb,$case${}$case$::jsonb),false,'never');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Hydraulic"}, {"field": "circuit", "operator": "eq", "value_type": "token", "value": "A"}], [{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Mechanical"}]]}$case$::jsonb,$case${"actuation": "Hydraulic", "circuit": "A"}$case$::jsonb),true,'both_and_match');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Hydraulic"}, {"field": "circuit", "operator": "eq", "value_type": "token", "value": "A"}], [{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Mechanical"}]]}$case$::jsonb,$case${"actuation": "Hydraulic", "circuit": "B"}$case$::jsonb),false,'no_cartesian_rows');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Hydraulic"}, {"field": "circuit", "operator": "eq", "value_type": "token", "value": "A"}], [{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Mechanical"}]]}$case$::jsonb,$case${"actuation": "Mechanical"}$case$::jsonb),true,'independent_alternative');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Hydraulic"}, {"field": "circuit", "operator": "eq", "value_type": "token", "value": "A"}], [{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Mechanical"}]]}$case$::jsonb,$case${"actuation": "Hydraulic"}$case$::jsonb),null::boolean,'missing_is_unknown');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Hydraulic"}, {"field": "circuit", "operator": "eq", "value_type": "token", "value": "A"}], [{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Mechanical"}]]}$case$::jsonb,$case${"actuation": "Other"}$case$::jsonb),false,'known_negative');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Hydraulic"}, {"field": "circuit", "operator": "eq", "value_type": "token", "value": "A"}], [{"field": "actuation", "operator": "eq", "value_type": "token", "value": "Mechanical"}]]}$case$::jsonb,$case${"actuation": "Mechanical", "circuit": "Desconocido / sin confirmar"}$case$::jsonb),true,'unknown_does_not_override_other_match');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "included", "operator": "eq", "value_type": "boolean", "value": false}]]}$case$::jsonb,$case${"included": false}$case$::jsonb),true,'false_is_answer');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "included", "operator": "eq", "value_type": "boolean", "value": false}]]}$case$::jsonb,$case${"included": "false"}$case$::jsonb),null::boolean,'string_false_unknown');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "model", "operator": "eq", "value_type": "token", "value": "01"}]]}$case$::jsonb,$case${"model": "1"}$case$::jsonb),false,'literal_model_01');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "model", "operator": "eq", "value_type": "token", "value": "01"}]]}$case$::jsonb,$case${"model": "01"}$case$::jsonb),true,'literal_model_01_matches');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "model", "operator": "eq", "value_type": "token", "value": "01"}]]}$case$::jsonb,$case${"model": ["01"]}$case$::jsonb),null::boolean,'list_is_not_one_model');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "diameter", "operator": "gte", "value_type": "decimal", "value": "9007199254740993.1"}]]}$case$::jsonb,$case${"diameter": "9007199254740993.0"}$case$::jsonb),false,'exact_decimal');
select is(public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "diameter", "operator": "gte", "value_type": "decimal", "value": "2"}]]}$case$::jsonb,$case${"diameter": 2}$case$::jsonb),true,'ordinary_json_number_projected');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${}$case$::jsonb,'{}')$test$,'22023',null,'invalid expression 0');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${"kind": "sometimes"}$case$::jsonb,'{}')$test$,'22023',null,'invalid expression 1');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${"kind": "always", "rows": []}$case$::jsonb,'{}')$test$,'22023',null,'invalid expression 2');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${"kind": "when", "rows": []}$case$::jsonb,'{}')$test$,'22023',null,'invalid expression 3');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[]]}$case$::jsonb,'{}')$test$,'22023',null,'invalid expression 4');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "x", "operator": "eq", "value_type": "token", "value": false}]]}$case$::jsonb,'{}')$test$,'22023',null,'invalid expression 5');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "x", "operator": "gte", "value_type": "token", "value": "01"}]]}$case$::jsonb,'{}')$test$,'22023',null,'invalid expression 6');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "diameter", "operator": "gte", "value_type": "decimal", "value": "2,5"}]]}$case$::jsonb,'{}')$test$,'22023',null,'noncanonical condition operand 0');
select throws_ok($test$select public.spec_template_condition_internal_v1($case${"kind": "when", "rows": [[{"field": "diameter", "operator": "gte", "value_type": "decimal", "value": " 2 "}]]}$case$::jsonb,'{}')$test$,'22023',null,'noncanonical condition operand 1');
insert into public.spec_definitions(id,key,label,data_type,allowed_values) values
 ('99bc0000-0000-4000-8000-000000000001','fixture_actuation','Accionamiento','single_select','["Mechanical","Hydraulic"]'),
 ('99bc0000-0000-4000-8000-000000000002','fixture_cable','Cable','single_select','["01","1","A"]');
insert into public.spec_templates(id,key,name,technical_family,form_contract) values
 ('99bc0000-0000-4000-8000-000000000010','fixture_conditions','Condiciones','fixture',
 '{"rules_version":2,"allowed_when":{"fixture_cable":{"kind":"when","rows":[[{"field":"fixture_actuation","operator":"eq","value_type":"token","value":"Mechanical"}]]}},
 "required_when":{"fixture_cable":{"kind":"when","rows":[[{"field":"fixture_actuation","operator":"eq","value_type":"token","value":"Mechanical"}]]}},
 "allowed_options":{"fixture_cable":["01"]},"prerequisites":{}}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order) values
 ('99bc0000-0000-4000-8000-000000000010','99bc0000-0000-4000-8000-000000000001','primary',1),
 ('99bc0000-0000-4000-8000-000000000010','99bc0000-0000-4000-8000-000000000002','primary',2);
select lives_ok($$set constraints spec_template_rules_guard,spec_template_field_rules_guard,spec_definition_template_rules_guard immediate$$,'complete template validates at commit boundary');
select is(public.spec_validate_draft_internal_v1('99bc0000-0000-4000-8000-000000000010','{"fixture_actuation":"Hydraulic"}'),'[]'::jsonb,'hydraulic answer does not require cable');
select is(public.spec_validate_draft_internal_v1('99bc0000-0000-4000-8000-000000000010','{}'),'[]'::jsonb,'missing upstream does not invent applicability');
select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1('99bc0000-0000-4000-8000-000000000010','{"fixture_actuation":"Mechanical"}')) i
 where i->>'code'='required_missing' and i->>'blocking'='false'),'conditional required is a nonblocking missing observation');
select ok(exists(select 1 from jsonb_array_elements(public.spec_validate_draft_internal_v1('99bc0000-0000-4000-8000-000000000010','{"fixture_actuation":"Hydraulic","fixture_cable":"01"}')) i
 where i->>'code'='field_applicability' and i->>'blocking'='true'),'upstream contradiction blocks without discarding the answer');
select is(public.spec_validate_draft_internal_v1('99bc0000-0000-4000-8000-000000000010','{"fixture_actuation":"Mechanical","fixture_cable":"01"}'),'[]'::jsonb,'literal model01 is offered');
select ok(jsonb_array_length(public.spec_validate_draft_internal_v1('99bc0000-0000-4000-8000-000000000010','{"fixture_actuation":"Mechanical","fixture_cable":"1"}'))>0,'literal model1 does not match template option01');
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_options,fixture_cable}','["B"]')
 where id='99bc0000-0000-4000-8000-000000000010'$$,'23514',null,'template cannot invent definition options');
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{prerequisites}','{"fixture_actuation":["fixture_cable"],"fixture_cable":["fixture_actuation"]}')
 where id='99bc0000-0000-4000-8000-000000000010'$$,'23514',null,'dependency cycle cannot make a field unreachable');
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{prerequisites}','{"fixture_cable":["other_family"]}')
 where id='99bc0000-0000-4000-8000-000000000010'$$,'23514',null,'prerequisite cannot belong to another family');
select throws_ok($$update public.spec_templates set form_contract=jsonb_set(form_contract,'{allowed_when,fixture_cable,rows,0,0,value}','"Mecanical"')
 where id='99bc0000-0000-4000-8000-000000000010'$$,'23514',null,'unreachable condition caused by misspelled vocabulary is rejected');
select throws_ok($$delete from public.spec_template_fields where template_id='99bc0000-0000-4000-8000-000000000010' and spec_definition_id='99bc0000-0000-4000-8000-000000000001'$$,
 '23514',null,'deleting an upstream field cannot strand its conditions');
-- Changing a key/unit invalidates an editor even without an AST reference.
insert into public.spec_definitions(id,key,label,data_type,allowed_values) values
 ('99bc0000-0000-4000-8000-000000000003','fixture_note','Nota','text','[]');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order) values
 ('99bc0000-0000-4000-8000-000000000010','99bc0000-0000-4000-8000-000000000003','primary',3);
create temporary table fixture_conditions_version as select contract_version v from public.spec_templates where id='99bc0000-0000-4000-8000-000000000010';
select lives_ok($$update public.spec_definitions set key='fixture_note_renamed' where id='99bc0000-0000-4000-8000-000000000003'$$,'an unreferenced key may be renamed through metadata');
select ok((select contract_version from public.spec_templates where id='99bc0000-0000-4000-8000-000000000010')>(select v from fixture_conditions_version),'key rename invalidates an open editor');
update fixture_conditions_version set v=(select contract_version from public.spec_templates where id='99bc0000-0000-4000-8000-000000000010');
select lives_ok($$update public.spec_definitions set unit='code' where id='99bc0000-0000-4000-8000-000000000003'$$,'unit metadata update uses the same revision boundary');
select ok((select contract_version from public.spec_templates where id='99bc0000-0000-4000-8000-000000000010')>(select v from fixture_conditions_version),'unit change invalidates an open editor');
select * from finish();
rollback;
