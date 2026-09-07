-- Product identity owns the technical template; the commercial category is
-- only the legacy default. This migration does not assign or fill products.
begin;
-- Do not overwrite a concurrent change to any shared reader or writer.
do $$
declare expected record;
begin
 for expected in select * from (values
  ('assign_product_spec_template_v1(uuid,uuid,bigint,timestamp with time zone,text,text)',null::text,'83e6922ef72686c0b326104191d39468'),
  ('assistant_infer_technical_predicates_internal_v1(uuid,text)','493a99c584ea32030cbe328b7af24792','81c8b719dd1045f2a9c5344a47920ea4'),
  ('assistant_inspect_inventory_schema_v1(text,text)','105a2978d384f2250af9103ef1cc5b35','7bbc39ab1e133c0eb4e871767058bfe4'),
  ('assistant_inspect_inventory_schema_v3(text,text)','2770a3967b5bda77c65456dc1ef695b3','26987ba99cc2eda8ac97822fb06e8188'),
  ('assistant_inventory_technical_filter_source_internal_v1(uuid,uuid,text,text,text,text)','a778c4f135bed392c7ccf6dce65ab026','bc000c89b3c97cafac28c0507b402ce9'),
  ('assistant_inventory_technical_predicate_source_internal_v1(uuid,uuid,text,text,jsonb,text,text)','a77db149de31fb65d1f2b0345cd8dab0','ff9871ba6dab000cba0cdb08c2fff8bc'),
  ('assistant_search_inventory_v4(text,text,text,jsonb)','24b11122f8f77555197536d24cc1100b','76c04a1e7acc06de7b21851150ed626b'),
  ('assistant_search_inventory_v5(text,text,text,jsonb)','8e09cf7cbb23700b48ab4e47288ce866','0a25c2875d242f44627dfcdcd3ef1cf2'),
  ('assistant_search_inventory_v6(text,text,text,jsonb,jsonb,text,text,integer,text)','56a7f32b2a5667c199022eae215799a8','28c85cd5633346cb352e762ec0c82890'),
  ('assistant_search_inventory_v7(text,text,text,jsonb,jsonb,text,text,integer,text)','c4f72e4d02b1d4e476f95ba9abf01968','e24570be356f28df2ee03309dd44863c'),
  ('get_product_ids_for_spec_family_v1(text)',null::text,'e03037a3826ed15303fb2cddb2876747'),
  ('get_product_spec_bindings_v1(uuid[])',null::text,'a3e6388150b1ad397f3d64bd0598a81b'),
  ('get_product_spec_contexts_v1(uuid[])','5190cde862b60b351cedc46bf79ed041','40d64bdcef3cb02da023adaa7c18baac'),
  ('get_product_spec_editor_context_v1(uuid,uuid)',null::text,'f22771ee06c6934df9637f11a2e8030c'),
  ('get_product_spec_snapshot_v1(uuid)','180c131636eebed774aeebdfb4a14435','4beeceb9e7bd2851db4588df173118e5'),
  ('get_public_product_technical_specs(uuid,uuid)','16a58c51cd6402c93fecca5be88c1d80','6a4f8d71823c385d164096635af3dc00'),
  ('save_product_spec_facts_v1(uuid,uuid[],jsonb)','748a15f661dcafedad468b0bddb287ee','46fb391ccfc59e454b727250bdf46424'),
  ('save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb)','66b69b3594b6ede2e102348e054d5b09','d7fd562e5e269f82b25a1b3cf417b2a6'),
  ('spec_active_product_values_internal_v1(uuid,uuid)',null::text,'1ab99082cbf39cc4eb3bfc046d25e6f5'),
  ('spec_product_constraint_internal_v1()','a433db96f91cf69c1976f1972649a202','e0f2ed4633d1f3e62d63840928f9d619'),
  ('spec_product_field_is_active_internal_v1(uuid,uuid,text)',null::text,'f4dcf9d875d92392f0ac883bf4b58b21'),
  ('spec_product_revision_internal_v1()','b094ece92ab8505baa3262b0be1e639f','ba1b6a5937353686bf3cbf9957e6957b'),
  ('spec_template_resolution_internal_v1(uuid,uuid,uuid)',null::text,'d16d71e4bb74c787d327ebe80b6a1c2b'),
  ('spec_template_retirement_guard_internal_v1()',null::text,'d45f8208b806d10eff49c3f8b8e3a257'),
  ('spec_unassigned_facts_internal_v1(uuid,uuid)',null::text,'09bb7db18ed3db2f0df093f82b20ed9c'),
  ('spec_validate_product_internal_v1(uuid)','f57e58b871a767f8b170d61d169034c0','6f8f676f03241a5f68a10b3d9b152272'),
  ('supply_need_eligible_products_internal_v1(uuid,uuid,integer)','4136473bde5ed924089271fe153eac90','34eb434cda196e513113e9d4fa6ad425'),
  ('supply_need_stock_candidates_v1(uuid,integer)','30758a22097848bf7a93bd6d92e83198','c27a321442b6ce010eee550629ea9a84')
,
  ('spec_product_definition_is_active_internal_v1(uuid,uuid,uuid)',null::text,'459f3dc86573e7c7a022cea7e4cc139c'),
  ('spec_product_field_definition_internal_v1(uuid,uuid,text)',null::text,'db46ccd5eb176214e126e762f5e15310'),
  ('spec_template_product_payload_internal_v1(uuid,uuid,boolean)',null::text,'a56ef26e739ff4b3687d9f07f9065cb0')
 ) reviewed(signature,before_md5,after_md5) loop
   if to_regprocedure(expected.signature) is null then
     if expected.before_md5 is not null then raise exception 'Required function missing: %',expected.signature; end if;
   elsif md5(pg_get_functiondef(to_regprocedure(expected.signature))) <> expected.after_md5
     and (expected.before_md5 is null or md5(pg_get_functiondef(to_regprocedure(expected.signature))) <> expected.before_md5) then
     raise exception 'Affected function changed since review: %',expected.signature;
   end if;
 end loop;
end $$;
alter table public.products add column if not exists spec_template_id uuid
  references public.spec_templates(id) on delete restrict;
-- Declarative active-template references close assignment/retirement races,
-- including transactions with an older snapshot. The trigger below supplies
-- a useful message; these foreign keys enforce the committed graph.
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.spec_templates'::regclass and conname='spec_templates_id_active_key') then
  alter table public.spec_templates add constraint spec_templates_id_active_key unique(id,is_active);
 end if;
end $$;
alter table public.products add column if not exists spec_template_active_guard boolean
  generated always as (true) stored;
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.products'::regclass and conname='products_spec_template_active_fk') then
  alter table public.products add constraint products_spec_template_active_fk
  foreign key(spec_template_id,spec_template_active_guard) references public.spec_templates(id,is_active)
  deferrable initially immediate;
 end if;
end $$;
alter table public.category_tech_mappings add column if not exists spec_template_active_guard boolean
  generated always as (case when status='active' then true else null::boolean end) stored;
do $$ begin
 if not exists(select 1 from pg_constraint where conrelid='public.category_tech_mappings'::regclass and conname='category_spec_template_active_fk') then
  alter table public.category_tech_mappings add constraint category_spec_template_active_fk
  foreign key(template_id,spec_template_active_guard) references public.spec_templates(id,is_active)
  deferrable initially immediate;
 end if;
end $$;
create index if not exists products_explicit_spec_template_idx on public.products(spec_template_id)
  where spec_template_id is not null;
comment on column public.products.spec_template_id is
 'Reviewed product object class; null uses the active category default. Assignment does not assert mechanical compatibility.';

-- Column revokes alone cannot override a table-wide grant. Preserve each
-- client's existing ordinary-column grants, but require commands for these
-- three protected identities on INSERT as well as UPDATE.
do $$
declare v_role text; v_privilege text; v_columns text;
begin
 if exists(select 1 from pg_class c cross join lateral aclexplode(c.relacl) a
   where c.oid='public.products'::regclass and a.grantee=0 and a.privilege_type in ('INSERT','UPDATE')) then
   raise exception 'Unexpected PUBLIC product write grant; review ACL before deployment';
 end if;
 foreach v_role in array array['anon','authenticated'] loop
   foreach v_privilege in array array['INSERT','UPDATE'] loop
     select string_agg(format('%I',attname),',' order by attnum) into v_columns
     from pg_attribute where attrelid='public.products'::regclass and attnum>0 and not attisdropped
       and attname not in ('spec_template_id','spec_reference_id','spec_revision','spec_template_active_guard')
       and has_column_privilege(v_role,'public.products',attname,v_privilege);
     execute format('revoke %s on public.products from %I',v_privilege,v_role);
     execute format('revoke %s (spec_template_id,spec_reference_id,spec_revision,spec_template_active_guard) on public.products from %I',v_privilege,v_role);
     if v_columns is not null then execute format('grant %s (%s) on public.products to %I',v_privilege,v_columns,v_role); end if;
   end loop;
 end loop;
end $$;

create or replace function public.spec_template_retirement_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin
 if ((old.is_active and not new.is_active)
   or (old.tenant_id,old.key,old.technical_family) is distinct from (new.tenant_id,new.key,new.technical_family)) and (
   exists(select 1 from public.products where spec_template_id=old.id)
   or exists(select 1 from public.category_tech_mappings where template_id=old.id and status='active')
 ) then raise exception 'Reasigna los productos y categorías antes de retirar esta ficha.' using errcode='23514'; end if;
 return new;
end $$;
revoke all on function public.spec_template_retirement_guard_internal_v1() from public,anon,authenticated;
drop trigger if exists spec_template_retirement_guard on public.spec_templates;
create trigger spec_template_retirement_guard before update of is_active,tenant_id,key,technical_family on public.spec_templates
 for each row execute function public.spec_template_retirement_guard_internal_v1();

create or replace function public.spec_template_resolution_internal_v1(
  p_tenant_id uuid,p_category_id uuid,p_explicit_template_id uuid
) returns uuid language sql stable set search_path=pg_catalog,public,pg_temp as $$
 select t.id from public.spec_templates t
 where t.is_active and (t.tenant_id is null or t.tenant_id=p_tenant_id)
   and t.id=case when p_explicit_template_id is not null then p_explicit_template_id
     else (select m.template_id from public.category_tech_mappings m
       where m.tenant_id=p_tenant_id and m.category_id=p_category_id and m.status='active') end
$$;
revoke all on function public.spec_template_resolution_internal_v1(uuid,uuid,uuid)
  from public,anon,authenticated;

-- Private projection: only tenant-guarded SECURITY DEFINER readers may use it.
-- An invalid/inactive explicit binding never falls back to the category.
create or replace view public.product_spec_bindings_internal_v1 as
 select p.id product_id,p.tenant_id,p.category_id,p.spec_template_id explicit_template_id,
   t.id template_id,t.key template_key,t.technical_family,t.contract_version,
   case when p.spec_template_id is not null then
     case when t.id is null then 'explicit_unavailable' else 'explicit' end
     when t.id is not null then 'category' else 'none' end binding_source
 from public.products p
 left join public.spec_templates t on t.id=public.spec_template_resolution_internal_v1(
   p.tenant_id,p.category_id,p.spec_template_id);
revoke all on public.product_spec_bindings_internal_v1 from public,anon,authenticated;

-- A commercial category may contain multiple object classes. Schema discovery
-- exposes their union without pretending that each field belongs to every item.
create or replace view public.category_spec_template_scope_internal_v1 as
 select m.tenant_id,m.category_id,t.id template_id,t.technical_family,'active'::text status
 from public.category_tech_mappings m join public.spec_templates t on t.id=m.template_id
 where m.status='active' and t.is_active and (t.tenant_id is null or t.tenant_id=m.tenant_id)
 union
 select b.tenant_id,b.category_id,b.template_id,b.technical_family,'active'::text
 from public.product_spec_bindings_internal_v1 b join public.products p on p.id=b.product_id
 where b.category_id is not null and b.template_id is not null and p.is_active;
revoke all on public.category_spec_template_scope_internal_v1 from public,anon,authenticated;

-- Resolve field identity inside the bound template before interpreting its key.
-- A key shared by global and tenant definitions is not an implicit override.
create or replace function public.spec_product_field_definition_internal_v1(p_tenant_id uuid,p_product_id uuid,p_field_key text)
returns uuid language sql stable set search_path=pg_catalog,public,pg_temp as $$
 select case when count(distinct d.id)=1 then (array_agg(distinct d.id))[1] end
 from public.product_spec_bindings_internal_v1 b
 join public.spec_templates t on t.id=b.template_id
 join public.spec_template_fields f on f.template_id=t.id
 join public.spec_definitions d on d.id=f.spec_definition_id
 where b.tenant_id=p_tenant_id and b.product_id=p_product_id and d.key=p_field_key
   and (d.tenant_id is null or d.tenant_id=b.tenant_id)
   and coalesce(t.form_contract->'roles'->>d.key,'primary')<>'legacy'
$$;
revoke all on function public.spec_product_field_definition_internal_v1(uuid,uuid,text) from public,anon,authenticated;

create or replace function public.spec_product_definition_is_active_internal_v1(p_tenant_id uuid,p_product_id uuid,p_definition_id uuid)
returns boolean language sql stable set search_path=pg_catalog,public,pg_temp as $$
 select coalesce(p_definition_id=public.spec_product_field_definition_internal_v1(
   p_tenant_id,p_product_id,(select key from public.spec_definitions where id=p_definition_id)),false)
$$;
revoke all on function public.spec_product_definition_is_active_internal_v1(uuid,uuid,uuid) from public,anon,authenticated;

create or replace function public.spec_product_field_is_active_internal_v1(p_tenant_id uuid,p_product_id uuid,p_field_key text)
returns boolean language sql stable set search_path=pg_catalog,public,pg_temp as $$
 select public.spec_product_field_definition_internal_v1(p_tenant_id,p_product_id,p_field_key) is not null
$$;
revoke all on function public.spec_product_field_is_active_internal_v1(uuid,uuid,text) from public,anon,authenticated;

-- Filter normalized IDs before display reduces them to keys. Ambiguous keys
-- in a malformed template reject the scalar projection before an editor can save.
create or replace function public.spec_template_product_payload_internal_v1(p_product_id uuid,p_template_id uuid,p_include_legacy boolean)
returns jsonb language plpgsql stable set search_path=pg_catalog,public,pg_temp as $$
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
 from jsonb_each(public.spec_product_payload_internal_v1(p_product_id)) e
 join public.spec_definitions d on d.id::text=e.key
 join public.products p on p.id=p_product_id and (d.tenant_id is null or d.tenant_id=p.tenant_id)
 join public.spec_templates t on t.id=p_template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
 where exists(select 1 from public.spec_template_fields f where f.template_id=t.id and f.spec_definition_id=d.id)
   and (coalesce(p_include_legacy,false) or coalesce(t.form_contract->'roles'->>d.key,'primary')<>'legacy'));
end $$;
revoke all on function public.spec_template_product_payload_internal_v1(uuid,uuid,boolean) from public,anon,authenticated;

create or replace function public.get_product_spec_bindings_v1(p_product_ids uuid[])
returns jsonb language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select coalesce(jsonb_object_agg(b.product_id,to_jsonb(b)-'tenant_id'),'{}'::jsonb)
 from public.product_spec_bindings_internal_v1 b
 where b.product_id=any(p_product_ids) and b.tenant_id=public.user_tenant_id() and auth.uid() is not null
$$;
revoke all on function public.get_product_spec_bindings_v1(uuid[]) from public,anon;
grant execute on function public.get_product_spec_bindings_v1(uuid[]) to authenticated;

-- The editor resolves the stored product override against the draft category
-- in the same statement as its facts/revision. Null category is a valid draft.
create or replace function public.get_product_spec_editor_context_v1(p_product_id uuid,p_category_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_tenant uuid:=public.user_tenant_id(); v_product public.products%rowtype;
 v_template public.spec_templates%rowtype; v_snapshot jsonb:='{"values":{},"revision":0}'::jsonb;
begin
 if auth.uid() is null or v_tenant is null then raise exception 'Authenticated tenant required' using errcode='42501'; end if;
 if p_product_id is not null then
   select * into v_product from public.products where id=p_product_id and tenant_id=v_tenant;
   if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
   v_snapshot:=public.get_product_spec_snapshot_v1(p_product_id);
 end if;
 if p_category_id is not null and not exists(select 1 from public.product_categories where id=p_category_id and tenant_id=v_tenant) then
   raise exception 'Categoría no disponible para este tenant' using errcode='42501'; end if;
 select * into v_template from public.spec_templates where id=public.spec_template_resolution_internal_v1(v_tenant,p_category_id,v_product.spec_template_id);
 return v_snapshot||jsonb_build_object('template_id',v_template.id,'template_key',v_template.key,
   'technical_family',v_template.technical_family,'contract_version',v_template.contract_version,
   'binding_source',case when v_product.spec_template_id is not null then
     case when v_template.id is null then 'explicit_unavailable' else 'explicit' end
     when v_template.id is not null then 'category' else 'none' end,
   'values',public.spec_payload_display_internal_v1(public.spec_template_product_payload_internal_v1(p_product_id,v_template.id,true)),
   'unassigned_facts',public.spec_unassigned_facts_internal_v1(p_product_id,v_template.id));
end $$;
revoke all on function public.get_product_spec_editor_context_v1(uuid,uuid) from public,anon;
grant execute on function public.get_product_spec_editor_context_v1(uuid,uuid) to authenticated;

create or replace function public.get_product_ids_for_spec_family_v1(p_family text)
returns uuid[] language sql stable security definer set search_path=pg_catalog,public,pg_temp as $$
 select coalesce(array_agg(p.id order by p.id),'{}'::uuid[]) from public.products p
 join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
 where p.tenant_id=public.user_tenant_id() and auth.uid() is not null
   and p.is_active and p.product_type='product' and b.technical_family=p_family
$$;
revoke all on function public.get_product_ids_for_spec_family_v1(text) from public,anon;
grant execute on function public.get_product_ids_for_spec_family_v1(text) to authenticated;

create or replace function public.spec_unassigned_facts_internal_v1(p_product_id uuid,p_template_id uuid)
returns jsonb language sql stable set search_path=pg_catalog,public,pg_temp as $$
 with payload as materialized (
   select public.spec_product_payload_internal_v1(p_product_id) values
 )
 select coalesce(jsonb_agg(jsonb_build_object(
   'fact_id',f.id,'definition_id',d.id,'key',d.key,'label',d.label,
   'value',public.spec_payload_display_internal_v1(jsonb_build_object(d.id::text,payload.values->d.id::text))->d.key,
   'source',f.source,'confirmed',f.confirmed,'updated_at',f.updated_at,
   'readings',(select coalesce(jsonb_agg(to_jsonb(r)),'[]'::jsonb) from public.spec_fact_readings r where r.fact_id=f.id and r.tenant_id=f.tenant_id)
 ) order by d.key),'[]'::jsonb)
 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id cross join payload
 where f.subject_type='product' and f.subject_id=p_product_id and f.subject_scope is null
   and f.tenant_id=(select tenant_id from public.products where id=p_product_id)
   and not exists(select 1 from public.spec_template_fields tf
     where tf.template_id=p_template_id and tf.spec_definition_id=f.spec_definition_id)
$$;
revoke all on function public.spec_unassigned_facts_internal_v1(uuid,uuid) from public,anon,authenticated;

create or replace function public.spec_active_product_values_internal_v1(p_product_id uuid,p_template_id uuid)
returns jsonb language sql stable set search_path=pg_catalog,public,pg_temp as $$
 select public.spec_payload_display_internal_v1(public.spec_template_product_payload_internal_v1(p_product_id,p_template_id,false))
$$;
revoke all on function public.spec_active_product_values_internal_v1(uuid,uuid) from public,anon,authenticated;

create or replace function public.assign_product_spec_template_v1(
 p_product_id uuid,p_template_id uuid,p_expected_revision bigint,
 p_expected_updated_at timestamptz,p_operation_key text,p_reason text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_tenant uuid:=public.user_tenant_id(); v_product public.products%rowtype;
 v_receipt public.product_spec_save_receipts%rowtype; v_hash text; v_result jsonb; v_before jsonb;
begin
 if v_tenant is null or auth.uid() is null then raise exception 'Authenticated tenant required' using errcode='42501'; end if;
 if p_product_id is null or nullif(btrim(p_operation_key),'') is null or length(p_operation_key)>180
   or nullif(btrim(p_reason),'') is null or length(p_reason)>2000 then
   raise exception 'Assignment requires product, operation key and review reason' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_tenant::text||':product_spec_save:'||p_operation_key,0));
 v_hash:=md5(jsonb_build_object('command','assign_product_spec_template_v1','product_id',p_product_id,
   'template_id',p_template_id,'reason',p_reason)::text);
 select * into v_receipt from public.product_spec_save_receipts where tenant_id=v_tenant and operation_key=p_operation_key;
 if found then
   if v_receipt.request_hash<>v_hash then raise exception 'Operation key already used for another command' using errcode='23505'; end if;
   return v_receipt.result||jsonb_build_object('replayed',true);
 end if;
 perform pg_advisory_xact_lock(hashtextextended(v_tenant::text||':spec_fact:'||p_product_id::text,0));
 select * into v_product from public.products where id=p_product_id and tenant_id=v_tenant for update;
 if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
 if v_product.spec_revision is distinct from p_expected_revision or v_product.updated_at is distinct from p_expected_updated_at then
   raise exception 'La ficha cambió desde que la revisaste. Recarga antes de asignarla.' using errcode='40001'; end if;
 if p_template_id is not null and public.spec_template_resolution_internal_v1(v_tenant,null,p_template_id) is null then
   raise exception 'Plantilla no disponible para este tenant' using errcode='42501'; end if;
 v_before:=public.get_product_spec_snapshot_v1(p_product_id)||jsonb_build_object('updated_at',v_product.updated_at);
 update public.products set spec_template_id=p_template_id,updated_at=clock_timestamp()
   where id=p_product_id and tenant_id=v_tenant;
 -- Validate the new active field graph and reference identity, without writing
 -- or deleting any facts, option links, readings, categories or operational data.
 perform public.spec_validate_product_internal_v1(p_product_id);
 select jsonb_build_object('product',to_jsonb(p),'before',v_before,
   'after',public.get_product_spec_snapshot_v1(p.id),'review_reason',p_reason,
   'actor_id',auth.uid(),'replayed',false) into v_result from public.products p where p.id=p_product_id;
 insert into public.product_spec_save_receipts(tenant_id,operation_key,request_hash,result)
 values(v_tenant,p_operation_key,v_hash,v_result);
 return v_result;
