-- Chain/connector anatomy and reviewed OEM editions. Forward-only, no product backfill.
begin;
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
end $$;



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

-- No products/facts are rewritten. Metadata revision triggers invalidate older editors.
-- Discard the historical mode -> speed heuristic. A chain may have several
-- applications; an IGH gear count does not define a chain's declared class.
update public.spec_template_fields f set constraint_rules='[]'::jsonb
from public.spec_templates t, public.spec_definitions d
where f.template_id=t.id and d.id=f.spec_definition_id
 and t.technical_family in ('chain','chain_link') and d.key='chain_speeds'
 and f.constraint_rules <> '[]'::jsonb;

insert into public.spec_definitions(key,label,data_type,allowed_values,validation_rules,sort_order,description,is_customer_visible)
values
 ('chain_connector_target','Cadenas admitidas por el fabricante','text','[]','{}',90,'Modelos, series y excepciones de la cadena objetivo; no la marca de la bicicleta.',true),
 ('chain_connector_directional','Conector con sentido de montaje','boolean','[]','{}',100,'Declara el sentido del conector, que puede diferir del de la cadena.',true)
on conflict(key) where tenant_id is null do nothing;

insert into public.spec_template_fields(template_id,spec_definition_id,section_key,sort_order,is_required,visibility_rules,option_rules)
select t.id,d.id,'declaration',d.sort_order,false,'[]','[]'
from public.spec_templates t cross join public.spec_definitions d
where t.is_active and t.technical_family='chain_link'
 and d.tenant_id is null and d.key in ('chain_connector_target','chain_connector_directional')
on conflict(template_id,spec_definition_id) do nothing;

-- Dedicated connector anatomy; keep the old labels/IDs stable.
update public.spec_definitions set allowed_values=allowed_values || '["Eslabón con clip"]'::jsonb
where key='chain_connector_type' and tenant_id is null and not allowed_values ? 'Eslabón con clip';
insert into public.spec_definition_values(spec_definition_id,code,label,sort_order)
select id,'clip','Eslabón con clip',50 from public.spec_definitions d
where key='chain_connector_type' and tenant_id is null
 and not exists(select 1 from public.spec_definition_values v
   where v.spec_definition_id=d.id and v.label='Eslabón con clip')
on conflict(spec_definition_id,code) do nothing;

-- Glossary bands are examples, not universal physical limits.
update public.spec_definitions set validation_rules=(validation_rules-'min'-'max') || '{"positive":true}'::jsonb
where key='chain_outer_width_mm' and tenant_id is null;
update public.spec_definitions set validation_rules=(validation_rules-'min'-'max') || '{"positive":true,"integer":true}'::jsonb
where key in ('link_count','chain_link_pack_qty') and tenant_id is null;

update public.spec_templates set form_contract = form_contract ||
 jsonb_build_object(
 'roles', form_contract->'roles' || '{"chain_connector_type":"primary","spec_evidence_source":"primary","chain_speeds":"primary","drivetrain_mode":"legacy","drivetrain_declared_compatible_ecosystems":"legacy","chain_connector_target":"declaration","chain_link_reusable":"declaration","chain_connector_directional":"declaration","chain_link_pack_qty":"contents"}'::jsonb,
 'prerequisites','{"chain_speeds":["chain_connector_type"],"chain_connector_target":["chain_connector_type","spec_evidence_source"],"chain_link_reusable":["chain_connector_type","spec_evidence_source"],"chain_connector_directional":["chain_connector_type","spec_evidence_source"]}'::jsonb,
 'labels', form_contract->'labels' || '{"chain_connector_type":"Tipo de conector","chain_speeds":"Clase de cadena declarada","chain_link_pack_qty":"Conectores completos por envase","chain_outer_width_mm":"Ancho del conector montado sobre el pasador","chain_link_reusable":"Reutilizable según el fabricante"}'::jsonb,
 'helpers', form_contract->'helpers' || '{"chain_connector_type":"Missing link: cierre rápido de dos placas. Pin: pasador de unión. Half link: medio eslabón. El clip es otro tipo de cierre.","chain_speeds":"Clase indicada para las cadenas que admite este conector. No es el número de piñones de la bicicleta y no confirma por sí sola compatibilidad.","chain_connector_target":"Copia los modelos o series admitidos y sus excepciones. Dos cadenas de la misma marca o velocidad pueden necesitar conectores distintos.","chain_link_reusable":"Registra lo indicado para este modelo. Sin dato no autoriza reutilizarlo; un pasador de unión nuevo se utiliza una sola vez.","chain_connector_directional":"Confirma las flechas o instrucciones del conector, independientemente del sentido de la cadena.","chain_link_pack_qty":"Cuenta cierres completos: dos mitades de un eslabón rápido forman un conector, no dos.","chain_outer_width_mm":"Medida exterior del cierre ya montado. No es la longitud de la punta guía de un pasador de unión.","spec_evidence_source":"URL o identificación del envase/manual de este modelo. Se necesita antes de declarar sus cadenas admitidas, reutilización o sentido."}'::jsonb)
