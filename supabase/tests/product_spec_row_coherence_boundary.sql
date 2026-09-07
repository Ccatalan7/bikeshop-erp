-- Independent row-coherence regressions: endpoints, units, populated metadata,
-- exact bounds, row identity, derived labels, rejected readings and ACL.
-- Synthetic only: no SKU attribution, no OEM claim, every row has sources [].
-- Every assertion expects the corrected contract (insert-or-update populated
-- guard, endpoint-only comparison, order cycles rejected); see
-- docs/development/product-specs-research-2026-09-05/row-coherence-implementation-review-2026-09-07.md.
begin;
set local client_min_messages=error;
\ir fixtures/product_spec_binding_prerequisites.sql
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values('c0be0000-0000-4000-8000-000000000001','Coherence boundary');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('c0be0000-0000-4000-8000-000000000091','authenticated','authenticated','coherence-boundary@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"c0be0000-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='c0be0000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values('c0be0000-0000-4000-8000-000000000091','c0be0000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"c0be0000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','c0be0000-0000-4000-8000-000000000091',true);

-- Definitions: three rows fields, two mm bounds, one inch bound, one inherited
-- pair with mismatched units and one inherited pair without units.
insert into public.spec_definitions(id,tenant_id,key,label,data_type,unit,is_filterable,is_customer_visible,validation_rules) values
 ('c0be0000-0000-4000-8000-000000000011','c0be0000-0000-4000-8000-000000000001','ports','Puertos','json',null,false,true,
  '{"rows_schema":{"version":1,"columns":[{"key":"name","label":"Puerto","type":"text"},{"key":"fast","label":"Rápido","type":"boolean"}]}}'),
 ('c0be0000-0000-4000-8000-000000000012','c0be0000-0000-4000-8000-000000000001','allocations','Reparto','json',null,false,true,
  '{"rows_schema":{"version":1,"columns":[{"key":"port_row_id","label":"Puerto de esta ficha","type":"text","required":true},{"key":"port_kind","label":"Clase","type":"token","allowed_values":["A","B"]},{"key":"power_w","label":"Potencia","type":"decimal","unit":"W"}]}}'),
 ('c0be0000-0000-4000-8000-000000000013','c0be0000-0000-4000-8000-000000000001','groups','Grupos','json',null,false,true,
  '{"rows_schema":{"version":1,"columns":[{"key":"alloc_row_id","label":"Reparto","type":"text"},{"key":"title","label":"Título","type":"text"}]}}'),
 ('c0be0000-0000-4000-8000-000000000014','c0be0000-0000-4000-8000-000000000001','lower','Límite inferior','number','mm',true,true,'{}'),
 ('c0be0000-0000-4000-8000-000000000015','c0be0000-0000-4000-8000-000000000001','upper','Límite superior','number','mm',true,true,'{}'),
 ('c0be0000-0000-4000-8000-000000000016','c0be0000-0000-4000-8000-000000000001','upper_in','Límite en pulgadas','number','in',false,true,'{}'),
 ('c0be0000-0000-4000-8000-000000000017','c0be0000-0000-4000-8000-000000000001','tube_width_min_mm','Ancho mínimo','number','mm',false,true,'{}'),
 ('c0be0000-0000-4000-8000-000000000018','c0be0000-0000-4000-8000-000000000001','tube_width_max_mm','Ancho máximo','number','in',false,true,'{}'),
 ('c0be0000-0000-4000-8000-000000000019','c0be0000-0000-4000-8000-000000000001','smallest_cog_teeth','Piñón menor','number',null,false,true,'{}'),
 ('c0be0000-0000-4000-8000-00000000001a','c0be0000-0000-4000-8000-000000000001','largest_cog_teeth','Piñón mayor','number',null,false,true,'{}');
create function pg_temp.base_contract() returns jsonb language sql immutable as $$
 select '{"rules_version":2,"allowed_when":{},"required_when":{},"prerequisites":{},"allowed_options":{},
   "row_coherence":{"version":1,"links":[{"id":"allocation_port","field":"allocations","column":"port_row_id","target_field":"ports","label_columns":["name","fast"]}]},
   "scalar_ordered_pairs":[["lower","upper"]]}'::jsonb
$$;
insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
values('c0be0000-0000-4000-8000-000000000050','c0be0000-0000-4000-8000-000000000001','coherence_boundary','Coherence boundary','fixture_coherence_boundary',pg_temp.base_contract());
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select 'c0be0000-0000-4000-8000-000000000050',id,'measurement',1 from public.spec_definitions where tenant_id='c0be0000-0000-4000-8000-000000000001';
set constraints all immediate;

