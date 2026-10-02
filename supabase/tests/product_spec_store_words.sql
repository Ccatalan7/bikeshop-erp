-- The storefront sheet speaks the customer's words (20261002130000): the
-- store name of each datum, a one-line explanation of a technical term, the
-- rank of what decides the purchase, and option names in Spanish in the sheet
-- and in the catalog filters. The operator's label and the option label (the
-- identity rules and name readings cite) stay as they were.
begin;
select no_plan();
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.sub','',true);
insert into public.tenants(id,shop_name) values ('99c40000-0000-4000-8000-000000000001','Store words');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('99c40000-0000-4000-8000-000000000091','authenticated','authenticated','store-words@example.invalid','',now(),'{}',
 jsonb_build_object('account_type','public_store_customer','customer_tenant_id','99c40000-0000-4000-8000-000000000001'),now(),now());
delete from public.user_profiles where user_id='99c40000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values ('99c40000-0000-4000-8000-000000000091','99c40000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"99c40000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99c40000-0000-4000-8000-000000000091',true);
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99c40000-0000-4000-8000-000000000010','99c40000-0000-4000-8000-000000000001','Cadenas','Cadenas');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status)
select '99c40000-0000-4000-8000-000000000001','99c40000-0000-4000-8000-000000000010','chain',id,'active'
from public.spec_templates where key='chain' and tenant_id is null;

create function pg_temp.def(p_key text) returns uuid language sql as $$
 select id from public.spec_definitions where key=p_key and tenant_id is null $$;
create function pg_temp.options(p_key text,p_labels text[]) returns jsonb language sql as $$
 select jsonb_build_object(d.id,jsonb_build_object('value_ids',jsonb_agg(v.id order by v.label)))
 from public.spec_definitions d join public.spec_definition_values v on v.spec_definition_id=d.id
 where d.key=p_key and d.tenant_id is null and v.label=any(p_labels) group by d.id $$;
create function pg_temp.sheet() returns setof record language sql as $$
 select spec_key,spec_label,display_value,spec_hint,highlight_rank
 from public.get_public_product_technical_specs('99c40000-0000-4000-8000-000000000001','99c40000-0000-4000-8000-000000000020') $$;

select lives_ok($$select public.save_product_with_specs_v1(
  '{"id":"99c40000-0000-4000-8000-000000000020","name":"Cadena KMC HV408 116 eslabones","sku":"WORDS-HV408","brand":"KMC","model":"HV408","price":9990,"cost":4000,"category_id":"99c40000-0000-4000-8000-000000000010","is_published":true,"show_on_website":true}'::jsonb,
  true,(select id from public.spec_templates where key='chain' and tenant_id is null),
  (select contract_version from public.spec_templates where key='chain' and tenant_id is null),
  pg_temp.options('chain_speeds',array['6']) || pg_temp.options('chain_width_family',array['3/32'])
   || jsonb_build_object(pg_temp.def('link_count'),jsonb_build_object('number',116))
   || jsonb_build_object(pg_temp.def('quick_link_included'),jsonb_build_object('boolean',false)),
  null,null,'store-words-create',null,null)$$,'a published chain with four facts');

select is((select s.spec_label from pg_temp.sheet() s(spec_key text,spec_label text,display_value text,spec_hint text,highlight_rank integer) where s.spec_key='chain_speeds'),
  'Velocidades','the store name replaces «Velocidades declaradas del modelo»');
select is((select s.display_value from pg_temp.sheet() s(spec_key text,spec_label text,display_value text,spec_hint text,highlight_rank integer) where s.spec_key='chain_width_family'),
  '3/32"','an option shows its visible name');
select isnt((select s.spec_hint from pg_temp.sheet() s(spec_key text,spec_label text,display_value text,spec_hint text,highlight_rank integer) where s.spec_key='chain_width_family'),
  null,'a technical term carries its explanation');
select is((select array_agg(s.spec_key order by s.highlight_rank) from pg_temp.sheet() s(spec_key text,spec_label text,display_value text,spec_hint text,highlight_rank integer) where s.highlight_rank is not null),
  array['chain_speeds','link_count','chain_width_family','quick_link_included'],'what decides the purchase, in order');
select is((select s.display_value from pg_temp.sheet() s(spec_key text,spec_label text,display_value text,spec_hint text,highlight_rank integer) where s.spec_key='quick_link_included'),
  'No','an explicit false is still published');

select is((select label from public.spec_definition_values where spec_definition_id=pg_temp.def('chain_width_family') and label='3/32' and tenant_id is null),
  '3/32','the option label, cited by rules and name readings, is unchanged');
select isnt((select label from public.spec_definitions where id=pg_temp.def('chain_speeds')),
  'Velocidades','the operator keeps the editor label');
select ok(not exists(select 1 from public.spec_definitions where tenant_id is null and is_customer_visible
  and key in ('published_variant_label','rear_derailleur_supplied_adapter_reference','rim_joint_designation')),
  'supplier text and reconciliation notes leave the storefront');

select is((select v.spec_label from public.spec_public_facet_values_internal_v1('99c40000-0000-4000-8000-000000000001') v
  where v.product_id='99c40000-0000-4000-8000-000000000020' and v.spec_key='chain_width_family'),
  'Ancho de cadena','a catalog filter is named as the sheet names it');
select is((select v.value_text from public.spec_public_facet_values_internal_v1('99c40000-0000-4000-8000-000000000001') v
  where v.product_id='99c40000-0000-4000-8000-000000000020' and v.spec_key='chain_width_family'),
  '3/32','a filter keeps matching by the option label that links cite');

set local role anon;
select is((select display_label from public.get_public_spec_option_labels_v1('99c40000-0000-4000-8000-000000000001')
  where spec_key='chain_width_family' and value_label='3/32'),'3/32"','a visitor reads the option name of a filter');
select ok(exists(select 1 from public.get_public_product_technical_specs('99c40000-0000-4000-8000-000000000001','99c40000-0000-4000-8000-000000000020')),
  'the recreated sheet stays readable by visitors');
reset role;
select ok(not has_function_privilege('anon','public.spec_public_facet_values_internal_v1(uuid)','execute'),'the facet reader stays internal');

select * from finish();
rollback;
