-- Member profile framework only. No family activation, assignment or product filling.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';
lock table public.category_tech_mappings,public.product_spec_references,public.product_spec_save_receipts,public.products,public.spec_definitions,public.spec_facts,public.spec_fact_values,public.spec_fact_readings,public.spec_template_fields,public.spec_templates in share row exclusive mode;
create temp table member_publication_state on commit drop as select to_regclass('public.product_spec_member_profiles') is not null as installed;
do $functions$
declare wanted jsonb; actual jsonb;
begin
 if not (not (select installed from member_publication_state)) then return; end if;
 for wanted in select value from jsonb_array_elements('[{"identity":"get_product_spec_editor_context_v2(uuid,uuid)","md5":"ffc95bc18f46105a9b7dc3a702e485a6","owner":"postgres","acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","security_definer":true,"volatility":"s","config":["search_path=pg_catalog, public, pg_temp"]},{"identity":"save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb)","md5":"007ed3a67a009527c24ed54ee3380b99","owner":"postgres","acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","security_definer":true,"volatility":"v","config":["search_path=pg_catalog, public, pg_temp"]},{"identity":"spec_product_payload_internal_v1(uuid)","md5":"a353807af49f812d0b349fbc6f112c4c","owner":"postgres","acl":"{postgres=X/postgres,service_role=X/postgres}","security_definer":false,"volatility":"s","config":["search_path=pg_catalog, public, pg_temp"]},{"identity":"spec_template_product_payload_internal_v1(uuid,uuid,boolean)","md5":"a56ef26e739ff4b3687d9f07f9065cb0","owner":"postgres","acl":"{postgres=X/postgres,service_role=X/postgres}","security_definer":false,"volatility":"s","config":["search_path=pg_catalog, public, pg_temp"]},{"identity":"spec_validate_product_internal_v1(uuid)","md5":"6f8f676f03241a5f68a10b3d9b152272","owner":"postgres","acl":"{postgres=X/postgres,service_role=X/postgres}","security_definer":true,"volatility":"v","config":["search_path=pg_catalog, public, pg_temp"]},{"identity":"spec_write_payload_internal_v2(uuid,uuid,jsonb,text)","md5":"4000850abcb96fe223f1df53584eadfb","owner":"postgres","acl":"{postgres=X/postgres,service_role=X/postgres}","security_definer":true,"volatility":"v","config":["search_path=pg_catalog, public, pg_temp"]}]'::jsonb) loop
   select jsonb_build_object('identity',p.oid::regprocedure::text,'md5',md5(pg_get_functiondef(p.oid)),
     'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'security_definer',p.prosecdef,
     'volatility',p.provolatile::text,'config',to_jsonb(p.proconfig)) into actual
     from pg_proc p where p.oid=to_regprocedure('public.'||(wanted->>'identity'));
   if actual is distinct from wanted then raise exception 'Member predecessor changed: %',wanted->>'identity'; end if;
 end loop;
end $functions$;
do $functions$
declare wanted jsonb; actual jsonb;
begin
 if not ((select installed from member_publication_state)) then return; end if;
 for wanted in select value from jsonb_array_elements('[{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"977c2146949cfddabc03a1de248598bc","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_editor_context_v2(uuid,uuid)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"b78ece378e8f70a2282586a09ac1481a","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_editor_context_v3(uuid,uuid)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"604107480ffe3d26740975c8635994b9","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_member_profiles_v1(uuid)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"3639e9242cf7b2e2bfca740d9717eca4","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_member_template_v1(uuid,uuid,text)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"e8bd4c930b6c5ca5b4c455ff1606922f","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_research_snapshot_v2(uuid)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"cbd432b9892842961abec4f9950e3b9f","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"43f2feb8bda787b386ad1a3cbc2f9971","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"save_product_with_specs_v2(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb,jsonb)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"b408a4c0db772e61a1cf372a5ad0171c","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_apply_member_profiles_internal_v1(uuid,jsonb)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"d9e0a08ca3d95e4fb67e3eb2e8b6880d","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_binding_internal_v1(uuid,uuid,text,uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"6026de56d6112b7c10919f6cd42fbb35","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_category_constraint_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"a7de45643b6c30f9d9d3eaab844accb9","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_collection_contract_internal_v1(uuid,uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"25cce62d4f204b929a8772e6a8d82cd5","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_event_immutable_internal_v1()","volatility":"v","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"498b68a21a1c36d40153392c66e6c312","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_fact_guard_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"4698117d2826ea0e2d2694cfff518e1f","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_graph_touch_internal_v1(uuid)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"73340635457d66c471ceba0d77f1a9ec","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_identity_enrichment_internal_v1(jsonb,jsonb)","volatility":"i","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"4e0960c70cb9661d41e214578ea8f325","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_metadata_constraint_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"7b3cde401821955714c90f30a0a8a47e","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_profile_constraint_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"64c5d3e81962271d42524a6ca9430992","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_profile_guard_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"0ddc8bea7c5d7fbfbca8fbf8b60be8e1","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_profile_issues_internal_v1(uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"14e0d49c11737c959a74b4d53cccbfea","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_profile_revision_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"564c8154b4a6fb52733761d12d91e3df","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_reading_revision_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"9154286781ea568d0d30f9018b185c6a","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_product_payload_internal_v1(uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"a49ac75683db625460cec11de8e13b46","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_product_scope_payload_internal_v1(uuid,text)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"06cbf3bd2edb820007ada9a7e7444b04","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_save_product_with_specs_internal_v2(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb,jsonb,integer)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"dc82a3d8359e72cf2afb4c0d0c45156c","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_template_editor_internal_v1(uuid,uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"44e846009662462220baa2e60686aa5a","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_template_product_payload_internal_v1(uuid,uuid,boolean)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"5a7555f13bb7dd0dc7f797abde9cac52","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_template_product_scope_payload_internal_v1(uuid,uuid,boolean,text)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"d290d4df318cff8865553df64b929c78","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_validate_product_fact_shape_internal_v1(uuid,text)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"ebe417e4a4d802d7dfc60f40768125e7","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_validate_product_internal_v1(uuid)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"e20342ed1ea076059d9325382b58798d","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_validate_product_member_profiles_internal_v1(uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"0c1ef47fee4b566ce39c4255d2f0f484","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_write_payload_internal_v2(uuid,uuid,jsonb,text)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"1ec9a61aa2a4be4093be590af2f1a610","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_write_scope_payload_internal_v1(uuid,uuid,jsonb,text,text)","volatility":"v","security_definer":true}]'::jsonb) loop
   select jsonb_build_object('identity',p.oid::regprocedure::text,'md5',md5(pg_get_functiondef(p.oid)),
     'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'security_definer',p.prosecdef,
     'volatility',p.provolatile::text,'config',to_jsonb(p.proconfig)) into actual
     from pg_proc p where p.oid=to_regprocedure('public.'||(wanted->>'identity'));
   if actual is distinct from wanted then raise exception 'Previously installed member function differs: %',wanted->>'identity'; end if;
 end loop;
end $functions$;
do $new_objects$ begin
 if not (select installed from member_publication_state) and (exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname=any(array['get_product_spec_editor_context_v3','get_product_spec_member_profiles_v1','get_product_spec_member_template_v1','get_product_spec_research_snapshot_v2','save_product_with_specs_v2','spec_apply_member_profiles_internal_v1','spec_member_binding_internal_v1','spec_member_category_constraint_internal_v1','spec_member_collection_contract_internal_v1','spec_member_event_immutable_internal_v1','spec_member_fact_guard_internal_v1','spec_member_graph_touch_internal_v1','spec_member_identity_enrichment_internal_v1','spec_member_metadata_constraint_internal_v1','spec_member_profile_constraint_internal_v1','spec_member_profile_guard_internal_v1','spec_member_profile_issues_internal_v1','spec_member_profile_revision_internal_v1','spec_member_reading_revision_internal_v1','spec_product_scope_payload_internal_v1','spec_save_product_with_specs_internal_v2','spec_template_editor_internal_v1','spec_template_product_scope_payload_internal_v1','spec_validate_product_fact_shape_internal_v1','spec_validate_product_member_profiles_internal_v1','spec_write_scope_payload_internal_v1']))
   or to_regclass('public.product_spec_member_profiles') is not null or to_regclass('public.product_spec_member_profile_events') is not null or to_regclass('public.spec_member_graph_revisions') is not null) then raise exception 'Partial member objects exist; inspect before proceeding'; end if;
 if exists(select 1 from public.spec_facts where subject_type='product' and subject_scope is not null)
   or exists(select 1 from public.spec_templates where form_contract ? 'member_profiles') then
   raise exception 'Unexpected prior member data or configuration'; end if;
 if md5(pg_get_functiondef('public.spec_rows_schema_validate_internal_v1(jsonb)'::regprocedure))<>'c21cb764086b89a50c5580ad72c0c970'
   or md5(pg_get_functiondef('public.spec_rows_validate_internal_v1(jsonb,jsonb)'::regprocedure))<>'a7e629a22356148871253ad48ef25b3f' then
   raise exception 'Strict-row prerequisite differs from the reviewed production state'; end if;
