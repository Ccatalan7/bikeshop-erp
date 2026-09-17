-- Research fills follow the rows schema version each definition declares.
-- fill-005 (2026-09-16): front_derailleur_clamp_options, headset_lower_bearing_
-- configuration and headset_upper_bearing_configuration carry rows_schema
-- version 2 (strict ordered pairs, 20260908185800) and the row validator
-- rightly refuses a version-1 payload for them, but the research merge, the
-- preview's empty-envelope test and the row-conditions probe still had version
-- 1 written in, so no research fill could ever reach those three fields. The
-- editor (product_spec_rows_field.dart) already sends the definition's version.
-- Rerunnable: create or replace only.
begin;
set local lock_timeout='5s';
set local statement_timeout='120s';

create or replace function public.spec_merge_research_rows_internal_v1(p_current jsonb,p_patch jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $merge_rows$
declare version jsonb; original jsonb; old_row jsonb; patch_row jsonb; merged jsonb:='[]'; sources jsonb;
begin
 -- The rows carry the version their definition's rows_schema declares and the
 -- row validator refuses any other; the fill therefore names that version
 -- explicitly, and a delta never migrates rows written under an older one.
 if jsonb_typeof(p_patch) is distinct from 'object' then
   raise exception 'El llenado de configuraciones requiere filas por ID, sin borrado implícito' using errcode='23514';
 end if;
 version:=p_patch->'schema_version';
 if version is null or jsonb_typeof(version)<>'number' or (version#>>'{}') !~ '^[1-9][0-9]{0,8}$' then
   raise exception 'La versión del esquema de filas debe ser un entero positivo' using errcode='23514';
 end if;
 original:=coalesce(nullif(p_current,'null'::jsonb),jsonb_build_object('schema_version',version,'rows','[]'::jsonb));
 if jsonb_typeof(p_patch->'rows') is distinct from 'array' or p_patch->'rows'='[]'::jsonb
   or exists(select 1 from jsonb_object_keys(p_patch) k where k not in ('schema_version','rows'))
   or jsonb_typeof(original) is distinct from 'object' or jsonb_typeof(original->'rows') is distinct from 'array' then
   raise exception 'El llenado de configuraciones requiere filas por ID, sin borrado implícito' using errcode='23514';
 end if;
 if original->'schema_version' is distinct from version then
   raise exception 'Las filas guardadas tienen otra versión de esquema: requieren saneamiento' using errcode='23514';
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
   or e.value='[]'::jsonb or (jsonb_typeof(e.value)='object' and e.value->'rows'='[]'::jsonb)
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
 'Authenticated read-only draft simulation with current server preimage, identity allowlist, explicit fact delta, preserved observations, and canonical validation. It writes nothing and grants no authority.';
revoke all on function public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text) from public,anon,authenticated;
grant execute on function public.preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text) to authenticated,service_role;

