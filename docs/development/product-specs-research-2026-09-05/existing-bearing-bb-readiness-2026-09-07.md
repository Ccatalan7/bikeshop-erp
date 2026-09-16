# Rodamiento y motor: sucesor de cinco plantillas existentes (2026-09-07)

**Publicado el 2026-09-16** como `20260916100000_bearing_bb_successors.sql` sobre 72 productos; ver [bearing-bb-successors-adjudication-2026-09-16.md](bearing-bb-successors-adjudication-2026-09-16.md).

`bearing`, `bottom_bracket`, `bottom_bracket_axle`, `bottom_bracket_bearing` y
`bottom_bracket_cup`. Candidato para adjudicación. Sólo metadatos; sin migración,
sin base productiva, sin git, sin runtime, sin hechos ni asignaciones.
`mechanical_coverage_complete` y `automatic_fill_authorized` en `false`. No toqué
las otras 32 ni las 67 nuevas ya aplicadas.

La regla que ordena todo el bloque es **un hecho, un dueño**. La auditoría que
mandaste señalaba siempre lo mismo desde ángulos distintos: una construcción que
además anuncia el sellado, un estándar de conicidad al lado de una interfaz que
ya lo nombra, un diámetro de copa junto a un puerto que lo mide. Cada una de
esas parejas son dos celdas que pueden desmentirse, y la que se queda es la que
lleva la medida.

## Lo primero: la compartida viva manda sobre la propuesta congelada

De las 21 definiciones compartidas que usan estas cinco familias, **11 estaban
mal en el congelado**. El candidato toma la fila viva de todas ellas.

- **Tres dicen `origin: new` y ya están publicadas**: `ball_diameter_in`,
  `bb_shell_interface` y `kit_members`. Se reutilizan sin tocarlas.
- **Ocho tienen listas de valores o etiquetas que el congelado no tiene**:
  `bb_ball_count_per_side`, `bb_cup_outer_diameter_mm`, `bb_shell_diameter_mm`,
  `bb_shell_width_mm`, `bb_spacer_stack_mm`, `spindle_diameter_mm`,
  `spindle_length_mm` (listas vivas), más `bearing_application` y
  `bearing_size_code` (etiquetas vivas).
- **`spindle_interface` es la trampa concreta**: el congelado tiene un
  decimoquinto valor, `Desconocido / sin confirmar`, que **nunca se publicó**.
  Usarlo intentaría añadir una opción a una definición viva, que el publicador
  rechaza. El candidato copia los catorce valores vivos y trae una guardia que
  aborta si ese vocabulario se mueve.

Verificado: las 21 quedan idénticas a la preimagen en las seis propiedades que
el publicador compara.

## Y algo que no esperaba: el congelado renombra cuatro de las cinco

| Propuesta congelada | Nombre vivo |
|---|---|
| Pedalier | Motor / Bottom Bracket |
| Eje de pedalier | Eje de Motor |
| Rodamiento de pedalier | Rodamiento Motor |
| Copa de pedalier | Cubeta de Motor |

**El candidato conserva los nombres vivos.** «Motor» y «cubeta» son la palabra
del taller, y renombrar cuatro familias no es un efecto lateral de rehacer un
contrato: es una decisión de producto, y va aparte. Lo dejo declarado en el
propio catálogo (`renames_declined`) en vez de publicarlo.

Esto se cruzó con tu arreglo del publicador: con la versión anterior los cuatro
renombres habrían pasado en silencio; con la de ahora el paquete se detiene en
*Unsupported template metadata change: name*. Lo comprobé sin querer, y funciona.

## Los cruces que la auditoría pedía

### La construcción no puede contestar por el sellado

`bearing_construction` contestaba tres preguntas a la vez —cómo se suministra la
pieza, si está sellada y en qué estado— y `bearing_seal_kind` volvía a contestar
la del sellado en texto libre. Se parte en tres frases distintas:

- `bearing_supply_form` — Cartucho, Bolas sueltas, Canastillo. Nada más.
- `bearing_seal_type` — sellado de contacto, blindado, abierto. Sólo en cartucho.
- `bearing_seal_designation` — la designación literal del fabricante (2RS, LLU),
  sólo donde hay sello. Un cartucho abierto no la admite.

### El ángulo de las pistas no es el bisel del asiento

