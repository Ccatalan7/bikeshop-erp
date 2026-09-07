-- Local-only missing historical catalogue rows, not a production restore.
-- The prepared local fixture lacks these 12 numeric definitions. Their old
-- domains come from the March spec-engine seed and the August tube/BB seeds.
-- No products, prices, facts, or production identifiers are copied.
begin;
insert into public.spec_definitions
  (tenant_id,key,label,data_type,allowed_values,validation_rules)
select null,k,k,'number','[]'::jsonb,r from (values
  ('bb_spacer_stack_mm','{"min":0,"max":10}'::jsonb),
  ('hose_length_mm','{}'::jsonb),
  ('rim_erd_mm','{}'::jsonb),
  ('rim_external_width_mm','{}'::jsonb),
  ('rim_internal_width_mm','{}'::jsonb),
  ('rotor_thickness_mm','{}'::jsonb),
  ('sealant_volume_ml','{}'::jsonb),
  ('spoke_length_mm','{}'::jsonb),
  ('tube_width_min_in','{"min":0.5,"max":6}'::jsonb),
  ('tube_width_max_in','{"min":0.5,"max":6}'::jsonb),
  ('tube_width_min_mm','{"min":10,"max":120}'::jsonb),
  ('tube_width_max_mm','{"min":10,"max":120}'::jsonb)
) v(k,r) where not exists(select 1 from public.spec_definitions d
  where d.key=v.k and d.tenant_id is null);
commit;
