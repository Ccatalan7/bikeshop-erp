-- El motor publica el costo con flete y sin flete, y no son el mismo número.
select
  (item->>'supplierName') proveedor,
  (item->>'averageLandedUnitCostNet')::numeric con_flete,
  (item->>'averageBaseUnitCostNet')::numeric sin_flete,
  (item->>'averageLandedUnitCostNet')::numeric
    >= (item->>'averageBaseUnitCostNet')::numeric con_flete_no_es_menor
from (
  select public.purchase_supplier_concentration_internal_v1(
    '5443b130-cc28-45af-a420-cd500b288890',
    'Cámaras 29 con válvula Schrader', null, null, 6) page
) probe
cross join lateral jsonb_array_elements(page->'items') item
limit 6;
