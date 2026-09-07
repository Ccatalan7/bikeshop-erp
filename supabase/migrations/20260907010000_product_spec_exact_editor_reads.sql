-- Versioned exact numeric reads. V1 consumers keep their existing JSON types.
-- No product, fact, reference or template data is changed by this migration.
begin;
do $preimage$
declare x record; actual text;
begin
 for x in select * from (values
 ('get_product_spec_editor_context_v1(uuid,uuid)','f22771ee06c6934df9637f11a2e8030c'),
 ('spec_payload_display_internal_v1(jsonb)','4b968349fa25437f1c931ec50378f452'),
 ('spec_template_product_payload_internal_v1(uuid,uuid,boolean)','a56ef26e739ff4b3687d9f07f9065cb0'),
 ('get_product_spec_references_v1(text)','a5b42a3914d654170a43b2c8a16c626f'),
 ('spec_unassigned_facts_internal_v1(uuid,uuid)','3bf820b8dc28859670c5d0fa5e11f89e')
 ) e(signature,hash) loop
   actual:=md5(pg_get_functiondef(to_regprocedure('public.'||x.signature)));
   if actual is distinct from x.hash then
     raise exception 'Exact editor dependency drift: %',x.signature using errcode='55000';
   end if;
 end loop;
end $preimage$;

do $new_functions$
declare x record; actual text;
begin
 for x in select * from (values
 ('get_product_spec_editor_context_v2(uuid,uuid)','ffc95bc18f46105a9b7dc3a702e485a6'),
 ('get_product_spec_references_v2(text)','9fa7a332a7002cbdfe9a815d246096fb'),
 ('spec_editor_rule_numbers_as_text_internal_v1(jsonb)','4d73e8cbbaeb6dd2c373f4369dacbba5'),
 ('spec_json_numbers_as_text_internal_v1(jsonb)','29bc24fcc3975cc2ad6ba42268da60d4'),
 ('spec_payload_display_exact_internal_v1(jsonb)','052421b50d689600494ef0f7ab33dc73')
 ) e(signature,hash) loop
   actual:=md5(pg_get_functiondef(to_regprocedure('public.'||x.signature)));
   if actual is not null and actual is distinct from x.hash then
     raise exception 'Exact editor function preimage drift: %',x.signature using errcode='55000';
   end if;
 end loop;
end $new_functions$;

create or replace function public.spec_json_numbers_as_text_internal_v1(p_value jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $numbers$
begin
 case jsonb_typeof(p_value)
 when 'number' then return to_jsonb(p_value#>>'{}');
 when 'array' then return (select coalesce(jsonb_agg(public.spec_json_numbers_as_text_internal_v1(value) order by ordinality),'[]'::jsonb)
   from jsonb_array_elements(p_value) with ordinality);
 when 'object' then return (select coalesce(jsonb_object_agg(key,public.spec_json_numbers_as_text_internal_v1(value)),'{}'::jsonb) from jsonb_each(p_value));
 else return p_value;
 end case;
end $numbers$;

-- Convert operands/bounds, never versions, sort order, booleans or token text.
create or replace function public.spec_editor_rule_numbers_as_text_internal_v1(p_value jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $rules$
begin
 if jsonb_typeof(p_value)='array' then
   return (select coalesce(jsonb_agg(public.spec_editor_rule_numbers_as_text_internal_v1(value) order by ordinality),'[]'::jsonb)
     from jsonb_array_elements(p_value) with ordinality);
 elsif jsonb_typeof(p_value)='object' then
   return (select coalesce(jsonb_object_agg(key,case when key in ('min','max','value','allow')
     then public.spec_json_numbers_as_text_internal_v1(value)
     else public.spec_editor_rule_numbers_as_text_internal_v1(value) end),'{}'::jsonb) from jsonb_each(p_value));
 end if;
 return p_value;
end $rules$;

create or replace function public.spec_payload_display_exact_internal_v1(p_payload jsonb)
returns jsonb language sql stable set search_path=pg_catalog,public,pg_temp as $display$
 select public.spec_payload_display_internal_v1(p_payload) ||
   coalesce((select jsonb_object_agg(d.key,to_jsonb((e.value->>'number')::numeric::text))
     from jsonb_each(coalesce(p_payload,'{}')) e
     join public.spec_definitions d on d.id::text=e.key
     where d.data_type='number' and e.value ? 'number'),'{}'::jsonb)
$display$;

create or replace function public.get_product_spec_editor_context_v2(p_product_id uuid,p_category_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $editor$
#variable_conflict use_variable
declare result jsonb; template_id uuid; template jsonb; fields jsonb; unassigned jsonb;
 tenant uuid:=public.user_tenant_id();
begin
 -- This call enforces product/category tenant ownership and explicit binding.
 -- STABLE nested reads share this statement's MVCC snapshot.
 result:=public.get_product_spec_editor_context_v1(p_product_id,p_category_id);
 template_id:=(result->>'template_id')::uuid;
 if template_id is not null then
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
 end if;
 select coalesce(jsonb_agg(case when d.data_type='number' then e.value||jsonb_build_object(
     'value',public.spec_json_numbers_as_text_internal_v1(e.value->'value')) else e.value end order by e.ordinality),'[]'::jsonb)
 into unassigned from jsonb_array_elements(result->'unassigned_facts') with ordinality e
 left join public.spec_definitions d on d.id::text=e.value->>'definition_id';
 return result||jsonb_build_object('read_schema_version',2,'product_id',p_product_id,'draft_category_id',p_category_id,
   'template',template,'unassigned_facts',unassigned,
   'values',public.spec_payload_display_exact_internal_v1(public.spec_template_product_payload_internal_v1(p_product_id,template_id,true)));
end $editor$;

create or replace function public.get_product_spec_references_v2(p_family text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $references$
begin
 if auth.uid() is null or public.user_tenant_id() is null then
   raise exception 'Authenticated tenant required' using errcode='42501';
 end if;
 return (select coalesce(jsonb_agg((to_jsonb(r)-'fact_values')||jsonb_build_object(
   'read_schema_version',2,'facts',public.spec_payload_display_exact_internal_v1(r.fact_values)) order by r.label),'[]'::jsonb)
   from public.product_spec_references r where r.technical_family=p_family);
end $references$;

revoke all on function public.spec_json_numbers_as_text_internal_v1(jsonb),
 public.spec_editor_rule_numbers_as_text_internal_v1(jsonb),public.spec_payload_display_exact_internal_v1(jsonb)
 from public,anon,authenticated;
grant execute on function public.spec_json_numbers_as_text_internal_v1(jsonb),
 public.spec_editor_rule_numbers_as_text_internal_v1(jsonb),public.spec_payload_display_exact_internal_v1(jsonb) to service_role;
revoke all on function public.get_product_spec_editor_context_v2(uuid,uuid),public.get_product_spec_references_v2(text) from public,anon;
grant execute on function public.get_product_spec_editor_context_v2(uuid,uuid),public.get_product_spec_references_v2(text) to authenticated;
notify pgrst,'reload schema';
commit;
