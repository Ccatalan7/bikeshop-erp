-- Verifier: fails (division by zero) while the ISO diameter definition still carries the engineer's label.
select 1/(case when (select count(*) from public.spec_definitions where tenant_id is null and key='bead_seat_diameter_mm' and label='Aro (diámetro ISO)')=1
             and (select count(*) from public.spec_definitions where tenant_id is null and key='bead_seat_diameter_mm' and label='Diámetro ISO (BSD)')=0 then 1 else 0 end) as ok;
