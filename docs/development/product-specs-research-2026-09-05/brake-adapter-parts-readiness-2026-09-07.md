# Adaptadores de freno y frenos de maza — sucesor acotado (2026-09-07)

Familias: `brake_mount_adapter`, `rotor_mount_adapter`, `brake_small_part`,
`hub_brake`. Candidato. `mechanical_coverage_complete` y
`automatic_fill_authorized` en `false`; sin hechos, sin asignaciones, sin
migración, sin cambios de motor, sin consultas a producción y sin tocar ningún
archivo fuera de los cuatro míos.

Cinco defectos implementados con casos, un error propio que las regresiones
adjudicadas detectaron, y cinco cosas no modeladas que quedan nombradas.

## Alcance real, medido

Congelado verificado por hash al compilar: `16459826…f15` y sus casos
`329ad3e5…6d7`. Casos heredados: **RCF38 y RCF39**, ambos de
`rotor_mount_adapter`.

| | |
|---|---|
| Definiciones **añadidas** | `brake_adapter_included_hardware`, `brake_small_part_components`, `hub_brake_configurations` |
| Definiciones **modificadas** | `brake_adapter_fitments`, `rotor_adapter_fitments`, `brake_part_kind` — las tres con `used_by` de **una sola familia** |
| Retiros, sólo de plantilla | `bolts_included`; `thread`; `drum_diameter_mm`, `axle_fit`, `reaction_arm_mount`, `brake_actuation` |

El compilador no puede tocar una compartida por accidente: `extend()` compara
`used_by` con la familia y **levanta excepción** si no coinciden. Comprobado
además byte a byte que siguen idénticas `bolts_included` (3 familias), `thread`
(3), `compatible_brake_models` (5), `brake_actuation` (5), `material` (27),
`pack_quantity` (19) y `spec_evidence_source` (105).

No consulté producción, como pediste. La base para tratar esas tres tablas como
extensibles es que el congelado las declara de una familia y que ninguna aparece
en las preimágenes locales de los bloques aplicados; `bolts_included` y `thread`
**sí** aparecen en la preimagen de transmisión, y por eso sólo se retira su uso.

## Corregido

**BA-1 — la tabla de aplicaciones sólo sabía decir que sí.** No tenía columna de
estado, así que una exclusión publicada y una fila ausente se leían igual. Entra
`status` (compatible / excluido / condicional), con `conditions` exigida cuando
es condicional. La base del cuadro u horquilla deja de ser una cifra opcional
suelta: `frame_base_form` obliga a decir si está declarada, no publicada o
publicada como designación, y sólo entonces se abre la celda correspondiente.
Posición, base, montaje del cáliper y rotor objetivo ya viajaban juntos en la
misma fila y así se conservan.

**BA-2 — los herrajes incluidos eran un booleano compartido.** Cuáles, cuántos,
de qué largo y medido desde dónde no existían en ninguna parte. Entra
`brake_adapter_included_hardware`, con el largo gobernado por su forma, su datum
propio, y la rosca descompuesta o como designación. Cada herraje se ata por
**id de fila** a la configuración a la que pertenece, y el helper dice lo que
importa: lo que viene en la bolsa no acredita que el conjunto sirva.

**BA-3 — una celda hacía dos trabajos.** `hub_thread_spec` servía a la vez para
la rosca con que el adaptador se fija a la maza y para la del anillo propio.
Entra `thread_owner`, **opcional**, para decir de quién es la rosca descrita, y
`status` para que una exclusión publicada por modelo de rotor se registre como
exclusión. La celda original conserva su sitio, que es justo lo que RCF39 exige.

**BA-4 — a un resorte se le preguntaba su rosca.** El escalar `thread` estaba
permitido siempre. Entra `brake_small_part_components`, una fila por pieza con
su propia forma, y un `value_when` que impide declarar roscado un resorte o un
clip. `brake_part_kind` gana «Clip / retención sin rosca». Que una pieza del
juego sea un tornillo ya no convierte al resto en tornillos.

**BA-5 — el freno de maza mezclaba mecanismo, conjunto y accionamiento.** Entra
`hub_brake_configurations`, que los separa y añade el brazo de reacción con su
punto de fijación, condicionado a que haga falta. Tres reglas salen de Sheldon
y sólo de ahí: un contrapedal es una maza **trasera**, se acciona **pedaleando
hacia atrás**, y **lleva** brazo de reacción. Ninguna regla liga la rueda
delantera con la trasera, porque la fuente no dice nada de eso.

## El error fue mío y lo cazó una regresión adjudicada

Añadí primero un `value_when` que forzaba `thread_owner = 'Fijación a la maza'`
en toda ruta «Rosca especificada». **RCF38 falló**, y al mirarlo la regla estaba
mal en el fondo, no sólo en la forma: una ruta roscada a la maza puede llevar
además su propio anillo, así que deducir el dueño de la rosca desde el tipo de
montaje era exactamente la inferencia que este bloque debe impedir. La quité, y
quité también el caso que la probaba. La fixture heredada hizo su trabajo.

## La traducción de RCF38 y RCF39, declarada y auditada

