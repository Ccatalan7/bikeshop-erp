-- Template-local row occurrence cardinality. No catalogue/fact/reference writes.
-- The stricter bucket is row_coherence v2; old clients reject it as unsupported.
begin;

do $preimages$
declare expected record; actual record; fn regprocedure;
begin
 for expected in select * from (values
  ('spec_coherence_fields_internal_v1(uuid)','e3b437887bdcbb2766d46805beb3a719','842a6575f1eedcef45b7749b76e458e9',false,'s'),
  ('spec_coherence_metadata_internal_v1(jsonb,jsonb)','863ba9ce738f2c6d497e1a3786c02eb5','62b9c8349bf9d4fa4f983d3009980171',false,'i'),
  ('spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','48f01ef6f5343dfe3a45285ad227fb60','d57404a97c12b336e64b59202b3d56f4',false,'i'),
  ('spec_coherence_publication_guard_internal_v1()','1d9f691d7e044034255f7500c21feb7c','235850d2afe7e1571431c7f7c4942b7b',true,'v'),
  ('spec_template_rules_validate_internal_v1(uuid)','273b46c7568552a6e2641eec4f69f59c','61cc6156d8ec2f36a7e9a1cc47b95c53',true,'v'),
  ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','25a18d1d600cf2d8da7c30a59e54123f','9ea12d82761d6ffd0584d460cbc998d6',false,'s')
 ) e(signature,old_md5,new_md5,definer,volatility) loop
  fn:=to_regprocedure('public.'||expected.signature);
  if fn is null then raise exception 'Missing cardinality predecessor: %',expected.signature; end if;
  select p.*,pg_get_userbyid(p.proowner) owner_name,md5(pg_get_functiondef(p.oid)) body_md5
   into actual from pg_proc p where p.oid=fn;
  if actual.body_md5 not in (expected.old_md5,expected.new_md5)
    or actual.owner_name<>'postgres' or actual.prosecdef<>expected.definer or actual.provolatile::text<>expected.volatility
    or actual.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp']::text[]
    or actual.proacl::text is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception 'Unreviewed cardinality preimage/security: %',expected.signature;
  end if;
 end loop;
end $preimages$;

