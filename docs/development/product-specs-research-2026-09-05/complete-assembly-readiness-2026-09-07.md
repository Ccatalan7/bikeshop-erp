# Bicicleta, cuadro y rueda — sucesor acotado (2026-09-07)

Familias: `bicycle`, `frame`, `wheel`. Candidato. `mechanical_coverage_complete`
y `automatic_fill_authorized` en `false`; sin hechos, sin asignaciones, sin
migración, sin publicador, sin base y sin tocar nada fuera de mis cuatro
archivos.

Cuatro defectos implementados con casos, dos trampas en las que caí y de las que
salí, y cinco cosas no modeladas.

## Alcance real, medido

Congelado verificado por hash al compilar: `16459826…f15` y sus casos
`329ad3e5…6d7`. Casos heredados: **RCF23** (bicicleta) y los cuatro
**`wss_frame_*`**; los cinco siguen verdes sin tocarlos.

| | |
|---|---|
| Definiciones **añadidas** | `frame_geometry_measurements` (cuadro + bicicleta), `bicycle_size_configurations`, `bicycle_wheel_positions`, `wheel_compatible_claims` |
| Definiciones **modificadas** | **ninguna** |
| Retiros, sólo de plantilla | 13 en bicicleta, 2 en rueda, 0 en cuadro |

Comprobado byte a byte que siguen idénticas `kit_members` (23 familias),
`wheel_position` (5), `max_tire_width_mm` (4), `bb_shell_interface` (4),
`material` (27), `color` (37), `spec_evidence_source` (105), `frame_size_label`
(2), `rear_bead_seat_diameter_mm` (2) y `thru_axle_thread` (4).

## Corregido

**CA-1 — la geometría no existía, y una talla sin datum no es una talla.**
Sheldon lo dice sin rodeos: el sistema antiguo medía del centro del pedalier al
extremo del tubo de sillín, muchos fabricantes miden ahora a la intersección con
el tubo superior, y «seat tube 'frame size' numbers are nearly meaningless
unless you know how they are measured». Entra `frame_geometry_measurements`, una
fila por talla, medida y datum, con la unidad como respuesta propia y
`unique_by [[talla, medida, datum]]` — de modo que centro‑centro y centro‑extremo
del **mismo** tubo conviven, y la misma medida con el mismo datum dos veces no.
Un `value_when` exige grados para los ángulos.

La tabla de geometría de Surly confirma las dos mitades: sus etiquetas son las
que este vocabulario nombra —Seat Tube Length, Top Tube Length Actual y
Effective, Head Tube Angle, Seat Tube Angle, con ángulos en grados— y **no dice
si el tubo de sillín está medido centro a centro o centro al extremo**. Una tabla
OEM real omite justo el dato que Sheldon llama imprescindible, así que exigir el
datum no es rigor de laboratorio: hace visible una pregunta que los catálogos
dejan sin responder, y la fila la registra como «no especificado por la fuente»
en vez de esconderla en un blanco.

**CA-2 — un modelo se vende en tallas y la ficha tenía una.** `frame_size_label`
era un escalar único obligatorio y el rango de estatura, otro par de escalares
para todo el producto. Entra `bicycle_size_configurations`, una fila por talla,
con el rango gobernado por su forma y su unidad, `unique_by` por talla y el par
ordenado mínimo/máximo.

**CA-3 — las dos ruedas eran diez escalares paralelos.** Nada ataba una medida a
la rueda a la que pertenece. Entra `bicycle_wheel_positions`, una fila por
posición con su diámetro de asiento de talón, anchura de maza, retención de eje,
montaje de freno y rotores; `unique_by` por posición, y el par ordenado
montado/máximo. Una rueda sin freno de disco no declara rotor. Se retiran los
diez escalares delanteros y traseros, sólo en esta plantilla.

**CA-4 — «incluye cubierta» no dice cuál, y «acepta» no existía.**
`includes_tire` e `includes_tube` eran resúmenes sí/no de lo que ya lleva
`kit_members` con identidad. Lo que faltaba era la otra declaración entera: qué
dice el fabricante que la rueda acepta. Entra `wheel_compatible_claims`,
separada de los miembros del conjunto, con su estado y su apartado de fuente. El
helper dice lo que importa: una rueda puede venir con una cubierta que no es la
única que acepta, y aceptar una que no incluye.

## Dos trampas, y cómo salí

**Iba a "arreglar" algo que no estaba roto.** Sospeché que una rueda `Universal`
no podía registrar ninguna medida y estuve a punto de abrir la compuerta. Lo
sondeé antes: el contrato ya la excluye por `allowed_options`, que en esta
plantilla deja sólo Delantera, Trasera y Par, y la sonda devolvió
`constraint:wheel_position`. No era un hueco. Y el juego de ruedas ya estaba bien
resuelto en el congelado —`wheel_configurations` con `unique_by [[posición]]` y
tres columnas obligatorias—, así que sólo añadí el caso que lo fija.

