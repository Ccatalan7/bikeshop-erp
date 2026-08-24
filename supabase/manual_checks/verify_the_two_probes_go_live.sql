select
  1 / (case when (
    select count(*) from public.supplier_portal_probes where is_enabled
  ) = 2 then 1 else 0 end) as exactamente_dos_encendidas,
  1 / (case when (
    select count(*) from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where probe.is_enabled
      and supplier.name not in ('RBX', 'MKR Imports')
  ) = 0 then 1 else 0 end) as ninguna_sin_reconocer;
