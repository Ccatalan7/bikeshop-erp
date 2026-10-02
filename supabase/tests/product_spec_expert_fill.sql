-- A sheet is completed with expert judgment (20261002150000): any current
-- field, no quote and no URL, origin `research` with a batch receipt. It never
-- overwrites what someone else wrote, the sheet's rules still judge the value,
-- and a batch can be undone without touching what was corrected afterwards.
begin;
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values ('99c60000-0000-4000-8000-000000000001','Expert fill');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at) values
 ('99c60000-0000-4000-8000-000000000091','authenticated','authenticated','expert-fill@example.invalid','',now(),'{}',
  jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99c60000-0000-4000-8000-000000000001'),now(),now()),
 ('99c60000-0000-4000-8000-000000000092','authenticated','authenticated','expert-fill-customer@example.invalid','',now(),'{}',
  jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99c60000-0000-4000-8000-000000000001'),now(),now());
delete from public.user_profiles where user_id in ('99c60000-0000-4000-8000-000000000091','99c60000-0000-4000-8000-000000000092');
insert into public.user_profiles(user_id,tenant_id,role) values ('99c60000-0000-4000-8000-000000000091','99c60000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"99c60000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99c60000-0000-4000-8000-000000000091',true);
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99c60000-0000-4000-8000-000000000010','99c60000-0000-4000-8000-000000000001','Cadenas','Cadenas');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status)
select '99c60000-0000-4000-8000-000000000001','99c60000-0000-4000-8000-000000000010','chain',id,'active'
from public.spec_templates where key='chain' and tenant_id is null;

create function pg_temp.def(p_key text) returns uuid language sql as $$
 select id from public.spec_definitions where key=p_key and tenant_id is null $$;
create function pg_temp.fill(p_key text, p_value jsonb, p_batch text default 'tanda-1') returns jsonb language sql as $$
 select public.record_product_spec_expert_value_v1('99c60000-0000-4000-8000-000000000020',p_key,p_value,p_batch,
   'Cadena KMC de 8 velocidades','claude-opus-5-5') $$;
create function pg_temp.fact(p_key text) returns public.spec_facts language sql as $$
 select f.* from public.spec_facts f where f.subject_id='99c60000-0000-4000-8000-000000000020'
   and f.spec_definition_id=pg_temp.def(p_key) and f.subject_scope is null $$;
create function pg_temp.sheet(p_key text) returns text language sql as $$
 select display_value from public.get_public_product_technical_specs('99c60000-0000-4000-8000-000000000001',
   '99c60000-0000-4000-8000-000000000020') where spec_key=p_key $$;

select lives_ok($$select public.save_product_with_specs_v1(
  '{"id":"99c60000-0000-4000-8000-000000000020","name":"Cadena KMC Z8.3 116L","sku":"FILL-Z83","brand":"KMC","model":"Z8.3","price":9990,"cost":4000,"category_id":"99c60000-0000-4000-8000-000000000010","is_published":true,"show_on_website":true}'::jsonb,
  true,(select id from public.spec_templates where key='chain' and tenant_id is null),
  (select contract_version from public.spec_templates where key='chain' and tenant_id is null),
  jsonb_build_object(pg_temp.def('quick_link_included'),jsonb_build_object('boolean',true)),
  null,null,'expert-fill-create',null,null)$$,'a published chain with one datum written by hand');

-- Empty fields fill, in the field's own shape, without quote or URL.
select is(pg_temp.fill('link_count','116')->>'verdict','recorded','a number fills an empty field');
select is(pg_temp.fill('chain_speeds','["8"]')->>'verdict','recorded','a multiple choice fills by its labels');
select is(pg_temp.fill('drivetrain_mode','"derailleur"')->>'verdict','recorded','an option matches its label without case');
select is(pg_temp.fill('chain_directional','false')->>'verdict','recorded','a boolean fills');
select is((pg_temp.fact('link_count')).source,'research','the origin is catalog research');
select is((select batch||'/'||model||'/'||reason from public.spec_fact_expert_fills where fact_id=(pg_temp.fact('link_count')).id),
  'tanda-1/claude-opus-5-5/Cadena KMC de 8 velocidades','the receipt keeps batch, model and reason');
select is(pg_temp.sheet('link_count'),'116','the storefront shows it');
select is(pg_temp.sheet('chain_speeds'),'8','the storefront shows the option');

-- What someone else wrote stays; the sheet's rules still judge.
select is(pg_temp.fill('quick_link_included','false')->>'verdict','kept_existing','a datum written by hand is never overwritten');
select is((pg_temp.fact('quick_link_included')).value_boolean,true,'and keeps its value');
select is(pg_temp.fill('chain_width_family','"5/32"')->>'verdict','rejected','an option outside the list is rejected');
select is(pg_temp.fill('chain_outer_width_mm','-3')->>'verdict','rejected','a value the rules reject is not written');
select ok((pg_temp.fact('chain_outer_width_mm')).id is null,'and leaves no fact behind');
select is(pg_temp.fill('drivetrain_primary_ecosystem','"Ecosistema Shimano"')->>'verdict','rejected','a retired field is not filled');
select is(pg_temp.fill('no_such_field','1')->>'verdict','rejected','a field outside the sheet is rejected');

-- A deduction is replaced; an earlier batch is corrected while untouched.
update public.spec_facts set source='inferred' where id=(pg_temp.fact('chain_directional')).id;
delete from public.spec_fact_expert_fills where fact_id=(pg_temp.fact('chain_directional')).id;
select is(pg_temp.fill('chain_directional','true')->>'replaced','inferred','a deduction gives way to expert judgment');
select is(pg_temp.fill('link_count','114','tanda-2')->>'verdict','recorded','an untouched earlier fill can be corrected');
select is((pg_temp.fact('link_count')).value_number,114::numeric,'with the new value');
-- A correction keeps the batch's origin and lands in the same transaction
-- (same now()): only the value tells it apart.
update public.spec_fact_values set value_id=(select id from public.spec_definition_values
  where spec_definition_id=pg_temp.def('chain_speeds') and label='9' and tenant_id is null)
 where fact_id=(pg_temp.fact('chain_speeds')).id;
select is(pg_temp.fill('chain_speeds','["10"]')->>'verdict','kept_existing','a fill someone corrected afterwards is kept');
select is((select v.label from public.spec_fact_values x join public.spec_definition_values v on v.id=x.value_id
  where x.fact_id=(pg_temp.fact('chain_speeds')).id),'9','with the correction');
-- A deduction someone confirmed is no longer a guess.
insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_number,source,confirmed)
values ('99c60000-0000-4000-8000-000000000001','product','99c60000-0000-4000-8000-000000000020',
  pg_temp.def('chain_outer_width_mm'),7.1,'inferred',true);
select is(pg_temp.fill('chain_outer_width_mm','7.3')->>'verdict','kept_existing','a confirmed deduction is kept');
select is((pg_temp.fact('chain_outer_width_mm')).value_number,7.1::numeric,'with its value');

-- A row needs no document: the source columns are optional and stay so.
select throws_ok($$insert into public.spec_definitions(key,label,data_type,validation_rules) values ('expert_fill_doc_rows','Filas','json',
  '{"rows_schema":{"version":1,"columns":[{"key":"value","label":"Valor","type":"text","required":true},{"key":"source_document","label":"Documento","type":"text","required":true}]}}')$$,
  '23514',null,'a rows table cannot require a source document');
insert into public.spec_definitions(id,key,label,data_type,validation_rules,is_customer_visible,store_label,store_view) values
 ('99c60000-0000-4000-8000-000000000055','expert_fill_pressures','Presiones','json',
  '{"rows_schema":{"version":1,"columns":[{"key":"max_pressure_value","label":"Presión","type":"decimal","required":true},{"key":"pressure_unit","label":"Unidad","type":"token","required":true,"allowed_values":["psi","bar"]},{"key":"source_document","label":"Documento","type":"text"}]}}',
  true,'Presión máxima','{"format":"{max_pressure_value} {pressure_unit}","join":" o "}');
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order)
select id,'99c60000-0000-4000-8000-000000000055','measurement',99 from public.spec_templates where key='chain' and tenant_id is null;
select is(pg_temp.fill('expert_fill_pressures','{"schema_version":1,"rows":[{"id":"a","values":{"max_pressure_value":"120","pressure_unit":"psi"},"sources":[]}]}')->>'verdict',
  'recorded','a row is written without a document');
