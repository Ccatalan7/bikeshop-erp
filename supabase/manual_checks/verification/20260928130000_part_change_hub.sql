-- Read-back de 20260928130000_part_change_hub. Antes de desplegar tiene que
-- fallar contra producción (la relación no tiene filas de la maza).

-- La relación única: la maza escribe su driver (sólo los tipos de receptor
-- que son un código de la ficha) y el anclaje del rotor de su rueda; sus
-- perforaciones y el anclaje de un rotor sólo se revisan. La posición de la
-- maza decide la rueda; un juego no instala. Lo de antes sigue igual.
select 1 / (case when
  (select count(*) from public.bike_fact_spec_links) = 15
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = 'hub_drive_receiver_kind'
          and position = 'rear'
          and bike_fact_key = 'freehubType'
          and template_key = 'hub'
          and on_mismatch = 'change'
          and value_map = '{"Driver BMX": "bmx_driver", "Rosca para piñón fijo": "fixed_threaded", "Rosca para piñón (rueda libre)": "threaded_freewheel"}'::jsonb
          and not value_map ? 'Núcleo de cassette'
          and product_condition = '{"spec_key": "hub_package_position", "values": ["Trasera", "Universal"], "missing_ok": true}'::jsonb) = 1
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = 'rotor_mount_type'
          and template_key = 'hub'
          and on_mismatch = 'change'
          and bike_fact_key = case position when 'front' then 'frontRotorMount' else 'rearRotorMount' end
          and value_map = '{"6 pernos": "six_bolt", "Centerlock": "centerlock"}'::jsonb
          and product_condition->'values' = case position
                when 'front' then '["Delantera", "Universal"]'::jsonb
                else '["Trasera", "Universal"]'::jsonb end) = 2
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = 'spoke_hole_count'
          and template_key = 'hub'
          and on_mismatch = 'check'
          and min_value = 12 and max_value = 48) = 2
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = 'rotor_mount_type'
          and template_key = 'rotor'
          and on_mismatch = 'check'
          and fits = '{"six_bolt": ["centerlock"]}'::jsonb) = 2
  and (select count(*) from public.bike_fact_spec_links
        where template_key in ('cassette', 'freewheel')
           or spec_key in ('rotor_diameter_mm_value', 'bead_seat_diameter_mm')) = 8
then 1 else 0 end) as relacion_maza;

-- Con el inventario real: cada tipo de receptor que dice una maza tiene
-- código o es «Núcleo de cassette» (que no dice cuál); cada anclaje dicho se
-- lee; cada posición dicha es una de las cuatro. La HB-RM66 pone Center Lock
-- adelante, la de rosca pone rueda libre, la Freestyle un driver BMX, la
-- Blooke de núcleo nada; el SM-RT10 es Center Lock y el G3, 6 pernos.
select 1 / (case when
  not exists (
    select 1
      from public.products p
      join public.product_spec_bindings_internal_v1 b on b.product_id = p.id
     where b.template_key = 'hub'
       and (public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'hub_drive_receiver_kind')->>'value'
              not in ('Rosca para piñón (rueda libre)', 'Driver BMX', 'Rosca para piñón fijo',
                      'Núcleo de cassette')
            or public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'rotor_mount_type')->>'value'
              not in ('6 pernos', 'Centerlock')
            or public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'hub_package_position')->>'value'
              not in ('Delantera', 'Trasera', 'Juego (delantera y trasera)', 'Universal')))
  and not exists (
    select 1
      from public.products p
      join public.product_spec_bindings_internal_v1 b on b.product_id = p.id
     where b.template_key = 'rotor'
       and public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'rotor_mount_type')->>'value'
           not in ('6 pernos', 'Centerlock'))
  and (select public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key))
         from public.products p, public.bike_fact_spec_links l
        where p.name = 'maza shimano hb-rm66 36h (cl) delantero negro bolsa'
          and l.template_key = 'hub' and l.bike_fact_key = 'frontRotorMount'
        order by p.created_at limit 1) = '"centerlock"'::jsonb
  and (select public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key))
         from public.products p, public.bike_fact_spec_links l
        where p.name = 'Maza Trasera Disco 36H para Piñon con hilo QR 13mm 8S'
          and l.template_key = 'hub' and l.bike_fact_key = 'freehubType'
        order by p.created_at limit 1) = '"threaded_freewheel"'::jsonb
  and (select public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key))
         from public.products p, public.bike_fact_spec_links l
        where p.name = 'Maza Trasera Freestyle sellada 14mm 9T 36H Red'
          and l.template_key = 'hub' and l.bike_fact_key = 'freehubType'
        order by p.created_at limit 1) = '"bmx_driver"'::jsonb
  and (select public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key))
         from public.products p, public.bike_fact_spec_links l
        where p.name = 'Maza Blooke Trasera Nucleo 8-9-10 disco negra 36h 135x10MM'
          and l.template_key = 'hub' and l.bike_fact_key = 'freehubType'
        order by p.created_at limit 1) is null
  and (select public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key))
         from public.products p, public.bike_fact_spec_links l
        where p.name = 'ROTOR FRENO DISCO SHIMANO SM-RT10 160MM AE'
          and l.template_key = 'rotor' and l.bike_fact_key = 'frontRotorMount'
        order by p.created_at limit 1) = '"centerlock"'::jsonb
  and (select public.bike_fact_link_value_internal(l,
                public.product_bike_fact_spec_internal(p.tenant_id, p.id, l.spec_key))
         from public.products p, public.bike_fact_spec_links l
        where p.name = 'Disco freno G3 AE 160mm Genérico con tornillos 1Un'
          and l.template_key = 'rotor' and l.bike_fact_key = 'frontRotorMount'
        order by p.created_at limit 1) = '"six_bolt"'::jsonb
