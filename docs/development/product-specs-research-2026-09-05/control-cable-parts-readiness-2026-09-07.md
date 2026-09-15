# Control cable parts — sucesor acotado (2026-09-07)

Familias: `control_cable`, `control_housing`, `control_small_part`,
`bmx_cable_detangler`. Candidato. `mechanical_coverage_complete` y
`automatic_fill_authorized` en `false`; sin hechos, sin asignaciones, sin
migración, sin cambios de motor.

**Estas cuatro familias no quedan saneadas.** Abajo van, separados, los cuatro
defectos corregidos y los seis vacíos que siguen abiertos, uno de ellos
inexpresable con el motor actual.

## Entradas y alcance real de la escritura

Congelados verificados por hash en tiempo de compilación:
catálogo `16459826…f15`, casos `329ad3e5…6d7`. Cero casos heredados.

Diferencia medida contra el catálogo congelado — no declarada, computada:

| | |
|---|---|
| Definiciones **añadidas** | `control_adjuster_threads`, `control_cable_runs`, `detangler_cable_configurations` (las tres de una sola familia) |
| Definiciones **modificadas** | `control_cable_end_options` — `used_by = ['control_cable']`, ausente de producción |
| Compartidas **byte a byte idénticas** | `cable_length_mm` (2 usos), `cable_diameter_mm` (2), `kit_members` (23), `pack_quantity` (19), `compatible_brake_models` (5) |

Lecturas de sólo lectura en producción: las cuatro plantillas están ausentes;
`adjuster_thread`, `detangler_kind` y `fits_housing_diameter_mm` no existen;
`cable_length_mm`, `cable_diameter_mm` y `kit_members` están publicadas con cero
hechos; **`lock` está publicada** y es la otra dueña viva de los dos escalares de
cable. El retiro de `cable_length_mm` es de plantilla: su rol pasa a `legacy` en
`control_cable` y la definición queda intacta, con sus dos usos. Es el patrón que
el paquete de suspensión demuestra documentalmente, donde `thru_axle_thread`,
`inner_diameter_mm` y `thickness_mm` viajan en `reused_definitions` y no en los
registros nuevos.

## Corregido

### CC‑1 — el regulador exigía una respuesta que la propia ficha llama insuficiente

`adjuster_thread` ofrecía `M6`, `M10` y desconocido, y era **obligatorio** para el
regulador de barril, mientras el helper de la misma plantilla dice que una rosca
nominal sin paso no identifica un regulador. Un `M6` pelado es valor conocido
para el motor: no dejaba la pregunta abierta, la callaba.

Park publica designaciones como `10 mm x 26 TPI`, de modo que la unidad del
diámetro no determina la forma del paso. Reemplazado por
`control_adjuster_threads`, con la forma de fila ya adjudicada en
`wheel_part_interfaces`: `diameter_unit` y `pitch_unit` independientes, cada una
abriendo sólo su celda, más `designation` para lo publicado sin descomponer.
`adjuster_thread` queda `legacy`.

### CC‑2 — el gyro tenía dos tramos y ningún lugar donde ponerlos

Evidencia OEM de la tienda de Odyssey: el kit G3 incluye superior de **425 mm**,
el GTX‑S Pro superior de **475 mm**, y los inferiores se venden sin largo, como
que calzan en la mayoría de los sistemas. O sea: dos kits con cifras distintas, y
**un miembro que no publica largo**. El único contenedor era `kit_members`, cuyas
posiciones son Delantero/Trasero/Izquierdo/Derecho; publicada y usada por 23
familias, no se toca.

`detangler_cable_configurations` es local a la familia. La columna
`configuration` es lo que impide que dos conjuntos se lean como un solo lote
intercambiable.

**Corrección por contraejemplo:** Odyssey vende un *M2 Dual Upper Cable*, así que
un conjunto puede llevar **dos tramos en la misma posición**. Por eso no se puso
`unique_by` sobre (conjunto, posición): habría rechazado un producto real. El
caso `cc_gyro_dual_upper_is_two_runs_same_position` lo fija.

### CC‑3 — un juego de cables no podía llevar un largo por miembro

`control_cable.cable_length_mm` era un escalar único y siempre obligatorio. Se
retira su uso en esta plantilla y entra `control_cable_runs`: una fila por tramo,
con `length_form` (`Declarado` / `No declarado / universal`) abriendo largo,
unidad y referencia. La forma explícita es lo que distingue «el fabricante no
publica largo» de «nadie lo ha buscado todavía».

**Extremos enlazados al tramo.** Se añade la columna `run_row_id` a
`control_cable_end_options` y un `row_coherence.links` que la resuelve contra
`control_cable_runs` por id de fila. Con eso las tres formas conviven sin
cruzarse:

- **Cable simple**: un tramo, sus extremos apuntando a él.
- **Doble punta**: **un** tramo con **dos** extremos alternativos — Sheldon
  publica los dos terminales de freno y dice que el alambre de doble punta
  «must be cut before it can be used», así que nunca sirven a la vez.
- **Juego**: un tramo por miembro, cada uno con su largo y sus terminaciones.

Alcance honesto de la garantía: el enlace obliga a **atribuir** cada extremo a un
tramo y bloquea con `row_reference_unresolved` si apunta a uno inexistente. No
puede saber si una atribución es semánticamente equivocada; lo que elimina es que
la atribución quede implícita.

