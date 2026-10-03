-- Read-back of 20261002170000: steering and cockpit in the bike sheet. The
-- relation admits whole-bike parts (position none) and measures with tenths;
-- its eight new rows exist with their rule, and the stem is not one of them
-- (a bigger stem clamps a thinner bar with a shim); the value reader takes 31.8 and
-- refuses 31.85; a line mark compares tenths by value; the gate knows the five
-- new keys with their ranges and vocabularies; labels speak with a decimal
-- comma; the history pass left every written fact sourced from a finished job
-- and in range. Read-only; division by zero fails it.
select 1/(case when
 exists (select 1 from information_schema.columns where table_schema = 'public'
         and table_name = 'bike_fact_spec_links' and column_name = 'value_decimals')
 and (select pg_get_constraintdef(oid) from pg_constraint
       where conname = 'bike_fact_spec_links_position_check') like '%none%'
 and (select count(*) from public.bike_fact_spec_links where position = 'none') = 8
 and (select count(*) from public.bike_fact_spec_links where position in ('front', 'rear')) = 19
 and not exists (select 1 from public.bike_fact_spec_links where template_key = 'stem')
 and exists (select 1 from public.bike_fact_spec_links where position = 'none'
             and template_key = 'shifter' and bike_fact_key = 'controlsBarDiameterMm'
             and on_mismatch = 'conflict' and value_decimals = 1)
 and exists (select 1 from public.bike_fact_spec_links where position = 'none'
             and template_key = 'seatpost' and bike_fact_key = 'seatpostDiameterMm'
             and product_condition->'values' ? 'Rígida'
             and not product_condition->'values' ? 'Suplemento (shim)')
 and public.bike_fact_link_value_internal(
       (select l from public.bike_fact_spec_links l
         where l.spec_key = 'bar_clamp_diameter_mm' and l.template_key = 'handlebar'),
       '{"value": 31.8}') = '31.8'::jsonb
 and public.bike_fact_link_value_internal(
       (select l from public.bike_fact_spec_links l
         where l.spec_key = 'bar_clamp_diameter_mm' and l.template_key = 'handlebar'),
       '{"value": 31.85}') is null
 and public.bike_fact_link_value_internal(
       (select l from public.bike_fact_spec_links l
         where l.spec_key = 'steerer_fit'),
       '{"value": "1 1/8\" (28.6 mm)"}') = '"straight_1_1_8"'::jsonb
 and position('(\.[0-9]+)?$' in pg_get_functiondef(
       'public.job_line_part_change_internal(uuid,uuid,text)'::regprocedure)) > 0
 and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
       like '%when ''handlebarClampMm'' then v_number between 20 and 40%'
 and pg_get_functiondef('public.patch_bike_technical_facts_v1(text,uuid,uuid,text,jsonb)'::regprocedure)
       like '%when ''seatpostKind'' then v_text in (''rigid'', ''suspension'', ''dropper'')%'
 and pg_get_functiondef('public.bike_fact_part_conflict_internal(uuid,uuid,uuid,text,jsonb,jsonb,jsonb,text)'::regprocedure)
       like '%trim_scale((v_current%'
 and public.installed_bike_fact_label('handlebarClampMm', '31.8') = '31,8 mm en la abrazadera del manubrio'
 and public.installed_bike_fact_label('steererFit', '"tapered_1_1_8_1_5"') = 'cónico 1⅛″–1,5″ en el tubo de horquilla'
 and public.bike_fact_requirement_text('controlsBarDiameterMm', '23.8') = 'la zona de mandos del manubrio es de 23,8 mm'
 and public.bike_fact_requirement_advice('controlsBarDiameterMm') like 'Manillas, mandos y puños calzan%'
 and not has_function_privilege('authenticated',
       'public.bike_fact_link_value_internal(public.bike_fact_spec_links,jsonb)', 'execute')
 and not exists (
   select 1
     from public.bike_profiles bp
    cross join lateral jsonb_each(coalesce(bp.technical_profile->'values', '{}'::jsonb)) v
    where (v.key = 'handlebarClampMm'
           and (jsonb_typeof(v.value) <> 'number'
                or (v.value #>> '{}')::numeric not between 20 and 40))
       or (v.key = 'controlsBarDiameterMm'
           and (jsonb_typeof(v.value) <> 'number'
                or (v.value #>> '{}')::numeric not between 20 and 30))
       or (v.key = 'seatpostDiameterMm'
           and (jsonb_typeof(v.value) <> 'number'
                or (v.value #>> '{}')::numeric not between 20 and 36)))
 and not exists (
   select 1
     from public.bike_events e
    where e.payload->>'migration' = '20261002170000_cockpit_bike_facts'
      and (e.source <> 'job_completion' or e.event_category <> 'state'))
 then 1 else 0 end) as cockpit_bike_facts_ok;