exception when foreign_key_violation then
 raise exception 'La plantilla dejó de estar disponible. Recarga antes de asignarla.' using errcode='23514';
end $$;
revoke all on function public.assign_product_spec_template_v1(uuid,uuid,bigint,timestamptz,text,text) from public,anon;
grant execute on function public.assign_product_spec_template_v1(uuid,uuid,bigint,timestamptz,text,text) to authenticated;

-- Shared readers/writers and revision guards follow below.

CREATE OR REPLACE FUNCTION public.get_product_spec_snapshot_v1(p_product_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_result jsonb;
begin
  select jsonb_build_object('revision',p.spec_revision,'reference_id',p.spec_reference_id,
    'category_id',p.category_id,'template_id',b.template_id,'explicit_template_id',p.spec_template_id,
    'template_key',b.template_key,'technical_family',b.technical_family,'contract_version',b.contract_version,
    'binding_source',b.binding_source,'unassigned_facts',public.spec_unassigned_facts_internal_v1(p.id,b.template_id),'catalog_keys',(select coalesce(jsonb_agg(d.key),'[]'::jsonb) from public.spec_facts f join public.spec_definitions d on d.id = f.spec_definition_id where f.subject_type = 'product' and f.subject_id = p.id and f.subject_scope is null and f.source = 'catalog' and exists(select 1 from public.spec_template_fields tf where tf.template_id=b.template_id and tf.spec_definition_id=f.spec_definition_id)),'values',public.spec_payload_display_internal_v1(public.spec_template_product_payload_internal_v1(p.id,b.template_id,true)))
    into v_result from public.products p left join public.product_spec_bindings_internal_v1 b on b.product_id=p.id where p.id = p_product_id and p.tenant_id = public.user_tenant_id()
      and auth.uid() is not null;
  if v_result is null then raise exception 'Producto no disponible para este tenant' using errcode = '42501'; end if;
  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION public.get_product_spec_contexts_v1(p_product_ids uuid[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_object_agg(p.id, coalesce(v.facts,'{}'::jsonb) || jsonb_build_object(
    '__reference_claims',coalesce(r.claims,'[]'::jsonb),
    '__technical_family',b.technical_family,'__template_key',b.template_key,'__template_id',b.template_id,
    '__binding_source',b.binding_source,
    '__unassigned_facts',public.spec_unassigned_facts_internal_v1(p.id,b.template_id),
    '__spec_issues',case when b.binding_source='explicit_unavailable' then '[{"code":"template_unavailable"}]'::jsonb when t.id is null then '[{"code":"unmapped"}]'::jsonb
      else public.spec_validate_draft_internal_v1(t.id,v.facts,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) end)), '{}')
  from public.products p
  left join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
  left join public.spec_templates t on t.id=b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
  left join public.product_spec_references r on r.id=p.spec_reference_id
  cross join lateral (select public.spec_active_product_values_internal_v1(p.id,t.id) facts) v
  where p.id=any(p_product_ids) and p.tenant_id=public.user_tenant_id() and auth.uid() is not null
$function$;

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
  if exists(select 1 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
    where f.subject_type='product' and f.subject_id=p_product_id and f.subject_scope is null and (
      (d.data_type='number' and (f.value_boolean is not null or f.value_text is not null)) or
      (d.data_type='boolean' and (f.value_number is not null or f.value_text is not null)) or
      (d.data_type not in ('number','boolean','single_select','multi_select') and (f.value_number is not null or f.value_boolean is not null)) or
      (d.data_type in ('single_select','multi_select') and num_nonnulls(f.value_number,f.value_boolean,f.value_text)>0) or
      exists(select 1 from public.spec_fact_values fv join public.spec_definition_values v on v.id=fv.value_id
        where fv.fact_id=f.id and (v.spec_definition_id<>f.spec_definition_id or d.data_type not in ('single_select','multi_select'))) or
      (d.data_type='single_select' and (select count(*) from public.spec_fact_values fv where fv.fact_id=f.id)>1)
    )) then raise exception 'Invalid specification shape or option ownership' using errcode='23514'; end if;
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

CREATE OR REPLACE FUNCTION public.get_public_product_technical_specs(p_tenant_id uuid, p_product_id uuid)
 RETURNS TABLE(section_key text, section_sort_order integer, field_sort_order integer, spec_key text, spec_label text, display_value text, unit text, data_type text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
  with visible as (
    select p.id,p.brand,p.model,p.manufacturer_sku,p.spec_reference_id,t.id template_id,t.form_contract
    from public.products p
    join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
    join public.spec_templates t on t.id=b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
    where p.id=p_product_id and p.tenant_id=p_tenant_id and coalesce(p.is_active,true)
      and coalesce(p.is_published,false) and coalesce(p.show_on_website,false)
  ), facts as (
    select p.*,public.spec_active_product_values_internal_v1(p.id,p.template_id) vals from visible p
  ), assessed as (select p.*,public.spec_validate_draft_internal_v1(p.template_id,p.vals,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) issues from facts p
  ), fields as (
    select f.section_key,f.sort_order,d.key,coalesce(p.form_contract->'labels'->>d.key,d.label) label,
      d.unit,d.data_type,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  )
  select f.section_key,dense_rank() over(order by f.section_order,f.section_key)::integer,
    f.sort_order,f.key,f.label,case
      when jsonb_typeof(f.val)='array' then (select string_agg(e,', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      else f.val#>>'{}' end,f.unit,f.data_type
  from fields f order by f.section_order,f.sort_order,f.label
$function$;

CREATE OR REPLACE FUNCTION public.save_product_with_specs_v1(p_product jsonb, p_is_new boolean, p_template_id uuid, p_contract_version integer, p_values jsonb, p_expected_revision bigint, p_reference_id text, p_operation_key text, p_expected_updated_at timestamp with time zone, p_components jsonb DEFAULT NULL::jsonb)
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
    v_product.spec_template_id);
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
  perform public.spec_validate_product_internal_v1(v_id);
  select jsonb_build_object('product',to_jsonb(p),'revision',p.spec_revision,'replayed',false)
    into v_result from public.products p where p.id = v_id and p.tenant_id = v_tenant;
  if v_set is not null then v_result := v_result || jsonb_build_object('set',v_set || jsonb_build_object('parent',v_result->'product')); end if;
  insert into public.product_spec_save_receipts(tenant_id,operation_key,request_hash,result)
    values(v_tenant,p_operation_key,v_hash,v_result);
  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION public.save_product_spec_facts_v1(p_product_id uuid, p_definition_ids uuid[], p_values jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_tenant uuid := public.user_tenant_id();
  v_definicion uuid;
  v_tipo text;
  v_entrada jsonb;
  v_fact uuid;
  v_escritos integer := 0;
begin
  if v_tenant is null then
    raise exception 'sin tenant' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.products
    where id = p_product_id and tenant_id = v_tenant
  ) then
    raise exception 'el producto no pertenece a este tenant' using errcode = '42501';
  end if;

  -- **La misma llave que toma la lectura, y antes de tocar nada.** Vaciar un
  -- criterio es lo primero que hace esta función; sin el candado acá, una
  -- lectura en vuelo podía reinsertar justo el campo que la persona acababa de
  -- vaciar, y el resultado quedaba escrito por el lector aunque la persona
  -- hubiera llegado después.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant::text || ':spec_fact:' || p_product_id::text, 0));

  if jsonb_typeof(p_values) is distinct from 'object' or p_definition_ids is null then
    raise exception 'Invalid specification payload' using errcode = '22023';
  end if;
  if exists(select 1 from unnest(p_definition_ids) d where not exists(
    select 1 from public.spec_definitions sd where sd.id=d and (sd.tenant_id is null or sd.tenant_id=v_tenant)))
    or exists(select 1 from jsonb_object_keys(p_values) k where not k = any(array(select d::text from unnest(p_definition_ids) d))) then
    raise exception 'Unknown or foreign specification definition' using errcode = '23514';
  end if;
  if exists(select 1 from public.product_spec_bindings_internal_v1 b where b.product_id=p_product_id and b.template_id is not null)
    and exists(select 1 from unnest(p_definition_ids) d where not exists(
      select 1 from public.product_spec_bindings_internal_v1 b
      join public.spec_template_fields tf on tf.template_id=b.template_id
      where b.product_id=p_product_id and tf.spec_definition_id=d)) then
    raise exception 'La respuesta no pertenece a esta plantilla' using errcode = '23514';
  end if;
  for v_definicion in select unnest(p_definition_ids) loop
    v_entrada := p_values->v_definicion::text;
    continue when v_entrada is null;
    select data_type into strict v_tipo from public.spec_definitions where id=v_definicion;
    if v_tipo in ('single_select','multi_select') then
      if jsonb_typeof(v_entrada->'labels') is distinct from 'array'
        or jsonb_array_length(v_entrada->'labels')=0
        or (v_tipo='single_select' and jsonb_array_length(v_entrada->'labels')<>1) then
        raise exception 'Invalid option cardinality' using errcode = '23514';
      end if;
      if (select count(distinct v.id) from jsonb_array_elements_text(v_entrada->'labels') a(label)
        join public.spec_definition_values v on v.spec_definition_id=v_definicion and v.label=a.label)
        <> jsonb_array_length(v_entrada->'labels') then
        raise exception 'Unknown or duplicate specification option' using errcode = '23514';
      end if;
    elsif v_tipo='number' and jsonb_typeof(v_entrada->'number') is distinct from 'number' then
      raise exception 'Expected numeric specification value' using errcode = '23514';
    elsif v_tipo='boolean' and jsonb_typeof(v_entrada->'boolean') is distinct from 'boolean' then
      raise exception 'Expected boolean specification value' using errcode = '23514';
    end if;
  end loop;

  -- Lo que la plantilla incluye y el payload no trae, se borra: vaciar un
  -- campo es parte de guardar, no una operación aparte.
  delete from public.spec_facts f
  where f.tenant_id = v_tenant and f.subject_type = 'product'
    and f.subject_id = p_product_id and f.subject_scope is null
    and f.spec_definition_id = any(p_definition_ids)
    and not (p_values ? f.spec_definition_id::text);

  for v_definicion in
    select unnest(p_definition_ids)
  loop
    v_entrada := p_values -> v_definicion::text;
    continue when v_entrada is null;

    select data_type into v_tipo from public.spec_definitions where id = v_definicion;
    continue when v_tipo is null;

    insert into public.spec_facts (
      tenant_id, subject_type, subject_id, spec_definition_id,
      value_number, value_boolean, value_text, source, confirmed
    ) values (
      v_tenant, 'product', p_product_id, v_definicion,
      case when v_tipo = 'number'
           then nullif(v_entrada ->> 'number', '')::numeric end,
      case when v_tipo = 'boolean'
           then (v_entrada ->> 'boolean')::boolean end,
      case when v_tipo not in ('number','boolean','single_select','multi_select')
           then nullif(v_entrada ->> 'text', '') end,
      'mechanic', false
    )
    on conflict (tenant_id, subject_type, subject_id, spec_definition_id,
                 coalesce(subject_scope, ''))
    do update set
      value_number = excluded.value_number,
      value_boolean = excluded.value_boolean,
      value_text = excluded.value_text,
      -- **La persona gana de verdad.** Sin esto, guardar encima de una lectura
      -- del nombre dejaba el valor del mecanico con `source = 'name_reading'`
      -- y con el recibo de una cita que ya no lo sostiene: procedencia y
      -- respaldo falsos, y ademas el hecho caducaba solo al cambiar el nombre
      -- del producto, borrando en silencio lo que una persona escribio.
      source = excluded.source,
      confirmed = excluded.confirmed,
      updated_at = now()
    returning id into v_fact;

    -- El recibo se retira: ya no hay ninguna lectura que respaldar.
    delete from public.spec_fact_readings where fact_id = v_fact;
    delete from public.spec_fact_values where fact_id = v_fact;

    if v_tipo in ('single_select','multi_select')
       and jsonb_typeof(v_entrada -> 'labels') = 'array' then
      insert into public.spec_fact_values (fact_id, value_id, position)
      select v_fact, sv.id, (elem.ordinality - 1)::integer
      from jsonb_array_elements_text(v_entrada -> 'labels')
        with ordinality as elem(etiqueta, ordinality)
      join public.spec_definition_values sv
        on sv.spec_definition_id = v_definicion and sv.label = elem.etiqueta
      on conflict do nothing;
    end if;

    v_escritos := v_escritos + 1;
  end loop;

  perform public.spec_validate_product_internal_v1(p_product_id);
  return v_escritos;
end;
$function$;

CREATE OR REPLACE FUNCTION public.spec_product_revision_internal_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_subject uuid; v_type text;
begin
  if tg_table_name = 'products' then
    if (new.brand,new.model,new.manufacturer_sku,new.category_id,new.spec_reference_id,new.spec_template_id)
      is distinct from (old.brand,old.model,old.manufacturer_sku,old.category_id,old.spec_reference_id,old.spec_template_id) then
      new.spec_revision := old.spec_revision + 1;
    elsif pg_trigger_depth() > 1 and new.spec_revision = old.spec_revision + 1 then
      null; -- Only a nested fact trigger may increment without identity change.
    else
      new.spec_revision := old.spec_revision;
    end if;
    return new;
  elsif tg_table_name = 'spec_facts' then
    if tg_op = 'DELETE' then v_subject := old.subject_id; v_type := old.subject_type;
    else v_subject := new.subject_id; v_type := new.subject_type; end if;
  else
    select f.subject_id,f.subject_type into v_subject,v_type from public.spec_facts f
      where f.id = case when tg_op = 'DELETE' then old.fact_id else new.fact_id end;
  end if;
  if v_type = 'product' then
    update public.products set spec_revision = spec_revision + 1 where id = v_subject;
  end if;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.spec_product_constraint_internal_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_subject uuid; v_type text;
begin
  if tg_table_name = 'products' then
    if tg_op = 'UPDATE' and (new.brand,new.model,new.manufacturer_sku,new.category_id,new.spec_reference_id,new.spec_template_id)
      is not distinct from (old.brand,old.model,old.manufacturer_sku,old.category_id,old.spec_reference_id,old.spec_template_id) then return null; end if;
    v_subject := new.id; v_type := 'product';
  elsif tg_table_name = 'spec_facts' then
    if tg_op = 'DELETE' then v_subject := old.subject_id; v_type := old.subject_type;
    else v_subject := new.subject_id; v_type := new.subject_type; end if;
  else
    select f.subject_id,f.subject_type into v_subject,v_type from public.spec_facts f
      where f.id = case when tg_op = 'DELETE' then old.fact_id else new.fact_id end;
  end if;
  if v_type = 'product' then perform public.spec_validate_product_internal_v1(v_subject); end if;
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.assistant_search_inventory_v4(p_query text, p_category text, p_availability text, p_technical_filters jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_query text;
  v_category text;
  v_filter jsonb;
  v_filter_field text;
  v_filter_value text;
  v_filter_fields text[] := array[]::text[];
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  if octet_length(coalesce(p_query, '')) not between 1 and 240
     or octet_length(coalesce(p_category, '')) > 160
     or p_availability not in (
       'any', 'in_stock', 'low_stock', 'out_of_stock'
     )
     or jsonb_typeof(p_technical_filters) <> 'array'
     or jsonb_array_length(p_technical_filters) > 6 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category),
    ''
  );
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  if v_category is not null and not exists (
    select 1
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      )
  ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  for v_filter in
    select value from jsonb_array_elements(p_technical_filters) item(value)
  loop
    if jsonb_typeof(v_filter) <> 'object'
       or not (v_filter ? 'field' and v_filter ? 'value')
       or jsonb_typeof(v_filter -> 'field') <> 'string'
       or jsonb_typeof(v_filter -> 'value') <> 'string'
       or exists (
         select 1 from jsonb_object_keys(v_filter) key
         where key not in ('field', 'value')
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_filter_field := btrim(v_filter ->> 'field');
    v_filter_value := btrim(v_filter ->> 'value');
    if v_filter_field !~ '^[a-z][a-z0-9_]{1,63}$'
       or octet_length(v_filter_value) not between 1 and 120
       or v_filter_field = any(v_filter_fields)
       or not exists (
         select 1
         from public.spec_definitions definition
         where definition.key = v_filter_field
           and (definition.tenant_id is null
             or definition.tenant_id = v_authority.tenant_id)
           and definition.is_filterable is true
           and (
             jsonb_array_length(definition.allowed_values) = 0
             or exists (
               select 1
               from jsonb_array_elements(definition.allowed_values) allowed(value)
               where jsonb_typeof(allowed.value) = 'string'
                 and public.assistant_normalize_query_internal_v1(
                   allowed.value #>> '{}'
                 ) = public.assistant_normalize_query_internal_v1(v_filter_value)
             )
           )
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_filter_fields := array_append(v_filter_fields, v_filter_field);
  end loop;

  with requested_filters as materialized (
    select
      filter.ordinality,
      filter.value ->> 'field' field_key,
      coalesce((
        select allowed.value #>> '{}'
        from public.spec_definitions definition
        cross join jsonb_array_elements(definition.allowed_values) allowed(value)
        where definition.key = filter.value ->> 'field'
          and (definition.tenant_id is null
            or definition.tenant_id = v_authority.tenant_id)
          and definition.is_filterable is true
          and jsonb_typeof(allowed.value) = 'string'
          and public.assistant_normalize_query_internal_v1(
            allowed.value #>> '{}'
          ) = public.assistant_normalize_query_internal_v1(
            filter.value ->> 'value'
          )
        order by (definition.tenant_id is not null) desc
        limit 1
      ), filter.value ->> 'value') canonical_value
    from jsonb_array_elements(p_technical_filters)
      with ordinality filter(value, ordinality)
  ), category_scope as materialized (
    select distinct category.id category_id, mapping.technical_family
    from public.product_categories category
    left join public.category_spec_template_scope_internal_v1 mapping
      on mapping.tenant_id = category.tenant_id
     and mapping.category_id = category.id
     and mapping.status = 'active'
    where v_category is not null
      and category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      )
  ), product_surfaces as materialized (
    select
      product.id entity_id,
      product.category_id,
      mapping.technical_family,
      product.name,
      product.sku,
      product.brand,
      product.category_name,
      product.category,
      product.price,
      product.warehouse_location,
      product.updated_at,
      coalesce(product.track_stock, false) tracks_inventory,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
      case
        when coalesce(product.is_set, false)
          then coalesce(product.full_sets_available, 0)
        else coalesce(product.stock_quantity, product.inventory_qty, 0)
      end available_stock,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.sku, product.barcode, product.brand,
        product.model, product.manufacturer, product.category_name,
        product.category, product.description
      )) search_surface,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.brand, product.model, product.manufacturer,
        product.category_name, product.category
      )) identity_surface,
      unaccent(lower(concat_ws(' ',
        product.name, product.brand, product.model, product.manufacturer,
        product.category_name, product.category
      ))) identity_raw,
      public.assistant_normalize_query_internal_v1(product.sku) sku_exact,
      public.assistant_normalize_query_internal_v1(product.barcode) barcode_exact
    from public.products_with_sets product
    left join public.product_spec_bindings_internal_v1 mapping
        on mapping.tenant_id = product.tenant_id and mapping.product_id = product.id
    where product.tenant_id = v_authority.tenant_id
      and product.is_active is true
  ), scoped as materialized (
    select
      product.*,
      filter_state.technical_match
    from product_surfaces product
    cross join lateral (
      select
        coalesce(bool_and(source.value in ('product_spec', 'identity_fallback')), true)
          filters_match,
        case
          when count(*) = 0 then 'not_applicable'
          when bool_and(source.value = 'product_spec') then 'product_spec'
          else 'identity_fallback'
        end technical_match
      from requested_filters filter
      cross join lateral (
        select public.assistant_inventory_technical_filter_source_internal_v1(
          v_authority.tenant_id,
          product.entity_id,
          filter.field_key,
          filter.canonical_value,
          product.identity_surface,
          product.identity_raw
        ) value
      ) source
    ) filter_state
    where filter_state.filters_match
      and (
        v_category is null
        or exists (
          select 1
          from category_scope scope
          where (
            scope.technical_family is not null
            and scope.technical_family = product.technical_family
          ) or (
            scope.technical_family is null
            and scope.category_id = product.category_id
          )
        )
      )
      and not exists (
        select 1
        from regexp_split_to_table(v_query, ' +') token
        where case
          when token ~ '[0-9]' then not (
            position(' ' || token || ' ' in
              ' ' || product.identity_surface || ' ') > 0
            or (
              token ~ '^[0-9]+$'
              and product.identity_raw ~ (
                '(^|[^0-9])' || token || '([^0-9]|$)'
              )
            )
            or product.sku_exact = token
            or product.barcode_exact = token
          )
          else position(token in product.search_surface) = 0
        end
      )
  ), matched as materialized (
    select
      scoped.*,
      case
        when not tracks_inventory then 'not_tracked'
        when available_stock <= 0 then 'out_of_stock'
        when available_stock <= minimum_stock then 'low_stock'
        else 'in_stock'
      end availability
    from scoped
    where p_availability = 'any'
       or (p_availability = 'in_stock'
         and tracks_inventory and available_stock > 0)
       or (p_availability = 'low_stock'
         and tracks_inventory and available_stock > 0
         and available_stock <= minimum_stock)
       or (p_availability = 'out_of_stock'
         and tracks_inventory and available_stock <= 0)
    order by
      (public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
      (position(v_query in public.assistant_normalize_query_internal_v1(name)) > 0) desc,
      updated_at desc nulls last,
      name
    limit 11
  ), numbered as (
    select
      entity_id, name, sku, brand, category_name, category, price,
      warehouse_location, available_stock, minimum_stock, availability,
      tracks_inventory, technical_match,
      row_number() over (
        order by
          (public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
          (position(v_query in public.assistant_normalize_query_internal_v1(name)) > 0) desc,
          updated_at desc nulls last,
          name
      ) ordinal
    from matched
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160),
      'sku', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(sku, ''), 80), ''),
      'brand', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(brand, ''), 100), ''),
      'category', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(category_name, category, ''), 100), ''),
      'price', price,
      'stock', available_stock,
      'minimumStock', minimum_stock,
      'availability', availability,
      'tracksInventory', tracks_inventory,
      'location', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(warehouse_location, ''), 120), ''),
      'technicalMatch', technical_match
    ) order by ordinal) filter (where ordinal <= 10), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    v_items,
    v_total > 10
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_search_inventory_v5(p_query text, p_category text, p_availability text, p_technical_predicates jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_query text;
  v_category text;
  v_predicate jsonb;
  v_field text;
  v_operator text;
  v_values jsonb;
  v_definition record;
  v_fields text[] := array[]::text[];
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.operational') authority;

  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or p_availability not in ('any', 'in_stock', 'low_stock', 'out_of_stock')
     or jsonb_typeof(p_technical_predicates) <> 'array'
     or jsonb_array_length(p_technical_predicates) > 8 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_category := nullif(public.assistant_normalize_query_internal_v1(p_category), '');
  if v_query is null and v_category is null
     and jsonb_array_length(p_technical_predicates) = 0 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  if v_category is not null and not exists (
    select 1 from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category)
  ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  for v_predicate in
    select value from jsonb_array_elements(p_technical_predicates) item(value)
  loop
    if jsonb_typeof(v_predicate) <> 'object'
       or not (v_predicate ? 'field' and v_predicate ? 'operator'
         and v_predicate ? 'values')
       or jsonb_typeof(v_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_predicate -> 'values') <> 'array'
       or exists (select 1 from jsonb_object_keys(v_predicate) key
         where key not in ('field', 'operator', 'values')) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_field := btrim(v_predicate ->> 'field');
    v_operator := v_predicate ->> 'operator';
    v_values := v_predicate -> 'values';
    select definition.data_type, definition.allowed_values
    into v_definition
    from public.spec_definitions definition
    where definition.key = v_field
      and (definition.tenant_id is null or definition.tenant_id = v_authority.tenant_id)
      and definition.is_filterable is true
    order by (definition.tenant_id is not null) desc
    limit 1;
    if not found
       or v_field !~ '^[a-z][a-z0-9_]{1,63}$'
       or v_field = any(v_fields)
       or v_operator not in ('eq','neq','lt','lte','gt','gte','between','in','contains')
       or jsonb_array_length(v_values) not between 1 and 10
       or (v_operator = 'between' and jsonb_array_length(v_values) <> 2)
       or (v_operator not in ('between','in') and jsonb_array_length(v_values) <> 1)
       or (v_definition.data_type = 'number' and (
         v_operator not in ('eq','neq','lt','lte','gt','gte','between','in')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'number')
       ))
       or (v_definition.data_type = 'boolean' and (
         v_operator not in ('eq','neq')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'boolean')
       ))
       or (v_definition.data_type in ('single_select','multi_select') and (
         v_operator not in ('eq','neq','in')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or (jsonb_array_length(v_definition.allowed_values) > 0 and not exists (
               select 1 from jsonb_array_elements(v_definition.allowed_values) allowed(value)
               where public.assistant_normalize_query_internal_v1(
                 allowed.value #>> '{}'
               ) = public.assistant_normalize_query_internal_v1(
                 requested.value #>> '{}'
               )
             )))
       ))
       or (v_definition.data_type = 'text' and (
         v_operator not in ('eq','neq','in','contains')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or octet_length(requested.value #>> '{}') not between 1 and 120)
       ))
       or v_definition.data_type not in (
         'number','boolean','single_select','multi_select','text'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_fields := array_append(v_fields, v_field);
  end loop;

  with recursive selected_category as materialized (
    select category.id, category.name, category.full_path
    from public.product_categories category
    where v_category is not null
      and category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category)
    order by (public.assistant_normalize_query_internal_v1(category.full_path) = v_category) desc,
      category.level desc
    limit 1
  ), category_scope as (
    select selected.id from selected_category selected
    union
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_authority.tenant_id and child.is_active is true
  ), scoped_families as materialized (
    select distinct mapping.technical_family
    from category_scope scope
    join public.category_spec_template_scope_internal_v1 mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    where mapping.technical_family is not null
  ), requested_predicates as materialized (
    select predicate.value ->> 'field' field_key,
      predicate.value ->> 'operator' operator,
      predicate.value -> 'values' values
    from jsonb_array_elements(p_technical_predicates) predicate(value)
  ), product_surfaces as materialized (
    select product.id entity_id, product.category_id,
      mapping.technical_family, product.name, product.sku, product.brand,
      product.category_name, product.category, product.price,
      product.warehouse_location, product.updated_at,
      coalesce(product.track_stock, false) tracks_inventory,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
      case when coalesce(product.is_set, false)
        then coalesce(product.full_sets_available, 0)
        else coalesce(product.stock_quantity, product.inventory_qty, 0)
      end available_stock,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.sku, product.barcode, product.brand,
        product.model, product.manufacturer, product.category_name,
        product.category, product.description
      )) search_surface,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.brand, product.model, product.manufacturer,
        product.category_name, product.category
      )) identity_surface,
      unaccent(lower(concat_ws(' ', product.name, product.brand,
        product.model, product.manufacturer, product.category_name,
        product.category))) identity_raw,
      public.assistant_normalize_query_internal_v1(product.sku) sku_exact,
      public.assistant_normalize_query_internal_v1(product.barcode) barcode_exact
    from public.products_with_sets product
    left join public.product_spec_bindings_internal_v1 mapping
        on mapping.tenant_id = product.tenant_id and mapping.product_id = product.id
    where product.tenant_id = v_authority.tenant_id and product.is_active is true
  ), scoped as materialized (
    select product.*, predicate_state.technical_match
    from product_surfaces product
    cross join lateral (
      select coalesce(bool_and(source.value in (
          'product_spec','identity_fallback'
        )), true) predicates_match,
        case when count(*) = 0 then 'not_applicable'
          when bool_and(source.value = 'product_spec') then 'product_spec'
          else 'identity_fallback' end technical_match
      from requested_predicates predicate
      cross join lateral (
        select public.assistant_inventory_technical_predicate_source_internal_v1(
          v_authority.tenant_id, product.entity_id, predicate.field_key,
          predicate.operator, predicate.values, product.identity_surface,
          product.identity_raw
        ) value
      ) source
    ) predicate_state
    where predicate_state.predicates_match
      and (v_category is null or product.category_id in (select id from category_scope)
        or (product.technical_family is not null and product.technical_family in (
          select technical_family from scoped_families
        )))
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where case when token ~ '[0-9]' then not (
            position(' ' || token || ' ' in ' ' || product.identity_surface || ' ') > 0
            or (token ~ '^[0-9]+$' and product.identity_raw ~ (
              '(^|[^0-9])' || token || '([^0-9]|$)'))
            or product.sku_exact = token or product.barcode_exact = token
          ) else position(token in product.search_surface) = 0 end
      ))
  ), matched as materialized (
    select scoped.*,
      case when not tracks_inventory then 'not_tracked'
        when available_stock <= 0 then 'out_of_stock'
        when available_stock <= minimum_stock then 'low_stock'
        else 'in_stock' end availability
    from scoped
    where p_availability = 'any'
      or (p_availability = 'in_stock' and tracks_inventory and available_stock > 0)
      or (p_availability = 'low_stock' and tracks_inventory
        and available_stock > 0 and available_stock <= minimum_stock)
      or (p_availability = 'out_of_stock' and tracks_inventory and available_stock <= 0)
    order by (v_query is not null and
        public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
      (v_query is not null and position(v_query in
        public.assistant_normalize_query_internal_v1(name)) > 0) desc,
      updated_at desc nulls last, name
    limit 11
  ), numbered as (
    select *, row_number() over (order by
      (v_query is not null and
        public.assistant_normalize_query_internal_v1(sku) = v_query) desc,
      (v_query is not null and position(v_query in
        public.assistant_normalize_query_internal_v1(name)) > 0) desc,
      updated_at desc nulls last, name) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160),
      'sku', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(sku, ''), 80), ''),
      'brand', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(brand, ''), 100), ''),
      'category', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(category_name, category, ''), 100
      ), ''),
      'price', price,
      'stock', available_stock,
      'minimumStock', minimum_stock,
      'availability', availability,
      'tracksInventory', tracks_inventory,
      'location', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(warehouse_location, ''), 120
      ), ''),
      'technicalMatch', technical_match
    ) order by ordinal) filter (where ordinal <= 10), '[]'::jsonb), count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > 10
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_search_inventory_v6(p_query text, p_category text, p_availability text, p_technical_predicates jsonb, p_operational_predicates jsonb, p_sort_field text, p_sort_direction text, p_limit integer, p_selection_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_query text;
  v_category text;
  v_predicate jsonb;
  v_field text;
  v_operator text;
  v_values jsonb;
  v_definition record;
  v_fields text[] := array[]::text[];
  v_operational_predicate jsonb;
  v_operational_field text;
  v_operational_operator text;
  v_operational_values jsonb;
  v_operational_fields text[] := array[]::text[];
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.operational') authority;

  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or p_availability not in ('any', 'in_stock', 'low_stock', 'out_of_stock')
     or jsonb_typeof(p_technical_predicates) <> 'array'
     or jsonb_array_length(p_technical_predicates) > 8
     or jsonb_typeof(p_operational_predicates) <> 'array'
     or jsonb_array_length(p_operational_predicates) > 6
     or p_sort_field not in ('relevance','name','stock','minimum_stock','price')
     or p_sort_direction not in ('asc','desc')
     or (p_sort_field = 'relevance' and p_sort_direction <> 'desc')
     or p_limit not between 1 and 10
     or p_selection_mode not in ('all_matches','top_n') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_category := nullif(public.assistant_normalize_query_internal_v1(p_category), '');
  if v_category is not null and not exists (
    select 1 from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category)
  ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  for v_predicate in
    select value from jsonb_array_elements(p_technical_predicates) item(value)
  loop
    if jsonb_typeof(v_predicate) <> 'object'
       or not (v_predicate ? 'field' and v_predicate ? 'operator'
         and v_predicate ? 'values')
       or jsonb_typeof(v_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_predicate -> 'values') <> 'array'
       or exists (select 1 from jsonb_object_keys(v_predicate) key
         where key not in ('field', 'operator', 'values')) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_field := btrim(v_predicate ->> 'field');
    v_operator := v_predicate ->> 'operator';
    v_values := v_predicate -> 'values';
    select definition.data_type, definition.allowed_values
    into v_definition
    from public.spec_definitions definition
    where definition.key = v_field
      and (definition.tenant_id is null or definition.tenant_id = v_authority.tenant_id)
      and definition.is_filterable is true
    order by (definition.tenant_id is not null) desc
    limit 1;
    if not found
       or v_field !~ '^[a-z][a-z0-9_]{1,63}$'
       or v_field = any(v_fields)
       or v_operator not in ('eq','neq','lt','lte','gt','gte','between','in','contains')
       or jsonb_array_length(v_values) not between 1 and 10
       or (v_operator = 'between' and jsonb_array_length(v_values) <> 2)
       or (v_operator not in ('between','in') and jsonb_array_length(v_values) <> 1)
       or (v_definition.data_type = 'number' and (
         v_operator not in ('eq','neq','lt','lte','gt','gte','between','in')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'number')
       ))
       or (v_definition.data_type = 'boolean' and (
         v_operator not in ('eq','neq')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'boolean')
       ))
       or (v_definition.data_type in ('single_select','multi_select') and (
         v_operator not in ('eq','neq','in')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or (jsonb_array_length(v_definition.allowed_values) > 0 and not exists (
               select 1 from jsonb_array_elements(v_definition.allowed_values) allowed(value)
               where public.assistant_normalize_query_internal_v1(
                 allowed.value #>> '{}'
               ) = public.assistant_normalize_query_internal_v1(
                 requested.value #>> '{}'
               )
             )))
       ))
       or (v_definition.data_type = 'text' and (
         v_operator not in ('eq','neq','in','contains')
         or exists (select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or octet_length(requested.value #>> '{}') not between 1 and 120)
       ))
       or v_definition.data_type not in (
         'number','boolean','single_select','multi_select','text'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_fields := array_append(v_fields, v_field);
  end loop;

  for v_operational_predicate in
    select value from jsonb_array_elements(p_operational_predicates) item(value)
  loop
    if jsonb_typeof(v_operational_predicate) <> 'object'
       or not (v_operational_predicate ? 'field'
         and v_operational_predicate ? 'operator'
         and v_operational_predicate ? 'values')
       or jsonb_typeof(v_operational_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_operational_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_operational_predicate -> 'values') <> 'array'
       or exists (select 1 from jsonb_object_keys(v_operational_predicate) key
         where key not in ('field', 'operator', 'values')) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_operational_field := btrim(v_operational_predicate ->> 'field');
    v_operational_operator := v_operational_predicate ->> 'operator';
    v_operational_values := v_operational_predicate -> 'values';
    if v_operational_field not in ('stock', 'minimum_stock', 'price')
       or v_operational_field = any(v_operational_fields)
       or v_operational_operator not in (
         'eq','neq','lt','lte','gt','gte','between','in'
       )
       or jsonb_array_length(v_operational_values) not between 1 and 10
       or (v_operational_operator = 'between'
         and jsonb_array_length(v_operational_values) <> 2)
       or (v_operational_operator not in ('between','in')
         and jsonb_array_length(v_operational_values) <> 1)
       or exists (
         select 1
         from jsonb_array_elements(v_operational_values) requested(value)
         where jsonb_typeof(requested.value) <> 'number'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_operational_fields := array_append(
      v_operational_fields, v_operational_field
    );
  end loop;

  with recursive selected_category as materialized (
    select category.id, category.name, category.full_path
    from public.product_categories category
    where v_category is not null
      and category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category)
    order by (public.assistant_normalize_query_internal_v1(category.full_path) = v_category) desc,
      category.level desc
    limit 1
  ), category_scope as (
    select selected.id from selected_category selected
    union
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = v_authority.tenant_id and child.is_active is true
  ), scoped_families as materialized (
    select distinct mapping.technical_family
    from category_scope scope
    join public.category_spec_template_scope_internal_v1 mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    where mapping.technical_family is not null
  ), requested_predicates as materialized (
    select predicate.value ->> 'field' field_key,
      predicate.value ->> 'operator' operator,
      predicate.value -> 'values' values
    from jsonb_array_elements(p_technical_predicates) predicate(value)
  ), requested_operational_predicates as materialized (
    select predicate.value ->> 'field' field_key,
      predicate.value ->> 'operator' operator,
      predicate.value -> 'values' values
    from jsonb_array_elements(p_operational_predicates) predicate(value)
  ), product_surfaces as materialized (
    select product.id entity_id, product.category_id,
      mapping.technical_family, product.name, product.sku, product.brand,
      product.category_name, product.category, product.price,
      product.warehouse_location, product.updated_at,
      coalesce(product.track_stock, false) tracks_inventory,
      greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
      case when coalesce(product.is_set, false)
        then coalesce(product.full_sets_available, 0)
        else coalesce(product.stock_quantity, product.inventory_qty, 0)
      end available_stock,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.sku, product.barcode, product.brand,
        product.model, product.manufacturer, product.category_name,
        product.category, product.description
      )) search_surface,
      public.assistant_normalize_query_internal_v1(concat_ws(' ',
        product.name, product.brand, product.model, product.manufacturer,
        product.category_name, product.category
      )) identity_surface,
      unaccent(lower(concat_ws(' ', product.name, product.brand,
        product.model, product.manufacturer, product.category_name,
        product.category))) identity_raw,
      public.assistant_normalize_query_internal_v1(product.sku) sku_exact,
      public.assistant_normalize_query_internal_v1(product.barcode) barcode_exact
    from public.products_with_sets product
    left join public.product_spec_bindings_internal_v1 mapping
        on mapping.tenant_id = product.tenant_id and mapping.product_id = product.id
    where product.tenant_id = v_authority.tenant_id and product.is_active is true
  ), scoped as materialized (
    select product.*, predicate_state.technical_match
    from product_surfaces product
    cross join lateral (
      select coalesce(bool_and(source.value in (
          'product_spec','identity_fallback'
        )), true) predicates_match,
        case when count(*) = 0 then 'not_applicable'
          when bool_and(source.value = 'product_spec') then 'product_spec'
          else 'identity_fallback' end technical_match
      from requested_predicates predicate
      cross join lateral (
        select public.assistant_inventory_technical_predicate_source_internal_v1(
          v_authority.tenant_id, product.entity_id, predicate.field_key,
          predicate.operator, predicate.values, product.identity_surface,
          product.identity_raw
        ) value
      ) source
    ) predicate_state
    where predicate_state.predicates_match
      and (v_category is null or product.category_id in (select id from category_scope)
        or (product.technical_family is not null and product.technical_family in (
          select technical_family from scoped_families
        )))
      and (v_query is null or not exists (
        select 1 from regexp_split_to_table(v_query, ' +') token
        where case when token ~ '[0-9]' then not (
            position(' ' || token || ' ' in ' ' || product.identity_surface || ' ') > 0
            or (token ~ '^[0-9]+$' and product.identity_raw ~ (
              '(^|[^0-9])' || token || '([^0-9]|$)'))
            or product.sku_exact = token or product.barcode_exact = token
          ) else position(token in product.search_surface) = 0 end
      ))
  ), matched as materialized (
    select scoped.*,
      case when not tracks_inventory then 'not_tracked'
        when available_stock <= 0 then 'out_of_stock'
        when available_stock <= minimum_stock then 'low_stock'
        else 'in_stock' end availability
    from scoped
    where (
      p_availability = 'any'
      or (p_availability = 'in_stock' and tracks_inventory and available_stock > 0)
      or (p_availability = 'low_stock' and tracks_inventory
        and available_stock > 0 and available_stock <= minimum_stock)
      or (p_availability = 'out_of_stock' and tracks_inventory and available_stock <= 0)
    )
      and not exists (
        select 1
        from requested_operational_predicates predicate
        cross join lateral (
          select case predicate.field_key
            when 'stock' then scoped.available_stock::numeric
            when 'minimum_stock' then scoped.minimum_stock::numeric
            when 'price' then scoped.price::numeric
            else null::numeric
          end actual_value
        ) actual
        where actual.actual_value is null
          or (predicate.field_key in ('stock', 'minimum_stock')
            and not scoped.tracks_inventory)
          or not case predicate.operator
            when 'eq' then actual.actual_value = (predicate.values ->> 0)::numeric
            when 'neq' then actual.actual_value <> (predicate.values ->> 0)::numeric
            when 'lt' then actual.actual_value < (predicate.values ->> 0)::numeric
            when 'lte' then actual.actual_value <= (predicate.values ->> 0)::numeric
            when 'gt' then actual.actual_value > (predicate.values ->> 0)::numeric
            when 'gte' then actual.actual_value >= (predicate.values ->> 0)::numeric
            when 'between' then actual.actual_value between
              least((predicate.values ->> 0)::numeric,
                (predicate.values ->> 1)::numeric)
              and greatest((predicate.values ->> 0)::numeric,
                (predicate.values ->> 1)::numeric)
            when 'in' then exists (
              select 1
              from jsonb_array_elements_text(predicate.values) requested(value)
              where requested.value::numeric = actual.actual_value
            )
            else false
          end
      )
  ), numbered as (
    select *,
      count(*) over()::integer matched_count,
      count(*) filter (where tracks_inventory) over()::integer tracked_count,
      coalesce(sum(available_stock) filter (where tracks_inventory) over(), 0)::integer
        total_stock,
      coalesce(sum(greatest(available_stock, 0) * price)
        filter (where tracks_inventory) over(), 0)::numeric inventory_retail_value,
      avg(price) over()::numeric average_price,
      min(price) over()::numeric minimum_price,
      max(price) over()::numeric maximum_price,
      row_number() over (order by
        case when p_sort_field = 'stock' and p_sort_direction = 'asc'
          then available_stock end asc nulls last,
        case when p_sort_field = 'stock' and p_sort_direction = 'desc'
          then available_stock end desc nulls last,
        case when p_sort_field = 'minimum_stock' and p_sort_direction = 'asc'
          then minimum_stock end asc nulls last,
        case when p_sort_field = 'minimum_stock' and p_sort_direction = 'desc'
          then minimum_stock end desc nulls last,
        case when p_sort_field = 'price' and p_sort_direction = 'asc'
          then price end asc nulls last,
        case when p_sort_field = 'price' and p_sort_direction = 'desc'
          then price end desc nulls last,
        case when p_sort_field = 'name' and p_sort_direction = 'asc'
          then public.assistant_normalize_query_internal_v1(name) end asc nulls last,
        case when p_sort_field = 'name' and p_sort_direction = 'desc'
          then public.assistant_normalize_query_internal_v1(name) end desc nulls last,
        case when p_sort_field = 'relevance' then
          (v_query is not null and
            public.assistant_normalize_query_internal_v1(sku) = v_query)
        end desc nulls last,
        case when p_sort_field = 'relevance' then
          (v_query is not null and position(v_query in
            public.assistant_normalize_query_internal_v1(name)) > 0)
        end desc nulls last,
        case when p_sort_field = 'relevance' then updated_at end desc nulls last,
        public.assistant_normalize_query_internal_v1(name), entity_id
      ) ordinal
    from matched
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'entityId', entity_id,
      'name', public.assistant_truncate_utf8_internal_v1(name, 160),
      'sku', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(sku, ''), 80), ''),
      'brand', nullif(public.assistant_truncate_utf8_internal_v1(coalesce(brand, ''), 100), ''),
      'category', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(category_name, category, ''), 100
      ), ''),
      'price', price,
      'stock', available_stock,
      'minimumStock', minimum_stock,
      'availability', availability,
      'tracksInventory', tracks_inventory,
      'location', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(warehouse_location, ''), 120
      ), ''),
      'technicalMatch', technical_match,
      'matchedCount', matched_count,
      'trackedCount', tracked_count,
      'totalStock', total_stock,
      'inventoryRetailValue', inventory_retail_value,
      'averagePrice', average_price,
      'minimumPrice', minimum_price,
      'maximumPrice', maximum_price
    ) order by ordinal) filter (where ordinal <= p_limit), '[]'::jsonb),
    coalesce(max(matched_count), 0)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items,
    p_selection_mode = 'all_matches' and v_total > p_limit
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_search_inventory_v7(p_query text, p_category text, p_availability text, p_technical_predicates jsonb, p_operational_predicates jsonb, p_sort_field text, p_sort_direction text, p_limit integer, p_selection_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_query text;
  v_category text;
  v_predicate jsonb;
  v_translated_values jsonb;
  v_untranslated integer;
  v_applied_predicates jsonb := '[]'::jsonb;
  v_dropped_predicates integer := 0;
  v_field text;
  v_operator text;
  v_values jsonb;
  v_definition record;
  v_fields text[] := array[]::text[];
  v_operational_predicate jsonb;
  v_operational_field text;
  v_operational_operator text;
  v_operational_values jsonb;
  v_operational_fields text[] := array[]::text[];
  v_items jsonb;
  v_total integer;
  v_inferred jsonb;
  v_inferred_predicates jsonb;
  v_inferred_categories uuid[];
  v_model_predicates jsonb := '[]'::jsonb;
  v_relaxations integer := 0;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  if octet_length(coalesce(p_query, '')) > 240
     or octet_length(coalesce(p_category, '')) > 160
     or p_availability is null
     or p_availability not in ('any', 'in_stock', 'low_stock', 'out_of_stock')
     or jsonb_typeof(p_technical_predicates) <> 'array'
     or jsonb_array_length(p_technical_predicates) > 8
     or jsonb_typeof(p_operational_predicates) <> 'array'
     or jsonb_array_length(p_operational_predicates) > 6
     or p_sort_field is null
     or p_sort_field not in ('relevance','name','stock','minimum_stock','price','margin','sold_recently')
     or p_sort_direction is null
     or p_sort_direction not in ('asc','desc')
     or (p_sort_field = 'relevance' and p_sort_direction <> 'desc')
     or p_limit not between 1 and 10
     or p_selection_mode is null
     or p_selection_mode not in ('all_matches','top_n') then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := nullif(public.assistant_normalize_query_internal_v1(p_query), '');
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category), ''
  );
  if v_category is not null and not exists (
    select 1
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        public.assistant_normalize_query_internal_v1(category.name) = v_category
        or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      )
  ) then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  for v_predicate in
    select value
    from jsonb_array_elements(p_technical_predicates) item(value)
  loop
    if jsonb_typeof(v_predicate) <> 'object'
       or not (
         v_predicate ? 'field' and v_predicate ? 'operator'
         and v_predicate ? 'values'
       )
       or jsonb_typeof(v_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_predicate -> 'values') <> 'array'
       or exists (
         select 1 from jsonb_object_keys(v_predicate) key
         where key not in ('field', 'operator', 'values')
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_field := btrim(v_predicate ->> 'field');
    v_operator := v_predicate ->> 'operator';
    v_values := v_predicate -> 'values';
    select definition.data_type, definition.allowed_values
    into v_definition
    from public.spec_definitions definition
    where definition.key = v_field
      and (
        definition.tenant_id is null
        or definition.tenant_id = v_authority.tenant_id
      )
      and definition.is_filterable is true
    order by (definition.tenant_id is not null) desc
    limit 1;
    if not found
       or v_field !~ '^[a-z][a-z0-9_]{1,63}$'
       or v_field = any(v_fields)
       or v_operator not in (
         'eq','neq','lt','lte','gt','gte','between','in','contains'
       )
       or jsonb_array_length(v_values) not between 1 and 10
       or (v_operator = 'between' and jsonb_array_length(v_values) <> 2)
       or (
         v_operator not in ('between','in')
         and jsonb_array_length(v_values) <> 1
       )
       or (v_definition.data_type = 'number' and (
         v_operator not in ('eq','neq','lt','lte','gt','gte','between','in')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'number'
         )
       ))
       or (v_definition.data_type = 'boolean' and (
         v_operator not in ('eq','neq')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'boolean'
         )
       ))
       or (v_definition.data_type in ('single_select','multi_select') and (
         v_operator not in ('eq','neq','in','contains')
         or exists (
           select 1
           from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
         )
       ))
       or (v_definition.data_type = 'text' and (
         v_operator not in ('eq','neq','in','contains')
         or exists (
           select 1 from jsonb_array_elements(v_values) requested(value)
           where jsonb_typeof(requested.value) <> 'string'
             or octet_length(requested.value #>> '{}') not between 1 and 120
         )
       ))
       or v_definition.data_type not in (
         'number','boolean','single_select','multi_select','text'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_fields := array_append(v_fields, v_field);

    -- Interpretar antes de actuar. El operador habla como habla: «caja
    -- inglesa», «cuadrado», «hollowtech». El vocabulario guarda la entrada
    -- completa. Traducir eso es trabajo del buscador, no del operador: se
    -- resuelve contra `allowed_values` y recién ahí se filtra.
    if v_definition.data_type in ('single_select', 'multi_select')
       and v_operator in ('eq', 'neq', 'in')
       and jsonb_array_length(v_definition.allowed_values) > 0 then
      -- Un término que calza con varias entradas NO es un problema: es un
      -- filtro más ancho. «cuadrado» calza con JIS y con ISO, y los dos son
      -- cuadrados — se devuelven los dos. Rendirse ahí sería esconderle al
      -- operador stock que sí sirve.
      select jsonb_agg(distinct candidata), count(*) filter (where sin_traduccion)
      into v_translated_values, v_untranslated
      from (
        select
          jsonb_array_elements(
            public.assistant_resolve_select_value_internal_v1(
              v_definition.allowed_values, pedido.value #>> '{}'
            )
          ) as candidata,
          false as sin_traduccion
        from jsonb_array_elements(v_values) as pedido(value)
        union all
        select null::jsonb, true
        from jsonb_array_elements(v_values) as pedido(value)
        where jsonb_array_length(
          public.assistant_resolve_select_value_internal_v1(
            v_definition.allowed_values, pedido.value #>> '{}'
          )
        ) = 0
      ) resolucion
      where candidata is not null or sin_traduccion;

      -- Sólo se descarta el predicado cuando NINGÚN término se pudo traducir.
      -- Pedir tres cosas y equivocarse en una devuelve las otras dos.
      if v_translated_values is null
         or jsonb_array_length(v_translated_values) = 0 then
        v_dropped_predicates := v_dropped_predicates + 1;
        continue;
      end if;

      v_values := v_translated_values;
      -- Con más de una candidata la comparación pasa a ser de pertenencia.
      if v_operator = 'eq' and jsonb_array_length(v_values) > 1 then
        v_operator := 'in';
      end if;
    end if;

    v_applied_predicates := v_applied_predicates || jsonb_build_array(
      jsonb_build_object(
        'field', v_field, 'operator', v_operator, 'values', v_values
      )
    );
  end loop;

  -- El resto de la función filtra con los predicados ya traducidos.
  p_technical_predicates := v_applied_predicates;

  -- El operador escribe una frase, no predicados. Cuando el modelo no arma
  -- ninguno, el servidor traduce esa frase contra el registro de vocabulario y
  -- los hechos reales, y filtra con lo que reconoce. Las palabras que sobran se
  -- descartan: el filtro de texto exige que *cada* palabra esté en el nombre
  -- del producto, así que dejar «dame» o «caja» dentro devolvía cero.
  -- Los productos sin ficha no se pierden: el resolvedor de predicados admite
  -- `identity_fallback`, que reconoce la medida en el propio nombre.
  -- La traducción corre siempre que haya frase, no sólo cuando el modelo se
  -- abstuvo de armar predicados: lo que el modelo mande no puede decidir si el
  -- servidor entiende o no la frase del operador. Los predicados del modelo
  -- mandan sobre su propio campo; la frase sólo aporta los campos que él no
  -- tocó, y el texto libre se reduce a lo que no se pudo traducir.
  if v_query is not null then
    v_inferred := public.assistant_infer_technical_predicates_internal_v1(
      v_authority.tenant_id, p_query
    );
    v_inferred_predicates := coalesce(v_inferred -> 'predicates', '[]'::jsonb);
    -- La frase nombró una rama del catálogo —«discos de freno», «motores»—.
    -- Esas palabras se consumen para que no maten el filtro de texto, así que
    -- tienen que volver como lo que son: un filtro de categoría. Sin esto,
    -- «discos de freno de 160» calzaba 23 productos —siete rotores por ficha y
    -- dieciséis por traer «160» en el nombre, entre ellos bielas y cadenas—.
    select array_agg((category.value #>> '{}')::uuid)
    into v_inferred_categories
    from jsonb_array_elements(
      coalesce(v_inferred -> 'categories', '[]'::jsonb)
    ) category(value);

    v_model_predicates := p_technical_predicates;
    if jsonb_array_length(v_inferred_predicates) > 0 then
      -- Sobre un mismo campo manda el valor deducido, no el del modelo: el
      -- deducido salió de `spec_definition_values`, así que existe con
      -- certeza, mientras que el del modelo es una abreviatura suya —«BSA»
      -- por «BSA / Caja inglesa 34,8 mm (1.37\") x 24»— que al no traducir
      -- filtra a cero. Los campos que la frase no menciona los conserva él.
      select coalesce(jsonb_agg(kept.value), '[]'::jsonb)
      into p_technical_predicates
      from jsonb_array_elements(p_technical_predicates) kept(value)
      where not exists (
        select 1
        from jsonb_array_elements(v_inferred_predicates) inferred(value)
        where inferred.value ->> 'field' = kept.value ->> 'field'
      );
      v_model_predicates := p_technical_predicates;
      p_technical_predicates := v_model_predicates || v_inferred_predicates;
    end if;

    -- El texto se reemplaza por el residuo en cuanto la frase aportó ALGO:
    -- un filtro técnico o el nombre de una rama. «Cuáles son los 5 motores más
    -- caros» no tiene filtro técnico, pero «motores» sí nombra una rama; si el
    -- texto se conservaba, el buscador exigía la palabra «motores» dentro del
    -- nombre del producto y devolvía cero teniendo treinta y cuatro.
    --
    -- Sólo se toca el texto cuando algo se tradujo. Si no, «VP-BC73» sigue
    -- siendo una búsqueda por identidad y no se puede borrar.
    if jsonb_array_length(v_inferred_predicates) > 0
       or v_inferred_categories is not null then
      v_query := nullif(btrim(v_inferred ->> 'residual'), '');
    end if;
  end if;

  for v_operational_predicate in
    select value
    from jsonb_array_elements(p_operational_predicates) item(value)
  loop
    if jsonb_typeof(v_operational_predicate) <> 'object'
       or not (
         v_operational_predicate ? 'field'
         and v_operational_predicate ? 'operator'
         and v_operational_predicate ? 'values'
       )
       or jsonb_typeof(v_operational_predicate -> 'field') <> 'string'
       or jsonb_typeof(v_operational_predicate -> 'operator') <> 'string'
       or jsonb_typeof(v_operational_predicate -> 'values') <> 'array'
       or exists (
         select 1 from jsonb_object_keys(v_operational_predicate) key
         where key not in ('field', 'operator', 'values')
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_operational_field := btrim(v_operational_predicate ->> 'field');
    v_operational_operator := v_operational_predicate ->> 'operator';
    v_operational_values := v_operational_predicate -> 'values';
    if v_operational_field not in ('stock', 'minimum_stock', 'price', 'sold_recently')
       or v_operational_field = any(v_operational_fields)
       or v_operational_operator not in (
         'eq','neq','lt','lte','gt','gte','between','in'
       )
       or jsonb_array_length(v_operational_values) not between 1 and 10
       or (
         v_operational_operator = 'between'
         and jsonb_array_length(v_operational_values) <> 2
       )
       or (
         v_operational_operator not in ('between','in')
         and jsonb_array_length(v_operational_values) <> 1
       )
       or exists (
         select 1
         from jsonb_array_elements(v_operational_values) requested(value)
         where jsonb_typeof(requested.value) <> 'number'
       ) then
      raise exception 'Invalid AI tool arguments' using errcode = '22023';
    end if;
    v_operational_fields := array_append(
      v_operational_fields, v_operational_field
    );
  end loop;

  -- Si la combinación completa no calza nada, el filtro más débil sobra: se
  -- suelta y se vuelve a preguntar. Los predicados deducidos vienen ordenados
  -- por cuánta ficha tiene cargada cada campo, así que el último es siempre el
  -- que menos respalda el catálogo.
  --
  -- Caso real del dueño, 2026-08-21: «caja inglesa de 68 mm con eje cuadrado de
  -- 118 mm» deducía los cuatro filtros correctos y devolvía cero, porque
  -- `spindle_interface_accepted` tiene ficha en cinco productos y ninguno era
  -- un motor. Rendirse ahí es lo contrario de lo que el operador pidió.
  loop
    with recursive selected_category as materialized (
      select category.id, category.name, category.full_path
      from public.product_categories category
      where v_category is not null
        and category.tenant_id = v_authority.tenant_id
        and category.is_active is true
        and (
          public.assistant_normalize_query_internal_v1(category.name) = v_category
          or public.assistant_normalize_query_internal_v1(category.full_path) = v_category
        )
      order by (
        public.assistant_normalize_query_internal_v1(category.full_path) = v_category
      ) desc, category.level desc
      limit 1
    ), category_scope as (
      select selected.id from selected_category selected
      union
      select child.id
      from public.product_categories child
      join category_scope parent on child.parent_id = parent.id
      where child.tenant_id = v_authority.tenant_id
        and child.is_active is true
    ), scoped_families as materialized (
      select distinct mapping.technical_family
      from category_scope scope
      join public.category_spec_template_scope_internal_v1 mapping
        on mapping.tenant_id = v_authority.tenant_id
       and mapping.category_id = scope.id
       and mapping.status = 'active'
      where mapping.technical_family is not null
    ), requested_predicates as materialized (
      select predicate.value ->> 'field' field_key,
        predicate.value ->> 'operator' operator,
        predicate.value -> 'values' values
      from jsonb_array_elements(p_technical_predicates) predicate(value)
    ), requested_operational_predicates as materialized (
      select predicate.value ->> 'field' field_key,
        predicate.value ->> 'operator' operator,
        predicate.value -> 'values' values
      from jsonb_array_elements(p_operational_predicates) predicate(value)
    ), recent_demand as materialized (
      -- La MISMA definición de demanda que usa la reposición: lo vendido y lo
      -- consumido en taller en 90 días. Sin esto, «qué tengo en stock que
      -- nunca se vende» era una carencia declarada, y es plata parada.
      select linea.product_id, sum(linea.quantity) units
      from (
        select (item ->> 'product_id')::uuid product_id,
          coalesce((item ->> 'quantity')::numeric, 0) quantity
        from public.sales_invoices invoice
          cross join lateral jsonb_array_elements(invoice.items) item
        where invoice.tenant_id = v_authority.tenant_id
          and invoice.voided_at is null
          and invoice.date >= current_date - 90
          and jsonb_typeof(invoice.items) = 'array'
          and (item ->> 'product_id') ~ '^[0-9a-f-]{36}$'
        union all
        select job_item.product_id, coalesce(job_item.quantity, 0)
        from public.mechanic_job_items job_item
        where job_item.product_id is not null
          and job_item.created_at >= current_date - 90
      ) linea
      group by linea.product_id
    ), product_surfaces as materialized (
      select product.id entity_id, product.category_id,
        mapping.technical_family, product.name, product.sku, product.brand,
        product.category_name, product.category, product.price,
        -- El costo viaja para poder responder «cuál me deja más margen», que
        -- es una pregunta de negocio corriente y no se podía contestar: el
        -- buscador exponía el precio y no el costo, así que el asistente
        -- declaraba una carencia teniendo el dato en la misma fila.
        product.cost,
        floor(coalesce(demand.units, 0))::integer sold_recently,
        product.warehouse_location, product.updated_at,
        coalesce(product.track_stock, false) tracks_inventory,
        greatest(coalesce(product.min_stock_level, 0), 0) minimum_stock,
        public.inventory_available_quantity_v1(
          product.tenant_id, product.id
        ) available_stock,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.sku, product.barcode, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category, product.description
        )) search_surface,
        public.assistant_normalize_query_internal_v1(concat_ws(' ',
          product.name, product.brand, product.model, product.manufacturer,
          product.category_name, product.category
        )) identity_surface,
        unaccent(lower(concat_ws(' ', product.name, product.brand,
          product.model, product.manufacturer, product.category_name,
          product.category))) identity_raw,
        public.assistant_normalize_query_internal_v1(product.sku) sku_exact,
        public.assistant_normalize_query_internal_v1(product.barcode) barcode_exact
      from public.products_with_sets product
        left join recent_demand demand on demand.product_id = product.id
      left join public.product_spec_bindings_internal_v1 mapping
        on mapping.tenant_id = product.tenant_id and mapping.product_id = product.id
      where product.tenant_id = v_authority.tenant_id
        and product.is_active is true
    ), scoped as materialized (
      select product.*, predicate_state.technical_match
      from product_surfaces product
      cross join lateral (
        select coalesce(bool_and(source.value in (
            'product_spec','identity_fallback'
          )), true) predicates_match,
          case
            when count(*) = 0 then 'not_applicable'
            when bool_and(source.value = 'product_spec') then 'product_spec'
            else 'identity_fallback'
          end technical_match
        from requested_predicates predicate
        cross join lateral (
          select public.assistant_inventory_technical_predicate_source_internal_v1(
            v_authority.tenant_id, product.entity_id, predicate.field_key,
            predicate.operator, predicate.values, product.identity_surface,
            product.identity_raw
          ) value
        ) source
      ) predicate_state
      where predicate_state.predicates_match
        and (
          v_inferred_categories is null
          or product.category_id = any(v_inferred_categories)
        )
        and (
          v_category is null
          or product.category_id in (select id from category_scope)
          or (
            product.technical_family is not null
            and product.technical_family in (
              select technical_family from scoped_families
            )
          )
        )
        and (
          v_query is null
          or not exists (
            select 1 from regexp_split_to_table(v_query, ' +') token
            where case
              when token ~ '[0-9]' then not (
                position(
                  ' ' || token || ' ' in ' ' || product.identity_surface || ' '
                ) > 0
                or (
                  token ~ '^[0-9]+$'
                  and product.identity_raw ~ (
                    '(^|[^0-9])' || token || '([^0-9]|$)'
                  )
                )
                or product.sku_exact = token
                or product.barcode_exact = token
              )
              else position(token in product.search_surface) = 0
            end
          )
        )
    ), matched as materialized (
      select scoped.*,
        case
          when not tracks_inventory then 'not_tracked'
          when available_stock <= 0 then 'out_of_stock'
          when available_stock <= minimum_stock then 'low_stock'
          else 'in_stock'
        end availability
      from scoped
      where (
        p_availability = 'any'
        or (
          p_availability = 'in_stock'
          and tracks_inventory and available_stock > 0
        )
        or (
          p_availability = 'low_stock'
          and tracks_inventory and available_stock > 0
          and available_stock <= minimum_stock
        )
        or (
          p_availability = 'out_of_stock'
          and tracks_inventory and available_stock <= 0
        )
      )
        and not exists (
          select 1
          from requested_operational_predicates predicate
          cross join lateral (
            select case predicate.field_key
              when 'stock' then scoped.available_stock::numeric
              when 'minimum_stock' then scoped.minimum_stock::numeric
              when 'price' then scoped.price::numeric
              when 'sold_recently' then scoped.sold_recently::numeric
              else null::numeric
            end actual_value
          ) actual
          where actual.actual_value is null
            or (
              predicate.field_key in ('stock', 'minimum_stock')
              and not scoped.tracks_inventory
            )
            or not case predicate.operator
              when 'eq' then
                actual.actual_value = (predicate.values ->> 0)::numeric
              when 'neq' then
                actual.actual_value <> (predicate.values ->> 0)::numeric
              when 'lt' then
                actual.actual_value < (predicate.values ->> 0)::numeric
              when 'lte' then
                actual.actual_value <= (predicate.values ->> 0)::numeric
              when 'gt' then
                actual.actual_value > (predicate.values ->> 0)::numeric
              when 'gte' then
                actual.actual_value >= (predicate.values ->> 0)::numeric
              when 'between' then actual.actual_value between
                least(
                  (predicate.values ->> 0)::numeric,
                  (predicate.values ->> 1)::numeric
                ) and greatest(
                  (predicate.values ->> 0)::numeric,
                  (predicate.values ->> 1)::numeric
                )
              when 'in' then exists (
                select 1
                from jsonb_array_elements_text(
                  predicate.values
                ) requested(value)
                where requested.value::numeric = actual.actual_value
              )
              else false
            end
        )
    ), numbered as (
      select *,
        count(*) over()::integer matched_count,
        count(*) filter (where tracks_inventory) over()::integer tracked_count,
        coalesce(sum(available_stock) filter (
          where tracks_inventory
        ) over(), 0)::integer total_stock,
        coalesce(sum(greatest(available_stock, 0) * price) filter (
          where tracks_inventory
        ) over(), 0)::numeric inventory_retail_value,
        -- Lo que el taller tiene INVERTIDO, que es otra pregunta que la de
        -- cuánto vale a precio de venta: sólo suma lo que tiene costo cargado,
        -- para no rebajar el total con ceros que en realidad son datos que
        -- faltan.
        coalesce(sum(greatest(available_stock, 0) * cost) filter (
          where tracks_inventory and coalesce(cost, 0) > 0
        ) over(), 0)::numeric inventory_cost_value,
        count(*) filter (
          where tracks_inventory and coalesce(cost, 0) > 0
        ) over()::integer costed_count,
        avg(price) over()::numeric average_price,
        min(price) over()::numeric minimum_price,
        max(price) over()::numeric maximum_price,
        row_number() over (order by
          case
            when p_sort_field = 'stock' and p_sort_direction = 'asc'
              then available_stock
          end asc nulls last,
          case
            when p_sort_field = 'stock' and p_sort_direction = 'desc'
              then available_stock
          end desc nulls last,
          case
            when p_sort_field = 'minimum_stock' and p_sort_direction = 'asc'
              then minimum_stock
          end asc nulls last,
          case
            when p_sort_field = 'minimum_stock' and p_sort_direction = 'desc'
              then minimum_stock
          end desc nulls last,
          case
            when p_sort_field = 'sold_recently' and p_sort_direction = 'desc'
              then sold_recently
          end desc nulls last,
          case
            when p_sort_field = 'sold_recently' and p_sort_direction = 'asc'
              then sold_recently
          end asc nulls last,
          case
            when p_sort_field = 'margin' and p_sort_direction = 'desc'
              then case
                when coalesce(price, 0) > 0 and coalesce(cost, 0) > 0
                  then (price - cost) / price
                else null
              end
          end desc nulls last,
          case
            when p_sort_field = 'margin' and p_sort_direction = 'asc'
              then case
                when coalesce(price, 0) > 0 and coalesce(cost, 0) > 0
                  then (price - cost) / price
                else null
              end
          end asc nulls last,
          case
            when p_sort_field = 'price' and p_sort_direction = 'asc'
              then price
          end asc nulls last,
          case
            when p_sort_field = 'price' and p_sort_direction = 'desc'
              then price
          end desc nulls last,
          case
            when p_sort_field = 'name' and p_sort_direction = 'asc'
              then public.assistant_normalize_query_internal_v1(name)
          end asc nulls last,
          case
            when p_sort_field = 'name' and p_sort_direction = 'desc'
              then public.assistant_normalize_query_internal_v1(name)
          end desc nulls last,
          case
            when p_sort_field = 'relevance' then (
              v_query is not null
              and public.assistant_normalize_query_internal_v1(sku) = v_query
            )
          end desc nulls last,
          case
            when p_sort_field = 'relevance' then (
              v_query is not null
              and position(
                v_query in public.assistant_normalize_query_internal_v1(name)
              ) > 0
            )
          end desc nulls last,
          case when p_sort_field = 'relevance' then updated_at end desc nulls last,
          public.assistant_normalize_query_internal_v1(name), entity_id
        ) ordinal
      from matched
    )
    select coalesce(jsonb_agg(jsonb_build_object(
        'entityId', entity_id,
        'name', public.assistant_truncate_utf8_internal_v1(name, 160),
        'sku', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(sku, ''), 80
        ), ''),
        'brand', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(brand, ''), 100
        ), ''),
        'category', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(category_name, category, ''), 100
        ), ''),
        'price', price,
        'cost', cost,
        'soldRecently', sold_recently,
        -- Margen sobre el precio de venta, que es como lo mira el taller.
        -- Nulo cuando falta un dato: un margen inventado es peor que ninguno.
        'marginPercent', case
          when coalesce(price, 0) > 0 and coalesce(cost, 0) > 0
            then round(((price - cost) / price * 100)::numeric, 1)
          else null
        end,
        'stock', available_stock,
        'minimumStock', minimum_stock,
        'availability', availability,
        'tracksInventory', tracks_inventory,
        'location', nullif(public.assistant_truncate_utf8_internal_v1(
          coalesce(warehouse_location, ''), 120
        ), ''),
        'technicalMatch', technical_match,
      -- La ficha viaja con el producto. Sin esto el asistente podía FILTRAR
      -- por especificaciones pero no LEERLAS: ante «qué mano de rosca tiene
      -- esta cubeta» sacaba las medidas del nombre del producto —y cuando el
      -- nombre no las traía, se iba a buscar el dato a internet en vez de a su
      -- propia bodega (2026-08-21).
      'technicalSpecs', (
        select nullif(public.assistant_truncate_utf8_internal_v1(
          string_agg(
            spec.label || ': ' || spec.value,
            ' · ' order by spec.sort_order, spec.label
          ), 600
        ), '')
        from (
          select definition.label,
            min(definition.sort_order) sort_order,
            coalesce(
              string_agg(value_row.label, ', ' order by fact_value.position),
              fact.value_text,
              fact.value_number::text,
              case when fact.value_boolean then 'Sí' when fact.value_boolean=false then 'No' end
            ) value
          from public.spec_facts fact
          join public.spec_definitions definition
            on definition.id = fact.spec_definition_id
          left join public.spec_fact_values fact_value on fact_value.fact_id = fact.id
          left join public.spec_definition_values value_row
            on value_row.id = fact_value.value_id
          where fact.tenant_id = v_authority.tenant_id
            and fact.subject_type = 'product'
            and fact.subject_id = numbered.entity_id
            and fact.subject_scope is null
            and public.spec_product_definition_is_active_internal_v1(v_authority.tenant_id,numbered.entity_id,definition.id)
          group by definition.label, fact.value_text, fact.value_number,
            fact.value_boolean
        ) spec
      ),
        'matchedCount', matched_count,
        'trackedCount', tracked_count,
        'totalStock', total_stock,
        'inventoryRetailValue', inventory_retail_value,
        'inventoryCostValue', inventory_cost_value,
        'costedCount', costed_count,
        'averagePrice', average_price,
        'minimumPrice', minimum_price,
        'maximumPrice', maximum_price
      ) order by ordinal) filter (
        where ordinal <= p_limit
      ), '[]'::jsonb),
      coalesce(max(matched_count), 0)
    into v_items, v_total
    from numbered;
    exit when v_total > 0;
    exit when v_relaxations >= 3;
    exit when jsonb_array_length(v_inferred_predicates) <= 1;
    v_inferred_predicates := v_inferred_predicates
      - (jsonb_array_length(v_inferred_predicates) - 1);
    p_technical_predicates := v_model_predicates || v_inferred_predicates;
    v_relaxations := v_relaxations + 1;
  end loop;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id,
    v_items,
    p_selection_mode = 'all_matches' and v_total > p_limit
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_infer_technical_predicates_internal_v1(p_tenant_id uuid, p_query text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
  with params as (
    select p_tenant_id as tid, coalesce(p_query, '') as q
  ), scoped as (
    select distinct on (d.key) d.id, d.key, d.label, d.data_type
    from public.spec_definitions d
    cross join params p
    where d.is_filterable is true
      and exists(select 1 from public.spec_template_fields af join public.spec_templates at on at.id=af.template_id
        where af.spec_definition_id=d.id and (af.tenant_id is null or af.tenant_id=p.tid) and at.is_active and (at.tenant_id is null or at.tenant_id=p.tid)
          and coalesce(at.form_contract->'roles'->>d.key,'primary')<>'legacy')
      and (d.tenant_id is null or d.tenant_id = p.tid)
      -- `boolean` entra recién ahora: sin él, `includes_spindle` no existía
      -- para la inferencia y ninguna negación podía amarrarse.
      and d.data_type in (
        'number', 'single_select', 'multi_select', 'text', 'boolean'
      )
    order by d.key, (d.tenant_id is not null) desc
  ), raw_tokens as (
    -- El normalizador de búsqueda borra el punto decimal: «122.5» se vuelve
    -- «122» y «5». Para leer una medida hay que tokenizar el texto crudo.
    select case
        when t.token ~ '^[0-9]+,[0-9]+$' then replace(t.token, ',', '.')
        else btrim(t.token, '.,')
      end token,
      t.ordinality
    from params p
    cross join lateral regexp_split_to_table(
      unaccent(lower(p.q)), '[^a-z0-9.,]+'
    ) with ordinality as t(token, ordinality)
    where btrim(t.token, '.,') <> ''
  ), tokens as (
    -- **Un número pegado a su unidad también entrega el número.** El separador
    -- corta por caracteres no alfanuméricos, así que «48mm» quedaba de una
    -- pieza y jamás igualaba al rótulo «48»: el largo de válvula no se resolvía
    -- en ninguna redacción, con 94 fichas cargadas. Y nadie escribe «48 mm»
    -- con espacio — el catálogo mismo dice «48MM».
    --
    -- Se emite el número ADEMÁS del token original, con su misma `ordinality`,
    -- para que la lógica de adyacencia siga viendo una sola posición.
    --
    -- El sufijo se limita a letras: «700c» y «2.1in» entran, y «26x1.95» queda
    -- fuera a propósito —ese es un calce de neumático, no una medida suelta, y
    -- partirlo inventaría un 26 que la frase no pidió como valor—.
    select token, ordinality from raw_tokens
    union all
    select (regexp_match(token, '^([0-9]+(?:[.,][0-9]+)?)[a-z"]{1,10}$'))[1],
      ordinality
    from raw_tokens
    where token ~ '^[0-9]+(?:[.,][0-9]+)?[a-z"]{1,10}$'
  ), stop_words as (
    -- Palabras del idioma, no del dominio. «Con uña / claw» convertía
    -- cualquier frase con «con una» en un filtro de patilla trasera; lo
    -- detectó el read-back antes de que llegara al asistente. La lista es de
    -- español, no de bicicletas: el vocabulario técnico sigue saliendo del
    -- catálogo, nunca de una lista escrita a mano.
    select unnest(array[
      'con', 'sin', 'por', 'para', 'que', 'del', 'las', 'los', 'una', 'uno',
      'unos', 'unas', 'como', 'mas', 'muy', 'este', 'esta', 'esto', 'esos',
      'esas', 'the', 'and', 'for', 'with'
    ]) token
  ), vocab_tokens as (
    select s.key, s.id def_id, v.label, vt.token
    from scoped s
    cross join params p
    join public.spec_definition_values v
      on v.spec_definition_id = s.id
     and v.is_active is true
     and (v.tenant_id is null or v.tenant_id = p.tid)
    cross join lateral regexp_split_to_table(
      public.assistant_normalize_query_internal_v1(v.label), ' +'
    ) vt(token)
    where vt.token ~ '^[a-z]{3,}$'
      and vt.token not in (select token from stop_words)
  ), all_label_tokens as (
    -- Las palabras de los RÓTULOS, sin acotar por alcance. Una palabra que
    -- nombra un campo no puede ser evidencia de un valor: «caja» está en «Caja
    -- de motor» y en «Ancho caja motor», y por aparecer además dentro de un
    -- solo valor hacía que «motor caja 73» asumiera BSA en silencio.
    select distinct lt.token
    from scoped s
    cross join lateral regexp_split_to_table(
      public.assistant_normalize_query_internal_v1(s.label), ' +'
    ) lt(token)
    where lt.token ~ '^[a-z]{3,}$'
  ), definition_coverage as (
    select f.spec_definition_id id, count(distinct f.subject_id) n
    from public.spec_facts f
    cross join params p
    where f.tenant_id = p.tid and f.subject_type = 'product' and f.subject_scope is null
      and public.spec_product_definition_is_active_internal_v1(p.tid,f.subject_id,f.spec_definition_id)
    group by 1
  ), vocab_candidates as (
    select vt.token, vt.key, vt.label, coalesce(dc.n, 0) coverage
    from vocab_tokens vt
    left join definition_coverage dc on dc.id = vt.def_id
    where vt.token not in (select token from all_label_tokens)
  ), vocab_top as (
    select token, max(coverage) top from vocab_candidates group by token
  ), vocab_unique as (
    -- «bsa» vive en cuatro campos —caja, mano de la rosca y dos heredados—.
    -- Decide el catálogo: gana el campo que el taller realmente llena, y sólo
    -- si gana solo. Un campo sin un hecho cargado no compite.
    select c.token, min(c.key) key
    from vocab_candidates c
    join vocab_top t2 on t2.token = c.token and c.coverage = t2.top
    group by c.token
    having count(distinct c.key) = 1 and max(c.coverage) > 0
  ), vocab_hits as (
    select distinct u.key, c.label, tk.ordinality
    from vocab_unique u
    join vocab_candidates c on c.token = u.token and c.key = u.key
    join tokens tk on tk.token = u.token
  ), query_categories as (
    -- «motor» no es el nombre exacto de la categoría «Motores», pero sí una
    -- palabra de su ruta. Ese es el ancla que vuelve resoluble un rótulo
    -- genérico cuando la frase no trae ninguna palabra del vocabulario.
    select c.id, public.assistant_normalize_query_internal_v1(c.full_path) path
    from public.product_categories c
    cross join params p
    where c.tenant_id = p.tid
      and c.is_active is true
      and exists (
        select 1 from tokens t
        where t.token ~ '^[a-z]{4,}$'
          and position(
            t.token in public.assistant_normalize_query_internal_v1(c.full_path)
          ) > 0
      )
  ), vocab_scope as (
    select distinct other.spec_definition_id
    from vocab_hits hit
    join scoped s on s.key = hit.key
    join public.spec_template_fields own on own.spec_definition_id = s.id
    join public.spec_template_fields other on other.template_id = own.template_id
    join public.spec_templates active_template on active_template.id=own.template_id and active_template.is_active
      and (active_template.tenant_id is null or active_template.tenant_id=(select tid from params))
    join public.spec_definitions other_definition on other_definition.id=other.spec_definition_id
    where coalesce(active_template.form_contract->'roles'->>s.key,'primary')<>'legacy'
      and coalesce(active_template.form_contract->'roles'->>other_definition.key,'primary')<>'legacy'
  ), category_scope_fields as (
    select distinct tf.spec_definition_id
    from query_categories qc
    cross join params p
    join public.category_spec_template_scope_internal_v1 m
      on m.category_id = qc.id and m.tenant_id = p.tid and m.status = 'active'
    join public.spec_templates tpl
      on tpl.is_active is true
     and (tpl.tenant_id is null or tpl.tenant_id = p.tid)
     and (tpl.id = m.template_id
       or (m.template_id is null and tpl.technical_family = m.technical_family))
    join public.spec_template_fields tf on tf.template_id = tpl.id
    join public.spec_definitions active_definition on active_definition.id=tf.spec_definition_id
      and coalesce(tpl.form_contract->'roles'->>active_definition.key,'primary')<>'legacy'
  ), family_scope as (
    select spec_definition_id from vocab_scope
    union all
    select spec_definition_id from category_scope_fields
    where not exists (select 1 from vocab_scope)
  ), label_tokens as (
    select s.key, s.data_type, lt.token
    from scoped s
    cross join lateral regexp_split_to_table(
      public.assistant_normalize_query_internal_v1(s.label), ' +'
    ) lt(token)
    where lt.token ~ '^[a-z]{3,}$'
      and lt.token not in (select token from stop_words)
      and (
        not exists (select 1 from family_scope)
        or s.id in (select spec_definition_id from family_scope)
      )
  ), label_counts as (
    select token, count(distinct key) n, min(key) key, min(data_type) dt
    from label_tokens
    group by token
  ), numeric_cues as (
    select token, key from label_counts where n = 1 and dt = 'number'
  ), number_tokens as (
    select token::numeric value, token, ordinality
    from tokens
    where token ~ '^[0-9]+([.][0-9]+)?$'
  ), numeric_field_range as (
    -- Lo que el catálogo admite de verdad para cada campo numérico. Sirve de
    -- cordura: una pista no puede amarrar cualquier número que venga detrás.
    select s.key,
      min(f.value_number) lo, max(f.value_number) hi
    from scoped s
    cross join params p
    join public.spec_facts f
      on f.spec_definition_id = s.id and f.tenant_id = p.tid
     and f.subject_type = 'product' and f.subject_scope is null and f.value_number is not null
     and public.spec_product_definition_is_active_internal_v1(p.tid,f.subject_id,f.spec_definition_id)
    where s.data_type = 'number'
    group by s.key
  ), cue_bindings as (
    -- La pista amarra el número siguiente SÓLO si cae dentro del rango real
    -- del campo. Sin esto, «cubeta NAKASAWA 10561» amarraba el SKU como
    -- «diámetro de rosca de cubeta = 10561» —los reales rondan los 34,8 mm— y
    -- la búsqueda devolvía cero; el asistente terminaba buscando el producto
    -- en internet en vez de leer su propia bodega (2026-08-21).
    select distinct on (c.key) c.key, n.value, n.ordinality, t.ordinality cue_ord
    from numeric_cues c
    join tokens t on t.token = c.token
    join number_tokens n
      on n.ordinality > t.ordinality and n.ordinality <= t.ordinality + 4
    join numeric_field_range r on r.key = c.key
     and n.value between r.lo and r.hi
    order by c.key, n.ordinality
  ), numeric_vocab as (
    -- «160» no es una medida libre: es una opción de `rotor_diameter_mm`, que
    -- es una lista cuyos valores son números. Lo mismo pasa con el rodado
    -- («29\"») y el número de rayos. Sin esta regla, «discos de freno de 160»
    -- devolvía cero teniendo siete en bodega.
    --
    -- Se compara contra el rótulo despojado de puntuación, no contra el
    -- normalizador de búsqueda: ése borra el punto decimal y «27.5» dejaría de
    -- calzar. Y se compara por igualdad, no por fragmento, para que «160» no
    -- se lleve «160/140».
    select n.ordinality, min(s.key) key, min(v.label) label
    from number_tokens n
    cross join params p
    join scoped s
      on s.data_type in ('single_select', 'multi_select')
     and s.id in (select spec_definition_id from family_scope)
    join public.spec_definition_values v
      on v.spec_definition_id = s.id
     and v.is_active is true
     and (v.tenant_id is null or v.tenant_id = p.tid)
     and regexp_replace(lower(unaccent(v.label)), '[^a-z0-9.]', '', 'g') = n.token
    where not exists (
      select 1 from cue_bindings b where b.ordinality = n.ordinality
    )
    group by n.ordinality
    having count(distinct s.key) = 1
  ), fact_bindings as (
    -- Un número sin pista —«manubrio 31.8»— se resuelve si dentro del alcance
    -- existe un solo campo cuyos hechos reales lo contengan. Decide el
    -- catálogo, no una lista escrita a mano.
    select n.ordinality, n.value, min(s.key) key
    from number_tokens n
    cross join params p
    join public.spec_facts f
      on f.tenant_id = p.tid and f.value_number = n.value
     and f.subject_type='product' and f.subject_scope is null
     and public.spec_product_definition_is_active_internal_v1(p.tid,f.subject_id,f.spec_definition_id)
    join scoped s
      on s.id = f.spec_definition_id
     and s.data_type = 'number'
     and s.id in (select spec_definition_id from family_scope)
    where not exists (
      select 1 from cue_bindings b where b.ordinality = n.ordinality
    )
    and not exists (
      select 1 from numeric_vocab nv where nv.ordinality = n.ordinality
    )
    group by n.ordinality, n.value
    having count(distinct s.key) = 1
  ), boolean_cues as (
    -- «eje» no sirve como pista numérica —está en «Largo eje» y en «Punta del
    -- eje»—, pero entre los campos BOOLEANOS del alcance sólo lo tiene
    -- «Incluye eje». Esa distinción alcanza, y evita inventarle sinónimos al
    -- idioma: «traen», «incluye» y «con» no aparecen en ninguna lista.
    select s.key, lt.token
    from scoped s
    cross join lateral regexp_split_to_table(
      public.assistant_normalize_query_internal_v1(s.label), ' +'
    ) lt(token)
    where s.data_type = 'boolean'
      and s.id in (select spec_definition_id from family_scope)
      and lt.token ~ '^[a-z]{3,}$'
      and lt.token not in (select token from stop_words)
  ), boolean_unique as (
    select token, min(key) key
    from boolean_cues group by token having count(distinct key) = 1
  ), negation_bindings as (
    -- Sólo se amarra la negación. Afirmar es ambiguo: «con largo de eje 118»
    -- habla de la medida, no de si el motor trae eje, y amarrar «true» ahí
    -- dejaría fuera productos correctos.
    select distinct on (u.key) u.key, t.ordinality, neg.ordinality neg_ord
    from boolean_unique u
    join tokens t on t.token = u.token
    join tokens neg
      on neg.token in ('no', 'sin', 'ningun', 'ninguna')
     and neg.ordinality < t.ordinality
     and neg.ordinality >= t.ordinality - 3
    order by u.key, t.ordinality
  ), predicates as (
    select key, 'in' operator,
      jsonb_agg(distinct to_jsonb(label)) values, min(ordinality) ordinality
    from vocab_hits group by key
    union all
    select key, 'eq', jsonb_build_array(to_jsonb(value)), ordinality
    from cue_bindings
    union all
    select key, 'eq', jsonb_build_array(to_jsonb(value)), ordinality
    from fact_bindings
    union all
    select key, 'in', jsonb_build_array(to_jsonb(label)), ordinality
    from numeric_vocab
    union all
    select key, 'eq', jsonb_build_array(to_jsonb(false)), ordinality
    from negation_bindings
  ), predicates_ranked as (
    -- Se ordenan por cuánta ficha tiene cargada cada campo. El buscador
    -- descarta desde el final si la combinación completa no calza nada: un
    -- campo casi vacío es el primero en sobrar.
    select p.key, p.operator, p.values, p.ordinality,
      coalesce(dc.n, 0) coverage
    from predicates p
    join scoped s on s.key = p.key
    left join definition_coverage dc on dc.id = s.id
  ), bounded_predicates as (
    select * from predicates_ranked order by coverage desc, ordinality limit 8
  ), category_words as (
    select distinct t.ordinality
    from tokens t
    join query_categories qc on position(t.token in qc.path) > 0
    where t.token ~ '^[a-z]{4,}$'
  ), consumed as (
    select ordinality from vocab_hits
    union select ordinality from cue_bindings
    union select cue_ord from cue_bindings
    union select ordinality from fact_bindings
    union select ordinality from numeric_vocab
    union select ordinality from negation_bindings
    union select neg_ord from negation_bindings
    union select ordinality from category_words
    -- Sólo se consumen las palabras que NOMBRAN un campo. Antes se consumía
    -- también cualquier palabra que apareciera en algún valor del vocabulario,
    -- aunque no llegara a ser filtro: «shimano» existe dentro del valor
    -- «Shimano HG» de un piñón, así que en «qué motores shimano tengo» la
    -- marca desaparecía en silencio y la respuesta traía todos los motores.
    -- Una palabra de valor que sí amarra ya viene consumida por `vocab_hits`.
    union select t.ordinality from tokens t
      where exists (select 1 from label_tokens l where l.token = t.token)
  ), residual_candidates as (
    select t.token, t.ordinality
    from tokens t
    where t.ordinality not in (select ordinality from consumed)
      -- Un código de producto —«bc73»— es identidad, no palabra vacía: si se
      -- exige sólo letras, una frase mixta pierde la parte que identifica.
      -- Pero bajar el largo a tres dejó pasar «con», que existe como palabra
      -- suelta en nombres del catálogo («manilla con cable») y por lo tanto
      -- exigía «con» en cada resultado: cero. Tres caracteres sólo valen si
      -- traen un dígito; si son puras letras, hacen falta cuatro.
      and t.token ~ '^[a-z0-9]{3,}$'
      and (t.token ~ '[0-9]' or length(t.token) >= 4)
      and t.token not in (select token from stop_words)
  ), residual_tokens as (
    -- Lo que sobra sólo se conserva si nombra algo real del catálogo —una
    -- marca, un modelo—. «dame», «necesito» y «quiero» no sobreviven ese
    -- filtro, y por eso no hace falta una lista de palabras vacías.
    --
    -- El barrido de productos se paga por palabra candidata, no por consulta:
    -- medido el 2026-08-21, precomputarlo costaba 660 ms incluso cuando no
    -- quedaba ninguna palabra por revisar.
    select c.token, c.ordinality
    from residual_candidates c
    where exists (
      select 1
      from public.products pr
      cross join params p
      where pr.tenant_id = p.tid
        and pr.is_active is true
        and public.assistant_normalize_query_internal_v1(concat_ws(' ',
          pr.name, pr.sku, pr.barcode, pr.brand, pr.model, pr.manufacturer,
          pr.category_name, pr.category, pr.description
        )) ~ ('(^| )' || c.token || '( |$)')
    )
  )
  select jsonb_build_object(
    'categories', coalesce((
      select jsonb_agg(distinct qc.id) from query_categories qc
    ), '[]'::jsonb),
    'predicates', coalesce((
      select jsonb_agg(jsonb_build_object(
        'field', key, 'operator', operator, 'values', values
      ) order by coverage desc, ordinality)
      from bounded_predicates
    ), '[]'::jsonb),
    'residual', coalesce((
      select string_agg(token, ' ' order by ordinality) from residual_tokens
    ), '')
  );
$function$;

CREATE OR REPLACE FUNCTION public.assistant_inspect_inventory_schema_v1(p_query text, p_category text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_query text;
  v_category text;
  v_items jsonb;
  v_total integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1('ai.read.operational') authority;

  if octet_length(coalesce(p_query, '')) not between 1 and 240
     or octet_length(coalesce(p_category, '')) > 160 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category), ''
  );
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  with recursive candidate_roots as materialized (
    select category.id, category.name, category.full_path, category.level,
      row_number() over (order by
        (public.assistant_normalize_query_internal_v1(category.name) =
          coalesce(v_category, v_query)) desc,
        (public.assistant_normalize_query_internal_v1(category.full_path) =
          coalesce(v_category, v_query)) desc,
        category.level,
        length(category.full_path),
        category.full_path
      ) root_rank
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        (
          v_category is not null
          and exists (
            select 1 from public.product_categories exact_category
            where exact_category.tenant_id = v_authority.tenant_id
              and exact_category.is_active is true
              and (public.assistant_normalize_query_internal_v1(
                  exact_category.name
                ) = v_category
                or public.assistant_normalize_query_internal_v1(
                  exact_category.full_path
                ) = v_category)
          )
          and (public.assistant_normalize_query_internal_v1(category.name) = v_category
            or public.assistant_normalize_query_internal_v1(
              category.full_path
            ) = v_category)
        )
        or (
          v_category is not null
          and not exists (
            select 1 from public.product_categories exact_category
            where exact_category.tenant_id = v_authority.tenant_id
              and exact_category.is_active is true
              and (public.assistant_normalize_query_internal_v1(
                  exact_category.name
                ) = v_category
                or public.assistant_normalize_query_internal_v1(
                  exact_category.full_path
                ) = v_category)
          )
          and (
            position(v_category in public.assistant_normalize_query_internal_v1(
              category.full_path
            )) > 0
            or position(public.assistant_normalize_query_internal_v1(
              category.name
            ) in v_category) > 0
          )
        )
        or (
          v_category is null
          and length(public.assistant_normalize_query_internal_v1(category.name)) >= 3
          and position(public.assistant_normalize_query_internal_v1(
            category.name
          ) in v_query) > 0
        )
        or (
          v_category is null
          and exists (
            select 1 from regexp_split_to_table(v_query, ' +') token
            where length(token) >= 4
              and position(token in public.assistant_normalize_query_internal_v1(
                category.full_path
              )) > 0
          )
        )
      )
    order by root_rank
    limit 8
  ), category_scope as (
    select root.id, root.name, root.full_path, root.level, root.root_rank
    from candidate_roots root
    where root.root_rank <= 8
    union
    select child.id, child.name, child.full_path, child.level, scope.root_rank
    from public.product_categories child
    join category_scope scope on child.parent_id = scope.id
    where child.tenant_id = v_authority.tenant_id
      and child.is_active is true
  ), category_rows as materialized (
    select distinct on (scope.id)
      'category'::text kind,
      scope.name category,
      scope.full_path category_path,
      case when count(distinct mapping.technical_family)=1 then min(mapping.technical_family) end technical_family,
      null::text field_key,
      null::text field_label,
      null::text data_type,
      null::text unit,
      null::text operators,
      null::text allowed_values,
      count(distinct product.id)::integer product_count,
      0::integer populated_count,
      scope.root_rank,
      scope.level,
      0 sort_order
    from category_scope scope
    left join public.category_spec_template_scope_internal_v1 mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    left join public.products product
      on product.tenant_id = v_authority.tenant_id
     and product.category_id = scope.id and product.is_active is true
    group by scope.id, scope.name, scope.full_path,
      scope.root_rank, scope.level
    order by scope.id
  ), field_rows as materialized (
    select
      'field'::text kind,
      scope.name category,
      scope.full_path category_path,
      mapping.technical_family,
      definition.key field_key,
      definition.label field_label,
      definition.data_type,
      definition.unit,
      case definition.data_type
        when 'number' then 'eq,neq,lt,lte,gt,gte,between,in'
        when 'boolean' then 'eq,neq'
        when 'single_select' then 'eq,neq,in'
        when 'multi_select' then 'eq,neq,in'
        when 'text' then 'eq,neq,in,contains'
      end operators,
      nullif(public.assistant_truncate_utf8_internal_v1(
        definition.allowed_values::text, 480
      ), '[]') allowed_values,
      count(distinct product.id)::integer product_count,
      count(distinct value.product_id)::integer populated_count,
      scope.root_rank,
      scope.level,
      template_field.sort_order
    from category_scope scope
    join public.category_spec_template_scope_internal_v1 mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    join lateral (
      select template.id,template.form_contract
      from public.spec_templates template
      where template.is_active is true
        and (template.tenant_id is null or template.tenant_id = v_authority.tenant_id)
        and (template.id = mapping.template_id
          or (mapping.template_id is null
            and template.technical_family = mapping.technical_family))
      order by (template.id = mapping.template_id) desc,
        (template.tenant_id is not null) desc
      limit 1
    ) template on true
    join public.spec_template_fields template_field
      on template_field.template_id = template.id
     and (template_field.tenant_id is null
       or template_field.tenant_id = v_authority.tenant_id)
    join public.spec_definitions definition
      on definition.id = template_field.spec_definition_id
     and (definition.tenant_id is null
       or definition.tenant_id = v_authority.tenant_id)
     and definition.is_filterable is true
     and coalesce(template.form_contract->'roles'->>definition.key,'primary')<>'legacy'
     and definition.data_type in (
       'text', 'number', 'boolean', 'single_select', 'multi_select'
     )
    left join public.products product
      on product.tenant_id = v_authority.tenant_id
     and product.category_id = scope.id and product.is_active is true
     and public.spec_template_resolution_internal_v1(product.tenant_id,product.category_id,product.spec_template_id)=template.id
    left join public.product_spec_values value
      on value.tenant_id = v_authority.tenant_id
     and value.product_id = product.id
     and value.spec_definition_id = definition.id
    group by scope.name, scope.full_path, mapping.technical_family,
      definition.key, definition.label, definition.data_type,
      definition.unit, definition.allowed_values, scope.root_rank,
      scope.level, template_field.sort_order
  ), bounded as materialized (
    select * from category_rows
    union all
    select * from field_rows
    order by root_rank, level, category_path, sort_order, field_key nulls first
    limit 41
  ), numbered as (
    select *, row_number() over (
      order by root_rank, level, category_path, sort_order, field_key nulls first
    ) ordinal
    from bounded
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', kind,
      'category', public.assistant_truncate_utf8_internal_v1(category, 160),
      'categoryPath', public.assistant_truncate_utf8_internal_v1(category_path, 240),
      'technicalFamily', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(technical_family, ''), 120
      ), ''),
      'field', field_key,
      'label', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(field_label, ''), 160
      ), ''),
      'dataType', data_type,
      'unit', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(unit, ''), 40
      ), ''),
      'operators', operators,
      'allowedValues', allowed_values,
      'productCount', product_count,
      'populatedCount', populated_count
    ) order by ordinal) filter (where ordinal <= 40), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > 40
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_inspect_inventory_schema_v3(p_query text, p_category text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
 SET statement_timeout TO '4500ms'
AS $function$
declare
  v_authority record;
  v_query text;
  v_category text;
  v_items jsonb;
  v_total integer;
  v_active_count integer;
  v_stock_count integer;
  v_minimum_stock_count integer;
  v_price_count integer;
begin
  select authority.tenant_id, authority.actor_user_id,
    authority.authority_role, authority.permissions, authority.capabilities,
    authority.authority_fingerprint
  into strict v_authority
  from public.assistant_require_capability_internal_v1(
    'ai.read.operational'
  ) authority;

  if octet_length(coalesce(p_query, '')) not between 1 and 240
     or octet_length(coalesce(p_category, '')) > 160 then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;
  v_query := public.assistant_normalize_query_internal_v1(p_query);
  v_category := nullif(
    public.assistant_normalize_query_internal_v1(p_category), ''
  );
  if v_query = '' then
    raise exception 'Invalid AI tool arguments' using errcode = '22023';
  end if;

  with recursive candidate_roots as materialized (
    select category.id, category.name, category.full_path, category.level,
      row_number() over (order by
        (public.assistant_normalize_query_internal_v1(category.name) =
          coalesce(v_category, v_query)) desc,
        (public.assistant_normalize_query_internal_v1(category.full_path) =
          coalesce(v_category, v_query)) desc,
        category.level,
        length(category.full_path),
        category.full_path
      ) root_rank
    from public.product_categories category
    where category.tenant_id = v_authority.tenant_id
      and category.is_active is true
      and (
        (
          v_category is not null
          and exists (
            select 1 from public.product_categories exact_category
            where exact_category.tenant_id = v_authority.tenant_id
              and exact_category.is_active is true
              and (public.assistant_normalize_query_internal_v1(
                  exact_category.name
                ) = v_category
                or public.assistant_normalize_query_internal_v1(
                  exact_category.full_path
                ) = v_category)
          )
          and (public.assistant_normalize_query_internal_v1(category.name) = v_category
            or public.assistant_normalize_query_internal_v1(
              category.full_path
            ) = v_category)
        )
        or (
          v_category is not null
          and not exists (
            select 1 from public.product_categories exact_category
            where exact_category.tenant_id = v_authority.tenant_id
              and exact_category.is_active is true
              and (public.assistant_normalize_query_internal_v1(
                  exact_category.name
                ) = v_category
                or public.assistant_normalize_query_internal_v1(
                  exact_category.full_path
                ) = v_category)
          )
          and (
            position(v_category in public.assistant_normalize_query_internal_v1(
              category.full_path
            )) > 0
            or position(public.assistant_normalize_query_internal_v1(
              category.name
            ) in v_category) > 0
          )
        )
        or (
          v_category is null
          and length(public.assistant_normalize_query_internal_v1(category.name)) >= 3
          and position(public.assistant_normalize_query_internal_v1(
            category.name
          ) in v_query) > 0
        )
        or (
          v_category is null
          and exists (
            select 1 from regexp_split_to_table(v_query, ' +') token
            where length(token) >= 4
              and position(token in public.assistant_normalize_query_internal_v1(
                category.full_path
              )) > 0
          )
        )
      )
    order by root_rank
    limit 8
  ), category_scope as (
    select root.id, root.name, root.full_path, root.level, root.root_rank
    from candidate_roots root
    where root.root_rank <= 8
    union
    select child.id, child.name, child.full_path, child.level, scope.root_rank
    from public.product_categories child
    join category_scope scope on child.parent_id = scope.id
    where child.tenant_id = v_authority.tenant_id
      and child.is_active is true
  ), category_rows as materialized (
    select distinct on (scope.id)
      'category'::text kind,
      scope.id entity_id,
      scope.name category,
      scope.full_path category_path,
      case when count(distinct mapping.technical_family)=1 then min(mapping.technical_family) end technical_family,
      null::text field_key,
      null::text field_label,
      null::text data_type,
      null::text unit,
      null::text operators,
      null::text allowed_values,
      count(distinct product.id)::integer product_count,
      0::integer populated_count,
      scope.root_rank,
      scope.level,
      0 sort_order
    from category_scope scope
    left join public.category_spec_template_scope_internal_v1 mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    left join public.products product
      on product.tenant_id = v_authority.tenant_id
     and product.category_id = scope.id and product.is_active is true
    group by scope.id, scope.name, scope.full_path,
      scope.root_rank, scope.level
    order by scope.id
  ), field_rows as materialized (
    select
      'field'::text kind,
      -- La fila de campo pertenece a la misma categoría que la fila de
      -- categoría: agrupar por `scope.id` además del nombre evita fundir dos
      -- ramas homónimas del árbol en una sola identidad.
      scope.id entity_id,
      scope.name category,
      scope.full_path category_path,
      mapping.technical_family,
      definition.key field_key,
      definition.label field_label,
      definition.data_type,
      definition.unit,
      case definition.data_type
        when 'number' then 'eq,neq,lt,lte,gt,gte,between,in'
        when 'boolean' then 'eq,neq'
        when 'single_select' then 'eq,neq,in'
        when 'multi_select' then 'eq,neq,in'
        when 'text' then 'eq,neq,in,contains'
      end operators,
      nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce((
          select jsonb_agg(sv.label order by sv.sort_order)::text
          from public.spec_definition_values sv
          where sv.spec_definition_id = definition.id and sv.is_active
        ), definition.allowed_values::text), 480
      ), '[]') allowed_values,
      count(distinct product.id)::integer product_count,
      count(distinct value.subject_id)::integer populated_count,
      scope.root_rank,
      scope.level,
      template_field.sort_order
    from category_scope scope
    join public.category_spec_template_scope_internal_v1 mapping
      on mapping.tenant_id = v_authority.tenant_id
     and mapping.category_id = scope.id and mapping.status = 'active'
    join lateral (
      select template.id,template.form_contract
      from public.spec_templates template
      where template.is_active is true
        and (template.tenant_id is null or template.tenant_id = v_authority.tenant_id)
        and (template.id = mapping.template_id
          or (mapping.template_id is null
            and template.technical_family = mapping.technical_family))
      order by (template.id = mapping.template_id) desc,
        (template.tenant_id is not null) desc
      limit 1
    ) template on true
    join public.spec_template_fields template_field
      on template_field.template_id = template.id
     and (template_field.tenant_id is null
       or template_field.tenant_id = v_authority.tenant_id)
    join public.spec_definitions definition
      on definition.id = template_field.spec_definition_id
     and (definition.tenant_id is null
       or definition.tenant_id = v_authority.tenant_id)
     and definition.is_filterable is true
     and coalesce(template.form_contract->'roles'->>definition.key,'primary')<>'legacy'
     and definition.data_type in (
       'text', 'number', 'boolean', 'single_select', 'multi_select'
     )
    left join public.products product
      on product.tenant_id = v_authority.tenant_id
     and product.category_id = scope.id and product.is_active is true
     and public.spec_template_resolution_internal_v1(product.tenant_id,product.category_id,product.spec_template_id)=template.id
    -- La cobertura sale del registro unificado. Antes contaba filas de
    -- `product_spec_values`; ahora cuenta hechos, que es lo mismo hoy y lo
    -- correcto cuando la tabla vieja se retire.
    left join public.spec_facts value
      on value.tenant_id = v_authority.tenant_id
     and value.subject_type = 'product'
     and value.subject_id = product.id
     and value.spec_definition_id = definition.id
     and value.subject_scope is null
    -- `definition.id` va en el GROUP BY porque la subconsulta de
    -- `allowed_values` lo referencia. Sin él Postgres aborta con «subquery
    -- uses ungrouped column», y la función falla ENTERA: 28 llamadas fallidas
    -- contra 5 exitosas el 2026-08-21, y el asistente perdiendo la herramienta
    -- que resuelve categorías antes de buscar. Agruparlo no cambia la
    -- granularidad: es la clave primaria de la misma fila que ya aporta
    -- `definition.key`.
    group by scope.id, scope.name, scope.full_path, mapping.technical_family,
      definition.id, definition.key, definition.label, definition.data_type,
      definition.unit, definition.allowed_values, scope.root_rank,
      scope.level, template_field.sort_order
  ), bounded as materialized (
    select * from category_rows
    union all
    select * from field_rows
    order by root_rank, level, category_path, sort_order, field_key nulls first
    limit 41
  ), numbered as (
    select *, row_number() over (
      order by root_rank, level, category_path, sort_order, field_key nulls first
    ) ordinal
    from bounded
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'kind', kind,
      'entityId', entity_id,
      'category', public.assistant_truncate_utf8_internal_v1(category, 160),
      'categoryPath', public.assistant_truncate_utf8_internal_v1(category_path, 240),
      'technicalFamily', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(technical_family, ''), 120
      ), ''),
      'field', field_key,
      'label', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(field_label, ''), 160
      ), ''),
      'dataType', data_type,
      'unit', nullif(public.assistant_truncate_utf8_internal_v1(
        coalesce(unit, ''), 40
      ), ''),
      'operators', operators,
      'allowedValues', allowed_values,
      'productCount', product_count,
      'populatedCount', populated_count
    ) order by ordinal) -- 37, no 40: abajo se agregan SIEMPRE tres campos operativos —stock,
    -- stock mínimo y precio— y el ejecutor rechaza el sobre entero sobre 40
    -- ítems. Una consulta amplia como «freno» o «rueda» devolvía 43 y moría
    -- con `tool_source_unavailable`, así que la herramienta fallaba justo en
    -- las preguntas más comunes. `hasMore` ya avisa que la lista viene cortada.
    filter (where ordinal <= 37), '[]'::jsonb),
    count(*)
  into v_items, v_total
  from numbered;

  -- Campos operativos: los mismos de `_v2`, sin identidad de categoría porque
  -- «Inventario» no es una categoría del catálogo.
  select count(*)::integer,
    count(*) filter (where coalesce(product.track_stock, false))::integer,
    count(*) filter (
      where coalesce(product.track_stock, false)
        and coalesce(product.min_stock_level, 0) > 0
    )::integer,
    count(*) filter (where coalesce(product.price, 0) > 0)::integer
  into v_active_count, v_stock_count, v_minimum_stock_count, v_price_count
  from public.products product
  where product.tenant_id = v_authority.tenant_id
    and product.is_active is true;

  v_items := v_items || jsonb_build_array(
    jsonb_build_object(
      'kind', 'operational_field', 'entityId', null,
      'category', 'Inventario', 'categoryPath', 'Inventario',
      'technicalFamily', null, 'field', 'stock',
      'label', 'Stock disponible', 'dataType', 'number', 'unit', 'unidades',
      'operators', 'eq,neq,lt,lte,gt,gte,between,in', 'allowedValues', null,
      'productCount', v_active_count, 'populatedCount', v_stock_count
    ),
    jsonb_build_object(
      'kind', 'operational_field', 'entityId', null,
      'category', 'Inventario', 'categoryPath', 'Inventario',
      'technicalFamily', null, 'field', 'minimum_stock',
      'label', 'Stock mínimo', 'dataType', 'number', 'unit', 'unidades',
      'operators', 'eq,neq,lt,lte,gt,gte,between,in', 'allowedValues', null,
      'productCount', v_active_count, 'populatedCount', v_minimum_stock_count
    ),
    jsonb_build_object(
      'kind', 'operational_field', 'entityId', null,
      'category', 'Inventario', 'categoryPath', 'Inventario',
      'technicalFamily', null, 'field', 'price',
      'label', 'Precio de venta', 'dataType', 'number', 'unit', 'CLP',
      'operators', 'eq,neq,lt,lte,gt,gte,between,in', 'allowedValues', null,
      'productCount', v_active_count, 'populatedCount', v_price_count
    )
  );

  return public.assistant_tool_envelope_internal_v1(
    v_authority.tenant_id, v_items, v_total > 37
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_inventory_technical_predicate_source_internal_v1(p_tenant_id uuid, p_product_id uuid, p_field_key text, p_operator text, p_values jsonb, p_identity_surface text, p_identity_raw text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_definition record;
  v_value record;
  v_match boolean := false;
  v_candidate text;
  v_candidate_normalized text;
  v_number numeric;
  v_first numeric;
  v_second numeric;
  v_boolean boolean;
  v_found boolean := false;
  v_texto text;
begin
  if not public.spec_product_field_is_active_internal_v1(p_tenant_id,p_product_id,p_field_key) then return 'unresolved'; end if;
  select definition.id, definition.data_type, definition.allowed_values
  into v_definition
  from public.spec_definitions definition
  where definition.id = public.spec_product_field_definition_internal_v1(p_tenant_id,p_product_id,p_field_key)
    and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
    and definition.is_filterable is true
  order by (definition.tenant_id is not null) desc
  limit 1;
  if not found then return 'unresolved'; end if;

  -- El hecho sale del registro unificado. Los valores de lista se arman desde
  -- `spec_fact_values`, así que la ETIQUETA con la que se compara es la actual
  -- del vocabulario y no una copia congelada: renombrar un valor no rompe un
  -- filtro que ya funcionaba.
  select f.value_text, f.value_number, f.value_boolean, f.source,
    (
      select string_agg(sv.label, ', ' order by fv.position)
      from public.spec_fact_values fv
      join public.spec_definition_values sv on sv.id = fv.value_id
      where fv.fact_id = f.id
    ) as value_option,
    (
      select jsonb_agg(sv.label order by fv.position)
      from public.spec_fact_values fv
      join public.spec_definition_values sv on sv.id = fv.value_id
      where fv.fact_id = f.id
    ) as value_json,
    null::text as display_value,
    (select r.source_digest from public.spec_fact_readings r
      where r.fact_id = f.id) as source_digest,
    (select r.vocabulary_digest from public.spec_fact_readings r
      where r.fact_id = f.id) as vocabulary_digest,
    f.spec_definition_id as definition_id
  into v_value
  from public.spec_facts f
  join public.spec_definitions definition
    on definition.id = f.spec_definition_id
   and definition.id = v_definition.id
   and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
  where f.tenant_id = p_tenant_id
    and f.subject_type = 'product'
    and f.subject_id = p_product_id
    and f.subject_scope is null
  order by (f.source <> 'name_reading') desc,
           (definition.tenant_id is not null) desc
  limit 1;
  v_found := found;

  -- **Una lectura vale para el texto que se leyó.** Si el nombre cambió, el
  -- digest no calza y el hecho se ignora entero: vuelve a ser silencio, que es
  -- la respuesta correcta a «ya no sé si esto seguía diciéndolo».
  if v_found and v_value.source = 'name_reading' then
    select concat_ws(' ', p.name, p.description) into v_texto
    from public.products p
    where p.id = p_product_id and p.tenant_id = p_tenant_id;
    if v_value.source_digest is null
       or v_texto is null
       or v_value.source_digest
          <> encode(sha256(convert_to(v_texto, 'UTF8')), 'hex') then
      v_found := false;
    end if;
    -- **Y el vocabulario con que se juzgo la cita.** Atar la vigencia solo al
    -- nombre dejaba viva una lectura que ya no se sostiene: renombrar la
    -- etiqueta elegida, cambiar el nombre del campo, o agregar un valor
    -- hermano mas especifico son tres formas de que la misma cita deje de
    -- decir lo que decia. Ninguna toca el nombre del producto.
    if v_found and (
         v_value.vocabulary_digest is null
         or v_value.vocabulary_digest
            <> public.spec_definition_vocabulary_digest_internal_v1(
                 v_value.definition_id)) then
      v_found := false;
    end if;
  end if;

  if v_found then
    if v_definition.data_type = 'number' then
      if v_value.value_number is null then return 'conflict'; end if;
      v_number := v_value.value_number;
      v_first := (p_values ->> 0)::numeric;
      if p_operator = 'eq' then v_match := v_number = v_first;
      elsif p_operator = 'neq' then v_match := v_number <> v_first;
      elsif p_operator = 'lt' then v_match := v_number < v_first;
      elsif p_operator = 'lte' then v_match := v_number <= v_first;
      elsif p_operator = 'gt' then v_match := v_number > v_first;
      elsif p_operator = 'gte' then v_match := v_number >= v_first;
      elsif p_operator = 'between' then
        v_second := (p_values ->> 1)::numeric;
        v_match := v_number between least(v_first, v_second)
          and greatest(v_first, v_second);
      elsif p_operator = 'in' then
        v_match := exists (
          select 1 from jsonb_array_elements(p_values) requested(value)
          where v_number = (requested.value #>> '{}')::numeric
        );
      end if;
    elsif v_definition.data_type = 'boolean' then
      if v_value.value_boolean is null then return 'conflict'; end if;
      v_boolean := (p_values ->> 0)::boolean;
      if p_operator = 'eq' then v_match := v_value.value_boolean = v_boolean;
      elsif p_operator = 'neq' then v_match := v_value.value_boolean <> v_boolean;
      end if;
    elsif v_definition.data_type in ('single_select', 'multi_select', 'text') then
      if p_operator = 'contains' then
        v_candidate_normalized := public.assistant_normalize_query_internal_v1(
          p_values ->> 0
        );
        v_match := position(v_candidate_normalized in
          public.assistant_normalize_query_internal_v1(concat_ws(' ',
            v_value.value_text, v_value.value_option, v_value.display_value,
            v_value.value_json::text
          ))) > 0;
      else
        v_match := exists (
          select 1
          from jsonb_array_elements(p_values) requested(value)
          where public.assistant_normalize_query_internal_v1(
              requested.value #>> '{}'
            ) in (
              public.assistant_normalize_query_internal_v1(v_value.value_text),
              public.assistant_normalize_query_internal_v1(v_value.value_option),
              public.assistant_normalize_query_internal_v1(v_value.display_value)
            )
            or (
              jsonb_typeof(v_value.value_json) = 'array'
              and exists (
                select 1
                from jsonb_array_elements(v_value.value_json) member(value)
                where jsonb_typeof(member.value) in ('string', 'number', 'boolean')
                  and public.assistant_normalize_query_internal_v1(
                    member.value #>> '{}'
                  ) = public.assistant_normalize_query_internal_v1(
                    requested.value #>> '{}'
                  )
              )
            )
        );
        if p_operator = 'neq' then v_match := not v_match; end if;
      end if;
    end if;
    -- **La procedencia viaja.** Una lectura del nombre no se disfraza de ficha
    -- del taller: sale con su propio token y cada consumidor decide si la
    -- acepta. Un `conflict` sí es un conflicto venga de donde venga.
    return case
      when not v_match then 'conflict'
      when v_value.source = 'name_reading' then 'name_reading'
      else 'product_spec' end;
  end if;

  -- Curated identity may fill only exact equality/membership for an empty
  -- ficha. It is never a range engine: 68x122.5 cannot prove "eje < 125".
  if p_operator in ('eq', 'in') then
    for v_candidate in
      select requested.value #>> '{}'
      from jsonb_array_elements(p_values) requested(value)
    loop
      v_candidate_normalized := public.assistant_normalize_query_internal_v1(
        v_candidate
      );
      if position(
           ' ' || v_candidate_normalized || ' '
           in ' ' || coalesce(p_identity_surface, '') || ' '
         ) > 0
         or (
           v_candidate_normalized ~ '^[0-9]+(?:[.]?[0-9]+)?$'
           and coalesce(p_identity_raw, '') ~ (
             '(^|[^0-9.])' || replace(v_candidate_normalized, '.', '[.]') ||
             '([^0-9.]|$)'
           )
         ) then
        return 'identity_fallback';
      end if;
    end loop;
  end if;
  return 'unresolved';
end;
$function$;

CREATE OR REPLACE FUNCTION public.assistant_inventory_technical_filter_source_internal_v1(p_tenant_id uuid, p_product_id uuid, p_field_key text, p_requested_value text, p_identity_surface text, p_identity_raw text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_requested text;
  v_definition_id uuid;
begin
  v_definition_id:=public.spec_product_field_definition_internal_v1(p_tenant_id,p_product_id,p_field_key);
  if v_definition_id is null then return 'unresolved'; end if;
  v_requested := public.assistant_normalize_query_internal_v1(p_requested_value);

  if exists (
    select 1
    from public.product_spec_values value
    join public.spec_definitions definition
      on definition.id = value.spec_definition_id
     and definition.id = v_definition_id
     and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
    where value.tenant_id = p_tenant_id
      and value.product_id = p_product_id
      and (
        public.assistant_normalize_query_internal_v1(value.value_option) = v_requested
        or public.assistant_normalize_query_internal_v1(value.value_text) = v_requested
        or public.assistant_normalize_query_internal_v1(value.display_value) = v_requested
        or public.assistant_normalize_query_internal_v1(value.value_number::text) = v_requested
        or public.assistant_normalize_query_internal_v1(value.value_boolean::text) = v_requested
        or (
          jsonb_typeof(value.value_json) = 'array'
          and exists (
            select 1
            from jsonb_array_elements(value.value_json) member(value)
            where jsonb_typeof(member.value) in ('string', 'number', 'boolean')
              and public.assistant_normalize_query_internal_v1(
                member.value #>> '{}'
              ) = v_requested
          )
        )
      )
  ) then
    return 'product_spec';
  end if;

  -- Any populated canonical value owns the field. A conflicting value cannot
  -- be overruled by a product name, description, SKU or model-generated prose.
  if exists (
    select 1
    from public.product_spec_values value
    join public.spec_definitions definition
      on definition.id = value.spec_definition_id
     and definition.id = v_definition_id
     and (definition.tenant_id is null or definition.tenant_id = p_tenant_id)
    where value.tenant_id = p_tenant_id
      and value.product_id = p_product_id
  ) then
    return 'conflict';
  end if;

  -- Sparse catalogs remain searchable only from the curated identity surface.
  -- Identifier substrings and compatibility/description prose never satisfy
  -- an absent technical field.
  if position(
       ' ' || v_requested || ' '
       in ' ' || coalesce(p_identity_surface, '') || ' '
     ) > 0
     or (
       v_requested ~ '^[0-9]+$'
       and coalesce(p_identity_raw, '') ~ (
         '(^|[^0-9])' || v_requested || '([^0-9]|$)'
       )
     ) then
    return 'identity_fallback';
  end if;

  return 'unresolved';
end;
$function$;

CREATE OR REPLACE FUNCTION public.supply_need_eligible_products_internal_v1(p_tenant_id uuid, p_need_id uuid, p_max_universe integer DEFAULT 400)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_context record;
  v_universe_size integer := 0;
  v_predicates jsonb;
  v_predicate_count integer;
  v_items jsonb;
  v_scoped_ids uuid[];
  v_available_fields jsonb := '[]'::jsonb;
  v_detail jsonb;
begin
  if p_max_universe is null or p_max_universe not between 1 and 5000 then
    raise exception 'Invalid eligible product bound' using errcode = '22023';
  end if;

  select * into v_context
  from public.supply_need_resolution_context_internal_v1(
    p_tenant_id, p_need_id
  );

  -- Sólo los predicados técnicos: `ranking_profile` y `commercial_preference`
  -- viven en el mismo arreglo y no son criterios de compatibilidad.
  select coalesce(jsonb_agg(entry.value), '[]'::jsonb)
  into v_predicates
  from jsonb_array_elements(v_context.constraints) entry(value)
  where entry.value ? 'field' and entry.value ? 'operator'
    and entry.value ? 'values';
  v_predicate_count := jsonb_array_length(v_predicates);

  -- Carril exacto: el universo es un solo producto y no se ensancha.
  if v_context.product_id is not null
     and v_context.identity_state = 'confirmed' then
    v_detail := public.supply_need_match_detail_internal_v1(
      p_tenant_id, v_context.product_id, v_predicates
    );
    return jsonb_build_object(
      'status', 'ok',
      'lane', 'exact',
      'categoryId', v_context.category_id,
      'universeSize', 1,
      'safeLimit', p_max_universe,
      'predicateCount', v_predicate_count,
      'items', jsonb_build_array(jsonb_build_object(
        'productId', v_context.product_id,
        'matchState', public.supply_need_match_state_internal_v1(
          v_detail, v_predicate_count
        ),
        'matchDetail', v_detail
      ))
    );
  end if;

  if v_context.category_id is null then
    return jsonb_build_object(
      'status', 'identity_unresolved',
      'lane', 'family',
      'categoryId', null,
      'universeSize', 0,
      'safeLimit', p_max_universe,
      'predicateCount', v_predicate_count,
      'items', '[]'::jsonb
    );
  end if;

  -- El universo se cuenta ANTES de evaluar: el techo es sobre lo que habría
  -- que mirar, no sobre lo que sobrevive.
  with recursive category_scope as (
    select category.id
    from public.product_categories category
    where category.tenant_id = p_tenant_id
      and category.id = v_context.category_id
      and category.is_active is true
    union all
    select child.id
    from public.product_categories child
    join category_scope parent on child.parent_id = parent.id
    where child.tenant_id = p_tenant_id and child.is_active is true
  )
  , category_products as materialized (
    select product.id from public.products product
    where product.tenant_id=p_tenant_id and product.is_active
      and not coalesce(product.is_service,false)
      and coalesce(product.product_type,'product')<>'service'
      and product.category_id in(select id from category_scope)
  ), bound_products as materialized (
    select product.id,b.template_id,t.form_contract
    from category_products product
    join public.product_spec_bindings_internal_v1 b on b.product_id=product.id
    left join public.spec_templates t on t.id=b.template_id
  )
  select coalesce(array_agg(product.id),'{}'::uuid[]) into v_scoped_ids
  from bound_products product
  where product.template_id is null or not exists(
    select 1 from jsonb_array_elements(v_predicates) criterion
    where not exists(select 1 from public.spec_template_fields f
      join public.spec_definitions d on d.id=f.spec_definition_id
      where f.template_id=product.template_id and d.key=criterion->>'field'
        and (d.tenant_id is null or d.tenant_id=p_tenant_id)
        and coalesce(product.form_contract->'roles'->>d.key,'primary')<>'legacy'));
  v_universe_size:=cardinality(v_scoped_ids);

  if v_universe_size > p_max_universe then
    -- La plantilla activa la resuelve su dueño de la Fase A, no una variante
    -- local. Resolverla acá con `coalesce(mapping.template_id, …)` publicaba
    -- los campos de una plantilla **inactiva** cuando el mapeo la nombraba
    -- explícitamente: se le ofrecía al operador refinar por criterios que el
    -- taller ya había retirado.
    with recursive scoped_categories as (
      select id from public.product_categories where id=v_context.category_id and tenant_id=p_tenant_id and is_active
      union all
      select c.id from public.product_categories c join scoped_categories parent on c.parent_id=parent.id
      where c.tenant_id=p_tenant_id and c.is_active
    )
    select coalesce(jsonb_agg(distinct d.key),'[]'::jsonb) into v_available_fields
    from public.category_spec_template_scope_internal_v1 scope
    join public.spec_template_fields f on f.template_id=scope.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id
    join public.spec_templates active_template on active_template.id=scope.template_id
      and coalesce(active_template.form_contract->'roles'->>d.key,'primary')<>'legacy'
    where scope.tenant_id=p_tenant_id and scope.category_id in(select id from scoped_categories)
      and (d.tenant_id is null or d.tenant_id=p_tenant_id) and d.is_filterable;

    -- Refinar es una acción concreta: se dice cuántos hay, cuál es el techo y
    -- qué campos de la plantilla sirven para acotar. «Sé más específico» no
    -- es una respuesta.
    return jsonb_build_object(
      'status', 'needs_refinement',
      'lane', 'family',
      'categoryId', v_context.category_id,
      'universeSize', v_universe_size,
      'safeLimit', p_max_universe,
      'predicateCount', v_predicate_count,
      'availableFields', v_available_fields,
      'items', '[]'::jsonb
    );
  end if;

  -- Se evalúa el universo entero y recién después se excluye `conflict`.
  --
  -- **El alcance se cierra ANTES de evaluar, y por eso `scoped` es
  -- `materialized`.** La llamada por producto acababa en el filtro
  -- del scan de `products`, así que el planificador la ejecutaba durante ese
  -- scan y **antes** del join que restringe a la categoría: medido el
  -- 2026-08-31 sobre la necesidad real de pastillas, `Seq Scan on products
  -- (rows=1554)` con 7154 ms para juzgar 49 productos. Se pagaba el juicio
  -- completo de las 1554 filas del tenant para descartar 1505 después.
  --
  -- No se recorta el universo ni cambia qué se considera compatible: se
  -- evalúan exactamente los mismos productos que antes sobrevivían al filtro.
  -- Lo único que cambia es cuándo. Misma medición tras el cambio: 289 ms y
  -- 2013 buffers, contra 7160 ms y 51 691.
  with scoped as materialized (
    -- Reuse the exact bounded set; do not resolve each binding per criterion
    -- or scan a second time between counting and evaluating.
    select unnest(v_scoped_ids) product_id
  ), evaluated as materialized (
    select scoped.product_id,
      public.supply_need_match_detail_internal_v1(
        p_tenant_id, scoped.product_id, v_predicates
      ) as match_detail
    from scoped
  ), stated as (
    select evaluated.product_id, evaluated.match_detail,
      public.supply_need_match_state_internal_v1(
        evaluated.match_detail, v_predicate_count
      ) as match_state
    from evaluated
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'productId', stated.product_id,
    'matchState', stated.match_state,
    'matchDetail', stated.match_detail
  ) order by stated.product_id), '[]'::jsonb)
  into v_items
  from stated
  where stated.match_state <> 'conflict';

  return jsonb_build_object(
    'status', 'ok',
    'lane', 'family',
    'categoryId', v_context.category_id,
    'universeSize', v_universe_size,
    'safeLimit', p_max_universe,
    'predicateCount', v_predicate_count,
    'items', v_items
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.supply_need_stock_candidates_v1(p_need_id uuid, p_limit integer DEFAULT 8)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
 SET statement_timeout TO '9000ms'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_need record;
  v_items jsonb;
  v_total integer := 0;
  v_dropped_words text;
  v_dropped_filters text;
begin
  if v_tenant_id is null then
    raise exception 'No tenant context' using errcode = '42501';
  end if;
  if p_limit not between 1 and 20 then
    raise exception 'Invalid stock candidate arguments' using errcode = '22023';
  end if;

  select need.id, need.original_description, need.product_id
  into v_need
  from public.supply_needs need
  where need.id = p_need_id and need.tenant_id = v_tenant_id;

  if v_need.id is null then
    raise exception 'Supply need not found' using errcode = 'P0002';
  end if;

  -- Con producto confirmado esta lectura no aplica: la bodega exacta ya la
  -- publica `get_supply_need_inventory_snapshot_v1`, que es su dueña. Dos
  -- verdades sobre el mismo stock es peor que una sola incompleta.
  if v_need.product_id is not null then
    return jsonb_build_object(
      'asOf', clock_timestamp(),
      'items', '[]'::jsonb,
      'resultCount', 0,
      'totalMatches', 0,
      'reason', 'identity_confirmed'
    );
  end if;

  -- **Las características que el asistente ya tradujo mandan sobre la frase.**
  --
  -- La interpretación guarda predicados tipados —`wheel_size = 27.5"`,
  -- `valve_type = Schrader (americana / auto)`— y este paso los ignoraba: volvía
  -- a resolver `original_description` como texto. Con «camaras 27.5 con válvula
  -- de auto» eso devolvía 33 alternativas donde la ficha dice 12, porque el
  -- texto no sabe de válvulas.
  --
  -- Se leen los del revision más reciente. Si no hay ninguno —una necesidad sin
  -- características, o escrita antes de que existieran— el camino sigue siendo
  -- la frase, que es lo que hace que esto no sea obligatorio: se avanza igual.
  with criterios as (
    select predicado.value ->> 'field' campo,
      predicado.value -> 'values' valores
    from public.supply_need_interpretation_revisions revision
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(revision.constraints) = 'array'
      then revision.constraints else '[]'::jsonb end
    ) predicado(value)
    where revision.tenant_id = v_tenant_id
      and revision.supply_need_id = v_need.id
      and revision.revision_no = (
        select max(newest.revision_no)
        from public.supply_need_interpretation_revisions newest
        where newest.tenant_id = v_tenant_id
          and newest.supply_need_id = v_need.id
      )
      and predicado.value ? 'field'
      and jsonb_typeof(predicado.value -> 'values') = 'array'
  ), por_ficha as (
    -- Un producto entra si cumple TODAS las características pedidas. El valor
    -- viaja como etiqueta —así lo guarda el asistente— y por eso se compara
    -- contra `spec_definition_values.label`.
    select fact.subject_id product_id
    from public.spec_facts fact
    join public.spec_definitions definition
      on definition.id = fact.spec_definition_id
    join public.spec_fact_values fact_value on fact_value.fact_id = fact.id
    join public.spec_definition_values value_row
      on value_row.id = fact_value.value_id
    join criterios on criterios.campo = definition.key
     and value_row.label in (
       select valor #>> '{}' from jsonb_array_elements(criterios.valores) valor
     )
    where fact.tenant_id = v_tenant_id
      and fact.subject_type = 'product'
       and fact.subject_scope is null
       and public.spec_product_definition_is_active_internal_v1(v_tenant_id,fact.subject_id,fact.spec_definition_id)
    group by fact.subject_id
    having count(distinct definition.key) = (select count(*) from criterios)
  ), resolved as materialized (
    select * from public.purchase_query_products_internal_v1(
      v_tenant_id, v_need.original_description, false
    )
    where not exists (select 1 from criterios)
    union all
    select por_ficha.product_id, null::text, null::text, null::text[]
    from por_ficha
  ), stock as (
    select product.id,
      product.name,
      product.sku,
      product.brand,
      product.category_name,
      product.price,
      product.cost,
      coalesce(product.track_stock, false) tracks_inventory,
      public.inventory_available_quantity_v1(product.tenant_id, product.id)
        available,
      max(resolved.dropped_words) over () dropped_words,
      max(resolved.dropped_filters) over () dropped_filters,
      count(*) over ()::integer matched
    from public.products product
    join resolved on resolved.product_id = product.id
    where product.tenant_id = v_tenant_id
      and product.is_active is true
  ), ranked as (
    select stock.*,
      row_number() over (
        -- Lo que hay primero: un producto que calza y está en cero no le
        -- resuelve el día a nadie, pero saber que existe sí evita crearlo
        -- de nuevo.
        order by (case when available > 0 then 0 else 1 end), available desc,
          name
      )::integer rank
    from stock
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'productId', id,
      'name', name,
      'sku', sku,
      'brand', brand,
      'category', category_name,
      'available', available,
      'tracksInventory', tracks_inventory,
      'priceGross', price,
      'costNet', cost
    ) order by rank) filter (where rank <= p_limit), '[]'::jsonb),
    coalesce(max(matched), 0),
    max(dropped_words),
    max(dropped_filters)
  into v_items, v_total, v_dropped_words, v_dropped_filters
  from ranked;

  return jsonb_build_object(
    'asOf', clock_timestamp(),
    'items', v_items,
    'resultCount', jsonb_array_length(v_items),
    'totalMatches', v_total,
    'hasMore', v_total > p_limit,
    'droppedWords', v_dropped_words,
    'droppedFilters', v_dropped_filters,
    'reason', case when v_total = 0 then 'no_match' else 'candidates' end
  );
end;
$function$;

notify pgrst, 'reload schema';
commit;