CREATE OR REPLACE FUNCTION public.spec_coherence_fields_internal_v1(p_template_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
 select coalesce(jsonb_object_agg(d.key,jsonb_build_object('data_type',d.data_type,'unit',d.unit,
   'schema',d.validation_rules->'rows_schema','validation_rules',d.validation_rules)),'{}')
 from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
 join public.spec_templates t on t.id=f.template_id
 where f.template_id=p_template_id and coalesce(t.form_contract->'roles'->>d.key,'primary')<>'legacy'
$function$
;

CREATE OR REPLACE FUNCTION public.spec_coherence_metadata_internal_v1(p_contract jsonb, p_fields jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare block jsonb:=p_contract->'row_coherence'; links jsonb; link jsonb; other_link jsonb; col jsonb;
 source jsonb; target jsonb; pair jsonb; cardinality jsonb; rules jsonb; minimum numeric; maximum numeric; collections text[]:='{}'; ids text[]:='{}'; cells text[]:='{}'; seen text[]:='{}'; key text;
begin
 perform public.spec_row_conditions_metadata_internal_v1(p_contract,p_fields);
 if (p_contract ? 'row_coherence' or p_contract ? 'scalar_ordered_pairs')
   and p_contract->'rules_version' is distinct from '2'::jsonb then
   raise exception 'La coherencia requiere condiciones de ficha v2' using errcode='23514';
 end if;
 if p_contract ? 'row_coherence' then
   if jsonb_typeof(block) is distinct from 'object' then raise exception 'Contrato de vínculos inválido' using errcode='23514'; end if;
   if (block->'version' is distinct from '1'::jsonb and
       (jsonb_typeof(block->'version') is distinct from 'number' or block->>'version'<>'2'))
     or jsonb_typeof(block->'links') is distinct from 'array'
     or (block->'version'='1'::jsonb and exists(select 1 from jsonb_object_keys(block) k where k not in ('version','links')))
     or (block->'version'='2'::jsonb and (jsonb_typeof(block->'cardinalities') is distinct from 'array'
       or exists(select 1 from jsonb_object_keys(block) k where k not in ('version','links','cardinalities')))) then
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
   -- V2 declares one independent total per collection. ID counts are never
   -- inferred from cells, labels, mounting positions or another collection.
   for cardinality in select value from jsonb_array_elements(coalesce(block->'cardinalities','[]')) loop
     if jsonb_typeof(cardinality) is distinct from 'object' then
       raise exception 'Cardinalidad inválida' using errcode='23514'; end if;
     if (select count(*) from jsonb_object_keys(cardinality))<>3
       or exists(select 1 from jsonb_object_keys(cardinality) k where k not in ('id','field','total_field')) then
       raise exception 'Claves de cardinalidad inválidas' using errcode='23514'; end if;
     foreach key in array array['id','field','total_field'] loop
       if jsonb_typeof(cardinality->key) is distinct from 'string'
         or cardinality->>key !~ '^[a-z][a-z0-9_]*$' or cardinality->>key ~ '[[:space:]]' then
         raise exception 'Identificador de cardinalidad inválido' using errcode='23514'; end if;
     end loop;
     source:=p_fields->(cardinality->>'field'); target:=p_fields->(cardinality->>'total_field');
     if cardinality->>'id'=any(ids) or cardinality->>'field'=any(collections)
       or source->>'data_type' is distinct from 'json' or jsonb_typeof(source->'schema') is distinct from 'object'
       or target->>'data_type' is distinct from 'number' then
       raise exception 'Extremos de cardinalidad no disponibles o duplicados' using errcode='23514'; end if;
     perform public.spec_rows_schema_validate_internal_v1(source->'schema');
     rules:=target->'validation_rules';
     minimum:=public.spec_rule_number_internal_v1(rules->'min');
     maximum:=public.spec_rule_number_internal_v1(rules->'max');
     if rules->'integer' is distinct from 'true'::jsonb or minimum is null or minimum<0
       or (rules->'max' is not null and rules->'max'<>'null'::jsonb and maximum is null) or minimum>maximum then
       raise exception 'El total de filas necesita un dominio entero no negativo' using errcode='23514'; end if;
     ids:=array_append(ids,cardinality->>'id'); collections:=array_append(collections,cardinality->>'field');
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

CREATE OR REPLACE FUNCTION public.spec_coherence_issues_internal_v1(p_contract jsonb, p_fields jsonb, p_values jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare result jsonb:='[]'; parsed jsonb:='{}'; invalid text[]:='{}'; link jsonb; r jsonb; target jsonb;
 key text; pair jsonb; v_cell jsonb; field text; cardinality jsonb; total numeric; row_count numeric; rules jsonb;
begin
 result:=public.spec_row_conditions_issues_internal_v1(p_contract,p_fields,p_values);
 for key in select distinct k from (
   select k from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'links','[]')) l
     cross join lateral (values(l->>'field'),(l->>'target_field')) keys(k)
   union select c->>'field' from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'cardinalities','[]')) c
 ) endpoints order by k loop
   if not public.spec_rule_known_internal_v1(p_values->key) and not(
     coalesce(jsonb_typeof(p_values->key),'null') not in ('null','string') and exists(select 1 from
       jsonb_array_elements(coalesce(p_contract->'row_coherence'->'cardinalities','[]')) c where c->>'field'=key)) then continue; end if;
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
 for cardinality in select value from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'cardinalities','[]')) loop
   field:=cardinality->>'field'; key:=cardinality->>'total_field';
   -- Do not discard malformed observations to manufacture a smaller collection.
   if field=any(invalid) then continue; end if;
   if p_values->key is null or p_values->key='null'::jsonb
     or (jsonb_typeof(p_values->key)='string' and not public.spec_rule_known_internal_v1(p_values->key)) then
     result:=result||jsonb_build_array(jsonb_build_object('code','row_cardinality_pending','field',field,
       'message','Falta confirmar el total declarado de esta colección.','blocking',false));
     continue;
   end if;
   total:=public.spec_rule_number_internal_v1(p_values->key);
   rules:=p_fields->key->'validation_rules';
   if total is null or total<0 or total<>trunc(total)
     or total<public.spec_rule_number_internal_v1(rules->'min')
     or total>public.spec_rule_number_internal_v1(rules->'max')
     or (rules->'positive'='true'::jsonb and total<=0) then
     result:=result||jsonb_build_array(jsonb_build_object('code','row_cardinality_total','field',key,
       'message','El total debe ser una cantidad entera no negativa dentro del dominio del campo.','blocking',true));
     continue;
   end if;
   row_count:=coalesce(jsonb_array_length(parsed->field->'rows'),0)::numeric;
   if row_count>total then
     result:=result||jsonb_build_array(jsonb_build_object('code','row_cardinality_conflict','field',field,
       'message','Hay más filas documentadas que el total declarado. Revisa el total o las filas; sus datos se conservan.','blocking',true));
   elsif row_count<total then
     result:=result||jsonb_build_array(jsonb_build_object('code','row_cardinality_pending','field',field,
       'message','Faltan filas por documentar para completar el total declarado.','blocking',false));
   end if;
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

