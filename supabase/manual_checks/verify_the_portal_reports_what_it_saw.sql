-- Read-back: el dominio raíz une login y catálogo, y la RPC existe para el
-- módulo pero no para anónimos.
select
  1 / (case when public.registrable_domain_internal_v1('https://portal.rburgos.cl')
    = public.registrable_domain_internal_v1('http://www.rburgos.cl/sitio/aplicaciones/seleccion.asp')
    then 1 else 0 end) as rbx_es_el_mismo_proveedor,
  1 / (case when public.registrable_domain_internal_v1('https://mkr.cl')
    = 'mkr.cl' then 1 else 0 end) as dominio_simple,
  1 / (case when public.registrable_domain_internal_v1('https://mkr.cl')
    <> public.registrable_domain_internal_v1('https://derman.cl')
    then 1 else 0 end) as no_confunde_proveedores,
  1 / (case when has_function_privilege('authenticated',
    'public.record_supplier_portal_discovery_v1(text,jsonb)', 'execute')
    then 1 else 0 end) as modulo_ejecuta,
  1 / (case when not has_function_privilege('anon',
    'public.record_supplier_portal_discovery_v1(text,jsonb)', 'execute')
    then 1 else 0 end) as anon_no_ejecuta;
