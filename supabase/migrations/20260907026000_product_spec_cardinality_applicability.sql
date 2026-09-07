-- Suppress an impossible completeness request for an inapplicable collection.
-- One private validator changes; observations, catalogue metadata and ACL stay intact.
begin;
set local lock_timeout='5s';
set local statement_timeout='30s';
do $before$
declare fn regprocedure:='public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)'::regprocedure; p record;
begin
 select x.*,pg_get_userbyid(x.proowner) owner_name,md5(pg_get_functiondef(x.oid)) body_md5 into p from pg_proc x where x.oid=fn;
 if p.owner_name<>'postgres' or p.prosecdef or p.provolatile<>'s'
  or p.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp']::text[]
  or p.proacl::text is distinct from '{postgres=X/postgres,service_role=X/postgres}'
  or p.body_md5 not in ('9ea12d82761d6ffd0584d460cbc998d6','ac0738d5c2039412b603dc71adc41721') then
   raise exception 'Unreviewed cardinality applicability function state';
 end if;
end
$before$;

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
    where not(c->>'code'='row_cardinality_pending' and c->>'field'=any(v_inapplicable))
    and not(c->>'code'='row_cardinality_conflict' and exists(select 1 from jsonb_array_elements(v_issues) i
      where i->>'field'=c->>'field' and i->>'code'='field_applicability' and i->'blocking'='true'::jsonb))
    and not(c->>'code'='row_cardinality_total' and exists(select 1 from jsonb_array_elements(v_issues) i
      where i->>'field'=c->>'field' and i->>'code'='field_constraint' and coalesce(i->'blocking','true'::jsonb)='true'::jsonb));
  v_issues:=v_issues||v_coherence;
  return v_issues;
end $function$
;

do $after$
declare fn regprocedure:='public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)'::regprocedure; p record;
begin
 select x.*,pg_get_userbyid(x.proowner) owner_name,md5(pg_get_functiondef(x.oid)) body_md5 into p from pg_proc x where x.oid=fn;
 if p.owner_name<>'postgres' or p.prosecdef or p.provolatile<>'s'
  or p.proconfig is distinct from array['search_path=pg_catalog, public, pg_temp']::text[]
  or p.proacl::text is distinct from '{postgres=X/postgres,service_role=X/postgres}'
  or p.body_md5 not in ('ac0738d5c2039412b603dc71adc41721') then
   raise exception 'Unreviewed cardinality applicability function state';
 end if;
end
$after$;
commit;
