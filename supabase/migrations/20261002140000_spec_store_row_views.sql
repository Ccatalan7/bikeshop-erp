-- Las tablas de la ficha se leen como el cliente las pide (2026-10-01).
--
-- La ficha guarda en tablas (`rows_schema`) lo que el fabricante documenta
-- fila por fila: los dientes de cada piñón, la presión máxima del neumático,
-- el aro y el neumático más ancho de una horquilla, los platos de una biela,
-- las cadenas que admite un eslabón. Eran invisibles para la tienda: la única
-- forma de mostrarlas era la del editor, todas las columnas con su rótulo de
-- operador, el documento y la URL de la fuente («Identificación de esta
-- declaración: …; Documento o envase identificado: …»). Por eso 17 tablas con
-- datos en productos publicados quedaron ocultas, y una horquilla publicada no
-- decía para qué aro es.
--
-- `spec_definitions.store_view` dice qué lee el cliente de cada fila:
--   format    plantilla con {columna}; una lista prueba en orden y usa la
--             primera con todas sus columnas. Una fila sin ninguna no se muestra.
--   only      {columna: [valores]}: sólo filas así («Compatible declarado»,
--             «Admitido por la fuente», una operación admitida).
--   sort_by / sort_desc  orden numérico por una columna.
--   join / suffix / distinct  cómo se unen las filas.
--   replace   [[patrón, reemplazo]] por fila, para palabras de proveedor.
-- Los números van con coma decimal; la unidad la escribe la plantilla.
-- Sin `store_view` una tabla visible se sigue mostrando entera (las cámaras).
-- Una tabla cuya vista no deja nada no aparece en la ficha.
--
-- Y lo deducido se muestra. Desde 20260915034000 la tienda escondía un dato de
-- origen `inferred` mientras nadie lo confirmara; nadie confirma (`confirmed`
-- es falso en todos los hechos), así que 229 datos de 133 cámaras publicadas
-- (butilo, sin líquido: lo que es una cámara cuando el nombre no dice otra
-- cosa) nunca salían. El dueño: «nadie pidió eso de que los datos tuvieran que
-- sí o sí ser respaldados con fuente documentada». El origen queda en el editor.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

alter table public.spec_definitions add column if not exists store_view jsonb;

-- Una vista se juzga entera al guardarla: la ficha pública la lee para cada
-- producto, y una vista que fallara al leerse apagaría la ficha completa de
-- todos sus productos, no sólo esa tabla. Nulo: la vista sirve; si no, qué
-- tiene mal.
create or replace function public.spec_store_view_problem_internal_v1(p_view jsonb, p_schema jsonb)
returns text language plpgsql immutable set search_path = pg_catalog, public, pg_temp as $check$
declare
  v_columns text[] := array(
    select c->>'key' from jsonb_array_elements(case when jsonb_typeof(p_schema->'columns') = 'array'
      then p_schema->'columns' else '[]'::jsonb end) c);
  v_formats jsonb;
  v_format jsonb;
  v_key text;
  v_entry record;
  v_rule jsonb;
