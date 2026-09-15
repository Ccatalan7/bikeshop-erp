-- Read-back: la ambigüedad de «no encontrado» quedó escrita donde se lee.
select
  1 / (case when (
    select col_description('public.supplier_portal_probes'::regclass,
      (select attnum from pg_attribute
       where attrelid = 'public.supplier_portal_probes'::regclass
         and attname = 'not_found_pattern'))
  ) like '%no prueba que el proveedor no lo venda%' then 1 else 0 end)
    as la_regla_esta_escrita,
  1 / (case when (
    select probe.notes from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'MKR Imports'
  ) like '%el producto %existe%' then 1 else 0 end) as mkr_corregido,
  1 / (case when (
    select probe.notes from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
  ) like '%AMBIGUO%' then 1 else 0 end) as rbx_declara_su_ambiguedad;
