-- Source-backed product specification editing. Additive, no catalogue backfill.
begin;

alter table public.spec_templates
  add column if not exists form_contract jsonb not null default '{}'::jsonb,
  add column if not exists contract_version integer not null default 1;

alter table public.spec_template_fields
  add column if not exists constraint_rules jsonb not null default '[]'::jsonb;

drop trigger if exists product_spec_template_revision on public.spec_templates;
drop trigger if exists product_spec_field_revision on public.spec_template_fields;
drop trigger if exists product_spec_definition_revision on public.spec_definitions;
drop trigger if exists product_spec_option_revision on public.spec_definition_values;

create table if not exists public.product_spec_references (
  id text primary key,
  technical_family text not null,
  brand text not null,
  model text not null,
  manufacturer_sku text,
  label text not null,
  fact_values jsonb not null check (jsonb_typeof(fact_values) = 'object'),
  sources jsonb not null check (jsonb_typeof(sources) = 'array' and jsonb_array_length(sources) > 0),
  claims jsonb not null default '[]'::jsonb check (jsonb_typeof(claims) = 'array'),
  reviewed_on date not null,
  created_at timestamptz not null default now()
);
alter table public.product_spec_references enable row level security;
drop policy if exists product_spec_references_read on public.product_spec_references;
create policy product_spec_references_read on public.product_spec_references
  for select to authenticated using (true);
revoke all on public.product_spec_references from authenticated;
grant select on public.product_spec_references to authenticated;
revoke all on public.product_spec_references from anon;

alter table public.products
  add column if not exists spec_revision bigint not null default 0,
  add column if not exists spec_reference_id text references public.product_spec_references(id);

create table if not exists public.product_spec_save_receipts (
  tenant_id uuid not null references public.tenants(id),
  operation_key text not null check (length(operation_key) between 1 and 180),
  request_hash text not null,
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key (tenant_id, operation_key)
);
alter table public.product_spec_save_receipts enable row level security;
revoke all on public.product_spec_save_receipts from anon, authenticated;