CREATE OR REPLACE FUNCTION public.spec_coherence_publication_guard_internal_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
#variable_conflict use_column
declare endpoints text[]; previous jsonb; old_links jsonb; new_links jsonb; old_cardinalities jsonb; new_cardinalities jsonb;
begin
 perform public.spec_coherence_metadata_internal_v1(new.form_contract,public.spec_coherence_fields_internal_v1(new.id));
 previous:=case when tg_op='UPDATE' then old.form_contract else '{}'::jsonb end;
 select coalesce(jsonb_agg(l-'label_columns'-'id' order by l->>'field',l->>'column',l->>'target_field'),'[]') into old_links
   from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')) l;
 select coalesce(jsonb_agg(l-'label_columns'-'id' order by l->>'field',l->>'column',l->>'target_field'),'[]') into new_links
   from jsonb_array_elements(coalesce(new.form_contract->'row_coherence'->'links','[]')) l;
 select coalesce(jsonb_agg(c-'id' order by c->>'field',c->>'total_field'),'[]') into old_cardinalities
   from jsonb_array_elements(coalesce(previous->'row_coherence'->'cardinalities','[]')) c;
 select coalesce(jsonb_agg(c-'id' order by c->>'field',c->>'total_field'),'[]') into new_cardinalities
   from jsonb_array_elements(coalesce(new.form_contract->'row_coherence'->'cardinalities','[]')) c;
 if old_links=new_links and old_cardinalities=new_cardinalities and previous->'scalar_ordered_pairs' is not distinct from new.form_contract->'scalar_ordered_pairs'
   and previous->'row_conditions' is not distinct from new.form_contract->'row_conditions' then return new; end if;
 -- This is an AFTER trigger: malformed metadata is rejected by the shape guard,
 -- not interpreted here as an empty relation. No in-place activation over facts.
 select array_agg(distinct key) into endpoints from (
   select l->>'field' key from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')||coalesce(new.form_contract->'row_coherence'->'links','[]')) l
   union select l->>'target_field' from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')||coalesce(new.form_contract->'row_coherence'->'links','[]')) l
   union select c->>'field' from jsonb_array_elements(coalesce(previous->'row_coherence'->'cardinalities','[]')||coalesce(new.form_contract->'row_coherence'->'cardinalities','[]')) c
   union select c->>'total_field' from jsonb_array_elements(coalesce(previous->'row_coherence'->'cardinalities','[]')||coalesce(new.form_contract->'row_coherence'->'cardinalities','[]')) c
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
   union select c->>'field',c->>'total_field' from jsonb_array_elements(coalesce(contract->'row_coherence'->'cardinalities','[]')) c
 ), paths(start,tip,visited,cycle) as (
   select parent,child,array[parent,child],parent=child from edges
   union all select p.start,e.child,p.visited||e.child,e.child=any(p.visited)
     from paths p join edges e on e.parent=p.tip where not p.cycle
 ) select 1 from paths where cycle) then
   raise exception 'Los prerrequisitos de la ficha forman un ciclo' using errcode='23514';
 end if;
end $function$
;

