-- Read-back: la sonda de RBX existe, busca por código, sabe reconocer una
-- sesión caída y NO afirma cantidades que el portal no publica.
select
  1 / (case when (
    select count(*) from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
  ) = 1 then 1 else 0 end) as sonda_de_rbx,
  1 / (case when (
    select search_url_template from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
  ) like '%Clasificacion2={code}%' then 1 else 0 end) as busca_por_codigo,
  -- Sin esto, un portal deslogueado se contaría como «sin stock» y haría
  -- comprar de más.
  1 / (case when (
    select logged_out_pattern from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
  ) is not null then 1 else 0 end) as reconoce_sesion_caida,
  -- RBX no publica cantidad: la sonda no puede pretender leerla.
  1 / (case when (
    select stock_pattern from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
  ) is null then 1 else 0 end) as no_inventa_cantidad,
  -- Configurar no es autorizar: la enciende el dueño.
  1 / (case when (
    select not is_enabled from public.supplier_portal_probes probe
    join public.suppliers supplier on supplier.id = probe.supplier_id
    where supplier.name = 'RBX'
  ) then 1 else 0 end) as nace_apagada;
