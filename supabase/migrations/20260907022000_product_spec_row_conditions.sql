-- Same-row conditions and template-specific column options. No fact/catalogue writes.
begin;
do $preimage$ declare x record; actual text; begin
 for x in select * from (values
 ('save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamp with time zone,jsonb)','d7fd562e5e269f82b25a1b3cf417b2a6','007ed3a67a009527c24ed54ee3380b99'),
 ('spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','06dc1b93436b1ac5693142b2eace82ec','48f01ef6f5343dfe3a45285ad227fb60'),
 ('spec_coherence_metadata_internal_v1(jsonb,jsonb)','94ea287f2f4b1c0782253c722eb3e0e7','863ba9ce738f2c6d497e1a3786c02eb5'),
 ('spec_coherence_publication_guard_internal_v1()','bcc98eaa28aeb87f265e569ba587c007','1d9f691d7e044034255f7500c21feb7c'),
 ('spec_template_rules_validate_internal_v1(uuid)','fc4875e265b52a847b6a63f406487f96','273b46c7568552a6e2641eec4f69f59c')
 ) p(signature,before_hash,after_hash) loop
  actual:=md5(pg_get_functiondef(to_regprocedure('public.'||x.signature)));
  if actual is distinct from x.before_hash and actual is distinct from x.after_hash then
   raise exception 'Row conditions preimage drift: %',x.signature;
  end if;
 end loop;
end $preimage$;
create or replace function public.spec_row_conditions_metadata_internal_v1(p_contract jsonb,p_fields jsonb)
returns void language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $row_metadata$
#variable_conflict use_column
declare block jsonb:=p_contract->'row_conditions'; field record; bucket record; cell record;
 schema jsonb; columns jsonb; col jsonb; predicate jsonb; input jsonb; choices jsonb; edges jsonb;
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
     if bucket.key not in ('allowed_when','required_when','allowed_options') or jsonb_typeof(bucket.value) is distinct from 'object' then
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
       perform public.spec_template_condition_internal_v1(cell.value,'{}');
       if bucket.key='allowed_when' and col->'required'='true'::jsonb and cell.value->>'kind'<>'always' then
         raise exception 'Una columna obligatoria del esquema no puede hacerse condicional' using errcode='23514';
       end if;
       for predicate in select p from jsonb_array_elements(coalesce(cell.value->'rows','[]')) r
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
   if exists(with recursive e(a,b) as (select p->>0,p->>1 from jsonb_array_elements(edges) p),
     paths(tip,visited,cycle) as (
       select b,array[a,b],a=b from e
       union all select e.b,p.visited||e.b,e.b=any(p.visited)
         from paths p join e on e.a=p.tip where not p.cycle
     ) select 1 from paths where cycle) then
     raise exception 'Los requisitos de una configuración forman un ciclo' using errcode='23514';
   end if;
 end loop;
end $row_metadata$;

