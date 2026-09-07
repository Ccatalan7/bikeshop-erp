-- Template-scoped row references and exact scalar bounds. No catalogue/fact writes.
begin;

do $preimage$ declare x record; actual text; begin
 for x in select * from (values
 ('spec_template_rules_validate_internal_v1(uuid)','06cbe78b729c4b3a683c7f6d0c2379f9','fc4875e265b52a847b6a63f406487f96'),
 ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','0a9d8a40eaad998ffb26d36170a4c93e','25a18d1d600cf2d8da7c30a59e54123f'),
 ('get_public_product_technical_specs(uuid,uuid)','39a483344a232591c125a6704a542bc4','89e21f13bb41bdac92b17e62b059df06'),
 ('get_product_spec_typed_configurations_v1(uuid[])','cdfe087a7aefbfcd4f9d7c1573f1041d','0e71196e4ea36bae1b69f4e016947ff8'),
 ('record_product_spec_reading_v1(uuid,text,jsonb,text,text)','49076ebef1568025b62ed51e48ae0442','39eaa8aca4660283e431bd064540bbc3')) p(signature,before_hash,after_hash) loop
 actual:=md5(pg_get_functiondef(to_regprocedure('public.'||x.signature)));
 if actual is distinct from x.before_hash and actual is distinct from x.after_hash then raise exception 'Coherence preimage drift: %',x.signature; end if;
 end loop; end $preimage$;

-- Metadata is template-scoped. A reusable rows_schema never embeds another field.
create or replace function public.spec_coherence_fields_internal_v1(p_template_id uuid)
returns jsonb language sql stable set search_path=pg_catalog,public,pg_temp as $fields$
 select coalesce(jsonb_object_agg(d.key,jsonb_build_object('data_type',d.data_type,'unit',d.unit,
   'schema',d.validation_rules->'rows_schema')),'{}')
 from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
 join public.spec_templates t on t.id=f.template_id
 where f.template_id=p_template_id and coalesce(t.form_contract->'roles'->>d.key,'primary')<>'legacy'
$fields$;

create or replace function public.spec_coherence_metadata_internal_v1(p_contract jsonb,p_fields jsonb)
returns void language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $metadata$
#variable_conflict use_column
declare block jsonb:=p_contract->'row_coherence'; links jsonb; link jsonb; other_link jsonb; col jsonb;
 source jsonb; target jsonb; pair jsonb; ids text[]:='{}'; cells text[]:='{}'; seen text[]:='{}'; key text;
begin
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
end $metadata$;

create or replace function public.spec_coherence_pairs_internal_v1(p_contract jsonb,p_fields jsonb)
returns jsonb language sql immutable set search_path=pg_catalog,public,pg_temp as $pairs$
 -- A single evaluator owns legacy and declared pairs; existing metadata is not rewritten.
 select coalesce(jsonb_agg(pair order by position),'[]') from (
   select pair,min(position) position from (
     select pair,position from jsonb_array_elements(coalesce(p_contract->'scalar_ordered_pairs','[]')) with ordinality x(pair,position)
     union all select pair,100000+position from jsonb_array_elements(
       '[["smallest_cog_teeth","largest_cog_teeth"],["tube_width_min_mm","tube_width_max_mm"],["tube_width_min_in","tube_width_max_in"],["bearing_inner_diameter_mm","bearing_outer_diameter_mm"]]'::jsonb)
       with ordinality x(pair,position)
     where p_fields->(pair->>0)->>'data_type'='number' and p_fields->(pair->>1)->>'data_type'='number'
       and (p_fields->(pair->>0)->'unit') is not distinct from (p_fields->(pair->>1)->'unit')
   ) candidates group by pair
 ) unique_pairs
$pairs$;

create or replace function public.spec_coherence_issues_internal_v1(p_contract jsonb,p_fields jsonb,p_values jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $issues$
#variable_conflict use_column
declare result jsonb:='[]'; parsed jsonb:='{}'; invalid text[]:='{}'; link jsonb; r jsonb; target jsonb;
 key text; pair jsonb; v_cell jsonb; field text;
begin
 for key in select distinct k from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'links','[]')) l
   cross join lateral (values(l->>'field'),(l->>'target_field')) keys(k) order by k loop
   if not public.spec_rule_known_internal_v1(p_values->key) then continue; end if;
   begin
     v_cell:=public.spec_rows_validate_internal_v1(p_fields->key->'schema',p_values->key);
     parsed:=jsonb_set(parsed,array[key],v_cell);
   exception when check_violation then
     invalid:=array_append(invalid,key);
     result:=result||jsonb_build_array(jsonb_build_object('code','row_shape','field',key,
       'message','La configuración tiene un formato inválido. Sus datos se conservan.','blocking',true));
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
end $issues$;

