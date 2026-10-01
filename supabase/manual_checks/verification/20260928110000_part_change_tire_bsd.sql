-- Read-back de 20260928110000_part_change_tire_bsd. Antes de desplegar tiene
-- que fallar contra producción (la relación no tiene familia ni regla de
-- calce).

-- La relación única: el BSD del neumático por rueda, sólo desde la familia
-- neumático, y tiene que calzar; el rotor sigue siendo un cambio. Una fila
-- por concepto, rueda y familia; el ancho no se enlaza.
select 1 / (case when
  (select count(*) from public.bike_fact_spec_links) = 4
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = 'bead_seat_diameter_mm'
          and template_key = 'tire'
          and on_mismatch = 'conflict'
          and component_article = 'la'
          and min_value = 150 and max_value = 700
          and requires_fact_key is null
          and ((position = 'front' and bike_fact_key = 'frontWheelBsdMm'
                and component_label = 'rueda delantera')
            or (position = 'rear' and bike_fact_key = 'rearWheelBsdMm'
                and component_label = 'rueda trasera'))) = 2
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = 'rotor_diameter_mm_value'
          and on_mismatch = 'change'
          and component_article = 'el') = 2
  and not exists (select 1 from public.bike_fact_spec_links
                   where spec_key in ('tire_width_mm', 'tire_etrto'))
  and exists (select 1 from pg_indexes
               where schemaname = 'public'
                 and indexname = 'bike_fact_spec_links_concept_position_family')
  and not has_table_privilege('authenticated', 'public.bike_fact_spec_links', 'INSERT')
then 1 else 0 end) as relacion_por_familia;

-- El lector del producto da valor, familia y verificación con lo que dice el
-- inventario real; la llanta es otra familia.
select 1 / (case when
  (select public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'bead_seat_diameter_mm')
     from public.products p
    where p.name = 'MAXXIS ALAMBRE 29X2.25 M315P ARDENT'
    order by p.created_at limit 1)
    = '{"value": 622, "template_key": "tire", "verified": false}'::jsonb
  and (select public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'bead_seat_diameter_mm')
     from public.products p
    where p.name = 'Neumatico Bicicleta Aro 27.5 X 2.10 Voltage Best'
    order by p.created_at limit 1)
    = '{"value": 584, "template_key": "tire", "verified": false}'::jsonb
  and (select public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'bead_seat_diameter_mm')
             ->> 'template_key'
     from public.products p
    where p.name = 'Llanta Weinmann U32 TL 29" Ojetillos 32H Presta Negro'
    order by p.created_at limit 1) = 'rim'
  and (select public.product_bike_fact_spec_value_internal(p.tenant_id, p.id, 'rotor_diameter_mm_value')
     from public.products p
    where p.name = 'Disco freno Shimano Deore RT56 180MM'
    order by p.created_at limit 1) = '180'::jsonb
  -- En todo neumático con BSD, el lector da lo mismo que el espejo.
  and (select count(*)
         from public.product_spec_values v
         join public.spec_definitions d on d.id = v.spec_definition_id
         join public.products p
           on p.id = v.product_id and p.tenant_id = v.tenant_id
        where d.key = 'bead_seat_diameter_mm'
          and v.value_number is not null
          and (public.product_bike_fact_spec_value_internal(
                 p.tenant_id, p.id, d.key) #>> '{}')::numeric
              is distinct from v.value_number) = 0
  and not has_function_privilege('authenticated',
    'public.product_bike_fact_spec_internal(uuid,uuid,text)', 'EXECUTE')
then 1 else 0 end) as lector_con_familia;

-- ISO 5775 sobre los rótulos reales de las bicis: sólo 29″/700c (622) y
-- 27,5″/650b (584) refutan; 26″ y lo que no se lee, nada.
select 1 / (case when
  not exists (
    select 1
      from (select distinct wheel_size from public.bikes) b,
           unnest(public.iso_bsd_candidates_for_wheel_size(b.wheel_size)) c
     where c not in (584, 622))
  and public.iso_bsd_candidates_for_wheel_size('29"') = '{622}'
  and public.iso_bsd_candidates_for_wheel_size('700') = '{622}'
  and public.iso_bsd_candidates_for_wheel_size('27.5"') = '{584}'
  and public.iso_bsd_candidates_for_wheel_size('26"') = '{}'
  and public.iso_bsd_candidates_for_wheel_size('27.5" - 26"') = '{}'
  and public.iso_bsd_candidates_for_wheel_size('28') = '{}'
  and public.iso_bsd_candidates_for_wheel_size('2 9') = '{}'
  and public.iso_bsd_wheel_label(622) = '622 (29″/700c)'
  and public.iso_bsd_wheel_label(642) = '642 (28″ 700A)'
  and not has_function_privilege('authenticated',
    'public.iso_bsd_candidates_for_wheel_size(text)', 'EXECUTE')
then 1 else 0 end) as aro_iso;

-- Las reglas: lo declarado sin verificar, la regla de calce en el aplicador
-- y el parche (con las fuentes de la ficha, para que una medida del mecánico
-- no se tome por un dato de la línea), y el texto del taller.
select 1 / (case when
  not has_function_privilege('authenticated',
    'public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)', 'EXECUTE')
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%Lo declarado que ya dice lo mismo no cambia nada%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%v_values, v_sources, v_bike.wheel_size);%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%set, suggest, declare or remove%'
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%coalesce(v_profile_sources, ''{}''::jsonb), v_wheel_size)%'
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%else ''declare''%'
  and pg_get_functiondef('public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)'::regprocedure)
    like '%is distinct from ''job_completion''%'
  -- La regla es la de la fila que usó la línea, y «lo escribió» es el último
  -- recibo de la bici que tocó la clave.
  and pg_get_functiondef('public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)'::regprocedure)
    like '%v_part->>''on_mismatch'' is distinct from ''conflict''%'
  and pg_get_functiondef('public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)'::regprocedure)
    like '%bike_fact_line_wrote_internal%'
  and pg_get_functiondef('public.bike_fact_line_wrote_internal(uuid,uuid,uuid,text,numeric)'::regprocedure)
    like '%jsonb_array_elements%order by p.completed_at desc,%'
  and not has_function_privilege('authenticated',
    'public.bike_fact_line_wrote_internal(uuid,uuid,uuid,text,numeric)', 'EXECUTE')
  -- Lo que lee el formulario: sólo el taller del trabajo.
  and has_function_privilege('authenticated', 'public.job_part_change_writers_v1(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.job_part_change_writers_v1(uuid)', 'EXECUTE')
  and pg_get_functiondef('public.job_part_change_writers_v1(uuid)'::regprocedure)
    like '%assert_workshop_rpc_tenant%'
  and pg_get_functiondef('public.job_line_part_change_internal(uuid,uuid)'::regprocedure)
    like '%''link_id'', v_link.id%'
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%where l.id = (v_verified->>''link_id'')::uuid%'
  and public.installed_bike_fact_label('rearWheelBsdMm', '622'::jsonb)
      = '622 (29″/700c) en la rueda trasera'
  and public.installed_bike_fact_label('rearRotorSizeMm', '180'::jsonb)
      = '180 mm en el rotor trasero'
  and public.bike_fact_requirement_text('frontWheelBsdMm', '584')
      = 'la rueda delantera es 584 (27,5″/650b)'
  and public.bike_fact_requirement_text('bikes.wheel_size', '29"') = 'aro 29"'
then 1 else 0 end) as neumatico_por_la_puerta;
