-- Read-back of 20261002130000: the storefront speaks the customer's words.
-- 227 store names, 43 with an explanation of the term;
-- 4 names per sheet, 157 ranked highlights in 45 sheets, 3 fields
-- leave the storefront, 19 more option names; every datum a published
-- product shows has a store name; the sheet sends explanation and rank; the
-- filters use the store name and the visitor can read option names.
-- Read-only; division by zero fails it.
select 1/(case when
 (select count(*) from public.spec_definitions where tenant_id is null and store_label is not null)=227
 and (select count(*) from public.spec_definitions where tenant_id is null and store_hint is not null)=43
 and (select count(*) from public.spec_template_fields f join public.spec_templates t on t.id=f.template_id join public.spec_definitions d on d.id=f.spec_definition_id
      where t.tenant_id is null and ((t.key='chain_link' and d.key='chain_speeds' and f.store_label='Velocidades de la cadena') or (t.key='handlebar' and d.key='bar_clamp_diameter_mm' and f.store_label='Diámetro central') or (t.key='stem' and d.key='bar_clamp_diameter_mm' and f.store_label='Para manubrio de') or (t.key='bottle' and d.key='volume_ml' and f.store_label='Capacidad')))=4
 and (select count(*) from public.spec_template_fields where store_highlight is not null)=157
 and (select count(*) from public.spec_definitions where tenant_id is null and is_customer_visible and key in ('published_variant_label', 'rear_derailleur_supplied_adapter_reference', 'rim_joint_designation'))=0
 and (select count(*) from public.spec_definition_values v join public.spec_definitions d on d.id=v.spec_definition_id
      where d.tenant_id is null and v.tenant_id is null and ((d.key='spoke_head_interface' and v.label='J-Bend' and v.display_label='Con codo (J-bend)') or (d.key='spoke_head_interface' and v.label='Straight Pull' and v.display_label='Recto (straight pull)') or (d.key='hub_spoke_head_interface' and v.label='J-Bend' and v.display_label='Con codo (J-bend)') or (d.key='hub_spoke_head_interface' and v.label='Straight Pull' and v.display_label='Recto (straight pull)') or (d.key='spoke_bend_type' and v.label='J-Bend' and v.display_label='Con codo (J-bend)') or (d.key='spoke_bend_type' and v.label='Straight Pull' and v.display_label='Recto (straight pull)') or (d.key='front_derailleur_pull_direction' and v.label='Top pull' and v.display_label='Tiro arriba (top pull)') or (d.key='front_derailleur_pull_direction' and v.label='Down pull' and v.display_label='Tiro abajo (down pull)') or (d.key='front_derailleur_pull_direction' and v.label='Dual pull' and v.display_label='Doble tiro (dual pull)') or (d.key='rear_derailleur_mount_type' and v.label='Pata/postiza estándar' and v.display_label='En la postiza (estándar)') or (d.key='rear_derailleur_mount_type' and v.label='Con uña / claw' and v.display_label='Con uña (claw)') or (d.key='chain_width_family' and v.label='1/8' and v.display_label='1/8"') or (d.key='chain_width_family' and v.label='3/32' and v.display_label='3/32"') or (d.key='chain_width_family' and v.label='11/128' and v.display_label='11/128"') or (d.key='shift_technology' and v.label='HYPERGLIDE' and v.display_label='Hyperglide') or (d.key='shift_technology' and v.label='HYPERGLIDE+' and v.display_label='Hyperglide+') or (d.key='shift_technology' and v.label='LINKGLIDE' and v.display_label='Linkglide') or (d.key='cassette_spline_standard' and v.label='Shimano MICRO SPLINE (MTB 12v)' and v.display_label='Shimano Micro Spline (MTB 12v)') or (d.key='target_rear_drive_interface' and v.label='Shimano MICRO SPLINE (MTB 12v)' and v.display_label='Shimano Micro Spline (MTB 12v)')))=19
 and not exists (
   select 1 from public.products p
   join public.product_spec_bindings_internal_v1 b on b.product_id=p.id
   join public.spec_templates t on t.id=b.template_id
   join public.spec_template_fields f on f.template_id=t.id
   join public.spec_definitions d on d.id=f.spec_definition_id and d.is_customer_visible
   join public.spec_facts x on x.tenant_id=p.tenant_id and x.subject_type='product' and x.subject_id=p.id
     and x.subject_scope is null and x.spec_definition_id=d.id
   where coalesce(p.is_published,false) and coalesce(p.show_on_website,false) and coalesce(p.is_active,true)
     and coalesce(t.form_contract->'roles'->>d.key,'primary')<>'legacy'
     and nullif(btrim(coalesce(f.store_label,d.store_label)),'') is null)
 and position('spec_hint' in pg_get_function_result('public.get_public_product_technical_specs(uuid,uuid)'::regprocedure))>0
 and position('highlight_rank' in pg_get_function_result('public.get_public_product_technical_specs(uuid,uuid)'::regprocedure))>0
 and has_function_privilege('anon','public.get_public_product_technical_specs(uuid,uuid)','execute')
 and has_function_privilege('anon','public.get_public_spec_option_labels_v1(uuid)','execute')
 and not has_function_privilege('anon','public.spec_public_facet_values_internal_v1(uuid)','execute')
 and position('store_label' in pg_get_functiondef('public.spec_public_facet_values_internal_v1(uuid)'::regprocedure))>0
 then 1 else 0 end) as spec_store_words_ok;