`status` es obligatoria, y las dos fixtures son anteriores a esa columna. Ambas
describen una ruta documentada que funciona, así que cada fila recibe
`status = "Compatible declarado"`, que es lo que ya significaba, con la nota
`successor_translation` en el propio caso. Auditado programáticamente: el único
delta en toda la fixture es esa celda, y `expected_row_condition_issues`,
`expected_blocking` y `purpose` quedan **idénticos** en las dos. Si prefieres las
fixtures intactas, basta con volver `status` opcional; el costo sería que una
fila vuelva a poder callar si es aplicación o exclusión.

## Verificación

**30 pruebas Dart, todas verdes** — 4 de metadatos y 26 casos, incluidas RCF38 y
RCF39 con sus afirmaciones intactas.

Cuatro mutantes, cada uno falla exactamente lo suyo y nada más:

| Mutante | Falla |
|---|---|
| quitar la cláusula padre AND-ada de las compuertas de fila | `ba_spacer_is_not_threaded`, `ba_unthreaded_piece_cannot_carry_a_pitch` |
| quitar el `row_coherence.links` de los herrajes | `ba_hardware_cannot_point_at_absent_configuration` |
| quitar el `value_when` del freno de maza | `ba_coaster_cannot_be_cable_actuated`, `ba_coaster_cannot_be_declared_front` |
| quitar el `value_when` de las piezas de repuesto | `ba_spring_is_never_threaded` |

## No modelado

- **Una fila que no adapta nada.** Nada impide `hub_mount` igual a
  `rotor_mount`. No lo llamo inexpresable: **sí** habría una forma —enumerar las
  rutas válidas en una columna y atarla a ambas celdas con `value_when`— pero
  eso cierra el universo de rutas a una lista, que es justo lo que el bloque
  evita en todo lo demás. Queda abierto como decisión, no como imposibilidad.
- **La identidad inicial y las piezas pueden discrepar.** `brake_part_kind` dice
  «resorte» y la tabla puede listar sólo tornillos; nada lo cruza.
- **Ninguna cifra de tambor, rodillo o banda.** Sturmey-Archer no se pudo abrir.
- **Ningún dato de Shimano entró.** Ni modelo, ni posición, ni exclusión.
- **`unique_by` no se añadió a ninguna tabla.** No encontré en estas cuatro una
  identidad de colección que lo justifique: dos herrajes iguales, dos piezas
  iguales o dos configuraciones de rueda distinta no son contradicciones.

## Hashes

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_brake_adapter_parts_catalog.py` | `ed4d6429b76d3a3925ea14844d6d5f1592e45cebc323db191839a59b4ecf9d51` |
| `brake-adapter-parts-catalog-2026-09-07.json` | `c632b404c2ce85359ca42b34a3435cfe39f2c1b8dff20cea03e58cd852b87ea7` |
| `brake-adapter-parts-cases-2026-09-07.json` | `ffeadc083b98968dbe29c17c5a293bd3178e8c01887d81b701b885d94b6d8ef7` |

Totales: 4 plantillas, 24 definiciones, 27 usos de campo, **26 casos**.

## Fuentes, con su alcance exacto

Leídas por mí esta ronda:

- **Park Tool, mechanical disc brake alignment** —
  https://www.parktool.com/en-us/blog/repair-help/mechanical-disc-brake-alignment
  Dice que la posición de los pernos varía según el estándar del cuadro, y
  nombra Post Mount, IS y Flat Mount. Verifiqué también lo que **no** dice: no
  afirma que un adaptador sea específico de un tamaño de rotor ni de delantero o
  trasero, ni que un cuadro tenga tamaño nativo. Nada de eso se le atribuye.
- **Sheldon Brown, coaster brakes** —
  https://www.sheldonbrown.com/coaster-brakes.html
  «It is also a brake, activated by turning the pedals backwards»; el brazo de
  reacción va del cono izquierdo a la vaina; «A coaster brake is a special rear
  hub». Y **no** contiene ninguna afirmación sobre qué freno delantero admite,
  que es la razón de que no exista tal regla aquí.

No legibles, con el límite exacto:

- **`si.shimano.com`: HTTP 403.** No abrí ninguno de los dos PDF. Los datos que
  aportaste —SM-MA00A, y SM-RTAD05 como ruta de 6 tornillos a maza Centerlock
  que excluye SM-RT86/RT76— me sirvieron para ver **que hacía falta poder
  registrar una exclusión**, y ese es su único efecto: ni un modelo ni una cifra
  suya entró en los artefactos. Las filas de rotor son sintéticas. Tampoco
  interpreté ninguna celda de tabla de un PDF, porque no llegué a abrir ninguno.
- **Sturmey-Archer: HTTP 403** en tres rutas y dos hosts
  (`www.sturmey-archer.com` y `sturmey-archer.com`), HTML y PDF. No insistí.
  Nada suyo entró, y por eso el bloque no lleva ninguna cifra de tambor.

Ninguna de estas reglas es aprobación mecánica. El esquema **representa** estas
declaraciones y se niega a contradecirse; que un adaptador concreto sirva a un
cuadro concreto sigue siendo una afirmación del fabricante.