create function pg_temp.contract(p_extra jsonb) returns void language sql as $$
 update public.spec_templates set form_contract=pg_temp.base_contract()||p_extra where id='c0be0000-0000-4000-8000-000000000050'
$$;
create function pg_temp.projection(issues jsonb) returns jsonb language sql immutable as $$
 select coalesce(jsonb_agg(jsonb_build_object('code',i->>'code','field',i->>'field','row_id',i->>'row_id',
   'blocking',coalesce((i->>'blocking')::boolean,true)) order by position),'[]')
 from jsonb_array_elements(issues) with ordinality x(i,position)
 where i->>'code' in ('row_shape','row_reference_pending','row_reference_unresolved','range_order')
$$;
create function pg_temp.issues(p_values jsonb) returns jsonb language sql stable as $$
 select pg_temp.projection(public.spec_validate_draft_internal_v1('c0be0000-0000-4000-8000-000000000050',p_values))
$$;
create function pg_temp.rows(p_rows jsonb) returns jsonb language sql immutable as $$
 select jsonb_build_object('schema_version',1,'rows',(select jsonb_agg(jsonb_build_object('id',r->>'id','values',r->'values','sources','[]'::jsonb)) from jsonb_array_elements(p_rows) r))
$$;
create function pg_temp.ports() returns jsonb language sql immutable as $$
 select pg_temp.rows('[{"id":"p1","values":{"name":"USB-C","fast":true}},{"id":"p2","values":{"name":"USB-C","fast":false}},{"id":"p3","values":{"fast":true}}]')
$$;

-- 1. Endpoints and units in metadata.
select throws_ok($$select pg_temp.contract('{"row_coherence":{"version":1,"links":[{"id":"allocation_port","field":"allocations","column":"port_kind","target_field":"ports","label_columns":["name"]}]}}')$$,
 '23514',null,'a token column with a closed vocabulary cannot carry a row id');
select throws_ok($$select pg_temp.contract('{"row_coherence":{"version":1,"links":[
 {"id":"allocation_port","field":"allocations","column":"port_row_id","target_field":"ports","label_columns":["name"]},
 {"id":"group_alloc","field":"groups","column":"alloc_row_id","target_field":"allocations","label_columns":["port_row_id"]}]}}')$$,
 '23514',null,'a chained target cannot label itself with another link column');
select lives_ok($$select pg_temp.contract('{"row_coherence":{"version":1,"links":[
 {"id":"allocation_port","field":"allocations","column":"port_row_id","target_field":"ports","label_columns":["name"]},
 {"id":"group_alloc","field":"groups","column":"alloc_row_id","target_field":"allocations","label_columns":["power_w"]}]}}')$$,
 'a chain that labels with the target own data is accepted');
select pg_temp.contract('{}');
select throws_ok($$select pg_temp.contract('{"scalar_ordered_pairs":[["lower","upper_in"]]}')$$,'23514',null,'a declared pair with different units is rejected');
select throws_ok($$delete from public.spec_template_fields where template_id='c0be0000-0000-4000-8000-000000000050' and spec_definition_id='c0be0000-0000-4000-8000-000000000011'$$,
 '23514',null,'removing a link target from the template is rejected');
select throws_ok($$select pg_temp.contract('{"scalar_ordered_pairs":[["lower","upper"],["upper","lower"]]}')$$,'23514',null,'a reversed duplicate pair is rejected as an order cycle');
select throws_ok($$select pg_temp.contract('{"scalar_ordered_pairs":[["lower","upper"],["upper","tube_width_min_mm"],["tube_width_min_mm","lower"]]}')$$,'23514',null,'an order cycle longer than two pairs is rejected');
select throws_ok($$select pg_temp.contract('{"scalar_ordered_pairs":[["largest_cog_teeth","smallest_cog_teeth"]]}')$$,'23514',null,'a declared pair cannot contradict an inherited one');
select lives_ok($$select pg_temp.contract('{"scalar_ordered_pairs":[["lower","upper"],["upper","tube_width_min_mm"]]}')$$,'a transitive chain of bounds is accepted');
select is(pg_temp.issues('{"lower":"1","upper":"2","tube_width_min_mm":"3"}'),'[]'::jsonb,'a transitive chain in order raises nothing');
select pg_temp.contract('{}');

