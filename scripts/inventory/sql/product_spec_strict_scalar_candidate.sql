-- Candidate only: no metadata, grants or facts are changed.
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
   if public.spec_rule_number_internal_v1(p_values->(pair->>0)) > public.spec_rule_number_internal_v1(p_values->(pair->>1))
     or (pair->>2='lt' and public.spec_rule_number_internal_v1(p_values->(pair->>0)) = public.spec_rule_number_internal_v1(p_values->(pair->>1))) then
     for field in select jsonb_array_elements_text(jsonb_build_array(pair->0,pair->1)) loop
       result:=result||jsonb_build_array(jsonb_build_object('code','range_order','field',field,
         'message',case when pair->>2='lt' then 'La primera medida debe ser menor que la segunda.'
           else 'El límite inferior no puede superar el superior.' end,'blocking',true));
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
     if not (jsonb_array_length(pair)=2 or (jsonb_array_length(pair)=3 and pair->2='"lt"'::jsonb))
       or pair->0=pair->1 or jsonb_build_array(pair->0,pair->1)::text=any(seen)
       or exists(select 1 from jsonb_array_elements(jsonb_build_array(pair->0,pair->1)) k where jsonb_typeof(k)<>'string' or p_fields->(k#>>'{}')->>'data_type' is distinct from 'number')
       or (p_fields->(pair->>0)->'unit') is distinct from (p_fields->(pair->>1)->'unit') then
       raise exception 'Los límites requieren dos campos numéricos distintos con la misma unidad' using errcode='23514';
     end if;
     seen:=array_append(seen,jsonb_build_array(pair->0,pair->1)::text);
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
CREATE OR REPLACE FUNCTION public.spec_coherence_pairs_internal_v1(p_contract jsonb, p_fields jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
 -- A single evaluator owns legacy and declared pairs; existing metadata is not rewritten.
 select coalesce(jsonb_agg(pair order by position),'[]') from (
   select pair,min(position) position from (
     select pair,position from jsonb_array_elements(coalesce(p_contract->'scalar_ordered_pairs','[]')) with ordinality x(pair,position)
     union all select pair,100000+position from jsonb_array_elements(
       '[["smallest_cog_teeth","largest_cog_teeth"],["tube_width_min_mm","tube_width_max_mm"],["tube_width_min_in","tube_width_max_in"],["bearing_inner_diameter_mm","bearing_outer_diameter_mm"]]'::jsonb)
       with ordinality x(pair,position)
     where p_fields->(pair->>0)->>'data_type'='number' and p_fields->(pair->>1)->>'data_type'='number'
       and (p_fields->(pair->>0)->'unit') is not distinct from (p_fields->(pair->>1)->'unit')
       and not exists(select 1 from jsonb_array_elements(coalesce(p_contract->'scalar_ordered_pairs','[]')) declared
         where declared->0=pair->0 and declared->1=pair->1)
   ) candidates group by pair
 ) unique_pairs
$function$

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
   union select jsonb_array_elements_text(jsonb_build_array(pair->0,pair->1)) from jsonb_array_elements(coalesce(previous->'scalar_ordered_pairs','[]')||coalesce(new.form_contract->'scalar_ordered_pairs','[]')) pair
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