end $new_objects$;
do $existing$ begin if (select installed from member_publication_state) then
perform 1/case when (select jsonb_agg(to_jsonb(t) order by name) from (select c.relname as name,pg_get_userbyid(c.relowner) as owner,
      c.relacl::text as acl,c.relrowsecurity as rls,
      (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
        'not_null',a.attnotnull,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
        from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
        where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped) as columns,
      (select jsonb_agg(jsonb_build_array(conname,pg_get_constraintdef(oid)) order by conname)
        from pg_constraint where conrelid=c.oid) as constraints,
      (select jsonb_agg(jsonb_build_array(indexrelid::regclass::text,pg_get_indexdef(indexrelid)) order by indexrelid::regclass::text)
        from pg_index where indrelid=c.oid) as indexes,
      (select jsonb_agg(jsonb_build_array(policyname,roles,cmd,qual,with_check) order by policyname)
        from pg_policies where schemaname='public' and tablename=c.relname) as policies
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=any(array['product_spec_member_profiles','product_spec_member_profile_events','spec_member_graph_revisions'])) t)='[{"acl":"{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}","rls":true,"name":"product_spec_member_profile_events","owner":"postgres","columns":[{"name":"id","type":"uuid","default":"gen_random_uuid()","not_null":true,"generated":""},{"name":"profile_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"tenant_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"product_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"actor_id","type":"uuid","default":null,"not_null":false,"generated":""},{"name":"occurred_at","type":"timestamp with time zone","default":"now()","not_null":true,"generated":""},{"name":"before_state","type":"jsonb","default":null,"not_null":false,"generated":""},{"name":"after_state","type":"jsonb","default":null,"not_null":true,"generated":""}],"indexes":[["product_spec_member_profile_events_pkey","CREATE UNIQUE INDEX product_spec_member_profile_events_pkey ON public.product_spec_member_profile_events USING btree (id)"],["product_spec_member_profile_events_profile","CREATE INDEX product_spec_member_profile_events_profile ON public.product_spec_member_profile_events USING btree (profile_id, occurred_at, id)"]],"policies":[["product_spec_member_profile_events_tenant_read",["authenticated"],"SELECT","(tenant_id = user_tenant_id())",null]],"constraints":[["product_spec_member_profile_events_pkey","PRIMARY KEY (id)"],["product_spec_member_profile_events_product_id_fkey","FOREIGN KEY (product_id) REFERENCES products(id)"],["product_spec_member_profile_events_profile_id_fkey","FOREIGN KEY (profile_id) REFERENCES product_spec_member_profiles(id)"],["product_spec_member_profile_events_tenant_id_fkey","FOREIGN KEY (tenant_id) REFERENCES tenants(id)"]]},{"acl":"{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}","rls":true,"name":"product_spec_member_profiles","owner":"postgres","columns":[{"name":"id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"tenant_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"product_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"collection_definition_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"member_row_id","type":"text","default":null,"not_null":true,"generated":""},{"name":"member_identity","type":"jsonb","default":null,"not_null":true,"generated":""},{"name":"identity_sources","type":"jsonb","default":"''[]''::jsonb","not_null":true,"generated":""},{"name":"manufacturer_sku","type":"text","default":null,"not_null":false,"generated":""},{"name":"template_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"saved_contract_version","type":"integer","default":null,"not_null":true,"generated":""},{"name":"reference_id","type":"text","default":null,"not_null":false,"generated":""},{"name":"created_at","type":"timestamp with time zone","default":"now()","not_null":true,"generated":""},{"name":"updated_at","type":"timestamp with time zone","default":"now()","not_null":true,"generated":""},{"name":"archived_at","type":"timestamp with time zone","default":null,"not_null":false,"generated":""},{"name":"scope","type":"text","default":"(''member:''::text || (id)::text)","not_null":false,"generated":"s"},{"name":"active_template_guard","type":"boolean","default":"\nCASE\n    WHEN (archived_at IS NULL) THEN true\n    ELSE NULL::boolean\nEND","not_null":false,"generated":"s"}],"indexes":[["product_spec_member_profiles_active_row","CREATE UNIQUE INDEX product_spec_member_profiles_active_row ON public.product_spec_member_profiles USING btree (tenant_id, product_id, collection_definition_id, member_row_id) WHERE (archived_at IS NULL)"],["product_spec_member_profiles_active_template","CREATE INDEX product_spec_member_profiles_active_template ON public.product_spec_member_profiles USING btree (template_id, product_id) WHERE (archived_at IS NULL)"],["product_spec_member_profiles_pkey","CREATE UNIQUE INDEX product_spec_member_profiles_pkey ON public.product_spec_member_profiles USING btree (id)"],["product_spec_member_profiles_product","CREATE INDEX product_spec_member_profiles_product ON public.product_spec_member_profiles USING btree (product_id)"],["product_spec_member_profiles_scope","CREATE UNIQUE INDEX product_spec_member_profiles_scope ON public.product_spec_member_profiles USING btree (tenant_id, product_id, scope)"]],"policies":[["product_spec_member_profiles_tenant_read",["authenticated"],"SELECT","(tenant_id = user_tenant_id())",null]],"constraints":[["product_spec_member_profiles_collection_definition_id_fkey","FOREIGN KEY (collection_definition_id) REFERENCES spec_definitions(id)"],["product_spec_member_profiles_identity_sources_check","CHECK ((jsonb_typeof(identity_sources) = ''array''::text))"],["product_spec_member_profiles_member_identity_check","CHECK ((jsonb_typeof(member_identity) = ''object''::text))"],["product_spec_member_profiles_member_row_id_check","CHECK ((member_row_id ~ ''^[A-Za-z0-9_-]{1,80}$''::text))"],["product_spec_member_profiles_pkey","PRIMARY KEY (id)"],["product_spec_member_profiles_product_id_fkey","FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT"],["product_spec_member_profiles_reference_id_fkey","FOREIGN KEY (reference_id) REFERENCES product_spec_references(id)"],["product_spec_member_profiles_saved_contract_version_check","CHECK ((saved_contract_version > 0))"],["product_spec_member_profiles_template_id_active_template_g_fkey","FOREIGN KEY (template_id, active_template_guard) REFERENCES spec_templates(id, is_active) DEFERRABLE"],["product_spec_member_profiles_template_id_fkey","FOREIGN KEY (template_id) REFERENCES spec_templates(id)"],["product_spec_member_profiles_tenant_id_fkey","FOREIGN KEY (tenant_id) REFERENCES tenants(id)"],["spec_member_profile_constraint","TRIGGER DEFERRABLE INITIALLY DEFERRED"]]},{"acl":"{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}","rls":true,"name":"spec_member_graph_revisions","owner":"postgres","columns":[{"name":"template_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"revision","type":"bigint","default":"0","not_null":true,"generated":""},{"name":"last_xid","type":"bigint","default":null,"not_null":true,"generated":""}],"indexes":[["spec_member_graph_revisions_pkey","CREATE UNIQUE INDEX spec_member_graph_revisions_pkey ON public.spec_member_graph_revisions USING btree (template_id)"]],"policies":null,"constraints":[["spec_member_graph_revisions_pkey","PRIMARY KEY (template_id)"],["spec_member_graph_revisions_template_id_fkey","FOREIGN KEY (template_id) REFERENCES spec_templates(id) ON DELETE CASCADE"]]}]'::jsonb then 1 else 0 end;
perform 1/case when (select jsonb_agg(to_jsonb(t) order by table_name,name) from (select c.relname as table_name,t.tgname as name,t.tgenabled::text as enabled,
      pg_get_triggerdef(t.oid) as definition
      from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and not t.tgisinternal and (c.relname,t.tgname) in (('category_tech_mappings','spec_member_category_constraint'),('spec_definitions','spec_member_definition_metadata_constraint'),('product_spec_member_profile_events','spec_member_event_immutable'),('spec_facts','spec_member_fact_guard'),('spec_fact_readings','spec_member_fact_readings_guard'),('spec_fact_values','spec_member_fact_values_guard'),('spec_template_fields','spec_member_field_metadata_constraint'),('product_spec_member_profiles','spec_member_profile_constraint'),('product_spec_member_profiles','spec_member_profile_guard'),('product_spec_member_profiles','spec_member_profile_revision'),('spec_fact_readings','spec_member_reading_revision'),('spec_templates','spec_member_template_metadata_constraint'))) t)='[{"name":"spec_member_category_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_category_constraint AFTER INSERT OR DELETE OR UPDATE ON public.category_tech_mappings DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_category_constraint_internal_v1()","table_name":"category_tech_mappings"},{"name":"spec_member_event_immutable","enabled":"O","definition":"CREATE TRIGGER spec_member_event_immutable BEFORE DELETE OR UPDATE ON public.product_spec_member_profile_events FOR EACH ROW EXECUTE FUNCTION spec_member_event_immutable_internal_v1()","table_name":"product_spec_member_profile_events"},{"name":"spec_member_profile_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_profile_constraint AFTER INSERT OR UPDATE ON public.product_spec_member_profiles DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_profile_constraint_internal_v1()","table_name":"product_spec_member_profiles"},{"name":"spec_member_profile_guard","enabled":"O","definition":"CREATE TRIGGER spec_member_profile_guard BEFORE INSERT OR DELETE OR UPDATE ON public.product_spec_member_profiles FOR EACH ROW EXECUTE FUNCTION spec_member_profile_guard_internal_v1()","table_name":"product_spec_member_profiles"},{"name":"spec_member_profile_revision","enabled":"O","definition":"CREATE TRIGGER spec_member_profile_revision AFTER INSERT OR UPDATE ON public.product_spec_member_profiles FOR EACH ROW EXECUTE FUNCTION spec_member_profile_revision_internal_v1()","table_name":"product_spec_member_profiles"},{"name":"spec_member_definition_metadata_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_definition_metadata_constraint AFTER UPDATE ON public.spec_definitions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_metadata_constraint_internal_v1()","table_name":"spec_definitions"},{"name":"spec_member_fact_readings_guard","enabled":"O","definition":"CREATE TRIGGER spec_member_fact_readings_guard BEFORE INSERT OR DELETE OR UPDATE ON public.spec_fact_readings FOR EACH ROW EXECUTE FUNCTION spec_member_fact_guard_internal_v1()","table_name":"spec_fact_readings"},{"name":"spec_member_reading_revision","enabled":"O","definition":"CREATE TRIGGER spec_member_reading_revision AFTER INSERT OR DELETE OR UPDATE ON public.spec_fact_readings FOR EACH ROW EXECUTE FUNCTION spec_member_reading_revision_internal_v1()","table_name":"spec_fact_readings"},{"name":"spec_member_fact_values_guard","enabled":"O","definition":"CREATE TRIGGER spec_member_fact_values_guard BEFORE INSERT OR DELETE OR UPDATE ON public.spec_fact_values FOR EACH ROW EXECUTE FUNCTION spec_member_fact_guard_internal_v1()","table_name":"spec_fact_values"},{"name":"spec_member_fact_guard","enabled":"O","definition":"CREATE TRIGGER spec_member_fact_guard BEFORE INSERT OR DELETE OR UPDATE ON public.spec_facts FOR EACH ROW EXECUTE FUNCTION spec_member_fact_guard_internal_v1()","table_name":"spec_facts"},{"name":"spec_member_field_metadata_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_field_metadata_constraint AFTER INSERT OR DELETE OR UPDATE ON public.spec_template_fields DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_metadata_constraint_internal_v1()","table_name":"spec_template_fields"},{"name":"spec_member_template_metadata_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_template_metadata_constraint AFTER INSERT OR UPDATE ON public.spec_templates DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_metadata_constraint_internal_v1()","table_name":"spec_templates"}]'::jsonb then 1 else 0 end;
end if; end $existing$;
create temp table member_data_before on commit drop as select jsonb_build_object('category_tech_mappings',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.category_tech_mappings x),'product_spec_references',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.product_spec_references x),'product_spec_save_receipts',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.product_spec_save_receipts x),'products',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.products x),'spec_definitions',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_definitions x),'spec_facts',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_facts x),'spec_fact_values',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_fact_values x),'spec_fact_readings',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_fact_readings x),'spec_template_fields',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_template_fields x),'spec_templates',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_templates x)) as value;
-- REVIEW CANDIDATE. No template activation or product filling.
CREATE OR REPLACE FUNCTION public.spec_product_scope_payload_internal_v1(p_product_id uuid, p_scope text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_object_agg(f.spec_definition_id::text,
    case d.data_type when 'number' then jsonb_build_object('number',f.value_number)
      when 'boolean' then jsonb_build_object('boolean',f.value_boolean)
      when 'single_select' then jsonb_build_object('value_ids',coalesce(v.ids,'[]'::jsonb))
      when 'multi_select' then jsonb_build_object('value_ids',coalesce(v.ids,'[]'::jsonb))
      when 'json' then case when d.validation_rules ? 'rows_schema' then jsonb_build_object('rows',f.value_json) else jsonb_build_object('text',f.value_text) end
      else jsonb_build_object('text',f.value_text) end), '{}'::jsonb)
  from public.spec_facts f join public.spec_definitions d on d.id = f.spec_definition_id
  left join lateral (select jsonb_agg(fv.value_id order by fv.position) ids
    from public.spec_fact_values fv where fv.fact_id = f.id) v on true
  where f.subject_type = 'product' and f.subject_id = p_product_id
    and f.subject_scope is not distinct from p_scope
    and f.tenant_id=(select tenant_id from public.products where id=p_product_id)
$function$;
CREATE OR REPLACE FUNCTION public.spec_template_product_scope_payload_internal_v1(p_product_id uuid, p_template_id uuid, p_include_legacy boolean, p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
begin
 if exists(select 1 from public.spec_template_fields f
   join public.spec_definitions d on d.id=f.spec_definition_id
   join public.products p on p.id=p_product_id
   join public.spec_templates t on t.id=f.template_id
   where f.template_id=p_template_id and (d.tenant_id is null or d.tenant_id=p.tenant_id)
     and (coalesce(p_include_legacy,false) or coalesce(t.form_contract->'roles'->>d.key,'primary')<>'legacy')
   group by d.key having count(distinct d.id)>1) then
   raise exception 'La plantilla contiene identidades de campo ambiguas' using errcode='23514';
 end if;
 return (select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb)
 from jsonb_each(public.spec_product_scope_payload_internal_v1(p_product_id,p_scope)) e
 join public.spec_definitions d on d.id::text=e.key
 join public.products p on p.id=p_product_id and (d.tenant_id is null or d.tenant_id=p.tenant_id)
 join public.spec_templates t on t.id=p_template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
 where exists(select 1 from public.spec_template_fields f where f.template_id=t.id and f.spec_definition_id=d.id)
   and (coalesce(p_include_legacy,false) or coalesce(t.form_contract->'roles'->>d.key,'primary')<>'legacy'));