-- 2. Inherited pairs: one evaluator, unit-aware, both bounds.
select is(pg_temp.issues('{"tube_width_min_mm":"30","tube_width_max_mm":"20"}'),'[]'::jsonb,'inherited pair with mismatched units is skipped');
select is(pg_temp.issues('{"smallest_cog_teeth":"12","largest_cog_teeth":"11"}'),
 '[{"code":"range_order","field":"smallest_cog_teeth","row_id":null,"blocking":true},{"code":"range_order","field":"largest_cog_teeth","row_id":null,"blocking":true}]'::jsonb,
 'inherited pair without declared pairs flags both bounds');
select pg_temp.contract('{"scalar_ordered_pairs":[["lower","upper"],["smallest_cog_teeth","largest_cog_teeth"]]}');
select is(jsonb_array_length(pg_temp.issues('{"smallest_cog_teeth":"12","largest_cog_teeth":"11"}')),2,'declaring an inherited pair does not evaluate it twice');
select pg_temp.contract('{}');

-- 3. Exact bounds across wire types.
select is(pg_temp.issues('{"lower":"2","upper":2.0}'),'[]'::jsonb,'text and number bounds compare by value');
select is(pg_temp.issues('{"lower":"2.50","upper":2.5}'),'[]'::jsonb,'trailing zeros do not invert a bound');
select is(pg_temp.issues('{"lower":2.5,"upper":"2.25"}')->0->>'field','lower','number over text inverted bound is flagged on the lower field');
select is(jsonb_array_length(pg_temp.issues('{"lower":2.5,"upper":"2.25"}')),2,'and on the upper field');
select is(pg_temp.issues('{"lower":"abc","upper":"1"}'),'[]'::jsonb,'a non-numeric bound is owned by the field validator, not by the pair');

-- 4. Row identity and derived labels on drafts.
select is(pg_temp.issues(jsonb_build_object('ports',pg_temp.ports(),'allocations',pg_temp.rows('[{"id":"c1","values":{"port_row_id":" p1"}}]'))),
 '[{"code":"row_reference_unresolved","field":"allocations","row_id":"c1","blocking":true}]'::jsonb,'an id is never trimmed');
select is(pg_temp.issues(jsonb_build_object('ports',pg_temp.rows('[{"id":"p9","values":{"name":"USB-C"}},{"id":"p8","values":{"name":"USB-C"}}]'),
 'allocations',pg_temp.rows('[{"id":"c1","values":{"port_row_id":"p1"}},{"id":"c2","values":{"port_row_id":"p2"}}]'))),
 '[{"code":"row_reference_unresolved","field":"allocations","row_id":"c1","blocking":true},{"code":"row_reference_unresolved","field":"allocations","row_id":"c2","blocking":true}]'::jsonb,
 're-minting every target id orphans every source row (F1b, draft level)');
select is(public.spec_coherence_labels_internal_v1('allocations',pg_temp.base_contract(),jsonb_build_object('ports',pg_temp.ports()))->'port_row_id',
 '{"p1":"USB-C · Sí","p2":"USB-C · No","p3":"Sí"}'::jsonb,'labels join name and boolean cells, and a blank name falls back to the boolean');
select is(public.spec_coherence_labels_internal_v1('allocations',pg_temp.base_contract(),
 jsonb_build_object('ports',pg_temp.rows('[{"id":"a","values":{"name":"X","fast":true}},{"id":"b","values":{"name":"X","fast":true}}]')))->'port_row_id',
 '{"a":"X · Sí · configuración 1","b":"X · Sí · configuración 2"}'::jsonb,'duplicate labels get a position suffix');
select is(public.spec_coherence_labels_internal_v1('allocations',pg_temp.base_contract(),'{"ports":"Desconocido / sin confirmar"}')->'port_row_id','{}'::jsonb,
 'an unknown target offers no labels');
select is(public.spec_coherence_display_rows_internal_v1(pg_temp.rows('[{"id":"c1","values":{"port_row_id":"ghost","power_w":"20"}}]'),
 public.spec_coherence_labels_internal_v1('allocations',pg_temp.base_contract(),jsonb_build_object('ports',pg_temp.ports())))#>>'{rows,0,values,port_row_id}',
 'Vínculo sin resolver','display never prints an orphan id');

-- 5. Populated data: atomic rejection of a re-minted target, protected metadata,
-- typed and public readers, rejected readings.
insert into public.products(id,tenant_id,name,sku,description,price,cost,is_active,spec_template_id) values
 ('c0be0000-0000-4000-8000-000000000020','c0be0000-0000-4000-8000-000000000001','Coherence boundary 10 then 30','COHERENCE-BOUNDARY','límite 10 mm y 30 mm',100,50,true,'c0be0000-0000-4000-8000-000000000050');