where is_active and technical_family='chain_link';

update public.spec_template_fields f set sort_order = case d.key
 when 'chain_connector_type' then 0 when 'chain_speeds' then 10
 when 'spec_evidence_source' then 20 else f.sort_order end
from public.spec_templates t, public.spec_definitions d
where f.template_id=t.id and d.id=f.spec_definition_id and t.technical_family='chain_link';

-- The mounted connector width is not the length of a replacement rivet's pilot.
update public.spec_template_fields f set visibility_rules='[{"field":"chain_connector_type","operator":"neq","value":"Pin"}]'::jsonb
from public.spec_templates t, public.spec_definitions d
where f.template_id=t.id and d.id=f.spec_definition_id and t.technical_family='chain_link'
 and d.key='chain_outer_width_mm';

update public.spec_template_fields f set constraint_rules=
 '[{"field":"chain_connector_type","value":"Pin","allow":[false],"sources":["https://www.parktool.com/en-us/blog/repair-help/chain-replacement-derailleur-bikes","https://www.sheldonbrown.com/chains.html"],"scope":"replacement connecting rivet, not a reusable master link"}]'::jsonb
from public.spec_templates t, public.spec_definitions d
where f.template_id=t.id and d.id=f.spec_definition_id and t.technical_family='chain_link'
 and d.key='chain_link_reusable';

-- Narrow scope: modern derailleur chains whose declared coverage includes 5+.
-- Missing mode or speed remains unknown; no speed coverage is inferred.
update public.spec_template_fields f set constraint_rules=
 '[{"all":[{"field":"drivetrain_mode","value":"Derailleur"},{"field":"chain_speeds","operator":"contains_any","value":["5","6","7","8","9","10","11","12","13"]}],"allow":["3/32","11/128","Otro","Desconocido / sin confirmar"],"sources":["https://www.kmcchain.eu/service/glossary","https://www.sheldonbrown.com/gloss_ch.html"],"scope":"1/8 wide chains excluded for declared modern derailleur use, not historical 2-3 cogs"}]'::jsonb
from public.spec_templates t, public.spec_definitions d
where f.template_id=t.id and d.id=f.spec_definition_id and t.technical_family='chain'
 and d.key='chain_width_family';

update public.spec_templates set form_contract=jsonb_set(form_contract,'{helpers,chain_width_family}',
 to_jsonb('Denominación nominal del fabricante. Una cadena 1/8 no corresponde a la cobertura declarada para desviador de 5 o más piñones. Las otras denominaciones no fijan por sí solas las velocidades.'::text))
where is_active and technical_family='chain';

do $seed$
declare v_reference jsonb; v_entry record; v_definition public.spec_definitions%rowtype;
  v_payload jsonb; v_item jsonb; v_ids jsonb;
