-- LOCAL CANDIDATE ONLY. No template activation, fact or product writes.
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
       (jsonb_typeof(block->'version') is distinct from 'number' or block->>'version' not in ('2','3')))
     or jsonb_typeof(block->'links') is distinct from 'array'
     or (block->'version'='1'::jsonb and exists(select 1 from jsonb_object_keys(block) k where k not in ('version','links')))
     or (block->>'version' in ('2','3') and (jsonb_typeof(block->'cardinalities') is distinct from 'array'
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
   -- V3 counts each explicit parent independently. A model's alternatives
   -- never inflate a SKU's scalar total or compensate for another parent.
   for cardinality in select value from jsonb_array_elements(coalesce(block->'cardinalities','[]')) loop
     if jsonb_typeof(cardinality) is distinct from 'object' then
       raise exception 'Cardinalidad inválida' using errcode='23514'; end if;
     if cardinality ? 'group_by' then
       if block->>'version'<>'3' or (select count(*) from jsonb_object_keys(cardinality))<>4
         or exists(select 1 from jsonb_object_keys(cardinality) k where k not in ('id','field','group_by','total_column')) then
         raise exception 'Claves de cardinalidad agrupada inválidas' using errcode='23514'; end if;
     elsif (select count(*) from jsonb_object_keys(cardinality))<>3
       or exists(select 1 from jsonb_object_keys(cardinality) k where k not in ('id','field','total_field')) then
       raise exception 'Claves de cardinalidad inválidas' using errcode='23514'; end if;
     for key in select jsonb_object_keys(cardinality) loop
       if jsonb_typeof(cardinality->key) is distinct from 'string'
         or cardinality->>key !~ '^[a-z][a-z0-9_]*$' or cardinality->>key ~ '[[:space:]]' then
         raise exception 'Identificador de cardinalidad inválido' using errcode='23514'; end if;
     end loop;
     source:=p_fields->(cardinality->>'field');
     if cardinality->>'id'=any(ids) or cardinality->>'field'=any(collections)
       or source->>'data_type' is distinct from 'json' or jsonb_typeof(source->'schema') is distinct from 'object' then
       raise exception 'Extremos de cardinalidad no disponibles o duplicados' using errcode='23514'; end if;
     perform public.spec_rows_schema_validate_internal_v1(source->'schema');
     if cardinality ? 'group_by' then
       select l into link from jsonb_array_elements(links) l where l->>'id'=cardinality->>'group_by';
       if link is null or link->>'field' is distinct from cardinality->>'field' then
         raise exception 'La agrupación necesita un vínculo de su propia tabla' using errcode='23514'; end if;
       target:=p_fields->(link->>'target_field');
       select c into col from jsonb_array_elements(target->'schema'->'columns') c where c->>'key'=cardinality->>'total_column';
       if col is null or col->>'type' is distinct from 'integer' then
         raise exception 'El total agrupado necesita una columna entera en su destino' using errcode='23514'; end if;
       rules:=coalesce(col->'validation','{}')||'{"integer":true}'::jsonb;
     else
       target:=p_fields->(cardinality->>'total_field');
       if target->>'data_type' is distinct from 'number' then
         raise exception 'El total necesita un campo numérico' using errcode='23514'; end if;
       rules:=target->'validation_rules';
     end if;
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
declare result jsonb:='[]'; parsed jsonb:='{}'; invalid text[]:='{}'; link jsonb; r jsonb; parent jsonb; target jsonb; grouped boolean;
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
       jsonb_array_elements(coalesce(p_contract->'row_coherence'->'cardinalities','[]')) c left join jsonb_array_elements(coalesce(p_contract->'row_coherence'->'links','[]')) l on l->>'id'=c->>'group_by' where c->>'field'=key or l->>'target_field'=key)) then continue; end if;
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
   grouped:=exists(select 1 from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'cardinalities','[]')) c where c->>'group_by'=link->>'id');
   for r in select value from jsonb_array_elements(coalesce(parsed->(link->>'field')->'rows','[]')) loop
     v_cell:=r->'values'->(link->>'column');
     if grouped and not public.spec_rule_known_internal_v1(v_cell)
       and not exists(select 1 from jsonb_array_elements(coalesce(target->'rows','[]')) t where t->'id'=v_cell) then
       result:=result||jsonb_build_array(jsonb_build_object('code','row_reference_pending','field',link->>'field',
         'row_id',r->>'id','column',link->>'column','message','Falta identificar la configuración de esta fila.','blocking',false));
       continue;
     end if;
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
   if cardinality ? 'group_by' then
     select l into link from jsonb_array_elements(p_contract->'row_coherence'->'links') l where l->>'id'=cardinality->>'group_by';
     key:=link->>'target_field';
     if key=any(invalid) then continue; end if;
     target:=parsed->key;
     if target is null then
       result:=result||jsonb_build_array(jsonb_build_object('code','row_cardinality_pending','field',key,
         'collection_field',field,'message','Falta documentar la configuración y su total.','blocking',false));
       continue;
     end if;
     for parent in select value from jsonb_array_elements(target->'rows') loop
       total:=public.spec_rule_number_internal_v1(parent->'values'->(cardinality->>'total_column'));
       select count(*) into row_count from jsonb_array_elements(coalesce(parsed->field->'rows','[]')) child
         where child->'values'->(link->>'column')=parent->'id';
       if total=row_count then continue; end if;
       result:=result||jsonb_build_array(jsonb_build_object(
         'code',case when row_count>total then 'row_cardinality_conflict' else 'row_cardinality_pending' end,
         'field',key,'row_id',parent->>'id','column',cardinality->>'total_column','collection_field',field,
         'message',case when total is null then 'Falta confirmar el total de esta configuración.'
           when row_count>total then 'Esta configuración tiene más filas que su total declarado.'
           else 'Faltan filas por documentar en esta configuración.' end,
         'blocking',coalesce(row_count>total,false)));
     end loop;
     continue;
   end if;
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
 select coalesce(jsonb_agg(case when c ? 'group_by' then (c-'id'-'group_by')||jsonb_build_object('group',l-'id'-'label_columns') else c-'id' end order by c->>'field'),'[]') into old_cardinalities
   from jsonb_array_elements(coalesce(previous->'row_coherence'->'cardinalities','[]')) c
   left join jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')) l on l->>'id'=c->>'group_by';
 select coalesce(jsonb_agg(case when c ? 'group_by' then (c-'id'-'group_by')||jsonb_build_object('group',l-'id'-'label_columns') else c-'id' end order by c->>'field'),'[]') into new_cardinalities
   from jsonb_array_elements(coalesce(new.form_contract->'row_coherence'->'cardinalities','[]')) c
   left join jsonb_array_elements(coalesce(new.form_contract->'row_coherence'->'links','[]')) l on l->>'id'=c->>'group_by';
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
  v_reference public.product_spec_references%rowtype; v_entry record; v_pair text[]; v_coherence jsonb; v_inapplicable text[]:='{}';
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
    if v_applicable is false then v_inapplicable:=array_append(v_inapplicable,v_field.key); end if;
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
    where not(c->>'code'='row_cardinality_pending' and (c->>'field'=any(v_inapplicable) or coalesce(c->>'collection_field',c->>'field')=any(v_inapplicable)))
    and not(c->>'code'='row_cardinality_conflict' and exists(select 1 from jsonb_array_elements(v_issues) i
      where i->>'field' in (c->>'field',c->>'collection_field') and i->>'code'='field_applicability' and i->'blocking'='true'::jsonb))
    and not(c->>'code'='row_cardinality_total' and exists(select 1 from jsonb_array_elements(v_issues) i
      where i->>'field'=c->>'field' and i->>'code'='field_constraint' and coalesce(i->'blocking','true'::jsonb)='true'::jsonb));
  v_issues:=v_issues||v_coherence;
  return v_issues;
end $function$
;
