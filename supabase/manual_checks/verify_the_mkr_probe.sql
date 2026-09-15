select
  1 / (case when (
    select count(*) from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'MKR Imports'
  ) = 1 then 1 else 0 end) as sonda_de_mkr,
  -- Sin `stock=1` lo agotado se confundiría con no vendido.
  1 / (case when (
    select search_url_template from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'MKR Imports'
  ) like '%stock=1%' then 1 else 0 end) as incluye_lo_agotado,
  -- MKR sí publica cantidad; RBX no. Cada sonda dice sólo lo que su portal da.
  1 / (case when (
    select stock_pattern from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'MKR Imports'
  ) is not null then 1 else 0 end) as mkr_lee_cantidad,
  1 / (case when (
    select stock_pattern from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
  ) is null then 1 else 0 end) as rbx_no_la_inventa,
  1 / (case when (
    select count(*) from public.supplier_portal_probes where is_enabled
  ) = 0 then 1 else 0 end) as ninguna_encendida_todavia;
