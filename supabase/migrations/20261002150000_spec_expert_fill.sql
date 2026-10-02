-- El catálogo se completa con criterio de experto (2026-10-01).
--
-- De 1.600 productos publicados, 347 no mostraban ningún dato técnico y 810
-- uno o dos. No faltaba conocimiento: faltaba una manera de escribirlo. Los
-- dos caminos automáticos exigían un respaldo que nadie pidió: la lectura del
-- nombre (`record_product_spec_reading_v1`) sólo acepta una cita textual del
-- nombre y sólo en campos filtrables, y la investigación
-- (`apply_product_spec_research_v1`) exige registro, habilitación y evidencia
-- por cambio. El dueño: «nadie pidió eso de que los datos tuvieran que sí o sí
-- ser respaldados con fuente documentada».
--
-- `record_product_spec_expert_value_v1` escribe lo que un vendedor experto
-- sabe del producto —por su nombre, su descripción, su marca, su modelo y la
-- línea del fabricante— en cualquier campo vigente de su ficha, sin cita ni
-- URL. El dato queda con origen `research` («De la investigación del
-- catálogo» en el editor) y un recibo con la tanda, el modelo y una razón
-- opcional, para que una tanda se pueda deshacer entera
-- (`discard_product_spec_expert_batch_v1`).
--
-- Nunca pisa lo que otro escribió: sólo llena un campo vacío, reemplaza una
-- deducción (`inferred`) que nadie confirmó o corrige un dato de una tanda
-- anterior que nadie tocó (su huella sigue siendo la del recibo). Lo escrito
-- a mano, lo confirmado, el texto del proveedor, una lectura del nombre, la
-- ficha anterior y la investigación con evidencia se conservan. Las reglas de
-- la ficha (opciones, rangos, coherencia entre campos, filas) siguen siendo
-- el juez: un valor que no las cumple se rechaza y no se escribe. Los 67
-- campos que la primera tanda puebla por primera vez reciben aquí su nombre
-- de tienda.
--
-- La misma exigencia estaba escrita en las tablas: 88 de las 150 con filas
-- (presiones, dientes, aros admitidos, capacidades…) pedían en cada fila el
-- documento, la URL o el «alcance» de la fuente, así que ninguna fila se podía
-- escribir sin inventar un documento. Esas columnas pasan a ser opcionales —se
-- llenan cuando hay documento— y un guardia impide volver a exigirlas.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';

create temporary table _rows_source_optional on commit drop as
select d.id from public.spec_definitions d
where d.validation_rules ? 'rows_schema'
  and exists (select 1 from jsonb_array_elements(d.validation_rules->'rows_schema'->'columns') c
              where c->>'key' like 'source%' and c->'required' = 'true'::jsonb);

-- Quitar una obligación no invalida ninguna fila guardada; el guardia de
-- esquemas con datos sólo se aparta para este cambio, como en 20260919253000.
alter table public.spec_definitions disable trigger spec_rows_definition_guard;
update public.spec_definitions d
   set validation_rules = jsonb_set(d.validation_rules, '{rows_schema,columns}',
         (select jsonb_agg(case when c->>'key' like 'source%' then c - 'required' else c end order by n)
          from jsonb_array_elements(d.validation_rules->'rows_schema'->'columns') with ordinality x(c, n))),
       updated_at = now()
  from _rows_source_optional o
 where o.id = d.id;
-- Una horquilla dice para qué aro es aunque no se sepa el neumático más
-- ancho que admite: esa medida deja de ser obligatoria en su fila.
update public.spec_definitions d
   set validation_rules = jsonb_set(d.validation_rules, '{rows_schema,columns}',
         (select jsonb_agg(case when c->>'key' = 'max_tire_width_mm' then c - 'required' else c end order by n)
          from jsonb_array_elements(d.validation_rules->'rows_schema'->'columns') with ordinality x(c, n))),
       updated_at = now()
 where d.tenant_id is null and d.key = 'fork_tire_clearance_configurations'
   and exists (select 1 from jsonb_array_elements(d.validation_rules->'rows_schema'->'columns') c
               where c->>'key' = 'max_tire_width_mm' and c->'required' = 'true'::jsonb);
