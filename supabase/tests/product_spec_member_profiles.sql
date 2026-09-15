-- Synthetic scoped-member graph regression; no OEM/product population.
begin;
\ir fixtures/product_spec_reading_receipt_contract.sql
-- Review candidates remain local to this transaction until forward publication.
\ir ../../scripts/inventory/sql/product_spec_strict_row_order_candidate.sql
\ir ../../scripts/inventory/sql/product_spec_member_profiles_candidate.sql
\ir ../../scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql
select no_plan();
\ir fixtures/product_spec_member_graph.sql
set local role authenticated;
select ok(not has_table_privilege('authenticated','public.product_spec_member_profiles','insert'),'profile headers require the aggregate command');
select ok(not has_function_privilege('authenticated','public.spec_write_scope_payload_internal_v1(uuid,uuid,jsonb,text,text)','execute'),'scoped writer remains private');
select ok(not has_function_privilege('anon','public.get_product_spec_member_profiles_v1(uuid)','execute'),'anonymous cannot read member observations');
select is(public.get_product_spec_editor_context_v3(null,'99e10000-0000-4000-8000-000000000010')->'member_profiles',
 '{"read_schema_version":1,"product_id":null,"revision":0,"product_updated_at":null,"profiles":[],"archived_profiles":[]}'::jsonb,
 'new product uses the same empty profile envelope as a persisted product');
select is(public.get_product_spec_member_template_v1('99e10000-0000-4000-8000-000000000050',
 '99e10000-0000-4000-8000-000000000051','member_part_test')->>'technical_family','complete_brake',
 'new draft member loads the existing family template without an inventory product');
select throws_ok($$select public.get_product_spec_member_template_v1('99e10000-0000-4000-8000-000000000050',
 '99e10000-0000-4000-8000-000000000054','member_part_test')$$,'23514',null,'draft template loader cannot use a child collection');
select throws_ok($$select public.get_product_spec_member_template_v1('99e10000-0000-4000-8000-000000000050',
 '99e10000-0000-4000-8000-000000000051','member_other_test')$$,'23514',null,'unknown family cannot receive a generic fallback template');
select lives_ok($$select pg_temp.member_save('two-members',jsonb_build_array(pg_temp.member_profile('r1'),pg_temp.member_profile('r2','9007199254740993.2')))$$,
 'two equal-family members save independent exact measurements');
select is(pg_temp.member_save('two-members',jsonb_build_array(pg_temp.member_profile('r1'),pg_temp.member_profile('r2','9007199254740993.2')))->'editor_context',
 public.get_product_spec_editor_context_v3('99e10000-0000-4000-8000-000000000020','99e10000-0000-4000-8000-000000000010'),
 'v2 receipt retains the complete confirmed editor context for reconstructing drafts');
select is(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')#>>'{profiles,1,values,member_test_length}',
 '9007199254740993.2','member decimal is transported as exact text');
select is(public.get_product_spec_editor_context_v3('99e10000-0000-4000-8000-000000000020',null)->'revision',
 public.get_product_spec_editor_context_v3('99e10000-0000-4000-8000-000000000020',null)#>'{member_profiles,revision}',
 'root and member contexts share the parent revision');
select is(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')#>>
 '{profiles,1,fact_payload,99e10000-0000-4000-8000-000000000052,number}','9007199254740993.2',
 'normalized member payload also preserves exact digits for research');
select ok((pg_temp.member_save('two-members',jsonb_build_array(pg_temp.member_profile('r1'),pg_temp.member_profile('r2','9007199254740993.2')))->>'replayed')::boolean,
 'same whole-graph command replays');
select throws_ok($$select pg_temp.member_save('two-members',jsonb_build_array(pg_temp.member_profile('r1','8')))$$,'23505',null,
 'a changed member is part of the idempotency hash');
select throws_ok($$select pg_temp.member_save('v1-collision',p_v1=>true); select pg_temp.member_save('v1-collision')$$,'23505',null,
 'v1 and v2 cannot collide on the same operation key');
