# Frenos: sucesor de las siete plantillas existentes (2026-09-07)

`brake_caliper`, `brake_lever`, `brake_pad`, `hydraulic_disc_brake`,
`mechanical_disc_brake`, `rim_brake` y `rotor`. Candidato para adjudicación.
Sin migración, sin producción, sin fill, sin cambios de asignación, sin git ni
runtime. `mechanical_coverage_complete` y `automatic_fill_authorized` en
`false`. No toqué las cinco de rodamiento/motor, ni las otras 25, ni las 68
nuevas.

**Publicado el 2026-09-16** el último tramo: las tres presentaciones completas y el dueño de `tool_size_mm` en `brake_caliper` como `20260916130000_brake_presentations.sql` (revisión 223, 44 productos); las cinco piezas se habían publicado el 2026-09-15. Ver [brake-presentations-adjudication-2026-09-16.md](brake-presentations-adjudication-2026-09-16.md).

Auditando los 128 usos y no sólo la lista que diste, el bloque tenía **tres
defectos sistemáticos**, y cada uno explica varios de los puntos que señalaste:

1. **Un hecho con dos dueños.** Un fluido en un select y otra vez en una tabla
   de aprobaciones; un largo de latiguillo en el producto y otra vez en la fila
   de su circuito; un espesor admitido suelto junto a una receta que ya dice
   posición, montaje y fuente.
2. **Un dueño que no tiene la propiedad.** `reach_adjust` —la distancia de una
   maneta al manillar— vivía en el cáliper, que nunca toca el manillar.
3. **Ocho tablas de filas y ninguna clave.** Ni una sola declaraba `unique_by`,
   así que dos filas podían contestar la misma pregunta con cifras distintas y
   nada objetaba.

Y dos familias completas —`rotor` y los dos conjuntos— llegaron **sin una sola
compuerta escalar**: el rotor no ordenaba sus dos espesores y el conjunto
mecánico podía declarar cualquier cosa.

## Lo vivo manda: 9 correcciones y 7 renombres declinados

De las 28 compartidas que usan las siete, **9 estaban mal en el congelado**.

- **Cinco dicen `origin: new` y ya están publicadas**: `brake_actuation`,
  `brake_hydraulic_connections`, `hose_system_code`, `kit_members` y
  `pack_quantity`.
- **Cuatro traen una opción que nunca se publicó** y que el publicador
  rechazaría: `compound_type` (+ «Resina (denominación OEM)»), `fluid_type`
  (+ «DOT 5»), `mount_standard` y `rotor_mount_type` (+ «Desconocido / sin
  confirmar»).

Y el congelado **renombra las siete**. El candidato conserva el nombre vivo y
declara el cambio en `renames_declined`: «Caliper de Freno», «Manilla de Freno»,
«Pastilla de Freno», «Freno Disco Hidráulico», «Freno Disco Mecánico», «Freno de
Llanta / V-Brake», «Rotor de Freno». Es la palabra del taller; renombrar es
decisión de producto y va aparte.

## Los cruces, por lo que pediste

### Accionamiento real de la pieza frente a conversión externa

`brake_actuation` admite «Híbrido (cable a hidráulico)», y con eso sólo no se
distingue qué mitad es la pieza. Entra `brake_external_converter_model`, en
cáliper, maneta y freno de llanta, **admisible únicamente cuando la pieza se
declara híbrida**: un cáliper hidráulico o de cable no puede nombrar un
convertidor, porque en esa pieza no hay conversión que nombrar.

### Fluido y latiguillo por circuito, no en un escalar al lado

`fluid_type` se retira en cáliper, maneta y freno hidráulico: la tabla de
aprobaciones ya dice marca, modelo y fuente del sistema que aprueba, y tener las
dos deja dos celdas que pueden desmentirse. `hose_system_code` se retira por lo
mismo frente a la tabla de conexiones, y `hose_length_mm` se retira del freno
hidráulico porque su configuración lleva el largo **por circuito y posición**.

### Cable pull por maneta y por cáliper, nunca por marca

Se conservan las tres celdas porque son tres hechos distintos: lo que una maneta
**entrega**, lo que un cáliper **exige** y lo que un freno de llanta **exige**.
Ninguna se deriva de otra ni de `brake_system`, que sigue retirado en las siete.
Sheldon lo respalda de frente, y es la única fuente que abrí para esto.

### Montaje real, adaptador y rotor por puerto y posición

`mount_standard` tiene «Adaptor Requerido» **como valor**, que mezcla el montaje
con la necesidad de un adaptador. Se retira en cáliper y en los dos conjuntos:
la receta de rotor ya separa montaje del cuadro, montaje del cáliper, si hace
falta adaptador y cuál, por posición y con su fuente. Y el diámetro que viene en
la caja (`rotor_included_diameter_mm`) queda distinto del admitido, que es la
receta.