create function pg_temp.save(p_values jsonb,p_operation text) returns jsonb language sql as $$
 select public.save_product_with_specs_v1(
 '{"id":"c0be0000-0000-4000-8000-000000000020","name":"Coherence boundary 10 then 30","sku":"COHERENCE-BOUNDARY"}',false,
 'c0be0000-0000-4000-8000-000000000050',
 (select contract_version from public.spec_templates where id='c0be0000-0000-4000-8000-000000000050'),p_values,
 (select spec_revision from public.products where id='c0be0000-0000-4000-8000-000000000020'),null,p_operation,
 (select updated_at from public.products where id='c0be0000-0000-4000-8000-000000000020'))
$$;
grant execute on function pg_temp.save(jsonb,text) to authenticated;
create function pg_temp.linked_payload(p_extra jsonb) returns jsonb language sql immutable as $$
 select jsonb_build_object(
   'c0be0000-0000-4000-8000-000000000011',jsonb_build_object('rows',pg_temp.ports()),
   'c0be0000-0000-4000-8000-000000000012',jsonb_build_object('rows',pg_temp.rows('[{"id":"c1","values":{"port_row_id":"p1","power_w":"20"}}]')))||p_extra
$$;
set local role authenticated;
select lives_ok($$select pg_temp.save(pg_temp.linked_payload('{}'),'coherence-boundary-1')$$,'authenticated aggregate saves a resolved link');
reset role;
select is((select value_json#>>'{rows,0,values,port_row_id}' from public.spec_facts where subject_id='c0be0000-0000-4000-8000-000000000020' and spec_definition_id='c0be0000-0000-4000-8000-000000000012'),
 'p1','the stored link cell is the target row id');
select throws_ok($$update public.spec_facts set value_json=jsonb_set(jsonb_set(value_json,'{rows,0,id}','"p9"'),'{rows,1,id}','"p8"')
 where subject_id='c0be0000-0000-4000-8000-000000000020' and spec_definition_id='c0be0000-0000-4000-8000-000000000011'$$,
 '23514',null,'re-minting target ids without relinking is rejected atomically (F1b)');
select is((select value_json#>>'{rows,0,id}' from public.spec_facts where subject_id='c0be0000-0000-4000-8000-000000000020' and spec_definition_id='c0be0000-0000-4000-8000-000000000011'),
 'p1','the rejected rewrite left the previous target rows intact');
select throws_ok($$select pg_temp.contract('{"row_coherence":{"version":1,"links":[
 {"id":"allocation_port","field":"allocations","column":"port_row_id","target_field":"ports","label_columns":["name","fast"]},
 {"id":"group_alloc","field":"groups","column":"alloc_row_id","target_field":"allocations","label_columns":["power_w"]}]}}')$$,
 '23514',null,'a new link over populated endpoints needs a reviewed migration');
-- Presentation-only metadata (link id, label_columns) still passes the shape
-- guard but never needs a fact migration; endpoints and the link cell do.
select lives_ok($$select pg_temp.contract('{"row_coherence":{"version":1,"links":[{"id":"allocation_port","field":"allocations","column":"port_row_id","target_field":"ports","label_columns":["name"]}]}}')$$,
 'a label-only change over populated data needs no migration');
select lives_ok($$select pg_temp.contract('{"row_coherence":{"version":1,"links":[{"id":"allocation_port_renamed","field":"allocations","column":"port_row_id","target_field":"ports","label_columns":["name","fast"]}]}}')$$,
 'a rule-id-only change over populated data needs no migration');
select throws_ok($$select pg_temp.contract('{"row_coherence":{"version":1,"links":[{"id":"allocation_port","field":"allocations","column":"port_row_id","target_field":"ports","label_columns":["missing"]}]}}')$$,
 '23514',null,'a label-only change still passes the metadata guard');
select pg_temp.contract('{}');
select throws_ok($$set constraints all deferred;
 insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract)
 values('c0be0000-0000-4000-8000-000000000051','c0be0000-0000-4000-8000-000000000001','coherence_boundary_b','Coherence boundary B','fixture_coherence_boundary_b',pg_temp.base_contract());
 insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
 select 'c0be0000-0000-4000-8000-000000000051',id,'measurement',1 from public.spec_definitions where tenant_id='c0be0000-0000-4000-8000-000000000001';
 set constraints all immediate$$,
 '23514',null,'inserting a template with links over populated definitions is rejected like an update');
set constraints all deferred;
delete from public.spec_template_fields where template_id='c0be0000-0000-4000-8000-000000000051';
delete from public.spec_templates where id='c0be0000-0000-4000-8000-000000000051';
set constraints all immediate;