select throws_ok($$select pg_temp.member_save('stale',p_revision=>-1)$$,'40001',null,'stale revision rejects the entire graph');
select lives_ok($$select pg_temp.member_save('old-client',p_v1=>true,p_patch=>'{"price":120}')$$,
 'old client preserves member profiles when their rows are unchanged');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')->'profiles'),2,
 'omitted profiles are not erased');
select throws_ok($$select pg_temp.member_save('orphan',p_root=>'{}',p_v1=>true,p_patch=>'{"name":"must roll back"}')$$,'23514',null,
 'old client cannot orphan a profile');
select is((select name from public.products where id='99e10000-0000-4000-8000-000000000020'),'Profile kit','orphan rejection rolls back commercial edits');
select throws_ok($$select pg_temp.member_save('wrong-row',jsonb_build_array(pg_temp.member_profile('missing')))$$,'23514',null,
 'a profile must target an actual root collection row');
select throws_ok($$select pg_temp.member_save('changed-identity',p_root=>jsonb_set((select value from member_root_values),
 '{99e10000-0000-4000-8000-000000000051,rows,rows,0,values,identity_brand}','"Different"'))$$,'23514',null,
 'same row id cannot reinterpret observations as another brand');
select throws_ok($$select pg_temp.member_save('wrong-version',jsonb_build_array(pg_temp.member_profile('r1','7.1','{"contract_version":-1}')))$$,'40001',null,
 'member template revision is guarded');
select throws_ok($$select pg_temp.member_save('wrong-shape',jsonb_build_array(pg_temp.member_profile('r1','-1')),p_patch=>'{"price":999}')$$,'23514',null,
 'family measurement rules execute within the member');
select is((select price::text from public.products where id='99e10000-0000-4000-8000-000000000020'),'120.00','bad member rolls back parent price');
select throws_ok($$select pg_temp.member_save('intrinsic-prerequisite',jsonb_build_array(pg_temp.member_profile('r1','7.1',
 '{"values":{"99e10000-0000-4000-8000-000000000052":{"number":"7.1"},"99e10000-0000-4000-8000-000000000053":{"boolean":false}}}')))$$,'23514',null,
 'intrinsic contents participate in the unchanged family prerequisite');
select lives_ok($$select pg_temp.member_save('intrinsic-rows',jsonb_build_array(pg_temp.member_profile('r1','7.1',
 '{"values":{"99e10000-0000-4000-8000-000000000054":{"rows":{"schema_version":2,"rows":[{"id":"intrinsic-a","values":{"inner":"10","outer":"20"},"sources":[]}]}}}}')))$$,
 'intrinsic row tables are retained inside a member profile');
select throws_ok($$select pg_temp.member_save('intrinsic-invalid',jsonb_build_array(pg_temp.member_profile('r1','7.1',
 '{"values":{"99e10000-0000-4000-8000-000000000054":{"rows":{"schema_version":2,"rows":[{"id":"intrinsic-a","values":{"inner":"20","outer":"10"},"sources":[]}]}}}}')))$$,'23514',null,
 'strict row order is shared with member profiles');
select lives_ok($$select pg_temp.member_save('exact-reference',jsonb_build_array(pg_temp.member_profile('r1','7.1','{"reference_id":"member-test-reference","values":{}}')))$$,
 'reference resolves through technical family, not the template key');
select throws_ok($$select pg_temp.member_save('reference-conflict',jsonb_build_array(pg_temp.member_profile('r1','8','{"reference_id":"member-test-reference"}')))$$,'23514',null,
 'member reference conflict rejects the aggregate');
select throws_ok($$select pg_temp.member_save('reference-wrong-member',jsonb_build_array(pg_temp.member_profile('r2','7.1','{"reference_id":"member-test-reference","values":{}}')))$$,'23514',null,
 'the other member cannot borrow the first member reference');
select throws_ok($$select pg_temp.member_save('identify-without-source',
 jsonb_build_array(pg_temp.member_profile('r2','9007199254740993.2','{"binding_action":"identify"}')),
 p_root=>jsonb_set(jsonb_set((select value from member_root_values),
 '{99e10000-0000-4000-8000-000000000051,rows,rows,1,values,identity_model}','"Model B"'),
 '{99e10000-0000-4000-8000-000000000051,rows,rows,1,sources}','[]'))$$,'23514',null,
 'identifying an unknown member requires its source');
