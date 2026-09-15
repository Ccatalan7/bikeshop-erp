begin;
select no_plan();
-- A synthetic template isolates measurement domains from model applicability.
-- Real family prerequisites and OEM constraints are tested separately.
insert into public.spec_templates(id,key,name,technical_family,form_contract)
values ('99b62000-0000-4000-8000-000000000001','numeric_domain_fixture',
  'Numeric domain fixture','numeric_domain_fixture','{}');
insert into public.spec_template_fields(template_id,spec_definition_id)
select '99b62000-0000-4000-8000-000000000001',id from public.spec_definitions
where tenant_id is null and data_type='number';
create function pg_temp.numeric_issues(v jsonb) returns jsonb language sql as $$
 select public.spec_validate_draft_internal_v1('99b62000-0000-4000-8000-000000000001',v)
$$;
select is(pg_temp.numeric_issues('{"chainring_bcd_mm":58}'),'[]'::jsonb,'Sheldon Sugino MX350 BCD 58 can be recorded');
select is(pg_temp.numeric_issues('{"chainring_bcd_mm":145}'),'[]'::jsonb,'Sheldon Campagnolo BCD 145 can be recorded');
select is(pg_temp.numeric_issues('{"chainring_bcd_mm":146}'),'[]'::jsonb,'Sheldon XTR M960 BCD 146 can be recorded');
select is(pg_temp.numeric_issues('{"bb_shell_width_mm":132}'),'[]'::jsonb,'Park PF41 shell width 132 can be recorded');
select is(pg_temp.numeric_issues('{"crank_arm_length_mm":127}'),'[]'::jsonb,'crank length is not restricted to the current adult-stock range');
select is(pg_temp.numeric_issues('{"spacer_thickness_mm":0.25}'),'[]'::jsonb,'submillimetre spacer observation is representable');
select is(pg_temp.numeric_issues('{"bb_spacer_stack_mm":0}'),'[]'::jsonb,'zero spacer stack is an explicit answer');
select is(pg_temp.numeric_issues('{"rear_derailleur_total_capacity_teeth":0}'),'[]'::jsonb,'zero declared capacity remains a count');
select is(pg_temp.numeric_issues('{"chainring_offset_mm":-12,"rim_asymmetric_offset_mm":0}'),'[]'::jsonb,'signed and zero offsets are representable');
select is(pg_temp.numeric_issues('{}'),'[]'::jsonb,'missing measurements remain unknown');
select ok(jsonb_array_length(pg_temp.numeric_issues(jsonb_build_object(k,0)))>0,k||' cannot be zero')
from unnest(array['chainring_bcd_mm','bb_shell_width_mm','bearing_inner_diameter_mm',
  'hose_length_mm','rotor_thickness_mm','rim_erd_mm','spoke_length_mm',
  'sealant_volume_ml','tube_width_min_mm']) k;
select ok(jsonb_array_length(pg_temp.numeric_issues(jsonb_build_object(k,-1)))>0,k||' cannot be negative')
from unnest(array['bb_spacer_stack_mm','rear_derailleur_total_capacity_teeth',
  'tire_width_in','spindle_length_mm','rim_internal_width_mm']) k;
select ok(jsonb_array_length(pg_temp.numeric_issues(jsonb_build_object(k,14.5)))>0,k||' cannot count a fraction of a tooth/ball')
from unnest(array['smallest_cog_teeth','largest_cog_teeth','single_cog_teeth',
  'pulley_teeth','bb_ball_count_per_side','rear_derailleur_max_teeth',
  'rear_derailleur_min_teeth','rear_derailleur_total_capacity_teeth']) k;
select ok(jsonb_array_length(pg_temp.numeric_issues('{"tube_width_min_mm":37,"tube_width_max_mm":33}'))>0,'tube range order still rejects reversal');
select ok(jsonb_array_length(pg_temp.numeric_issues('{"smallest_cog_teeth":34,"largest_cog_teeth":11}'))>0,'cassette extrema still reject reversal');
select ok(jsonb_array_length(pg_temp.numeric_issues('{"bearing_inner_diameter_mm":40,"bearing_outer_diameter_mm":20}'))>0,'bearing diameters still reject reversal');
select is((select validation_rules from public.spec_definitions where key='wear_percent' and tenant_id is null),'{"min":0,"max":100}'::jsonb,'workshop percentage retains its genuine closed domain');
select * from finish();
rollback;
