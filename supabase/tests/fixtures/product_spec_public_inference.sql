-- Synthetic catalogue owned only by the rollback test transaction.
insert into public.tenants(id,shop_name) values
 ('99bc0000-0000-4000-8000-000000000001','Public inference fixture');
insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values ('99bc0000-0000-4000-8000-000000000091','authenticated','authenticated',
 'public-spec-inference@example.invalid','',now(),'{}',
 '{"account_type":"public_store_customer","customer_tenant_id":"99bc0000-0000-4000-8000-000000000001"}',now(),now());
delete from public.user_profiles where user_id='99bc0000-0000-4000-8000-000000000091';
insert into public.user_profiles(user_id,tenant_id,role) values
 ('99bc0000-0000-4000-8000-000000000091','99bc0000-0000-4000-8000-000000000001','admin');
select set_config('request.jwt.claims','{"sub":"99bc0000-0000-4000-8000-000000000091","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','99bc0000-0000-4000-8000-000000000091',true);
insert into public.spec_templates(id,tenant_id,key,name,technical_family,is_active,form_contract)
values ('99bc0000-0000-4000-8000-000000000010','99bc0000-0000-4000-8000-000000000001',
 'public_inference_fixture','Synthetic public specification','tire',true,
 '{"version":1,"coverage":"template","roles":{"public_inference_legacy":"legacy"},"labels":{},"helpers":{},"prerequisites":{}}');
insert into public.spec_definitions(id,tenant_id,key,label,data_type,is_customer_visible,allowed_values,validation_rules)
select ('99bc0000-0000-4000-8000-00000000010'||n)::uuid,
 '99bc0000-0000-4000-8000-000000000001',key,key,kind,true,'[]','{}'
from (values
 (1,'public_inference_pending_number','number'),
 (2,'public_inference_confirmed_number','number'),
 (3,'public_inference_supplier_boolean','boolean'),
 (4,'public_inference_mechanic_zero','number'),
 (5,'public_inference_pending_text','text'),
 (6,'public_inference_legacy','number')) a(n,key,kind);
insert into public.spec_template_fields(tenant_id,template_id,spec_definition_id,section_key,sort_order,is_required)
select '99bc0000-0000-4000-8000-000000000001','99bc0000-0000-4000-8000-000000000010',
 id,case when key='public_inference_legacy' then 'legacy' else 'specs' end,10,false
from public.spec_definitions where tenant_id='99bc0000-0000-4000-8000-000000000001';
insert into public.products(id,tenant_id,name,sku,spec_template_id,price,cost,is_active,is_published,show_on_website)
values ('99bc0000-0000-4000-8000-000000000020','99bc0000-0000-4000-8000-000000000001',
 'Synthetic inference product','PUBLIC-INFERENCE','99bc0000-0000-4000-8000-000000000010',1,1,true,true,true);
insert into public.spec_facts(tenant_id,subject_type,subject_id,spec_definition_id,value_number,value_boolean,value_text,source,confirmed)
select '99bc0000-0000-4000-8000-000000000001','product','99bc0000-0000-4000-8000-000000000020',
 d.id,a.number,a.bool,a.text,a.source,a.confirmed
from (values
 ('public_inference_pending_number',12::numeric,null::boolean,null::text,'inferred',false),
 ('public_inference_confirmed_number',13,null,null,'inferred',true),
 ('public_inference_supplier_boolean',null,false,null,'supplier_text',false),
 ('public_inference_mechanic_zero',0,null,null,'mechanic',false),
 ('public_inference_pending_text',null,null,'Synthetic inference','inferred',false),
 ('public_inference_legacy',14,null,null,'inferred',true)) a(key,number,bool,text,source,confirmed)
join public.spec_definitions d on d.key=a.key and d.tenant_id='99bc0000-0000-4000-8000-000000000001';
create function pg_temp.public_inference_rows()
returns table(spec_key text, display_value text) language sql as $$
 select spec_key,display_value from public.get_public_product_technical_specs(
 '99bc0000-0000-4000-8000-000000000001','99bc0000-0000-4000-8000-000000000020')
$$;
create temp table public_inference_original as select
 (select jsonb_agg(to_jsonb(f) order by f.id) from public.spec_facts f
  where f.tenant_id='99bc0000-0000-4000-8000-000000000001') facts,
 (select to_jsonb(p) from public.products p where p.id='99bc0000-0000-4000-8000-000000000020') product,
 (select proacl from pg_proc where oid='public.get_public_product_technical_specs(uuid,uuid)'::regprocedure) acl,
 public.spec_active_product_values_internal_v1('99bc0000-0000-4000-8000-000000000020',
 '99bc0000-0000-4000-8000-000000000010') internal_values;
