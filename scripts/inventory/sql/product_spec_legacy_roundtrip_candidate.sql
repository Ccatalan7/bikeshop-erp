-- Typed legacy round-trip. No observation, template or profile rewrite.
do $predecessor$ begin
 if not exists(select 1 from pg_proc where oid='public.spec_write_scope_payload_internal_v1(uuid,uuid,jsonb,text,text)'::regprocedure
   and md5(pg_get_functiondef(oid)) in ('1ec9a61aa2a4be4093be590af2f1a610','cf4c62043ce36a3f62af020fade60417')
   and pg_get_userbyid(proowner)='postgres' and prosecdef and provolatile='v'
   and proconfig=array['search_path=pg_catalog, public, pg_temp']::text[]
   and proacl=array['postgres=X/postgres','service_role=X/postgres']::aclitem[]) then
  raise exception 'Unreviewed scoped writer predecessor';
 end if;
end $predecessor$;
CREATE OR REPLACE FUNCTION public.spec_write_scope_payload_internal_v1(p_product_id uuid, p_template_id uuid, p_values jsonb, p_reference_id text, p_scope text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pg_temp'
AS $function$
declare v_tenant uuid := public.user_tenant_id(); v_entry record; v_def public.spec_definitions%rowtype;
  v_fact uuid; v_ids uuid[]; v_count integer := 0; v_reference jsonb := '{}'; v_payload jsonb; v_old jsonb; v_contract jsonb; v_preserved jsonb;
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
  v_old:=public.spec_product_scope_payload_internal_v1(p_product_id,p_scope);
  -- Old clients may round-trip identical retired answers; omission preserves
  -- them too. Changed/new retired values need a separate reviewed repair.
  for v_entry in select e.* from jsonb_each(v_payload) e
    join public.spec_definitions d on d.id::text=e.key
    where v_contract->'roles'->>d.key='legacy' loop
    if v_old->v_entry.key is distinct from v_entry.value then
      select * into strict v_def from public.spec_definitions where id::text=v_entry.key;
      v_preserved:=v_old->v_entry.key;
      -- The editor transports exact decimals as text; PostgreSQL observations
      -- are numeric JSON. Compare typed values without rewriting the legacy
      -- observation, its source, timestamp, options or reading receipts.
      if v_def.data_type='number' and jsonb_typeof(v_entry.value)='object'
        and not exists(select 1 from jsonb_object_keys(v_entry.value) k where k<>'number')
        and public.spec_rule_number_internal_v1(v_entry.value->'number') is not null
        and public.spec_rule_number_internal_v1(v_preserved->'number') is not null then
        v_entry.value:=jsonb_build_object('number',public.spec_rule_number_internal_v1(v_entry.value->'number'));
        v_preserved:=jsonb_build_object('number',public.spec_rule_number_internal_v1(v_preserved->'number'));
      elsif v_def.data_type='json' and v_def.validation_rules ? 'rows_schema'
        and jsonb_typeof(v_entry.value)='object'
        and not exists(select 1 from jsonb_object_keys(v_entry.value) k where k<>'rows')
        and v_preserved is not null then
        v_entry.value:=jsonb_build_object('rows',public.spec_rows_validate_internal_v1(
          v_def.validation_rules->'rows_schema',v_entry.value->'rows'));
        v_preserved:=jsonb_build_object('rows',public.spec_rows_validate_internal_v1(
          v_def.validation_rules->'rows_schema',v_preserved->'rows'));
      end if;
      if v_preserved is distinct from v_entry.value then
        raise exception 'El campo retirado se conserva como legacy y no admite cambios: %',v_entry.key using errcode='23514';
      end if;
    end if;
    v_payload:=v_payload-v_entry.key;
  end loop;
  delete from public.spec_facts f using public.spec_template_fields tf
    where tf.template_id = p_template_id and tf.spec_definition_id = f.spec_definition_id
    and f.tenant_id = v_tenant and f.subject_type = 'product' and f.subject_id = p_product_id
    and f.subject_scope is not distinct from p_scope and not (v_payload ? f.spec_definition_id::text)
    and coalesce(v_contract->'roles'->>(select key from public.spec_definitions where id=f.spec_definition_id),'primary')<>'legacy';
  for v_entry in select * from jsonb_each(v_payload) loop
    select * into strict v_def from public.spec_definitions where id::text = v_entry.key;
    v_ids := null;
    if v_def.data_type='json' and v_def.validation_rules ? 'rows_schema' then
      if jsonb_typeof(v_entry.value) is distinct from 'object' or exists(
        select 1 from jsonb_object_keys(v_entry.value) k where k<>'rows') then
        raise exception 'La configuración requiere un payload de filas' using errcode='23514';
      end if;
      v_entry.value:=jsonb_build_object('rows',public.spec_rows_validate_internal_v1(
        v_def.validation_rules->'rows_schema',v_entry.value->'rows'));
    end if;
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
    elsif v_def.data_type = 'number' and (jsonb_typeof(v_entry.value->'number') not in ('number','string') or public.spec_rule_number_internal_v1(v_entry.value->'number') is null) then
      raise exception 'Expected numeric fact for %', v_def.key using errcode = '23514';
    elsif v_def.data_type = 'boolean' and jsonb_typeof(v_entry.value->'boolean') is distinct from 'boolean' then
      raise exception 'Expected boolean fact for %', v_def.key using errcode = '23514';
    elsif not (v_def.data_type='json' and v_def.validation_rules ? 'rows_schema')
      and v_def.data_type not in ('number','boolean','single_select','multi_select')
      and jsonb_typeof(v_entry.value->'text') is distinct from 'string' then
      raise exception 'Expected text fact for %', v_def.key using errcode = '23514';
    end if;
    if exists(select 1 from public.spec_facts f where f.subject_type='product' and f.subject_id=p_product_id
      and f.tenant_id=v_tenant and f.subject_scope is not distinct from p_scope and f.spec_definition_id=v_def.id
      and public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(v_entry.key,v_old->v_entry.key))->v_def.key)
        = public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(jsonb_build_object(v_entry.key,v_entry.value))->v_def.key)
      and (not (coalesce(v_reference,'{}'::jsonb) ? v_entry.key) or f.source='catalog')
      and (f.source<>'catalog' or coalesce(v_reference,'{}'::jsonb) ? v_entry.key)) then
      v_count := v_count+1;
      continue;
    end if;
    insert into public.spec_facts (tenant_id,subject_type,subject_id,subject_scope,spec_definition_id,
      value_number,value_boolean,value_text,value_json,source,confirmed)
    values (v_tenant,'product',p_product_id,p_scope,v_def.id,
      case when v_def.data_type = 'number' then (v_entry.value->>'number')::numeric end,
      case when v_def.data_type = 'boolean' then (v_entry.value->>'boolean')::boolean end,
      case when v_def.data_type not in ('number','boolean','single_select','multi_select') and not(v_def.validation_rules ? 'rows_schema') then v_entry.value->>'text' end,
      case when v_def.data_type='json' and v_def.validation_rules ? 'rows_schema' then v_entry.value->'rows' end,
      case when coalesce(v_reference,'{}'::jsonb) ? v_entry.key then 'catalog' else 'mechanic' end, false)
    on conflict (tenant_id,subject_type,subject_id,spec_definition_id,coalesce(subject_scope,''))
    do update set value_number = excluded.value_number, value_boolean = excluded.value_boolean,
      value_text = excluded.value_text, value_json=excluded.value_json, source = excluded.source, confirmed = excluded.confirmed, updated_at = now()
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
end $function$;

do $postimage$ begin
 if md5(pg_get_functiondef('public.spec_write_scope_payload_internal_v1(uuid,uuid,jsonb,text,text)'::regprocedure))<>'cf4c62043ce36a3f62af020fade60417' then
  raise exception 'Typed legacy writer postimage mismatch';
 end if;
end $postimage$;
