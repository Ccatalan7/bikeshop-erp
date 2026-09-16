# Filtros técnicos en la tienda — 2026-09-16

La ficha ya tenía 109 campos marcados «filtrable» y visibles al cliente, y ningún consumidor:
la tienda filtraba por categoría, disponibilidad, marca y precio. Desde hoy el cliente que abre
«Cámaras» filtra por tipo de válvula y largo de válvula; en neumáticos por aro y ancho; en
cassettes por velocidades y piñón mayor; en rayos por largo. Cada filtro muestra cuántos
productos quedan con cada opción.

## Qué se desplegó (migración `20260916210000_public_spec_facets.sql`)

- `spec_public_facet_values_internal_v1(tenant)`: los valores por los que un visitante puede
  filtrar. Sólo definiciones filtrables y visibles al cliente de la plantilla resuelta del
  producto (vínculo explícito o por categoría), de tipo opción, número o sí/no; nunca un campo
  `legacy` del contrato ni una inferencia sin confirmar. Números sin ceros de cola, booleanos
  como «Sí»/«No», opciones por su rótulo. El rótulo sale del contrato de la plantilla y, si no
  lo nombra, de la definición: lo mismo que ve el cliente en la ficha.
- `spec_public_facet_matches_internal_v1(tenant, filtros, clave_excluida)`: los productos que
  cumplen **todas** las claves pedidas (`{"valve_standard": ["Francesa (Presta)"]}`; dentro de
  una clave cualquier valor sirve). La clave excluida permite contar las alternativas de un
  filtro ya activo, como hace la faceta de marca.
- `get_public_products_faceted_v2` y `get_public_product_facets_v2`: las mismas firmas de v1
  más `p_spec_filters jsonb`. El snapshot devuelve una fila por valor con
  `facet_key = 'spec:<clave>:<tipo>:<unidad>'`, `value_id` = valor, `value_label` = rótulo del
  campo, `item_count` = productos con ese valor, `range_min` = productos del alcance que tienen
  el campo, `range_max` = productos del alcance. v1 queda intacta para clientes anteriores.
- Permisos como v1: `anon` y `authenticated` ejecutan las fachadas; `service_role`, `public` y
  cualquier rol ajeno no; los dos núcleos son privados.
- De paso, «Largo nominal de esta variante de rayo» pasa a «Largo del rayo» en la definición y
  en el contrato de «Rayo / Spoke» (era el único rótulo filtrable escrito para el motor).

pgTAP: `supabase/tests/public_catalog_facets.sql` suma 11 pruebas (66 en total): firmas y
permisos, y un escenario sembrado (válvula, largo con rótulo de contrato, un número privado, un
campo retirado, una inferencia sin confirmar) que fija qué se lista, cómo cuenta, que un filtro
no estrecha sus propias alternativas, que dos claves se exigen a la vez, que una clave privada o
retirada no filtra ni por nombre y que sin filtros v2 pagina exactamente lo que v1.

Lectura en producción antes de aplicar (transacción revertida, como `anon`): la categoría
«Cámaras» ofrece válvula (Auto 18 / Francesa 5) y largo (48 mm 14, 60 mm 3, 35 y 33 mm 1);
con «Francesa (Presta)» activa, la página baja de 23 a 5 cámaras y los largos a 48 mm 2 /
60 mm 2. Sin filtro, v2 y v1 devuelven las mismas 23.

## El aro de la cámara sale de sus filas (`20260916220000_public_spec_facets_tube_rows.sql`)

La primera versión ofrecía «Aro» en neumáticos (campo escalar `bead_seat_diameter_mm`) y no en
cámaras, que lo declaran dentro de «Aro y ancho de neumático» (una fila por diámetro ISO con el
rango de ancho). El núcleo de valores proyecta ahora una celda numérica de un campo de filas
sobre el campo global filtrable del mismo nombre: la celda `bead_seat_diameter_mm` de la cámara
filtra igual que el escalar del neumático, bajo el mismo rótulo y con la misma redacción («26"
(ISO 559)»). La proyección es genérica (cualquier columna de filas nombrada como un campo
numérico global filtrable) y conserva las exclusiones del camino escalar. Lectura en producción
antes de aplicar, como `anon`: «Cámaras» ofrece 622 → 9, 559 → 8, 584 → 2, 406 → 1, 203 → 1
(21 de 23 cámaras con aro) y el filtro 559 deja 8 cámaras. pgTAP: una fila sembrada proyecta su
valor sobre el campo que nombra y filtra como él (67 pruebas verdes).

## Cómo lo ve el cliente (se despliega con el merge)

- Los filtros técnicos aparecen debajo de «Marca» cuando la presentación muestra marcas y al
  final del riel si no (la presentación de «Cámaras» sólo muestra categorías, y la primera
  versión los ataba a la marca: no salían), cada uno con su rótulo de tienda, sus opciones con
  conteo (las medidas en orden de tamaño, las opciones por cantidad) y «Ver N opciones más»
  pasadas seis. Son presentación de la página, no una faceta guardada de la categoría: el editor
  no tiene que activarlos y no roban ninguna semántica almacenada (`WebsiteCatalogFacet` sigue
  siendo categorías, disponibilidad, marca y precio). Comprobado en la vista previa release
  contra producción: «Cámaras» ofrece válvula (Auto 18 / Francesa 5), aro (12½" a 29") y largo
  de válvula (33 a 60 mm); marcar «Francesa (Presta)» deja 5 cámaras con su chip activo, y la
  URL `?spec.valve_standard=Francesa (Presta)` reproduce ese estado.
- Un filtro se ofrece cuando describe la colección que el cliente mira: al menos el 30 % de los
  productos del alcance lo tienen (en «Cámaras» la válvula está en todas; en la portada, con 596
  productos, la válvula describe un rincón y no aparece), o cuando ya tiene un valor elegido.
  Máximo ocho, los de mayor cobertura primero; uno con una sola opción no se ofrece.
- Valores en palabras de tienda (`lib/public_store/utils/public_spec_display.dart`): el diámetro
  ISO como rodado («29" / 700c (ISO 622)»), el ancho de neumático en pulgadas desde 1.5"
  («2.1" · 53 mm», «2.125" · 54 mm») y en milímetros por debajo («25 mm»), los números con su
  unidad una sola vez. La ficha de producto usa la misma redacción.
- La URL lleva el filtro (`?spec.valve_standard=Francesa%20(Presta)`), así que un enlace
  compartido o un «atrás» del navegador conserva la selección; los chips de filtros activos y
  «Limpiar filtros» los incluyen. Las claves de la URL se validan (`[a-z0-9_]`) antes de llegar
  a la RPC.

## Qué queda

- Los números con muchas opciones (largo de rayo: 23 valores; ancho de neumático: 22) salen
  como lista con conteo. Un rango deslizable sería mejor para el ancho; la lista ya vende.
- El ancho de neumático que admite una cámara (`tube_fit_rows`, ancho mínimo y máximo) no
  filtra: la cámara filtra por aro, válvula y largo de válvula.
- Rótulos filtrables con mayúsculas de sistema viejo («Tipo de Tubo de Dirección», «Estándar de
  Montaje») viven en campos `legacy` de sus plantillas y no llegan al cliente; si alguno vuelve a
  un contrato vivo, se relabela antes.
