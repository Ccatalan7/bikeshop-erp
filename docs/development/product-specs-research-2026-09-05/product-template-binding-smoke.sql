-- Guarded READ ONLY production smoke. An existing tenant principal supplies
-- function context; this is not proof of an authenticated PostgREST session.
-- No writer, assignment, receipt or product mutation is invoked here.
select set_config('request.jwt.claim.sub',(
 select u.user_id::text from public.user_profiles u join public.tenants t on t.id=u.tenant_id
 where t.subdomain='vinabike' and u.is_active and u.role='admin' order by u.user_id limit 1
),true) is not null as principal_context_available;
select set_config('request.jwt.claims',jsonb_build_object(
 'sub',current_setting('request.jwt.claim.sub'),'role','authenticated')::text,true) is not null as read_context_set;
select 1/case when public.user_tenant_id()=(select id from public.tenants where subdomain='vinabike')
 then 1 else 0 end tenant_context_assertion;

with products as materialized (
 select p.id,p.category_id,b.template_id from public.products p
 join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
 where p.tenant_id=public.user_tenant_id() and p.product_type='product'
), checked as materialized (
 select id,template_id,public.get_product_spec_snapshot_v1(id) snapshot,
 public.get_product_spec_editor_context_v1(id,category_id) editor from products
)
select count(*) physical_products_read,
 count(*) filter(where template_id is null) without_template,
 1/case when count(*)=1605 and bool_and(jsonb_typeof(snapshot->'values')='object'
   and jsonb_typeof(editor->'unassigned_facts')='array'
   and (editor->>'template_id')::uuid is not distinct from template_id)
 then 1 else 0 end every_editor_context_assertion from checked;

with ids as (select array_agg(p.id) ids from public.products p where p.tenant_id=public.user_tenant_id()),
 payload as materialized (select public.get_product_spec_contexts_v1(ids) contexts,
 public.get_product_spec_bindings_v1(ids) bindings from ids)
select 1/case when (select count(*) from jsonb_each(contexts))=1664
 and (select count(*) from jsonb_each(bindings))=1664
 and not exists(select 1 from jsonb_each(contexts) e where jsonb_typeof(e.value->'__spec_issues')<>'array')
 then 1 else 0 end all_product_contexts_assertion from payload;

select 1/case when cardinality(public.get_product_ids_for_spec_family_v1('chain'))>0
 and public.spec_template_resolution_internal_v1(public.user_tenant_id(),null,null) is null
 then 1 else 0 end resolver_and_family_reader_assertion;

with responses(kind,payload) as materialized (
 values
 ('search_v4',public.assistant_search_inventory_v4('KMC',null,'any','[]')),
 ('search_v5',public.assistant_search_inventory_v5('KMC',null,'any','[]')),
 ('search_v6',public.assistant_search_inventory_v6('KMC',null,'any','[]','[]','name','asc',5,'all_matches')),
 ('search_v7',public.assistant_search_inventory_v7('KMC',null,'any','[]','[]','name','asc',5,'all_matches')),
 ('schema_v1',public.assistant_inspect_inventory_schema_v1('cadenas',null)),
 ('schema_v3',public.assistant_inspect_inventory_schema_v3('cadenas',null))
)
select kind,jsonb_array_length(payload->'items') returned_items,
 1/case when jsonb_typeof(payload)='object' and jsonb_array_length(payload->'items')>0 then 1 else 0 end executable_reader_assertion
 from responses;

with product as (
 select p.id,p.name from public.products p join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
 where p.tenant_id=public.user_tenant_id() and b.technical_family='chain' order by p.id limit 1
)
select 1/case when
 public.assistant_inventory_technical_predicate_source_internal_v1(public.user_tenant_id(),id,'tire_etrto','equals','["37-622"]',name,name)='unresolved'
 and public.assistant_inventory_technical_filter_source_internal_v1(public.user_tenant_id(),id,'tire_etrto','37-622',name,name)='unresolved'
 and jsonb_typeof(public.assistant_infer_technical_predicates_internal_v1(public.user_tenant_id(),'cadena 8 velocidades')->'predicates')='array'
 then 1 else 0 end technical_predicate_scope_assertion from product;

with needs as (select id from public.supply_needs where tenant_id=public.user_tenant_id() order by id limit 3),
 responses as materialized (select id,
 public.supply_need_eligible_products_internal_v1(public.user_tenant_id(),id,400) eligible,
 public.supply_need_stock_candidates_v1(id,8) stock from needs)
select count(*) needs_exercised,
 1/case when count(*)>0 and bool_and(jsonb_typeof(eligible)='object' and jsonb_typeof(stock)='object')
 then 1 else 0 end purchasing_readers_assertion from responses;

with visible as materialized (
 select p.id from public.products p where p.tenant_id=public.user_tenant_id()
 and p.is_active and p.is_published and p.show_on_website
), rendered as materialized (
 select p.id,s.spec_key,s.display_value from visible p
 cross join lateral public.get_public_product_technical_specs(public.user_tenant_id(),p.id) s
)
select count(*) public_fields_rendered,
 1/case when count(*)>0 and bool_and(public.spec_product_field_is_active_internal_v1(public.user_tenant_id(),id,spec_key)
 and display_value is not null) then 1 else 0 end public_store_scope_assertion from rendered;