create or replace function public.spec_row_conditions_issues_internal_v1(p_contract jsonb,p_fields jsonb,p_values jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $row_issues$
#variable_conflict use_column
declare result jsonb:='[]'; field record; schema jsonb; document jsonb; r jsonb; col jsonb;
 cells jsonb; allowed boolean; required boolean; known boolean; options jsonb; code text; message text; blocking boolean;
begin
 perform public.spec_row_conditions_metadata_internal_v1(p_contract,p_fields);
 for field in select * from jsonb_each(coalesce(p_contract->'row_conditions'->'fields','{}')) loop
   if not public.spec_rule_known_internal_v1(p_values->field.key) then continue; end if;
   schema:=p_fields->field.key->'schema';
   begin
     document:=public.spec_rows_validate_internal_v1(schema,p_values->field.key);
   exception when check_violation then
     result:=result||jsonb_build_array(jsonb_build_object('code','row_shape','field',field.key,
       'message','La configuración tiene un formato inválido. Sus datos se conservan.','blocking',true));
     continue;
   end;
   for r in select value from jsonb_array_elements(document->'rows') loop
     cells:=r->'values';
     for col in select value from jsonb_array_elements(schema->'columns') loop
       known:=public.spec_rule_known_internal_v1(cells->(col->>'key'));
       allowed:=public.spec_template_condition_internal_v1(coalesce(field.value->'allowed_when'->(col->>'key'),'{"kind":"always"}'),cells);
       required:=case when col->'required'='true'::jsonb then true else
         public.spec_template_condition_internal_v1(coalesce(field.value->'required_when'->(col->>'key'),'{"kind":"never"}'),cells) end;
       code:=null; message:=null; blocking:=false;
       if allowed is false then
         if known then code:='row_field_applicability';blocking:=true;message:='El dato no corresponde a los requisitos de esta configuración.'; end if;
       elsif allowed is null then code:='row_prerequisite';message:='Confirma primero los requisitos de esta configuración.';
       elsif not known and required is null then code:='row_prerequisite';message:='Falta determinar si este dato es necesario.';
       elsif not known and required and col->'required' is distinct from 'true'::jsonb then
         code:='row_required_missing';message:='Falta confirmar este dato de la configuración.';
       end if;
       if code is not null then result:=result||jsonb_build_array(jsonb_build_object('code',code,'field',field.key,'row_id',r->>'id',
         'column',col->>'key','message',(col->>'label')||': '||message,'blocking',blocking)); end if;
       if allowed is false then continue; end if;
       options:=field.value->'allowed_options'->(col->>'key');
       if known and options is not null and not(options @> jsonb_build_array(cells->(col->>'key'))) then
         result:=result||jsonb_build_array(jsonb_build_object('code','row_option','field',field.key,'row_id',r->>'id',
           'column',col->>'key','message',(col->>'label')||': La opción no pertenece a esta ficha.','blocking',true));
       end if;
     end loop;
   end loop;
 end loop;
 return result;
end $row_issues$;

alter function public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb) owner to postgres;
alter function public.spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb) owner to postgres;
revoke all on function public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.spec_row_conditions_metadata_internal_v1(jsonb,jsonb) to service_role;
grant execute on function public.spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb) to service_role;