### CC‑4 — retiré un caso mío que blindaba la combinación equivocada

En la entrega anterior fijé que `Freno` + `Hilos longitudinales sin refuerzo` era
registrable, razonando por mi cuenta que existían fundas sin compresión modernas
para freno. Al leer Jagwire resultó que su funda sin compresión de freno
(«Brake Housing 5mm KEB Slick‑Lube») es **con refuerzo**: son «linear steel
strands around a Slick-Lube liner and wrapped in a Kevlar weave». El refuerzo es
justo la propiedad que la separa de la funda de cambio que Sheldon prohíbe en
frenos — y el vocabulario congelado ya distinguía con refuerzo de sin refuerzo.

Ese caso queda **eliminado** y sustituido por
`cc_reinforced_compressionless_brake_housing`, anclado a Jagwire con sus 5 mm. La
combinación sin refuerzo + freno queda **sin blindar y abierta** (ver V‑1).

## Vacíos abiertos

- **V‑1 (inexpresable).** «Funda de hilos longitudinales **sin** refuerzo
  declarada para freno» es la contradicción que Sheldon nombra, y Jagwire no la
  cubre. No se puede expresar: es una restricción de desigualdad entre dos
  escalares, `value_when` es sólo de celda de fila y compara con `eq` contra un
  único valor esperado (`product_spec_row_conditions.dart:168-172`), y el parser
  de la ficha admite seis operadores sin negación. Cerrarla exige tocar el motor,
  que está fuera de alcance. Hoy sólo la frena el helper. **No la tapé con una
  regla aproximada ni con un caso verde.**
- **V‑2.** Las cifras del juego de `control_cable` (800/1700 mm) siguen siendo
  **sintéticas**. La estructura sí está respaldada por Odyssey, pero las páginas
  de kit de Jagwire publican sólo «extra-long inner cables and ample housing», sin
  largo por miembro, y `bike.shimano.com` devolvió **403** en sus dos fichas de
  juego de cable de freno. Ninguna cifra de Shimano entró en nada.
- **V‑3.** Los tramos del detangler no tienen modelo de terminaciones:
  `control_cable_end_options` es exclusiva de `control_cable`.
- **V‑4.** `pack_quantity` podría atarse al número de tramos con
  `row_coherence.cardinalities`, pero está compartida por 19 familias y no
  verifiqué que signifique «cantidad de miembros» en todas. No lo hice.
- **V‑5.** `housing_outer_diameter_mm` sigue siendo obligatorio siempre mientras
  `housing_length_m` y `lined` no lo son. Sin examinar.
- **V‑6.** No leí ninguna ficha OEM de detangler distinta del listado de tienda
  de Odyssey, ni ninguna que publique el diámetro **interior** de una funda; por
  eso no se añadió ese campo.

Considerado y descartado: renombrar la opción `Doble cabeza (universal)`. El
helper ya desactiva la lectura de «universal» como permiso, la palabra es la del
envase, y root aceptó el campo esta ronda.

## Verificación

`test/unit/product_spec_integrated_catalog_test.dart` parametrizado:
**25 pruebas, todas verdes** — 4 de metadatos y 21 casos de representación.

El verde solo no prueba nada, así que muté el candidato: quitar la cláusula padre
AND‑ada de cada compuerta de fila hace fallar exactamente
`cc_adjuster_literal_cannot_carry_a_pitch_figure`, con
`Expected: ['row_field_applicability:control_adjuster_threads'], Actual: []`. El
arnés compara el conjunto de bloqueos de forma **exacta**, así que los casos que
esperan «sin bloqueo» son afirmaciones reales.

Correcciones que impuso el motor, comprobadas en código y no supuestas: una celda
de fila **estáticamente** obligatoria la reclama `rows.missingRequired` y sale
como `row_incomplete` no bloqueante, no como `row_required_missing`; y `lined` es
booleano, no un texto «Sí».

## Hashes

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_control_cable_parts_catalog.py` | `3cb30cd2bd0434e5428acf4fd7aeaa17b4f1e7876b7721281e228ba4428a257b` |
| `control-cable-parts-catalog-2026-09-07.json` | `04757bf4959ff4c2102a67f05464d3fbc2336211156f10d542ba5a4dd5500aba` |
| `control-cable-parts-cases-2026-09-07.json` | `cee5d803b121955bc86f60d7b904dfc22bf70919a4cd7ca705c7ffc334d6be58` |

Totales: 4 plantillas, 27 definiciones, 34 usos de campo, 21 casos.

## Fuentes

- Sheldon Brown, *Cables* — https://www.sheldonbrown.com/cables.html
- Park Tool, *Basic Thread Concepts* —
  https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts
- Jagwire, *Brake Housing 5mm KEB Slick-Lube* —
  https://www.jagwire.com/en/article/154-585/brake-housing-5mm-keb-slick-lube
- Odyssey, *Gyros®* — https://shop.odysseybmx.com/collections/odyssey-gyros

No legibles esta ronda, y por tanto sin uso: `bike.shimano.com` (403 en las dos
fichas de juego de freno), las tres rutas de Park sobre cable y funda (404),
`jagwire.com/products/housing/...` (404) y la ficha de producto de la tienda de
Odyssey para el cable superior doble (404); el dato del superior doble proviene
del listado de la propia tienda de Odyssey, ya citado. No se usaron minoristas.
