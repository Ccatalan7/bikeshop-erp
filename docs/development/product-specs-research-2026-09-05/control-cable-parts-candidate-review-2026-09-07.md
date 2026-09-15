# Cables y fundas — dictamen independiente (2026-09-07)

Lectura y veredicto sobre el sucesor de root, que sustituye mi propuesta
inicial. No edité candidatos, motor, migración, base ni el bloque hidráulico.
Las sondas corrieron contra el catálogo **sin modificar**, con archivos de casos
propios en el scratchpad.

**Veredicto: publicable.** Las diecisiete afirmaciones comprobables del
documento se sostienen, medidas una por una. **No encontré ningún hallazgo
nuevo.** Lo que sí encontré es un error mío que conviene dejar escrito.

## Integridad

Los siete SHA-256 recomputados coinciden exactamente con los declarados:

| Artefacto | SHA-256 verificado |
|---|---|
| `compile_control_cable_parts_catalog.py` | `2989e19f08189c97056148f2e73d843a02781ca75f98b78f841b568e781d121e` |
| `control-cable-parts-catalog-2026-09-07.json` | `15a2f1d0aa97e6413cf79419f45a711e1c2cb4234dcd38ab87893bf6c83ba412` |
| `control-cable-parts-cases-2026-09-07.json` | `7f2aebcfd66e5c54d8abd39fd997b913f75e8f215f5a79b9409e08c9c9ccedce` |
| `control-cable-parts-publication-preimage-2026-09-07.json` | `0ef47fd09b3b61e01f7a873c706a7fc481365b375a5f5b9584bbd3cc4a274cf4` |
| `control-cable-parts-publication-packet-2026-09-07.json` | `ba73dfab4fc8e9df1617505b6ee0dbbd7af0ef31af82be65aee1fbff485de56d` |
| `20260908022000_...sql` (migración) | `4ea0e59f028b0fda341699fdeb881c7eba27850ce1ed959a0dbd6e8b60897d7b` |
| `20260908022000_...sql` (verificador) | `a06742a3e55afe7735646701b871c8edf7d408f2208d9389aaae81f1667132b3` |

**40 pruebas Dart: las corrí yo, pasan.** Aritmética: 21 definiciones nuevas +
8 reutilizadas = 29; 37 opciones; 4 plantillas; 36 usos. Coincide.

Superficie de escritura sólo sobre las cuatro tablas de metadatos y pin del
motor `ac0738d5c2039412b603dc71adc41721`, el mismo de los bloques aplicados.

**Las ocho compartidas están preservadas**, y lo verifiqué por dos caminos: son
`cable_diameter_mm`, `cable_length_mm`, `color`, `kit_members`, `material`,
`pack_quantity`, `spec_evidence_source` y `steerer_fit`; viajan en
`reused_definitions` y **no** en los registros nuevos. Comparado con el
congelado, sólo dos definiciones cambian: `control_cable_end_options` y
`detangler_kind`. Ambas son de **una sola familia** y comprobé por lectura de
producción que **ninguna existe allí**; el cambio en `detangler_kind` es
puramente aditivo — añade `Rotor sin cables` a las cuatro opciones previas.

Confirmado también lo pequeño y comprobable: el tramo aparece antes que sus
extremos (`control_cable_runs` en 70 y sus extremos en 80; los del gyro en 50 y
60), y **no se añadió ninguna cardinalidad**, coherente con retirar V-4.
La prueba con dos celdas prohibidas existe y explicita ambas incidencias SQL en
`cc_undeclared_member_cannot_carry_a_length`; verifiqué su forma, no su verdad,
porque no corrí el lado SQL.

## Dieciséis sondas

Cada sonda predecía un resultado exacto y las dieciséis acertaron.

| Sonda | Resultado |
|---|---|
| freno + longitudinal sin refuerzo + «Compatible» | **bloquea** `row_value_conflict` |
| lo mismo con «Condicional» y una condición escrita | **bloquea** |
| lo mismo con «Incompatible declarado» | limpio — es lo único registrable |
| KEB con refuerzo, freno, 5 mm, con forro | limpio — el producto real se registra |
| longitudinal **sin** refuerzo para **cambio** | limpio — la exclusión es de carga de freno |
| segmentada para freno | limpio — conserva su construcción |
| interior 6 mm con exterior 5 mm | **bloquea** `row_shape` |
| diámetro «No publicado» cargando una cifra | **bloquea** `row_field_applicability` |
| forro 2000 mm con segmento 450 mm | limpio — no se igualan |
| largo de forro sin forro declarado | **bloquea** |
| cabeza de freno declarada de cambio | **bloquea** `row_value_conflict` |
| doble punta: dos extremos alternativos en un tramo | limpio |
| extremo de cable apuntando a un tramo inexistente | **bloquea** `row_reference_unresolved` |
| lo mismo en el **gyro** | **bloquea** — el enlace también rige allí |
| tramo «universal» que sí publica 440 mm | limpio — universal no borra la cifra |
| rotor sin cables como tipo propio | limpio |