insert into _rows_source_optional
select d.id from public.spec_definitions d
where d.tenant_id is null and d.key = 'fork_tire_clearance_configurations'
  and not exists (select 1 from _rows_source_optional o where o.id = d.id);
-- Las revisiones de contrato que dispara el cambio se resuelven antes de
-- volver a encender el guardia (si quedan pendientes, Postgres no lo deja).
set constraints all immediate;
alter table public.spec_definitions enable trigger spec_rows_definition_guard;
do $revalidate$
declare r record;
begin
  for r in select d.validation_rules->'rows_schema' as schema
           from public.spec_definitions d join _rows_source_optional o on o.id = d.id loop
    perform public.spec_rows_schema_validate_internal_v1(r.schema);
  end loop;
end
$revalidate$;

create or replace function public.spec_rows_source_optional_guard_internal_v1()
returns trigger language plpgsql set search_path = pg_catalog, public, pg_temp as $guard$
declare v_column text;
begin
  select c->>'key' into v_column
  from jsonb_array_elements(case when jsonb_typeof(new.validation_rules->'rows_schema'->'columns') = 'array'
    then new.validation_rules->'rows_schema'->'columns' else '[]'::jsonb end) c
  where c->>'key' like 'source%' and c->'required' = 'true'::jsonb
  limit 1;
  if v_column is not null then
    raise exception 'La fuente de una fila («%») es opcional: no puede ser obligatoria.', v_column
      using errcode = '23514';
  end if;
  return new;
end
$guard$;
revoke all on function public.spec_rows_source_optional_guard_internal_v1() from public, anon, authenticated;
drop trigger if exists spec_rows_source_optional_guard on public.spec_definitions;
create trigger spec_rows_source_optional_guard before insert or update of validation_rules on public.spec_definitions
  for each row execute function public.spec_rows_source_optional_guard_internal_v1();

