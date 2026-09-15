-- Retired product answers are immutable history during ordinary saves.
-- No product facts, readings, assignments or operational data are rewritten.
begin;
-- Reviewed canonical definitions: fail closed on drift, accept exact replay.
do $guard$ declare r record; actual text; begin
 for r in select * from (values
('record_product_spec_reading_v1(uuid,text,jsonb,text,text)','8756b35a852f77e330715c587c2dc68f','49076ebef1568025b62ed51e48ae0442'),
('mirror_facts_into_product_specs_internal_v1()','4fd0207f766333c03381407fabeb15f7','0441072aa7fee0cf927b9e09815423e3'),
('save_product_spec_facts_v1(uuid,uuid[],jsonb)','46fb391ccfc59e454b727250bdf46424','c7ae43770592d0ae1a9bcf1ca83a9735'),
('spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)','d87ef3bb5a913c8accbfb519cdbd0ce5','1b9760ba2076900cb68b9afb627c5173'),
('spec_write_payload_internal_v2(uuid,uuid,jsonb,text)','9a3f9b1db3b156dbcf9e8c0448a8a945','8d1cd17f62155def6cd528baf82a4817')
 ) reviewed(signature,before_md5,after_md5) loop
   select md5(pg_get_functiondef(to_regprocedure(r.signature))) into actual;
   if not (actual is not distinct from r.before_md5 or actual is not distinct from r.after_md5) then
     raise exception 'Affected function changed since review: %',r.signature using errcode='55000';
   end if;
 end loop;
end $guard$;

CREATE OR REPLACE FUNCTION public.spec_validate_draft_internal_v1(p_template_id uuid, p_values jsonb, p_reference_id text DEFAULT NULL::text, p_brand text DEFAULT ''::text, p_model text DEFAULT ''::text, p_manufacturer_sku text DEFAULT ''::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_issues jsonb := '[]'::jsonb; v_field record; v_value jsonb;
  v_rule jsonb; v_allowed text[]; v_next text[]; v_condition boolean;
  v_message text; v_number numeric; v_key text; v_contract jsonb;
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
      if public.spec_rule_known_internal_v1(p_values->v_entry.key)
        and public.spec_rule_set_internal_v1(p_values->v_entry.key) <> public.spec_rule_set_internal_v1(v_entry.value) then
        v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','reference_conflict','field',v_entry.key,
          'message','El valor difiere de la referencia del fabricante.'));
      end if;
    end loop;
  end if;
  for v_field in select d.*, f.visibility_rules, f.constraint_rules from public.spec_template_fields f
    join public.spec_definitions d on d.id = f.spec_definition_id where f.template_id = p_template_id loop
    v_value := p_values->v_field.key;
    continue when not public.spec_rule_known_internal_v1(v_value);
    v_message := null;
    if p_reference_id is not null and v_contract->'roles'->>v_field.key='declaration'
      and v_field.key <> 'spec_evidence_source' and not (coalesce(v_reference.fact_values,'{}'::jsonb) ? v_field.id::text) then
      v_message := 'La referencia elegida no documenta esta declaración manual. Usa sus declaraciones o retira la referencia.';
    end if;
    for v_rule in select value from jsonb_array_elements(coalesce(v_field.visibility_rules,'[]')) loop
      v_condition := public.spec_condition_internal_v1(v_rule,p_values);
      if v_condition is false then
        v_message := 'Revisa los requisitos de este campo o retira el valor.';
      elsif v_condition is null then
        v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','prerequisite_missing','field',v_field.key,
          'message','Falta confirmar los requisitos del campo.','blocking',false));
      end if;
    end loop;
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
    elsif v_field.data_type in ('single_select','multi_select') then
      if (v_field.data_type = 'single_select' and jsonb_typeof(v_value) <> 'string') or
         (v_field.data_type = 'multi_select' and jsonb_typeof(v_value) <> 'array') then
        v_message := 'La cantidad de respuestas no corresponde al campo.';
      elsif not (public.spec_rule_set_internal_v1(v_value) <@
          public.spec_rule_set_internal_v1(v_field.allowed_values)) then
        v_message := 'La respuesta no pertenece a las opciones del campo.';
      end if;
    end if;
    v_allowed := null;
    for v_rule in select value from jsonb_array_elements(coalesce(v_field.constraint_rules,'[]')) loop
      if public.spec_condition_internal_v1(v_rule,p_values) is true then
        if jsonb_typeof(v_rule->'allow') <> 'array' then raise exception 'Invalid option rule' using errcode = '22023'; end if;
        v_next := public.spec_rule_set_internal_v1(v_rule->'allow');
        if v_allowed is null then v_allowed := v_next;
        else v_allowed := array(select unnest(v_allowed) intersect select unnest(v_next)); end if;
      end if;
    end loop;
    if v_allowed is not null and not (public.spec_rule_set_internal_v1(v_value) <@ v_allowed) then
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
    if jsonb_typeof(p_values->v_pair[1]) = 'number' and jsonb_typeof(p_values->v_pair[2]) = 'number'
      and (p_values->>v_pair[1])::numeric > (p_values->>v_pair[2])::numeric then
      v_issues := v_issues || jsonb_build_array(jsonb_build_object('code','range_order','field',v_pair[2],
        'message','El límite inferior no puede superar el superior.'));
    end if;
  end loop;
  return v_issues;
