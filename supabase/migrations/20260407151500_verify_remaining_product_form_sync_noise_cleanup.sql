-- READ-ONLY verification after running
-- 20260407151000_cleanup_remaining_product_form_sync_noise.sql.
--
-- Expected result: no rows.

select
  sa.id,
  sa.created_at,
  p.name as product_name,
  sa.reason
from public.stock_adjustments sa
left join public.products p
  on p.id = sa.product_id
 and p.tenant_id = sa.tenant_id
where sa.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and sa.id in (
    'f13c64f0-eb36-4393-ba3a-835e314b4212',
    '624e613e-0c12-4091-b3ec-ab4d373797c1',
    'f56f2212-f738-4d2f-8285-9cc6f8d9c8d7'
  );