El par interior/exterior se leía como los dos biseles de un asiento. La geometría
de rodadura de un rodamiento es **un** ángulo de contacto de pistas, y el bisel
del asiento que **recibe** un rodamiento es de la copa. Así queda: la copa lleva
`bb_cup_seat_bevel` y lo declara cuando se vende sin su rodamiento; el rodamiento
lleva `bearing_race_type` y su ángulo. Son dos piezas y dos medidas.

### Bolas, canastillo y cartucho, separados

El modo de suministro decide qué se puede declarar: un cartucho no publica el
diámetro de sus bolas ni las cuenta, y unas bolas sueltas no tienen código de
cartucho ni número de hileras. La retención con jaula o sin ella es otra pregunta
y sigue siendo del cartucho.

### Componente físico frente a interfaz aceptada

`spindle_interface_accepted` era un multi-select de marcas sin ninguna variante
detrás. Entra `bb_accepted_spindles`: **una fila por variante**, con marca,
modelo y edición **obligatorios**, su interfaz y su veredicto. Cuadrado JIS y
Cuadrado ISO son dos declaraciones distintas y ninguna se hereda de la marca. Una
exclusión publicada se registra; la ausencia de fila no es un permiso. El alcance
publicado se admite en cualquier veredicto y se exige en uno condicionado.

Para el eje y el rodamiento de motor, `bb_construction` como «declaración» decía
para qué sistema son. Eso es una afirmación del fabricante, no una propiedad de
la pieza: pasa a `bb_declared_systems`, con modelo y edición.

### Eje incluido frente a eje de biela

`includes_spindle` era una casilla suelta y las medidas del eje se podían llenar
igual. Ahora `spindle_interface`, `spindle_length_mm` y `spindle_diameter_mm`
sólo existen si el pedalier **trae** eje. Lo que acepta de una biela vive en la
tabla de ejes admitidos, que es otra cosa, y un pedalier sin eje puede llenarla
sin contradecirse.

### Que dos copas se rosquen entre sí no dice que la caja tenga rosca

Entra `bb_shell_ports`, un puerto por fila, y la columna que lo resuelve es
**contra qué cierra**: la caja del cuadro o la otra copa. Un pedalier de copas
roscadas entre sí en una caja a presión son tres filas —dos a presión contra la
caja y una roscada contra la copa opuesta— y ninguna implica a la otra.

### Diámetro, paso, unidad y sentido, por puerto y por lado

