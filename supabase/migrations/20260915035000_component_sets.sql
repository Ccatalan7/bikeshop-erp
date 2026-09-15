-- Reviewed new metadata only: 1 templates, 0 definitions, 2 fields.
-- Source catalogue SHA-256: 2e64c7ebebb44d28bb4751b24b99a6c4e05df870b9253a53e7f29ecedd431f69
-- No product, category default, fact, reference or compatibility approval write.
-- Recovery: deactivate only these new templates with the normal binding guard;
-- retain their definitions and observations. Never erase later product edits.
begin isolation level repeatable read;
set local lock_timeout='5s';
set local statement_timeout='120s';
lock table public.spec_definitions,public.spec_definition_values,
 public.spec_templates,public.spec_template_fields in share row exclusive mode;
create temporary table nd_publication_document(doc jsonb) on commit drop;
insert into nd_publication_document values ($nd_catalog${"schema_version":1,"scope":"new_global_metadata_only","audited_tenant_id":"5443b130-cc28-45af-a420-cd500b288890","catalog_sha256":"2e64c7ebebb44d28bb4751b24b99a6c4e05df870b9253a53e7f29ecedd431f69","preimage_sha256":"bd2be92df06430d92486f3698d8ea85fe0ca268acb1a18de6eb3647a35666862","families":["component_set"],"reused_definitions":[{"id":"d0cfc800-78a6-5bba-945b-ccbff6fa88e1","key":"kit_members","unit":null,"label":"Componentes incluidos","options":[],"data_type":"json","tenant_id":null,"created_at":"2026-09-07T22:33:40.381707+00:00","group_name":null,"sort_order":0,"updated_at":"2026-09-07T22:33:40.381707+00:00","description":null,"is_filterable":false,"allowed_values":[],"validation_rules":{"rows_schema":{"columns":[{"key":"member_role","type":"token","label":"Componente","required":true,"allowed_values":["maneta","cáliper","manguera","rotor","adaptador","cassette","cadena","biela","pedalier","copas","rodamientos","eje","plato","mando","cambio trasero","desviador","pastilla","parche","pegamento","válvula","cinta","sellante","rueda delantera","rueda trasera","llanta","maza","rayos","cubierta","tapa","araña","oliva","inserto","otro","cable","soporte","correa","espaciador"]},{"key":"family","type":"token","label":"Familia técnica","required":true,"allowed_values":["accessory_mount","audible_signal","bearing","bicycle","bike_bag","bike_protection","bmx_cable_detangler","bottle","bottle_cage","bottom_bracket","bottom_bracket_axle","bottom_bracket_bearing","bottom_bracket_cup","brake_caliper","brake_fluid","brake_lever","brake_mount_adapter","brake_pad","brake_shift_combined_control","brake_small_part","cassette","cassette_lockring","cassette_spacer","chain","chain_guide","chain_link","chainring","chainring_guard","consumer_electronics","control_cable","control_housing","control_small_part","crank_arm","crankset","cycle_computer","derailleur_hanger","derailleur_hanger_extender","derailleur_pulley","drivetrain_kit","eyewear","fastener","fender","fixed_cog","food_beverage","fork","frame","freewheel","front_derailleur","grip","handlebar","handlebar_covering","headset","headset_small_part","helmet","hub","hub_axle","hub_brake","hub_small_part","hydraulic_disc_brake","hydraulic_fitting","hydraulic_hose","kickstand","light","lock","mechanical_disc_brake","pedal","pedal_peg","pump","rack_basket","rear_derailleur","rear_shock","reflector","rider_apparel","rider_bag","rider_glove","rider_protection","rim","rim_brake","rim_strip","rotor","rotor_mount_adapter","saddle","saddle_cover","seat_clamp","seatpost","shifter","souvenir","spacer","spoke","spoke_nipple","stem","tire","tire_liner","training_wheel","tube","tube_repair","tubeless_consumable","tubeless_repair","tubeless_tape","tubeless_valve","valve_small_part","wheel","wheel_retention","workshop_chemical","workshop_tool"]},{"key":"quantity","type":"integer","label":"Cantidad","required":true,"validation":{"positive":true}},{"key":"position","type":"token","label":"Posición","required":true,"allowed_values":["Delantero","Trasero","Izquierdo","Derecho","Sin posición"]},{"key":"identity_brand","type":"text","label":"Marca","required":false},{"key":"identity_model","type":"text","label":"Modelo","required":false}],"version":1}},"is_customer_visible":false,"is_mechanic_visible":true,"is_required_by_default":false,"is_compatibility_relevant":false},{"id":"4f055961-6c16-430b-a4e2-e6b09dc1cccc","key":"spec_evidence_source","unit":null,"label":"Fuente de la declaración","options":[],"data_type":"text","tenant_id":null,"created_at":"2026-09-06T06:58:57.745728+00:00","group_name":null,"sort_order":900,"updated_at":"2026-09-06T06:58:57.745728+00:00","description":"URL del fabricante, manual o identificación del envase que respalda la declaración.","is_filterable":false,"allowed_values":[],"validation_rules":{},"is_customer_visible":false,"is_mechanic_visible":true,"is_required_by_default":false,"is_compatibility_relevant":false}],"records":{"spec_definitions":[],"spec_definition_values":[],"spec_templates":[{"id":"8209a066-4ec9-5707-b177-0d6d5cf8acdd","key":"component_set","name":"Conjunto de piezas","technical_family":"component_set","form_contract":{"rules_version":2,"roles":{"kit_members":"contents","spec_evidence_source":"declaration"},"semantic_roles":{"kit_members":"contents","spec_evidence_source":"evidence"},"labels":{},"allowed_options":{},"allowed_when":{"kit_members":{"kind":"always"},"spec_evidence_source":{"kind":"always"}},"required_when":{"kit_members":{"kind":"always"},"spec_evidence_source":{"kind":"always"}},"prerequisites":{"kit_members":["spec_evidence_source"]},"helpers":{"kit_members":"Identifica las piezas que realmente incluye esta presentación. Separa piezas con medidas, posición o modelo diferentes; agrupa cantidades sólo cuando sean piezas idénticas. Cada fila tiene su propia ficha. Compartir envase no acredita compatibilidad."},"evidence_requirements":{"kit_members":"package_or_label","spec_evidence_source":"oem_or_package"},"row_conditions":{"version":1,"fields":{"kit_members":{"allowed_options":{"family":["bearing","brake_caliper","brake_lever","brake_pad","fastener","hub_small_part","seat_clamp","wheel_retention"]}}}},"member_profiles":{"version":1,"collections":[{"field":"kit_members","family_column":"family","identity_columns":["member_role","position","identity_brand","identity_model"]}]}},"tenant_id":null,"is_active":true,"description":null,"default_tags":[],"contract_version":3}],"spec_template_fields":[{"section_key":"declaration","sort_order":0,"is_required":false,"visibility_rules":[],"option_rules":[],"constraint_rules":[],"default_value_json":null,"helper_text":null,"id":"f960008c-d1df-5a73-811b-427817eadbe4","tenant_id":null,"template_id":"8209a066-4ec9-5707-b177-0d6d5cf8acdd","spec_definition_id":"4f055961-6c16-430b-a4e2-e6b09dc1cccc"},{"section_key":"contents","sort_order":10,"is_required":false,"visibility_rules":[],"option_rules":[],"constraint_rules":[],"default_value_json":null,"helper_text":null,"id":"06bc8dd1-0b5f-5bca-9565-65c3a2c99885","tenant_id":null,"template_id":"8209a066-4ec9-5707-b177-0d6d5cf8acdd","spec_definition_id":"d0cfc800-78a6-5bba-945b-ccbff6fa88e1"}]},"product_writes":false,"fill_allowed":false,"mechanical_approval":false,"adjudication":{"scope":"Commercial collection of explicitly identified physical pieces; first eight supported piece families. Rim-brake presentation remains excluded pending ownership review.","no_recursive_member_family":true,"no_intrinsic_root_facts":true}}$nd_catalog$::jsonb);
create temporary table nd_publication_before on commit drop as select
 (select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f) facts,
 (select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p) products,
 (select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')::text) from public.product_spec_references r) references,
 (select md5(coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]')::text) from public.category_tech_mappings m) category_defaults;
do $publish$
declare doc jsonb; wanted jsonb; actual jsonb;
begin
 select d.doc into doc from nd_publication_document d;
 if md5(pg_get_functiondef(to_regprocedure(
   'public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)')))
   is distinct from 'ac0738d5c2039412b603dc71adc41721' then
   raise exception 'Unreviewed specification validator';
 end if;
 -- Reject homonymous visible metadata instead of silently shadowing it.
 if exists(select 1 from jsonb_array_elements(doc->'records'->'spec_templates') w
    join public.spec_templates t on t.key=w->>'key' and (t.tenant_id is null or t.tenant_id=(doc->>'audited_tenant_id')::uuid)
    where t.id<>(w->>'id')::uuid)
 or exists(select 1 from jsonb_array_elements(doc->'records'->'spec_definitions') w
    join public.spec_definitions d on d.key=w->>'key' and (d.tenant_id is null or d.tenant_id=(doc->>'audited_tenant_id')::uuid)
    where d.id<>(w->>'id')::uuid) then
   raise exception 'Publication key collision';
 end if;
 
 for wanted in select value from jsonb_array_elements(doc->'records'->'spec_definitions') loop
   select to_jsonb(t) into actual from public.spec_definitions t where id=(wanted->>'id')::uuid;
   if found then
     if (select jsonb_object_agg(k,actual->k) from jsonb_object_keys(wanted) k)
       is distinct from wanted then raise exception 'Publication drift in spec_definitions: %',wanted->>'id'; end if;
   else
     insert into public.spec_definitions(id,tenant_id,key,label,data_type,unit,allowed_values,validation_rules,is_customer_visible,is_compatibility_relevant,description,is_filterable,is_required_by_default,is_mechanic_visible,group_name,sort_order)
     select id,tenant_id,key,label,data_type,unit,allowed_values,validation_rules,is_customer_visible,is_compatibility_relevant,description,is_filterable,is_required_by_default,is_mechanic_visible,group_name,sort_order from jsonb_populate_record(null::public.spec_definitions,wanted);
   end if;
 end loop;
 for wanted in select value from jsonb_array_elements(doc->'records'->'spec_definition_values') loop
   select to_jsonb(t) into actual from public.spec_definition_values t where id=(wanted->>'id')::uuid;
   if found then
     if (select jsonb_object_agg(k,actual->k) from jsonb_object_keys(wanted) k)
       is distinct from wanted then raise exception 'Publication drift in spec_definition_values: %',wanted->>'id'; end if;
   else
     insert into public.spec_definition_values(id,tenant_id,spec_definition_id,code,label,sort_order,is_active)
     select id,tenant_id,spec_definition_id,code,label,sort_order,is_active from jsonb_populate_record(null::public.spec_definition_values,wanted);
   end if;
 end loop;
 for wanted in select value from jsonb_array_elements(doc->'records'->'spec_templates') loop
   select to_jsonb(t) into actual from public.spec_templates t where id=(wanted->>'id')::uuid;
   if found then
     if (select jsonb_object_agg(k,actual->k) from jsonb_object_keys(wanted) k)
       is distinct from wanted then raise exception 'Publication drift in spec_templates: %',wanted->>'id'; end if;
   else
     insert into public.spec_templates(id,tenant_id,key,name,technical_family,form_contract,is_active,description,default_tags)
     select id,tenant_id,key,name,technical_family,form_contract,is_active,description,default_tags from jsonb_populate_record(null::public.spec_templates,wanted);
   end if;
 end loop;
 for wanted in select value from jsonb_array_elements(doc->'records'->'spec_template_fields') loop
   select to_jsonb(t) into actual from public.spec_template_fields t where id=(wanted->>'id')::uuid;
   if found then
     if (select jsonb_object_agg(k,actual->k) from jsonb_object_keys(wanted) k)
       is distinct from wanted then raise exception 'Publication drift in spec_template_fields: %',wanted->>'id'; end if;
   else
     insert into public.spec_template_fields(id,tenant_id,template_id,spec_definition_id,section_key,sort_order,is_required,visibility_rules,option_rules,constraint_rules,default_value_json,helper_text)
     select id,tenant_id,template_id,spec_definition_id,section_key,sort_order,is_required,visibility_rules,option_rules,constraint_rules,default_value_json,helper_text from jsonb_populate_record(null::public.spec_template_fields,wanted);
   end if;
 end loop;
end $publish$;
set constraints all immediate;
select 1/(case when (not exists (
 select 1 from jsonb_array_elements(doc->'records'->'spec_definitions') wanted
 left join public.spec_definitions actual on actual.id=(wanted->>'id')::uuid
 where actual.id is null or (select jsonb_object_agg(k,to_jsonb(actual)->k)
 from jsonb_object_keys(wanted) k) is distinct from wanted)) and
(not exists (
 select 1 from jsonb_array_elements(doc->'records'->'spec_definition_values') wanted
 left join public.spec_definition_values actual on actual.id=(wanted->>'id')::uuid
 where actual.id is null or (select jsonb_object_agg(k,to_jsonb(actual)->k)
 from jsonb_object_keys(wanted) k) is distinct from wanted)) and
(not exists (
 select 1 from jsonb_array_elements(doc->'records'->'spec_templates') wanted
 left join public.spec_templates actual on actual.id=(wanted->>'id')::uuid
 where actual.id is null or (select jsonb_object_agg(k,to_jsonb(actual)->k)
 from jsonb_object_keys(wanted) k) is distinct from wanted)) and
(not exists (
 select 1 from jsonb_array_elements(doc->'records'->'spec_template_fields') wanted
 left join public.spec_template_fields actual on actual.id=(wanted->>'id')::uuid
 where actual.id is null or (select jsonb_object_agg(k,to_jsonb(actual)->k)
 from jsonb_object_keys(wanted) k) is distinct from wanted)) and
(not exists (select 1 from public.spec_template_fields f
 where f.template_id in (select (t->>'id')::uuid from jsonb_array_elements(doc->'records'->'spec_templates') t)
 and f.id not in (select (f->>'id')::uuid from jsonb_array_elements(doc->'records'->'spec_template_fields') f))) and
(not exists (select 1 from public.spec_definition_values v
 where v.spec_definition_id in (select (d->>'id')::uuid from jsonb_array_elements(doc->'records'->'spec_definitions') d)
 and v.id not in (select (v->>'id')::uuid from jsonb_array_elements(doc->'records'->'spec_definition_values') v))) and
(not exists (select 1 from jsonb_array_elements(doc->'reused_definitions') wanted
 left join public.spec_definitions d on d.id=(wanted->>'id')::uuid
 where d.id is null or to_jsonb(d) is distinct from wanted-'options'
 or (select coalesce(jsonb_agg(to_jsonb(v) order by v.id),'[]')
     from public.spec_definition_values v where v.spec_definition_id=d.id) is distinct from wanted->'options')) then 1 else 0 end) as exact_metadata
from nd_publication_document;
select 1/(case when b.facts=(select md5(coalesce(jsonb_agg(to_jsonb(f) order by f.id),'[]')::text) from public.spec_facts f)
 and b.products=(select md5(coalesce(jsonb_agg(jsonb_build_array(p.id,p.spec_revision,p.spec_template_id,p.spec_reference_id) order by p.id),'[]')::text) from public.products p)
 and b.references=(select md5(coalesce(jsonb_agg(to_jsonb(r) order by r.id),'[]')::text) from public.product_spec_references r)
 and b.category_defaults=(select md5(coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]')::text) from public.category_tech_mappings m)
 then 1 else 0 end) as product_observations_and_identity_unchanged from nd_publication_before b;
commit;