### Espesor nuevo, mínimo y admitido

El rotor ordena por fin sus dos espesores: `rotor_min_thickness_mm` no puede
superar a `rotor_thickness_mm`. No hace falta fuente para eso —una pista sólo
adelgaza— y nada lo comprobaba. El **admitido**, que es del cáliper, deja de ser
una cifra suelta y pasa a `accepted_rotor_thickness_mm` dentro de la receta,
junto al montaje y la posición que lo admiten y con la fuente de esa misma fila.

### Pista, compuesto y forma de pastilla

La clase de compuesto y el nombre comercial con que el fabricante la rotula son
dos celdas, y la segunda **sólo se admite si la primera está declarada**: sin
clase no hay nombre que calificar, y así no pueden contradecirse. La lista de
cáliperes compatibles gana clave, de modo que el mismo cáliper no se puede
declarar dos veces con veredictos distintos. La restricción de compuesto del
rotor se mantiene como lo que es —una afirmación sobre **ese** rotor— y sólo se
admite con su material en el registro.

### Freno de llanta: reach y pivote por montaje

El reach dejaba de ser del montaje y era del producto. Pasa a la fila de
`rim_brake_mount_fitments`, con su par ordenado, así que un rango invertido sigue
bloqueando y ahora además está atado al montaje y a la fuente que lo dice. Se
quitan los dos escalares y `rim_brake_frame_mount`, que repetía el `mount_spec`
de la fila. Ninguno de los tres estaba publicado.

### Claves en las tablas

Siete de las ocho tablas reciben una clave compuesta hecha **sólo de columnas
obligatorias** —receta, montajes de llanta, configuraciones, aprobaciones,
purgadores y cáliperes de pastilla—. Una clave con una columna opcional es la
debilidad HY-B, y en este proyecto ya se reprodujo dos veces.

## Retiros y bajas

30 usos retirados —todos publicados, todos conservan su observación— y 9 campos
dados de baja que nunca se publicaron. **Ningún campo vivo se pierde**,
verificado familia por familia contra la preimagen.

| Familia | Retirados | Dados de baja |
|---|---|---|
| brake_caliper | 10 | 1 |
| brake_lever | 3 | 0 |
| brake_pad | 2 | 0 |
| hydraulic_disc_brake | 8 | 1 |
| mechanical_disc_brake | 3 | 0 |
| rim_brake | 1 | 3 |
| rotor | 2 | 0 |

## Verificación

**80 pruebas Dart verdes**: 7 de metadatos y 73 casos —23 heredados, 9 de ellos
con traducción explícita, y 50 nuevos—. No toqué `lib/`, así que no repetí la
batería del motor.

**El publicador de las 37 acepta el paquete**, verificado contra la preimagen
viva restringida a estas siete. No generé migración.

**Veintiséis mutantes en total, todos mortales**: los dieciséis de la primera
ronda y diez más sobre lo que cerré ahora — el orden de los espesores, el orden
que **no** debe existir sobre la medida actual, el prerrequisito del método, las
dos compuertas de la conversión, la de los puertos, las claves de puertos y de
circuitos, el enlace de configuración y la obligatoriedad de los selectores.

Dos de ellos valen doble. El del enlace de circuito mata además la regresión
heredada `brake_link_label_is_not_id`, así que la traducción conservó lo que esa
prueba afirmaba. Y el del orden sobre la medida actual **falló primero por mi
culpa**: escribí el par al revés, y un par `[a, b]` significa `a ≤ b`. Corregido,
mata exactamente el caso del rotor gastado, que es lo que había que demostrar.

**Dieciséis mutantes de la primera ronda.** El detalle está más abajo, pero lo que importa es lo que
me enseñaron: **tres no mataban nada al principio**. Dos porque mis afirmaciones
de pendiente eran ciertas por una razón ajena —esos campos ya traían un
prerrequisito sobre `spec_evidence_source`, y esa pendiente satisfacía la
aserción mientras la compuerta bajo prueba no hacía nada—. Llené la evidencia en
esas fixtures para que la única fuente posible de la incidencia sea la compuerta.
Es la tercera vez que este proyecto encuentra el mismo patrón y ya es rutina
buscarlo.