-- Los campos que este llenado puebla por primera vez se nombran para la
-- tienda en la misma migración (regla de 20261002130000: todo dato publicado
-- lleva nombre de tienda).
create temporary table _expert_store_words(key text primary key, label text not null, hint text) on commit drop;
insert into _expert_store_words(key, label, hint) values
  ('bike_attachment_kind', 'Se fija a', null),
  ('color', 'Color', null),
  ('ball_count_per_pack', 'Bolitas por bolsa', null),
  ('bike_protection_kind', 'Tipo de protección', null),
  ('bottle_retention_system', 'Sujeción', null),
  ('cage_mount', 'Fijación', null),
  ('cage_retention_system', 'Sujeción de la caramagiola', null),
  ('boss_count', 'Tornillos al cuadro', null),
  ('cable_pull_required', 'Para manilla de', 'Tiro largo: manillas de V-brake y de disco mecánico. Tiro corto: manillas de ruta.'),
  ('lever_mount_method', 'Fijación', null),
  ('pad_shape_code', 'Modelo de pastilla', 'Compara este código con el de la pastilla que sacas.'),
  ('rim_pad_construction', 'Tipo de patín', null),
  ('target_rear_drive_interface', 'Para núcleo', null),
  ('spacer_thickness_mm', 'Espesor', null),
  ('chain_directional', 'Con sentido de montaje', 'Si dice sí, la cadena se instala con las letras hacia afuera.'),
  ('chainring_teeth_min', 'Plato desde', null),
  ('chainring_teeth_max', 'Plato hasta', null),
  ('chainring_mount_type', 'Fijación', null),
  ('chainring_bolt_pattern_symmetric', 'Pernos simétricos', null),
  ('chainring_set_member_count', 'Platos del juego', null),
  ('noodle_angle_deg', 'Ángulo', null),
  ('fits_cable_diameter_mm', 'Para cable de', null),
  ('fits_housing_diameter_mm', 'Para funda de', null),
  ('pedal_thread', 'Rosca de pedal', '9/16": bielas de dos y tres piezas. 1/2": biela americana de una pieza.'),
  ('hanger_derailleur_interface', 'Unión con el cambio', null),
  ('hanger_frame_interface', 'Se monta en', null),
  ('hanger_model_code', 'Código de la postiza', 'Compara este código con el de tu postiza antes de comprar.'),
  ('uv_protection_claim', 'Protección UV', null),
  ('temperature', 'Se sirve', null),
  ('preparation_kind', 'Preparación', null),
  ('food_item_kind', 'Bebida', null),
  ('serving_size', 'Tamaño', null),
  ('milk_in_recipe', 'Leche', null),
  ('flavor', 'Sabor', null),
  ('freewheel_thread_standard', 'Rosca', 'La inglesa 1.37" x 24 es la de casi todas las mazas de rosca.'),
  ('remover_tool_standard', 'Extractor', null),
  ('grip_bar_nominal_diameter_mm', 'Para manubrio de', null),
  ('grip_end_plugs_included', 'Incluye tapones', null),
  ('bar_construction', 'Construcción', null),
  ('grip_area_diameter_mm', 'Diámetro en los puños', null),
  ('bar_width_reference', 'El ancho se mide', null),
  ('crown_race_included', 'Incluye pista de corona', null),
  ('oem_size_label', 'Talla', null),
  ('visor', 'Visera', null),
  ('head_circumference_min_cm', 'Contorno de cabeza desde', null),
  ('head_circumference_max_cm', 'Contorno de cabeza hasta', null),
  ('hub_spoke_head_interface', 'Tipo de rayo', 'Con codo (J-bend) es el rayo común; el recto (straight pull) necesita una maza hecha para él.'),
  ('inner_width_mm', 'Ancho interior', null),
  ('inner_height_mm', 'Largo interior', null),
  ('cable_length_mm', 'Largo del cable', null),
  ('cleat_system', 'Sistema de calas', null),
  ('hose', 'Con manguera', null),
  ('carrier_mount_kind', 'Fijación', null),
  ('rear_derailleur_spring_return', 'Retorno del resorte', null),
  ('gender_fit', 'Corte', null),
  ('pad_compound_restriction', 'Pastillas', 'Un disco «sólo resina» se gasta rápido con pastillas metálicas.'),
  ('cover_material', 'Forro', null),
  ('saddle_rail_geometry', 'Rieles', 'Los redondos de 7 mm calzan en casi todos los postes de asiento.'),
  ('spoke_finish_declared', 'Acabado', null),
  ('spoke_material_declared', 'Material', null),
  ('stem_steerer_clamp_diameter_mm', 'Para tubo de dirección de', null),
  ('valve_core_removable', 'Obús desmontable', null),
  ('toluene_free', 'Sin tolueno', null),
  ('patch_size_mm', 'Medida del parche', null),
  ('tubeless_tape_application', 'Cómo se usa', null),
  ('not_for', 'No usar en', null),
  ('tool_interface', 'Encaje', null);
update public.spec_definitions d
   set store_label = w.label, store_hint = w.hint, updated_at = now()
  from _expert_store_words w
 where d.tenant_id is null and d.key = w.key
   and (d.store_label is distinct from w.label or d.store_hint is distinct from w.hint);

