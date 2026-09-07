-- Declarative field applicability, required answers and template-local options.
-- This controls a ficha, not an assertion that two bicycle parts fit.
begin;
do $preimage$
declare x record; actual text;
begin
 for x in select * from (values
 ('spec_template_condition_internal_v1(jsonb,jsonb)',null,'b069c020eac9ddc2c088dbbab3bdd091'),
 ('spec_template_rules_guard_internal_v1()',null,'93b6939f2eac40107abfdabb2d27895c'),
 ('spec_template_rules_validate_internal_v1(uuid)',null,'06cbe78b729c4b3a683c7f6d0c2379f9'),
 ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','76a3e46dd75f5a3c444bbf3755ab0bc6','0a9d8a40eaad998ffb26d36170a4c93e')
 ) e(signature,before_hash,after_hash) loop
   actual:=md5(pg_get_functiondef(to_regprocedure('public.'||x.signature)));
   if actual is distinct from x.before_hash and actual is distinct from x.after_hash then
     raise exception 'Field condition function preimage drift: %',x.signature using errcode='55000';
   end if;
 end loop;
 for x in select * from (values
 ('product_spec_definition_revision','spec_definitions','a0bd95a165f3d6898086f6234fca5ec2','74dc221b889aae1ba07e69ff0870ef42'),
 ('spec_definition_template_rules_guard','spec_definitions',null,'7ea2735625ae81d1aceda141d16fa151'),
 ('spec_template_field_rules_guard','spec_template_fields',null,'e7cef22d324ebdc92894454d91c0c0de'),
 ('spec_template_rules_guard','spec_templates',null,'277df089eb89e702af996630bda57279')
 ) e(name,relation,before_hash,after_hash) loop
   select md5(pg_get_triggerdef(oid)) into actual from pg_trigger where tgname=x.name and tgrelid=('public.'||x.relation)::regclass;
   if actual is distinct from x.before_hash and actual is distinct from x.after_hash then
     raise exception 'Field condition trigger preimage drift: %',x.name using errcode='55000';
   end if;
 end loop;
end $preimage$;

create or replace function public.spec_template_condition_internal_v1(p_expression jsonb,p_values jsonb)
returns boolean language plpgsql immutable set search_path=pg_catalog,public,pg_temp as $condition$
#variable_conflict use_column
declare r jsonb; c jsonb; choice jsonb; choices jsonb; cell boolean;
 row_state boolean; projected jsonb; any_yes boolean:=false; any_unknown boolean:=false;