-- Labels are derived for presentation only; typed observations retain row IDs.
create or replace function public.spec_coherence_labels_internal_v1(p_field text,p_contract jsonb,p_values jsonb)
returns jsonb language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $labels$
#variable_conflict use_column
declare result jsonb:='{}'; link jsonb; target jsonb; labels jsonb; r record; label text;
begin
 for link in select value from jsonb_array_elements(coalesce(p_contract->'row_coherence'->'links','[]')) l where l->>'field'=p_field loop
   labels:='{}'; target:=p_values->(link->>'target_field');
   if jsonb_typeof(target->'rows')='array' then
     for r in select v,position from jsonb_array_elements(target->'rows') with ordinality x(v,position) loop
       select string_agg(case jsonb_typeof(r.v->'values'->k) when 'boolean' then
         case r.v->'values'->k when 'true'::jsonb then 'Sí' else 'No' end else r.v->'values'->>k end,' · ' order by n)
         into label from jsonb_array_elements_text(link->'label_columns') with ordinality x(k,n);
       labels:=jsonb_set(labels,array[r.v->>'id'],to_jsonb(coalesce(nullif(label,''),'Configuración '||r.position)));
     end loop;
     select coalesce(jsonb_object_agg(id,case when total>1 then to_jsonb(label||' · configuración '||position) else to_jsonb(label) end),'{}') into labels
       from (select v->>'id' id,position,labels->>(v->>'id') label,
         count(*) over(partition by labels->>(v->>'id')) total
         from jsonb_array_elements(target->'rows') with ordinality x(v,position)) l;
   end if;
   result:=jsonb_set(result,array[link->>'column'],labels);
 end loop;
 return result;
end $labels$;