end $function$
;

CREATE OR REPLACE FUNCTION public.spec_write_payload_internal_v2(p_product_id uuid, p_template_id uuid, p_values jsonb, p_reference_id text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_tenant uuid := public.user_tenant_id(); v_entry record; v_def public.spec_definitions%rowtype;
  v_fact uuid; v_ids uuid[]; v_count integer := 0; v_reference jsonb := '{}'; v_payload jsonb; v_old jsonb; v_contract jsonb;
begin
  if v_tenant is null or auth.uid() is null or not exists (
    select 1 from public.products where id = p_product_id and tenant_id = v_tenant) then
    raise exception 'Producto no disponible para este tenant' using errcode = '42501';
  end if;
  select fact_values into v_reference from public.product_spec_references where id = p_reference_id;
  -- Explicitly submitted facts are independent observations. The client omits
  -- automatic values; reference validation still rejects conflicting facts.
  -- Reattribution to catalog would erase the observation on reload/detach.
  v_reference := coalesce(v_reference,'{}'::jsonb) - array(select jsonb_object_keys(p_values));
  v_payload := v_reference || p_values;
  if jsonb_typeof(v_payload) <> 'object' then raise exception 'Invalid fact payload' using errcode = '22023'; end if;
  -- No arbitrary definition list from the client, and no silently dropped IDs.
  if exists (select 1 from jsonb_object_keys(v_payload) k where not exists (
    select 1 from public.spec_template_fields f where f.template_id = p_template_id and f.spec_definition_id::text = k)) then
    raise exception 'La respuesta no pertenece a esta plantilla' using errcode = '23514';
  end if;
  select form_contract into v_contract from public.spec_templates where id=p_template_id;
  v_old:=public.spec_product_payload_internal_v1(p_product_id);
  -- Old clients may round-trip identical retired answers; omission preserves
  -- them too. Changed/new retired values need a separate reviewed repair.
  for v_entry in select e.* from jsonb_each(v_payload) e
    join public.spec_definitions d on d.id::text=e.key
    where v_contract->'roles'->>d.key='legacy' loop
    if v_old->v_entry.key is distinct from v_entry.value then
      raise exception 'El campo retirado se conserva como legacy y no admite cambios: %',v_entry.key using errcode='23514';
    end if;
    v_payload:=v_payload-v_entry.key;
  end loop;
  delete from public.spec_facts f using public.spec_template_fields tf
    where tf.template_id = p_template_id and tf.spec_definition_id = f.spec_definition_id
    and f.tenant_id = v_tenant and f.subject_type = 'product' and f.subject_id = p_product_id
    and f.subject_scope is null and not (v_payload ? f.spec_definition_id::text)
    and coalesce(v_contract->'roles'->>(select key from public.spec_definitions where id=f.spec_definition_id),'primary')<>'legacy';
  for v_entry in select * from jsonb_each(v_payload) loop
    select * into strict v_def from public.spec_definitions where id::text = v_entry.key;
    v_ids := null;
    if v_def.data_type in ('single_select','multi_select') then
      if jsonb_typeof(v_entry.value->'value_ids') is distinct from 'array'
        or jsonb_array_length(v_entry.value->'value_ids') = 0
        or (v_def.data_type = 'single_select' and jsonb_array_length(v_entry.value->'value_ids') <> 1) then
        raise exception 'Invalid option cardinality for %', v_def.key using errcode = '23514';
      end if;
      v_ids := array(select jsonb_array_elements_text(v_entry.value->'value_ids')::uuid);
      if cardinality(v_ids) <> (select count(distinct v.id) from public.spec_definition_values v
        where v.spec_definition_id = v_def.id and v.id = any(v_ids)) then
        raise exception 'Unknown, duplicate or foreign option for %', v_def.key using errcode = '23514';
      end if;
    elsif v_def.data_type = 'number' and jsonb_typeof(v_entry.value->'number') is distinct from 'number' then
      raise exception 'Expected numeric fact for %', v_def.key using errcode = '23514';
    elsif v_def.data_type = 'boolean' and jsonb_typeof(v_entry.value->'boolean') is distinct from 'boolean' then
      raise exception 'Expected boolean fact for %', v_def.key using errcode = '23514';
    elsif v_def.data_type not in ('number','boolean','single_select','multi_select')
      and jsonb_typeof(v_entry.value->'text') is distinct from 'string' then
      raise exception 'Expected text fact for %', v_def.key using errcode = '23514';
    end if;
    if exists(select 1 from public.spec_facts f where f.subject_type='product' and f.subject_id=p_product_id
      and f.tenant_id=v_tenant and f.subject_scope is null and f.spec_definition_id=v_def.id
      and public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(v_entry.key,v_old->v_entry.key))->v_def.key)
        = public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(v_entry.key,v_entry.value))->v_def.key)
      and (not (coalesce(v_reference,'{}'::jsonb) ? v_entry.key) or f.source='catalog')
      and (f.source<>'catalog' or coalesce(v_reference,'{}'::jsonb) ? v_entry.key)) then
      v_count := v_count+1;
      continue;
    end if;
    insert into public.spec_facts (tenant_id,subject_type,subject_id,spec_definition_id,
      value_number,value_boolean,value_text,source,confirmed)
    values (v_tenant,'product',p_product_id,v_def.id,
      case when v_def.data_type = 'number' then (v_entry.value->>'number')::numeric end,
      case when v_def.data_type = 'boolean' then (v_entry.value->>'boolean')::boolean end,
      case when v_def.data_type not in ('number','boolean','single_select','multi_select') then v_entry.value->>'text' end,
      case when coalesce(v_reference,'{}'::jsonb) ? v_entry.key then 'catalog' else 'mechanic' end, false)
    on conflict (tenant_id,subject_type,subject_id,spec_definition_id,coalesce(subject_scope,''))
    do update set value_number = excluded.value_number, value_boolean = excluded.value_boolean,
      value_text = excluded.value_text, source = excluded.source, confirmed = excluded.confirmed, updated_at = now()
    returning id into v_fact;
    delete from public.spec_fact_readings where fact_id = v_fact;
    delete from public.spec_fact_values where fact_id = v_fact;
    if v_ids is not null then
      insert into public.spec_fact_values(fact_id,value_id,position)
        select v_fact,id,(ordinality-1)::integer from unnest(v_ids) with ordinality a(id,ordinality);
    end if;
    v_count := v_count + 1;
  end loop;
  return v_count;