CREATE OR REPLACE FUNCTION public.spec_validate_draft_internal_v1(p_template_id uuid, p_values jsonb, p_reference_id text DEFAULT NULL::text, p_brand text DEFAULT ''::text, p_model text DEFAULT ''::text, p_manufacturer_sku text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_issues jsonb := '[]'::jsonb; v_field record; v_value jsonb;
  v_rule jsonb; v_allowed text[]; v_next text[]; v_condition boolean;
  v_message text; v_number numeric; v_key text; v_contract jsonb;
  v_applicable boolean; v_required boolean; v_expression jsonb; v_conflict boolean; v_type text;
  v_reference public.product_spec_references%rowtype; v_entry record; v_pair text[]; v_coherence jsonb;
begin
  select form_contract into v_contract from public.spec_templates where id = p_template_id;
  if v_contract is null then raise exception 'Unknown specification template' using errcode = '22023'; end if;
  -- Retired/out-of-template values remain history; neither predicates nor
  -- measurement pair checks may use them to judge the current draft.
  select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) into p_values
  from jsonb_each(p_values) e where exists(
    select 1 from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
    where f.template_id=p_template_id and d.key=e.key
      and coalesce(v_contract->'roles'->>d.key,'primary')<>'legacy');
  if p_reference_id is not null then
    select * into v_reference from public.product_spec_references where id = p_reference_id;
    if not found or lower(btrim(v_reference.brand)) <> lower(btrim(coalesce(p_brand,'')))
      or lower(btrim(v_reference.model)) <> lower(btrim(coalesce(p_model,'')))
      or (v_reference.manufacturer_sku is not null and lower(btrim(v_reference.manufacturer_sku)) <> lower(btrim(coalesce(p_manufacturer_sku,''))))
      or v_reference.technical_family <> (select technical_family from public.spec_templates where id = p_template_id) then
      v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','reference_identity','field','',
        'message','La referencia no corresponde a esta marca, modelo o familia.'));
    end if;
    for v_entry in select * from jsonb_each(public.spec_payload_display_internal_v1(coalesce(v_reference.fact_values,'{}'))) loop
      -- Operator evidence supplements the immutable manufacturer's sources.
      continue when v_entry.key = 'spec_evidence_source';
      v_conflict:=public.spec_rule_set_internal_v1(p_values->v_entry.key) <> public.spec_rule_set_internal_v1(v_entry.value);
      if v_contract->'rules_version'='2'::jsonb then
        select d.data_type into v_type from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
          where f.template_id=p_template_id and d.key=v_entry.key;
        v_conflict:=case when v_type='number' then public.spec_rule_number_internal_v1(p_values->v_entry.key)
            is distinct from public.spec_rule_number_internal_v1(v_entry.value)
          when v_type='multi_select' and jsonb_typeof(p_values->v_entry.key)='array' and jsonb_typeof(v_entry.value)='array' then
            (select jsonb_agg(x order by x) from jsonb_array_elements(p_values->v_entry.key) x)
            is distinct from (select jsonb_agg(x order by x) from jsonb_array_elements(v_entry.value) x)
          else p_values->v_entry.key is distinct from v_entry.value end;
      end if;
      if public.spec_rule_known_internal_v1(p_values->v_entry.key) and v_conflict then
        v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','reference_conflict','field',v_entry.key,
          'message','El valor difiere de la referencia del fabricante.'));
      end if;
    end loop;
  end if;
  for v_field in select d.*, f.visibility_rules, f.constraint_rules from public.spec_template_fields f
    join public.spec_definitions d on d.id = f.spec_definition_id where f.template_id = p_template_id loop
    v_value := p_values->v_field.key;
    if coalesce(v_contract->'roles'->>v_field.key,'primary')='legacy' then continue; end if;
    v_expression:=v_contract->'allowed_when'->v_field.key;
    v_applicable:=case when v_expression is null then true
      else public.spec_template_condition_internal_v1(v_expression,p_values) end;
    for v_rule in select value from jsonb_array_elements(coalesce(v_field.visibility_rules,'[]')) loop
      v_applicable:=v_applicable and public.spec_condition_internal_v1(v_rule,p_values);
    end loop;
    v_expression:=v_contract->'required_when'->v_field.key;
    v_required:=case when v_expression is null then false
      else public.spec_template_condition_internal_v1(v_expression,p_values) end;
    if not public.spec_rule_known_internal_v1(v_value) then
      if v_applicable is true and v_required is true then
        v_issues:=v_issues||jsonb_build_array(jsonb_build_object('code','required_missing','field',v_field.key,
          'message',v_field.label||': falta confirmar este dato.','blocking',false));
      end if;
      continue;
    end if;
    if v_applicable is not true then
      v_issues:=v_issues||jsonb_build_array(jsonb_build_object('code','field_applicability','field',v_field.key,
        'message',v_field.label||case when v_applicable is false then ': no corresponde a los requisitos elegidos.'
          else ': falta confirmar sus requisitos.' end,'blocking',v_applicable is false));
    end if;
    v_message := null;
    if p_reference_id is not null and v_contract->'roles'->>v_field.key='declaration'
      and v_field.key <> 'spec_evidence_source' and not (coalesce(v_reference.fact_values,'{}'::jsonb) ? v_field.id::text) then
      v_message := 'La referencia elegida no documenta esta declaración manual. Usa sus declaraciones o retira la referencia.';
    end if;
    for v_key in select jsonb_array_elements_text(coalesce(v_contract->'prerequisites'->v_field.key,'[]')) loop
      if not public.spec_rule_known_internal_v1(p_values->v_key) then
        v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','prerequisite_missing','field',v_field.key,
          'message','Falta confirmar ' || v_key || '.','blocking',false));
      end if;
    end loop;
    if v_field.data_type = 'boolean' and jsonb_typeof(v_value) <> 'boolean' then
      v_message := 'El campo requiere Sí, No o Sin confirmar.';
    elsif v_field.data_type = 'number' then
      if public.spec_rule_normalize_internal_v1(v_value) !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)$' then
        v_message := 'El campo requiere un número válido.';
      else
        v_number := public.spec_rule_normalize_internal_v1(v_value)::numeric;
        if v_field.validation_rules->>'positive' = 'true' and v_number <= 0 then
          v_message := 'Ingresa un valor mayor que cero.';
        end if;
        if v_field.validation_rules->>'integer' = 'true' and v_number <> trunc(v_number) then
          v_message := 'Ingresa una cantidad entera.';
        end if;
        if v_number < (v_field.validation_rules->>'min')::numeric or
          v_number > (v_field.validation_rules->>'max')::numeric then
          v_message := 'El valor está fuera del rango declarado para este campo.';
        end if;
      end if;
    elsif v_field.data_type='json' and v_field.validation_rules ? 'rows_schema' then
      begin
        perform public.spec_rows_validate_internal_v1(v_field.validation_rules->'rows_schema',v_value);
        if exists(select 1 from jsonb_array_elements(v_value->'rows') r
          cross join jsonb_array_elements(v_field.validation_rules->'rows_schema'->'columns') c
          where c->>'required'='true' and not public.spec_rule_known_internal_v1(r->'values'->(c->>'key'))) then
          v_issues:=v_issues||jsonb_build_array(jsonb_build_object('code','row_incomplete','field',v_field.key,
            'message',v_field.label||': faltan datos dentro de una configuración.','blocking',false));
        end if;
      exception when check_violation then
        v_message:=sqlerrm;
      end;
    elsif v_field.data_type in ('single_select','multi_select') then
      if (v_field.data_type = 'single_select' and jsonb_typeof(v_value) <> 'string') or
         (v_field.data_type = 'multi_select' and jsonb_typeof(v_value) <> 'array') then
        v_message := 'La cantidad de respuestas no corresponde al campo.';
      elsif (case when v_contract->'rules_version'='2'::jsonb then
          not(v_field.allowed_values @> case when v_field.data_type='multi_select' then v_value else jsonb_build_array(v_value) end)
        else not (public.spec_rule_set_internal_v1(v_value) <@ public.spec_rule_set_internal_v1(v_field.allowed_values)) end) then
        v_message := 'La respuesta no pertenece a las opciones del campo.';
      end if;
    end if;
    v_allowed := case when v_contract->'allowed_options' ? v_field.key
      then array(select jsonb_array_elements_text(v_contract->'allowed_options'->v_field.key)) else null end;
    for v_rule in select value from jsonb_array_elements(coalesce(v_field.constraint_rules,'[]')) loop
      if public.spec_condition_internal_v1(v_rule,p_values) is true then
        if jsonb_typeof(v_rule->'allow') <> 'array' then raise exception 'Invalid option rule' using errcode = '22023'; end if;
        if v_contract->'rules_version'='2'::jsonb and exists(select 1 from jsonb_array_elements(v_rule->'allow') x
          where jsonb_typeof(x)<>'string' and not(v_field.data_type='boolean' and jsonb_typeof(x)='boolean')) then
          raise exception 'Opciones de requisito inválidas' using errcode='22023';
        end if;
        v_next := case when v_contract->'rules_version'='2'::jsonb then array(select jsonb_array_elements_text(v_rule->'allow'))
          else public.spec_rule_set_internal_v1(v_rule->'allow') end;
        if v_allowed is null then v_allowed := v_next;
        else v_allowed := array(select unnest(v_allowed) intersect select unnest(v_next)); end if;
      end if;
    end loop;
    if v_allowed is not null and not ((case when v_contract->'rules_version'='2'::jsonb then
      array(select jsonb_array_elements_text(case when jsonb_typeof(v_value)='array' then v_value else jsonb_build_array(v_value) end))
      else public.spec_rule_set_internal_v1(v_value) end) <@ v_allowed) then
      v_message := 'El valor no corresponde a los requisitos elegidos.';
    end if;
    if v_message is not null then
      v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','field_constraint','field',v_field.key,
        'message',v_field.label || ': ' || v_message));
    end if;
  end loop;
  v_coherence:=public.spec_coherence_issues_internal_v1(v_contract,public.spec_coherence_fields_internal_v1(p_template_id),p_values);
  -- The row validator above also owns non-linked rows. Avoid reporting the
  -- same malformed linked field twice with different error categories.
  select coalesce(jsonb_agg(i order by position),'[]') into v_issues
    from jsonb_array_elements(v_issues) with ordinality x(i,position)
    where not(i->>'code'='field_constraint' and exists(select 1 from jsonb_array_elements(v_coherence) c
      where c->>'code'='row_shape' and c->>'field'=i->>'field'));
  -- Applicability already owns an explicitly forbidden populated table
  -- (including a declared zero total); avoid a second cardinality conflict.
  -- Ordinary scalar validation likewise owns invalid total values.
  select coalesce(jsonb_agg(c order by position),'[]') into v_coherence
    from jsonb_array_elements(v_coherence) with ordinality x(c,position)
    where not(c->>'code'='row_cardinality_conflict' and exists(select 1 from jsonb_array_elements(v_issues) i
      where i->>'field'=c->>'field' and i->>'code'='field_applicability' and i->'blocking'='true'::jsonb))
    and not(c->>'code'='row_cardinality_total' and exists(select 1 from jsonb_array_elements(v_issues) i
      where i->>'field'=c->>'field' and i->>'code'='field_constraint' and coalesce(i->'blocking','true'::jsonb)='true'::jsonb));
  v_issues:=v_issues||v_coherence;
  return v_issues;
