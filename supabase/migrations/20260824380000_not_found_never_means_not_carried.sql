-- «No encontrado» nunca significa «no lo vende».
--
-- **Corrección del dueño, 2026-08-23, verificada en el portal:** yo concluí que
-- el código `N1010` del catálogo del taller «ya no existe en MKR». Él dijo que
-- no necesariamente, que muchas veces el producto sólo está sin stock y por eso
-- no aparece. Tenía razón:
--
--   ?q=N1010             → Sin resultados
--   ?q=N1010&stock=1     → Cod: N1010 · Stock: 0 · No Disponible
--                          «Neumático Vuelta Semi Slick CB588 700x38c Negro»
--
-- El producto existe. Mi conclusión salió de una búsqueda hecha con el filtro
-- por omisión, que oculta lo agotado — y yo mismo había agregado `&stock=1` a
-- la sonda por esa razón, pero saqué la conclusión de la consulta sin él.
--
-- La regla, que vale para todos los portales y no sólo para MKR:
--
--   `not_found` significa **el portal no lo mostró**. Nunca «el proveedor no lo
--   vende» ni «está descontinuado». Un producto puede faltar de un listado por
--   estar agotado, por un filtro, por un código que cambió o por un buscador
--   que no calza exacto. Son causas distintas con acciones distintas, y una
--   sola de ellas justifica dejar de pedírselo a ese proveedor.
--
-- Donde el portal permite incluir lo agotado, la sonda DEBE usarlo: es la única
-- forma de separar «lo vende y está en cero» de «no lo mostró». Donde no lo
-- permite —RBX no publica cantidad—, un `not_found` es ambiguo y se informa
-- como ambiguo.

begin;

update public.supplier_portal_probes probe
set notes = 'MKR publica cantidad («Stock: 36»). `&stock=1` es OBLIGATORIO: sin '
      || 'él, un producto agotado no aparece y se confundiría con uno que el '
      || 'proveedor no vende. Verificado: N1010 sin el parámetro da «Sin '
      || 'resultados», y con él da «Stock: 0 · No Disponible» — el producto '
      || 'existe. El precio es la ÚLTIMA coincidencia: la ficha con descuento '
      || 'muestra «Antes $8.850» y «$6.195», y se paga la segunda.',
    updated_at = now()
from public.suppliers supplier
where supplier.id = probe.supplier_id
  and supplier.name = 'MKR Imports';

update public.supplier_portal_probes probe
set notes = 'RBX no publica cantidad en stock: se confirma precio y presencia '
      || 'en catálogo, nunca unidades. Su buscador no ofrece incluir agotados, '
      || 'así que un «no encontrado» acá es AMBIGUO —puede ser agotado, código '
      || 'cambiado o búsqueda que no calza— y se informa como tal. Portal por '
      || 'HTTP sin cifrar (decisión del proveedor). Reconocido el 2026-08-23 '
      || 'con los códigos 11285, 12184 y 13166.',
    updated_at = now()
from public.suppliers supplier
where supplier.id = probe.supplier_id
  and supplier.name = 'RBX';

comment on column public.supplier_portal_probes.not_found_pattern is
  'Cómo se ve que el portal NO mostró el producto. Es exactamente eso y nada más: no prueba que el proveedor no lo venda ni que esté descontinuado. Un agotado, un filtro o un código cambiado producen la misma pantalla.';

comment on constraint supplier_availability_checks_status_check
  on public.supplier_availability_checks is
  'not_found = el portal no lo mostró, por la causa que sea. out_of_stock = el portal lo mostró y dijo cero. session_expired = no había sesión. Confundir el primero con los otros dos hace comprar de más o dejar de pedirle a un proveedor que sí lo vende.';

commit;