create or replace function public.spec_rule_normalize_internal_v1(p_value jsonb)
returns text language plpgsql immutable set search_path = pg_catalog, public, pg_temp as $$
declare v_text text := btrim(p_value #>> '{}'); v_number numeric;
begin
  if p_value is null or p_value = 'null'::jsonb then return ''; end if;
  if replace(v_text, ',', '.') ~ '^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$' then
    v_number := replace(v_text, ',', '.')::numeric;
    return case when position('.' in v_number::text) > 0
      then rtrim(rtrim(v_number::text, '0'), '.') else v_number::text end;
  end if;
  return v_text;
end $$;

create or replace function public.spec_rule_known_internal_v1(p_value jsonb)
returns boolean language plpgsql immutable set search_path = pg_catalog, public, pg_temp as $$
begin
  if p_value is null or p_value = 'null'::jsonb then return false; end if;
  if jsonb_typeof(p_value) = 'array' then
    return jsonb_array_length(p_value) > 0 and not exists (
      select 1 from jsonb_array_elements(p_value) e where not public.spec_rule_known_internal_v1(e));
  end if;
  return lower(btrim(p_value #>> '{}')) not in ('', 'desconocido / sin confirmar', 'unknown');
end $$;

create or replace function public.spec_rule_set_internal_v1(p_value jsonb)
returns text[] language sql immutable set search_path = pg_catalog, public, pg_temp as $$
  select coalesce(array_agg(distinct public.spec_rule_normalize_internal_v1(e)
    order by public.spec_rule_normalize_internal_v1(e)), '{}'::text[])
  from jsonb_array_elements(case when jsonb_typeof(p_value) = 'array'
    then p_value else jsonb_build_array(p_value) end) e
$$;

-- SQL NULL is unknown, not false. Same operators and set semantics as Dart.
create or replace function public.spec_condition_internal_v1(p_rule jsonb, p_values jsonb)
returns boolean language plpgsql immutable set search_path = pg_catalog, public, pg_temp as $$
declare v_child jsonb; v_result boolean; v_unknown boolean := false;
  v_group text; v_operator text := coalesce(p_rule->>'operator', 'eq');
  v_actual jsonb; v_set text[]; v_expected text[];
begin
  foreach v_group in array array['all','any'] loop
    if p_rule ? v_group then
      if jsonb_typeof(p_rule->v_group) <> 'array' or jsonb_array_length(p_rule->v_group) = 0 then
        raise exception 'Invalid specification condition group' using errcode = '22023';
      end if;
      for v_child in select value from jsonb_array_elements(p_rule->v_group) loop
        v_result := public.spec_condition_internal_v1(v_child, p_values);
        if v_group = 'all' and v_result = false then return false; end if;
        if v_group = 'any' and v_result = true then return true; end if;
        v_unknown := v_unknown or v_result is null;
      end loop;
      return case when v_unknown then null else v_group = 'all' end;
    end if;
  end loop;
  if nullif(p_rule->>'field', '') is null then
    raise exception 'Specification condition requires a field' using errcode = '22023';
  end if;
  v_actual := p_values->(p_rule->>'field');
  if v_operator = 'is_set' then return public.spec_rule_known_internal_v1(v_actual); end if;
  if v_operator = 'not_set' then return not public.spec_rule_known_internal_v1(v_actual); end if;
  if v_operator not in ('eq','neq','in','not_in','contains_any','contains_all') then
    raise exception 'Unsupported specification operator: %', v_operator using errcode = '22023';
  end if;
  if not public.spec_rule_known_internal_v1(v_actual) then return null; end if;
  v_set := public.spec_rule_set_internal_v1(v_actual);
  v_expected := public.spec_rule_set_internal_v1(p_rule->'value');
  return case v_operator
    when 'eq' then v_set = v_expected when 'neq' then v_set <> v_expected
    when 'in' then v_set <@ v_expected when 'not_in' then not (v_set && v_expected)
    when 'contains_any' then v_set && v_expected when 'contains_all' then v_set @> v_expected end;
end $$;

create or replace function public.spec_payload_display_internal_v1(p_values jsonb)
returns jsonb language sql stable set search_path = pg_catalog, public, pg_temp as $$
  select coalesce(jsonb_object_agg(d.key,
    case d.data_type when 'number' then e.value->'number'
      when 'boolean' then e.value->'boolean'
      when 'single_select' then to_jsonb((select v.label from public.spec_definition_values v
        where v.spec_definition_id = d.id and v.id::text = e.value->'value_ids'->>0))
      when 'multi_select' then coalesce((select jsonb_agg(v.label order by a.ordinality)
        from jsonb_array_elements_text(e.value->'value_ids') with ordinality a(id, ordinality)
        join public.spec_definition_values v on v.id::text = a.id and v.spec_definition_id = d.id), '[]'::jsonb)
      else e.value->'text' end), '{}'::jsonb)
  from jsonb_each(p_values) e join public.spec_definitions d on d.id::text = e.key
$$;

create or replace function public.spec_product_payload_internal_v1(p_product_id uuid)
returns jsonb language sql stable set search_path = pg_catalog, public, pg_temp as $$
  select coalesce(jsonb_object_agg(f.spec_definition_id::text,
    case d.data_type when 'number' then jsonb_build_object('number',f.value_number)
      when 'boolean' then jsonb_build_object('boolean',f.value_boolean)
      when 'single_select' then jsonb_build_object('value_ids',coalesce(v.ids,'[]'::jsonb))
      when 'multi_select' then jsonb_build_object('value_ids',coalesce(v.ids,'[]'::jsonb))
      else jsonb_build_object('text',f.value_text) end), '{}'::jsonb)
  from public.spec_facts f join public.spec_definitions d on d.id = f.spec_definition_id
  left join lateral (select jsonb_agg(fv.value_id order by fv.position) ids
    from public.spec_fact_values fv where fv.fact_id = f.id) v on true
  where f.subject_type = 'product' and f.subject_id = p_product_id
    and f.subject_scope is null
    and f.tenant_id=(select tenant_id from public.products where id=p_product_id)
$$;

create or replace function public.spec_validate_draft_internal_v1(
  p_template_id uuid, p_values jsonb, p_reference_id text default null,
  p_brand text default '', p_model text default '', p_manufacturer_sku text default ''
) returns jsonb language plpgsql stable set search_path = pg_catalog, public, pg_temp as $$
declare v_issues jsonb := '[]'::jsonb; v_field record; v_value jsonb;
  v_rule jsonb; v_allowed text[]; v_next text[]; v_condition boolean;
  v_message text; v_number numeric; v_key text; v_contract jsonb;
  v_reference public.product_spec_references%rowtype; v_entry record; v_pair text[];
begin
  select form_contract into v_contract from public.spec_templates where id = p_template_id;
  if v_contract is null then raise exception 'Unknown specification template' using errcode = '22023'; end if;
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
end $$;

create or replace function public.get_product_spec_references_v1(p_family text)
returns jsonb language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select coalesce(jsonb_agg((to_jsonb(r) - 'fact_values') ||
    jsonb_build_object('facts',public.spec_payload_display_internal_v1(r.fact_values)) order by r.label),'[]'::jsonb)
  from public.product_spec_references r where r.technical_family = p_family
    and auth.uid() is not null and public.user_tenant_id() is not null
$$;

create or replace function public.get_product_spec_snapshot_v1(p_product_id uuid)
returns jsonb language plpgsql stable security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_result jsonb;
begin
  select jsonb_build_object('revision',p.spec_revision,'reference_id',p.spec_reference_id,
    'category_id',p.category_id,'catalog_keys',(select coalesce(jsonb_agg(d.key),'[]'::jsonb) from public.spec_facts f join public.spec_definitions d on d.id = f.spec_definition_id where f.subject_type = 'product' and f.subject_id = p.id and f.subject_scope is null and f.source = 'catalog'),'values',public.spec_payload_display_internal_v1(public.spec_product_payload_internal_v1(p.id)))
    into v_result from public.products p where p.id = p_product_id and p.tenant_id = public.user_tenant_id()
      and auth.uid() is not null;
  if v_result is null then raise exception 'Producto no disponible para este tenant' using errcode = '42501'; end if;
  return v_result;
end $$;

create or replace function public.get_product_spec_contexts_v1(p_product_ids uuid[])
returns jsonb language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  select coalesce(jsonb_object_agg(p.id, coalesce(v.facts,'{}'::jsonb) || jsonb_build_object(
    '__reference_claims',coalesce(r.claims,'[]'::jsonb),
    '__spec_issues',case when t.id is null then '[{"code":"unmapped"}]'::jsonb
      else public.spec_validate_draft_internal_v1(t.id,v.facts,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) end)), '{}')
  from public.products p
  left join public.category_tech_mappings m on m.category_id=p.category_id and m.tenant_id=p.tenant_id and m.status='active'
  left join public.spec_templates t on t.id=m.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
  left join public.product_spec_references r on r.id=p.spec_reference_id
  cross join lateral (select coalesce(jsonb_object_agg(e.key,e.value),'{}'::jsonb) facts
    from jsonb_each(public.spec_payload_display_internal_v1(public.spec_product_payload_internal_v1(p.id))) e
    where exists(select 1 from public.spec_template_fields f join public.spec_definitions d on d.id=f.spec_definition_id
      where f.template_id=t.id and d.key=e.key and coalesce(t.form_contract->'roles'->>d.key,'primary') <> 'legacy')) v
  where p.id=any(p_product_ids) and p.tenant_id=public.user_tenant_id() and auth.uid() is not null
$$;

create or replace function public.spec_write_payload_internal_v2(
  p_product_id uuid, p_template_id uuid, p_values jsonb, p_reference_id text
) returns integer language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_tenant uuid := public.user_tenant_id(); v_entry record; v_def public.spec_definitions%rowtype;
  v_fact uuid; v_ids uuid[]; v_count integer := 0; v_reference jsonb := '{}'; v_payload jsonb;
begin
  if v_tenant is null or auth.uid() is null or not exists (
    select 1 from public.products where id = p_product_id and tenant_id = v_tenant) then
    raise exception 'Producto no disponible para este tenant' using errcode = '42501';
  end if;
  select fact_values into v_reference from public.product_spec_references where id = p_reference_id;
  v_payload := coalesce(v_reference,'{}'::jsonb) || p_values;
  if jsonb_typeof(v_payload) <> 'object' then raise exception 'Invalid fact payload' using errcode = '22023'; end if;
  -- No arbitrary definition list from the client, and no silently dropped IDs.
  if exists (select 1 from jsonb_object_keys(v_payload) k where not exists (
    select 1 from public.spec_template_fields f where f.template_id = p_template_id and f.spec_definition_id::text = k)) then
    raise exception 'La respuesta no pertenece a esta plantilla' using errcode = '23514';
  end if;
  delete from public.spec_facts f using public.spec_template_fields tf
    where tf.template_id = p_template_id and tf.spec_definition_id = f.spec_definition_id
    and f.tenant_id = v_tenant and f.subject_type = 'product' and f.subject_id = p_product_id
    and f.subject_scope is null and not (v_payload ? f.spec_definition_id::text);
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
      and public.spec_rule_set_internal_v1(public.spec_payload_display_internal_v1(public.spec_product_payload_internal_v1(p_product_id))->v_def.key)
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
end $$;

create or replace function public.spec_validate_product_internal_v1(p_product_id uuid)
returns void language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_product public.products%rowtype; v_template uuid; v_issues jsonb;
begin
  select * into v_product from public.products where id = p_product_id;
  if not found then return; end if;
  select m.template_id into v_template from public.category_tech_mappings m
    join public.spec_templates t on t.id = m.template_id and t.is_active
    where m.category_id = v_product.category_id and m.tenant_id = v_product.tenant_id and m.status = 'active'
      and (t.tenant_id is null or t.tenant_id = v_product.tenant_id);
  if v_template is null then
    if v_product.spec_reference_id is not null then
      raise exception 'La referencia requiere una familia técnica' using errcode = '23514';
    end if;
    return;
  end if;
  if exists(select 1 from public.spec_facts f join public.spec_definitions d on d.id=f.spec_definition_id
    where f.subject_type='product' and f.subject_id=p_product_id and f.subject_scope is null and (
      (d.data_type='number' and (f.value_boolean is not null or f.value_text is not null)) or
      (d.data_type='boolean' and (f.value_number is not null or f.value_text is not null)) or
      (d.data_type not in ('number','boolean','single_select','multi_select') and (f.value_number is not null or f.value_boolean is not null)) or
      (d.data_type in ('single_select','multi_select') and num_nonnulls(f.value_number,f.value_boolean,f.value_text)>0) or
      exists(select 1 from public.spec_fact_values fv join public.spec_definition_values v on v.id=fv.value_id
        where fv.fact_id=f.id and (v.spec_definition_id<>f.spec_definition_id or d.data_type not in ('single_select','multi_select'))) or
      (d.data_type='single_select' and (select count(*) from public.spec_fact_values fv where fv.fact_id=f.id)>1)
    )) then raise exception 'Invalid specification shape or option ownership' using errcode='23514'; end if;
  if v_product.spec_reference_id is not null and exists(
    select 1 from public.product_spec_references r cross join lateral jsonb_object_keys(r.fact_values) k
    where r.id=v_product.spec_reference_id and (not (public.spec_product_payload_internal_v1(p_product_id) ? k)
      or not public.spec_rule_known_internal_v1(public.spec_payload_display_internal_v1(public.spec_product_payload_internal_v1(p_product_id))->(select d.key from public.spec_definitions d where d.id::text=k)))
  ) then raise exception 'La referencia requiere sus datos documentados' using errcode='23514'; end if;
  v_issues := public.spec_validate_draft_internal_v1(v_template,
    public.spec_payload_display_internal_v1(public.spec_product_payload_internal_v1(p_product_id)),
    v_product.spec_reference_id,v_product.brand,v_product.model,v_product.manufacturer_sku);
  if exists(select 1 from jsonb_array_elements(v_issues) i where coalesce((i->>'blocking')::boolean,true)) then
    raise exception 'La ficha técnica tiene conflictos' using errcode = '23514', detail = v_issues::text;
  end if;
end $$;

-- The public store uses the same active fields. Internal source notes and
-- retired compatibility labels cannot leak through the legacy mirror.
create or replace function public.get_public_product_technical_specs(p_tenant_id uuid,p_product_id uuid)
returns table(section_key text,section_sort_order integer,field_sort_order integer,spec_key text,
  spec_label text,display_value text,unit text,data_type text)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  with visible as (
    select p.id,p.brand,p.model,p.manufacturer_sku,p.spec_reference_id,t.id template_id,t.form_contract
    from public.products p
    join public.category_tech_mappings m on m.category_id=p.category_id and m.tenant_id=p.tenant_id and m.status='active'
    join public.spec_templates t on t.id=m.template_id and t.is_active and (t.tenant_id is null or t.tenant_id=p.tenant_id)
    where p.id=p_product_id and p.tenant_id=p_tenant_id and coalesce(p.is_active,true)
      and coalesce(p.is_published,false) and coalesce(p.show_on_website,false)
  ), facts as (
    select p.*,public.spec_payload_display_internal_v1(public.spec_product_payload_internal_v1(p.id)) vals from visible p
  ), assessed as (select p.*,public.spec_validate_draft_internal_v1(p.template_id,p.vals,p.spec_reference_id,p.brand,p.model,p.manufacturer_sku) issues from facts p
  ), fields as (
    select f.section_key,f.sort_order,d.key,coalesce(p.form_contract->'labels'->>d.key,d.label) label,
      d.unit,d.data_type,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  )
  select f.section_key,dense_rank() over(order by f.section_order,f.section_key)::integer,
    f.sort_order,f.key,f.label,case
      when jsonb_typeof(f.val)='array' then (select string_agg(e,', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      else f.val#>>'{}' end,f.unit,f.data_type
  from fields f order by f.section_order,f.sort_order,f.label
$$;
revoke all on function public.get_public_product_technical_specs(uuid,uuid) from public;
grant execute on function public.get_public_product_technical_specs(uuid,uuid) to anon,authenticated;

-- One transaction for the product, normalized facts and optional set command.
-- The product patch is an explicit allowlist, never an arbitrary table writer.
create or replace function public.save_product_with_specs_v1(
  p_product jsonb, p_is_new boolean, p_template_id uuid, p_contract_version integer,
  p_values jsonb, p_expected_revision bigint, p_reference_id text,
  p_operation_key text, p_expected_updated_at timestamptz, p_components jsonb default null
) returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
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
  select t.* into v_template from public.category_tech_mappings m
    join public.spec_templates t on t.id = m.template_id and t.is_active
    where m.category_id = nullif(p_product->>'category_id','')::uuid
      and m.tenant_id = v_tenant and m.status = 'active'
      and (t.tenant_id is null or t.tenant_id = v_tenant);
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
end $$;

-- A tenant-scoped fact must also point at a product from that tenant.
-- Observation identity is immutable; moving it would leave an old reference
-- without its required facts and would evade that product's revision guard.
create or replace function public.spec_product_fact_graph_internal_v1()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if tg_table_name='spec_fact_values' then
    if tg_op='UPDATE' and new.fact_id<>old.fact_id and exists(
      select 1 from public.spec_facts where id in (old.fact_id,new.fact_id) and subject_type='product') then
      raise exception 'Product observation identity is immutable' using errcode='23514';
    end if;
  elsif new.subject_type='product' or (tg_op='UPDATE' and old.subject_type='product') then
    if tg_op='UPDATE' and (new.tenant_id,new.subject_type,new.subject_id,new.subject_scope,new.spec_definition_id)
      is distinct from (old.tenant_id,old.subject_type,old.subject_id,old.subject_scope,old.spec_definition_id) then
      raise exception 'Product observation identity is immutable' using errcode='23514';
    end if;
    if not exists(select 1 from public.products p join public.spec_definitions d on d.id=new.spec_definition_id
      where p.id=new.subject_id and p.tenant_id=new.tenant_id and (d.tenant_id is null or d.tenant_id=p.tenant_id)) then
      raise exception 'Foreign product specification relation' using errcode='42501';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists product_spec_fact_graph on public.spec_facts;
create trigger product_spec_fact_graph before insert or update on public.spec_facts
  for each row execute function public.spec_product_fact_graph_internal_v1();
drop trigger if exists product_spec_value_graph on public.spec_fact_values;
create trigger product_spec_value_graph before update on public.spec_fact_values
  for each row execute function public.spec_product_fact_graph_internal_v1();
revoke all on function public.spec_product_fact_graph_internal_v1() from public,anon,authenticated;

-- Increment the revision for every fact writer, including older clients.
create or replace function public.spec_product_revision_internal_v1()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_subject uuid; v_type text;
begin
  if tg_table_name = 'products' then
    if (new.brand,new.model,new.manufacturer_sku,new.category_id,new.spec_reference_id)
      is distinct from (old.brand,old.model,old.manufacturer_sku,old.category_id,old.spec_reference_id) then
      new.spec_revision := old.spec_revision + 1;
    elsif pg_trigger_depth() > 1 and new.spec_revision = old.spec_revision + 1 then
      null; -- Only a nested fact trigger may increment without identity change.
    else
      new.spec_revision := old.spec_revision;
    end if;
    return new;
  elsif tg_table_name = 'spec_facts' then
    if tg_op = 'DELETE' then v_subject := old.subject_id; v_type := old.subject_type;
    else v_subject := new.subject_id; v_type := new.subject_type; end if;
  else
    select f.subject_id,f.subject_type into v_subject,v_type from public.spec_facts f
      where f.id = case when tg_op = 'DELETE' then old.fact_id else new.fact_id end;
  end if;
  if v_type = 'product' then
    update public.products set spec_revision = spec_revision + 1 where id = v_subject;
  end if;
  return null;
end $$;

drop trigger if exists product_spec_identity_revision on public.products;
create trigger product_spec_identity_revision before update
  on public.products for each row execute function public.spec_product_revision_internal_v1();
drop trigger if exists product_spec_fact_revision on public.spec_facts;
create trigger product_spec_fact_revision after insert or update or delete on public.spec_facts
  for each row execute function public.spec_product_revision_internal_v1();
drop trigger if exists product_spec_value_revision on public.spec_fact_values;
create trigger product_spec_value_revision after insert or update or delete on public.spec_fact_values
  for each row execute function public.spec_product_revision_internal_v1();

create or replace function public.spec_product_constraint_internal_v1()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
declare v_subject uuid; v_type text;
begin
  if tg_table_name = 'products' then
    if tg_op = 'UPDATE' and (new.brand,new.model,new.manufacturer_sku,new.category_id,new.spec_reference_id)
      is not distinct from (old.brand,old.model,old.manufacturer_sku,old.category_id,old.spec_reference_id) then return null; end if;
    v_subject := new.id; v_type := 'product';
  elsif tg_table_name = 'spec_facts' then
    if tg_op = 'DELETE' then v_subject := old.subject_id; v_type := old.subject_type;
    else v_subject := new.subject_id; v_type := new.subject_type; end if;
  else
    select f.subject_id,f.subject_type into v_subject,v_type from public.spec_facts f
      where f.id = case when tg_op = 'DELETE' then old.fact_id else new.fact_id end;
  end if;
  if v_type = 'product' then perform public.spec_validate_product_internal_v1(v_subject); end if;
  return null;
end $$;
drop trigger if exists product_spec_identity_constraint on public.products;
create constraint trigger product_spec_identity_constraint after insert or update on public.products
  deferrable initially deferred for each row execute function public.spec_product_constraint_internal_v1();
drop trigger if exists product_spec_fact_constraint on public.spec_facts;
create constraint trigger product_spec_fact_constraint after insert or update or delete on public.spec_facts
  deferrable initially deferred for each row execute function public.spec_product_constraint_internal_v1();
drop trigger if exists product_spec_value_constraint on public.spec_fact_values;
create constraint trigger product_spec_value_constraint after insert or update or delete on public.spec_fact_values
  deferrable initially deferred for each row execute function public.spec_product_constraint_internal_v1();

-- The legacy label-based RPC gets the same validation gate; invalid labels
-- cannot be silently lost in its join. Its signature and ACL are preserved.
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
begin
  if v_tenant is null then
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
  if exists(select 1 from public.products p join public.category_tech_mappings m on m.category_id=p.category_id and m.tenant_id=p.tenant_id and m.status='active' where p.id=p_product_id)
    and exists(select 1 from unnest(p_definition_ids) d where not exists(
      select 1 from public.products p join public.category_tech_mappings m on m.category_id=p.category_id and m.tenant_id=p.tenant_id and m.status='active'
      join public.spec_template_fields tf on tf.template_id=m.template_id
      where p.id=p_product_id and tf.spec_definition_id=d)) then
    raise exception 'La respuesta no pertenece a esta plantilla' using errcode = '23514';
  end if;
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
$function$
;

-- Presentation roles describe the operator decision, not a compatibility claim.
-- Legacy option_rules remain suggestions. Reviewed constraint_rules are the only
-- option prohibitions; no width->speed heuristic is added.
insert into public.spec_definitions(key,label,data_type,allowed_values,validation_rules,sort_order,description,is_customer_visible)
select 'spec_evidence_source','Fuente de la declaración','text','[]'::jsonb,'{}'::jsonb,900,
  'URL del fabricante, manual o identificación del envase que respalda la declaración.',false
where not exists(select 1 from public.spec_definitions where key = 'spec_evidence_source');
update public.spec_definitions set is_customer_visible=false where key='spec_evidence_source';
insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order,is_required,visibility_rules,option_rules)
select t.id,d.id,'declaration',5,false,'[]'::jsonb,'[]'::jsonb
from public.spec_templates t cross join public.spec_definitions d
where t.is_active and d.key = 'spec_evidence_source'
  and not exists(select 1 from public.spec_template_fields f where f.template_id = t.id and f.spec_definition_id = d.id);

update public.spec_template_fields f set sort_order=5 from public.spec_definitions d where d.id=f.spec_definition_id and d.key='spec_evidence_source';

update public.spec_templates t set contract_version = 2,
  form_contract = jsonb_build_object('version',1,'coverage','template',
    'roles',(select jsonb_object_agg(d.key,case
      when t.technical_family in ('chain','chain_link') and d.key in ('drivetrain_primary_ecosystem','chain_profile_family') then 'legacy'
      when t.technical_family in ('chain','chain_link') and d.key='drivetrain_platform' then 'declaration'
      when d.key in ('spec_evidence_source','drivetrain_declared_compatible_ecosystems','pad_compatibility_note','compatible_frame_hint') then 'declaration'
      when f.section_key = 'contents' then 'contents'
      when d.data_type in ('number','boolean') or d.key = 'chain_width_family' then 'measurement'
      else 'primary' end) from public.spec_template_fields f join public.spec_definitions d on d.id = f.spec_definition_id where f.template_id = t.id),
    'prerequisites','{}'::jsonb,'helpers','{}'::jsonb,'labels','{}'::jsonb)
where t.is_active;

update public.spec_templates set form_contract = form_contract ||
  jsonb_build_object('prerequisites',jsonb_build_object('chain_speeds',jsonb_build_array('drivetrain_mode'),
    'drivetrain_platform',jsonb_build_array('chain_speeds','spec_evidence_source'),
    'drivetrain_declared_compatible_ecosystems',jsonb_build_array('chain_speeds','spec_evidence_source')),
    'helpers',jsonb_build_object(
      'drivetrain_mode','Tipo de transmisión para el que se declara esta cadena o conector.',
      'chain_speeds','Velocidades declaradas para este modelo. No se deducen del ancho ni confirman por sí solas un montaje.',
      'chain_width_family','Denominación nominal del fabricante. No es una medición del ancho exterior.',
      'chain_outer_width_mm','Ancho sobre el pasador. Conserva la medida real; no determina por sí sola las velocidades compatibles.',
      'drivetrain_platform','Sistema indicado por el fabricante para este modelo. Conserva su fuente y alcance.',
      'drivetrain_declared_compatible_ecosystems','Declaraciones del fabricante; no crean combinaciones entre componentes.'),
    'labels',jsonb_build_object('chain_speeds','Velocidades declaradas del modelo',
      'chain_outer_width_mm','Ancho sobre el pasador','chain_width_family','Denominación de ancho',
      'drivetrain_platform','Sistema declarado'))
where is_active and technical_family in ('chain','chain_link');

-- No blanket mode/width/speed prohibition: a product can serve more than one
-- application. Exact reference constraints and scoped declarations own this.
-- Exact manufacturer editions: stable normalized option UUIDs are resolved at
-- migration time. A missing/ambiguous catalogue definition aborts the migration.
do $seed$
declare v_reference jsonb; v_entry record; v_definition public.spec_definitions%rowtype;
  v_payload jsonb; v_item jsonb; v_ids jsonb;
begin
  for v_reference in select value from jsonb_array_elements($references$[{"id": "kmc-x8-bx08ng114-eu-20260905", "technical_family": "chain", "brand": "KMC", "model": "X8", "manufacturer_sku": "BX08NG114", "label": "KMC X8 Silver/Grey · BX08NG114 · 114 eslabones", "facts": {"chain_speeds": ["6", "7", "8"], "chain_width_family": "3/32", "chain_outer_width_mm": 7.3, "link_count": 114, "quick_link_included": true, "drivetrain_mode": "Derailleur", "spec_evidence_source": "https://www.kmcchain.eu/products/x8-silver-grey"}, "sources": ["https://www.kmcchain.eu/products/x8-silver-grey"], "claims": [{"rear_speeds": [6, 7, 8], "note": "Declaración del fabricante para todos los sistemas de 6, 7 y 8 velocidades. No implica compatibilidad entre mandos y desviadores de distintas marcas.", "platform": "Todos los sistemas de 6/7/8 velocidades"}]}, {"id": "kmc-eglide-us-20260905", "technical_family": "chain", "brand": "KMC", "model": "eGlide", "label": "KMC eGlide Silver · CN11245 · 126 eslabones", "facts": {"chain_speeds": ["9", "10", "11"], "chain_width_family": "11/128", "chain_outer_width_mm": 5.4, "link_count": 126, "drivetrain_mode": "Derailleur", "spec_evidence_source": "https://kmcchain.us/products/eglide"}, "sources": ["https://kmcchain.us/products/eglide"], "claims": [{"platform": "Shimano LINKGLIDE", "rear_speeds": [9, 10, 11], "exclusive": true, "note": "Sólo sistemas LINKGLIDE de 9, 10 u 11 velocidades. La cobertura no se extiende a otras transmisiones de esas velocidades."}], "manufacturer_sku": "CN11245"}, {"id": "kmc-x11-us-118-20260905", "technical_family": "chain", "brand": "KMC", "model": "X11", "label": "KMC X11 Nickel/Black · CN11665 · 118 eslabones", "facts": {"chain_speeds": ["11"], "chain_width_family": "11/128", "link_count": 118, "drivetrain_mode": "Derailleur", "spec_evidence_source": "https://kmcchain.us/products/x11"}, "sources": ["https://kmcchain.us/products/x11"], "claims": [{"systems": ["Shimano", "SRAM", "Campagnolo"], "rear_speeds": [11], "note": "Declaración del fabricante para transmisiones de 11 velocidades; confirmar el resto de componentes del montaje."}], "manufacturer_sku": "CN11665"}]$references$::jsonb) loop
    v_payload := '{}'::jsonb;
    for v_entry in select * from jsonb_each(v_reference->'facts') loop
      select * into strict v_definition from public.spec_definitions where key = v_entry.key;
      if v_definition.data_type in ('single_select','multi_select') then
        select jsonb_agg(v.id order by a.ordinality) into v_ids
        from jsonb_array_elements_text(case when jsonb_typeof(v_entry.value) = 'array' then v_entry.value
          else jsonb_build_array(v_entry.value) end) with ordinality a(label,ordinality)
        join public.spec_definition_values v on v.spec_definition_id = v_definition.id and v.label = a.label;
        if coalesce(jsonb_array_length(v_ids),0) <> (case when jsonb_typeof(v_entry.value) = 'array'
          then jsonb_array_length(v_entry.value) else 1 end) then
          raise exception 'Reference seed cannot resolve %',v_entry.key;
        end if;
        v_item := jsonb_build_object('value_ids',v_ids);
      elsif v_definition.data_type = 'number' then v_item := jsonb_build_object('number',v_entry.value);
      elsif v_definition.data_type = 'boolean' then v_item := jsonb_build_object('boolean',v_entry.value);
      else v_item := jsonb_build_object('text',v_entry.value); end if;
      v_payload := v_payload || jsonb_build_object(v_definition.id::text,v_item);
    end loop;
    insert into public.product_spec_references(id,technical_family,brand,model,manufacturer_sku,label,fact_values,sources,claims,reviewed_on)
      values(v_reference->>'id',v_reference->>'technical_family',v_reference->>'brand',v_reference->>'model',
        v_reference->>'manufacturer_sku',v_reference->>'label',v_payload,v_reference->'sources',v_reference->'claims','2026-09-05')
      on conflict(id) do nothing;
  end loop;
end $seed$;

create or replace function public.spec_reference_immutable_internal_v1()
returns trigger language plpgsql set search_path = pg_catalog, public, pg_temp as $$
begin
  if tg_op = 'DELETE' or new is distinct from old then
    raise exception 'Una referencia publicada es inmutable; crea otra versión.' using errcode = '23514';
  end if;
  return new;
end $$;
drop trigger if exists product_spec_reference_immutable on public.product_spec_references;
create trigger product_spec_reference_immutable before update or delete on public.product_spec_references
  for each row execute function public.spec_reference_immutable_internal_v1();

-- Only the three public RPCs are client-callable. Helpers and trigger functions
-- cannot be used to bypass the atomic writer or inspect another tenant's facts.
-- Future metadata edits invalidate editors, including option label/rule edits.
create or replace function public.spec_contract_revision_internal_v1()
returns trigger language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $$
begin
  if tg_table_name='spec_templates' then
    if (new.form_contract,new.is_active,new.technical_family) is distinct from (old.form_contract,old.is_active,old.technical_family) then
      new.contract_version := greatest(new.contract_version,old.contract_version+1);
    elsif new.contract_version < old.contract_version then new.contract_version := old.contract_version;
    end if;
    return new;
  elsif tg_table_name='spec_template_fields' then
    update public.spec_templates set contract_version=contract_version+1 where id=case when tg_op='DELETE' then old.template_id else new.template_id end;
  elsif tg_table_name='spec_definitions' then
    update public.spec_templates set contract_version=contract_version+1 where id in
      (select template_id from public.spec_template_fields where spec_definition_id=new.id);
  else
    update public.spec_templates set contract_version=contract_version+1 where id in
      (select template_id from public.spec_template_fields where spec_definition_id=case when tg_op='DELETE' then old.spec_definition_id else new.spec_definition_id end);
  end if;
  return null;
end $$;
create trigger product_spec_template_revision before update on public.spec_templates
  for each row execute function public.spec_contract_revision_internal_v1();
create trigger product_spec_field_revision after insert or update or delete on public.spec_template_fields
  for each row execute function public.spec_contract_revision_internal_v1();
create trigger product_spec_definition_revision after update of validation_rules,data_type,allowed_values,label on public.spec_definitions
  for each row execute function public.spec_contract_revision_internal_v1();
create trigger product_spec_option_revision after insert or update or delete on public.spec_definition_values
  for each row execute function public.spec_contract_revision_internal_v1();
revoke all on function public.spec_contract_revision_internal_v1() from public,anon,authenticated;

do $acl$
declare v_function record;
begin
  for v_function in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'spec_rule_normalize_internal_v1','spec_rule_known_internal_v1','spec_rule_set_internal_v1',
      'spec_condition_internal_v1','spec_payload_display_internal_v1','spec_product_payload_internal_v1',
      'spec_validate_draft_internal_v1','spec_write_payload_internal_v2','spec_validate_product_internal_v1',
      'spec_product_revision_internal_v1','spec_product_constraint_internal_v1','spec_reference_immutable_internal_v1',
      'get_product_spec_references_v1','get_product_spec_snapshot_v1','get_product_spec_contexts_v1','save_product_with_specs_v1')
  loop
    execute format('revoke all on function %s from public,anon,authenticated',v_function.signature);
  end loop;
end $acl$;
grant execute on function public.get_product_spec_references_v1(text) to authenticated;
grant execute on function public.get_product_spec_snapshot_v1(uuid) to authenticated;
grant execute on function public.get_product_spec_contexts_v1(uuid[]) to authenticated;
grant execute on function public.save_product_with_specs_v1(jsonb,boolean,uuid,integer,jsonb,bigint,text,text,timestamptz,jsonb) to authenticated;
notify pgrst, 'reload schema';

commit;