end $function$
;

CREATE OR REPLACE FUNCTION public.save_product_spec_facts_v1(p_product_id uuid, p_definition_ids uuid[], p_values jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_tenant uuid := public.user_tenant_id();
  v_definicion uuid;
  v_tipo text;
  v_entrada jsonb;
  v_fact uuid;
  v_escritos integer := 0;
  v_retired uuid[]; v_old jsonb; v_key text;
begin
  if v_tenant is null or auth.uid() is null then
    raise exception 'sin tenant' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.products
    where id = p_product_id and tenant_id = v_tenant
  ) then
    raise exception 'el producto no pertenece a este tenant' using errcode = '42501';
  end if;

  -- **La misma llave que toma la lectura, y antes de tocar nada.** Vaciar un
  -- criterio es lo primero que hace esta función; sin el candado acá, una
  -- lectura en vuelo podía reinsertar justo el campo que la persona acababa de
  -- vaciar, y el resultado quedaba escrito por el lector aunque la persona
  -- hubiera llegado después.
  perform pg_advisory_xact_lock(hashtextextended(
    v_tenant::text || ':spec_fact:' || p_product_id::text, 0));

  if jsonb_typeof(p_values) is distinct from 'object' or p_definition_ids is null then
    raise exception 'Invalid specification payload' using errcode = '22023';
  end if;
  if exists(select 1 from unnest(p_definition_ids) d where not exists(
    select 1 from public.spec_definitions sd where sd.id=d and (sd.tenant_id is null or sd.tenant_id=v_tenant)))
    or exists(select 1 from jsonb_object_keys(p_values) k where not k = any(array(select d::text from unnest(p_definition_ids) d))) then
    raise exception 'Unknown or foreign specification definition' using errcode = '23514';
  end if;
  if exists(select 1 from unnest(p_definition_ids) d where not exists(
      select 1 from public.product_spec_bindings_internal_v1 b
      join public.spec_template_fields tf on tf.template_id=b.template_id
      where b.product_id=p_product_id and tf.spec_definition_id=d)) then
    raise exception 'La respuesta no pertenece a esta plantilla' using errcode = '23514';
  end if;
  select coalesce(array_agg(d.id),'{}'::uuid[]) into v_retired
  from public.product_spec_bindings_internal_v1 b join public.spec_templates t on t.id=b.template_id
  join public.spec_template_fields f on f.template_id=t.id join public.spec_definitions d on d.id=f.spec_definition_id
  where b.product_id=p_product_id and d.id=any(p_definition_ids) and t.form_contract->'roles'->>d.key='legacy';
  v_old:=public.spec_product_payload_internal_v1(p_product_id);
  foreach v_definicion in array v_retired loop
    if not (p_values ? v_definicion::text) then continue; end if;
    select key,data_type into v_key,v_tipo from public.spec_definitions where id=v_definicion;
    v_entrada:=p_values->v_definicion::text;
    if v_tipo in ('single_select','multi_select') then
      v_entrada:=case when v_tipo='single_select' then v_entrada->'labels'->0 else v_entrada->'labels' end;
    else
      v_entrada:=v_entrada->case v_tipo when 'number' then 'number' when 'boolean' then 'boolean' else 'text' end;
    end if;
    if not(v_old ? v_definicion::text) or public.spec_payload_display_internal_v1(jsonb_build_object(v_definicion::text,v_old->v_definicion::text))->v_key is distinct from v_entrada then
      raise exception 'El campo retirado se conserva como legacy y no admite cambios: %',v_key using errcode='23514';
    end if;
    p_values:=p_values-v_definicion::text;
  end loop;
  p_definition_ids:=array(select d from unnest(p_definition_ids) d where not d=any(v_retired));
  for v_definicion in select unnest(p_definition_ids) loop
    v_entrada := p_values->v_definicion::text;
    continue when v_entrada is null;
    select data_type into strict v_tipo from public.spec_definitions where id=v_definicion;
    if v_tipo in ('single_select','multi_select') then
      if jsonb_typeof(v_entrada->'labels') is distinct from 'array'
        or jsonb_array_length(v_entrada->'labels')=0
        or (v_tipo='single_select' and jsonb_array_length(v_entrada->'labels')<>1) then
        raise exception 'Invalid option cardinality' using errcode = '23514';
      end if;
      if (select count(distinct v.id) from jsonb_array_elements_text(v_entrada->'labels') a(label)
        join public.spec_definition_values v on v.spec_definition_id=v_definicion and v.label=a.label)
        <> jsonb_array_length(v_entrada->'labels') then
        raise exception 'Unknown or duplicate specification option' using errcode = '23514';
      end if;
    elsif v_tipo='number' and jsonb_typeof(v_entrada->'number') is distinct from 'number' then
      raise exception 'Expected numeric specification value' using errcode = '23514';
    elsif v_tipo='boolean' and jsonb_typeof(v_entrada->'boolean') is distinct from 'boolean' then
      raise exception 'Expected boolean specification value' using errcode = '23514';
    end if;
  end loop;

  -- Lo que la plantilla incluye y el payload no trae, se borra: vaciar un
  -- campo es parte de guardar, no una operación aparte.
  delete from public.spec_facts f
  where f.tenant_id = v_tenant and f.subject_type = 'product'
    and f.subject_id = p_product_id and f.subject_scope is null
    and f.spec_definition_id = any(p_definition_ids)
    and not (p_values ? f.spec_definition_id::text);

  for v_definicion in
    select unnest(p_definition_ids)
  loop
    v_entrada := p_values -> v_definicion::text;
    continue when v_entrada is null;

    select data_type into v_tipo from public.spec_definitions where id = v_definicion;
    continue when v_tipo is null;

    insert into public.spec_facts (
      tenant_id, subject_type, subject_id, spec_definition_id,
      value_number, value_boolean, value_text, source, confirmed
    ) values (
      v_tenant, 'product', p_product_id, v_definicion,
      case when v_tipo = 'number'
           then nullif(v_entrada ->> 'number', '')::numeric end,
      case when v_tipo = 'boolean'
           then (v_entrada ->> 'boolean')::boolean end,
      case when v_tipo not in ('number','boolean','single_select','multi_select')
           then nullif(v_entrada ->> 'text', '') end,
      'mechanic', false
    )
    on conflict (tenant_id, subject_type, subject_id, spec_definition_id,
                 coalesce(subject_scope, ''))
    do update set
      value_number = excluded.value_number,
      value_boolean = excluded.value_boolean,
      value_text = excluded.value_text,
      -- **La persona gana de verdad.** Sin esto, guardar encima de una lectura
      -- del nombre dejaba el valor del mecanico con `source = 'name_reading'`
      -- y con el recibo de una cita que ya no lo sostiene: procedencia y
      -- respaldo falsos, y ademas el hecho caducaba solo al cambiar el nombre
      -- del producto, borrando en silencio lo que una persona escribio.
      source = excluded.source,
      confirmed = excluded.confirmed,
      updated_at = now()
    returning id into v_fact;

    -- El recibo se retira: ya no hay ninguna lectura que respaldar.
    delete from public.spec_fact_readings where fact_id = v_fact;
    delete from public.spec_fact_values where fact_id = v_fact;

    if v_tipo in ('single_select','multi_select')
       and jsonb_typeof(v_entrada -> 'labels') = 'array' then
      insert into public.spec_fact_values (fact_id, value_id, position)
      select v_fact, sv.id, (elem.ordinality - 1)::integer
      from jsonb_array_elements_text(v_entrada -> 'labels')
        with ordinality as elem(etiqueta, ordinality)
      join public.spec_definition_values sv
        on sv.spec_definition_id = v_definicion and sv.label = elem.etiqueta
      on conflict do nothing;
    end if;

    v_escritos := v_escritos + 1;
  end loop;

  perform public.spec_validate_product_internal_v1(p_product_id);
  return v_escritos;
