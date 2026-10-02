-- Read-back of 20261002140000: the storefront reads rows fields through their
-- store view. 17 views, each visible with a store name; the three projected
-- columns named; 24 ranks in 5 sheets (163 highlights in all); every datum a
-- published product shows still has a store name; and, on one published
-- product per view, the live sheet shows the view, never a source URL; and
-- neither the sheet nor the filters hide a datum for being a deduction; and
-- every saved view passes its own check, which stays internal.
-- Read-only; division by zero fails it.
with sample as (
  select distinct on (d.key) d.key, f.subject_id
  from public.spec_facts f
  join public.spec_definitions d on d.id = f.spec_definition_id and d.store_view is not null
  join public.products p on p.id = f.subject_id and p.tenant_id = f.tenant_id
  where f.tenant_id = '5443b130-cc28-45af-a420-cd500b288890' and f.subject_type = 'product' and f.subject_scope is null
    and coalesce(p.is_published, false) and coalesce(p.show_on_website, false) and coalesce(p.is_active, true)
  order by d.key, p.name
), shown as (
  select s.key, x.display_value
  from sample s
  cross join lateral public.get_public_product_technical_specs('5443b130-cc28-45af-a420-cd500b288890', s.subject_id) x
  where x.spec_key = s.key
)
select 1/(case when
 (select count(*) from public.spec_definitions where tenant_id is null and store_view is not null
    and is_customer_visible and nullif(btrim(store_label), '') is not null)=17
 and (select count(*) from public.spec_definitions where tenant_id is null
    and key in ('max_tire_width_mm', 'handlebar_clamp_mm', 'chainline_mm') and nullif(btrim(store_label), '') is not null)=3
 and (select count(*) from public.spec_template_fields f join public.spec_templates t on t.id = f.template_id and t.tenant_id is null
      join public.spec_definitions d on d.id = f.spec_definition_id
      where (t.key, d.key, f.store_highlight) in (
        ('fork', 'fork_tire_clearance_configurations', 1), ('fork', 'fork_kind', 2), ('fork', 'travel_mm', 3),
        ('fork', 'axle_type', 4), ('fork', 'steerer_fit', 5), ('fork', 'lockout', 6),
        ('rear_derailleur', 'rear_derailleur_application_configurations', 1), ('rear_derailleur', 'derailleur_cage_length', 2),
        ('rear_derailleur', 'rear_derailleur_mount_type', 3), ('rear_derailleur', 'derailleur_clutch', 4),
        ('front_derailleur', 'front_derailleur_clamp_options', 1), ('front_derailleur', 'front_derailleur_application_configurations', 2),
        ('front_derailleur', 'front_derailleur_cable_pull', 3), ('front_derailleur', 'front_derailleur_swing', 4),
        ('front_derailleur', 'front_derailleur_mount_type', 5),
        ('crankset', 'crank_arm_length_mm', 1), ('crankset', 'chainring_teeth_rows', 2), ('crankset', 'crankset_construction', 3),
        ('crankset', 'chainring_mounting', 4), ('crankset', 'included_chainring_count', 5),
        ('pump', 'pump_kind', 1), ('pump', 'pump_pressure_specifications', 2), ('pump', 'gauge', 3), ('pump', 'valve_heads_supported', 4)))=24
 and (select count(*) from public.spec_template_fields where store_highlight is not null)=163
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
 and (select count(distinct key) from shown where nullif(btrim(display_value), '') is not null) >= 16
 and not exists (select 1 from shown where display_value ilike '%http%' or display_value ilike '%Documento%')
 and exists (select 1 from shown where key = 'fork_tire_clearance_configurations' and display_value like 'BSD: %')
 and exists (select 1 from shown where key = 'cog_sequence' and display_value like '%dientes')
 and position('inferred' in pg_get_functiondef('public.get_public_product_technical_specs(uuid,uuid)'::regprocedure))=0
 and position('inferred' in pg_get_functiondef('public.spec_public_facet_values_internal_v1(uuid)'::regprocedure))=0
 and not exists (select 1 from public.spec_definitions where store_view is not null
   and public.spec_store_view_problem_internal_v1(store_view, validation_rules->'rows_schema') is not null)
 and public.spec_store_view_problem_internal_v1('{"format":"{x}","sort_desc":"invalid"}', '{"columns":[{"key":"x"}]}') is not null
 and not has_function_privilege('authenticated','public.spec_store_view_problem_internal_v1(jsonb,jsonb)','execute')
 and not has_function_privilege('anon','public.spec_rows_store_display_internal_v1(jsonb,jsonb,jsonb)','execute')
 and has_function_privilege('anon','public.get_public_product_technical_specs(uuid,uuid)','execute')
 then 1 else 0 end) as spec_store_row_views_ok;
