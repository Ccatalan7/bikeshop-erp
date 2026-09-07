-- Authenticated, read-only research preimage. No catalogue or product writes.
begin;

-- Refuse drift in the existing readers and collisions with these new names.
-- Accept the reviewed postimage too so a local verification can replay safely.
do $preimage$
declare expected record; actual record; fn regprocedure;
begin
 for expected in select * from (values
  ('get_product_spec_references_v1(text)','a5b42a3914d654170a43b2c8a16c626f','ac13815c1272725a784596953b771531',true,true,'s'),
  ('get_product_spec_references_v2(text)','9fa7a332a7002cbdfe9a815d246096fb','ffb27b5770dee7a7ce0675eea552ce9b',true,true,'s'),
  ('get_product_spec_research_snapshot_v1(uuid)',null,'981026d3283612b825ff3231d0d9ab41',true,true,'s'),
  ('preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)',null,'a48f8882900af7d7e945ad4cbc561df2',true,true,'s'),
  ('spec_merge_research_rows_internal_v1(jsonb,jsonb)',null,'079b3e15c5db9903476f94801394691d',false,false,'i'),
  ('spec_reference_global_scope_internal_v1(text)',null,'f60238e0b53dabe706b1939af477b96a',false,false,'s')
 ) e(signature,old_md5,new_md5,definer,authenticated_execute,volatility) loop
  fn:=to_regprocedure('public.'||expected.signature);
  if fn is null then
   if expected.old_md5 is not null then
    raise exception 'Missing required research reader: %',expected.signature;
   end if;
   continue;
  end if;
  select p.*,pg_get_userbyid(p.proowner) owner_name,md5(pg_get_functiondef(p.oid)) body_md5
   into actual from pg_proc p where p.oid=fn;
  if actual.body_md5 is distinct from expected.new_md5
    and actual.body_md5 is distinct from expected.old_md5 then
   raise exception 'Unreviewed research reader preimage: %',expected.signature;
  end if;
  if actual.owner_name<>'postgres' or actual.prosecdef<>expected.definer
   or actual.provolatile::text<>expected.volatility
   or actual.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp']::text[]
   or has_function_privilege('anon',fn,'execute')
   or has_function_privilege('authenticated',fn,'execute')<>expected.authenticated_execute
   or not has_function_privilege('service_role',fn,'execute')
   or exists(select 1 from aclexplode(coalesce(actual.proacl,acldefault('f',actual.proowner))) a
     where a.grantee not in ('postgres'::regrole::oid,'service_role'::regrole::oid,
       case when expected.authenticated_execute then 'authenticated'::regrole::oid else 'postgres'::regrole::oid end)
       or a.grantor<>actual.proowner or a.is_grantable or a.privilege_type<>'EXECUTE') then
   raise exception 'Unreviewed research reader security: %',expected.signature;
  end if;
 end loop;
end $preimage$;