end;
$function$;

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
end;
$function$
;

CREATE OR REPLACE FUNCTION public.mirror_facts_into_product_specs_internal_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare
  v_fact public.spec_facts%rowtype;
  v_tipo text;
  v_etiquetas text[];
begin
  if tg_op = 'DELETE' then
    if tg_table_name = 'spec_facts' then
      if old.subject_type <> 'product' or old.subject_scope is not null then
        return old;
      end if;
      delete from public.product_spec_values
      where tenant_id = old.tenant_id and product_id = old.subject_id
        and spec_definition_id = old.spec_definition_id;
      return old;
    end if;
    select * into v_fact from public.spec_facts where id = old.fact_id;
  elsif tg_table_name = 'spec_fact_values' then
    select * into v_fact from public.spec_facts where id = new.fact_id;
  else
    v_fact := new;
  end if;

  if v_fact.id is null or v_fact.subject_type <> 'product'
     or v_fact.subject_scope is not null then
    return coalesce(new, old);
  end if;

  select data_type into v_tipo from public.spec_definitions
  where id = v_fact.spec_definition_id;

  select array_agg(sv.label order by fv.position) into v_etiquetas
  from public.spec_fact_values fv
  join public.spec_definition_values sv on sv.id = fv.value_id
  where fv.fact_id = v_fact.id;

  insert into public.product_spec_values (
    tenant_id, product_id, spec_definition_id,
    value_number, value_boolean, value_text, value_option, value_json,
    display_value
  ) values (
    v_fact.tenant_id, v_fact.subject_id, v_fact.spec_definition_id,
    v_fact.value_number, v_fact.value_boolean, v_fact.value_text,
    case when v_tipo = 'single_select' then v_etiquetas[1] end,
    case when v_tipo = 'multi_select' then to_jsonb(v_etiquetas) end,
    coalesce(
      array_to_string(v_etiquetas, ', '),
      v_fact.value_text,
      v_fact.value_number::text,
      case when v_fact.value_boolean then 'Sí'
           when v_fact.value_boolean is not null then 'No' end
    )
  )
  on conflict (tenant_id, product_id, spec_definition_id) do update set
    value_number = excluded.value_number,
    value_boolean = excluded.value_boolean,
    value_text = excluded.value_text,
    value_option = excluded.value_option,
    value_json = excluded.value_json,
    display_value = excluded.display_value,
    updated_at = now();

  return coalesce(new, old);
