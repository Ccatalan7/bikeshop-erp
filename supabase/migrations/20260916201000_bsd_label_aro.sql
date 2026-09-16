-- The tyre, tube, rim and rim strip diameter is now populated (20260916200000)
-- and the storefront prints it as the commercial wheel size («29" / 700c
-- (ISO 622)»). The field label follows the shop's word: «Aro».
-- Rerunnable: only the old label is touched.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
update public.spec_definitions
   set label = 'Aro (diámetro ISO)', updated_at = now()
 where tenant_id is null and key = 'bead_seat_diameter_mm' and label = 'Diámetro ISO (BSD)';
commit;