create table if not exists public.spec_fact_expert_fills (
  fact_id uuid primary key references public.spec_facts(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  batch text not null check (length(btrim(batch)) between 1 and 80),
  model text not null check (length(model) between 1 and 80),
  reason text check (reason is null or length(reason) <= 500),
  written_by uuid not null,
  written_at timestamptz not null default now(),
  fingerprint text not null
);
create index if not exists spec_fact_expert_fills_batch_idx
  on public.spec_fact_expert_fills (tenant_id, batch);
alter table public.spec_fact_expert_fills enable row level security;
revoke all on table public.spec_fact_expert_fills from public, anon, authenticated;
comment on table public.spec_fact_expert_fills is
  'Recibo de cada dato de ficha completado con criterio de experto: tanda, modelo, razón y la huella del dato tal como quedó. Se borra con su dato.';

-- La huella de un dato: su valor, sus opciones, su origen y si alguien lo
-- confirmó. Un dato de una tanda «sigue como la tanda lo dejó» mientras su
-- huella sea la del recibo; la hora no sirve, porque dentro de una misma
-- transacción `now()` no cambia y una corrección pasaría por intacta.
create or replace function public.spec_fact_fingerprint_internal_v1(p_tenant_id uuid, p_fact_id uuid)
returns text language sql stable set search_path = pg_catalog, public, pg_temp as $print$
  select md5(jsonb_build_object(
    'number', f.value_number, 'boolean', f.value_boolean, 'text', f.value_text, 'json', f.value_json,
    'source', f.source, 'confirmed', f.confirmed,
    'options', (select coalesce(jsonb_agg(v.value_id order by v.position), '[]'::jsonb)
                from public.spec_fact_values v where v.fact_id = f.id))::text)
  from public.spec_facts f
  where f.id = p_fact_id and f.tenant_id = p_tenant_id
$print$;
revoke all on function public.spec_fact_fingerprint_internal_v1(uuid, uuid) from public, anon, authenticated;

create or replace function public.record_product_spec_expert_value_v1(
  p_product_id uuid, p_field_key text, p_value jsonb, p_batch text,
  p_reason text default null, p_model text default null)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $fill$
declare
  v_tenant uuid := public.user_tenant_id();
  v_actor uuid := auth.uid();
  v_def record;
  v_role text;
  v_existing record;
  v_fact uuid;
  v_items text[];
  v_ids uuid[] := '{}';
  v_item text;
  v_id uuid;
  v_number numeric;
  v_message text;
  v_detail text;
begin
  if v_tenant is null or v_actor is null then
    raise exception 'Sin inquilino' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_batch, '')), '') is null or length(p_batch) > 80 then
    return jsonb_build_object('verdict', 'rejected', 'reason', 'la tanda necesita un nombre de hasta 80 letras');
  end if;
  if length(coalesce(p_model, '')) > 80 or length(coalesce(p_reason, '')) > 500 then
    return jsonb_build_object('verdict', 'rejected', 'reason', 'el modelo o la razón son demasiado largos');
  end if;
  if p_value is null or jsonb_typeof(p_value) = 'null' then
    return jsonb_build_object('verdict', 'rejected', 'reason', 'falta el valor');
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_tenant::text || ':spec_fact:' || p_product_id::text, 0));
  perform 1 from public.products p where p.id = p_product_id and p.tenant_id = v_tenant for update;
  if not found then
    return jsonb_build_object('verdict', 'rejected', 'reason', 'el producto no es de este taller');
  end if;

  select d.id, d.key, d.data_type into v_def from public.spec_definitions d
  where d.id = public.spec_product_field_definition_internal_v1(v_tenant, p_product_id, p_field_key);
  if not found then
    return jsonb_build_object('verdict', 'rejected', 'reason', 'el campo no pertenece a la ficha técnica activa');
  end if;
  select coalesce(t.form_contract->'roles'->>v_def.key, 'primary') into v_role
  from public.product_spec_bindings_internal_v1 b
  join public.spec_templates t on t.id = b.template_id
  where b.product_id = p_product_id and b.tenant_id = v_tenant;
  if v_role = 'legacy' then
    return jsonb_build_object('verdict', 'rejected', 'reason', 'el campo está retirado de la ficha');
  end if;

  -- Se reemplaza una deducción que nadie confirmó, o un dato de una tanda
  -- anterior que sigue como esa tanda lo dejó (misma huella).
  select f.id, f.source, f.confirmed,
         coalesce(e.fingerprint = public.spec_fact_fingerprint_internal_v1(v_tenant, f.id), false) as untouched_fill
    into v_existing
  from public.spec_facts f
  left join public.spec_fact_expert_fills e on e.fact_id = f.id and e.tenant_id = v_tenant
  where f.tenant_id = v_tenant and f.subject_type = 'product' and f.subject_id = p_product_id
    and f.spec_definition_id = v_def.id and f.subject_scope is null;
  if found and not ((v_existing.source = 'inferred' and not v_existing.confirmed) or v_existing.untouched_fill) then
    return jsonb_build_object('verdict', 'kept_existing', 'reason', 'el campo ya tiene un dato '
      || case when v_existing.confirmed then 'confirmado' else 'de ' || v_existing.source end);
  end if;

  -- The value in the field's own shape; an option by its label (its
  -- identity), compared without accents or case.
  if v_def.data_type in ('single_select', 'multi_select') then
    v_items := case jsonb_typeof(p_value)
      when 'array' then array(select jsonb_array_elements_text(p_value))
      else array[p_value #>> '{}'] end;
    if cardinality(v_items) = 0 or (v_def.data_type = 'single_select' and cardinality(v_items) <> 1) then
      return jsonb_build_object('verdict', 'rejected', 'reason', 'una opción única necesita exactamente un valor');
    end if;
    foreach v_item in array v_items loop
      select v.id into v_id from public.spec_definition_values v
      where v.spec_definition_id = v_def.id and v.is_active is true
        and (v.tenant_id is null or v.tenant_id = v_tenant)
        and public.assistant_normalize_query_internal_v1(v_item)
          = public.assistant_normalize_query_internal_v1(v.label)
      order by (v.label = v_item) desc, v.sort_order nulls last
      limit 1;
      if v_id is null then
        return jsonb_build_object('verdict', 'rejected', 'reason', 'el valor no está en la lista del campo: ' || v_item);
      end if;
      if not v_id = any(v_ids) then
        v_ids := v_ids || v_id;
      end if;
    end loop;
  elsif v_def.data_type = 'number' then
    if jsonb_typeof(p_value) = 'number' or (p_value #>> '{}') ~ '^-?[0-9]+(\.[0-9]+)?$' then
      v_number := (p_value #>> '{}')::numeric;
    else
      return jsonb_build_object('verdict', 'rejected', 'reason', 'el campo espera un número');
    end if;
  elsif v_def.data_type = 'boolean' then
    if jsonb_typeof(p_value) <> 'boolean' then
      return jsonb_build_object('verdict', 'rejected', 'reason', 'el campo espera sí o no');
    end if;
  elsif v_def.data_type = 'text' then
    if jsonb_typeof(p_value) <> 'string' or nullif(btrim(p_value #>> '{}'), '') is null then
      return jsonb_build_object('verdict', 'rejected', 'reason', 'el campo espera un texto');
    end if;
  elsif v_def.data_type = 'json' then
    if jsonb_typeof(p_value) <> 'object' or jsonb_typeof(p_value->'rows') <> 'array' then
      return jsonb_build_object('verdict', 'rejected', 'reason', 'el campo espera filas');
    end if;
  else
    return jsonb_build_object('verdict', 'rejected', 'reason', 'tipo de campo no admitido: ' || v_def.data_type);
  end if;

  -- A value the sheet's rules reject rolls back its own write.
  begin
    if v_existing.id is not null then
      v_fact := v_existing.id;
      delete from public.spec_fact_values where fact_id = v_fact;
      update public.spec_facts set
        value_number = case when v_def.data_type = 'number' then v_number end,
        value_boolean = case when v_def.data_type = 'boolean' then (p_value #>> '{}')::boolean end,
        value_text = case when v_def.data_type = 'text' then btrim(p_value #>> '{}') end,
        value_json = case when v_def.data_type = 'json' then p_value end,
        source = 'research', confirmed = false, updated_at = now()
      where id = v_fact and tenant_id = v_tenant;
    else
      insert into public.spec_facts (tenant_id, subject_type, subject_id, spec_definition_id,
        value_number, value_boolean, value_text, value_json, source, confirmed)
      values (v_tenant, 'product', p_product_id, v_def.id,
        case when v_def.data_type = 'number' then v_number end,
        case when v_def.data_type = 'boolean' then (p_value #>> '{}')::boolean end,
        case when v_def.data_type = 'text' then btrim(p_value #>> '{}') end,
        case when v_def.data_type = 'json' then p_value end,
        'research', false)
      returning id into v_fact;
    end if;
    insert into public.spec_fact_values (fact_id, value_id, position)
    select v_fact, x.id, (x.n - 1)::integer from unnest(v_ids) with ordinality x(id, n);

    insert into public.spec_fact_expert_fills (fact_id, tenant_id, batch, model, reason, written_by, written_at, fingerprint)
    values (v_fact, v_tenant, btrim(p_batch), coalesce(nullif(btrim(p_model), ''), 'desconocido'),
      nullif(btrim(p_reason), ''), v_actor, now(), public.spec_fact_fingerprint_internal_v1(v_tenant, v_fact))
    on conflict (fact_id) do update set batch = excluded.batch, model = excluded.model,
      reason = excluded.reason, written_by = excluded.written_by, written_at = excluded.written_at,
      fingerprint = excluded.fingerprint;

    perform public.spec_validate_product_internal_v1(p_product_id);
    return jsonb_build_object('verdict', 'recorded', 'factId', v_fact,
      'replaced', case when v_existing.id is null then null else v_existing.source end);
  exception when check_violation or invalid_text_representation or numeric_value_out_of_range
    or invalid_parameter_value or not_null_violation then
    get stacked diagnostics v_message = MESSAGE_TEXT, v_detail = PG_EXCEPTION_DETAIL;
    return jsonb_build_object('verdict', 'rejected', 'reason', v_message, 'details', v_detail);
  end;
end
$fill$;
revoke all on function public.record_product_spec_expert_value_v1(uuid, text, jsonb, text, text, text) from public, anon;
grant execute on function public.record_product_spec_expert_value_v1(uuid, text, jsonb, text, text, text) to authenticated, service_role;

-- Deshacer una tanda: borra sólo los datos que siguen como la tanda los dejó;
-- lo que alguien corrigió después se queda.
create or replace function public.discard_product_spec_expert_batch_v1(p_batch text)
returns jsonb language plpgsql security definer set search_path = pg_catalog, public, pg_temp as $discard$
declare
  v_tenant uuid := public.user_tenant_id();
  v_product uuid;
  v_gone integer;
  v_count integer := 0;
  v_products integer := 0;
begin
  if v_tenant is null or auth.uid() is null then
    raise exception 'Sin inquilino' using errcode = '42501';
  end if;
  -- Producto por producto, bajo el mismo candado que el editor de la ficha:
  -- la huella se compara con nadie escribiendo encima.
  for v_product in
    select distinct f.subject_id
    from public.spec_fact_expert_fills e
    join public.spec_facts f on f.id = e.fact_id and f.tenant_id = v_tenant
    where e.tenant_id = v_tenant and e.batch = btrim(p_batch) and f.subject_type = 'product'
    order by f.subject_id
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_tenant::text || ':spec_fact:' || v_product::text, 0));
    delete from public.spec_facts f
    using public.spec_fact_expert_fills e
    where e.fact_id = f.id and e.tenant_id = v_tenant and e.batch = btrim(p_batch)
      and f.tenant_id = v_tenant and f.subject_type = 'product' and f.subject_id = v_product
      and e.fingerprint = public.spec_fact_fingerprint_internal_v1(v_tenant, f.id);
    get diagnostics v_gone = row_count;
    if v_gone > 0 then
      v_count := v_count + v_gone;
      v_products := v_products + 1;
      perform public.spec_validate_product_internal_v1(v_product);
    end if;
  end loop;
  return jsonb_build_object('discarded', v_count, 'products', v_products);
end
$discard$;
revoke all on function public.discard_product_spec_expert_batch_v1(text) from public, anon;
grant execute on function public.discard_product_spec_expert_batch_v1(text) to authenticated, service_role;

commit;