CREATE OR REPLACE FUNCTION public.spec_row_conditions_metadata_internal_v1(p_contract jsonb, p_fields jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare block jsonb:=p_contract->'row_conditions'; field record; bucket record; cell record;
 schema jsonb; columns jsonb; col jsonb; predicate jsonb; input jsonb; choices jsonb; edges jsonb; expressions jsonb; expression jsonb; rule jsonb; expected jsonb;
begin
 if not(p_contract ? 'row_conditions') then return; end if;
 if p_contract->'rules_version' is distinct from '2'::jsonb or jsonb_typeof(block) is distinct from 'object' then
   raise exception 'Condiciones de configuración inválidas' using errcode='23514';
 end if;
 if block->'version' is distinct from '1'::jsonb or jsonb_typeof(block->'fields') is distinct from 'object'
   or exists(select 1 from jsonb_object_keys(block) k where k not in ('version','fields')) then
   raise exception 'Condiciones de configuración inválidas' using errcode='23514';
 end if;
 for field in select * from jsonb_each(block->'fields') loop
   schema:=p_fields->field.key->'schema';
   if p_fields->field.key->>'data_type' is distinct from 'json' or jsonb_typeof(schema) is distinct from 'object'
     or jsonb_typeof(field.value) is distinct from 'object' or field.value='{}'::jsonb then
     raise exception 'Las condiciones usan un campo de filas no disponible' using errcode='23514';
   end if;
   perform public.spec_rows_schema_validate_internal_v1(schema);
   select jsonb_object_agg(c->>'key',c) into columns from jsonb_array_elements(schema->'columns') c;
   edges:='[]';
   for bucket in select * from jsonb_each(field.value) loop
     if bucket.key not in ('allowed_when','required_when','allowed_options','value_when') or jsonb_typeof(bucket.value) is distinct from 'object' then
       raise exception 'Falta un mapa de condiciones de columnas' using errcode='23514';
     end if;
     for cell in select * from jsonb_each(bucket.value) loop
       col:=columns->cell.key;
       if col is null then raise exception 'Una condición apunta a otra configuración' using errcode='23514'; end if;
       if bucket.key='allowed_options' then
         if col->>'type'<>'token' or jsonb_typeof(cell.value) is distinct from 'array' then
           raise exception 'Las opciones exceden el dominio de la columna' using errcode='23514';
         end if;
         if jsonb_array_length(cell.value)<>(select count(distinct v) from jsonb_array_elements(cell.value) v)
           or exists(select 1 from jsonb_array_elements(cell.value) v where jsonb_typeof(v)<>'string' or v#>>'{}'=''
             or (jsonb_array_length(coalesce(col->'allowed_values','[]'))>0 and not(col->'allowed_values' @> jsonb_build_array(v)))) then
           raise exception 'Las opciones exceden el dominio de la columna' using errcode='23514';
         end if;
         continue;
       end if;
       if bucket.key='value_when' then
         if jsonb_typeof(cell.value) is distinct from 'array' then
           raise exception 'Una columna necesita reglas de valor condicionado' using errcode='23514';
         end if;
         if jsonb_array_length(cell.value)=0 then
           raise exception 'Una columna necesita reglas de valor condicionado' using errcode='23514';
         end if;
         expressions:='[]';
         for rule in select value from jsonb_array_elements(cell.value) loop
           if jsonb_typeof(rule) is distinct from 'object' then
             raise exception 'Regla de valor condicionado inválida' using errcode='23514';
           end if;
           if not(rule ?& array['when','expected'])
             or exists(select 1 from jsonb_object_keys(rule) k where k not in ('when','expected'))
             or jsonb_typeof(rule->'expected') is distinct from 'object'
             or jsonb_typeof(rule->'when') is distinct from 'object' then
             raise exception 'Regla de valor condicionado inválida' using errcode='23514';
           end if;
           expected:=rule->'expected';
           if not(expected ?& array['value_type','value'])
             or exists(select 1 from jsonb_object_keys(expected) k where k not in ('value_type','value'))
             or coalesce(expected->>'value_type','') not in ('boolean','token','decimal')
             or (expected->>'value_type'='boolean' and col->>'type'<>'boolean')
             or (expected->>'value_type'='token' and col->>'type'<>'token')
             or (expected->>'value_type'='decimal' and col->>'type' not in ('decimal','integer'))
             or not public.spec_rule_known_internal_v1(expected->'value') then
             raise exception 'El valor condicionado necesita el tipo y dominio de su columna' using errcode='23514';
           end if;
           -- The row parser owns literal types, exact PG decimals and numeric
           -- domains. A single target observation cannot satisfy another cell.
           perform public.spec_rows_validate_internal_v1(schema,jsonb_build_object('schema_version',schema->'version','rows',
             jsonb_build_array(jsonb_build_object('id','expected','values',jsonb_build_object(cell.key,expected->'value'),'sources','[]'::jsonb))));
           if field.value->'allowed_options' ? cell.key and
             not(field.value->'allowed_options'->cell.key @> jsonb_build_array(expected->'value')) then
             raise exception 'El valor condicionado excede las opciones de esta ficha' using errcode='23514';
           end if;
           expressions:=expressions||jsonb_build_array(rule->'when');
         end loop;
       else
         expressions:=jsonb_build_array(cell.value);
       end if;
       for expression in select value from jsonb_array_elements(expressions) loop
       if bucket.key='value_when' then
         begin
           perform public.spec_template_condition_internal_v1(expression,'{}');
         exception when invalid_parameter_value then
           raise exception 'Condición de valor de configuración inválida' using errcode='23514';
         end;
       else
         perform public.spec_template_condition_internal_v1(expression,'{}');
       end if;
       if bucket.key='allowed_when' and col->'required'='true'::jsonb and expression->>'kind'<>'always' then
         raise exception 'Una columna obligatoria del esquema no puede hacerse condicional' using errcode='23514';
       end if;
       for predicate in select p from jsonb_array_elements(coalesce(expression->'rows','[]')) r
         cross join lateral jsonb_array_elements(r) pp(p) loop
         input:=columns->(predicate->>'field');
         if input is null or (predicate->>'value_type'='boolean' and input->>'type'<>'boolean')
           or (predicate->>'value_type'='decimal' and input->>'type' not in ('decimal','integer'))
           or (predicate->>'value_type'='token' and input->>'type' not in ('text','token')) then
           raise exception 'Un requisito usa una columna o un tipo ajeno' using errcode='23514';
         end if;
         choices:=case when predicate->>'operator'='in' then predicate->'value' else jsonb_build_array(predicate->'value') end;
         if jsonb_array_length(coalesce(input->'allowed_values','[]'))>0 and not(input->'allowed_values' @> choices) then
           raise exception 'Un requisito usa una opción ajena a la columna' using errcode='23514';
         end if;
         edges:=edges||jsonb_build_array(jsonb_build_array(cell.key,predicate->>'field'));
       end loop;
       end loop;
     end loop;
   end loop;
   if exists(with recursive e(a,b) as (select p->>0,p->>1 from jsonb_array_elements(edges) p),
     paths(tip,visited,cycle) as (
       select b,array[a,b],a=b from e
       union all select e.b,p.visited||e.b,e.b=any(p.visited)
         from paths p join e on e.a=p.tip where not p.cycle
     ) select 1 from paths where cycle) then
     raise exception 'Los requisitos de una configuración forman un ciclo' using errcode='23514';
   end if;
 end loop;
end $function$
;
revoke all on function public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb) to service_role;
commit;