end;
$function$;

-- Preserve one authenticated public command; implementation helpers cannot
-- become an alternate mutation entry point through inherited PUBLIC execute.
revoke all on function public.spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text) from public,anon,authenticated;
revoke all on function public.spec_write_payload_internal_v2(uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.save_product_spec_facts_v1(uuid,uuid[],jsonb) from public,anon;
grant execute on function public.save_product_spec_facts_v1(uuid,uuid[],jsonb) to authenticated;
revoke all on function public.record_product_spec_reading_v1(uuid,text,jsonb,text,text) from public,anon;
grant execute on function public.record_product_spec_reading_v1(uuid,text,jsonb,text,text) to authenticated;
revoke all on function public.mirror_facts_into_product_specs_internal_v1() from public,anon,authenticated;

-- Direct product writes must use the guarded commands. Other subject kinds
-- retain their existing tenant policies. SD mirrors keep the legacy projection.
drop policy if exists spec_facts_product_command_insert on public.spec_facts;
create policy spec_facts_product_command_insert on public.spec_facts as restrictive for insert to authenticated,anon with check (subject_type <> 'product');
drop policy if exists spec_facts_product_command_update on public.spec_facts;
create policy spec_facts_product_command_update on public.spec_facts as restrictive for update to authenticated,anon using (subject_type <> 'product') with check (subject_type <> 'product');
drop policy if exists spec_facts_product_command_delete on public.spec_facts;
create policy spec_facts_product_command_delete on public.spec_facts as restrictive for delete to authenticated,anon using (subject_type <> 'product');
drop policy if exists spec_fact_values_product_command_insert on public.spec_fact_values;
create policy spec_fact_values_product_command_insert on public.spec_fact_values as restrictive for insert to authenticated,anon with check (exists(select 1 from public.spec_facts f where f.id=fact_id and f.subject_type<>'product'));
drop policy if exists spec_fact_values_product_command_update on public.spec_fact_values;
create policy spec_fact_values_product_command_update on public.spec_fact_values as restrictive for update to authenticated,anon using (exists(select 1 from public.spec_facts f where f.id=fact_id and f.subject_type<>'product')) with check (exists(select 1 from public.spec_facts f where f.id=fact_id and f.subject_type<>'product'));
drop policy if exists spec_fact_values_product_command_delete on public.spec_fact_values;
create policy spec_fact_values_product_command_delete on public.spec_fact_values as restrictive for delete to authenticated,anon using (exists(select 1 from public.spec_facts f where f.id=fact_id and f.subject_type<>'product'));
drop policy if exists product_spec_values_product_command_insert on public.product_spec_values;
create policy product_spec_values_product_command_insert on public.product_spec_values as restrictive for insert to authenticated,anon with check (false);
drop policy if exists product_spec_values_product_command_update on public.product_spec_values;
create policy product_spec_values_product_command_update on public.product_spec_values as restrictive for update to authenticated,anon using (false) with check (false);
drop policy if exists product_spec_values_product_command_delete on public.product_spec_values;
create policy product_spec_values_product_command_delete on public.product_spec_values as restrictive for delete to authenticated,anon using (false);
notify pgrst,'reload schema';
commit;