## Una precisión sobre pendiente y bloqueo

Añadí una sonda decimoséptima porque la compuerta de V-1 necesita la
construcción **confirmada** para dispararse, y quería medir qué pasa antes de
eso. Una fila de freno declarada «Compatible» con la construcción todavía en
blanco no bloquea: emite `row_value_pending`, no bloqueante.

Eso es lo correcto y no es una vía de escape. La pregunta queda **abierta y
visible** hasta que se responda, y en el momento en que se responda «sin
refuerzo» la fila pasa a bloquear. Conviene decirlo con precisión porque es
fácil leerlo al revés: un `row_value_pending`, un `row_incomplete` o un
`row_required_missing` marcan una fila **pendiente**, nunca un guardado
rechazado. Sólo las incidencias bloqueantes impiden cerrar.

## El error fue mío, y vale la pena escribirlo

Declaré V-1 inexpresable «sin tocar el motor», y me equivoqué. Lo planteé como
una desigualdad entre dos **escalares** —construcción y uso— y de ahí concluí que
hacía falta una negación que los seis operadores no tienen. La salida no era un
operador nuevo: era poner construcción, uso y veredicto **en la misma fila**,
donde `value_when` sí opera, y convertir la prohibición en una igualdad positiva
sobre la celda de veredicto. Es la segunda vez en esta ronda que el arreglo
correcto fue mover el ámbito y no ampliar la gramática —la primera fue SH-1 en
suspensión, con el antecedente partido en `anchor_contact`—. Lo dejo escrito
porque el patrón se me repitió: **antes de declarar algo inexpresable, comprobar
en qué ámbito viven la propiedad y su antecedente.**

## Alcance de las fuentes, tal como lo declara el documento

El documento distingue con cuidado dos cosas que suelen confundirse, y la
distinción es correcta: las fichas de Jagwire —KEB Slick-Lube y su variante
ZHB905, Universal Sport XL UCK800 con 2000/2500 mm, Mountain Elite Link con
segmento de 450 mm sobre forro de 2000 mm— son **tablas OEM recuperadas por el
buscador**, y abrir esas rutas directamente falló. No es lo mismo que una
lectura de catálogo vivo, y el documento no lo presenta como tal. Las dos
páginas de Odyssey —M2 con 440 mm y GTX-S Pro con superior 475 mm e inferior
universal— **sí se abrieron**.

Coincide con lo que yo mismo pude y no pude leer en mi ronda: la tienda de
Odyssey se abrió, `jagwire.com/products/...` devolvió 404 y `www.jagwire.com/en/article/...`
sí se abrió. Dos límites que el documento asume explícitamente y comparto: el
perfil de terminación del M2 no se leyó y queda **ausente y pendiente** en la
fixture en vez de inventarse, y no hay ninguna cifra OEM de diámetro interior,
así que no se asigna ninguna. Los demás números del arnés son sintéticos y están
declarados como tales.

Sobre Sheldon, la lectura del documento es más precisa que la mía: su exclusión
bajo carga de freno se refiere a la funda longitudinal sostenida por plástico, no
a toda construcción vendida como sin compresión. Esa precisión es justamente la
que hace que KEB con Kevlar quede fuera de la prohibición y siga siendo
registrable, y las sondas lo confirman en las dos direcciones.

## Lo que no verifiqué

No corrí los 36 casos SQL, las cinco pruebas del publicador ni los registros en
`.tmp/product-spec-catalog/control-cable-parts-dart.log` y
`.tmp/db/control-cable-parts-publication-tests.log`; el documento pide comprobar
que terminaron correctamente antes de aplicar, y eso sigue pendiente de tu lado.
No consulté la preimagen viva de las 01:41:12Z, el respaldo
`20260908T014349Z-control-cable-metadata` ni el estado de aplicación. No abrí de
nuevo las fichas de Jagwire ni las de Odyssey en esta ronda.

Nada de esto es aprobación mecánica. El esquema ahora **representa** estas
declaraciones y **se niega a contradecirse**; que una funda concreta aguante una
maneta concreta sigue siendo una afirmación del fabricante, no del motor.