begin
  for v_reference in select value from jsonb_array_elements($references$[{"id":"kmc-cl573r-global-20260906","technical_family":"chain_link","brand":"KMC","model":"CL573R","label":"KMC CL573R · datos del modelo; presentación por confirmar","facts":{"chain_connector_type":"Missing link","chain_speeds":["6","7","8"],"chain_link_reusable":true,"chain_connector_directional":false,"chain_connector_target":"KMC X8, KMC Z8.3, KMC Z7, KMC Z6","spec_evidence_source":"https://www.kmcchain.com/en/product/connector-missing-link-cl573r-8s-7s-6s-speed"},"sources":["https://www.kmcchain.com/en/product/connector-missing-link-cl573r-8s-7s-6s-speed"],"claims":[{"interface":"connector_chain","targets":["KMC X8","KMC Z8.3","KMC Z7","KMC Z6"],"chain_speeds":[6,7,8],"excludes":[],"note":"Alcance declarado para estas cadenas. Confirma el modelo instalado y las instrucciones de montaje. La cantidad del envase se registra por separado."}]},{"id":"kmc-cl571r-global-20260906","technical_family":"chain_link","brand":"KMC","model":"CL571R","label":"KMC CL571R · datos del modelo; presentación por confirmar","facts":{"chain_connector_type":"Missing link","chain_speeds":["8"],"chain_link_reusable":true,"chain_connector_directional":false,"chain_connector_target":"KMC Z8.1","spec_evidence_source":"https://www.kmcchain.com/en/product/connector-missing-link-cl571r-8s-single-speed"},"sources":["https://www.kmcchain.com/en/product/connector-missing-link-cl571r-8s-single-speed"],"claims":[{"interface":"connector_chain","targets":["KMC Z8.1"],"chain_speeds":[8],"excludes":[],"note":"Alcance declarado para estas cadenas. Confirma el modelo instalado y las instrucciones de montaje. La cantidad del envase se registra por separado."}]},{"id":"kmc-cl566r-global-20260906","technical_family":"chain_link","brand":"KMC","model":"CL566R","label":"KMC CL566R · datos del modelo; presentación por confirmar","facts":{"chain_connector_type":"Missing link","chain_speeds":["9"],"chain_link_reusable":true,"chain_connector_directional":false,"chain_connector_target":"KMC 9 velocidades, Shimano 9 velocidades, SRAM 9 velocidades","spec_evidence_source":"https://www.kmcchain.com/en/product/connector-missing-link-cl566r-9-speed"},"sources":["https://www.kmcchain.com/en/product/connector-missing-link-cl566r-9-speed"],"claims":[{"interface":"connector_chain","targets":["KMC 9 velocidades","Shimano 9 velocidades","SRAM 9 velocidades"],"chain_speeds":[9],"excludes":[],"note":"Alcance declarado para estas cadenas. Confirma el modelo instalado y las instrucciones de montaje. La cantidad del envase se registra por separado."}]},{"id":"kmc-cl559r-global-20260906","technical_family":"chain_link","brand":"KMC","model":"CL559R","label":"KMC CL559R · datos del modelo; presentación por confirmar","facts":{"chain_connector_type":"Missing link","chain_speeds":["10"],"chain_link_reusable":true,"chain_connector_directional":false,"chain_connector_target":"KMC 10 velocidades, Shimano 10 velocidades","spec_evidence_source":"https://www.kmcchain.com/en/product/connector-missing-link-cl559r-10-speed"},"sources":["https://www.kmcchain.com/en/product/connector-missing-link-cl559r-10-speed"],"claims":[{"interface":"connector_chain","targets":["KMC 10 velocidades","Shimano 10 velocidades"],"chain_speeds":[10],"excludes":[],"note":"Alcance declarado para estas cadenas. Confirma el modelo instalado y las instrucciones de montaje. La cantidad del envase se registra por separado."}]},{"id":"kmc-cl555r-global-20260906","technical_family":"chain_link","brand":"KMC","model":"CL555R","label":"KMC CL555R · datos del modelo; presentación por confirmar","facts":{"chain_connector_type":"Missing link","chain_speeds":["11"],"chain_link_reusable":true,"chain_connector_directional":false,"chain_connector_target":"KMC 11 velocidades, Shimano 11 velocidades, SRAM 11 velocidades","spec_evidence_source":"https://www.kmcchain.com/en/product/connector-missing-link-cl555r-11-speed"},"sources":["https://www.kmcchain.com/en/product/connector-missing-link-cl555r-11-speed"],"claims":[{"interface":"connector_chain","targets":["KMC 11 velocidades","Shimano 11 velocidades","SRAM 11 velocidades"],"chain_speeds":[11],"excludes":[],"note":"Alcance declarado para estas cadenas. Confirma el modelo instalado y las instrucciones de montaje. La cantidad del envase se registra por separado."}]},{"id":"kmc-cl552-global-20260906","technical_family":"chain_link","brand":"KMC","model":"CL552","label":"KMC CL552 · datos del modelo; presentación por confirmar","facts":{"chain_connector_type":"Missing link","chain_speeds":["12"],"chain_link_reusable":false,"chain_connector_directional":false,"chain_connector_target":"KMC 12 velocidades, Shimano 12 velocidades, SRAM MTB 12 velocidades, Campagnolo 12 velocidades; excluye cualquier Flattop","spec_evidence_source":"https://www.kmcchain.com/en/product/connector-missing-link-cl552-12-speed"},"sources":["https://www.kmcchain.com/en/product/connector-missing-link-cl552-12-speed"],"claims":[{"interface":"connector_chain","targets":["KMC 12 velocidades","Shimano 12 velocidades","SRAM MTB 12 velocidades","Campagnolo 12 velocidades"],"chain_speeds":[12],"excludes":["Cualquier cadena Flattop"],"note":"Alcance declarado para estas cadenas. Confirma el modelo instalado y las instrucciones de montaje. La cantidad del envase se registra por separado."}]},{"id":"kmc-z83-bz08ng114-eu-20260906","technical_family":"chain","brand":"KMC","model":"Z8.3","manufacturer_sku":"BZ08NG114","label":"KMC Z8.3 Silver/Grey · BZ08NG114 · 114 eslabones","facts":{"chain_speeds":["6","7","8"],"drivetrain_mode":"Derailleur","link_count":114,"quick_link_included":true,"spec_evidence_source":"https://www.datocms-assets.com/104526/1781274377-kmc-2026-dealer-catalogue-en-260612.pdf"},"sources":["https://www.datocms-assets.com/104526/1781274377-kmc-2026-dealer-catalogue-en-260612.pdf"],"claims":[{"rear_speeds":[6,7,8],"note":"Catálogo Europa 2026, revisión junio, página 59. Esta referencia corresponde a la cadena de 114 eslabones; el DISPLAY de 116 tiene otro código.","coverage":"Todos los sistemas"}]},{"id":"kmc-z7-bz07gb114-eu-20260906","technical_family":"chain","brand":"KMC","model":"Z7","manufacturer_sku":"BZ07GB114","label":"KMC Z7 Grey/Brown · BZ07GB114 · 114 eslabones","facts":{"chain_speeds":["6","7"],"chain_width_family":"3/32","chain_outer_width_mm":7.3,"drivetrain_mode":"Derailleur","link_count":114,"quick_link_included":true,"spec_evidence_source":"https://www.kmcchain.eu/products/z7-grey-brown"},"sources":["https://www.kmcchain.eu/products/z7-grey-brown","https://www.datocms-assets.com/104526/1781274377-kmc-2026-dealer-catalogue-en-260612.pdf"],"claims":[{"rear_speeds":[6,7],"note":"La edición declara 6/7. No se agrega cobertura de 8 velocidades por compartir ancho con otras cadenas.","coverage":"Todos los sistemas"}]}]$references$::jsonb) loop
    v_payload := '{}'::jsonb;
    for v_entry in select * from jsonb_each(v_reference->'facts') loop
      select * into strict v_definition from public.spec_definitions where key = v_entry.key and tenant_id is null;
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
        v_reference->>'manufacturer_sku',v_reference->>'label',v_payload,v_reference->'sources',v_reference->'claims','2026-09-06')
      on conflict(id) do nothing;
  end loop;
end $seed$;
notify pgrst, 'reload schema';
commit;
