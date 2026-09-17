-- Verifier: fails (division by zero) while the global rim template still closes ETRTO or tubeless readiness to a rim whose bead profile is «Desconocido / sin confirmar», or while the requirement stopped being hooked/hookless only.
select 1/(case when exists (
 select 1 from public.spec_templates t where t.tenant_id is null and t.key='rim' and t.is_active
  and t.form_contract#>'{allowed_when,bead_seat_diameter_mm,rows,0,0,value}' @> '["Desconocido / sin confirmar","Otro","Con gancho (hooked)","Sin gancho (hookless)"]'::jsonb
  and t.form_contract#>'{allowed_when,rim_internal_width_mm,rows,0,0,value}' @> '["Desconocido / sin confirmar","Otro"]'::jsonb
  and t.form_contract#>'{allowed_when,rim_tubeless_ready,rows,0,0,value}' @> '["Desconocido / sin confirmar","Otro"]'::jsonb
  and t.form_contract#>'{allowed_when,tire_width_range_mm,rows,0,0,value}' = '["Con gancho (hooked)","Sin gancho (hookless)"]'::jsonb
  and t.form_contract#>'{required_when,bead_seat_diameter_mm,rows,0,0,value}' = '["Con gancho (hooked)","Sin gancho (hookless)"]'::jsonb
) then 1 else 0 end) as ok;