then 1 else 0 end) as inventario_real;

-- Las reglas: marcas por clave, la rueda que queda, los patrones de rayado,
-- el anclaje nuevo en el parche, y la puerta del trabajo terminado que mira
-- también la otra línea de esa rueda.
select 1 / (case when
  public.hub_lacing_fits(36, 32)
  and not public.hub_lacing_fits(32, 36)
  and public.hub_lacing_fits(48, 36)
  and public.job_line_part_change_marks_internal(
        '[{"key": "rearRotorMount", "value": "centerlock"}, {"key": "freehubType", "value": "threaded_freewheel"}]')
      = '[{"key": "freehubType", "value": "threaded_freewheel"}, {"key": "rearRotorMount", "value": "centerlock"}]'::jsonb
  and public.installed_bike_fact_label('frontRotorMount', '"centerlock"')
      = 'Center Lock en el anclaje del rotor delantero'
  and public.bike_fact_requirement_text('rearSpokeHoles', '36') = 'la rueda trasera lleva 36 rayos'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%El anclaje del rotor de cada rueda lo pone su maza (20260928130000)%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%job_line_part_change_internal(v_tenant_id, v_item.id, v_fact->>''key'')%'
  and pg_get_functiondef('public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)'::regprocedure)
    like '%bike_fact_part_checks_internal%'
  and pg_get_functiondef('public.bike_fact_part_checks_internal(uuid,uuid,uuid,text,jsonb)'::regprocedure)
    like '%job_wheel_spokes_internal%'
  and pg_get_functiondef('public.bike_fact_part_checks_internal(uuid,uuid,uuid,text,jsonb)'::regprocedure)
    like '%rotor_floating%'
  -- Revisión de Codex: lo que depende del repuesto se revisa aunque el recibo
  -- exista; dos Enrayados de la misma rueda no escriben; una maza de la otra
  -- rueda no es evidencia; una maza o llanta sin marca pasa por la puerta.
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%conflicting_build%'
  and (select count(*) from regexp_matches(
         pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure),
         'bike_fact_part_checks_internal', 'g')) = 1
  and pg_get_functiondef('public.job_hub_at_wheel_internal(uuid,uuid,uuid,text)'::regprocedure)
    like '%else ''Delantera'' end%'
  and pg_get_functiondef('public.job_wheel_spokes_internal(uuid,uuid,uuid,text,jsonb)'::regprocedure)
    like '%between 12 and 48%'
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%v_evidence_only%'
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%otro Enrayado del mismo trabajo%'
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%v_write_suffix%'
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%sibling_incompatible%'
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%la maza que instala el trabajo%'
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%«Asignar a…» en el menú de la línea%'
  and not has_function_privilege('authenticated',
    'public.job_line_part_change_internal(uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_hub_at_wheel_internal(uuid,uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_wheel_spokes_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_product_condition_met_internal(uuid,uuid,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.hub_lacing_fits(integer,integer)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_part_checks_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.apply_installed_bike_facts_on_job_line_change()', 'EXECUTE')
  and not has_function_privilege('anon', 'public.job_part_change_writers_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.job_part_change_writers_v1(uuid)', 'EXECUTE')
then 1 else 0 end) as reglas_de_la_maza;

-- Ninguna ficha real dice un anclaje fuera del vocabulario.
select 1 / (case when
  not exists (
    select 1
      from public.bike_profiles bp
     where coalesce(bp.technical_profile->'values'->>'frontRotorMount', 'six_bolt')
             not in ('six_bolt', 'centerlock', 'unknown')
        or coalesce(bp.technical_profile->'values'->>'rearRotorMount', 'six_bolt')
             not in ('six_bolt', 'centerlock', 'unknown'))
then 1 else 0 end) as fichas_con_anclaje;