CREATE OR REPLACE FUNCTION public.spec_coherence_issues_internal_v1(p_contract jsonb, p_fields jsonb, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare result jsonb:='[]'; parsed jsonb:='{}'; invalid text[]:='{}'; link jsonb; r jsonb; target jsonb;
 key text; pair jsonb; v_cell jsonb; field text;
begin
 result:=public.spec_row_conditions_issues_internal_v1(p_contract,p_fields,p_values);
 for key in select distinct k from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'links','[]')) l
   cross join lateral (values(l->>'field'),(l->>'target_field')) keys(k) order by k loop
   if not public.spec_rule_known_internal_v1(p_values->key) then continue; end if;
   begin
     v_cell:=public.spec_rows_validate_internal_v1(p_fields->key->'schema',p_values->key);
     parsed:=jsonb_set(parsed,array[key],v_cell);
   exception when check_violation then
     invalid:=array_append(invalid,key);
     if not exists(select 1 from jsonb_array_elements(result) i where i->>'code'='row_shape' and i->>'field'=key) then
       result:=result||jsonb_build_array(jsonb_build_object('code','row_shape','field',key,
         'message','La configuración tiene un formato inválido. Sus datos se conservan.','blocking',true));
     end if;
   end;
 end loop;
 for link in select value from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'links','[]')) loop
   if link->>'field'=any(invalid) or link->>'target_field'=any(invalid) then continue; end if;
   target:=parsed->(link->>'target_field');
   for r in select value from jsonb_array_elements(coalesce(parsed->(link->>'field')->'rows','[]')) loop
     v_cell:=r->'values'->(link->>'column');
     if v_cell is null then continue; end if;
     if target is null then
       result:=result||jsonb_build_array(jsonb_build_object('code','row_reference_pending','field',link->>'field',
         'row_id',r->>'id','column',link->>'column','message','Define primero la configuración de destino.','blocking',false));
     elsif not exists(select 1 from jsonb_array_elements(target->'rows') t where t->'id'=v_cell) then
       result:=result||jsonb_build_array(jsonb_build_object('code','row_reference_unresolved','field',link->>'field',
         'row_id',r->>'id','column',link->>'column','message','La configuración vinculada no existe en esta ficha. Revisa el vínculo.','blocking',true));
     end if;
   end loop;
 end loop;
 for pair in select value from jsonb_array_elements(public.spec_coherence_pairs_internal_v1(p_contract,p_fields)) loop
   if public.spec_rule_number_internal_v1(p_values->(pair->>0)) > public.spec_rule_number_internal_v1(p_values->(pair->>1)) then
     for field in select jsonb_array_elements_text(pair) loop
       result:=result||jsonb_build_array(jsonb_build_object('code','range_order','field',field,
         'message','El límite inferior no puede superar el superior.','blocking',true));
     end loop;
   end if;
 end loop;
 return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.spec_coherence_metadata_internal_v1(p_contract jsonb, p_fields jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare block jsonb:=p_contract->'row_coherence'; links jsonb; link jsonb; other_link jsonb; col jsonb;
 source jsonb; target jsonb; pair jsonb; ids text[]:='{}'; cells text[]:='{}'; seen text[]:='{}'; key text;
begin
 perform public.spec_row_conditions_metadata_internal_v1(p_contract,p_fields);
 if (p_contract ? 'row_coherence' or p_contract ? 'scalar_ordered_pairs')
   and p_contract->'rules_version' is distinct from '2'::jsonb then
   raise exception 'La coherencia requiere condiciones de ficha v2' using errcode='23514';
 end if;
 if p_contract ? 'row_coherence' then
   if jsonb_typeof(block) is distinct from 'object' then raise exception 'Contrato de vínculos inválido' using errcode='23514'; end if;
   if block->'version' is distinct from '1'::jsonb or jsonb_typeof(block->'links') is distinct from 'array'
     or exists(select 1 from jsonb_object_keys(block) k where k not in ('version','links')) then
     raise exception 'Contrato de vínculos inválido' using errcode='23514';
   end if;
   links:=block->'links';
   for link in select value from jsonb_array_elements(links) loop
     if jsonb_typeof(link) is distinct from 'object' then raise exception 'Vínculo inválido' using errcode='23514'; end if;
     if (select count(*) from jsonb_object_keys(link))<>5
       or exists(select 1 from jsonb_object_keys(link) k where k not in ('id','field','column','target_field','label_columns')) then
       raise exception 'Claves de vínculo inválidas' using errcode='23514';
     end if;
     foreach key in array array['id','field','column','target_field'] loop
       if jsonb_typeof(link->key) is distinct from 'string' or link->>key !~ '^[a-z][a-z0-9_]*$'
         or link->>key ~ '[[:space:]]' then
         raise exception 'Identificador de vínculo inválido' using errcode='23514';
       end if;
     end loop;
     if link->>'field'=link->>'target_field' or link->>'id'=any(ids)
       or (link->>'field')||'.'||(link->>'column')=any(cells) then
       raise exception 'Vínculo duplicado o autorreferente' using errcode='23514';
     end if;
     ids:=array_append(ids,link->>'id'); cells:=array_append(cells,(link->>'field')||'.'||(link->>'column'));
     source:=p_fields->(link->>'field'); target:=p_fields->(link->>'target_field');
     if source->>'data_type' is distinct from 'json' or target->>'data_type' is distinct from 'json'
       or jsonb_typeof(source->'schema') is distinct from 'object' or jsonb_typeof(target->'schema') is distinct from 'object' then
       raise exception 'Extremo de vínculo no disponible' using errcode='23514';
     end if;
     perform public.spec_rows_schema_validate_internal_v1(source->'schema');
     perform public.spec_rows_schema_validate_internal_v1(target->'schema');
     select c into col from jsonb_array_elements(source->'schema'->'columns') c where c->>'key'=link->>'column';
     if col is null or col->>'type' not in ('text','token') or jsonb_array_length(coalesce(col->'allowed_values','[]'))>0 then
       raise exception 'La columna del vínculo necesita un identificador libre' using errcode='23514';
     end if;
     if jsonb_typeof(link->'label_columns') is distinct from 'array' then raise exception 'Etiqueta de vínculo inválida' using errcode='23514'; end if;
     if jsonb_array_length(link->'label_columns')=0
       or jsonb_array_length(link->'label_columns')<>(select count(distinct x) from jsonb_array_elements(link->'label_columns') x)
       or exists(select 1 from jsonb_array_elements(link->'label_columns') x where jsonb_typeof(x)<>'string'
         or not exists(select 1 from jsonb_array_elements(target->'schema'->'columns') c where c->>'key'=x#>>'{}')) then
       raise exception 'La etiqueta usa columnas ajenas o duplicadas' using errcode='23514';
     end if;
   end loop;
   for link in select value from jsonb_array_elements(links) loop
     if exists(select 1 from jsonb_array_elements(links) x where x->>'field'=link->>'target_field'
       and link->'label_columns' @> jsonb_build_array(x->'column')) then
       raise exception 'La etiqueta del destino no puede ser otro vínculo' using errcode='23514';
     end if;
   end loop;
 end if;
 if p_contract ? 'scalar_ordered_pairs' then
   if jsonb_typeof(p_contract->'scalar_ordered_pairs') is distinct from 'array' then
     raise exception 'Orden de límites inválido' using errcode='23514';
   end if;
   for pair in select value from jsonb_array_elements(p_contract->'scalar_ordered_pairs') loop
     if jsonb_typeof(pair) is distinct from 'array' then raise exception 'Par de límites inválido' using errcode='23514'; end if;
     if jsonb_array_length(pair)<>2 or pair->0=pair->1 or pair::text=any(seen)
       or exists(select 1 from jsonb_array_elements(pair) k where jsonb_typeof(k)<>'string' or p_fields->(k#>>'{}')->>'data_type' is distinct from 'number')
       or (p_fields->(pair->>0)->'unit') is distinct from (p_fields->(pair->>1)->'unit') then
       raise exception 'Los límites requieren dos campos numéricos distintos con la misma unidad' using errcode='23514';
     end if;
     seen:=array_append(seen,pair::text);
   end loop;
 end if;
 if exists(with recursive edges(a,b) as (
   select pair->>0,pair->>1 from jsonb_array_elements(public.spec_coherence_pairs_internal_v1(p_contract,p_fields)) pair
 ), paths(start,tip,visited,cycle) as (
   select a,b,array[a,b],a=b from edges
   union all select p.start,e.b,p.visited||e.b,e.b=any(p.visited)
   from paths p join edges e on e.a=p.tip where not p.cycle
 ) select 1 from paths where cycle) then
   raise exception 'El orden de límites no puede contradecirse en un ciclo' using errcode='23514';
 end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.spec_coherence_publication_guard_internal_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare endpoints text[]; previous jsonb; old_links jsonb; new_links jsonb;
begin
 perform public.spec_coherence_metadata_internal_v1(new.form_contract,public.spec_coherence_fields_internal_v1(new.id));
 previous:=case when tg_op='UPDATE' then old.form_contract else '{}'::jsonb end;
 select coalesce(jsonb_agg(l-'label_columns'-'id' order by l->>'field',l->>'column',l->>'target_field'),'[]') into old_links
   from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')) l;
 select coalesce(jsonb_agg(l-'label_columns'-'id' order by l->>'field',l->>'column',l->>'target_field'),'[]') into new_links
   from jsonb_array_elements(coalesce(new.form_contract->'row_coherence'->'links','[]')) l;
 if old_links=new_links and previous->'scalar_ordered_pairs' is not distinct from new.form_contract->'scalar_ordered_pairs'
   and previous->'row_conditions' is not distinct from new.form_contract->'row_conditions' then return new; end if;
 -- This is an AFTER trigger: malformed metadata is rejected by the shape guard,
 -- not interpreted here as an empty relation. No in-place activation over facts.
 select array_agg(distinct key) into endpoints from (
   select l->>'field' key from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')||coalesce(new.form_contract->'row_coherence'->'links','[]')) l
   union select l->>'target_field' from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')||coalesce(new.form_contract->'row_coherence'->'links','[]')) l
   union select jsonb_array_elements_text(pair) from jsonb_array_elements(coalesce(previous->'scalar_ordered_pairs','[]')||coalesce(new.form_contract->'scalar_ordered_pairs','[]')) pair
   union select jsonb_object_keys(coalesce(previous->'row_conditions'->'fields','{}')||coalesce(new.form_contract->'row_conditions'->'fields','{}'))
 ) keys;
 -- Fact and reference writers hold SHARE on their definitions. Wait for them
 -- in a separate statement, then re-read population with a fresh snapshot.
 -- An AFTER check alone can otherwise miss a concurrent committed fact.
 perform d.id from public.spec_template_fields tf join public.spec_definitions d on d.id=tf.spec_definition_id
   where tf.template_id=new.id and d.key=any(endpoints) order by d.id for update of d;
 if exists(select 1 from public.spec_template_fields tf join public.spec_definitions d on d.id=tf.spec_definition_id
   where tf.template_id=new.id and d.key=any(endpoints) and (
     exists(select 1 from public.spec_facts f where f.spec_definition_id=d.id)
     or exists(select 1 from public.product_spec_references r where r.fact_values ? d.id::text))) then
   raise exception 'La coherencia de datos poblados requiere una migración revisada con diagnóstico previo' using errcode='23514';
 end if;
 return new;
end $function$
;

CREATE OR REPLACE FUNCTION public.spec_template_rules_validate_internal_v1(p_template_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare contract jsonb; keys text[]; e record; c jsonb; dep text; bucket text; dtype text; choices jsonb;
 legacy_edges jsonb;
begin
 -- Serialize metadata changes against each other; otherwise a definition edit
 -- and a condition edit could each validate against the other's old value.
 select form_contract into contract from public.spec_templates where id=p_template_id for update;
 if contract ? 'row_coherence' or contract ? 'scalar_ordered_pairs' or contract ? 'row_conditions' then
   if contract->'rules_version' is distinct from '2'::jsonb then raise exception 'La coherencia requiere condiciones de ficha v2' using errcode='23514'; end if;
 end if;
 if contract is null or not(contract ? 'rules_version') then return; end if;
 if contract->'rules_version'='1'::jsonb then return; end if;
 if contract->'rules_version' is distinct from '2'::jsonb then
   raise exception 'Versión de condiciones de ficha inválida' using errcode='23514';
 end if;
 perform d.id from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
   where f.template_id=p_template_id order by d.id for share of d;
 perform public.spec_coherence_metadata_internal_v1(contract,public.spec_coherence_fields_internal_v1(p_template_id));
 select array_agg(d.key) into keys from public.spec_template_fields f
 join public.spec_definitions d on d.id=f.spec_definition_id where f.template_id=p_template_id;
 keys:=coalesce(keys,'{}');
 if cardinality(keys)<>(select count(distinct k) from unnest(keys) k) then
   raise exception 'La ficha repite una clave técnica' using errcode='23514';
 end if;
 foreach bucket in array array['allowed_when','required_when','allowed_options','prerequisites'] loop
   if jsonb_typeof(contract->bucket) is distinct from 'object' then
     raise exception 'Falta el mapa de % en la ficha',bucket using errcode='23514';
   end if;
   for e in select * from jsonb_each(contract->bucket) loop
     if not(e.key=any(keys)) then raise exception 'Campo ajeno en %: %',bucket,e.key using errcode='23514'; end if;
     if bucket in ('allowed_when','required_when') then
       perform public.spec_template_condition_internal_v1(e.value,'{}');
       for c in select condition from jsonb_array_elements(coalesce(e.value->'rows','[]')) r
         cross join lateral jsonb_array_elements(r) cc(condition) loop
         if not(c->>'field'=any(keys)) then raise exception 'Requisito de otra ficha: %',c->>'field' using errcode='23514'; end if;
         if coalesce(contract->'roles'->>(c->>'field'),'primary')='legacy' then
           raise exception 'Un requisito no puede depender de un dato retirado' using errcode='23514';
         end if;
         select d.data_type,d.allowed_values into dtype,choices from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
           where f.template_id=p_template_id and d.key=c->>'field';
         if (c->>'value_type'='boolean' and dtype<>'boolean')
           or (c->>'value_type'='decimal' and dtype<>'number')
           or (c->>'value_type'='token' and dtype not in ('single_select','text')) then
           raise exception 'El requisito compara un tipo diferente al campo: %',c->>'field' using errcode='23514';
         end if;
         if dtype='single_select' and not(coalesce(choices,'[]') @> case when c->>'operator'='in' then c->'value' else jsonb_build_array(c->'value') end) then
           raise exception 'El requisito usa una opción ajena al campo: %',c->>'field' using errcode='23514';
         end if;
       end loop;
     elsif bucket='prerequisites' then
       if jsonb_typeof(e.value)<>'array' then raise exception 'Prerrequisitos inválidos' using errcode='23514'; end if;
       if exists(select 1 from jsonb_array_elements(e.value) v where jsonb_typeof(v)<>'string' or v#>>'{}'='') then
         raise exception 'Cada prerrequisito debe identificar un campo' using errcode='23514';
       end if;
       for dep in select jsonb_array_elements_text(e.value) loop
         if not(dep=any(keys)) then raise exception 'Prerrequisito de otra ficha: %',dep using errcode='23514'; end if;
         if coalesce(contract->'roles'->>dep,'primary')='legacy' then
           raise exception 'Un requisito no puede depender de un dato retirado' using errcode='23514';
         end if;
       end loop;
     else
       if jsonb_typeof(e.value)<>'array' then raise exception 'Opciones de ficha inválidas' using errcode='23514'; end if;
       select d.data_type,d.allowed_values into dtype,choices from public.spec_template_fields f
         join public.spec_definitions d on d.id=f.spec_definition_id where f.template_id=p_template_id and d.key=e.key;
       if dtype='boolean' then choices:='["true","false"]'; end if;
       if dtype not in ('single_select','multi_select','boolean') or exists(select 1 from jsonb_array_elements(e.value) v
         where jsonb_typeof(v)<>'string' or not(coalesce(choices,'[]') @> jsonb_build_array(v))) then
         raise exception 'Opciones ajenas al dominio de %',e.key using errcode='23514';
       end if;
     end if;
   end loop;
 end loop;
 -- Legacy visibility remains conjunctive. Follow its actual all/any grammar
 -- so those prerequisites cannot form an invisible cycle with new conditions.
 for e in select d.key,d.data_type,d.allowed_values,f.constraint_rules from public.spec_template_fields f
   join public.spec_definitions d on d.id=f.spec_definition_id where f.template_id=p_template_id
   and coalesce(contract->'roles'->>d.key,'primary')<>'legacy' loop
   for c in select value from jsonb_array_elements(coalesce(e.constraint_rules,'[]')) loop
     if e.data_type not in ('single_select','multi_select','boolean') or jsonb_typeof(c->'allow') is distinct from 'array' then
       raise exception 'Una restricción de opciones necesita un campo de elección' using errcode='23514';
     end if;
     for choices in select value from jsonb_array_elements(c->'allow') loop
       if e.data_type='boolean' and choices in ('true'::jsonb,'false'::jsonb,'"true"'::jsonb,'"false"'::jsonb) then continue; end if;
       if jsonb_typeof(choices)<>'string' or not(coalesce(e.allowed_values,'[]') @> jsonb_build_array(choices)) then
         raise exception 'Opción de restricción ajena al campo' using errcode='23514';
       end if;
     end loop;
   end loop;
 end loop;
 with recursive clauses(parent,body,affects_visibility) as (
   select d.key,r,part.affects_visibility from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
     cross join lateral (values (f.visibility_rules,true),(f.constraint_rules,false)) part(rules,affects_visibility)
     cross join lateral jsonb_array_elements(coalesce(part.rules,'[]')) rr(r)
     where f.template_id=p_template_id and coalesce(contract->'roles'->>d.key,'primary')<>'legacy'
   union all
   select c.parent,child,c.affects_visibility from clauses c cross join lateral jsonb_array_elements(
     case when c.body ? 'all' then c.body->'all' when c.body ? 'any' then c.body->'any' else '[]' end) cc(child)
 ) select coalesce(jsonb_agg(jsonb_build_object('parent',parent,'child',body->'field','visibility',affects_visibility)),'[]') into legacy_edges
   from clauses where not(body ? 'all' or body ? 'any');
 for c in select value from jsonb_array_elements(legacy_edges) loop
   if jsonb_typeof(c->'child') is distinct from 'string' or not(c->>'child'=any(keys))
     or coalesce(contract->'roles'->>(c->>'child'),'primary')='legacy' then
     raise exception 'La visibilidad heredada depende de un campo no disponible' using errcode='23514';
   end if;
 end loop;
 if exists(with recursive edges(parent,child) as (
   select e.key,dep from jsonb_each(contract->'prerequisites') e cross join lateral jsonb_array_elements_text(e.value) dd(dep)
   union select e.key,c->>'field' from jsonb_each(contract->'allowed_when') e
     cross join lateral jsonb_array_elements(coalesce(e.value->'rows','[]')) r
     cross join lateral jsonb_array_elements(r) cc(c)
   union select c->>'parent',c->>'child' from jsonb_array_elements(legacy_edges) cc(c) where c->>'visibility'='true'
   union select l->>'field',l->>'target_field' from jsonb_array_elements(coalesce(contract->'row_coherence'->'links','[]')) l
 ), paths(start,tip,visited,cycle) as (
   select parent,child,array[parent,child],parent=child from edges
   union all select p.start,e.child,p.visited||e.child,e.child=any(p.visited)
     from paths p join edges e on e.parent=p.tip where not p.cycle
 ) select 1 from paths where cycle) then
   raise exception 'Los prerrequisitos de la ficha forman un ciclo' using errcode='23514';
 end if;
end $function$
;

-- Hold the selected contract stable before checking the client's version.
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
    v_product.spec_template_id) for share of t;
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
end $function$
;
commit;