select lives_ok($$select pg_temp.member_save('identify',
 jsonb_build_array(pg_temp.member_profile('r2','9007199254740993.2','{"binding_action":"identify"}')),
 p_root=>jsonb_set((select value from member_root_values),
 '{99e10000-0000-4000-8000-000000000051,rows,rows,1,values,identity_model}','"Model B"'))$$,
 'evidence-backed identification preserves the existing profile');
reset role;
update member_root_values set value=jsonb_set(value,'{99e10000-0000-4000-8000-000000000051,rows,rows,1,values,identity_model}','"Model B"');
set local role authenticated;
select is((select count(*)::integer from public.product_spec_member_profiles),2,'identification does not split the physical piece into two profiles');
select throws_ok($$select pg_temp.member_save('unconfirmed-rebind',
 jsonb_build_array(pg_temp.member_profile('r3','9007199254740993.2')),
 p_root=>jsonb_set((select value from member_root_values),
 '{99e10000-0000-4000-8000-000000000051,rows,rows,1,id}','"r3"'))$$,'23514',null,
 'regenerated row ids never rebind automatically');
select lives_ok($$select pg_temp.member_save('explicit-rebind',
 jsonb_build_array(pg_temp.member_profile('r3','9007199254740993.2','{"binding_action":"rebind"}')),
 p_root=>jsonb_set((select value from member_root_values),
 '{99e10000-0000-4000-8000-000000000051,rows,rows,1,id}','"r3"'))$$,
 'explicitly selected identical row restores the binding without moving facts');
select ok(exists(select 1 from public.product_spec_member_profile_events
 where profile_id='99e10000-0000-4000-8000-000000000082' and before_state->>'member_row_id'='r2'
 and after_state->>'member_row_id'='r3' and actor_id='99e10000-0000-4000-8000-000000000091'),
 'rebind preserves the old row and actor in the profile history');
reset role;
update member_root_values set value=jsonb_set(value,'{99e10000-0000-4000-8000-000000000051,rows,rows,1,id}','"r3"');
select throws_ok($$delete from public.product_spec_member_profile_events
 where profile_id='99e10000-0000-4000-8000-000000000082'$$,'23514',null,'profile history is append-only');
select throws_ok($$update public.product_spec_member_profile_events set actor_id=null
 where profile_id='99e10000-0000-4000-8000-000000000081'$$,'23514',null,'profile history retains its original actor');
savepoint member_category_binding;
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99e10000-0000-4000-8000-000000000012','99e10000-0000-4000-8000-000000000001','Spec kits','Spec kits');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status) values
 ('99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000012','drivetrain_kit',
 '99e10000-0000-4000-8000-000000000050','active');
update public.products set category_id='99e10000-0000-4000-8000-000000000012',spec_template_id=null
 where id='99e10000-0000-4000-8000-000000000020';
set constraints all immediate;
set local role authenticated;
select is(public.get_product_spec_editor_context_v3('99e10000-0000-4000-8000-000000000020',
 '99e10000-0000-4000-8000-000000000010')#>>'{member_parent_context,template_id}',
 '99e10000-0000-4000-8000-000000000050','category preview retains the persisted collection owner');
select is(public.get_product_spec_editor_context_v3('99e10000-0000-4000-8000-000000000020',
 '99e10000-0000-4000-8000-000000000010')->>'template_key','chain',
 'category preview still returns the requested draft root');
select throws_ok($$update public.category_tech_mappings set status='pending'
 where category_id='99e10000-0000-4000-8000-000000000012'$$,'23514',null,
 'category unassignment cannot orphan active member profiles');
select throws_ok($$delete from public.category_tech_mappings
 where category_id='99e10000-0000-4000-8000-000000000012'$$,'23514',null,
 'category mapping deletion cannot orphan active member profiles');
