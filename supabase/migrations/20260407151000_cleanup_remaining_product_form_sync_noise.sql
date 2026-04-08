-- Cleanup the remaining confirmed standalone phantom manual-adjustment rows
-- caused by the pre-fix product-form inventory_qty/stock_quantity drift.
--
-- Safety:
-- - Deletes ONLY the 3 exact stock_adjustments rows confirmed via read-only inspection.
-- - Deletes ONLY their matching manual stock_movements rows at the same timestamp.
-- - Does NOT touch any real manual adjustments outside these exact IDs.

begin;

create temp table tmp_remaining_product_form_sync_noise_adjustments on commit drop as
select *
from public.stock_adjustments
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and id in (
    'f13c64f0-eb36-4393-ba3a-835e314b4212',
    '624e613e-0c12-4091-b3ec-ab4d373797c1',
    'f56f2212-f738-4d2f-8285-9cc6f8d9c8d7'
  );

create temp table tmp_remaining_product_form_sync_noise_movements on commit drop as
select sm.*
from public.stock_movements sm
join tmp_remaining_product_form_sync_noise_adjustments sa
  on sm.tenant_id = sa.tenant_id
 and sm.product_id = sa.product_id
 and sm.created_at = sa.created_at
 and coalesce(sm.movement_type, '') = 'manual'
 and coalesce(sm.notes, '') = coalesce(sa.reason, '')
 and coalesce(sm.reference, '') = coalesce(sa.reference, '');

delete from public.stock_movements sm
using tmp_remaining_product_form_sync_noise_movements doomed
where sm.id = doomed.id;

delete from public.stock_adjustments sa
using tmp_remaining_product_form_sync_noise_adjustments doomed
where sa.id = doomed.id;

commit;