| Mutante | Caso que cae |
|---|---|
| abrir el convertidor externo | hidráulico y de cable dejan de rechazarlo |
| quitar la clave de la receta | la misma receta dos veces |
| abrir la receta en el cáliper | receta en cáliper de llanta, y la heredada del espesor |
| abrir el conteo de pistones | pistones en cáliper de llanta |
| abrir el tiro exigido del cáliper | tiro en cáliper hidráulico |
| abrir el tiro entregado de la maneta | tiro en maneta hidráulica |
| quitar la clave de montajes | el mismo montaje dos veces |
| quitar el par ordenado del montaje | reach invertido, nuevo y heredado |
| quitar la clave de configuraciones | la misma configuración dos veces |
| quitar la clave de aprobaciones | la misma aprobación dos veces |
| quitar la clave de cáliperes de pastilla | el mismo cáliper dos veces |
| quitar el orden de espesores del rotor | descarte mayor que el nuevo |
| abrir la restricción de compuesto | rotor sin material declarado |
| abrir la herramienta del rotor | rotor sin montaje declarado |
| abrir el nombre comercial del compuesto | compuesto sin clase declarada |
| abrir el compuesto por superficie | compuesto de disco en un patín de llanta |

## Traducciones heredadas

Seis de las 23 heredadas cambian de dueño y cada una lleva su
`successor_translation`: el código de latiguillo pasa a la tabla de conexiones,
el espesor admitido pasa a la receta, el par de reach pasa a la fila del montaje
—donde el rechazo cambia de `range_order` sobre dos escalares a `row_shape` sobre
la tabla, sin dejar de rechazar— y el `reach_adjust` sale del escenario del
cáliper porque esa propiedad no es suya. **Ninguna expectativa se ablanda**: lo
que bloqueaba sigue bloqueando.

## Segunda ronda: los tres gates cerrados

### El espesor del rotor: tres cifras, y sólo dos ordenadas

Tenías razón en que quitarle la unidad a un campo nuevo para que el comparador
aceptara el par era el arreglo equivocado: compraba un orden tirando lo único que
hace legible un número. La definición viva `rotor_thickness_mm` **se conserva
intacta con su historia** y su uso se retira; entran tres sucesores con semántica
y unidad explícitas, más el método:

- `rotor_nominal_thickness_mm` — el espesor de un rotor nuevo.
- `rotor_wear_limit_mm` — el límite que publica **ese** fabricante.
- `rotor_measured_thickness_mm` — lo que mide **esta pieza usada** hoy.
- `rotor_thickness_measurement_method` — prerrequisito del anterior.

Sólo el nominal y el límite se ordenan entre sí. **La medida actual no se compara
con ninguno de los dos**, porque un rotor gastado mide por debajo de su límite y
eso es precisamente lo que es: un estado, no un nominal imposible. Un caso lo
fija con 1,4 bajo un límite de 1,5, y el mutante que sí ordena esa pareja lo mata.

Esto sale de Sheldon, abierto y leído: el rotor «becomes thinner as it wears»; el
descarte es por marca —1,5 mm en la mayoría, 1,7 en una y 1,52 en otra—, así que
un límite sin su fuente no es un límite; y el espesor «cannot be measured directly
with a conventional vernier caliper, due to the concavity», que es por qué la
medida declara cómo se tomó.

### Las conexiones: dos dueños distintos, ninguno fingido

No toqué la definición compartida. En su lugar entran dos esquemas, cada uno con
el dueño que de verdad tiene:

- **`brake_piece_hydraulic_ports`** para el cáliper y la maneta. Una pieza suelta
  **es** la dueña de sus puertos, así que no hay padre que resolver y nada
  pretende que lo haya. Clave: el identificador físico del puerto, de modo que
  cambiar de apartado no permite repetirlo con otro conector.
- **`brake_circuit_connections`** para los conjuntos. Cada extremo nombra su
  configuración y el motor **la resuelve**: un `configuration_row_id` que apunta
  a una fila ausente bloquea.

El uso de `brake_hydraulic_connections` se da de baja en las cuatro familias.
Comprobado contra la preimagen: **no está publicada en ninguna de las 37**, así
que darla de baja no pierde ninguna observación y evita cuatro filas legacy
vacías. La definición queda intacta para sus otros consumidores.

### El `circuit_id` del cáliper ya no finge

Era el mismo defecto visto desde el otro lado: en un conjunto el enlace resolvía;
en un cáliper suelto apuntaba a la nada y nadie lo notaba. Ahora el cáliper tiene
puertos propios y el conjunto tiene enlace real.

## Todas las ramas, no sólo los tres gates

Auditadas por cómputo y no a mano: **todo campo que alguna compuerta lee es
obligatorio**, calculado desde las propias compuertas, así que un selector sin
contestar deja la ficha **pendiente** en vez de darla por terminada. Cuatro
selectores en el cáliper, tres en la maneta, dos en pastilla, dos en freno de
llanta y dos en el rotor; cero en los dos conjuntos, y eso es correcto y no un
descuido: en un freno hidráulico completo no hay rama que discriminar, todo es
hidráulico por definición. Tres casos fijan la pendiente y el mutante que las
vuelve opcionales los mata.

## La conversión, corregida por la fuente