select is(pg_temp.sheet('expert_fill_pressures'),'120 psi','and the storefront reads it through its view');

-- Undo a batch: only what still reads as the batch left it.
select is(public.discard_product_spec_expert_batch_v1('tanda-1')->>'discarded','3','the batch is undone except the edited datum');
select ok((pg_temp.fact('drivetrain_mode')).id is null,'an untouched fill is gone');
select ok((pg_temp.fact('chain_speeds')).id is not null,'an edited fill stays');
select ok((pg_temp.fact('link_count')).id is not null,'another batch stays');
select ok((pg_temp.fact('quick_link_included')).id is not null,'what was written by hand stays');

-- Only shop staff fill a sheet.
select set_config('request.jwt.claims','{"sub":"99c60000-0000-4000-8000-000000000092","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99c60000-0000-4000-8000-000000000092',true);
set local role authenticated;
select throws_ok($$select pg_temp.fill('drivetrain_mode','"Derailleur"')$$,'42501',null,'a store customer cannot fill a sheet');
reset role;
set local role anon;
select throws_ok($$select public.record_product_spec_expert_value_v1('99c60000-0000-4000-8000-000000000020','link_count','1','x')$$,
  '42501',null,'a visitor cannot call it');
reset role;
select ok(not has_table_privilege('authenticated','public.spec_fact_expert_fills','select'),'the receipts stay internal');

select * from finish();
rollback;