end $function$;
CREATE OR REPLACE FUNCTION public.spec_write_scope_payload_internal_v1(p_product_id uuid, p_template_id uuid, p_values jsonb, p_reference_id text, p_scope text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_tenant uuid := public.user_tenant_id(); v_entry record; v_def public.spec_definitions%rowtype;
  v_fact uuid; v_ids uuid[]; v_count integer := 0; v_reference jsonb := '{}'; v_payload jsonb; v_old jsonb; v_contract jsonb;
begin
  if v_tenant is null or auth.uid() is null or not exists (
    select 1 from public.products where id = p_product_id and tenant_id = v_tenant) then
    raise exception 'Producto no disponible para este tenant' using errcode = '42501';
  end if;
  select fact_values into v_reference from public.product_spec_references where id = p_reference_id;
  -- Explicitly submitted facts are independent observations. The client omits
  -- automatic values; reference validation still rejects conflicting facts.
  -- Reattribution to catalog would erase the observation on reload/detach.
  v_reference := coalesce(v_reference,'{}'::jsonb) - array(select jsonb_object_keys(p_values));
  v_payload := v_reference || p_values;
  if jsonb_typeof(v_payload) <> 'object' then raise exception 'Invalid fact payload' using errcode = '22023'; end if;
  -- No arbitrary definition list from the client, and no silently dropped IDs.
  if exists (select 1 from jsonb_object_keys(v_payload) k where not exists (
    select 1 from public.spec_template_fields f where f.template_id = p_template_id and f.spec_definition_id::text = k)) then
    raise exception 'La respuesta no pertenece a esta plantilla' using errcode = '23514';
  end if;
  select form_contract into v_contract from public.spec_templates where id=p_template_id;
  v_old:=public.spec_product_scope_payload_internal_v1(p_product_id,p_scope);
  -- Old clients may round-trip identical retired answers; omission preserves
  -- them too. Changed/new retired values need a separate reviewed repair.
  for v_entry in select e.* from jsonb_each(v_payload) e
    join public.spec_definitions d on d.id::text=e.key
    where v_contract->'roles'->>d.key='legacy' loop
    if v_old->v_entry.key is distinct from v_entry.value then
      raise exception 'El campo retirado se conserva como legacy y no admite cambios: %',v_entry.key using errcode='23514';
    end if;
    v_payload:=v_payload-v_entry.key;
  end loop;
  delete from public.spec_facts f using public.spec_template_fields tf
    where tf.template_id = p_template_id and tf.spec_definition_id = f.spec_definition_id
    and f.tenant_id = v_tenant and f.subject_type = 'product' and f.subject_id = p_product_id
    and f.subject_scope is not distinct from p_scope and not (v_payload ? f.spec_definition_id::text)
    and coalesce(v_contract->'roles'->>(select key from public.spec_definitions where id=f.spec_definition_id),'primary')<>'legacy';
  for v_entry in select * from jsonb_each(v_payload) loop
    select * into strict v_def from public.spec_definitions where id::text = v_entry.key;
    v_ids := null;
    if v_def.data_type='json' and v_def.validation_rules ? 'rows_schema' then
      if jsonb_typeof(v_entry.value) is distinct from 'object' or exists(
        select 1 from jsonb_object_keys(v_entry.value) k where k<>'rows') then
        raise exception 'La configuración requiere un payload de filas' using errcode='23514';
      end if;
      v_entry.value:=jsonb_build_object('rows',public.spec_rows_validate_internal_v1(
        v_def.validation_rules->'rows_schema',v_entry.value->'rows'));
    end if;
    if v_def.data_type in ('single_select','multi_select') then
      if jsonb_typeof(v_entry.value->'value_ids') is distinct from 'array'
        or jsonb_array_length(v_entry.value->'value_ids') = 0
        or (v_def.data_type = 'single_select' and jsonb_array_length(v_entry.value->'value_ids') <> 1) then
        raise exception 'Invalid option cardinality for %', v_def.key using errcode = '23514';
      end if;
      v_ids := array(select jsonb_array_elements_text(v_entry.value->'value_ids')::uuid);
      if cardinality(v_ids) <> (select count(distinct v.id) from public.spec_definition_values v
        where v.spec_definition_id = v_def.id and v.id = any(v_ids)) then
        raise exception 'Unknown, duplicate or foreign option for %', v_def.key using errcode = '23514';
      end if;
    elsif v_def.data_type = 'number' and (jsonb_typeof(v_entry.value->'number') not in ('number','string') or public.spec_rule_number_internal_v1(v_entry.value->'number') is null) then
      raise exception 'Expected numeric fact for %', v_def.key using errcode = '23514';
    elsif v_def.data_type = 'boolean' and jsonb_typeof(v_entry.value->'boolean') is distinct from 'boolean' then
      raise exception 'Expected boolean fact for %', v_def.key using errcode = '23514';
    elsif not (v_def.data_type='json' and v_def.validation_rules ? 'rows_schema')
      and v_def.data_type not in ('number','boolean','single_select','multi_select')
      and jsonb_typeof(v_entry.value->'text') is distinct from 'string' then
      raise exception 'Expected text fact for %', v_def.key using errcode = '23514';
    end if;
    if exists(select 1 from public.spec_facts f where f.subject_type='product' and f.subject_id=p_product_id
      and f.tenant_id=v_tenant and f.subject_scope is not distinct from p_scope and f.spec_definition_id=v_def.id
      and public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(v_entry.key,v_old->v_entry.key))->v_def.key)
        = public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(v_entry.key,v_entry.value))->v_def.key)
      and (not (coalesce(v_reference,'{}'::jsonb) ? v_entry.key) or f.source='catalog')
      and (f.source<>'catalog' or coalesce(v_reference,'{}'::jsonb) ? v_entry.key)) then
      v_count := v_count+1;
      continue;
    end if;
    insert into public.spec_facts (tenant_id,subject_type,subject_id,subject_scope,spec_definition_id,
      value_number,value_boolean,value_text,value_json,source,confirmed)
    values (v_tenant,'product',p_product_id,p_scope,v_def.id,
      case when v_def.data_type = 'number' then (v_entry.value->>'number')::numeric end,
      case when v_def.data_type = 'boolean' then (v_entry.value->>'boolean')::boolean end,
      case when v_def.data_type not in ('number','boolean','single_select','multi_select') and not(v_def.validation_rules ? 'rows_schema') then v_entry.value->>'text' end,
      case when v_def.data_type='json' and v_def.validation_rules ? 'rows_schema' then v_entry.value->'rows' end,
      case when coalesce(v_reference,'{}'::jsonb) ? v_entry.key then 'catalog' else 'mechanic' end, false)
    on conflict (tenant_id,subject_type,subject_id,spec_definition_id,coalesce(subject_scope,''))
    do update set value_number = excluded.value_number, value_boolean = excluded.value_boolean,
      value_text = excluded.value_text, value_json=excluded.value_json, source = excluded.source, confirmed = excluded.confirmed, updated_at = now()
    returning id into v_fact;
    delete from public.spec_fact_readings where fact_id = v_fact;
    delete from public.spec_fact_values where fact_id = v_fact;
    if v_ids is not null then
      insert into public.spec_fact_values(fact_id,value_id,position)
        select v_fact,id,(ordinality-1)::integer from unnest(v_ids) with ordinality a(id,ordinality);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $function$;
create or replace function public.spec_template_editor_internal_v1(template_id uuid,tenant uuid)
returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
#variable_conflict use_variable
declare template jsonb; fields jsonb;
begin
   select jsonb_build_object('id',t.id,'tenant_id',t.tenant_id,'key',t.key,'name',t.name,
     'technical_family',t.technical_family,'contract_version',t.contract_version,
     'form_contract',public.spec_editor_rule_numbers_as_text_internal_v1(t.form_contract))
   into template from public.spec_templates t
   where t.id=template_id and t.is_active and (t.tenant_id is null or t.tenant_id=tenant);
   if template is null then raise exception 'Ficha no disponible' using errcode='42501'; end if;
   -- A malformed cross-tenant link fails closed instead of silently dropping a
   -- prerequisite and presenting a seemingly complete template.
   if exists(select 1 from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
     where f.template_id=template_id and ((f.tenant_id is not null and f.tenant_id<>tenant)
       or (d.tenant_id is not null and d.tenant_id<>tenant))) then
     raise exception 'Campo no disponible para este tenant' using errcode='42501';
   end if;
   select coalesce(jsonb_agg(jsonb_build_object(
     'spec_definition_id',f.spec_definition_id,'section_key',f.section_key,'sort_order',f.sort_order,
     'is_required',f.is_required,'helper_text',f.helper_text,
     'default_value_json',case when d.data_type='number' then public.spec_json_numbers_as_text_internal_v1(f.default_value_json) else f.default_value_json end,
     'visibility_rules',public.spec_editor_rule_numbers_as_text_internal_v1(f.visibility_rules),
     'option_rules',public.spec_editor_rule_numbers_as_text_internal_v1(f.option_rules),
     'constraint_rules',public.spec_editor_rule_numbers_as_text_internal_v1(f.constraint_rules),
     'spec_definitions',jsonb_build_object('id',d.id,'key',d.key,'label',d.label,'data_type',d.data_type,
       'unit',d.unit,'description',d.description,'sort_order',d.sort_order,'allowed_values',d.allowed_values,
       'validation_rules',public.spec_editor_rule_numbers_as_text_internal_v1(d.validation_rules),
       'spec_definition_values',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'label',o.label) order by o.sort_order,o.id),'[]'::jsonb)
         from public.spec_definition_values o where o.spec_definition_id=d.id and (o.tenant_id is null or o.tenant_id=tenant))))
     order by f.sort_order,f.id),'[]'::jsonb)
   into fields from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
   where f.template_id=template_id;
   template:=template||jsonb_build_object('fields',fields);
 return template;
end $$;
create or replace function public.spec_validate_product_fact_shape_internal_v1(p_product_id uuid,p_scope text)
returns void language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
begin
  if exists(select 1 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
    where f.subject_type='product' and f.subject_id=p_product_id and f.subject_scope is not distinct from p_scope and (
      (d.data_type='number' and (f.value_boolean is not null or f.value_text is not null)) or
      (d.data_type='boolean' and (f.value_number is not null or f.value_text is not null)) or
      (d.data_type not in ('number','boolean','single_select','multi_select') and (f.value_number is not null or f.value_boolean is not null)) or
      (d.data_type in ('single_select','multi_select') and num_nonnulls(f.value_number,f.value_boolean,f.value_text)>0) or
      exists(select 1 from public.spec_fact_values fv join public.spec_definition_values v on v.id=fv.value_id
        where fv.fact_id=f.id and (v.spec_definition_id<>f.spec_definition_id or d.data_type not in ('single_select','multi_select'))) or
      (d.data_type='single_select' and (select count(*) from public.spec_fact_values fv where fv.fact_id=f.id)>1)
    )) then raise exception 'Invalid specification shape or option ownership' using errcode='23514'; end if;
