-- The rows schema of «Mandos que trae el envase» (shifter_units) still named
-- the side with the texts renamed on 2026-09-16 (20260916230000). No fact
-- carries shifter_units rows yet (0 in production), so the tokens change
-- without touching data. The Dart client canonicalises both spellings.
begin;
set local lock_timeout='5s';
update public.spec_definitions d
set validation_rules = replace(replace(d.validation_rules::text, '"Izquierdo / delantero"', '"Izquierdo (delantero)"'), '"Derecho / trasero"', '"Derecho (trasero)"')::jsonb,
    updated_at = now()
where d.tenant_id is null and d.key = 'shifter_units'
  and (d.validation_rules::text like '%Izquierdo / delantero%' or d.validation_rules::text like '%Derecho / trasero%');
commit;