begin
 if jsonb_typeof(p_expression) is distinct from 'object' then
   raise exception 'Condición de campo inválida' using errcode='22023';
 end if;
 if coalesce(p_expression->>'kind','') not in ('always','never','when')
   or exists(select 1 from jsonb_object_keys(p_expression) k where k not in ('kind','rows')) then
   raise exception 'Condición de campo inválida' using errcode='22023';
 end if;
 if p_expression->>'kind'<>'when' then
   if p_expression ? 'rows' then raise exception 'Una constante no admite filas' using errcode='22023'; end if;
   return p_expression->>'kind'='always';
 end if;
 if jsonb_typeof(p_expression->'rows') is distinct from 'array' then raise exception 'Faltan alternativas' using errcode='22023'; end if;
 if jsonb_array_length(p_expression->'rows')=0 then raise exception 'Faltan alternativas' using errcode='22023'; end if;
 for r in select value from jsonb_array_elements(p_expression->'rows') loop
   if jsonb_typeof(r)<>'array' then raise exception 'Alternativa inválida' using errcode='22023'; end if;
   if jsonb_array_length(r)=0 then raise exception 'Alternativa vacía' using errcode='22023'; end if;
   row_state:=true;
   for c in select value from jsonb_array_elements(r) loop
     if jsonb_typeof(c)<>'object' then raise exception 'Requisito inválido' using errcode='22023'; end if;
     if jsonb_typeof(c->'field') is distinct from 'string' or c->>'field'=''
       or coalesce(c->>'value_type','') not in ('token','decimal','boolean')
       or coalesce(c->>'operator','') not in ('eq','in','lt','lte','gt','gte')
       or (c->>'operator' in ('lt','lte','gt','gte') and c->>'value_type'<>'decimal')
       or exists(select 1 from jsonb_object_keys(c) k where k not in ('field','value_type','operator','value')) then
       raise exception 'Requisito inválido' using errcode='22023';
     end if;
     choices:=case when c->>'operator'='in' then c->'value' else jsonb_build_array(c->'value') end;
     if jsonb_typeof(choices) is distinct from 'array' then raise exception 'Opciones de requisito inválidas' using errcode='22023'; end if;
     if jsonb_array_length(choices)=0 then raise exception 'Opciones de requisito vacías' using errcode='22023'; end if;
     for choice in select value from jsonb_array_elements(choices) loop
       if (c->>'value_type'='boolean' and jsonb_typeof(choice)<>'boolean')
         or (c->>'value_type'<>'boolean' and (jsonb_typeof(choice)<>'string' or choice#>>'{}'=''))
         or (c->>'value_type'='decimal' and ((choice#>>'{}') !~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' or public.spec_rule_number_internal_v1(choice) is null)) then
         raise exception 'Valor de requisito inválido' using errcode='22023';
       end if;
     end loop;
     -- The ordinary editor also carries JSON numbers. Only a declared decimal
     -- operand receives this exact PostgreSQL numeric-to-text projection.
     projected:=p_values;
     if c->>'value_type'='decimal' and jsonb_typeof(p_values->(c->>'field'))='number' then
       projected:=jsonb_set(p_values,array[c->>'field'],to_jsonb(p_values->>(c->>'field')));
     end if;
     cell:=public.spec_relation_condition_internal_v1(c,projected);
     row_state:=row_state and cell;
   end loop;
   any_yes:=any_yes or row_state is true;
   any_unknown:=any_unknown or row_state is null;
 end loop;
 return case when any_yes then true when any_unknown then null else false end;
end $condition$;

create or replace function public.spec_template_rules_validate_internal_v1(p_template_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $metadata$
#variable_conflict use_column
declare contract jsonb; keys text[]; e record; c jsonb; dep text; bucket text; dtype text; choices jsonb;
 legacy_edges jsonb;
begin
 -- Serialize metadata changes against each other; otherwise a definition edit
 -- and a condition edit could each validate against the other's old value.
 select form_contract into contract from public.spec_templates where id=p_template_id for update;
 if contract is null or not(contract ? 'rules_version') then return; end if;
 if contract->'rules_version'='1'::jsonb then return; end if;
 if contract->'rules_version' is distinct from '2'::jsonb then
   raise exception 'Versión de condiciones de ficha inválida' using errcode='23514';
 end if;
 perform d.id from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
   where f.template_id=p_template_id order by d.id for share of d;
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
 ), paths(start,tip,visited,cycle) as (
   select parent,child,array[parent,child],parent=child from edges
   union all select p.start,e.child,p.visited||e.child,e.child=any(p.visited)
     from paths p join edges e on e.parent=p.tip where not p.cycle
 ) select 1 from paths where cycle) then
   raise exception 'Los prerrequisitos de la ficha forman un ciclo' using errcode='23514';
 end if;
end $metadata$;

create or replace function public.spec_template_rules_guard_internal_v1()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $guard$
declare template_id uuid;
begin
 if tg_table_name='spec_templates' then
   if tg_op<>'DELETE' then perform public.spec_template_rules_validate_internal_v1(new.id); end if;
 elsif tg_table_name='spec_definitions' then
   for template_id in select f.template_id from public.spec_template_fields f where f.spec_definition_id=new.id loop
     perform public.spec_template_rules_validate_internal_v1(template_id);
   end loop;
 else
   if tg_op<>'DELETE' then perform public.spec_template_rules_validate_internal_v1(new.template_id); end if;
   if tg_op<>'INSERT' then perform public.spec_template_rules_validate_internal_v1(old.template_id); end if;
 end if;
 return null;
end $guard$;
drop trigger if exists spec_template_rules_guard on public.spec_templates;
create constraint trigger spec_template_rules_guard after insert or update on public.spec_templates
 deferrable initially deferred for each row execute function public.spec_template_rules_guard_internal_v1();
drop trigger if exists spec_template_field_rules_guard on public.spec_template_fields;
create constraint trigger spec_template_field_rules_guard after insert or update or delete on public.spec_template_fields
 deferrable initially deferred for each row execute function public.spec_template_rules_guard_internal_v1();

drop trigger if exists spec_definition_template_rules_guard on public.spec_definitions;
create constraint trigger spec_definition_template_rules_guard after update on public.spec_definitions
 deferrable initially deferred for each row
 when (old.key is distinct from new.key or old.data_type is distinct from new.data_type or old.allowed_values is distinct from new.allowed_values)
 execute function public.spec_template_rules_guard_internal_v1();

-- A renamed key or unit also invalidates open editors, even if no predicate
-- mentions that definition. Product observations themselves are not rewritten.
drop trigger if exists product_spec_definition_revision on public.spec_definitions;
create trigger product_spec_definition_revision after update of validation_rules,data_type,allowed_values,label,key,unit
 on public.spec_definitions for each row execute function public.spec_contract_revision_internal_v1();

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
  v_reference public.product_spec_references%rowtype; v_entry record; v_pair text[];
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
  foreach v_pair slice 1 in array array[
    ['smallest_cog_teeth','largest_cog_teeth'],['tube_width_min_mm','tube_width_max_mm'],
    ['tube_width_min_in','tube_width_max_in'],['bearing_inner_diameter_mm','bearing_outer_diameter_mm']]
  loop
    if public.spec_rule_number_internal_v1(p_values->v_pair[1]) > public.spec_rule_number_internal_v1(p_values->v_pair[2]) then
      v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','range_order','field',v_pair[2],
        'message','El límite inferior no puede superar el superior.'));
    end if;
  end loop;
  return v_issues;
end $function$;

revoke all on function public.spec_template_condition_internal_v1(jsonb,jsonb),
 public.spec_template_rules_validate_internal_v1(uuid),public.spec_template_rules_guard_internal_v1()
 from public,anon,authenticated;
do $postimage$
declare x record; actual text;
begin
 for x in select * from (values
 ('spec_template_condition_internal_v1(jsonb,jsonb)',null,'b069c020eac9ddc2c088dbbab3bdd091'),
 ('spec_template_rules_guard_internal_v1()',null,'93b6939f2eac40107abfdabb2d27895c'),
 ('spec_template_rules_validate_internal_v1(uuid)',null,'06cbe78b729c4b3a683c7f6d0c2379f9'),
 ('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','76a3e46dd75f5a3c444bbf3755ab0bc6','0a9d8a40eaad998ffb26d36170a4c93e')
 ) e(signature,before_hash,after_hash) loop
   actual:=md5(pg_get_functiondef(to_regprocedure('public.'||x.signature)));
   if actual is distinct from x.after_hash then raise exception 'Field condition function postimage drift: %',x.signature; end if;
 end loop;
 for x in select * from (values
 ('product_spec_definition_revision','spec_definitions','a0bd95a165f3d6898086f6234fca5ec2','74dc221b889aae1ba07e69ff0870ef42'),
 ('spec_definition_template_rules_guard','spec_definitions',null,'7ea2735625ae81d1aceda141d16fa151'),
 ('spec_template_field_rules_guard','spec_template_fields',null,'e7cef22d324ebdc92894454d91c0c0de'),
 ('spec_template_rules_guard','spec_templates',null,'277df089eb89e702af996630bda57279')
 ) e(name,relation,before_hash,after_hash) loop
   select md5(pg_get_triggerdef(oid)) into actual from pg_trigger where tgname=x.name and tgrelid=('public.'||x.relation)::regclass;
   if actual is distinct from x.after_hash then raise exception 'Field condition trigger postimage drift: %',x.name; end if;
 end loop;
end $postimage$;
notify pgrst,'reload schema';
commit;
