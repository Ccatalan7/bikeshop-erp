-- Read-back of 20261002150000: a sheet is completed with expert judgment.
-- The batch receipt table is internal; the fill command and its undo exist
-- for shop staff only; a receipt carries the datum's fingerprint, whose
-- function stays internal; no rows table requires a source document, URL or
-- scope any more, and a guard keeps it so; a fork row may carry only its
-- wheel size; the 67 fields the first batch populates have a store name.
-- Read-only; division by zero fails it.
select 1/(case when
 to_regclass('public.spec_fact_expert_fills') is not null
 and (select relrowsecurity from pg_class where oid = 'public.spec_fact_expert_fills'::regclass)
 and not has_table_privilege('anon', 'public.spec_fact_expert_fills', 'select')
 and not has_table_privilege('authenticated', 'public.spec_fact_expert_fills', 'select')
 and exists (select 1 from information_schema.columns where table_schema = 'public'
             and table_name = 'spec_fact_expert_fills' and column_name = 'fingerprint' and is_nullable = 'NO')
 and not has_function_privilege('authenticated', 'public.spec_fact_fingerprint_internal_v1(uuid,uuid)', 'execute')
 and has_function_privilege('authenticated', 'public.record_product_spec_expert_value_v1(uuid,text,jsonb,text,text,text)', 'execute')
 and not has_function_privilege('anon', 'public.record_product_spec_expert_value_v1(uuid,text,jsonb,text,text,text)', 'execute')
 and has_function_privilege('authenticated', 'public.discard_product_spec_expert_batch_v1(text)', 'execute')
 and not has_function_privilege('anon', 'public.discard_product_spec_expert_batch_v1(text)', 'execute')
 and not exists (
   select 1 from public.spec_definitions d
   cross join lateral jsonb_array_elements(d.validation_rules->'rows_schema'->'columns') c
   where d.validation_rules ? 'rows_schema' and c->>'key' like 'source%' and c->'required' = 'true'::jsonb)
 and not exists (
   select 1 from public.spec_definitions d
   cross join lateral jsonb_array_elements(d.validation_rules->'rows_schema'->'columns') c
   where d.tenant_id is null and d.key = 'fork_tire_clearance_configurations'
     and c->>'key' = 'max_tire_width_mm' and c->'required' = 'true'::jsonb)
 and (select count(*) from public.spec_definitions where tenant_id is null and nullif(btrim(store_label), '') is not null
      and key in ('bike_attachment_kind','color','ball_count_per_pack','bike_protection_kind','bottle_retention_system','cage_mount',
        'cage_retention_system','boss_count','cable_pull_required','lever_mount_method','pad_shape_code','rim_pad_construction',
        'target_rear_drive_interface','spacer_thickness_mm','chain_directional','chainring_teeth_min','chainring_teeth_max',
        'chainring_mount_type','chainring_bolt_pattern_symmetric','chainring_set_member_count','noodle_angle_deg',
        'fits_cable_diameter_mm','fits_housing_diameter_mm','pedal_thread','hanger_derailleur_interface','hanger_frame_interface',
        'hanger_model_code','uv_protection_claim','temperature','preparation_kind','food_item_kind','serving_size','milk_in_recipe',
        'flavor','freewheel_thread_standard','remover_tool_standard','grip_bar_nominal_diameter_mm','grip_end_plugs_included',
        'bar_construction','grip_area_diameter_mm','bar_width_reference','crown_race_included','oem_size_label','visor',
        'head_circumference_min_cm','head_circumference_max_cm','hub_spoke_head_interface','inner_width_mm','inner_height_mm',
        'cable_length_mm','cleat_system','hose','carrier_mount_kind','rear_derailleur_spring_return','gender_fit',
        'pad_compound_restriction','cover_material','saddle_rail_geometry','spoke_finish_declared','spoke_material_declared',
        'stem_steerer_clamp_diameter_mm','valve_core_removable','toluene_free','patch_size_mm','tubeless_tape_application',
        'not_for','tool_interface'))=67
 and exists (select 1 from pg_trigger where tgname = 'spec_rows_source_optional_guard'
             and tgrelid = 'public.spec_definitions'::regclass and tgenabled = 'O')
 and exists (select 1 from pg_trigger where tgname = 'spec_rows_definition_guard'
             and tgrelid = 'public.spec_definitions'::regclass and tgenabled = 'O')
 then 1 else 0 end) as spec_expert_fill_ok;