begin
  if jsonb_typeof(p_view) is distinct from 'object' then
    return 'la vista es un objeto';
  end if;
  select string_agg(k, ', ') into v_key from jsonb_object_keys(p_view) k
  where k not in ('format', 'only', 'sort_by', 'sort_desc', 'join', 'suffix', 'distinct', 'replace');
  if v_key is not null then
    return 'clave desconocida: ' || v_key;
  end if;
  v_formats := case jsonb_typeof(p_view->'format')
    when 'string' then jsonb_build_array(p_view->'format') when 'array' then p_view->'format' end;
  if v_formats is null or jsonb_array_length(v_formats) = 0 then
    return 'falta format';
  end if;
  for v_format in select jsonb_array_elements(v_formats) loop
    if jsonb_typeof(v_format) <> 'string' or btrim(v_format #>> '{}') = '' then
      return 'cada format es un texto';
    end if;
    for v_key in select m[1] from regexp_matches(v_format #>> '{}', '\{([a-z0-9_]+)\}', 'g') m loop
      if not v_key = any(v_columns) then
        return 'format nombra una columna que la tabla no tiene: ' || v_key;
      end if;
    end loop;
  end loop;
  if p_view ? 'only' then
    if jsonb_typeof(p_view->'only') <> 'object' then
      return 'only es un objeto';
    end if;
    for v_entry in select o.k, o.allowed from jsonb_each(p_view->'only') o(k, allowed) loop
      if not v_entry.k = any(v_columns) then
        return 'only nombra una columna que la tabla no tiene: ' || v_entry.k;
      end if;
      if jsonb_typeof(v_entry.allowed) <> 'array' or jsonb_array_length(v_entry.allowed) = 0
         or exists (select 1 from jsonb_array_elements(v_entry.allowed) a where jsonb_typeof(a) <> 'string') then
        return 'only lleva una lista de textos por columna';
      end if;
    end loop;
  end if;
  if p_view ? 'sort_by' and (jsonb_typeof(p_view->'sort_by') <> 'string' or not (p_view->>'sort_by') = any(v_columns)) then
    return 'sort_by nombra una columna de la tabla';
  end if;
  if exists (select 1 from unnest(array['sort_desc', 'distinct']) k where p_view ? k and jsonb_typeof(p_view->k) <> 'boolean') then
    return 'sort_desc y distinct son sí o no';
  end if;
  if exists (select 1 from unnest(array['join', 'suffix']) k where p_view ? k and jsonb_typeof(p_view->k) <> 'string') then
    return 'join y suffix son textos';
  end if;
  if p_view ? 'replace' then
    if jsonb_typeof(p_view->'replace') <> 'array' then
      return 'replace es una lista';
    end if;
    for v_rule in select jsonb_array_elements(p_view->'replace') loop
      if jsonb_typeof(v_rule) <> 'array' or jsonb_array_length(v_rule) <> 2
         or jsonb_typeof(v_rule->0) <> 'string' or jsonb_typeof(v_rule->1) <> 'string' then
        return 'cada replace es [patrón, reemplazo]';
      end if;
      begin
        perform regexp_replace('', v_rule->>0, v_rule->>1, 'g');
      exception when invalid_regular_expression then
        return 'patrón inválido en replace: ' || (v_rule->>0);
      end;
    end loop;
  end if;
  return null;
end
$check$;
revoke all on function public.spec_store_view_problem_internal_v1(jsonb, jsonb) from public, anon, authenticated;

alter table public.spec_definitions drop constraint if exists spec_definitions_store_view_check;
alter table public.spec_definitions add constraint spec_definitions_store_view_check check (
  store_view is null or (
    validation_rules ? 'rows_schema'
    and public.spec_store_view_problem_internal_v1(store_view, validation_rules->'rows_schema') is null
  ));
comment on column public.spec_definitions.store_view is
  'Qué lee el cliente de cada fila de una tabla de la ficha (format, only, sort_by, sort_desc, join, suffix, distinct, replace). Nulo: la tabla entera. spec_store_view_problem_internal_v1 dice por qué se rechaza una.';

create or replace function public.spec_rows_store_display_internal_v1(p_view jsonb, p_schema jsonb, p_value jsonb)
returns text language plpgsql immutable set search_path = pg_catalog, public, pg_temp as $view$
declare
  v_formats jsonb := case jsonb_typeof(p_view->'format')
    when 'array' then p_view->'format'
    when 'string' then jsonb_build_array(p_view->'format')
    else '[]'::jsonb end;
  v_sort text := nullif(p_view->>'sort_by', '');
  v_sign numeric := case when coalesce((p_view->>'sort_desc')::boolean, false) then -1 else 1 end;
  v_distinct boolean := coalesce((p_view->>'distinct')::boolean, true);
  v_row jsonb; v_format text; v_piece text; v_key text; v_cell text; v_type text; v_rule jsonb;
  v_parts text[] := '{}';
  v_text text;
begin
  if p_view is null or jsonb_typeof(p_value->'rows') is distinct from 'array' then
    return null;
  end if;
  for v_row in
    select r from jsonb_array_elements(p_value->'rows') with ordinality x(r, n)
    order by case when v_sort is not null and (r->'values'->>v_sort) ~ '^-?[0-9]+(\.[0-9]+)?$'
      then (r->'values'->>v_sort)::numeric * v_sign end nulls last, n
  loop
    if jsonb_typeof(p_view->'only') = 'object' and exists (
      select 1 from jsonb_each(p_view->'only') o(k, allowed)
      where not coalesce((v_row->'values'->>o.k) in (select jsonb_array_elements_text(o.allowed)), false)
    ) then
      continue;
    end if;
    v_piece := null;
    for v_format in select jsonb_array_elements_text(v_formats) loop
      v_piece := v_format;
      for v_key in select distinct m[1] from regexp_matches(v_format, '\{([a-z0-9_]+)\}', 'g') m loop
        v_cell := nullif(btrim(v_row->'values'->>v_key), '');
        if v_cell is null then
          v_piece := null;
          exit;
        end if;
        select c->>'type' into v_type from jsonb_array_elements(p_schema->'columns') c where c->>'key' = v_key limit 1;
        if v_type in ('integer', 'decimal', 'number') and v_cell ~ '^-?[0-9]+(\.[0-9]+)?$' then
          v_cell := replace(trim_scale(v_cell::numeric)::text, '.', ',');
        end if;
        v_piece := replace(v_piece, '{' || v_key || '}', v_cell);
      end loop;
      exit when v_piece is not null;
    end loop;
    continue when v_piece is null;
    for v_rule in select jsonb_array_elements(coalesce(p_view->'replace', '[]'::jsonb)) loop
      v_piece := regexp_replace(v_piece, v_rule->>0, v_rule->>1, 'g');
    end loop;
    v_piece := nullif(btrim(v_piece), '');
    continue when v_piece is null or (v_distinct and v_piece = any(v_parts));
    v_parts := v_parts || v_piece;
  end loop;
  if cardinality(v_parts) = 0 then
    return null;
  end if;
  v_text := array_to_string(v_parts, coalesce(p_view->>'join', ', ')) || coalesce(p_view->>'suffix', '');
  return upper(left(v_text, 1)) || substr(v_text, 2);
end
$view$;
revoke all on function public.spec_rows_store_display_internal_v1(jsonb, jsonb, jsonb) from public, anon, authenticated;

create temporary table _store_views(key text primary key, label text not null, hint text, view jsonb not null) on commit drop;
insert into _store_views(key, label, hint, view) values
  ('cog_sequence', 'Dientes de cada piñón', null,
   '{"format":"{teeth}","sort_by":"position","join":"-","suffix":" dientes","distinct":false}'),
  ('chainring_teeth_rows', 'Platos', null,
   '{"format":"{teeth}","sort_by":"teeth","sort_desc":true,"join":"-","suffix":" dientes","distinct":false}'),
  ('tire_general_max_pressures', 'Presión máxima',
   'La que indica el fabricante en el costado del neumático; no se debe superar.',
   '{"format":"{max_pressure_value} {pressure_unit}","only":{"pressure_unit":["psi","bar"]},"join":" o "}'),
  ('pump_pressure_specifications', 'Presión máxima', null,
   '{"format":"{value} {unit}","only":{"quantity_kind":["Máximo de bombeo declarado","Máximo de trabajo declarado"]},"join":" o "}'),
  -- La tienda escribe el aro como se pide («29" / 700c») desde el diámetro ISO.
  ('fork_tire_clearance_configurations', 'Aro',
   'Tamaño de rueda de la horquilla y el neumático más ancho que admite.',
   '{"format":["BSD: {bead_seat_diameter_mm} · máximo: {max_tire_width_mm}","BSD: {bead_seat_diameter_mm}"],"sort_by":"bead_seat_diameter_mm","sort_desc":true,"join":" | "}'),
  ('rear_derailleur_application_configurations', 'Velocidades', null,
   '{"format":"{rear_sprocket_count}","sort_by":"rear_sprocket_count","join":" o "}'),
  ('rear_derailleur_compatibility_claims', 'Cadena compatible', null,
   '{"format":"{declared_interface}","only":{"target_component":["Cadena"],"declaration_result":["Compatible declarado"]},"join":", ","replace":[["(\\d)-speed","\\1 velocidades"]]}'),
  ('shifter_compatibility_claims', 'Para cambio trasero', null,
   '{"format":"{declared_interface}","only":{"target_component":["Cambio trasero"],"declaration_result":["Compatible declarado"]},"join":", ","replace":[["(\\d)-speed","\\1 velocidades"]]}'),
  ('connector_target_declarations', 'Para cadenas', null,
   '{"format":"{target_system}","only":{"verdict":["Admitido por la fuente"]},"join":", ","replace":[["(\\d)-speed","\\1 velocidades"]]}'),
  ('chain_mass_declarations', 'Peso', null,
   '{"format":"{weight_g} g ({basis_links} eslabones)","join":"; "}'),
  ('front_derailleur_clamp_options', 'Abrazadera',
   'Diámetro del tubo del asiento donde se monta.',
   '{"format":["{direct_tube_diameter_mm} mm","{reduced_tube_diameter_mm} mm (con casquillo)"],"join":", "}'),
  ('front_derailleur_application_configurations', 'Para transmisión',
   'Platos adelante por piñones atrás: 3x7 son 3 platos y 7 piñones.',
   '{"format":"{front_chainring_count}x{rear_sprocket_count}","sort_by":"rear_sprocket_count","join":" o "}'),
  ('tool_capabilities', 'Sirve para', null,
   '{"format":"{target_standard}","only":{"supported":["true"]},"join":"; "}'),
  ('kit_members', 'Componentes', null,
   '{"format":["{member_role} {identity_model}","{member_role}"],"join":", "}'),
  ('brake_circuits', 'Freno', null,
   '{"format":["{position} · {actuation} · {fluid_as_shipped}","{position} · {actuation}"],"join":"; ","replace":[[" · Desconocido / sin confirmar$",""],["Aceite Mineral","aceite mineral"]]}'),
  ('shifter_units', 'Mandos', null,
   '{"format":"{unit_side}: {actuation_mode}","join":"; "}'),
  ('crank_axle_interface_declarations', 'Eje de motor',
   'El eje de motor (pedalier) tiene que ser de este tipo.',
   '{"format":"{interface_geometry}","only":{"junction_role":["Asiento que recibe el eje"]},"join":", "}');

update public.spec_definitions d
   set store_view = s.view, store_label = s.label, store_hint = s.hint,
       is_customer_visible = true, updated_at = now()
  from _store_views s
 where d.tenant_id is null and d.key = s.key and d.validation_rules ? 'rows_schema'
   and (d.store_view is distinct from s.view or d.store_label is distinct from s.label
        or d.store_hint is distinct from s.hint or not d.is_customer_visible);

-- Columnas de esas tablas que la tienda proyecta como filtro (el neumático más
-- ancho de una horquilla, el manubrio de un mando, la línea de cadena) se
-- nombran como el cliente, si nadie las nombró antes.
update public.spec_definitions d
   set store_label = w.label, updated_at = now()
  from (values ('max_tire_width_mm', 'Neumático más ancho'),
               ('handlebar_clamp_mm', 'Para manubrio de'),
               ('chainline_mm', 'Línea de cadena')) w(key, label)
 where d.tenant_id is null and d.key = w.key and nullif(btrim(d.store_label), '') is null;

-- Lo esencial junto al precio: el aro de una horquilla, las velocidades de un
-- cambio, la abrazadera y la transmisión de un desviador, los platos de una
-- biela y la presión de un bombín.
create temporary table _store_rank(template_key text, key text, rank smallint, primary key (template_key, key)) on commit drop;
insert into _store_rank values
  ('fork', 'fork_tire_clearance_configurations', 1), ('fork', 'fork_kind', 2), ('fork', 'travel_mm', 3),
  ('fork', 'axle_type', 4), ('fork', 'steerer_fit', 5), ('fork', 'lockout', 6),
  ('rear_derailleur', 'rear_derailleur_application_configurations', 1), ('rear_derailleur', 'derailleur_cage_length', 2),
  ('rear_derailleur', 'rear_derailleur_mount_type', 3), ('rear_derailleur', 'derailleur_clutch', 4),
  ('front_derailleur', 'front_derailleur_clamp_options', 1), ('front_derailleur', 'front_derailleur_application_configurations', 2),
  ('front_derailleur', 'front_derailleur_cable_pull', 3), ('front_derailleur', 'front_derailleur_swing', 4),
  ('front_derailleur', 'front_derailleur_mount_type', 5),
  ('crankset', 'crank_arm_length_mm', 1), ('crankset', 'chainring_teeth_rows', 2), ('crankset', 'crankset_construction', 3),
  ('crankset', 'chainring_mounting', 4), ('crankset', 'included_chainring_count', 5),
  ('pump', 'pump_kind', 1), ('pump', 'pump_pressure_specifications', 2), ('pump', 'gauge', 3), ('pump', 'valve_heads_supported', 4);

update public.spec_template_fields f
   set store_highlight = r.rank
  from _store_rank r, public.spec_templates t, public.spec_definitions d
 where t.id = f.template_id and t.tenant_id is null and t.key = r.template_key
   and d.id = f.spec_definition_id and d.key = r.key
   and f.store_highlight is distinct from r.rank;

-- La ficha pública: una tabla con vista se lee por su vista; la que no deja
-- nada no aparece. Misma forma de salida, así que basta reemplazarla.
CREATE OR REPLACE FUNCTION public.get_public_product_technical_specs(p_tenant_id uuid, p_product_id uuid)
 RETURNS TABLE(section_key text, section_sort_order integer, field_sort_order integer, spec_key text, spec_label text, display_value text, unit text, data_type text, spec_hint text, highlight_rank integer)
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
    select f.section_key,f.sort_order,d.id definition_id,d.key,
      coalesce(nullif(btrim(f.store_label),''),nullif(btrim(d.store_label),''),p.form_contract->'labels'->>d.key,d.label) label,
      nullif(btrim(d.store_hint),'') hint,f.store_highlight,d.store_view,
      d.unit,d.data_type,d.validation_rules,p.form_contract,p.vals,p.vals->d.key val,min(f.sort_order) over(partition by f.section_key) section_order
    from assessed p join public.spec_template_fields f on f.template_id=p.template_id
    join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
    where coalesce(p.form_contract->'roles'->>d.key,'primary') <> 'legacy'
      and public.spec_rule_known_internal_v1(p.vals->d.key)
      -- El origen de un dato no decide si se publica (dueño, 2026-10-01): una
      -- deducción se muestra como cualquier otro dato y la mano la corrige.
      and not exists(select 1 from jsonb_array_elements(p.issues) i where coalesce((i->>'blocking')::boolean,true) and i->>'field' in ('',d.key))
  ), shown as (
    select f.*,case
      when f.data_type='json' and f.validation_rules ? 'rows_schema' and f.store_view is not null then public.spec_rows_store_display_internal_v1(f.store_view,f.validation_rules->'rows_schema',public.spec_coherence_display_rows_internal_v1(f.val,public.spec_coherence_labels_internal_v1(f.key,f.form_contract,f.vals)))
      when f.data_type='json' and f.validation_rules ? 'rows_schema' then public.spec_rows_display_internal_v1(f.validation_rules->'rows_schema',public.spec_coherence_display_rows_internal_v1(f.val,public.spec_coherence_labels_internal_v1(f.key,f.form_contract,f.vals)))
      when jsonb_typeof(f.val)='array' then (select string_agg(public.spec_option_display_internal_v1(f.definition_id,e,p_tenant_id),', ' order by n) from jsonb_array_elements_text(f.val) with ordinality a(e,n))
      when jsonb_typeof(f.val)='boolean' then case when f.val='true'::jsonb then 'Sí' else 'No' end
      when f.data_type='single_select' then public.spec_option_display_internal_v1(f.definition_id,f.val#>>'{}',p_tenant_id)
      else f.val#>>'{}' end display_value
    from fields f
  )
  select s.section_key,dense_rank() over(order by s.section_order,s.section_key)::integer,
    s.sort_order,s.key,s.label,s.display_value,s.unit,s.data_type,s.hint,s.store_highlight::integer
  from shown s where nullif(btrim(s.display_value),'') is not null
  order by s.section_order,s.sort_order,s.label
$function$;
revoke all on function public.get_public_product_technical_specs(uuid, uuid) from public;
grant execute on function public.get_public_product_technical_specs(uuid, uuid) to anon, authenticated, service_role;

-- Los filtros del catálogo cuentan lo deducido igual que la ficha.
create or replace function public.spec_public_facet_values_internal_v1(p_tenant_id uuid)
returns table(product_id uuid, spec_key text, spec_label text, data_type text, unit text, value_text text)
language sql stable security definer set search_path = pg_catalog, public, pg_temp as $$
  with bound as (
    -- Facts of the product's resolved active template, field not retired,
    -- customer-visible, whatever their origin.
    select f.id as fact_id, f.subject_id, f.value_number, f.value_boolean, f.value_json,
      d.key, d.label, d.store_label, d.data_type, d.unit, d.is_filterable, d.validation_rules,
      t.form_contract
    from public.spec_facts f
    join public.product_spec_bindings_internal_v1 b on b.product_id = f.subject_id and b.tenant_id = f.tenant_id
    join public.spec_templates t on t.id = b.template_id and t.is_active and (t.tenant_id is null or t.tenant_id = p_tenant_id)
    join public.spec_template_fields tf on tf.template_id = t.id and tf.spec_definition_id = f.spec_definition_id
    join public.spec_definitions d on d.id = f.spec_definition_id and d.is_customer_visible
    where f.tenant_id = p_tenant_id and f.subject_type = 'product' and f.subject_scope is null
      and coalesce(t.form_contract->'roles'->>d.key, 'primary') <> 'legacy'
  ), scalar as (
    -- Options by label, numbers without trailing zeros, booleans as «Sí»/«No».
    select b.subject_id, b.key,
      coalesce(nullif(btrim(b.store_label), ''), b.form_contract->'labels'->>b.key, b.label) as spec_label,
      b.data_type, b.unit,
      case b.data_type
        when 'number' then trim_scale(b.value_number)::text
        when 'boolean' then case when b.value_boolean then 'Sí' else 'No' end
        else v.label end as value_text
    from bound b
    left join public.spec_fact_values fv on fv.fact_id = b.fact_id
    left join public.spec_definition_values v on v.id = fv.value_id and v.is_active
    where b.is_filterable and b.data_type in ('single_select','number','boolean')
      and (b.data_type <> 'single_select' or v.label is not null)
      and (b.data_type <> 'number' or b.value_number is not null)
      and (b.data_type <> 'boolean' or b.value_boolean is not null)
  ), projected as (
    -- A numeric cell of a rows field named after a global filterable number
    -- field is that field for the visitor (a tube's ISO diameter is «Aro»).
    select b.subject_id, target.key,
      coalesce(nullif(btrim(target.store_label), ''), b.form_contract->'labels'->>target.key, target.label) as spec_label,
      target.data_type, target.unit,
      case when (fit.r->'values'->>(cols.col->>'key')) ~ '^[0-9]+(\.[0-9]+)?$'
        then trim_scale((fit.r->'values'->>(cols.col->>'key'))::numeric)::text end as value_text
    from bound b
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.validation_rules->'rows_schema'->'columns') = 'array'
        then b.validation_rules->'rows_schema'->'columns' else '[]'::jsonb end
    ) as cols(col)
    join public.spec_definitions target
      on target.tenant_id is null and target.key = cols.col->>'key'
     and target.data_type = 'number' and target.is_filterable and target.is_customer_visible
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.value_json->'rows') = 'array' then b.value_json->'rows' else '[]'::jsonb end
    ) as fit(r)
    where b.data_type = 'json' and cols.col->>'type' in ('integer','decimal','number')
  )
  select subject_id, key, spec_label, data_type, unit, value_text from scalar
  union
  select subject_id, key, spec_label, data_type, unit, value_text from projected where value_text is not null
$$;
revoke all on function public.spec_public_facet_values_internal_v1(uuid) from public, anon, authenticated, service_role;

commit;