select throws_ok($$update public.category_tech_mappings set template_id='99e10000-0000-4000-8000-000000000060'
 where category_id='99e10000-0000-4000-8000-000000000012'$$,'23514',null,
 'category reassignment cannot remove the collection owner');
reset role;
rollback to savepoint member_category_binding;
set local role authenticated;
select ok(not(public.get_product_spec_contexts_v1(array['99e10000-0000-4000-8000-000000000020'::uuid])->'99e10000-0000-4000-8000-000000000020' ? 'member_test_length'),
 'compatibility reader never flattens member facts into the kit');
select is((select count(*)::integer from public.get_public_product_technical_specs('99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000020')
 where spec_key='member_test_length'),0,'public store never publishes a member measurement as a kit measurement');
reset role;
create function pg_temp.member_bad_metadata(p_change text) returns void language plpgsql as $$
begin
 if p_change='disable' then
   update public.spec_templates set form_contract=form_contract-'member_profiles' where id='99e10000-0000-4000-8000-000000000050';
 elsif p_change='family' then
   update public.spec_templates set key='member_other_test' where id='99e10000-0000-4000-8000-000000000060';
 elsif p_change='identity' then
   update public.spec_templates set form_contract=jsonb_set(form_contract,
     '{member_profiles,collections,0,identity_columns}','["member_role","position","identity_brand"]')
     where id='99e10000-0000-4000-8000-000000000050';
 else
   update public.spec_templates set form_contract=jsonb_set(form_contract,'{member_profiles,version}','999')
     where id='99e10000-0000-4000-8000-000000000050';
 end if;
 set constraints all immediate;
end $$;
select throws_ok($$select pg_temp.member_bad_metadata('disable')$$,'23514',null,'metadata cannot orphan active profiles by disabling their collection');
select throws_ok($$select pg_temp.member_bad_metadata('family')$$,'23514',null,'template key changes cannot reinterpret an active member family');
select throws_ok($$select pg_temp.member_bad_metadata('version')$$,'23514',null,'unsupported member contract version fails at the metadata boundary');
select is((select count(*)::integer from public.product_spec_values where product_id='99e10000-0000-4000-8000-000000000020'
 and spec_definition_id='99e10000-0000-4000-8000-000000000052'),0,'legacy mirror excludes scoped measurements');
select throws_ok($$insert into public.spec_facts(tenant_id,subject_type,subject_id,subject_scope,spec_definition_id,value_number)
 values('99e10000-0000-4000-8000-000000000001','product','99e10000-0000-4000-8000-000000000020','kit_members:r1/kit_members:r2',
 '99e10000-0000-4000-8000-000000000052',5)$$,'23514',null,'nested or unowned scopes are rejected');
select throws_ok($$update public.product_spec_member_profiles set member_row_id='r2' where id='99e10000-0000-4000-8000-000000000081'$$,'23514',null,
 'profile binding cannot silently move to another row');
-- Defensive receipt coverage: a future member reading path must preserve the
-- real name_reading provenance. The aggregate editor itself writes mechanic.
update public.spec_facts set source='name_reading' where subject_id='99e10000-0000-4000-8000-000000000020'
 and subject_scope='member:99e10000-0000-4000-8000-000000000082' and spec_definition_id='99e10000-0000-4000-8000-000000000052';
create temp table member_revision_before_reading as select spec_revision from public.products
 where id='99e10000-0000-4000-8000-000000000020';
insert into public.spec_fact_readings(fact_id,tenant_id,source_text,source_digest,quote,model,definition_id,vocabulary_digest)
 select f.id,f.tenant_id,'Synthetic exact component measurement','synthetic-member-digest','9007199254740993.2','fixture',
 f.spec_definition_id,'synthetic-vocabulary-digest'
 from public.spec_facts f where f.subject_id='99e10000-0000-4000-8000-000000000020'
 and f.subject_scope='member:99e10000-0000-4000-8000-000000000082' and f.spec_definition_id='99e10000-0000-4000-8000-000000000052';
