# Mando combinado freno/cambio — sucesor corregido (2026-09-07)

Familia: `brake_shift_combined_control`. Candidato para handoff. Sólo metadatos
locales; sin hechos, asignaciones, migración, publicador, base, git ni runtime.
`mechanical_coverage_complete` y `automatic_fill_authorized` en `false`.

Dos rondas de corrección. La primera cerró el cruce de fluido→maneta de cable
cambiando la propiedad del dato. La segunda cierra los cruces que **tú mediste y
yo no**: semántica de modo mezclada con puerto, un conector que no dependía de
declarar que hubiera extremo externo, y un alcance publicado prohibido donde
debía admitirse.

## Ronda 2 — los cruces, medidos antes de tocar nada

Seis sondas permisivas y una restricción de más. Todas corridas contra el
candidato anterior:

| Sonda | Antes | Ahora |
|---|---|---|
| inalámbrico con once posiciones mecánicas | pasa | bloquea |
| eléctrico por cable con once posiciones mecánicas | pasa | bloquea |
| fricción declarada además inalámbrica y asignable | pasa | inexpresable |
| puerto mecánico declarado asignable | pasa | bloquea |
| `external_hose_connection=false` con conector y especificación | pasa | bloquea |
| conector sin haber declarado el extremo externo | pasa | bloquea |
| veredicto **Compatible** con alcance publicado | **bloquea** | pasa |

La causa de las cuatro primeras era una sola: **dos selectores contestaban
preguntas que se solapan.** `shift_function` significaba indexación y
`shift_port_kind` significaba electrónica, así que la ficha podía tomar uno de
cada uno y decir algo incoherente — «no indexado» más «inalámbrico» se lee como
un mando de fricción que además es electrónico, y un puerto electrónico heredaba
una cuenta de detentes mecánicas porque nada la ataba al modo.

## La corrección: una sola decisión canónica por configuración

`shift_mode`, obligatorio, con cinco valores y sin puerto aparte:

**Mecánico indexado · Mecánico de fricción · Electrónico por cable ·
Electrónico inalámbrico · Sin función de cambio**

De ahí cuelga todo lo demás, y la contradicción deja de tener dónde escribirse:

- **Posiciones de indexación mecánica**: sólo en `Mecánico indexado`.
- **Protocolo** y **asignación de la acción**: sólo en los dos modos
  electrónicos. `commanded_target` pierde el valor «Asignable por programación»,
  que era una función colada dentro de una lista de destinatarios; la
  reasignación pasa a `action_assignment`, que es otra pregunta y no contradice
  a la primera: uno dice **qué** gobierna, el otro **si eso puede cambiarse**.
- **Destinatario, edición y veredicto**: en cualquier modo con cambio.

Las sondas antiguas, corridas tal cual contra el candidato nuevo, ya no llegan a
evaluarse: dan `row_shape` porque las columnas que permitían escribir la
contradicción **no existen**. Es el resultado que se buscaba — no una regla que
la rechace, sino una ficha donde no se puede formular.

### No hay cuenta para el control electrónico, a propósito

Las pulsaciones de un botón no son una indexación de once posiciones. Ponerles
una columna entera al lado de las posiciones mecánicas es exactamente cómo las
dos acabarían leyéndose igual, así que no existe. Si una fuente publica cuántas
entradas tiene un mando electrónico, entra como su propia columna con su propio
nombre, nunca reinterpretando ésta.

### Y una detente no es un plato — ahora con lectura propia