Del mismo puerto salen las cuatro. [Sheldon](https://www.sheldonbrown.com/bbsize.html),
leído directamente: su tabla de roscas da el sentido **por copa**, no por
producto —en la caja inglesa la copa ajustable es derecha y la fija izquierda,
mientras en la italiana las dos son derechas—. Un token de par tipo «Derecha /
Izquierda» pierde cuál es cuál. Y [Park](https://www.parktool.com/en-us/blog/repair-help/basic-thread-concepts),
también leído: el diámetro mayor y el paso son dos medidas distintas, así que
cada una lleva su unidad. Un asiento a presión no declara paso ni sentido; una
designación OEM sin descomponer no declara diámetro.

### Ni el producto ni la caja se vuelven un catálogo de tallas

El ancho de caja y el stack de espaciadores siguen siendo una cifra declarada del
producto, no una lista. La copa conserva si trae su rodamiento y **no** conserva
`kit_members`: una copa es una pieza, no un kit. Y en el rodamiento de motor,
`spindle_diameter_mm` era el diámetro interior con otro nombre — se retira, y el
diámetro se declara una sola vez.

## Retiros y bajas, con la diferencia que importa

Un campo **publicado** se retira; uno que sólo estaba **propuesto** se quita. Las
observaciones cuelgan de lo publicado, y ninguna se pierde: verificado campo por
campo contra la preimagen, las cinco familias conservan **todos** sus campos
vivos.

| Familia | Retirados (publicados) | Quitados (nunca publicados) |
|---|---|---|
| bearing | ninguno | 7 |
| bottom_bracket | 6 | 3 |
| bottom_bracket_axle | 1 | 1 |
| bottom_bracket_bearing | 2 | 1 |
| bottom_bracket_cup | 5 | 3 |

## Las 20 regresiones heredadas, traducidas una por una

Las 20 se conservan y cada una lleva su `successor_translation` diciendo qué
celda cambió de dueño y por qué. Donde bloqueaban, siguen bloqueando.

**Dos se debilitan, y lo digo aquí en vez de disimularlo.**
`wss_bearing_headset_without_angles` y `wss_SF2` quedaban pendientes de sus
ángulos porque **los biseles del asiento los exigían** — la conflación exacta que
este sucesor elimina. Sin ese disparador, exigir el ángulo dejaría pendiente para
siempre a cualquier ficha honesta: un fabricante que dice «contacto angular» casi
nunca publica la cifra, y la otra regresión heredada (`wrfp_3802…`) prohíbe
justamente que aparezca una incidencia ahí. Las dos heredadas se contradicen
entre sí en cuanto se quita el asiento. Resolución: el ángulo **se admite y no se
exige**; donde la geometría de pistas sigue sin declararse, la pendiente se
conserva sobre `bearing_race_type`, que es el dato que de verdad falta; donde sí
está declarada, la pendiente desaparece.

## Verificación

**64 pruebas Dart verdes**: 5 de metadatos y 59 casos —20 heredados traducidos y
39 nuevos—. No toqué `lib/`, así que no reabrí la batería del motor.

**El publicador de las 37 acepta el candidato de punta a punta.** Lo armé contra
la preimagen viva restringida a estas cinco y `compile_packet` lo aceptó: 17
definiciones nuevas, 30 opciones, 5 parches de plantilla, 40 de campo y 24 filas
de campo nuevas. Revisiones calculadas: bearing 2→19, bottom_bracket 9→29, axle
4→12, bearing de motor 7→19, cubeta 4→16. No generé migración.

**Diecisiete mutantes, los diecisiete mortales**, uno por compuerta: sellado,
designación de sello, ángulo, bolas, código de cartucho, exigencia de geometría,
eje incluido, disposición, rodamiento de motor, bisel de la cubeta, paso, sentido,
designación OEM, y las tres claves compuestas más la exigencia de alcance.

El de la compuerta del paso **no mató nada en su primera corrida**: mi caso
llevaba también el sentido de rosca, y bloqueaba por esa otra compuerta. Afilé el
caso para que sólo el paso esté fuera de lugar. Es la tercera vez que encuentro
lo mismo en este proyecto y ya es sistemático mirarlo.

## Fuentes

- **Sheldon Brown, Bottom Bracket Sizes** — abierta y leída por mí. De ahí sale
  el sentido de rosca por copa, y también lo que **no** dice: su sección de
  ISO frente a JIS cita material de terceros y no define la diferencia en texto
  propio, así que el candidato **no** deriva ninguna regla JIS/ISO de Sheldon.
  Por eso cada interfaz admitida exige su variante OEM.
- **Park Tool, Basic Thread Concepts** — abierta y leída por mí: diámetro mayor y
  paso, y qué es una rosca derecha o izquierda.
- **Sin fuente para la copa roscada contra su opuesta.** La columna existe porque
  el cruce es medible, no porque una página lo diga; queda declarado.
- **Fixtures**: mis 39 casos nuevos son sintéticos sobre `example.invalid`. Los
  20 heredados **conservan la procedencia con que se publicaron** —ocho citan
  Enduro Bearings o Cane Creek—; no reabrí esas páginas y no las presento como
  lectura mía.

## Lo que este candidato no hace

No adjudica mecánicamente nada. No hay migración, no hay fill, no hay hechos ni
asignaciones. Que una copa concreta acepte un eje concreto sigue siendo
afirmación del fabricante; lo que el esquema hace es negarse a guardar dos
respuestas para el mismo dato. Antes de publicar faltan tu adjudicación por
familia, preimagen y backup recientes, y el readback posterior.

## Hashes

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_existing_bearing_bb_catalog.py` | `c658391ab918e3ad8eb1d53628ef5fcba53cc1b66721899984da8fb301814ae3` |
| `existing-bearing-bb-catalog-2026-09-07.json` | `850e26b0357a93e069f7e59c9e9b034cc925efeb8120cd8c39ce48dce3cd9b3f` |
| `existing-bearing-bb-cases-2026-09-07.json` | `83083632d850a483820aba045387ed4cfa529a4dc2d635e0fc58724102aa87aa` |

Entradas fijadas por hash al compilar: catálogo congelado `16459826…fadf15`,
casos `329ad3e5…3716d7`, preimagen `0a21d85a…08b2a6`.

Totales: 5 plantillas, 38 definiciones, 64 usos de campo, **59 casos**.