end $function$
;
do $after$
declare expected record; actual record; fn regprocedure;
begin
 for expected in select * from (values
  ('spec_coherence_fields_internal_v1(uuid)','e3b437887bdcbb2766d46805beb3a719','842a6575f1eedcef45b7749b76e458e9',false,'s'),
  ('spec_coherence_metadata_internal_v1(jsonb,jsonb)','863ba9ce738f2c6d497e1a3786c02eb5','62b9c8349bf9d4fa4f983d3009980171',false,'i'),
  ('spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','48f01ef6f5343dfe3a45285ad227fb60','d57404a97c12b336e64b59202b3d56f4',false,'i'),
  ('spec_coherence_publication_guard_internal_v1()','1d9f691d7e044034255f7500c21feb7c','235850d2afe7e1571431c7f7c4942b7b',true,'v'),
  ('spec_template_rules_validate_internal_v1(uuid)','273b46c7568552a6e2641eec4f69f59c','61cc6156d8ec2f36a7e9a1cc47b95c53',true,'v'),
  ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','25a18d1d600cf2d8da7c30a59e54123f','9ea12d82761d6ffd0584d460cbc998d6',false,'s')
 ) e(signature,old_md5,new_md5,definer,volatility) loop
  fn:=to_regprocedure('public.'||expected.signature);
  select p.*,pg_get_userbyid(p.proowner) owner_name,md5(pg_get_functiondef(p.oid)) body_md5 into actual from pg_proc p where p.oid=fn;
  if actual.body_md5 is distinct from expected.new_md5 or actual.owner_name<>'postgres'
    or actual.prosecdef<>expected.definer or actual.provolatile::text<>expected.volatility
    or actual.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp']::text[]
    or actual.proacl::text is distinct from '{postgres=X/postgres,service_role=X/postgres}' then
    raise exception 'Cardinality after-state mismatch: %',expected.signature;
  end if;
 end loop;
end $after$;
commit;