create or replace function public.spec_coherence_display_rows_internal_v1(p_value jsonb,p_labels jsonb)
returns jsonb language sql immutable set search_path=pg_catalog,public,pg_temp as $display$
 select jsonb_set(p_value,'{rows}',coalesce(jsonb_agg(jsonb_set(r,'{values}',
   (select jsonb_object_agg(k,case when p_labels ? k then coalesce(p_labels->k->(v#>>'{}'),'"Vínculo sin resolver"'::jsonb) else v end)
    from jsonb_each(r->'values') x(k,v))) order by n),'[]'))
 from jsonb_array_elements(p_value->'rows') with ordinality x(r,n)
$display$;

create or replace function public.spec_coherence_publication_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $guard$
#variable_conflict use_column
declare endpoints text[]; previous jsonb; old_links jsonb; new_links jsonb;
begin
 perform public.spec_coherence_metadata_internal_v1(new.form_contract,public.spec_coherence_fields_internal_v1(new.id));
 previous:=case when tg_op='UPDATE' then old.form_contract else '{}'::jsonb end;
 select coalesce(jsonb_agg(l-'label_columns'-'id' order by l->>'field',l->>'column',l->>'target_field'),'[]') into old_links
   from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')) l;
 select coalesce(jsonb_agg(l-'label_columns'-'id' order by l->>'field',l->>'column',l->>'target_field'),'[]') into new_links
   from jsonb_array_elements(coalesce(new.form_contract->'row_coherence'->'links','[]')) l;
 if old_links=new_links and previous->'scalar_ordered_pairs' is not distinct from new.form_contract->'scalar_ordered_pairs' then return new; end if;
 -- This is an AFTER trigger: malformed metadata is rejected by the shape guard,
 -- not interpreted here as an empty relation. No in-place activation over facts.
 select array_agg(distinct key) into endpoints from (
   select l->>'field' key from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')||coalesce(new.form_contract->'row_coherence'->'links','[]')) l
   union select l->>'target_field' from jsonb_array_elements(coalesce(previous->'row_coherence'->'links','[]')||coalesce(new.form_contract->'row_coherence'->'links','[]')) l
   union select jsonb_array_elements_text(pair) from jsonb_array_elements(coalesce(previous->'scalar_ordered_pairs','[]')||coalesce(new.form_contract->'scalar_ordered_pairs','[]')) pair
 ) keys;
 if exists(select 1 from public.spec_template_fields tf join public.spec_definitions d on d.id=tf.spec_definition_id
   where tf.template_id=new.id and d.key=any(endpoints) and (
     exists(select 1 from public.spec_facts f where f.spec_definition_id=d.id)
     or exists(select 1 from public.product_spec_references r where r.fact_values ? d.id::text))) then
   raise exception 'La coherencia de datos poblados requiere una migración revisada con diagnóstico previo' using errcode='23514';
 end if;
 return new;
end $guard$;

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
 if contract ? 'row_coherence' or contract ? 'scalar_ordered_pairs' then
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
end $function$;

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
          where c->>'required'='true' and not(r->'values' ? (c->>'key'))) then
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
  v_issues:=v_issues||v_coherence;
  return v_issues;
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
      d.unit,d.data_type,d.validation_rules,p.form_contract,p.vals,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  )
  select f.section_key,dense_rank() over(order by f.section_order,f.section_key)::integer,
    f.sort_order,f.key,f.label,case
      when f.data_type='json' and f.validation_rules ? 'rows_schema' then public.spec_rows_display_internal_v1(f.validation_rules->'rows_schema',public.spec_coherence_display_rows_internal_v1(f.val,public.spec_coherence_labels_internal_v1(f.key,f.form_contract,f.vals)))
      when jsonb_typeof(f.val)='array' then (select string_agg(e,', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      else f.val#>>'{}' end,f.unit,f.data_type
  from fields f order by f.section_order,f.sort_order,f.label
$function$;

CREATE OR REPLACE FUNCTION public.get_product_spec_typed_configurations_v1(p_product_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_tenant uuid:=public.user_tenant_id(); v_result jsonb;
begin
 if v_tenant is null or auth.uid() is null then raise exception 'No autenticado' using errcode='42501'; end if;
 if p_product_ids is null or cardinality(p_product_ids)>200 then
   raise exception 'Lee configuraciones en bloques de hasta 200 productos' using errcode='22023';
 end if;
 with scoped as materialized (
   select p.id,p.tenant_id,p.spec_revision,b.template_id,b.binding_source,t.contract_version,t.form_contract
   from public.products p join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
   left join public.spec_templates t on t.id=b.template_id
   where p.id=any(p_product_ids) and p.tenant_id=v_tenant
 ), payloads as materialized (
   select p.*,public.spec_template_product_payload_internal_v1(p.id,p.template_id,false) vals from scoped p
 ), configurations as (
   select p.*,coalesce((select jsonb_object_agg(d.key,jsonb_build_object(
     'definition_id',d.id,'value_type',case d.data_type
       when 'number' then 'decimal' when 'boolean' then 'boolean'
       when 'multi_select' then 'token_set' when 'json' then 'rows' else 'token' end,
     'value',case d.data_type when 'number' then to_jsonb((e.value->>'number')::numeric::text)
       else public.spec_payload_display_internal_v1(jsonb_build_object(e.key,e.value))->d.key end)
     ||case when d.data_type='json' then jsonb_build_object('row_labels',public.spec_coherence_labels_internal_v1(d.key,p.form_contract,public.spec_payload_display_exact_internal_v1(p.vals))) else '{}'::jsonb end)
     from jsonb_each(p.vals) e join public.spec_definitions d on d.id::text=e.key
     where d.data_type<>'json' or d.validation_rules ? 'rows_schema'),'{}'::jsonb) fields
   from payloads p
 ) select coalesce(jsonb_object_agg(id,jsonb_build_object('schema_version',2,
     'product_id',id,'template_id',template_id,'binding_source',binding_source,
     'revision',spec_revision,'contract_version',contract_version,'fields',fields)),'{}'::jsonb)
   into v_result from configurations;
 return v_result;
end $function$;

CREATE OR REPLACE FUNCTION public.record_product_spec_reading_v1(p_product_id uuid, p_field_key text, p_value jsonb, p_quote text, p_model text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_tenant_id uuid := public.user_tenant_id();
  v_texto text;
  v_digest text;
  v_vocabulario text;
  v_def record;
  v_rechazo text;
  v_details text;
  v_existente record;
  v_fact_id uuid;
  v_valor_id uuid;
begin
  if v_tenant_id is null or auth.uid() is null then
    raise exception 'Sin inquilino' using errcode = '42501';
  end if;
  if length(coalesce(p_model, '')) > 80 then
    return jsonb_build_object('verdict', 'rejected',
      'reason', 'el nombre del modelo es demasiado largo');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant_id::text || ':spec_fact:' || p_product_id::text, 0));

  select concat_ws(' ', p.name, p.description) into v_texto
  from public.products p
  where p.id = p_product_id and p.tenant_id = v_tenant_id for update;
  if not found then
    return jsonb_build_object('verdict', 'rejected',
      'reason', 'el producto no es de este taller');
  end if;

  -- Resolve the exact definition inside the current template. A tenant key
  -- outside this template cannot shadow a global definition used by the form.
  select d.id, d.data_type into v_def from public.spec_definitions d
  where d.id=public.spec_product_field_definition_internal_v1(v_tenant_id,p_product_id,p_field_key)
    and d.is_filterable is true;
  if not found then
    return jsonb_build_object('verdict','rejected','reason','el campo no pertenece a la ficha técnica activa o no es filtrable');
  end if;

  v_digest := encode(sha256(convert_to(v_texto, 'UTF8')), 'hex');

  if position(
       public.assistant_normalize_query_internal_v1(coalesce(p_quote, ''))
       in public.assistant_normalize_query_internal_v1(v_texto)) = 0
     or coalesce(btrim(p_quote), '') = '' then
    return jsonb_build_object('verdict', 'rejected',
      'reason', 'la cita no está en el texto del producto');
  end if;

  v_rechazo := public.spec_reading_rejection_internal_v1(
    v_def.id, p_value, p_quote);
  if v_rechazo is not null then
    return jsonb_build_object('verdict', 'rejected', 'reason', v_rechazo);
  end if;

  -- **El candado es por PRODUCTO, no por campo.** Por campo alcanzaba para
  -- dos lectores, pero no para el guardado manual: ese empieza BORRANDO los
  -- campos que la plantilla incluye y el payload no trae --vaciar un criterio
  -- es parte de guardar-- y ese borrado ocurre antes de saber que campos va a
  -- tocar. Con candados por campo, un lector podia reinsertar justo el campo
  -- que la persona acababa de vaciar. Y dos guardados con los campos en
  -- distinto orden podian trabarse entre si. Una sola llave por producto no
  -- tiene ninguno de los dos problemas, y la ficha de un producto se escribe
  -- lo bastante poco como para que la granularidad no importe.

  select f.id, f.source into v_existente
  from public.spec_facts f
  where f.tenant_id = v_tenant_id
    and f.subject_type = 'product'
    and f.subject_id = p_product_id
    and f.spec_definition_id = v_def.id
    and f.subject_scope is null;
  if found and v_existente.source <> 'name_reading' then
    return jsonb_build_object('verdict', 'kept_existing',
      'reason', 'el campo ya tiene un dato de ' || v_existente.source);
  end if;

  if v_def.data_type = 'single_select' then
    select v.id into v_valor_id
    from public.spec_definition_values v
    where v.spec_definition_id = v_def.id and v.is_active is true
      and public.assistant_normalize_query_internal_v1(v.label)
        = public.assistant_normalize_query_internal_v1(p_value #>> '{}')
    limit 1;
    if v_valor_id is null then
      return jsonb_build_object('verdict', 'rejected',
        'reason', 'el valor no está en la lista del campo');
    end if;
  end if;

  -- A rejected cross-field observation rolls back its own attempted write.
  begin
  if v_existente.id is not null then
    v_fact_id := v_existente.id;
    update public.spec_facts set
      value_number = case when v_def.data_type = 'number'
        then (p_value #>> '{}')::numeric else null end,
      value_boolean = case when v_def.data_type = 'boolean'
        then (p_value #>> '{}')::boolean else null end,
      value_text = null,
      updated_at = now()
    where id = v_fact_id;
  else
    insert into public.spec_facts (
      tenant_id, subject_type, subject_id, spec_definition_id,
      value_number, value_boolean, value_text, source, confirmed)
    values (
      v_tenant_id, 'product', p_product_id, v_def.id,
      case when v_def.data_type = 'number'
        then (p_value #>> '{}')::numeric end,
      case when v_def.data_type = 'boolean'
        then (p_value #>> '{}')::boolean end,
      null, 'name_reading', false)
    returning id into v_fact_id;
  end if;

  if v_valor_id is not null then
    delete from public.spec_fact_values where fact_id = v_fact_id;
    insert into public.spec_fact_values (fact_id, value_id, position)
    values (v_fact_id, v_valor_id, 0);
  end if;

  v_vocabulario := public.spec_definition_vocabulary_digest_internal_v1(
    v_def.id);

  insert into public.spec_fact_readings (
    fact_id, tenant_id, definition_id, source_text, source_digest,
    vocabulary_digest, quote, model)
  values (v_fact_id, v_tenant_id, v_def.id, v_texto, v_digest,
          v_vocabulario, btrim(p_quote),
          coalesce(nullif(btrim(p_model), ''), 'desconocido'))
  on conflict (fact_id) do update set
    definition_id = excluded.definition_id,
    source_text = excluded.source_text,
    source_digest = excluded.source_digest,
    vocabulary_digest = excluded.vocabulary_digest,
    quote = excluded.quote,
    model = excluded.model,
    read_at = now();

  perform public.spec_validate_product_internal_v1(p_product_id);

  return jsonb_build_object('verdict', 'recorded', 'factId', v_fact_id,
    'digest', v_digest);
  exception when check_violation then
    get stacked diagnostics v_rechazo=MESSAGE_TEXT,v_details=PG_EXCEPTION_DETAIL;
    return jsonb_build_object('verdict','rejected','reason',v_rechazo,'details',v_details);
  end;
end;
$function$;

drop trigger if exists spec_definition_template_rules_guard on public.spec_definitions;
create constraint trigger spec_definition_template_rules_guard after update on public.spec_definitions
 deferrable initially deferred for each row
 when (old.key is distinct from new.key or old.data_type is distinct from new.data_type or old.allowed_values is distinct from new.allowed_values
   or old.validation_rules is distinct from new.validation_rules or old.unit is distinct from new.unit)
 execute function public.spec_template_rules_guard_internal_v1();
drop trigger if exists spec_coherence_publication_guard on public.spec_templates;
create constraint trigger spec_coherence_publication_guard after insert or update on public.spec_templates
 deferrable initially deferred for each row execute function public.spec_coherence_publication_guard_internal_v1();

alter function public.spec_coherence_fields_internal_v1(uuid) owner to postgres;
revoke all on function public.spec_coherence_fields_internal_v1(uuid) from public,anon,authenticated;

alter function public.spec_coherence_metadata_internal_v1(jsonb,jsonb) owner to postgres;
revoke all on function public.spec_coherence_metadata_internal_v1(jsonb,jsonb) from public,anon,authenticated;

alter function public.spec_coherence_pairs_internal_v1(jsonb,jsonb) owner to postgres;
revoke all on function public.spec_coherence_pairs_internal_v1(jsonb,jsonb) from public,anon,authenticated;

alter function public.spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb) owner to postgres;
revoke all on function public.spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb) from public,anon,authenticated;

alter function public.spec_coherence_labels_internal_v1(text,jsonb,jsonb) owner to postgres;
revoke all on function public.spec_coherence_labels_internal_v1(text,jsonb,jsonb) from public,anon,authenticated;

alter function public.spec_coherence_display_rows_internal_v1(jsonb,jsonb) owner to postgres;
revoke all on function public.spec_coherence_display_rows_internal_v1(jsonb,jsonb) from public,anon,authenticated;

alter function public.spec_coherence_publication_guard_internal_v1() owner to postgres;
revoke all on function public.spec_coherence_publication_guard_internal_v1() from public,anon,authenticated;

do $postimage$ declare x record; actual text; begin
 for x in select * from (values
 ('get_product_spec_typed_configurations_v1(uuid[])','0e71196e4ea36bae1b69f4e016947ff8'),
 ('get_public_product_technical_specs(uuid,uuid)','89e21f13bb41bdac92b17e62b059df06'),
 ('record_product_spec_reading_v1(uuid,text,jsonb,text,text)','39eaa8aca4660283e431bd064540bbc3'),
 ('spec_coherence_display_rows_internal_v1(jsonb,jsonb)','7eeeea10db32822bae62c076e06363dd'),
 ('spec_coherence_fields_internal_v1(uuid)','e3b437887bdcbb2766d46805beb3a719'),
 ('spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)','06dc1b93436b1ac5693142b2eace82ec'),
 ('spec_coherence_labels_internal_v1(text,jsonb,jsonb)','7699347e366f71e9a3bce36c06420fa5'),
 ('spec_coherence_metadata_internal_v1(jsonb,jsonb)','94ea287f2f4b1c0782253c722eb3e0e7'),
 ('spec_coherence_pairs_internal_v1(jsonb,jsonb)','f8f1df3554fcb19199e1c62e55164a65'),
 ('spec_coherence_publication_guard_internal_v1()','bcc98eaa28aeb87f265e569ba587c007'),
 ('spec_template_rules_validate_internal_v1(uuid)','fc4875e265b52a847b6a63f406487f96'),
 ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','25a18d1d600cf2d8da7c30a59e54123f')) p(signature,hash) loop
 actual:=md5(pg_get_functiondef(to_regprocedure('public.'||x.signature)));
 if actual is distinct from x.hash then raise exception 'Coherence postimage drift: %',x.signature; end if;
 end loop; end $postimage$;

commit;
