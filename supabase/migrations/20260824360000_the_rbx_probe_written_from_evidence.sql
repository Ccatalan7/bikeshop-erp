-- La sonda de RBX, escrita con lo que el reconocimiento trajo.
--
-- Nada de esto se adivinó. Corriendo el reconocimiento dentro de la sesión del
-- taller, el portal contó su propia estructura:
--
--   · Es un frameset de siete marcos. Leer sólo el documento de arriba
--     devolvía un informe vacío con la página llena a la vista — ése fue el
--     primer defecto que el propio reconocimiento encontró.
--   · El marco de resultados es GET y direccionable, con el código del
--     proveedor en `Clasificacion2`. Verificado a mano con tres códigos
--     reales: 11285 → $2.350, 12184 → $1.940, 13166 → $2.240.
--   · Sin frameset la fila sale sola: Código · Descripción · Marca · Origen ·
--     Valor. **No publica cantidad en stock**, así que de RBX se confirma
--     PRECIO y presencia en catálogo, nunca unidades. Decir «hay stock» con
--     esto sería inventar.
--   · Un código inexistente responde «No hay ningún producto que mostrar en su
--     búsqueda». Ésa es la firma que separa un cero real de un error.
--
-- El portal viaja por HTTP sin cifrar. Es una decisión del proveedor y ya
-- ocurre cada vez que el taller entra; queda registrado en cada chequeo para
-- que la interfaz pueda decirlo.
--
-- Queda deshabilitada: configurar no es autorizar. La enciende el dueño cuando
-- decida que el chequeo corra.

begin;

insert into public.supplier_portal_probes (
  tenant_id, supplier_id, search_url_template,
  logged_out_pattern, not_found_pattern, price_pattern,
  in_stock_pattern, notes, is_enabled
)
select supplier.tenant_id,
  supplier.id,
  'http://www.rburgos.cl/sitio/aplicaciones/cat_cod_cf.asp'
    || '?url=cat_cod_cf.asp&url1=cat_cod_sf.asp'
    || '&Clasificacion2={code}&folio=0&paginaabsoluta=1',
  -- Sin sesión el portal manda al formulario de ingreso. Reconocerlo es lo que
  -- impide contar un deslogueo como «sin stock».
  'INGRESA CON TUS DATOS|RUT CLIENTE|valida_ingreso',
  'No hay ning[uú]n producto que mostrar',
  '\$\s*([0-9][0-9.]*)',
  -- Que la fila exista y traiga precio es lo único que RBX afirma sobre
  -- disponibilidad. No hay columna de cantidad.
  'Agregar',
  'RBX no publica cantidad en stock: se confirma precio y presencia en catálogo. '
    || 'Portal por HTTP sin cifrar (decisión del proveedor). '
    || 'Reconocido el 2026-08-23 con los códigos 11285, 12184 y 13166.',
  false
from public.suppliers supplier
where supplier.name = 'RBX'
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
    in_stock_pattern = excluded.in_stock_pattern,
    notes = excluded.notes,
    updated_at = now();

commit;
