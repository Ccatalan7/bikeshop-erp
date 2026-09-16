# Volantes, bielas y platos: candidato sin aplicar — 2026-09-08

**Publicado el 2026-09-16** como `20260916070000_crank_drive_successors.sql` sobre 57 productos; ver [crank-drive-successors-adjudication-2026-09-16.md](crank-drive-successors-adjudication-2026-09-16.md).

Sucesor local para las tres últimas originales sin sucesor: `crankset`,
`crank_arm` y `chainring`. **No aplicado.** Sin escrituras de producción,
migración, publicación, asignaciones ni llenado; sin SQL local, commit, push ni
runtime; sin tocar motor, GUI, migraciones ni el checkpoint global. Este
documento contiene sólo agregados, metadatos y ejemplos OEM públicos.

## 1. Entradas fijadas y salida

| entrada | sha256 |
|---|---|
| `all-family-port-cardinality-integrated-2026-09-07.json` | `16459826…fadf15` |
| `all-family-port-cardinality-cases-integrated-2026-09-07.json` | `329ad3e5…3716d7` |
| `existing-crank-drive-preimage-2026-09-08.json` | `3b947d4d…4424578` |

| salida | sha256 |
|---|---|
| `scripts/inventory/compile_existing_crank_drive_catalog.py` | `63bf4c07…584b0a` |
| `existing-crank-drive-catalog-2026-09-08.json` | `2caf9b53…912c756` |
| `existing-crank-drive-cases-2026-09-08.json` | `d957052b…50cd927` |

La preimagen entregada por Root se verificó por hash antes de usarla y trae
**20 definiciones publicadas**. Salida: 3 plantillas, 50 definiciones, 63 usos
de campo, **44 casos ejecutables y 7 pendientes**. El compilador es
determinista —ids nuevos por `uuid5` sobre la clave, dos corridas con bytes
idénticos— y reutiliza los ayudantes ya existentes de la serie, incluido el
bloque de declaraciones documentadas del paquete de mandos.

**Las 20 definiciones publicadas se reutilizan sin una sola diferencia** de
`id`, rótulo, tipo, unidad, dominio ni reglas; el compilador aborta si alguna
cambia. Las 30 nuevas tienen alcance de familia. Los campos retirados
conservan su observación con rol `legacy`: el motor los despoja antes de
validar, así que ni bloquean ni dejan pendencias, y nada se borra.

| plantilla | campos | nuevos | retirados a legacy |
|---|---|---|---|
| `crankset` | 28 | 13 | 8 |
| `crank_arm` | 13 | 8 | 0 |
| `chainring` | 22 | 11 | 5 |

## 2. Qué separa el candidato

**Caja, eje y asiento de biela son tres preguntas.** La caja del cuadro, el
pedalier que se atornilla en ella y el cuadrado o estriado sobre el que se
asienta la biela viven en filas y campos distintos. La combinación documentada
—caja, pedalier, largo de eje, línea de cadena resultante y su código— es una
fila con su condición, nunca una cifra suelta del conjunto.

**JIS e ISO se declaran, no se deducen.** La fuente documenta que el eje ISO es
más largo y termina más fino, y que la misma biela se asienta unos 4,5 mm más
afuera sobre un eje JIS del mismo largo: eso mueve la línea de cadena. La misma
fuente dice que en la práctica se mezclan a menudo eligiendo el largo de eje
que da la línea buscada, así que **el candidato no declara incompatibilidad
física universal** y no infiere el estándar por la marca.

**Un par no es una pieza.** Un envase de bielas con lado «Par» responde con una
fila por brazo —lado, largo, rosca de pedal y si lleva el asiento de los
platos— y los escalares quedan prohibidos, porque la rosca del pedal izquierdo
no es la del derecho y sólo uno de los dos brazos lleva la araña.

**Una, dos o tres piezas no es el número de platos.** La construcción es un
campo propio con las tres formas que documenta la fuente —una pieza de acero
que atraviesa la caja, el conjunto de tres piezas con eje independiente, y el
de dos piezas con el eje solidario al brazo derecho—, separada de cuántos
platos trae el envase.

**Un juego de platos no es un plato.** El envase declara si trae un plato o un
juego; con juego, cada plato tiene su fila con posición, dientes y **su propio
círculo de pernos**, y los escalares de dientes y de BCD quedan prohibidos.
Una vista despiezada de un solo pedivela publica dos círculos a la vez, uno
para el plato exterior y el medio y otro para el interior: por eso el círculo
pertenece al plato y no al conjunto.

