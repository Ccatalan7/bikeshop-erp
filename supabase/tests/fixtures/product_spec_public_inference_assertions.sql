-- Assertions shared by the standalone test and exact preimage/replay rehearsal.
-- 20261002140000: the origin of a datum no longer decides whether it is
-- published (owner, 2026-10-01); only the retired field stays out.
select is((select count(*)::int from pg_temp.public_inference_rows()),5,
 'public output omits only the existing legacy field');
select is((select display_value from pg_temp.public_inference_rows() where spec_key='public_inference_pending_number'),'12',
 'an unconfirmed deduced number is published like any other datum');
select is((select display_value from pg_temp.public_inference_rows() where spec_key='public_inference_pending_text'),'Synthetic inference',
 'an unconfirmed deduced text is published like any other datum');
select is((select display_value from pg_temp.public_inference_rows() where spec_key='public_inference_confirmed_number'),'13',
 'inference already confirmed by the existing contract keeps its display policy');
select is((select display_value from pg_temp.public_inference_rows() where spec_key='public_inference_supplier_boolean'),'No',
 'unconfirmed supplier assertion retains known false without a global confirmed filter');
select is((select display_value from pg_temp.public_inference_rows() where spec_key='public_inference_mechanic_zero'),'0',
 'mechanic observation retains zero');
select ok(not exists(select 1 from pg_temp.public_inference_rows() where spec_key='public_inference_legacy'),
 'existing legacy exclusion remains effective');
select is((select jsonb_agg(to_jsonb(f) order by f.id) from public.spec_facts f
 where f.tenant_id='99bc0000-0000-4000-8000-000000000001'),
 (select facts from public_inference_original),'every stored fact, source, confirmation, identity and timestamp is unchanged');
select is((select to_jsonb(p) from public.products p where p.id='99bc0000-0000-4000-8000-000000000020'),
 (select product from public_inference_original),'product identity, assignment, visibility and commerce are unchanged');
select is(public.spec_active_product_values_internal_v1('99bc0000-0000-4000-8000-000000000020',
 '99bc0000-0000-4000-8000-000000000010'),(select internal_values from public_inference_original),
 'internal value projection retains observations for review');
select is((select proacl from pg_proc where oid='public.get_public_product_technical_specs(uuid,uuid)'::regprocedure),
 (select acl from public_inference_original),'function grants remain unchanged');
select is((select count(*)::int from public.get_public_product_technical_specs(
 '99bc0000-0000-4000-8000-000000000099','99bc0000-0000-4000-8000-000000000020')),0,
 'another tenant cannot read the product');
update public.products set is_published=false where id='99bc0000-0000-4000-8000-000000000020';
select is((select count(*)::int from pg_temp.public_inference_rows()),0,'unpublished product remains hidden');
update public.products set is_published=true,show_on_website=false where id='99bc0000-0000-4000-8000-000000000020';
select is((select count(*)::int from pg_temp.public_inference_rows()),0,'website visibility remains enforced');
