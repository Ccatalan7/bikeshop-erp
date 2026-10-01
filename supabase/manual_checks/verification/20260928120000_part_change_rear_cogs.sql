-- Read-back de 20260928120000_part_change_rear_cogs. Antes de desplegar tiene
-- que fallar contra producción (la relación no tiene mapa de códigos ni
-- filas del driver trasero).

-- La relación única: el driver trasero desde las estrías del cassette o
-- desde la familia del piñón de rosca de dos o más coronas, y tiene que
-- calzar; los piñones del cassette y del piñón de rosca sólo se revisan
-- contra la transmisión. El rotor y el neumático siguen iguales.
select 1 / (case when
  (select count(*) from public.bike_fact_spec_links) = 8
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = 'cassette_spline_standard'
          and position = 'rear'
          and bike_fact_key = 'freehubType'
          and template_key = 'cassette'
          and on_mismatch = 'conflict'
          and value_map->>'Shimano HG spline S (7v)' = 'shimano_hg'
          and value_map->>'Shimano MICRO SPLINE (MTB 12v)' = 'microspline'
          and not value_map ? 'Shimano HG spline L2 (ROAD 12v dedicado)'
          and fits = '{"shimano_hg": ["shimano_hg_road_11"], "sram_xd": ["sram_xdr"]}'::jsonb) = 1
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = '_family'
          and template_key = 'freewheel'
          and constant_value = 'threaded_freewheel'
          and on_mismatch = 'conflict'
          and product_condition = '{"spec_key": "sprocket_count", "min": 2, "max": 14}'::jsonb) = 1
  and (select count(*) from public.bike_fact_spec_links
        where spec_key = 'sprocket_count'
          and bike_fact_key = 'drivetrainConfig'
          and on_mismatch = 'check'
          and template_key in ('cassette', 'freewheel')) = 2
  and (select count(*) from public.bike_fact_spec_links
        where spec_key in ('rotor_diameter_mm_value', 'bead_seat_diameter_mm')) = 4
then 1 else 0 end) as relacion_driver_trasero;

-- Con lo que dice el inventario real: cada estría que tiene un cassette en
-- producción tiene código en la ficha de la bici, salvo L2 (sin código); el
-- lector da la familia de un piñón de rosca, y su cuenta.
select 1 / (case when
  not exists (
    select 1
      from public.products p
      join public.product_spec_bindings_internal_v1 b on b.product_id = p.id
     where b.template_key = 'cassette'
       and public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'cassette_spline_standard')->>'value'
           is not null
       and public.bike_fact_link_value_internal(
             (select l from public.bike_fact_spec_links l
               where l.spec_key = 'cassette_spline_standard'),
             public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'cassette_spline_standard'))
           is null
       and public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'cassette_spline_standard')->>'value'
           <> 'Shimano HG spline L2 (ROAD 12v dedicado)')
  and (select public.bike_fact_link_value_internal(
             (select l from public.bike_fact_spec_links l
               where l.spec_key = 'cassette_spline_standard'),
             public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'cassette_spline_standard'))
         from public.products p
        where p.name = 'Cassette Shimano 7V CS-HG200-7 12/32T'
        order by p.created_at limit 1) = '"shimano_hg"'::jsonb
  and (select public.product_bike_fact_spec_internal(p.tenant_id, p.id, '_family')->>'template_key'
         from public.products p
        where p.name = 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71'
        order by p.created_at limit 1) = 'freewheel'
  and (select public.product_bike_fact_spec_internal(p.tenant_id, p.id, 'sprocket_count')->'value'
         from public.products p
        where p.name = 'PIÑON ATORNILLADO 7 VELOCIDADES FALCON MOD.FW71'
        order by p.created_at limit 1) = '7'::jsonb
then 1 else 0 end) as estrias_con_codigo;

-- Las bicis reales: cada transmisión escrita como platos x piñones se lee,
-- su total es platos × piñones (lo que ahora exige el parche), y cada driver
-- escrito tiene nombre.
select 1 / (case when
  not exists (
    select 1
      from public.bike_profiles bp
     where (bp.technical_profile->'values'->>'drivetrainSpeeds') ~ '^[0-9]{1,3}(\.[0-9]+)?$'
       and public.drivetrain_total_speeds(bp.technical_profile->'values'->>'drivetrainConfig')
           <> (bp.technical_profile->'values'->>'drivetrainSpeeds')::numeric)
  and
  not exists (
    select 1
      from public.bike_profiles bp
     where bp.technical_profile->'values'->>'drivetrainConfig' ~ '^[1-3]x([1-9]|1[0-4])$'
       and public.drivetrain_rear_cog_count(bp.technical_profile->'values'->>'drivetrainConfig') is null)
  and not exists (
    select 1
      from public.bike_profiles bp
     where bp.technical_profile->'values'->>'freehubType' is not null
       and public.freehub_type_label(bp.technical_profile->'values'->>'freehubType')
           = bp.technical_profile->'values'->>'freehubType')
  and public.drivetrain_rear_cog_count('3x7') = 7
  and public.drivetrain_rear_cog_count('singlespeed') = 1
  and public.installed_bike_fact_label('freehubType', '"threaded_freewheel"')
      = 'Rueda libre roscada en el driver trasero'
  and public.bike_fact_requirement_text('drivetrainConfig', '3x7') = 'la transmisión es 3x7'
  and public.installed_bike_fact_label('rearWheelBsdMm', '622') = '622 (29″/700c) en la rueda trasera'
then 1 else 0 end) as bicis_reales;

-- Las reglas: lo que calza no cambia la ficha, lo pendiente no se escribe,
-- la transmisión no la escribe un trabajo, y el total llega a 3 × 14.
select 1 / (case when
  pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%Una fila que sólo revisa no instala nada (20260928120000)%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%v_number between 1 and 42%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%v_fits ? v_key%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%waits for a decision%'
  and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
    like '%do not match its configuration%'
  and pg_get_functiondef('public.bike_fact_line_wrote_internal(uuid,uuid,uuid,text,jsonb)'::regprocedure)
    like '%later.completed_at >= latest.completed_at%'
  and public.drivetrain_total_speeds('3x7') = 21
  and public.drivetrain_total_speeds('singlespeed') = 1
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%installed_fact_needs_decision%'
  and pg_get_functiondef('public.apply_job_installed_bike_facts_internal(uuid,uuid,boolean)'::regprocedure)
    like '%v_value jsonb;%'
  and pg_get_functiondef('public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)'::regprocedure)
    like '%job_installs_rear_family_internal%'
  and pg_get_functiondef('public.job_line_part_change_internal(uuid,uuid)'::regprocedure)
    like '%product_condition%'
  -- La puerta de un trabajo terminado dice cómo resolver una línea sin bici.
  and pg_get_functiondef('public.apply_installed_bike_facts_on_job_line_change()'::regprocedure)
    like '%«Asignar a…» en el menú de la línea%'
  and not exists (
    select 1 from pg_proc
     where proname = 'bike_fact_line_wrote_internal'
       and pg_get_function_identity_arguments(oid) like '%numeric%')
  and not has_function_privilege('authenticated',
    'public.bike_fact_line_wrote_internal(uuid,uuid,uuid,text,jsonb)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.job_installs_rear_family_internal(uuid,uuid,uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated',
    'public.bike_fact_link_value_internal(public.bike_fact_spec_links,jsonb)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.job_part_change_writers_v1(uuid)', 'EXECUTE')
  and has_function_privilege('authenticated', 'public.job_part_change_writers_v1(uuid)', 'EXECUTE')
then 1 else 0 end) as reglas_del_driver;