Mi primera versión daba por hecho que una pieza híbrida la acciona siempre un
convertidor externo. **TRP HY/RD dice lo contrario con sus palabras**: «Using an
open hydraulic system it's compatible with Shimano and SRAM 11 speed road shift
levers», con «True 'plug-and-play' compatibility with existing cable actuated
systems». El cable llega al cáliper y la conversión ocurre **dentro de él**; no
hay dispositivo que nombrar, y un esquema que lo exigiera habría dejado sin
representar al híbrido más común del mercado.

Así que la pieza híbrida declara primero **dónde** ocurre la conversión, y sólo
si es en un dispositivo aparte se pregunta cuál. Cuatro casos: la conversión
interna pasa; la interna que además nombra un convertidor externo se rechaza; la
externa con su dispositivo pasa; y un cáliper hidráulico puro no declara
conversión ninguna. La página **no publica su fluido**, así que el fluido queda
ausente y pendiente, no inventado.

## Gates abiertos, dichos como tales

- **`brake_hydraulic_connections` sigue sin clave, y sigue intacta.** No es de
  este bloque arreglarla; lo que hice fue dejar de usarla. El compilador ahora
  **se niega** a keyear una definición publicada, que es como descubrí que la
  estaba tocando.
- **`rotor_thickness_mm` sigue sin unidad en producción**, ahora retirada de uso
  aquí. Ponerle la unidad —o decidir cuál de las tres cosas significaba— es una
  decisión sobre una definición compartida y sus observaciones, aparte de este
  candidato.
- **El fluido del HY/RD no está publicado por TRP** y no lo inventé. Cualquier
  ficha de esa pieza queda con su aprobación de fluido pendiente.
- **`rotor_diameter_mm` sigue retirado con valores compuestos** («160/140»), que
  metían dos posiciones en un token. Su sucesor por posición es la receta; la
  definición no se toca.
- **No adjudiqué ninguna compatibilidad mecánica.** El esquema se niega a guardar
  dos respuestas para el mismo dato; que una pastilla concreta sirva en un
  cáliper concreto sigue siendo afirmación del fabricante.

## Fuentes

- **Sheldon Brown, Disc Brakes** — abierta y leída por mí en esta ronda. De ahí
  salen las tres cifras del rotor: que se adelgaza al usarse, que el descarte lo
  fija cada fabricante, y que un rotor gastado no se mide con un pie de rey
  corriente. También que hay que usar el fluido correcto **sin decir cuál**, que
  es razón para exigir la fila de aprobación y no para adivinar una clase.
- **TRP HY/RD** — abierta y leída por mí. Corrigió mi diseño del convertidor.
- **Sheldon Brown, Cantilever Brakes** — abierta y leída por mí. De ahí sale la
  separación entre lo que una maneta entrega y lo que un freno exige: la página
  advierte que unas manetas convencionales con cantilevers de tiro directo «will
  usually not pull enough cable», y que al revés hay que apretar el doble.
  También da los pivotes en sitios distintos según el tipo de freno, que es por
  qué el montaje es un hecho de la fila y no un escalar del producto.
- **Park, Basic Thread Concepts** — leída en este mismo bloque de trabajo para
  las roscas; no la cito aquí porque no aporta a frenos.
- **Citas que retiré, y una ruta que abandoné.** Había referenciado la página de
  servicio de rotores de Park; **da 404**. Probé dos rutas más de ese blog para
  el tema de pastillas y rotores —`disc-brake-pad-and-rotor-service` y
  `disc-brake-pad-replacement`— y las dos también dan 404, así que dejé de
  adivinar por ahí y fui a las fuentes de arriba. Park sí responde en otras rutas
  que este proyecto ya usa; lo que no hago es seguir probando slugs.
- **Fixtures**: mis 34 casos nuevos son sintéticos sobre `example.invalid`. Las
  heredadas conservan su procedencia tal cual —nueve usan `example.com` y tres
  citan páginas de soporte de SRAM dentro de sus filas—. **No abrí esas páginas**
  (dieron 403 en rondas anteriores por esa misma vía) y no las presento como
  lectura mía; tampoco las reescribí, porque cambiar una procedencia ajena que
  puede ser genuina es peor que declarar que no la verifiqué.

## Hashes

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_existing_brakes_catalog.py` | `5f01bfefe574969da7dc59246ab456670be9e3de2b598683ffc0a10be1b58db9` |
| `existing-brakes-catalog-2026-09-07.json` | `f190d29a2a8b1775b060f126323e267cccf1c7a0b76cc4cac20b13336bb266a0` |
| `existing-brakes-cases-2026-09-07.json` | `066cf99106ad02c9470c1622fc79b739c07994e326f53971ad505891d2e88fbc` |

Entradas fijadas por hash al compilar: congelado `16459826…fadf15`, casos
`329ad3e5…3716d7`, preimagen `0a21d85a…08b2a6`.

Totales: 7 plantillas, 62 definiciones, 134 usos de campo, **73 casos**.