**Repetí en mi propio diseño el defecto que acababa de documentar.** La clave
compuesta de `wheel_compatible_claims` incluía `target_brand` opcional, y por eso
dos declaraciones contradictorias pasaban en silencio — exactamente la debilidad
que describí en el dictamen hidráulico una hora antes. La fixture lo cazó.
Lo arreglé **en el diseño y no en la sonda**: todas las columnas de la clave son
ahora obligatorias, y una marca o edición no declarada se escribe como tal en vez
de dejarse en blanco. El caso `ca_undeclared_edition_still_guards` fija que la
guardia sigue operando en ese caso.

Un mecanismo que descubrí de paso y conviene tener escrito: el validador del
contrato **rechaza un `scalar_ordered_pairs` cuyos miembros sean legacy**
(`compile_product_spec_catalog.py:634-637`). Retirar el rango de estatura obliga
por tanto a retirar también su par, que el par de filas sustituye.

## Verificación

**32 pruebas Dart, todas verdes** — 3 de metadatos y 29 casos, incluidas las
cinco regresiones heredadas.

Cuatro mutantes, cada uno falla exactamente lo suyo:

| Mutante | Falla |
|---|---|
| quitar la regla de unidad de los ángulos | `ca_angle_must_be_in_degrees` |
| quitar las cuatro claves compuestas | los cinco casos de duplicado, incluido `ca_undeclared_edition_still_guards` |
| quitar los pares ordenados | `ca_inverted_rider_range_blocks`, `ca_fitted_rotor_cannot_exceed_the_maximum` |

El primer intento del mutante de ángulos rompió dieciséis casos, lo que era
absurdo: vaciar la entrada de `row_conditions` la deja malformada y el
`FormatException` envenena toda la plantilla. Repetí la mutación quitando la
entrada completa y entonces falla sólo el caso previsto. Lo anoto porque es una
trampa del arnés de mutación, no del candidato.

## No modelado

- **Ninguna cifra de geometría es real.** Las del arnés son sintéticas; de Surly
  tomé sólo las **etiquetas** y el hecho de que su tabla no declare el datum.
- **`frame_geometry_measurements` y `bicycle_size_configurations` se cruzan por
  el texto de la talla, no por id de fila.** No puse enlace porque la tabla de
  tallas existe sólo en bicicleta y la de geometría también sirve al cuadro, que
  no tiene destino al que apuntar. Dos filas que digan «M» y «Talla M» no se
  reconocen entre sí.
- **El cuadro no gana geometría obligatoria.** Dejé `frame_geometry_measurements`
  opcional para no convertir las cuatro regresiones heredadas en filas
  pendientes; su ausencia no marca nada.
- **Avance y largo de horquilla no tienen token propio** y caen en «Otra medida
  declarada», aunque Surly los publica como campos separados.
- **La bicicleta conserva sus escalares de transmisión, dirección y pedalier**
  sin tocar: no eran parte del encargo y no los audité.

## Hashes

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_complete_assembly_catalog.py` | `4b984a545e02468585bb0062b0c214e781048328fc2a1853a21ab12a0e1e5a8a` |
| `complete-assembly-catalog-2026-09-07.json` | `b686801573367620b0c6b03ae5b10cdf60910a9837e45a9e5918131fc9b58033` |
| `complete-assembly-cases-2026-09-07.json` | `a0c18bdcb9f5f94191e7ba150ef4da6c2122f02fdc11da4b0b6e95db417e90b0` |

Totales: 3 plantillas, 64 definiciones, 85 usos de campo, **29 casos**.

## Fuentes, con su alcance

Leídas esta ronda:

- **Sheldon Brown, frame sizing** — https://www.sheldonbrown.com/frame-sizing.html
  Los dos sistemas de medida del tubo de sillín y la conclusión de que un número
  de talla no significa nada sin saber cómo se midió. Es la base de exigir datum.
- **Surly Cross-Check, tabla de geometría** — https://surlybikes.com/bikes/cross_check
  Etiquetas exactas y ángulos en grados; **no** declara el datum del tubo de
  sillín, y distingue tubo superior real de efectivo. Sólo se usan sus etiquetas
  y esa omisión: ninguna de sus cifras entró.

No intentadas ni usadas: no busqué fuentes OEM adicionales de geometría, así que
el vocabulario de medidas está validado contra **una** tabla real y no contra un
muestreo. Park no publica geometría de cuadros y no lo consulté para este bloque.

Nada de esto es aprobación mecánica. El esquema **representa** estas
declaraciones y se niega a contradecirse; que un cuadro concreto acepte una
rueda concreta sigue siendo una afirmación del fabricante, y ninguna medida se
convierte aquí en un calce.