**Un BCD no es un patrón ni un direct mount genérico es uno específico.** El
reparto simétrico es un campo aparte del diámetro, porque el mismo círculo se
publica con repartos distintos. Y un asiento direct mount exige nombrar el
asiento exacto y su generación: el mismo fabricante publica platos de montaje
directo con códigos distintos que no se intercambian.

**Emparejado OEM y montaje no desmontable.** El fabricante publica cada plato
dentro de una combinación, con su designación y sus propios pernos de fijación,
así que un número de dientes no identifica la pieza; eso vive en su tabla de
emparejado. Y el conjunto declara si los platos se sacan con pernos, si van
remachados o si el plato va direct mount al brazo.

**Desplazamiento con datum, línea de cadena del conjunto.** El desplazamiento
del plato se declara con la referencia desde la que se mide, en su propia
tabla; el escalar publicado sin datum se retira. La línea de cadena es del
conjunto y sólo es propia cuando el conjunto trae su eje: si el eje va aparte,
la línea pertenece a cada combinación de pedalier.

**Incluido y requerido son dos respuestas.** Que el conjunto necesite una caja
determinada y que el envase traiga el pedalier son campos distintos, con su
propia tabla de contenido; y el cubrecadena y el perno de fijación también son
contenido, no compatibilidad.

## 3. Lo implementado y ejecutado

```
fvm flutter test --no-pub test/unit/product_spec_integrated_catalog_test.dart \
  --dart-define=SPEC_CATALOG_INPUT=…/existing-crank-drive-catalog-2026-09-08.json \
  --dart-define=SPEC_CATALOG_CASES=…/existing-crank-drive-cases-2026-09-08.json
```

`00:06 +47: All tests passed!` — 3 pruebas de plantilla y metadatos de filas y
**44 casos**: positivos, negativos bloqueantes y pendientes. Salida real.

Diez mutantes acotados sobre el catálogo generado, corridos con los mismos
casos. **Cada mutante mata exactamente el caso que lo nombra y ningún otro**,
así que cada compuerta nueva carga peso:

| mutante | caso que cae |
|---|---|
| platos admitidos siempre | `ck_a_bare_crankset_cannot_list_rings` |
| línea de cadena admitida siempre | `ck_a_crankset_without_its_own_spindle_has_no_chain_line` |
| pedalier incluido admitido siempre | `ck_without_a_supplied_bottom_bracket_there_is_no_content` |
| sin clave de posición en los platos | `ck_the_same_ring_position_twice_blocks` |
| sin cardinalidad de platos | `ck_the_ring_count_must_match_the_rows` |
| dientes escalares admitidos siempre | `cr_a_set_cannot_carry_one_scalar_teeth_count` |
| BCD escalar admitido siempre | `cr_a_set_cannot_carry_one_scalar_bolt_circle` |
| generación direct mount admitida siempre | `cr_a_bolt_circle_ring_has_no_direct_mount_generation` |
| datum opcional en el desplazamiento | `cr_an_offset_without_its_datum_is_incomplete` |
| largo de biela admitido siempre | `ca_a_pair_cannot_carry_one_scalar_length` |

## 4. Lo representado sin certificación mecánica

Los 44 casos son representaciones sintéticas: `facts_verified_for_product` y
`automatic_fill_authorized` van en falso en todos, y el catálogo lleva
`mechanical_coverage_complete: false`. Ninguno certifica un montaje ni autoriza
llenar un producto.

Se representa sin certificar que un envase de bielas trae exactamente dos
lados distintos, que un juego trae al menos dos platos, y que una combinación
de pedalier produce una línea de cadena determinada. Las tres son formas
válidas de anotar lo que dice un documento; ninguna mide una bicicleta.

## 5. Fuentes exactas y límites OEM

Abiertas y leídas en esta ronda, por mí, no por el mensaje que me las nombró:

- `https://www.sheldonbrown.com/bbtaper.html` — el eje ISO es más largo y
  termina más fino que el JIS; una biela ISO sobre eje JIS se asienta unos
  4,5 mm más afuera; ambos comparten el ángulo de 2°; en la práctica se mezclan
  a menudo eligiendo el largo de eje que da la línea de cadena buscada; la
  página asocia estándares a marcas como tendencia, sin un método visual para
  distinguirlos sin medir.