create or replace function public.spec_reference_global_scope_internal_v1(p_family text)
returns void language plpgsql stable set search_path=pg_catalog,public,pg_temp as $global_scope$
begin
 if exists(select 1 from public.product_spec_references r
   cross join lateral jsonb_each(r.fact_values) f
   left join public.spec_definitions d on d.id::text=f.key
   where r.technical_family=p_family and (d.id is null or d.tenant_id is not null)) then
   raise exception 'La referencia global usa una definición no disponible' using errcode='42501';
 end if;
 if exists(select 1 from public.product_spec_references r
   cross join lateral jsonb_each(r.fact_values) f
   join public.spec_definitions d on d.id::text=f.key
   where r.technical_family=p_family and d.data_type in ('single_select','multi_select') and (
     jsonb_typeof(f.value->'value_ids') is distinct from 'array'
     or case when jsonb_typeof(f.value->'value_ids')='array' then
       jsonb_array_length(f.value->'value_ids')=0
       or (d.data_type='single_select' and jsonb_array_length(f.value->'value_ids')<>1)
       or jsonb_array_length(f.value->'value_ids')<>(select count(distinct x) from jsonb_array_elements(f.value->'value_ids') x)
       or exists(select 1 from jsonb_array_elements(f.value->'value_ids') x
         where jsonb_typeof(x)<>'string' or not exists(select 1 from public.spec_definition_values o
           where o.id::text=x#>>'{}' and o.spec_definition_id=d.id and o.tenant_id is null and o.is_active))
     else false end)) then
   raise exception 'La referencia global usa opciones no disponibles' using errcode='42501';
 end if;
end $global_scope$;
revoke all on function public.spec_reference_global_scope_internal_v1(text) from public,anon,authenticated;
grant execute on function public.spec_reference_global_scope_internal_v1(text) to service_role;

create or replace function public.get_product_spec_references_v1(p_family text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $legacy_references$
begin
 -- Preserve the v1 empty result and numeric wire format for old clients.
 if auth.uid() is null or public.user_tenant_id() is null then return '[]'::jsonb; end if;
 perform public.spec_reference_global_scope_internal_v1(p_family);
 return (select coalesce(jsonb_agg((to_jsonb(r)-'fact_values')||jsonb_build_object(
   'facts',public.spec_payload_display_internal_v1(r.fact_values)) order by r.label),'[]'::jsonb)
   from public.product_spec_references r where r.technical_family=p_family);
end $legacy_references$;
revoke all on function public.get_product_spec_references_v1(text) from public,anon,authenticated;
grant execute on function public.get_product_spec_references_v1(text) to authenticated,service_role;

-- References are global. Their definition and option IDs must therefore be
-- global too, before any definer formatter projects a label for the caller.
create or replace function public.get_product_spec_references_v2(p_family text)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $references$
begin
 if auth.uid() is null or public.user_tenant_id() is null then
   raise exception 'Authenticated tenant required' using errcode='42501';
 end if;
 perform public.spec_reference_global_scope_internal_v1(p_family);
 return (select coalesce(jsonb_agg((to_jsonb(r)-'fact_values')||jsonb_build_object(
   'read_schema_version',2,'facts',public.spec_payload_display_exact_internal_v1(r.fact_values)) order by r.label),'[]'::jsonb)
   from public.product_spec_references r where r.technical_family=p_family);
end $references$;
revoke all on function public.get_product_spec_references_v2(text) from public,anon,authenticated;
grant execute on function public.get_product_spec_references_v2(text) to authenticated,service_role;

create or replace function public.get_product_spec_research_snapshot_v1(p_product_id uuid)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $research_snapshot$
declare
 tenant uuid:=public.user_tenant_id(); actor uuid:=auth.uid();
 product public.products%rowtype; editor jsonb; facts jsonb; references_json jsonb;
 product_json jsonb; fingerprints jsonb;
begin
 if actor is null or tenant is null then
   raise exception 'Authenticated tenant required' using errcode='42501';
 end if;
 select * into product from public.products p where p.id=p_product_id and p.tenant_id=tenant;
 if not found then raise exception 'Producto no disponible para este tenant' using errcode='42501'; end if;
 -- A malformed historical association is an error, never an invitation to
 -- expose another tenant's data or silently omit an existing observation.
 if exists(select 1 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
   where f.subject_type='product' and f.subject_id=product.id
     and (f.tenant_id<>tenant or (d.tenant_id is not null and d.tenant_id<>tenant)))
   or exists(select 1 from public.spec_facts f join public.spec_fact_readings r on r.fact_id=f.id
     where f.subject_type='product' and f.subject_id=product.id and r.tenant_id<>tenant)
   or exists(select 1 from public.spec_facts f join public.spec_fact_values v on v.fact_id=f.id
     join public.spec_definition_values o on o.id=v.value_id
     where f.subject_type='product' and f.subject_id=product.id
       and (o.spec_definition_id<>f.spec_definition_id or (o.tenant_id is not null and o.tenant_id<>tenant))) then
   raise exception 'Observación no disponible para este tenant' using errcode='42501';
 end if;
 -- STABLE nested readers use the calling statement's MVCC snapshot. The
 -- caller cannot replace the saved category with a draft category here.
 editor:=public.get_product_spec_editor_context_v2(product.id,product.category_id);
 references_json:=public.get_product_spec_references_v2(editor->>'technical_family');
 select coalesce(jsonb_agg(jsonb_build_object(
   'fact',to_jsonb(f)-'value_json'||jsonb_build_object(
     'value_number',f.value_number::text,'value_json_text',f.value_json::text),
   'definition',jsonb_build_object('id',d.id,'key',d.key,'data_type',d.data_type,'unit',d.unit,
     'definition_sha256',encode(extensions.digest(to_jsonb(d)::text,'sha256'),'hex')),
   'options',v.rows,'readings',r.rows,
   'fact_sha256',encode(extensions.digest(jsonb_build_object(
     'fact',to_jsonb(f),'definition',to_jsonb(d),'options',v.rows,'readings',r.rows)::text,'sha256'),'hex'))
   order by f.id),'[]'::jsonb) into facts
 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
 cross join lateral(select coalesce(jsonb_agg(to_jsonb(v)||jsonb_build_object(
     'option_definition_sha256',encode(extensions.digest(to_jsonb(o)::text,'sha256'),'hex'))
     order by v.position,v.value_id),'[]'::jsonb) rows
   from public.spec_fact_values v join public.spec_definition_values o on o.id=v.value_id where v.fact_id=f.id) v
 cross join lateral(select coalesce(jsonb_agg(to_jsonb(r) order by r.fact_id),'[]'::jsonb) rows
   from public.spec_fact_readings r where r.fact_id=f.id and r.tenant_id=tenant) r
 where f.tenant_id=tenant and f.subject_type='product' and f.subject_id=product.id;
 product_json:=jsonb_build_object('id',product.id,'tenant_id',tenant,
   'name',product.name,'sku',product.sku,'brand',product.brand,'model',product.model,
   'manufacturer_sku',product.manufacturer_sku,'gtin',product.gtin,'barcode',product.barcode,
   'category_id',product.category_id,'spec_template_id',product.spec_template_id,
   'spec_reference_id',product.spec_reference_id,'spec_revision',product.spec_revision,
   'updated_at',product.updated_at,'is_active',product.is_active,'product_type',product.product_type);
 fingerprints:=jsonb_build_object(
   'product_sha256',encode(extensions.digest(to_jsonb(product)::text,'sha256'),'hex'),
   'facts_sha256',encode(extensions.digest(facts::text,'sha256'),'hex'),
   'template_sha256',encode(extensions.digest(coalesce(editor->'template','null'::jsonb)::text,'sha256'),'hex'),
   'references_sha256',encode(extensions.digest(references_json::text,'sha256'),'hex'));
 return jsonb_build_object('read_schema_version',1,'actor_id',actor,'tenant_id',tenant,
   'product',product_json,'editor',editor,'observations',facts,'references',references_json,
   'fingerprints',fingerprints,
   'snapshot_sha256',encode(extensions.digest(jsonb_build_object(
     'fingerprints',fingerprints,'product',product_json,'editor',editor)::text,'sha256'),'hex'));
end $research_snapshot$;

comment on function public.get_product_spec_research_snapshot_v1(uuid) is
 'Read-only research preimage: authenticated tenant, saved identity/binding, exact editor, all product observations/options/readings, and server fingerprints in one MVCC snapshot. Hashes detect drift; they are neither approval nor an apply capability.';
revoke all on function public.get_product_spec_research_snapshot_v1(uuid) from public,anon,authenticated;
grant execute on function public.get_product_spec_research_snapshot_v1(uuid) to authenticated,service_role;

create or replace function public.spec_merge_research_rows_internal_v1(p_current jsonb,p_patch jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $merge_rows$
declare original jsonb:=coalesce(nullif(p_current,'null'::jsonb),'{"schema_version":1,"rows":[]}');
 old_row jsonb; patch_row jsonb; merged jsonb:='[]'; sources jsonb;
begin
 if jsonb_typeof(p_patch) is distinct from 'object' or p_patch->'schema_version' is distinct from '1'::jsonb
   or jsonb_typeof(p_patch->'rows') is distinct from 'array' or p_patch->'rows'='[]'::jsonb
   or exists(select 1 from jsonb_object_keys(p_patch) k where k not in ('schema_version','rows'))
   or jsonb_typeof(original) is distinct from 'object' or original->'schema_version' is distinct from '1'::jsonb
   or jsonb_typeof(original->'rows') is distinct from 'array' then
   raise exception 'El llenado de configuraciones requiere filas por ID, sin borrado implícito' using errcode='23514';
 end if;
 if exists(select 1 from jsonb_array_elements(p_patch->'rows') r
   where jsonb_typeof(r) is distinct from 'object' or jsonb_typeof(r->'id') is distinct from 'string'
     or btrim(r->>'id')='' or jsonb_typeof(r->'values') is distinct from 'object'
     or jsonb_typeof(r->'sources') is distinct from 'array'
     or exists(select 1 from jsonb_object_keys(r) k where k not in ('id','values','sources')))
   or jsonb_array_length(p_patch->'rows')<>(select count(distinct r->>'id') from jsonb_array_elements(p_patch->'rows') r) then
   raise exception 'Cada configuración necesita un ID único y sus celdas/fuentes explícitas' using errcode='23514';
 end if;
 for patch_row in select r from jsonb_array_elements(p_patch->'rows') r loop
   if exists(select 1 from jsonb_each(patch_row->'values') c where c.value='null'::jsonb
      or (jsonb_typeof(c.value)='string' and btrim(c.value#>>'{}')=''))
      or exists(select 1 from jsonb_array_elements(patch_row->'sources') s
        where jsonb_typeof(s)<>'string' or btrim(s#>>'{}')='') then
     raise exception 'El llenado no retira celdas ni fuentes existentes' using errcode='23514';
   end if;
 end loop;
 for old_row in select r from jsonb_array_elements(original->'rows') r loop
   select r into patch_row from jsonb_array_elements(p_patch->'rows') r where r->>'id'=old_row->>'id';
   if patch_row is null then merged:=merged||jsonb_build_array(old_row); continue; end if;
   select coalesce(jsonb_agg(value order by first_position),'[]'::jsonb) into sources from (
     select value,min(ordinality) first_position from jsonb_array_elements((old_row->'sources')||(patch_row->'sources'))
       with ordinality group by value) s;
   merged:=merged||jsonb_build_array(old_row||jsonb_build_object(
     'values',(old_row->'values')||(patch_row->'values'),'sources',sources));
 end loop;
 for patch_row in select r from jsonb_array_elements(p_patch->'rows') r
   where not exists(select 1 from jsonb_array_elements(original->'rows') o where o->>'id'=r->>'id') loop
   merged:=merged||jsonb_build_array(patch_row);
 end loop;
 return original||jsonb_build_object('rows',merged);
end $merge_rows$;
revoke all on function public.spec_merge_research_rows_internal_v1(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.spec_merge_research_rows_internal_v1(jsonb,jsonb) to service_role;

-- This is a simulation against the current persisted template, not an apply
-- command. Unpublished family metadata is tested separately in local rollback.
create or replace function public.preview_product_spec_research_v1(
 p_product_id uuid,p_expected_snapshot_sha256 text,
 p_identity_patch jsonb default '{}'::jsonb,p_values_patch jsonb default '{}'::jsonb,
 p_reference_id text default null)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,pg_temp as $research_preview$
declare snapshot jsonb; editor jsonb; identity_json jsonb; candidate jsonb;
 reference_id text; reference_json jsonb; entry record; issues jsonb; derived_keys jsonb:='[]';
 definition jsonb; definition_id uuid; kind text;
begin
 snapshot:=public.get_product_spec_research_snapshot_v1(p_product_id);
 if p_expected_snapshot_sha256 is null or p_expected_snapshot_sha256 !~ '^[a-f0-9]{64}$'
   or p_expected_snapshot_sha256<>snapshot->>'snapshot_sha256' then
   raise exception 'La ficha cambió desde la investigación; vuelve a leer y revisar la propuesta'
     using errcode='40001';
 end if;
 editor:=snapshot->'editor';
 if editor->>'template_id' is null then
   raise exception 'Primero debe resolverse la familia técnica del producto' using errcode='23514';
 end if;
 if snapshot#>>'{product,product_type}'='service' then
   raise exception 'Los servicios conservan su contrato de trabajo' using errcode='23514';
 end if;
 if jsonb_typeof(p_identity_patch) is distinct from 'object'
   or jsonb_typeof(p_values_patch) is distinct from 'object'
   or octet_length(p_identity_patch::text)>8192 or octet_length(p_values_patch::text)>1048576 then
   raise exception 'Propuesta de investigación inválida' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_each(p_identity_patch) e where e.key not in ('brand','model','manufacturer_sku','gtin')
   or jsonb_typeof(e.value)<>'string' or btrim(e.value#>>'{}')='') then
   raise exception 'La investigación sólo propone identidad explícita y hechos técnicos' using errcode='22023';
 end if;
 if exists(select 1 from jsonb_each(p_values_patch) e where e.value='null'::jsonb
   or (jsonb_typeof(e.value)='string' and btrim(e.value#>>'{}')='')
   or e.value in ('[]'::jsonb,'{"schema_version":1,"rows":[]}'::jsonb)
   or not exists(
   select 1 from jsonb_array_elements(editor#>'{template,fields}') f
   where f#>>'{spec_definitions,key}'=e.key
     and coalesce(editor#>>array['template','form_contract','roles',e.key],'primary')<>'legacy')) then
   raise exception 'La propuesta borra un dato o usa un campo ajeno o legacy' using errcode='23514';
 end if;
 identity_json:=snapshot->'product'||p_identity_patch;
 candidate:=editor->'values'||p_values_patch;
 for entry in select e.* from jsonb_each(p_values_patch) e join lateral(
   select f->'spec_definitions' d from jsonb_array_elements(editor#>'{template,fields}') f
   where f#>>'{spec_definitions,key}'=e.key) metadata on true
   where metadata.d->>'data_type'='json' loop
   candidate:=jsonb_set(candidate,array[entry.key],public.spec_merge_research_rows_internal_v1(
     editor#>array['values',entry.key],entry.value));
 end loop;
 reference_id:=coalesce(p_reference_id,snapshot#>>'{product,spec_reference_id}');
 if reference_id is not null then
   select r into reference_json from jsonb_array_elements(snapshot->'references') r where r->>'id'=reference_id;
   if reference_json is null then
     raise exception 'La referencia no pertenece a la familia actual' using errcode='23514';
   end if;
   -- Validate immutable reference definition IDs before projecting to display
   -- keys. A same-key tenant definition is not the reference's definition.
   if exists(select 1 from public.product_spec_references r cross join lateral jsonb_object_keys(r.fact_values) k
     where r.id=reference_id and not exists(select 1 from public.spec_template_fields f
       join public.spec_definitions d on d.id=f.spec_definition_id
       where f.template_id=(editor->>'template_id')::uuid and f.spec_definition_id::text=k
         and coalesce(editor#>>array['template','form_contract','roles',d.key],'primary')<>'legacy')) then
     raise exception 'La referencia usa un campo ajeno o legacy de esta ficha' using errcode='23514';
   end if;
   -- Existing observations (including unknown/legacy observations) are never
   -- silently replaced by reference facts. Conflicts remain visible to review.
   for entry in select * from jsonb_each(reference_json->'facts') loop
     if not(candidate ? entry.key) then
       candidate:=candidate||jsonb_build_object(entry.key,entry.value);
       derived_keys:=derived_keys||jsonb_build_array(entry.key);
     end if;
   end loop;
 end if;
 -- Draft validators intentionally retain unknown observations. A research
 -- delta must first have the exact field shape; "unknown" is not a number,
 -- false is not 0, and an object is never a text observation.
 for entry in select e.* from jsonb_each(candidate) e where exists(
   select 1 from jsonb_array_elements(editor#>'{template,fields}') f
   where f#>>'{spec_definitions,key}'=e.key
     and coalesce(editor#>>array['template','form_contract','roles',e.key],'primary')<>'legacy') loop
   select f->'spec_definitions',(f->>'spec_definition_id')::uuid into strict definition,definition_id
     from jsonb_array_elements(editor#>'{template,fields}') f where f#>>'{spec_definitions,key}'=entry.key;
   kind:=definition->>'data_type';
   if (kind='number' and (jsonb_typeof(entry.value)<>'string' or public.spec_rule_number_internal_v1(entry.value) is null))
     or (kind='boolean' and jsonb_typeof(entry.value)<>'boolean')
     or (kind in ('text','single_select') and jsonb_typeof(entry.value)<>'string')
     or (kind='multi_select' and jsonb_typeof(entry.value)<>'array')
     or kind not in ('number','boolean','text','single_select','multi_select','json') then
     raise exception 'La observación necesita el tipo exacto de su campo: %',entry.key using errcode='23514';
   end if;
   if kind in ('single_select','multi_select') then
     if exists(select 1 from jsonb_array_elements(case when kind='single_select' then jsonb_build_array(entry.value) else entry.value end) x
       where jsonb_typeof(x)<>'string' or not exists(select 1 from public.spec_definition_values o
         where o.spec_definition_id=definition_id and o.is_active and to_jsonb(o.label)=x
           and (o.tenant_id is null or o.tenant_id=(snapshot->>'tenant_id')::uuid)))
       or (kind='multi_select' and jsonb_array_length(entry.value)<>
         (select count(distinct x) from jsonb_array_elements(entry.value) x)) then
       raise exception 'La selección no pertenece al vocabulario del campo: %',entry.key using errcode='23514';
     end if;
   elsif kind='json' then
     if not(definition->'validation_rules' ? 'rows_schema') then
       raise exception 'El campo JSON necesita un contrato de investigación tipado: %',entry.key using errcode='23514';
     end if;
     perform public.spec_rows_validate_internal_v1(definition#>'{validation_rules,rows_schema}',entry.value);
   end if;
 end loop;
 issues:=public.spec_validate_draft_internal_v1((editor->>'template_id')::uuid,candidate,reference_id,
   identity_json->>'brand',identity_json->>'model',identity_json->>'manufacturer_sku');
 return jsonb_build_object('read_schema_version',1,'mode','simulation','product_id',p_product_id,
   'actor_id',snapshot->'actor_id','tenant_id',snapshot->'tenant_id',
   'snapshot_sha256',snapshot->'snapshot_sha256','fingerprints',snapshot->'fingerprints',
   'revision',editor->'revision','contract_version',editor->'contract_version',
   'template_id',editor->'template_id','identity',identity_json,'values',candidate,
   'reference_id',reference_id,'derived_keys',derived_keys,'issues',issues,
   'valid_draft',not exists(select 1 from jsonb_array_elements(issues) i where coalesce((i->>'blocking')::boolean,true)),
   'mechanical_approval',false,'apply_authorized',false);
end $research_preview$;

comment on function public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text) is
 'Authenticated read-only draft simulation with current server preimage, identity allowlist, explicit fact delta, preserved observations, and canonical validation. It writes nothing and grants no authority to fill products.';
revoke all on function public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text) to authenticated,service_role;
commit;
