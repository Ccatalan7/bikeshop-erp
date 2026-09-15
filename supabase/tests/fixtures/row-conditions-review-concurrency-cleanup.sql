-- LOCAL ONLY exact cleanup for row-conditions-review-concurrency.sql.
begin;
set local request.jwt.claims='{}';
set local request.jwt.claim.sub='';
-- Polymorphic subjects do not cascade from products. Remove only these
-- synthetic product facts first while the subject still exists; the normal
-- fact/value/provenance triggers and foreign-key cascades remain enabled.
delete from public.spec_facts where tenant_id='c0bf0000-0000-4000-8000-000000000001'
  and subject_type='product' and subject_id in
    ('c0bf0000-0000-4000-8000-000000000020','c0bf0000-0000-4000-8000-000000000021');
delete from public.products where id in
  ('c0bf0000-0000-4000-8000-000000000020','c0bf0000-0000-4000-8000-000000000021')
  and tenant_id='c0bf0000-0000-4000-8000-000000000001';
delete from public.product_spec_save_receipts where tenant_id='c0bf0000-0000-4000-8000-000000000001';
-- Reference immutability intentionally prevents deletion. This LOCAL cleanup
-- suspends only that named trigger under a table lock, for this exact fixture
-- ID, and restores it within the same transaction. An exception rolls back the
-- trigger state together with the cleanup. No global replication-role change.
lock table public.product_spec_references in share row exclusive mode;
do $guard$ begin
  if (select tgenabled from pg_trigger where tgrelid='public.product_spec_references'::regclass
      and tgname='product_spec_reference_immutable' and not tgisinternal) is distinct from 'O' then
    raise exception 'Expected enabled product_spec_reference_immutable trigger; no cleanup change made';
  end if;
end $guard$;
alter table public.product_spec_references disable trigger product_spec_reference_immutable;
delete from public.product_spec_references where id='row-conditions-review-race-reference';
alter table public.product_spec_references enable trigger product_spec_reference_immutable;
delete from public.category_tech_mappings where tenant_id='c0bf0000-0000-4000-8000-000000000001'
  and category_id='c0bf0000-0000-4000-8000-000000000003';
delete from public.product_categories where tenant_id='c0bf0000-0000-4000-8000-000000000001'
  and id='c0bf0000-0000-4000-8000-000000000003';
delete from public.spec_templates where id in
  ('c0bf0000-0000-4000-8000-000000000050','c0bf0000-0000-4000-8000-000000000051','c0bf0000-0000-4000-8000-000000000052')
  and tenant_id='c0bf0000-0000-4000-8000-000000000001';
delete from public.spec_definitions where id in
  ('c0bf0000-0000-4000-8000-000000000011','c0bf0000-0000-4000-8000-000000000012','c0bf0000-0000-4000-8000-000000000013');
delete from auth.users where id='c0bf0000-0000-4000-8000-000000000091';
delete from public.tenants where id='c0bf0000-0000-4000-8000-000000000001';
set constraints all immediate;
commit;
select not exists(select 1 from public.tenants where id='c0bf0000-0000-4000-8000-000000000001')
  and not exists(select 1 from public.spec_definitions where id in
    ('c0bf0000-0000-4000-8000-000000000011','c0bf0000-0000-4000-8000-000000000012','c0bf0000-0000-4000-8000-000000000013'))
  and not exists(select 1 from public.product_spec_references where id='row-conditions-review-race-reference')
  and not exists(select 1 from public.spec_facts where tenant_id='c0bf0000-0000-4000-8000-000000000001'
    and subject_type='product' and subject_id in
      ('c0bf0000-0000-4000-8000-000000000020','c0bf0000-0000-4000-8000-000000000021'))
  as row_conditions_review_fixture_removed;
