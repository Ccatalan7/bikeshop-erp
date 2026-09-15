-- La sonda de MKR, también escrita con lo que el portal contó.
--
-- Reconocido en vivo el 2026-08-23, con la sesión del taller:
--
--   · Busca por SKU con `?q=` y la URL es direccionable:
--     https://mkr.cl/store/category/todos?q=P2341
--   · La ficha del resultado publica `Cod: P2341 · Stock: 36` y el precio con
--     descuento aplicado. **MKR sí entrega cantidad**, a diferencia de RBX.
--   · Por omisión el listado OCULTA lo agotado. `&stock=1` lo incluye, y es
--     obligatorio: sin eso, un producto que ese proveedor sí vende pero tiene
--     en cero se leería como «no lo vende», que es una conclusión distinta y
--     peor.
--   · Sin coincidencias responde «Sin resultados / No encontramos productos
--     para …».
--
-- **El precio es la ÚLTIMA coincidencia del patrón.** La ficha con descuento
-- muestra dos: «Antes $ 8.850» y «$ 6.195». La segunda es la que se paga.
-- Tomar la primera informaría un precio 43% más alto que el real.
--
-- Un hallazgo del reconocimiento que conviene saber: el código `N1010`, que el
-- catálogo del taller guarda para un producto de MKR, ya no existe en su
-- portal. El chequeo va a ir sacando a la luz códigos vencidos, y eso es un
-- resultado útil por sí solo — no un fallo de la sonda.
--
-- Nace deshabilitada: configurar no es autorizar.

begin;

insert into public.supplier_portal_probes (
  tenant_id, supplier_id, search_url_template,
  logged_out_pattern, not_found_pattern, price_pattern, stock_pattern,
  out_of_stock_pattern, notes, is_enabled
)
select supplier.tenant_id,
  supplier.id,
  'https://mkr.cl/store/category/todos?q={code}&stock=1',
  'ACCESO CLIENTES|INGRESAR AL CATÁLOGO|RUT EMPRESA',
  'Sin resultados|No encontramos productos para',
  '\$\s*([0-9][0-9.]*)',
  'Stock:\s*([0-9]+)',
  'Stock:\s*0\b',
  'MKR publica cantidad («Stock: 36»). `&stock=1` es obligatorio o lo agotado '
    || 'se confunde con no vendido. El precio es la ÚLTIMA coincidencia: la '
    || 'ficha con descuento muestra «Antes $8.850» y «$6.195», y se paga la '
    || 'segunda. Reconocido el 2026-08-23; el código N1010 del catálogo del '
    || 'taller ya no existe en su portal.',
  false
from public.suppliers supplier
where supplier.name = 'MKR Imports'
  and exists (
    select 1 from public.supplier_credentials credential
    where credential.supplier_id = supplier.id
      and credential.tenant_id = supplier.tenant_id
  )
on conflict (tenant_id, supplier_id) do update
set search_url_template = excluded.search_url_template,
    logged_out_pattern = excluded.logged_out_pattern,
    not_found_pattern = excluded.not_found_pattern,
    price_pattern = excluded.price_pattern,
    stock_pattern = excluded.stock_pattern,
    out_of_stock_pattern = excluded.out_of_stock_pattern,
    notes = excluded.notes,
    updated_at = now();

comment on column public.supplier_portal_probes.price_pattern is
  'Regex con UN grupo de captura. Se toma la ÚLTIMA coincidencia: una ficha con descuento muestra el precio anterior primero y el vigente después.';

commit;