- `https://www.parktool.com/en-us/blog/repair-help/how-to-remove-and-install-a-crank`
  — una sola pieza de acero forma los brazos y atraviesa la caja; el conjunto
  de tres piezas son brazo izquierdo, brazo derecho y eje; el de dos piezas
  lleva el brazo izquierdo con ranura de compresión y el derecho con el eje
  integrado; los conjuntos de tres piezas presentan eje cuadrado o estriado.
- `https://productinfo.shimano.com/en/compatibility/C-449` — la tabla de 8/7/6
  velocidades enfrenta una línea de pedivelas con **varios** pedalieres
  (BB-UN26, BB-UN300, BB-UN100, BB-UN101, y sus variantes con sufijo `-K`), y
  los códigos de configuración `D-NL`, `D-EL` y `D-NL-K` acompañan a esa línea,
  con `122.5` asociado a `D-NL` y `D-NL-K`; otras líneas de la misma tabla
  usan otro valor de línea de cadena. **Cada combinación conserva su
  condición**, incluida la variante `-K` ligada a la configuración con
  cubrecadena: por eso `122.5` no se toma como universal, y el candidato la
  guarda en la fila de su combinación.
- `https://dassets.shimano.com/…/EV-FC-M8000-3849B.pdf` — la vista despiezada
  declara combinaciones de dientes `40-30-22T / 38-28T / 36-26T / 34-24T / 34T
  / 32T / 30T` y **dos** diámetros de círculo de pernos en el mismo pedivela,
  96 mm para el plato exterior y el medio y 64 mm para el interior; nombra cada
  plato por la combinación a la que pertenece (`22T-BA for 40-30-22T`,
  `34T-BB for 34-24T`, `36T-BC for 36-26T`, `38T-BD for 38-28T`), da a cada
  combinación sus propios pernos de fijación, publica los platos de montaje
  directo con código propio y ofrece el brazo izquierdo en 165, 170, 175 y
  180 mm. Su leyenda de intercambiabilidad tiene grados: una marca significa
  la misma pieza, otra significa usable pero distinta en material, aspecto,
  terminación o tamaño, y **la ausencia de marca indica no
  intercambiabilidad**.

**Límite declarado:** la vista despiezada marca la intercambiabilidad con
letras repartidas en columnas por modelo. En esta ronda leí la **leyenda**, no
la alineación de columnas, así que **ninguna pieza se declara intercambiable
con un pedivela concreto**. Esa asociación columna-modelo es exactamente el
tipo de lectura que se equivoca al extraer una tabla, y no la afirmo sin
renderizarla.

## 6. Bloqueos reales de integración

1. **Un eje de motor integrado no tiene término publicado.** Un brazo del
   alcance se vende para eje de motor integrado y el dominio publicado de la
   interfaz de eje trae catorce interfaces reales **sin** un «Otro» ni un
   «Desconocido», mientras el campo es requerido siempre. El candidato guarda
   la designación del fabricante en un campo nuevo y **no inventa un token**:
   extender el dominio publicado es del publicador.
2. **Identidad del producto.** Los títulos llevan códigos de fabricante
   mientras `model` y `manufacturer_sku` están vacíos en **los 50 registros**
   del alcance (27 volantes, 7 bielas, 16 platos). Eso se resuelve en la
   identidad canónica, nunca en un segundo almacén dentro de la ficha.
3. **Publicación y adopción.** Publicador, SQL, adjudicación, adopción e
   integración final son de Root. Este paquete no los ejercita.
4. **Relación OEM dirigida y ronda de editor real.** No se ejercitan aquí.
5. **Las siete pendencias** del archivo de casos viajan con su razón en
   `pending_cases`, incluidas las dos de arriba, la de no deducir JIS/ISO por
   marca, la del largo en pulgadas de una biela americana y la del ancho de
   caja escrito en un título, que no prueba que el pedalier venga en el envase.

## 7. Lo que el alcance real muestra

Agregados del alcance, sin identidades: de 27 volantes, **8** nombran tres
platos y **3** nombran dos; **6** mencionan cubrecadena en un sentido u otro;
**3** anuncian el pedalier junto al conjunto; **2** son bielas americanas de
una pieza. De 16 platos, **2** son juegos y no platos sueltos, **10** declaran
un círculo de 104 mm, **2** declaran 96 mm y **uno de esos dos** se anuncia
explícitamente como asimétrico —la prueba de que el mismo diámetro no implica
el mismo patrón—. Los 7 brazos son izquierdos y **uno** se vende para eje de
motor integrado.
