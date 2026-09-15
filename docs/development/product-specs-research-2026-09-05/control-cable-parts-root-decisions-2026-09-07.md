# Cables y fundas: integración independiente antes de aplicar

2026-09-07. Cuatro plantillas, 29 definiciones, 36 usos y 36 casos. Candidato
sin aplicar, sin asignaciones ni llenado. La propuesta inicial y sus afirmaciones
de vacíos permanecen en el readiness como antecedente; este documento gobierna
el sucesor de root. Se preservan ocho definiciones compartidas exactamente.

## Decisiones comprobables

- **Tramo y extremo:** cada largo y diámetro de alambre vive en su tramo; cada
  extremo enlaza un ID estable. Se retiran los tres resúmenes escalares de
  función, diámetro y cabeza para evitar otra respuesta que los contradiga. El
  tramo aparece antes que sus extremos. Clase de terminación antecede a función;
  una cabeza declarada de freno no se puede declarar simultáneamente de cambio.
  La designación OEM queda abierta para una interfaz no clasificada. Los kits
  preservan cantidades por miembro y las alternativas de doble cabeza que
  requieren corte. No se afirma que cualquier perfil textual encaje con un modelo.
- **Fundas:** construcción, uso, veredicto y geometría se declaran en la misma
  fila. V-1 se cierra con el motor existente: freno más hilos longitudinales sin
  refuerzo exige registrar incompatibilidad; no admite compatible ni condicional.
  KEB con refuerzo y las fundas segmentadas conservan su propia construcción.
  Esto no convierte a toda funda reforzada en compatible con todo freno.
  Un diámetro no publicado queda pendiente, sin inventarlo; el interior es
  opcional y no puede superar al exterior cuando ambos se conocen. El largo del
  forro no se iguala al de sus segmentos metálicos.
- **Antienredos:** sus extremos también apuntan a sus propios tramos. Se añade
  rotor sin cables y se condiciona el montaje en espiga: el cable de repuesto no
  lo exige ni lo admite como propiedad propia. Una longitud OEM puede ser una
  cifra o una designación literal. Universal permanece texto de la fuente; no
  significa ausencia automática de cifra ni compatibilidad universal.
- **Reguladores:** se conservan las unidades independientes de diámetro y paso,
  la designación literal exclusiva y las compuertas AND del tipo de interfaz.
- **V-4 no era una identidad demostrada:** cantidad comercial del paquete no
  equivale a número de extremos, alternativas o filas. El helper aclara el
  alcance; no se añade una igualdad arbitraria de cardinalidad.

## Evidencia OEM y límites

[Sheldon, Cables](https://www.sheldonbrown.com/cables.html) distingue el cable de
freno/cambio y el uso de los extremos alternativos. Su exclusión bajo carga de
freno se refiere a la funda longitudinal sostenida por plástico; no a toda
construcción comercializada como sin compresión.

La ficha OEM indexada [Jagwire KEB Slick-Lube](https://www.jagwire.com/en/article/154-585/brake-housing-5mm-keb-slick-lube)
y su variante ZHB905 documentan refuerzo Kevlar, diámetro 5 mm y rollo 10 m.
La ficha indexada [Universal Sport XL UCK800](https://jagwire.com/products/diy-cable-kits/universal-sport-xl-brake-kit)
publica cable delantero 2000 mm y trasero 2500 mm, ambos incluidos. La ficha
[Mountain Elite Link 2017](https://jagwire.com/products/diy-cable-kits/2017mountain-elite-link-brake-kit)
publica un segmento de 450 mm sobre forro de 2000 mm. Son tablas del fabricante
recuperadas por el buscador; abrir directamente esas rutas devolvió error.
No se afirma vigencia de cada SKU para 2026 ni identidad con un producto del ERP.
La lectura directa no disponible se distingue de una lectura de catálogo vivo.

La página de [Odyssey M2](https://shop.odysseybmx.com/collections/odyssey-gyros/products/odyssey-m2-dual-upper-cable-black)
sí se abrió y publica 440 mm y la maneta objetivo. El perfil de su terminación
no se leyó: queda ausente y pendiente en la fixture, no se usa M2 como si fuera
una medida/perfil. [El GTX-S Pro](https://shop.odysseybmx.com/collections/odyssey-gyros/products/odyssey-gyro-gtx-s-pro-kit)
publica superior 475 mm e inferior universal. Los otros números sintéticos del
arnés no son hechos de esos modelos. No se leyó una cifra OEM de diámetro
interior, no se asigna ninguna. [Park, roscas](https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts)
justifica que diámetro y paso no comparten necesariamente unidad.

## Verificación y publicación propuesta

Preimagen viva 2026-09-08T01:41:12Z: ocho compartidas, cero colisiones. El
publicador sólo incorpora 21 definiciones, 37 opciones, cuatro plantillas y
36 usos. Backup restringido y hash verificado:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T014349Z-control-cable-metadata`.
Mismo bloqueo acotado, guardas de deriva, pin del motor y preservación de datos
que los cinco bloques aplicados. Registros de pruebas en
`.tmp/product-spec-catalog/control-cable-parts-dart.log` y
`.tmp/db/control-cable-parts-publication-tests.log`; comprobar que terminaron
correctamente antes de aplicar. Una prueba con dos celdas prohibidas explicita
ambas incidencias SQL, manteniendo idéntico el conjunto de bloqueos Dart.

No es certificación mecánica global ni prueba visual del formulario. Continúan
pendientes adopción por producto, consumidores y catálogo real. No habilita fill.

| Artefacto | SHA-256 |
|---|---|
| compile_control_cable_parts_catalog.py | `2989e19f08189c97056148f2e73d843a02781ca75f98b78f841b568e781d121e` |
| control-cable-parts-catalog-2026-09-07.json | `15a2f1d0aa97e6413cf79419f45a711e1c2cb4234dcd38ab87893bf6c83ba412` |
| control-cable-parts-cases-2026-09-07.json | `7f2aebcfd66e5c54d8abd39fd997b913f75e8f215f5a79b9409e08c9c9ccedce` |
| control-cable-parts-publication-preimage-2026-09-07.json | `0ef47fd09b3b61e01f7a873c706a7fc481365b375a5f5b9584bbd3cc4a274cf4` |
| control-cable-parts-publication-packet-2026-09-07.json | `ba73dfab4fc8e9df1617505b6ee0dbbd7af0ef31af82be65aee1fbff485de56d` |
| 20260908022000_control_cable_part_spec_templates.sql | `4ea0e59f028b0fda341699fdeb881c7eba27850ce1ed959a0dbd6e8b60897d7b` |
| 20260908022000_control_cable_part_spec_templates.sql | `a06742a3e55afe7735646701b871c8edf7d408f2208d9389aaae81f1667132b3` |