select ok((select spec_revision from public.products where id='99e10000-0000-4000-8000-000000000020')>
 (select spec_revision from member_revision_before_reading),'new member evidence invalidates an older editor revision');
select throws_ok($$update public.spec_fact_readings set fact_id=(select id from public.spec_facts
 where subject_id='99e10000-0000-4000-8000-000000000020' and subject_scope='member:99e10000-0000-4000-8000-000000000081'
 and spec_definition_id='99e10000-0000-4000-8000-000000000052') where source_digest='synthetic-member-digest'$$,'23514',null,
 'measurement evidence cannot move between included pieces');
create temp table preserved_member_facts as select to_jsonb(f) fact from public.spec_facts f
 where f.subject_id='99e10000-0000-4000-8000-000000000020' and f.subject_scope is not null;
create temp table preserved_member_readings as select to_jsonb(r) reading from public.spec_fact_readings r
 where r.tenant_id='99e10000-0000-4000-8000-000000000001';
set local role authenticated;
select lives_ok($$select pg_temp.member_save('archive',p_archive=>'["99e10000-0000-4000-8000-000000000081","99e10000-0000-4000-8000-000000000082"]',p_root=>'{}')$$,
 'explicit archive permits removing members without deleting their facts');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')->'profiles'),0,
 'archived profiles are excluded from active reads');
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')->'archived_profiles'),2,
 'archived profiles remain accessible as history');
select is(jsonb_array_length(public.get_product_spec_research_snapshot_v2('99e10000-0000-4000-8000-000000000020')#>
 '{member_profiles,archived_profiles}'),2,'research backup includes archived bindings beside their observations');
select ok(public.get_product_spec_research_snapshot_v2('99e10000-0000-4000-8000-000000000020')->'fingerprints' ?&
 array['member_profiles_sha256','member_events_sha256'],'backup fingerprint covers profile identity and event history');
reset role;
select throws_ok($$select pg_temp.member_bad_metadata('identity')$$,'23514',null,
 'member identity declares both canonical OEM keys even without active profiles');
select is((select jsonb_agg(to_jsonb(f) order by f.id) from public.spec_facts f
 where f.subject_id='99e10000-0000-4000-8000-000000000020' and f.subject_scope is not null),
 (select jsonb_agg(fact order by fact->>'id') from preserved_member_facts),'archival preserves facts, identities and provenance byte-for-byte');
select is((select jsonb_agg(to_jsonb(r) order by r.fact_id) from public.spec_fact_readings r
 where r.tenant_id='99e10000-0000-4000-8000-000000000001'),
 (select jsonb_agg(reading order by reading->>'fact_id') from preserved_member_readings),'archival also preserves the original readings');
select throws_ok($$delete from public.spec_fact_readings where source_digest='synthetic-member-digest'$$,'23514',null,
 'archived evidence cannot be deleted');
select throws_ok($$update public.spec_facts set value_number=99 where subject_id='99e10000-0000-4000-8000-000000000020'
 and subject_scope='member:99e10000-0000-4000-8000-000000000081' and value_number is not null$$,'23514',null,
 'archived observations are immutable');
select throws_ok($$delete from public.product_spec_member_profiles where id='99e10000-0000-4000-8000-000000000081'$$,'23514',null,
 'archive is not a destructive delete');
select set_config('request.jwt.claim.sub','99e10000-0000-4000-8000-000000000092',true);
select set_config('request.jwt.claims','{"sub":"99e10000-0000-4000-8000-000000000092","role":"authenticated"}',true);
set local role authenticated;
select is((select count(*)::integer from public.product_spec_member_profiles),0,'RLS hides other tenants profiles');
select throws_ok($$select public.get_product_spec_member_profiles_v1('99e10000-0000-4000-8000-000000000020')$$,'42501',null,'reader rejects foreign product');
reset role;
select set_config('request.jwt.claim.sub','99e10000-0000-4000-8000-000000000091',true);
select set_config('request.jwt.claims','{"sub":"99e10000-0000-4000-8000-000000000091","role":"authenticated"}',true);
set constraints all immediate;
select pass('deferred constraints accept the final archived graph');
select * from finish();
rollback;