Abrí [Sheldon, Front Derailers](https://sheldonbrown.com/front-derailers.html)
para mi propio dictamen, y es más preciso de lo que yo había escrito. La página
dice que los mandos indexados modernos, en su mayoría, tienen **«extra detent
positions to provide a limited trim capability»**. O sea: la cuenta de detentes
puede **exceder** el número de platos justamente porque algunas son de trim. Mi
formulación anterior —«nunca son coronas»— era falsa por absoluta, y la de
recambio —«depende del modelo»— era cierta pero floja. Lo exacto es que
`mechanical_positions` cuenta **detentes**, que las de trim son detentes extra, y
que si el resto corresponde con los platos lo dice el fabricante.

No añadí columna de trim: ninguna fuente de este bloque publica el desglose, y
la separación correcta el día que lo publique es una columna nueva, no releer
esta cuenta. Las lecturas de root sobre SRAM y sobre esa misma página están en
`combined-control-oem-root-sources-2026-09-07.md` y **son suyas, no mías**; de
ahí no tomé ninguna afirmación, sólo la confirmación de que un cambio
electrónico convive con freno de cable y con freno hidráulico, que el esquema ya
trataba como circuitos independientes y ahora tiene dos casos que lo fijan.

## El conector describe un extremo externo, y lo dice su nombre

`connector_model` y `connection_spec` colgaban sólo del circuito húmedo, así que
una configuración que declaraba **no** tener manguera externa podía describir su
conector igual. Pasan a llamarse `external_connector_model` y
`external_connection_spec` —el alcance en el nombre, no en un comentario— y
cuelgan de `external_hose_connection = true` **además** de la función y el
accionamiento. Si el extremo no se declaró, quedan pendientes; si se declaró que
no lo hay, se rechazan.

## El alcance publicado se admite; en un condicionado se exige

`conditions` estaba permitido sólo con veredicto `Condicionado`, lo que tiraba
justamente la frase que acota una declaración compatible o incompatible. Ahora se
admite en **cualquier** configuración con cambio y se **exige** sólo cuando el
estado es `Condicionado`. Para eso el ayudante de tabla aprende a separar
«admisible» de «obligatorio», que hasta ahora iban acoplados.

Ese acoplamiento tenía además un efecto que sólo se vio al mutar:
`shift_actuation_family_declared` —el texto con que la fuente nombra la familia—
quedaba **obligatorio** en toda fila con cambio, y su pendiente **enmascaraba** la
pendiente que el veredicto condicionado debía levantar. Lo desacoplé, y ahora las
dos afirmaciones de pendiente son las únicas de su fila.

## Ronda 1 — lo que ya estaba cerrado, y sigue

**Una fila hija demuestra que su padre existe, nunca que ambos concuerden.** El
enlace resuelve un `row_id`; no compara celdas. Por eso tres cruces pasaban sin
señal: fluido en maneta de cable, extremo hidráulico en maneta sin freno, y
declaración de cambio en maneta sin función de cambio.

La estructura que lo cierra son tres tablas, y la regla que las ordena es que **lo
que puede contradecirse vive en la misma fila que aquello de lo que depende**:

- **`combined_control_units`** — identidad y nada más: lado, modelo, edición,
  abrazadera, fuente. Sin función ni accionamiento, así que no hay nada que
  repetir abajo. Clave: lado + modelo + edición.
- **`combined_control_brake_configurations`** — un circuito completo por fila.
  Declara su función y su accionamiento, y de esas dos celdas cuelgan líquido,
  tiro, conexión externa y conector. Dos líquidos aprobados son dos filas
  completas con su sistema, su edición y su fuente; no una configuración libre
  que colecciona todas las combinaciones.
- **`combined_control_shift_configurations`** — una configuración completa por
  fila, con su destinatario y su veredicto junto al modo que los hace posibles.

Ninguna clave compuesta incluye una columna opcional: es la debilidad HY-B que
medí y luego reproduje dos veces.

La tabla de contrapartes hidráulicas no está: el otro extremo lo modela
`hydraulic_hose`, que ya posee extremos maneta/cáliper y sus fittings. Tenerlo en
dos sitios obliga a elegir cuál manda.

## Retiros: diez usos, cero definiciones editadas

| | |
|---|---|
| Definiciones **añadidas** | `combined_control_units`, `combined_control_brake_configurations`, `combined_control_shift_configurations`, `combined_control_declared_units` |
| Definiciones **modificadas** | **ninguna** |
| Retiros, sólo del uso en esta plantilla | **10** |

Las once heredadas siguen **byte a byte idénticas** al congelado. Diez quedan en
`legacy` aquí y la undécima, `spec_evidence_source`, sigue activa — ésa es la
lectura exacta de «conserva diez compartidas exactas». `shifter_position` sale
porque contestaba lado y cantidad en una celda comercial, y «Par» junto a una
única fila de mando era una contradicción evitable; `handlebar_clamp_mm` sale
porque daba una abrazadera para dos manetas. Ninguna de las dos definiciones se
toca: `shifter` conserva ambas y `brake_lever` conserva la abrazadera.

`combined_control_declared_units` sigue siendo el conteo propio, entero y con
mínimo cero, comparado con las filas por `row_coherence` v2. No es obligatorio,
no tiene default y su ausencia sólo deja `row_cardinality_pending`.

## Verificación

**52 pruebas Dart verdes**: 1 de metadatos y 51 casos, con la regresión heredada
traducida dentro. No toqué `lib/` en ninguna de las dos rondas, así que no
reabrí la batería del motor: no hay cambio que lo justifique.

**Diecisiete mutantes, todos mortales.** Los nueve de la ronda 2:

| Mutante | Casos que caen |
|---|---|
| abrir la compuerta de posiciones (permiso y exigencia) | inalámbrico, cableado, fricción, sin cambio, y la pendiente de la cuenta |
| abrir sólo el **permiso** de posiciones | los cuatro rechazos, no la pendiente |
| quitar sólo la **exigencia** de posiciones | sólo la pendiente de la cuenta |
| abrir la compuerta de protocolo | protocolo en fricción y en mecánico indexado |
| abrir la compuerta de asignación | mecánico declarado reasignable |
| quitar la cláusula `external_hose_connection` del conector | conector y especificación sin extremo declarado |
| abrir la compuerta del conector entera | además, conector en maneta de cable |
| volver a restringir `conditions` a `Condicionado` | alcance en Compatible y en Incompatible |
| quitar la exigencia de `conditions` | la pendiente del veredicto condicionado |

Y los ocho de la ronda 1 siguen matando lo suyo: compuerta de líquido, de tiro,
la cláusula `brake_function` AND-ada dentro de la del líquido, destinatario y
veredicto, las dos claves compuestas, los enlaces y la cardinalidad.

Dos de esos mutantes valen por lo que revelaron y no por lo que confirmaron. El
de `conditions` y el de la cuenta **no mataban nada** en su primera corrida: mis
dos afirmaciones de pendiente eran ciertas por una celda vecina que también
faltaba. Corregí las fixtures para que cada una tenga **una sola** carencia, y
además desacoplé la exigencia que las enmascaraba. Es la misma lección de la
ronda anterior —una cláusula sin caso que la ejercite no está probada— aplicada a
las pendientes, que son más fáciles de dar por buenas.

## Procedencia

Las 109 URL de las fixtures son `example.invalid`, verificado por conteo de
hosts: ningún otro host aparece. Sheldon y Park viven en comentarios del
compilador, que es donde se leyeron.

## Lo que queda abierto

- **`shift_actuation_family_declared` es texto libre**, y ahora además opcional.
  No hay otra celda tipada dueña del mismo dato con la que pueda contradecirse.
- **`configuration` es una etiqueta libre y está en las claves.** Es lo que deja
  convivir dos aprobaciones completas. Dos filas con la misma etiqueta y el mismo
  apartado bloquean; dos apartados distintos conviven.
- **Un mando puede quedarse sin ninguna configuración**, a propósito: una fuente
  puede publicar sólo identidad. Lo que ya no puede es publicar una propiedad sin
  el modo o la función que la sostiene.
- **Nadie exige un veredicto cuando se nombra un destinatario.** El DSL no tiene
  predicado de presencia, así que una fila que nombra un modelo sin estado queda
  incompleta y no se detecta como tal. Es un hueco real, medido, y no lo tapé con
  una regla aproximada.

## Hashes

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/compile_combined_control_catalog.py` | `8b817bb1f91f1d1acbc6b823fe09022190bfa1654002789c5bdc708e1a06f563` |
| `combined-control-catalog-2026-09-07.json` | `254e75fd0e76b7c0f7dbdd4093794831df0f59a94a13045ea746d457a615a73d` |
| `combined-control-cases-2026-09-07.json` | `b2dda0526f4a1ba1a37520c544376319f80ed1233bff8c621cb5bb94b3ca9c40` |

Totales: 1 plantilla, 15 definiciones, 15 usos de campo, **51 casos**.

Sigue sin ser aprobación mecánica. El esquema representa estas declaraciones y se
niega a contradecirse dentro de una fila resuelta; que un mando concreto gobierne
un cambio concreto es afirmación del fabricante, y el fill sigue en cero.