end $$;
-- Member profiles are scoped observations of an inventory product. This file
-- never activates a family, creates inventory children or fills product facts.
create table if not exists public.product_spec_member_profiles (
  id uuid primary key,
  tenant_id uuid not null references public.tenants(id),
  product_id uuid not null references public.products(id) on delete restrict,
  collection_definition_id uuid not null references public.spec_definitions(id),
  member_row_id text not null check (member_row_id ~ '^[A-Za-z0-9_-]{1,80}$'),
  member_identity jsonb not null check (jsonb_typeof(member_identity)='object'),
  identity_sources jsonb not null default '[]' check (jsonb_typeof(identity_sources)='array'),
  manufacturer_sku text,
  template_id uuid not null references public.spec_templates(id),
  saved_contract_version integer not null check (saved_contract_version>0),
  reference_id text references public.product_spec_references(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  scope text generated always as ('member:'||id::text) stored,
  active_template_guard boolean generated always as
    (case when archived_at is null then true else null::boolean end) stored,
  foreign key (template_id,active_template_guard)
    references public.spec_templates(id,is_active) deferrable initially immediate
);
create unique index if not exists product_spec_member_profiles_active_row
  on public.product_spec_member_profiles(tenant_id,product_id,collection_definition_id,member_row_id)
  where archived_at is null;
create unique index if not exists product_spec_member_profiles_scope
  on public.product_spec_member_profiles(tenant_id,product_id,scope);
create index if not exists product_spec_member_profiles_product on public.product_spec_member_profiles(product_id);
create index if not exists product_spec_member_profiles_active_template
  on public.product_spec_member_profiles(template_id,product_id) where archived_at is null;
alter table public.product_spec_member_profiles enable row level security;
revoke all on public.product_spec_member_profiles from public,anon,authenticated;
-- Writes only through the aggregate command. Read access is tenant-scoped.
grant select on public.product_spec_member_profiles to authenticated;
drop policy if exists product_spec_member_profiles_tenant_read on public.product_spec_member_profiles;
create policy product_spec_member_profiles_tenant_read on public.product_spec_member_profiles
  for select to authenticated using (tenant_id=public.user_tenant_id());

-- Header changes retain the previous binding/reference and the actor. Facts
-- and readings continue in the existing normalized observation graph.
create table if not exists public.product_spec_member_profile_events (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.product_spec_member_profiles(id),
  tenant_id uuid not null references public.tenants(id),
  product_id uuid not null references public.products(id),
  actor_id uuid,
  occurred_at timestamptz not null default now(),
  before_state jsonb,
  after_state jsonb not null
);
alter table public.product_spec_member_profile_events enable row level security;
revoke all on public.product_spec_member_profile_events from public,anon,authenticated;
grant select on public.product_spec_member_profile_events to authenticated;
drop policy if exists product_spec_member_profile_events_tenant_read on public.product_spec_member_profile_events;
create policy product_spec_member_profile_events_tenant_read on public.product_spec_member_profile_events
 for select to authenticated using (tenant_id=public.user_tenant_id());
create index if not exists product_spec_member_profile_events_profile on public.product_spec_member_profile_events(profile_id,occurred_at,id);

create or replace function public.spec_member_event_immutable_internal_v1()
returns trigger language plpgsql set search_path=pg_catalog,public,pg_temp as $$
begin
 raise exception 'El historial del componente conserva su actor y sus estados originales' using errcode='23514';
end $$;
drop trigger if exists spec_member_event_immutable on public.product_spec_member_profile_events;
create trigger spec_member_event_immutable before update or delete on public.product_spec_member_profile_events
 for each row execute function public.spec_member_event_immutable_internal_v1();

-- A real write barrier (rather than a snapshot-only existence check) makes a
-- metadata transaction with an older repeatable-read snapshot abort when a
-- profile was committed meanwhile. It is internal coordination, not template
-- metadata, and never changes a family's contract_version on a product edit.
create table if not exists public.spec_member_graph_revisions (
  template_id uuid primary key references public.spec_templates(id) on delete cascade,
  revision bigint not null default 0,
  last_xid bigint not null
);
revoke all on public.spec_member_graph_revisions from public,anon,authenticated;
alter table public.spec_member_graph_revisions enable row level security;
-- New relations must not inherit extra readers from an environment's default
-- privileges. Only the owner/service role and the explicit tenant reader above
-- belong to this extension; the internal epoch has no authenticated grant.
do $member_table_acl$
declare relation record; reader record;
begin
 for relation in select c.oid,c.relname,c.relowner,c.relacl from pg_class c
   where c.oid in ('public.product_spec_member_profiles'::regclass,
     'public.product_spec_member_profile_events'::regclass,'public.spec_member_graph_revisions'::regclass) loop
   for reader in select distinct a.grantee from aclexplode(relation.relacl) a
     where a.grantee not in (relation.relowner,'service_role'::regrole::oid,'authenticated'::regrole::oid) loop
     execute format('revoke all on table public.%I from %s',relation.relname,
       case when reader.grantee=0 then 'public' else quote_ident(pg_get_userbyid(reader.grantee)) end);
   end loop;
 end loop;
end $member_table_acl$;
create or replace function public.spec_member_graph_touch_internal_v1(p_template_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if p_template_id is null then return; end if;
 insert into public.spec_member_graph_revisions(template_id,revision,last_xid) values(p_template_id,1,txid_current())
 on conflict(template_id) do update set revision=public.spec_member_graph_revisions.revision+1,last_xid=txid_current()
 where public.spec_member_graph_revisions.last_xid<>txid_current();
end $$;

create or replace function public.spec_member_identity_enrichment_internal_v1(p_before jsonb,p_after jsonb)
returns boolean language sql immutable set search_path=pg_catalog,public,pg_temp as $$
 select jsonb_typeof(p_before)='object' and jsonb_typeof(p_after)='object' and not exists(
   select 1 from jsonb_each(p_before) e where public.spec_rule_known_internal_v1(e.value)
     and e.value is distinct from p_after->e.key)
$$;

-- The collection is enabled by template metadata. Field definitions, units and
-- rules remain owned by their existing family, including intrinsic row tables.
create or replace function public.spec_member_collection_contract_internal_v1(
  p_template_id uuid,p_definition_id uuid
) returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
declare cfg jsonb; entry jsonb; def public.spec_definitions%rowtype; k text; result jsonb;
begin
 select form_contract->'member_profiles' into cfg from public.spec_templates where id=p_template_id;
 if cfg is null then return null; end if;
 if jsonb_typeof(cfg) is distinct from 'object' or cfg->'version' is distinct from '1'::jsonb
   or jsonb_typeof(cfg->'collections') is distinct from 'array'
   or jsonb_array_length(cfg->'collections')=0
   or exists(select 1 from jsonb_object_keys(cfg) x where x not in ('version','collections')) then
   raise exception 'Contrato de perfiles de componentes inválido' using errcode='23514';
 end if;
 if exists(select 1 from jsonb_array_elements(cfg->'collections') x group by x->>'field' having count(*)>1) then
   raise exception 'La colección de componentes tiene dos dueños' using errcode='23514';
 end if;
 for entry in select value from jsonb_array_elements(cfg->'collections') loop
   if jsonb_typeof(entry) is distinct from 'object'
     or exists(select 1 from jsonb_object_keys(entry) x where x not in ('field','family_column','identity_columns'))
     or jsonb_typeof(entry->'field') is distinct from 'string'
     or jsonb_typeof(entry->'family_column') is distinct from 'string'
     or jsonb_typeof(entry->'identity_columns') is distinct from 'array' then
     raise exception 'Colección de perfiles inválida' using errcode='23514';
   end if;
   select d.* into def from public.spec_definitions d join public.spec_template_fields f on f.spec_definition_id=d.id
     join public.spec_templates t on t.id=f.template_id
     where f.template_id=p_template_id and d.key=entry->>'field'
       and t.form_contract->'roles'->>d.key='contents'
       and (d.tenant_id is null or d.tenant_id=t.tenant_id)
       and (f.tenant_id is null or f.tenant_id=t.tenant_id);
   if def.id is null or def.data_type<>'json' or not(def.validation_rules ? 'rows_schema') then
     raise exception 'El perfil necesita una colección activa de contenido' using errcode='23514';
   end if;
   if not exists(select 1 from jsonb_array_elements(def.validation_rules->'rows_schema'->'columns') c
     where c->>'key'=entry->>'family_column' and c->>'type'='token') then
     raise exception 'La familia del componente necesita una columna tipada' using errcode='23514';
   end if;
   if not (entry->'identity_columns' ?& array['identity_brand','identity_model']) or
     exists(select 1 from jsonb_array_elements(entry->'identity_columns') c
     where jsonb_typeof(c)<>'string') or
     jsonb_array_length(entry->'identity_columns')<>(select count(distinct x) from jsonb_array_elements(entry->'identity_columns') x) then
     raise exception 'Identidad de componente inválida' using errcode='23514';
   end if;
   for k in select jsonb_array_elements_text(entry->'identity_columns') loop
     if k=entry->>'family_column' or not exists(
       select 1 from jsonb_array_elements(def.validation_rules->'rows_schema'->'columns') c
       where c->>'key'=k and c->>'type' in ('token','text')) then
       raise exception 'Columna de identidad de componente inválida' using errcode='23514';
     end if;
   end loop;
   if def.id=p_definition_id then result:=entry; end if;
 end loop;
 return result;
end $$;

-- Resolves only a top-level row of this product, never a row in another scope.
create or replace function public.spec_member_binding_internal_v1(
  p_product_id uuid,p_definition_id uuid,p_row_id text,p_bound_template_id uuid default null
) returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
declare prod public.products%rowtype; parent_template uuid; cfg jsonb; row_value jsonb; row_sources jsonb;
  identity jsonb; family_key text; member_template uuid;
begin
 select * into prod from public.products where id=p_product_id;
 if not found then raise exception 'Producto no disponible' using errcode='42501'; end if;
 parent_template:=public.spec_template_resolution_internal_v1(prod.tenant_id,prod.category_id,prod.spec_template_id);
 cfg:=public.spec_member_collection_contract_internal_v1(parent_template,p_definition_id);
 if cfg is null then raise exception 'La ficha no admite perfiles en esta colección' using errcode='23514'; end if;
 select r->'values',r->'sources' into row_value,row_sources from public.spec_facts f
   cross join lateral jsonb_array_elements(f.value_json->'rows') r
   where f.tenant_id=prod.tenant_id and f.subject_type='product' and f.subject_id=prod.id
     and f.subject_scope is null and f.spec_definition_id=p_definition_id and r->>'id'=p_row_id;
 if row_value is null then raise exception 'Falta la fila del componente %: archiva o vuelve a vincular su ficha',p_row_id using errcode='23514'; end if;
 family_key:=row_value->>(cfg->>'family_column');
 select t.id into member_template from public.spec_templates t
   where t.key=family_key and t.is_active and (t.tenant_id is null or t.tenant_id=prod.tenant_id)
     and (p_bound_template_id is null or t.id=p_bound_template_id)
   order by (t.tenant_id=prod.tenant_id) desc nulls last,t.id limit 1;
 if member_template is null then raise exception 'Falta confirmar una familia con ficha disponible' using errcode='23514'; end if;
 select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) into identity from jsonb_each(row_value) e
   where e.key=cfg->>'family_column' or cfg->'identity_columns' ? e.key;
 return jsonb_build_object('identity',identity,'sources',row_sources,'template_id',member_template,'family_key',family_key);
end $$;

create or replace function public.spec_member_profile_issues_internal_v1(p_profile_id uuid)
returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
declare profile public.product_spec_member_profiles%rowtype; payload jsonb; issues jsonb;
begin
 select * into profile from public.product_spec_member_profiles where id=p_profile_id;
 if not found or profile.archived_at is not null then return '[]'; end if;
 perform public.spec_validate_product_fact_shape_internal_v1(profile.product_id,profile.scope);
 payload:=public.spec_template_product_scope_payload_internal_v1(profile.product_id,profile.template_id,false,profile.scope);
 -- The shared draft validator cannot accept omitted mandatory OEM facts. Its
 -- caller supplies the same completeness check as the root-product validator.
 if profile.reference_id is not null and exists(
   select 1 from public.product_spec_references r cross join lateral jsonb_object_keys(r.fact_values) k
   where r.id=profile.reference_id and (not(payload ? k) or not public.spec_rule_known_internal_v1(
     public.spec_payload_display_exact_internal_v1(jsonb_build_object(k,payload->k))->
       (select d.key from public.spec_definitions d where d.id::text=k)))) then
   raise exception 'La referencia exige hechos en la ficha del componente' using errcode='23514';
 end if;
 issues:=public.spec_validate_draft_internal_v1(profile.template_id,
   public.spec_payload_display_exact_internal_v1(payload),profile.reference_id,
   coalesce(profile.member_identity->>'identity_brand',''),coalesce(profile.member_identity->>'identity_model',''),
   coalesce(profile.manufacturer_sku,''));
 return (select coalesce(jsonb_agg(i||jsonb_build_object('profile_id',profile.id,
   'collection_definition_id',profile.collection_definition_id,'member_row_id',profile.member_row_id)),'[]'::jsonb)
   from jsonb_array_elements(issues) i);
end $$;

create or replace function public.spec_validate_product_member_profiles_internal_v1(p_product_id uuid)
returns void language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
declare profile public.product_spec_member_profiles%rowtype; binding jsonb; issues jsonb;
begin
 if exists(select 1 from public.spec_facts f where f.subject_type='product' and f.subject_id=p_product_id
   and f.subject_scope is not null and not exists(select 1 from public.product_spec_member_profiles p
     where p.product_id=f.subject_id and p.tenant_id=f.tenant_id and p.scope=f.subject_scope)) then
   raise exception 'Hecho de componente sin perfil dueño' using errcode='23514';
 end if;
 for profile in select * from public.product_spec_member_profiles
   where product_id=p_product_id and archived_at is null loop
   binding:=public.spec_member_binding_internal_v1(p_product_id,profile.collection_definition_id,profile.member_row_id,profile.template_id);
   if binding->'identity' is distinct from profile.member_identity or
     (binding->>'template_id')::uuid is distinct from profile.template_id then
     raise exception 'El componente cambió: archiva explícitamente su ficha anterior' using errcode='23514';
   end if;
   if exists(select 1 from public.spec_facts f where f.subject_type='product' and f.subject_id=p_product_id
     and f.subject_scope=profile.scope and not exists(select 1 from public.spec_template_fields tf
       where tf.template_id=profile.template_id and tf.spec_definition_id=f.spec_definition_id)) then
     raise exception 'El hecho no pertenece a la ficha del componente' using errcode='23514';
   end if;
   issues:=public.spec_member_profile_issues_internal_v1(profile.id);
   if exists(select 1 from jsonb_array_elements(issues) i where coalesce((i->>'blocking')::boolean,true)) then
     raise exception 'Ficha de componente contradictoria: %',issues using errcode='23514';
   end if;
 end loop;
end $$;

create or replace function public.spec_member_profile_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare prod public.products%rowtype; binding jsonb; v_template_id uuid;
begin
 if tg_op='DELETE' then
   raise exception 'Archiva la ficha del componente para conservar su evidencia' using errcode='23514';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(new.tenant_id::text||':spec_fact:'||new.product_id::text,0));
 select * into prod from public.products where id=new.product_id and tenant_id=new.tenant_id for update;
 if not found or not exists(select 1 from public.spec_templates t where t.id=new.template_id
   and (t.tenant_id is null or t.tenant_id=new.tenant_id)) or not exists(
     select 1 from public.spec_definitions d where d.id=new.collection_definition_id
       and (d.tenant_id is null or d.tenant_id=new.tenant_id)) then
   raise exception 'Perfil de componente ajeno al tenant' using errcode='42501';
 end if;
 for v_template_id in select distinct x from unnest(array[new.template_id,
   public.spec_template_resolution_internal_v1(prod.tenant_id,prod.category_id,prod.spec_template_id)]) x order by x loop
   perform public.spec_member_graph_touch_internal_v1(v_template_id);
 end loop;
 if jsonb_typeof(new.identity_sources) is distinct from 'array' or exists(
   select 1 from jsonb_array_elements(new.identity_sources) s
   where jsonb_typeof(s)<>'string' or not public.spec_source_url_valid_internal_v1(s#>>'{}')) then
   raise exception 'La identidad del componente necesita fuentes válidas' using errcode='23514';
 end if;
 if tg_op='UPDATE' then
   if old.archived_at is not null then
     raise exception 'La ficha archivada conserva su evidencia sin cambios' using errcode='23514';
   end if;
   if (new.id,new.tenant_id,new.product_id,new.collection_definition_id,new.template_id,new.created_at)
     is distinct from (old.id,old.tenant_id,old.product_id,old.collection_definition_id,old.template_id,old.created_at) then
     raise exception 'La identidad de la ficha del componente es inmutable' using errcode='23514';
   end if;
   if new.member_row_id is distinct from old.member_row_id and
     (new.member_identity,new.manufacturer_sku) is distinct from (old.member_identity,old.manufacturer_sku) then
     raise exception 'Vincular otra fila exige la misma identidad confirmada' using errcode='23514';
   end if;
   if (new.member_identity,new.manufacturer_sku) is distinct from (old.member_identity,old.manufacturer_sku) and (
     not public.spec_member_identity_enrichment_internal_v1(old.member_identity,new.member_identity)
     or (old.manufacturer_sku is not null and new.manufacturer_sku is distinct from old.manufacturer_sku)
     or jsonb_array_length(new.identity_sources)=0) then
     raise exception 'Cambiar identidad confirmada exige archivar; identificar un vacío exige su fuente' using errcode='23514';
   end if;
 end if;
 if new.archived_at is null then
   binding:=public.spec_member_binding_internal_v1(new.product_id,new.collection_definition_id,new.member_row_id,new.template_id);
   if binding->'identity' is distinct from new.member_identity then
     raise exception 'La fila elegida no corresponde a la identidad del componente' using errcode='23514';
   end if;
 end if;
 new.updated_at:=now();
 return new;
end $$;
drop trigger if exists spec_member_profile_guard on public.product_spec_member_profiles;
create trigger spec_member_profile_guard before insert or update or delete on public.product_spec_member_profiles
  for each row execute function public.spec_member_profile_guard_internal_v1();

create or replace function public.spec_member_profile_revision_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 insert into public.product_spec_member_profile_events(profile_id,tenant_id,product_id,actor_id,before_state,after_state)
 values(new.id,new.tenant_id,new.product_id,auth.uid(),case when tg_op='UPDATE' then to_jsonb(old) end,to_jsonb(new));
 update public.products set spec_revision=spec_revision+1 where id=new.product_id;
 return null;
end $$;
drop trigger if exists spec_member_profile_revision on public.product_spec_member_profiles;
create trigger spec_member_profile_revision after insert or update on public.product_spec_member_profiles
  for each row execute function public.spec_member_profile_revision_internal_v1();

create or replace function public.spec_member_profile_constraint_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 perform public.spec_validate_product_internal_v1(new.product_id);
 return null;
end $$;
drop trigger if exists spec_member_profile_constraint on public.product_spec_member_profiles;
create constraint trigger spec_member_profile_constraint after insert or update on public.product_spec_member_profiles
  deferrable initially deferred for each row execute function public.spec_member_profile_constraint_internal_v1();

create or replace function public.spec_member_metadata_constraint_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_template_id uuid; v_product_id uuid; target_ids uuid[];
begin
 if tg_table_name='spec_templates' then target_ids:=array[new.id];
 elsif tg_table_name='spec_template_fields' then
   target_ids:=array[case when tg_op='DELETE' then old.template_id else new.template_id end];
   if tg_op='UPDATE' then target_ids:=array_append(target_ids,old.template_id); end if;
 else
   select array_agg(f.template_id) into target_ids from public.spec_template_fields f where f.spec_definition_id=new.id;
 end if;
 for v_template_id in select distinct t.id from public.spec_templates t where t.id=any(target_ids) loop
   perform public.spec_member_graph_touch_internal_v1(v_template_id);
   perform public.spec_member_collection_contract_internal_v1(v_template_id,null);
   for v_product_id in select distinct p.id from public.product_spec_member_profiles m
     join public.products p on p.id=m.product_id where m.archived_at is null
       and (m.template_id=v_template_id or public.spec_template_resolution_internal_v1(p.tenant_id,p.category_id,p.spec_template_id)=v_template_id) loop
     perform public.spec_validate_product_member_profiles_internal_v1(v_product_id);
   end loop;
 end loop;
 return null;
end $$;
drop trigger if exists spec_member_template_metadata_constraint on public.spec_templates;
create constraint trigger spec_member_template_metadata_constraint after insert or update on public.spec_templates
 deferrable initially deferred for each row execute function public.spec_member_metadata_constraint_internal_v1();
drop trigger if exists spec_member_field_metadata_constraint on public.spec_template_fields;
create constraint trigger spec_member_field_metadata_constraint after insert or update or delete on public.spec_template_fields
 deferrable initially deferred for each row execute function public.spec_member_metadata_constraint_internal_v1();
drop trigger if exists spec_member_definition_metadata_constraint on public.spec_definitions;
create constraint trigger spec_member_definition_metadata_constraint after update on public.spec_definitions
 deferrable initially deferred for each row execute function public.spec_member_metadata_constraint_internal_v1();

-- A category binding is another metadata route to the parent template. Touch
-- both template epochs even when the current snapshot has no profiles: an RR
-- transaction must conflict with a profile committed after that snapshot.
create or replace function public.spec_member_category_constraint_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_template_id uuid; v_product_id uuid; target_ids uuid[];
begin
 if tg_op='UPDATE' and (old.tenant_id,old.category_id,old.template_id,old.status)
   is not distinct from (new.tenant_id,new.category_id,new.template_id,new.status) then return null; end if;
 target_ids:=array[case when tg_op<>'INSERT' then old.template_id end,
   case when tg_op<>'DELETE' then new.template_id end];
 for v_template_id in select distinct t.id from public.spec_templates t
   where t.id=any(target_ids) order by t.id loop
   perform public.spec_member_graph_touch_internal_v1(v_template_id);
 end loop;
 for v_product_id in select p.id from public.products p
   where p.spec_template_id is null and (
     (tg_op<>'INSERT' and p.tenant_id=old.tenant_id and p.category_id=old.category_id) or
     (tg_op<>'DELETE' and p.tenant_id=new.tenant_id and p.category_id=new.category_id))
   and exists(select 1 from public.product_spec_member_profiles m where m.product_id=p.id and m.archived_at is null)
   order by p.id loop
   perform public.spec_validate_product_member_profiles_internal_v1(v_product_id);
   -- Even a compatible parent reassignment invalidates an already-open editor.
   update public.products set spec_revision=spec_revision+1 where id=v_product_id;
 end loop;
 return null;
end $$;
drop trigger if exists spec_member_category_constraint on public.category_tech_mappings;
create constraint trigger spec_member_category_constraint after insert or update or delete on public.category_tech_mappings
 deferrable initially deferred for each row execute function public.spec_member_category_constraint_internal_v1();

-- Direct fact/option/reading writes must not mutate history or create an
-- unowned product scope. Bike/job_bike scopes retain their existing contract.
create or replace function public.spec_member_fact_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare fact public.spec_facts%rowtype; profile public.product_spec_member_profiles%rowtype; fid uuid; v_template_id uuid;
begin
 if tg_table_name='spec_facts' then
   if tg_op='DELETE' then fact:=old; else fact:=new; end if;
 else
   fid:=case when tg_op='DELETE' then old.fact_id else new.fact_id end;
   select * into fact from public.spec_facts where id=fid;
   if tg_op='UPDATE' and new.fact_id is distinct from old.fact_id and exists(
     select 1 from public.spec_facts where id in (old.fact_id,new.fact_id) and subject_type='product' and subject_scope is not null) then
     raise exception 'La evidencia no puede mudarse de componente' using errcode='23514';
   end if;
 end if;
 if fact.subject_type='product' and fact.subject_scope is not null then
   perform pg_advisory_xact_lock(hashtextextended(fact.tenant_id::text||':spec_fact:'||fact.subject_id::text,0));
   select * into profile from public.product_spec_member_profiles where tenant_id=fact.tenant_id
     and product_id=fact.subject_id and scope=fact.subject_scope for share;
   if not found then raise exception 'Hecho de componente sin perfil dueño' using errcode='23514'; end if;
   if profile.archived_at is not null then
     raise exception 'La ficha archivada conserva su evidencia sin cambios' using errcode='23514';
   end if;
   for v_template_id in select distinct x from public.products p cross join lateral unnest(array[profile.template_id,
     public.spec_template_resolution_internal_v1(p.tenant_id,p.category_id,p.spec_template_id)]) x
     where p.id=profile.product_id order by x loop
     perform public.spec_member_graph_touch_internal_v1(v_template_id);
   end loop;
 end if;
 if tg_op='DELETE' then return old; else return new; end if;
end $$;
drop trigger if exists spec_member_fact_guard on public.spec_facts;
create trigger spec_member_fact_guard before insert or update or delete on public.spec_facts
  for each row execute function public.spec_member_fact_guard_internal_v1();
drop trigger if exists spec_member_fact_values_guard on public.spec_fact_values;
create trigger spec_member_fact_values_guard before insert or update or delete on public.spec_fact_values
  for each row execute function public.spec_member_fact_guard_internal_v1();
drop trigger if exists spec_member_fact_readings_guard on public.spec_fact_readings;
create trigger spec_member_fact_readings_guard before insert or update or delete on public.spec_fact_readings
  for each row execute function public.spec_member_fact_guard_internal_v1();

create or replace function public.spec_member_reading_revision_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 update public.products p set spec_revision=p.spec_revision+1 from public.spec_facts f
   where f.id=case when tg_op='DELETE' then old.fact_id else new.fact_id end
     and f.subject_type='product' and f.subject_scope is not null and f.subject_id=p.id and f.tenant_id=p.tenant_id;
 return null;
end $$;
drop trigger if exists spec_member_reading_revision on public.spec_fact_readings;
create trigger spec_member_reading_revision after insert or update or delete on public.spec_fact_readings
 for each row execute function public.spec_member_reading_revision_internal_v1();

create or replace function public.spec_apply_member_profiles_internal_v1(p_product_id uuid,p_command jsonb)
returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare entry jsonb; profile public.product_spec_member_profiles%rowtype; binding jsonb; t public.spec_templates%rowtype;
  tenant uuid:=public.user_tenant_id(); profile_id uuid;
begin
 if jsonb_typeof(p_command) is distinct from 'object' or p_command->'schema_version' is distinct from '1'::jsonb
   or jsonb_typeof(p_command->'upserts') is distinct from 'array'
   or jsonb_typeof(p_command->'archive_ids') is distinct from 'array'
   or exists(select 1 from jsonb_object_keys(p_command) k where k not in ('schema_version','upserts','archive_ids'))
   or jsonb_array_length(p_command->'upserts')>200 or jsonb_array_length(p_command->'archive_ids')>200 then
   raise exception 'Comando de perfiles de componentes inválido' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_array_elements(p_command->'upserts') e group by (e->>'id')::uuid having count(*)>1)
   or exists(select 1 from jsonb_array_elements(p_command->'archive_ids') e group by (e#>>'{}')::uuid having count(*)>1) then
   raise exception 'El comando repite una ficha de componente' using errcode='22023';
 end if;
 for entry in select value from jsonb_array_elements(p_command->'archive_ids') loop
   if jsonb_typeof(entry)<>'string' then raise exception 'Identificador de archivo inválido' using errcode='22023'; end if;
   profile_id:=(entry#>>'{}')::uuid;
   select * into profile from public.product_spec_member_profiles where id=profile_id and tenant_id=tenant
     and product_id=p_product_id for update;
   if not found then raise exception 'Ficha de componente no disponible' using errcode='42501'; end if;
   if profile.archived_at is null then
     update public.product_spec_member_profiles set archived_at=now() where id=profile.id;
   end if;
 end loop;
 for entry in select value from jsonb_array_elements(p_command->'upserts') loop
   if jsonb_typeof(entry) is distinct from 'object' or jsonb_typeof(entry->'values') is distinct from 'object'
     or not(entry ?& array['id','collection_definition_id','member_row_id','template_id','contract_version','values'])
     or exists(select 1 from jsonb_object_keys(entry) k where k not in ('id','collection_definition_id',
       'member_row_id','template_id','contract_version','reference_id','manufacturer_sku','values','binding_action'))
     or (entry ? 'binding_action' and coalesce(entry->>'binding_action','') not in ('identify','rebind')) then
     raise exception 'Ficha de componente inválida' using errcode='22023';
   end if;
   profile_id:=(entry->>'id')::uuid;
   binding:=public.spec_member_binding_internal_v1(p_product_id,(entry->>'collection_definition_id')::uuid,
     entry->>'member_row_id',(entry->>'template_id')::uuid);
   select * into t from public.spec_templates where id=(binding->>'template_id')::uuid for share;
   if t.id is distinct from (entry->>'template_id')::uuid
     or t.contract_version is distinct from (entry->>'contract_version')::integer then
     raise exception 'La ficha del componente cambió. Recarga antes de guardar.' using errcode='40001';
   end if;
   select * into profile from public.product_spec_member_profiles where id=profile_id for update;
   if found then
     if (profile.tenant_id,profile.product_id) is distinct from (tenant,p_product_id) then
       raise exception 'Ficha de componente no disponible' using errcode='42501';
     end if;
     if profile.archived_at is not null or (profile.collection_definition_id,profile.template_id) is distinct from
       ((entry->>'collection_definition_id')::uuid,t.id) then
       raise exception 'Archiva la ficha anterior y crea una para esta pieza' using errcode='23514';
     end if;
     if (profile.member_identity,profile.manufacturer_sku) is distinct from
       (binding->'identity',nullif(btrim(entry->>'manufacturer_sku'),'')) then
       if entry->>'binding_action' is distinct from 'identify' or profile.member_row_id<>entry->>'member_row_id' then
         raise exception 'Confirma la identificación con su fuente o archiva la ficha anterior' using errcode='23514';
       end if;
       update public.product_spec_member_profiles set member_identity=binding->'identity',identity_sources=binding->'sources',
         manufacturer_sku=nullif(btrim(entry->>'manufacturer_sku'),'') where id=profile.id;
     elsif profile.member_row_id<>entry->>'member_row_id' then
       if entry->>'binding_action' is distinct from 'rebind' then
         raise exception 'Elige explícitamente la fila para volver a vincular esta ficha' using errcode='23514';
       end if;
       update public.product_spec_member_profiles set member_row_id=entry->>'member_row_id' where id=profile.id;
     end if;
     if (profile.reference_id,profile.saved_contract_version) is distinct from (entry->>'reference_id',t.contract_version) then
       update public.product_spec_member_profiles set reference_id=entry->>'reference_id',saved_contract_version=t.contract_version
         where id=profile.id;
     end if;
   else
     insert into public.product_spec_member_profiles(id,tenant_id,product_id,collection_definition_id,member_row_id,
       member_identity,identity_sources,manufacturer_sku,template_id,saved_contract_version,reference_id)
     values(profile_id,tenant,p_product_id,(entry->>'collection_definition_id')::uuid,entry->>'member_row_id',
       binding->'identity',binding->'sources',nullif(btrim(entry->>'manufacturer_sku'),''),t.id,t.contract_version,entry->>'reference_id');
   end if;
   perform public.spec_write_scope_payload_internal_v1(p_product_id,t.id,entry->'values',entry->>'reference_id','member:'||profile_id::text);
 end loop;
end $$;

-- Research backups include the binding history as well as scoped facts. The
-- v1 snapshot already covers all fact scopes; v2 adds their profile owners and
-- pins them in the fingerprint instead of leaving the observations orphaned.
create or replace function public.get_product_spec_research_snapshot_v2(p_product_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare root_snapshot jsonb; members jsonb; events jsonb; fingerprints jsonb;
begin
 root_snapshot:=public.get_product_spec_research_snapshot_v1(p_product_id);
 members:=public.get_product_spec_member_profiles_v1(p_product_id);
 select coalesce(jsonb_agg(to_jsonb(e) order by e.occurred_at,e.id),'[]'::jsonb) into events
   from public.product_spec_member_profile_events e where e.product_id=p_product_id and e.tenant_id=public.user_tenant_id();
 fingerprints:=root_snapshot->'fingerprints'||jsonb_build_object(
   'member_profiles_sha256',encode(extensions.digest(members::text,'sha256'),'hex'),
   'member_events_sha256',encode(extensions.digest(events::text,'sha256'),'hex'));
 return root_snapshot||jsonb_build_object('read_schema_version',2,'member_profiles',members,'member_profile_events',events,
   'fingerprints',fingerprints,'snapshot_sha256',encode(extensions.digest(jsonb_build_object(
     'root_snapshot_sha256',root_snapshot->>'snapshot_sha256','fingerprints',fingerprints)::text,'sha256'),'hex'));
end $$;

create or replace function public.get_product_spec_member_profiles_v1(p_product_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare prod public.products%rowtype; profile public.product_spec_member_profiles%rowtype;
  result jsonb:='[]'; archived jsonb:='[]'; profile_context jsonb; ref jsonb;
begin
 if auth.uid() is null then raise exception 'Authenticated tenant required' using errcode='42501'; end if;
 select * into prod from public.products where id=p_product_id and tenant_id=public.user_tenant_id();
 if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
 for profile in select * from public.product_spec_member_profiles where product_id=p_product_id and tenant_id=prod.tenant_id
   order by created_at,id loop
   select (to_jsonb(r)-'fact_values')||jsonb_build_object('read_schema_version',2,
     'facts',public.spec_payload_display_exact_internal_v1(r.fact_values)) into ref
     from public.product_spec_references r where id=profile.reference_id;
   profile_context:=to_jsonb(profile)||jsonb_build_object(
     'fact_payload',(select coalesce(jsonb_object_agg(e.key,case when d.data_type='number' then
       jsonb_build_object('number',e.value->>'number') else e.value end),'{}'::jsonb)
       from jsonb_each(public.spec_product_scope_payload_internal_v1(prod.id,profile.scope)) e
       join public.spec_definitions d on d.id::text=e.key),
     'catalog_keys',(select coalesce(jsonb_agg(d.key order by d.key),'[]'::jsonb) from public.spec_facts f
       join public.spec_definitions d on d.id=f.spec_definition_id
       where f.tenant_id=prod.tenant_id and f.subject_type='product' and f.subject_id=prod.id
         and f.subject_scope=profile.scope and f.source='catalog'),
     'values',public.spec_payload_display_exact_internal_v1(public.spec_product_scope_payload_internal_v1(prod.id,profile.scope)),
     'reference',ref,'issues',public.spec_member_profile_issues_internal_v1(profile.id));
   if profile.archived_at is null then
     profile_context:=profile_context||jsonb_build_object('template',public.spec_template_editor_internal_v1(profile.template_id,prod.tenant_id));
     result:=result||jsonb_build_array(profile_context);
   else
     archived:=archived||jsonb_build_array(profile_context);
   end if;
 end loop;
 return jsonb_build_object('read_schema_version',1,'product_id',prod.id,'revision',prod.spec_revision,
   'product_updated_at',prod.updated_at,'profiles',result,'archived_profiles',archived);
end $$;

-- One statement supplies the root and scoped contexts in the same MVCC view.
create or replace function public.get_product_spec_editor_context_v3(p_product_id uuid,p_category_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare root_context jsonb; persisted_context jsonb; prod public.products%rowtype; persisted_template uuid;
begin
 root_context:=public.get_product_spec_editor_context_v2(p_product_id,p_category_id);
 if p_product_id is not null then
   select * into prod from public.products where id=p_product_id and tenant_id=public.user_tenant_id();
   if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
   persisted_template:=public.spec_template_resolution_internal_v1(prod.tenant_id,prod.category_id,prod.spec_template_id);
   if persisted_template is distinct from (root_context->>'template_id')::uuid then
     persisted_context:=public.get_product_spec_editor_context_v2(p_product_id,prod.category_id)
       ||jsonb_build_object('product_updated_at',prod.updated_at);
   end if;
 end if;
 -- A category preview changes only the draft root. Keep the persisted owner
 -- available so its components can still be edited or explicitly archived.
 return root_context||jsonb_build_object('product_updated_at',prod.updated_at,'member_parent_context',persisted_context,
   'member_profiles',case when p_product_id is null then
   jsonb_build_object('read_schema_version',1,'product_id',null,'revision',0,
     'product_updated_at',null,'profiles','[]'::jsonb,'archived_profiles','[]'::jsonb)
   else public.get_product_spec_member_profiles_v1(p_product_id) end);
end $$;

-- Draft rows have not yet been persisted. Load the existing family's contract
-- after checking the parent's declared collection; saving still resolves the
-- actual persisted row and rechecks every template version atomically.
create or replace function public.get_product_spec_member_template_v1(
 p_parent_template_id uuid,p_collection_definition_id uuid,p_family_key text
) returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare tenant uuid:=public.user_tenant_id(); cfg jsonb; result jsonb; target uuid;
begin
 if auth.uid() is null or tenant is null or not exists(select 1 from public.spec_templates
   where id=p_parent_template_id and is_active and (tenant_id is null or tenant_id=tenant)) then
   raise exception 'Ficha no disponible para este tenant' using errcode='42501';
 end if;
 cfg:=public.spec_member_collection_contract_internal_v1(p_parent_template_id,p_collection_definition_id);
 if cfg is null or not exists(select 1 from public.spec_definitions d,
   lateral jsonb_array_elements(d.validation_rules->'rows_schema'->'columns') c
   where d.id=p_collection_definition_id and c->>'key'=cfg->>'family_column' and c->'allowed_values' ? p_family_key) then
   raise exception 'La familia no corresponde a esta colección' using errcode='23514';
 end if;
 select t.id into target from public.spec_templates t where t.key=p_family_key and t.is_active
   and (t.tenant_id is null or t.tenant_id=tenant)
   order by (t.tenant_id=tenant) desc nulls last,t.id limit 1;
 if target is null then raise exception 'La familia aún no tiene una ficha disponible' using errcode='23514'; end if;
 result:=public.spec_template_editor_internal_v1(target,tenant);
 return jsonb_build_object('read_schema_version',2,'revision',0,'values','{}'::jsonb,
   'parent_template_id',p_parent_template_id,'collection_definition_id',p_collection_definition_id,
   'template_id',target,'template_key',result->>'key','technical_family',result->>'technical_family',
   'contract_version',result->'contract_version','template',result);
end $$;
create or replace function public.spec_product_payload_internal_v1(p_product_id uuid)
returns jsonb language sql stable set search_path=pg_catalog,public,pg_temp as $$
 select public.spec_product_scope_payload_internal_v1(p_product_id,null)
$$;
create or replace function public.spec_template_product_payload_internal_v1(p_product_id uuid,p_template_id uuid,p_include_legacy boolean)
returns jsonb language sql stable set search_path=pg_catalog,public,pg_temp as $$
 select public.spec_template_product_scope_payload_internal_v1(p_product_id,p_template_id,p_include_legacy,null)
$$;
create or replace function public.spec_write_payload_internal_v2(p_product_id uuid,p_template_id uuid,p_values jsonb,p_reference_id text)
returns integer language sql security definer set search_path=pg_catalog,public,pg_temp as $$
 select public.spec_write_scope_payload_internal_v1(p_product_id,p_template_id,p_values,p_reference_id,null)
$$;
CREATE OR REPLACE FUNCTION public.get_product_spec_editor_context_v2(p_product_id uuid, p_category_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_variable
declare result jsonb; template_id uuid; template jsonb; fields jsonb; unassigned jsonb;
 tenant uuid:=public.user_tenant_id();
begin
 -- This call enforces product/category tenant ownership and explicit binding.
 -- STABLE nested reads share this statement's MVCC snapshot.
 result:=public.get_product_spec_editor_context_v1(p_product_id,p_category_id);
 template_id:=(result->>'template_id')::uuid;
 if template_id is not null then
   template:=public.spec_template_editor_internal_v1(template_id,tenant);
 end if;
 select coalesce(jsonb_agg(case when d.data_type='number' then e.value||jsonb_build_object(
     'value',public.spec_json_numbers_as_text_internal_v1(e.value->'value')) else e.value end order by e.ordinality),'[]'::jsonb)
 into unassigned from jsonb_array_elements(result->'unassigned_facts') with ordinality e
 left join public.spec_definitions d on d.id::text=e.value->>'definition_id';
 return result||jsonb_build_object('read_schema_version',2,'product_id',p_product_id,'draft_category_id',p_category_id,
   'template',template,'unassigned_facts',unassigned,
   'values',public.spec_payload_display_exact_internal_v1(public.spec_template_product_payload_internal_v1(p_product_id,template_id,true)));
end $function$;
CREATE OR REPLACE FUNCTION public.spec_validate_product_internal_v1(p_product_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_product public.products%rowtype; v_template uuid; v_issues jsonb;
begin
  select * into v_product from public.products where id = p_product_id;
  if not found then return; end if;
  perform public.spec_validate_product_member_profiles_internal_v1(p_product_id);
  v_template:=public.spec_template_resolution_internal_v1(v_product.tenant_id,v_product.category_id,v_product.spec_template_id);
  if v_product.spec_template_id is not null and v_template is null then
    raise exception 'Plantilla no disponible para este tenant' using errcode='42501';
  end if;
  if v_template is null then
    if v_product.spec_reference_id is not null then
      raise exception 'La referencia requiere una familia técnica' using errcode = '23514';
    end if;
    return;
  end if;
  perform public.spec_validate_product_fact_shape_internal_v1(p_product_id,null);
  if v_product.spec_reference_id is not null and exists(
    select 1 from public.product_spec_references r cross join lateral jsonb_object_keys(r.fact_values) k
    where r.id=v_product.spec_reference_id and (not (public.spec_product_payload_internal_v1(p_product_id) ? k)
      or not public.spec_rule_known_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(k,public.spec_product_payload_internal_v1(p_product_id)->k))->(select d.key from public.spec_definitions d where d.id::text=k)))
  ) then raise exception 'La referencia requiere sus datos documentados' using errcode='23514'; end if;
  v_issues := public.spec_validate_draft_internal_v1(v_template,
    public.spec_active_product_values_internal_v1(p_product_id,v_template),
    v_product.spec_reference_id,v_product.brand,v_product.model,v_product.manufacturer_sku);
  if exists(select 1 from jsonb_array_elements(v_issues) i where coalesce((i->>'blocking')::boolean,true)) then
    raise exception 'La ficha técnica tiene conflictos' using errcode = '23514', detail = v_issues::text;
  end if;
end $function$;
CREATE OR REPLACE FUNCTION public.spec_save_product_with_specs_internal_v2(p_product jsonb, p_is_new boolean, p_template_id uuid, p_contract_version integer, p_values jsonb, p_expected_revision bigint, p_reference_id text, p_operation_key text, p_expected_updated_at timestamp with time zone, p_components jsonb, p_member_profiles jsonb, p_protocol integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_tenant uuid := public.user_tenant_id(); v_id uuid; v_product public.products%rowtype;
  v_receipt public.product_spec_save_receipts%rowtype; v_hash text; v_patch jsonb;
  v_keys text[]; v_columns text; v_select text; v_assign text; v_result jsonb; v_set jsonb;
  v_template public.spec_templates%rowtype;
  v_allow text[] := array[
    'name','sku','description','website_description','category_id','supplier_id','supplier_reference','supplier_code',
    'brand_id','brand','model','manufacturer','manufacturer_sku','gtin','barcode','hs_code','country_of_origin',
    'color','size','material','dimensions','price','cost','min_stock_level','max_stock_level','image_url',
    'image_url_optimized','image_fingerprint','image_urls','specifications','tags','warranty_months','lifecycle_status',
    'serialized','lot_tracking','expiration_tracking','expiry_days','lead_time_days','reorder_quantity','warehouse_location',
    'price_currency','cost_currency','tax_rate','is_active','is_published','website_name','website_price',
    'website_image_url','website_image_url_optimized','website_image_urls','website_seo_title','website_seo_description',
    'website_search_terms','website_merchant_title','website_merchant_description','website_merchant_brand',
    'website_merchant_gtin','website_merchant_mpn','website_google_product_category','is_google_merchant',
    'is_whatsapp_catalog','whatsapp_catalog_title','whatsapp_catalog_description','whatsapp_catalog_price',
    'show_on_website','purchase_treatment','product_type','is_service','track_stock','embedding','set_type'
  ];
begin
  if v_tenant is null or auth.uid() is null then raise exception 'Authenticated tenant required' using errcode = '42501'; end if;
  if p_protocol not in (1,2) or p_protocol is null
    or (p_protocol=1 and p_member_profiles is not null)
    or (p_protocol=2 and jsonb_typeof(p_member_profiles) is distinct from 'object') then
    raise exception 'Invalid specification save protocol' using errcode='22023';
  end if;
  if p_is_new is null or jsonb_typeof(p_product) is distinct from 'object'
    or jsonb_typeof(p_values) is distinct from 'object' or nullif(btrim(p_operation_key),'') is null
    or length(p_operation_key) > 180 then raise exception 'Invalid specification save command' using errcode = '22023'; end if;
  if p_product ? 'tenant_id' and nullif(p_product->>'tenant_id','')::uuid is distinct from v_tenant then
    raise exception 'Foreign tenant in product command' using errcode = '42501';
  end if;
  if coalesce((p_product->>'inventory_qty')::numeric,0) <> 0 or coalesce((p_product->>'stock_quantity')::numeric,0) <> 0 then
    raise exception 'El stock requiere un ajuste de inventario' using errcode = '23514';
  end if;
  if exists (select 1 from jsonb_object_keys(p_product) k where not (k = any(v_allow || array[
    'id','tenant_id','created_at','updated_at','inventory_qty','stock_quantity','is_set','parent_set_id',
    'component_label','component_position','expected_updated_at']))) then
    raise exception 'Unsupported product patch field' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_tenant::text || ':product_spec_save:' || p_operation_key,0));
  v_hash := md5(jsonb_build_object('product',p_product - array['created_at','updated_at','embedding'],
    'new',p_is_new,'template',p_template_id,'version',p_contract_version,'values',p_values,
    'reference',p_reference_id,'components',p_components)::text);
  -- v1 hashes remain byte-identical so existing retries keep their receipt.
  -- The v2 protocol hashes the entire member command before reading a receipt.
  if p_protocol=2 then
    v_hash:=md5(jsonb_build_object('protocol',2,'root_hash',v_hash,'member_profiles',p_member_profiles)::text);
  end if;
  select * into v_receipt from public.product_spec_save_receipts
    where tenant_id = v_tenant and operation_key = p_operation_key;
  if found then
    if v_receipt.request_hash <> v_hash then raise exception 'Este intento ya se guardó con otros datos. Reabre el producto antes de continuar.' using errcode = '23505'; end if;
    return v_receipt.result || jsonb_build_object('replayed',true);
  end if;
  v_id := coalesce(nullif(p_product->>'id','')::uuid,gen_random_uuid());
  if not p_is_new and nullif(p_product->>'id','') is null then raise exception 'Existing product ID required' using errcode = '22023'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_tenant::text || ':spec_fact:' || v_id::text,0));
  select * into v_product from public.products where id = v_id and tenant_id = v_tenant for update;
  if p_is_new and exists(select 1 from public.products where id = v_id) then
    raise exception 'Product already exists' using errcode = '23505';
  elsif not p_is_new and v_product.id is null then
    raise exception 'Producto no disponible para este tenant' using errcode = '42501';
  elsif not p_is_new and (v_product.spec_revision is distinct from p_expected_revision
    or v_product.updated_at is distinct from p_expected_updated_at) then
    raise exception 'La ficha cambió desde que la abriste. Recarga antes de guardar.' using errcode = '40001';
  end if;
  select t.* into v_template from public.spec_templates t where t.id=public.spec_template_resolution_internal_v1(
    v_tenant,case when p_product ? 'category_id' then nullif(p_product->>'category_id','')::uuid else v_product.category_id end,
    v_product.spec_template_id) for share of t;
  if v_template.id is distinct from p_template_id or (p_template_id is not null
    and v_template.contract_version is distinct from p_contract_version) then
    raise exception 'La plantilla cambió. Recarga la ficha antes de guardar.' using errcode = '40001';
  end if;
  if p_template_id is null and (p_values <> '{}'::jsonb or p_reference_id is not null) then
    raise exception 'Una ficha necesita su plantilla' using errcode = '23514';
  end if;
  if nullif(btrim(p_product->>'name'),'') is null or nullif(btrim(p_product->>'sku'),'') is null then
    raise exception 'El producto requiere nombre y SKU' using errcode='23514';
  end if;
  if nullif(p_product->>'category_id','') is not null and not exists(
    select 1 from public.product_categories where id=(p_product->>'category_id')::uuid and tenant_id=v_tenant)
    or nullif(p_product->>'supplier_id','') is not null and not exists(
    select 1 from public.suppliers where id=(p_product->>'supplier_id')::uuid and tenant_id=v_tenant)
    or nullif(p_product->>'brand_id','') is not null and not exists(
    select 1 from public.product_brands where id=(p_product->>'brand_id')::uuid and (tenant_id is null or tenant_id=v_tenant)) then
    raise exception 'Foreign product relation' using errcode='42501';
  end if;
  if p_components is not null then
    v_set := public.save_product_set_aggregate(p_product || jsonb_build_object('id',v_id),p_components,p_operation_key);
  else
    if coalesce((p_product->>'is_set')::boolean,false) or v_product.is_set then
      raise exception 'Un juego debe guardarse con sus componentes' using errcode = '23514';
    end if;
    v_patch := (select coalesce(jsonb_object_agg(k,value),'{}'::jsonb) from jsonb_each(p_product) e(k,value) where k = any(v_allow));
    v_keys := array(select jsonb_object_keys(v_patch) order by 1);
    select string_agg(format('%I',k),','),string_agg(format('r.%I',k),','),string_agg(format('%I = r.%I',k,k),',')
      into v_columns,v_select,v_assign from unnest(v_keys) k;
    if p_is_new then
      execute format('insert into public.products(id,tenant_id,%s) select $2,$3,%s from jsonb_populate_record(null::public.products,$1) r',v_columns,v_select)
        using v_patch,v_id,v_tenant;
    else
      execute format('update public.products p set %s,updated_at = clock_timestamp() from jsonb_populate_record(null::public.products,$1) r where p.id = $2 and p.tenant_id = $3',v_assign)
        using v_patch,v_id,v_tenant;
    end if;
  end if;
  update public.products set spec_reference_id = p_reference_id where id = v_id and tenant_id = v_tenant;
  if p_template_id is not null then
    perform public.spec_write_payload_internal_v2(v_id,p_template_id,p_values,p_reference_id);
  end if;
  if p_protocol=2 then
    perform public.spec_apply_member_profiles_internal_v1(v_id,p_member_profiles);
  end if;
  perform public.spec_validate_product_internal_v1(v_id);
  select jsonb_build_object('product',to_jsonb(p),'revision',p.spec_revision,'replayed',false)
    into v_result from public.products p where p.id = v_id and p.tenant_id = v_tenant;
  if v_set is not null then v_result := v_result || jsonb_build_object('set',v_set || jsonb_build_object('parent',v_result->'product')); end if;
  if p_protocol=2 then
    v_result:=v_result||jsonb_build_object('member_profiles',public.get_product_spec_member_profiles_v1(v_id),
      'editor_context',public.get_product_spec_editor_context_v3(v_id,
        (select category_id from public.products where id=v_id)));
  end if;
  insert into public.product_spec_save_receipts(tenant_id,operation_key,request_hash,result)
    values(v_tenant,p_operation_key,v_hash,v_result);
  return v_result;
end $function$;
create or replace function public.save_product_with_specs_v1(p_product jsonb, p_is_new boolean, p_template_id uuid, p_contract_version integer, p_values jsonb, p_expected_revision bigint, p_reference_id text, p_operation_key text, p_expected_updated_at timestamp with time zone, p_components jsonb DEFAULT NULL::jsonb)
returns jsonb language sql security definer set search_path=pg_catalog,public,pg_temp as $$
 select public.spec_save_product_with_specs_internal_v2(p_product,p_is_new,p_template_id,p_contract_version,p_values,p_expected_revision,p_reference_id,p_operation_key,p_expected_updated_at,p_components,null,1)
$$;
create or replace function public.save_product_with_specs_v2(p_product jsonb, p_is_new boolean, p_template_id uuid, p_contract_version integer, p_values jsonb, p_expected_revision bigint, p_reference_id text, p_operation_key text, p_expected_updated_at timestamp with time zone, p_member_profiles jsonb, p_components jsonb DEFAULT NULL::jsonb)
returns jsonb language sql security definer set search_path=pg_catalog,public,pg_temp as $$
 select public.spec_save_product_with_specs_internal_v2(p_product,p_is_new,p_template_id,p_contract_version,p_values,p_expected_revision,p_reference_id,p_operation_key,p_expected_updated_at,p_components,p_member_profiles,2)
$$;
do $acl$
declare fn record;
begin
 for fn in select p.oid::regprocedure as signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
   where n.nspname='public' and p.proname=any(array[
     'spec_product_scope_payload_internal_v1','spec_template_product_scope_payload_internal_v1',
     'spec_write_scope_payload_internal_v1','spec_template_editor_internal_v1',
     'spec_validate_product_fact_shape_internal_v1','spec_member_collection_contract_internal_v1',
     'spec_member_identity_enrichment_internal_v1',
     'spec_member_graph_touch_internal_v1',
     'spec_member_event_immutable_internal_v1','spec_member_category_constraint_internal_v1',
     'spec_member_reading_revision_internal_v1',
     'spec_member_binding_internal_v1','spec_member_profile_issues_internal_v1',
     'spec_validate_product_member_profiles_internal_v1','spec_member_profile_guard_internal_v1',
     'spec_member_profile_revision_internal_v1','spec_member_profile_constraint_internal_v1',
     'spec_member_metadata_constraint_internal_v1','get_product_spec_member_template_v1',
     'spec_member_fact_guard_internal_v1','spec_apply_member_profiles_internal_v1',
     'spec_save_product_with_specs_internal_v2','get_product_spec_member_profiles_v1',
     'get_product_spec_research_snapshot_v2',
     'get_product_spec_editor_context_v3','save_product_with_specs_v2']) loop
   execute format('revoke all on function %s from public,anon,authenticated',fn.signature);
 end loop;
end $acl$;
grant execute on function public.get_product_spec_member_profiles_v1(uuid),
 public.get_product_spec_editor_context_v3(uuid,uuid),
 public.get_product_spec_member_template_v1(uuid,uuid,text),
 public.get_product_spec_research_snapshot_v2(uuid),
 public.save_product_with_specs_v2(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamptz,jsonb,jsonb)
 to authenticated;

do $functions$
declare wanted jsonb; actual jsonb;
begin
 
 for wanted in select value from jsonb_array_elements('[{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"977c2146949cfddabc03a1de248598bc","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_editor_context_v2(uuid,uuid)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"b78ece378e8f70a2282586a09ac1481a","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_editor_context_v3(uuid,uuid)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"604107480ffe3d26740975c8635994b9","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_member_profiles_v1(uuid)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"3639e9242cf7b2e2bfca740d9717eca4","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_member_template_v1(uuid,uuid,text)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"e8bd4c930b6c5ca5b4c455ff1606922f","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"get_product_spec_research_snapshot_v2(uuid)","volatility":"s","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"cbd432b9892842961abec4f9950e3b9f","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}","md5":"43f2feb8bda787b386ad1a3cbc2f9971","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"save_product_with_specs_v2(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb,jsonb)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"b408a4c0db772e61a1cf372a5ad0171c","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_apply_member_profiles_internal_v1(uuid,jsonb)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"d9e0a08ca3d95e4fb67e3eb2e8b6880d","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_binding_internal_v1(uuid,uuid,text,uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"6026de56d6112b7c10919f6cd42fbb35","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_category_constraint_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"a7de45643b6c30f9d9d3eaab844accb9","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_collection_contract_internal_v1(uuid,uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"25cce62d4f204b929a8772e6a8d82cd5","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_event_immutable_internal_v1()","volatility":"v","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"498b68a21a1c36d40153392c66e6c312","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_fact_guard_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"4698117d2826ea0e2d2694cfff518e1f","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_graph_touch_internal_v1(uuid)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"73340635457d66c471ceba0d77f1a9ec","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_identity_enrichment_internal_v1(jsonb,jsonb)","volatility":"i","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"4e0960c70cb9661d41e214578ea8f325","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_metadata_constraint_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"7b3cde401821955714c90f30a0a8a47e","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_profile_constraint_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"64c5d3e81962271d42524a6ca9430992","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_profile_guard_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"0ddc8bea7c5d7fbfbca8fbf8b60be8e1","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_profile_issues_internal_v1(uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"14e0d49c11737c959a74b4d53cccbfea","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_profile_revision_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"564c8154b4a6fb52733761d12d91e3df","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_member_reading_revision_internal_v1()","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"9154286781ea568d0d30f9018b185c6a","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_product_payload_internal_v1(uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"a49ac75683db625460cec11de8e13b46","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_product_scope_payload_internal_v1(uuid,text)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"06cbf3bd2edb820007ada9a7e7444b04","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_save_product_with_specs_internal_v2(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb,jsonb,integer)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"dc82a3d8359e72cf2afb4c0d0c45156c","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_template_editor_internal_v1(uuid,uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"44e846009662462220baa2e60686aa5a","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_template_product_payload_internal_v1(uuid,uuid,boolean)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"5a7555f13bb7dd0dc7f797abde9cac52","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_template_product_scope_payload_internal_v1(uuid,uuid,boolean,text)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"d290d4df318cff8865553df64b929c78","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_validate_product_fact_shape_internal_v1(uuid,text)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"ebe417e4a4d802d7dfc60f40768125e7","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_validate_product_internal_v1(uuid)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"e20342ed1ea076059d9325382b58798d","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_validate_product_member_profiles_internal_v1(uuid)","volatility":"s","security_definer":false},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"0c1ef47fee4b566ce39c4255d2f0f484","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_write_payload_internal_v2(uuid,uuid,jsonb,text)","volatility":"v","security_definer":true},{"acl":"{postgres=X/postgres,service_role=X/postgres}","md5":"1ec9a61aa2a4be4093be590af2f1a610","owner":"postgres","config":["search_path=pg_catalog, public, pg_temp"],"identity":"spec_write_scope_payload_internal_v1(uuid,uuid,jsonb,text,text)","volatility":"v","security_definer":true}]'::jsonb) loop
   select jsonb_build_object('identity',p.oid::regprocedure::text,'md5',md5(pg_get_functiondef(p.oid)),
     'owner',pg_get_userbyid(p.proowner),'acl',p.proacl::text,'security_definer',p.prosecdef,
     'volatility',p.provolatile::text,'config',to_jsonb(p.proconfig)) into actual
     from pg_proc p where p.oid=to_regprocedure('public.'||(wanted->>'identity'));
   if actual is distinct from wanted then raise exception 'Published member function mismatch: %',wanted->>'identity'; end if;
 end loop;
end $functions$;
select 1/case when (select jsonb_agg(to_jsonb(t) order by name) from (select c.relname as name,pg_get_userbyid(c.relowner) as owner,
      c.relacl::text as acl,c.relrowsecurity as rls,
      (select jsonb_agg(jsonb_build_object('name',a.attname,'type',format_type(a.atttypid,a.atttypmod),
        'not_null',a.attnotnull,'generated',a.attgenerated,'default',pg_get_expr(d.adbin,d.adrelid)) order by a.attnum)
        from pg_attribute a left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
        where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped) as columns,
      (select jsonb_agg(jsonb_build_array(conname,pg_get_constraintdef(oid)) order by conname)
        from pg_constraint where conrelid=c.oid) as constraints,
      (select jsonb_agg(jsonb_build_array(indexrelid::regclass::text,pg_get_indexdef(indexrelid)) order by indexrelid::regclass::text)
        from pg_index where indrelid=c.oid) as indexes,
      (select jsonb_agg(jsonb_build_array(policyname,roles,cmd,qual,with_check) order by policyname)
        from pg_policies where schemaname='public' and tablename=c.relname) as policies
      from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=any(array['product_spec_member_profiles','product_spec_member_profile_events','spec_member_graph_revisions'])) t)='[{"acl":"{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}","rls":true,"name":"product_spec_member_profile_events","owner":"postgres","columns":[{"name":"id","type":"uuid","default":"gen_random_uuid()","not_null":true,"generated":""},{"name":"profile_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"tenant_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"product_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"actor_id","type":"uuid","default":null,"not_null":false,"generated":""},{"name":"occurred_at","type":"timestamp with time zone","default":"now()","not_null":true,"generated":""},{"name":"before_state","type":"jsonb","default":null,"not_null":false,"generated":""},{"name":"after_state","type":"jsonb","default":null,"not_null":true,"generated":""}],"indexes":[["product_spec_member_profile_events_pkey","CREATE UNIQUE INDEX product_spec_member_profile_events_pkey ON public.product_spec_member_profile_events USING btree (id)"],["product_spec_member_profile_events_profile","CREATE INDEX product_spec_member_profile_events_profile ON public.product_spec_member_profile_events USING btree (profile_id, occurred_at, id)"]],"policies":[["product_spec_member_profile_events_tenant_read",["authenticated"],"SELECT","(tenant_id = user_tenant_id())",null]],"constraints":[["product_spec_member_profile_events_pkey","PRIMARY KEY (id)"],["product_spec_member_profile_events_product_id_fkey","FOREIGN KEY (product_id) REFERENCES products(id)"],["product_spec_member_profile_events_profile_id_fkey","FOREIGN KEY (profile_id) REFERENCES product_spec_member_profiles(id)"],["product_spec_member_profile_events_tenant_id_fkey","FOREIGN KEY (tenant_id) REFERENCES tenants(id)"]]},{"acl":"{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}","rls":true,"name":"product_spec_member_profiles","owner":"postgres","columns":[{"name":"id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"tenant_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"product_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"collection_definition_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"member_row_id","type":"text","default":null,"not_null":true,"generated":""},{"name":"member_identity","type":"jsonb","default":null,"not_null":true,"generated":""},{"name":"identity_sources","type":"jsonb","default":"''[]''::jsonb","not_null":true,"generated":""},{"name":"manufacturer_sku","type":"text","default":null,"not_null":false,"generated":""},{"name":"template_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"saved_contract_version","type":"integer","default":null,"not_null":true,"generated":""},{"name":"reference_id","type":"text","default":null,"not_null":false,"generated":""},{"name":"created_at","type":"timestamp with time zone","default":"now()","not_null":true,"generated":""},{"name":"updated_at","type":"timestamp with time zone","default":"now()","not_null":true,"generated":""},{"name":"archived_at","type":"timestamp with time zone","default":null,"not_null":false,"generated":""},{"name":"scope","type":"text","default":"(''member:''::text || (id)::text)","not_null":false,"generated":"s"},{"name":"active_template_guard","type":"boolean","default":"\nCASE\n    WHEN (archived_at IS NULL) THEN true\n    ELSE NULL::boolean\nEND","not_null":false,"generated":"s"}],"indexes":[["product_spec_member_profiles_active_row","CREATE UNIQUE INDEX product_spec_member_profiles_active_row ON public.product_spec_member_profiles USING btree (tenant_id, product_id, collection_definition_id, member_row_id) WHERE (archived_at IS NULL)"],["product_spec_member_profiles_active_template","CREATE INDEX product_spec_member_profiles_active_template ON public.product_spec_member_profiles USING btree (template_id, product_id) WHERE (archived_at IS NULL)"],["product_spec_member_profiles_pkey","CREATE UNIQUE INDEX product_spec_member_profiles_pkey ON public.product_spec_member_profiles USING btree (id)"],["product_spec_member_profiles_product","CREATE INDEX product_spec_member_profiles_product ON public.product_spec_member_profiles USING btree (product_id)"],["product_spec_member_profiles_scope","CREATE UNIQUE INDEX product_spec_member_profiles_scope ON public.product_spec_member_profiles USING btree (tenant_id, product_id, scope)"]],"policies":[["product_spec_member_profiles_tenant_read",["authenticated"],"SELECT","(tenant_id = user_tenant_id())",null]],"constraints":[["product_spec_member_profiles_collection_definition_id_fkey","FOREIGN KEY (collection_definition_id) REFERENCES spec_definitions(id)"],["product_spec_member_profiles_identity_sources_check","CHECK ((jsonb_typeof(identity_sources) = ''array''::text))"],["product_spec_member_profiles_member_identity_check","CHECK ((jsonb_typeof(member_identity) = ''object''::text))"],["product_spec_member_profiles_member_row_id_check","CHECK ((member_row_id ~ ''^[A-Za-z0-9_-]{1,80}$''::text))"],["product_spec_member_profiles_pkey","PRIMARY KEY (id)"],["product_spec_member_profiles_product_id_fkey","FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT"],["product_spec_member_profiles_reference_id_fkey","FOREIGN KEY (reference_id) REFERENCES product_spec_references(id)"],["product_spec_member_profiles_saved_contract_version_check","CHECK ((saved_contract_version > 0))"],["product_spec_member_profiles_template_id_active_template_g_fkey","FOREIGN KEY (template_id, active_template_guard) REFERENCES spec_templates(id, is_active) DEFERRABLE"],["product_spec_member_profiles_template_id_fkey","FOREIGN KEY (template_id) REFERENCES spec_templates(id)"],["product_spec_member_profiles_tenant_id_fkey","FOREIGN KEY (tenant_id) REFERENCES tenants(id)"],["spec_member_profile_constraint","TRIGGER DEFERRABLE INITIALLY DEFERRED"]]},{"acl":"{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres}","rls":true,"name":"spec_member_graph_revisions","owner":"postgres","columns":[{"name":"template_id","type":"uuid","default":null,"not_null":true,"generated":""},{"name":"revision","type":"bigint","default":"0","not_null":true,"generated":""},{"name":"last_xid","type":"bigint","default":null,"not_null":true,"generated":""}],"indexes":[["spec_member_graph_revisions_pkey","CREATE UNIQUE INDEX spec_member_graph_revisions_pkey ON public.spec_member_graph_revisions USING btree (template_id)"]],"policies":null,"constraints":[["spec_member_graph_revisions_pkey","PRIMARY KEY (template_id)"],["spec_member_graph_revisions_template_id_fkey","FOREIGN KEY (template_id) REFERENCES spec_templates(id) ON DELETE CASCADE"]]}]'::jsonb then 1 else 0 end as exact_member_tables;
select 1/case when (select jsonb_agg(to_jsonb(t) order by table_name,name) from (select c.relname as table_name,t.tgname as name,t.tgenabled::text as enabled,
      pg_get_triggerdef(t.oid) as definition
      from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and not t.tgisinternal and (c.relname,t.tgname) in (('category_tech_mappings','spec_member_category_constraint'),('spec_definitions','spec_member_definition_metadata_constraint'),('product_spec_member_profile_events','spec_member_event_immutable'),('spec_facts','spec_member_fact_guard'),('spec_fact_readings','spec_member_fact_readings_guard'),('spec_fact_values','spec_member_fact_values_guard'),('spec_template_fields','spec_member_field_metadata_constraint'),('product_spec_member_profiles','spec_member_profile_constraint'),('product_spec_member_profiles','spec_member_profile_guard'),('product_spec_member_profiles','spec_member_profile_revision'),('spec_fact_readings','spec_member_reading_revision'),('spec_templates','spec_member_template_metadata_constraint'))) t)='[{"name":"spec_member_category_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_category_constraint AFTER INSERT OR DELETE OR UPDATE ON public.category_tech_mappings DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_category_constraint_internal_v1()","table_name":"category_tech_mappings"},{"name":"spec_member_event_immutable","enabled":"O","definition":"CREATE TRIGGER spec_member_event_immutable BEFORE DELETE OR UPDATE ON public.product_spec_member_profile_events FOR EACH ROW EXECUTE FUNCTION spec_member_event_immutable_internal_v1()","table_name":"product_spec_member_profile_events"},{"name":"spec_member_profile_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_profile_constraint AFTER INSERT OR UPDATE ON public.product_spec_member_profiles DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_profile_constraint_internal_v1()","table_name":"product_spec_member_profiles"},{"name":"spec_member_profile_guard","enabled":"O","definition":"CREATE TRIGGER spec_member_profile_guard BEFORE INSERT OR DELETE OR UPDATE ON public.product_spec_member_profiles FOR EACH ROW EXECUTE FUNCTION spec_member_profile_guard_internal_v1()","table_name":"product_spec_member_profiles"},{"name":"spec_member_profile_revision","enabled":"O","definition":"CREATE TRIGGER spec_member_profile_revision AFTER INSERT OR UPDATE ON public.product_spec_member_profiles FOR EACH ROW EXECUTE FUNCTION spec_member_profile_revision_internal_v1()","table_name":"product_spec_member_profiles"},{"name":"spec_member_definition_metadata_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_definition_metadata_constraint AFTER UPDATE ON public.spec_definitions DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_metadata_constraint_internal_v1()","table_name":"spec_definitions"},{"name":"spec_member_fact_readings_guard","enabled":"O","definition":"CREATE TRIGGER spec_member_fact_readings_guard BEFORE INSERT OR DELETE OR UPDATE ON public.spec_fact_readings FOR EACH ROW EXECUTE FUNCTION spec_member_fact_guard_internal_v1()","table_name":"spec_fact_readings"},{"name":"spec_member_reading_revision","enabled":"O","definition":"CREATE TRIGGER spec_member_reading_revision AFTER INSERT OR DELETE OR UPDATE ON public.spec_fact_readings FOR EACH ROW EXECUTE FUNCTION spec_member_reading_revision_internal_v1()","table_name":"spec_fact_readings"},{"name":"spec_member_fact_values_guard","enabled":"O","definition":"CREATE TRIGGER spec_member_fact_values_guard BEFORE INSERT OR DELETE OR UPDATE ON public.spec_fact_values FOR EACH ROW EXECUTE FUNCTION spec_member_fact_guard_internal_v1()","table_name":"spec_fact_values"},{"name":"spec_member_fact_guard","enabled":"O","definition":"CREATE TRIGGER spec_member_fact_guard BEFORE INSERT OR DELETE OR UPDATE ON public.spec_facts FOR EACH ROW EXECUTE FUNCTION spec_member_fact_guard_internal_v1()","table_name":"spec_facts"},{"name":"spec_member_field_metadata_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_field_metadata_constraint AFTER INSERT OR DELETE OR UPDATE ON public.spec_template_fields DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_metadata_constraint_internal_v1()","table_name":"spec_template_fields"},{"name":"spec_member_template_metadata_constraint","enabled":"O","definition":"CREATE CONSTRAINT TRIGGER spec_member_template_metadata_constraint AFTER INSERT OR UPDATE ON public.spec_templates DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION spec_member_metadata_constraint_internal_v1()","table_name":"spec_templates"}]'::jsonb then 1 else 0 end as exact_member_triggers;
select 1/case when (select value from member_data_before)=(select value from (select jsonb_build_object('category_tech_mappings',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.category_tech_mappings x),'product_spec_references',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.product_spec_references x),'product_spec_save_receipts',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.product_spec_save_receipts x),'products',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.products x),'spec_definitions',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_definitions x),'spec_facts',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_facts x),'spec_fact_values',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_fact_values x),'spec_fact_readings',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_fact_readings x),'spec_template_fields',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_template_fields x),'spec_templates',(select md5(coalesce(jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text),'[]')::text) from public.spec_templates x)) as value) now) then 1 else 0 end as original_rows_unchanged;
notify pgrst,'reload schema';
commit;