-- Readings: a name reading that would invert the pair is rejected without
-- touching the previous reading fact.
set local role authenticated;
select lives_ok($$select pg_temp.save(pg_temp.linked_payload('{"c0be0000-0000-4000-8000-000000000015":{"number":"20"}}'),'coherence-boundary-2')$$,'authenticated aggregate stores the upper bound');
select is(public.record_product_spec_reading_v1('c0be0000-0000-4000-8000-000000000020','lower','10'::jsonb,'10','boundary')->>'verdict','recorded','a consistent lower bound reading is recorded');
select is(public.record_product_spec_reading_v1('c0be0000-0000-4000-8000-000000000020','lower','30'::jsonb,'30','boundary')->>'verdict','rejected','an inverting lower bound reading is rejected, not raised');
select ok((public.record_product_spec_reading_v1('c0be0000-0000-4000-8000-000000000020','lower','30'::jsonb,'30','boundary')->>'reason') like '%conflictos%','the rejection names the conflict');
reset role;
select is((select value_number::text from public.spec_facts where subject_id='c0be0000-0000-4000-8000-000000000020' and spec_definition_id='c0be0000-0000-4000-8000-000000000014'),'10','the previous reading fact keeps its value');
select is((select r.quote from public.spec_fact_readings r join public.spec_facts f on f.id=r.fact_id where f.subject_id='c0be0000-0000-4000-8000-000000000020' and f.spec_definition_id='c0be0000-0000-4000-8000-000000000014'),'10','the previous reading keeps its quote');
select throws_ok($$select pg_temp.contract('{"scalar_ordered_pairs":[]}')$$,'23514',null,'dropping a pair over populated bounds needs a reviewed migration');

-- Typed consumers keep the id and receive derived labels.
set local role authenticated;
select is(public.get_product_spec_typed_configurations_v1(array['c0be0000-0000-4000-8000-000000000020'::uuid])#>>'{c0be0000-0000-4000-8000-000000000020,fields,allocations,value,rows,0,values,port_row_id}',
 'p1','typed configurations keep the target row id as data');
select is(public.get_product_spec_typed_configurations_v1(array['c0be0000-0000-4000-8000-000000000020'::uuid])#>>'{c0be0000-0000-4000-8000-000000000020,fields,allocations,row_labels,port_row_id,p1}',
 'USB-C · Sí','typed configurations derive the label next to the id');
reset role;

-- Public display resolves the label and hides both bounds of an inverted pair.
update public.products set is_published=true,show_on_website=true where id='c0be0000-0000-4000-8000-000000000020';
select ok((select display_value from public.get_public_product_technical_specs('c0be0000-0000-4000-8000-000000000001','c0be0000-0000-4000-8000-000000000020') where spec_key='allocations')
 like '%USB-C · Sí%','public display shows the derived label');
select ok((select display_value from public.get_public_product_technical_specs('c0be0000-0000-4000-8000-000000000001','c0be0000-0000-4000-8000-000000000020') where spec_key='allocations')
 not like '%p1%','public display never prints the row id');
savepoint latent_inversion;
set constraints all deferred;
update public.spec_facts set value_number=30 where subject_id='c0be0000-0000-4000-8000-000000000020' and spec_definition_id='c0be0000-0000-4000-8000-000000000014';
select is((select count(*) from public.get_public_product_technical_specs('c0be0000-0000-4000-8000-000000000001','c0be0000-0000-4000-8000-000000000020') where spec_key in ('lower','upper')),
 0::bigint,'a latent inverted pair hides both bounds from the storefront');
rollback to savepoint latent_inversion;
set constraints all immediate;

-- 6. ACL: helpers stay private; the typed reader stays authenticated-only.
select ok(not has_function_privilege(r,'public.'||f,'execute'),f||' is private for '||r)
 from unnest(array['anon','authenticated']) r cross join unnest(array[
  'spec_coherence_metadata_internal_v1(jsonb,jsonb)','spec_coherence_pairs_internal_v1(jsonb,jsonb)',
  'spec_coherence_labels_internal_v1(text,jsonb,jsonb)','spec_coherence_display_rows_internal_v1(jsonb,jsonb)',
  'spec_coherence_publication_guard_internal_v1()']) f;
select ok(has_function_privilege('authenticated','public.get_product_spec_typed_configurations_v1(uuid[])','execute'),'typed reader stays available to authenticated');
select ok(not has_function_privilege('anon','public.get_product_spec_typed_configurations_v1(uuid[])','execute'),'typed reader is not anonymous');
select * from finish();
rollback;
