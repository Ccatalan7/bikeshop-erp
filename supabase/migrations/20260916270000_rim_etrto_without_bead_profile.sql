-- A rim's ETRTO (bead seat diameter × internal width) and its tubeless
-- readiness were only admitted once the bead profile was known to be hooked
-- or hookless. fill-009 (2026-09-16): Weinmann, Mavic and Race Face publish
-- the ETRTO of every rim and none of them states the bead profile, so no
-- researched rim could carry its most basic fit data. The profile field
-- already offers «Otro» and «Desconocido / sin confirmar»; those two now also
-- open the ETRTO and tubeless fields (a tubular rim still keeps them closed).
-- The requirement stays as it was: ETRTO is mandatory only once the profile is
-- hooked or hookless. The contract trigger bumps contract_version.
-- Rerunnable: the update is idempotent.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
with target as (
 select id from public.spec_templates where tenant_id is null and key='rim' and is_active
), opened as (
 select jsonb_build_object('kind','when','rows',jsonb_build_array(jsonb_build_array(jsonb_build_object(
   'field','rim_bead_profile','operator','in','value_type','token',
   'value',jsonb_build_array('Con gancho (hooked)','Sin gancho (hookless)','Otro','Desconocido / sin confirmar'))))) as gate
)
update public.spec_templates t
 set form_contract=jsonb_set(jsonb_set(jsonb_set(t.form_contract,
   '{allowed_when,bead_seat_diameter_mm}',o.gate,true),
   '{allowed_when,rim_internal_width_mm}',o.gate,true),
   '{allowed_when,rim_tubeless_ready}',o.gate,true),
  updated_at=now()
 from target, opened o
 where t.id=target.id
  and (t.form_contract#>'{allowed_when,bead_seat_diameter_mm}' is distinct from o.gate
    or t.form_contract#>'{allowed_when,rim_internal_width_mm}' is distinct from o.gate
    or t.form_contract#>'{allowed_when,rim_tubeless_ready}' is distinct from o.gate);
commit;
