# Transmisión menor — dictamen independiente (2026-09-07)

Lectura y veredicto. No edité el candidato, el motor, la migración, la base ni
mis archivos de cables. Las sondas corrieron contra el catálogo **sin
modificar**, con archivos de casos propios en el scratchpad.

**Veredicto: publicable.** Los cinco ejes que pediste revisar están verificados
y enforced, uno de ellos mejor construido de lo que dice el documento. Dos
hallazgos: contradicciones **representables y reales** que el esquema acepta en
silencio. Ninguno bloquea la migración; los dos conviene decidirlos antes de
registrar hechos.

## Integridad

Los siete SHA-256 recomputados coinciden exactamente con los declarados,
incluidos los tres que nombraste: catálogo `1dbb2f52…9213`, migración
`9339b819…a1da`, verificador `3897a23d…d7a2`.

Aritmética del paquete verificada: 26 definiciones nuevas + 8 reutilizadas = 34;
49 opciones; 4 plantillas; 39 usos. Coincide con el documento.

Superficie de escritura de `20260908013000`: sólo `spec_templates`,
`spec_template_fields`, `spec_definitions`, `spec_definition_values`, con la
huella de cuatro tablas afirmada dentro de la transacción y el pin del motor
`ac0738d5c2039412b603dc71adc41721` — el mismo que verifiqué en no-transmisión y
en suspensión. Mismo generador y mismas guardas.

**37 pruebas Dart: las corrí yo, pasan.** `mechanical_coverage_complete` y
`automatic_fill_authorized` en `false`.

**Las dos multiplicidades SQL existen y son como las describes.** Las busqué
primero en `expected_sql_issue_subset` y no estaban; están en
`expected_sql_blocking`: `ds_root_no_thread_pitch_on_plain_member` y
`ds_root_track_cannot_claim_cassette_outer_cog` declaran cada uno dos entradas
idénticas `row_field_applicability` sobre el mismo campo. Verifiqué su forma, no
su verdad: no corrí el lado SQL.

## Los cinco ejes, medidos con catorce sondas

Cada sonda esperaba deliberadamente «sin bloqueo», así que cualquier bloqueo
aparece como diferencia.

| Sonda | Resultado |
|---|---|
| paso en una pieza declarada «Sin rosca» | bloquea `row_field_applicability` |
| golilla con accionamiento escalar | bloquea `field_applicability` |
| «Combinación de cassette» sin piñón menor | `row_required_missing` (pendiente) |
| «Piñón máximo» cargando piñón menor | bloquea `row_field_applicability` |
| mismo 42 con 11T y con 10T, dos veredictos | limpio |
| placa apuntando a un montaje inexistente | bloquea `row_reference_unresolved` |
| dos placas con sus propios límites | limpio, sin unir |
| anillo de piñón fijo con rosca propia a derechas | bloquea `row_value_conflict` |
| lo mismo en un anillo de cassette | limpio — no se filtra |

**Un solo valor de paso, y es más fuerte que lo declarado.** No hay dos columnas
de paso que haya que excluir mutuamente: hay **una** `pitch_value` con su
`pitch_unit`. Dos unidades a la vez son imposibles por construcción, no por
regla — que es exactamente lo que yo no supe hacer en DS-1. Y el nominal
escalar `thread` es un `single_select` cerrado que ya incluye `9 mm`, `10 mm` y
`3/8"`, así que el 9 mm × 26 TPI de RCF47 se representa sin ninguna prohibición
por dialecto.

**RoadLink sin universalizar 42T.** `smallest_cog_teeth` es **obligatorio** para
«Combinación de cassette» y **prohibido** para «Piñón máximo»: un 42 solo no
puede declararse como combinación. La fixture `ds_root_roadlink_dm_cassette_pair`
lleva 11–42 «Aceptable» y 10–42 «No compatible» sobre el mismo cambio, y el
ámbito DM viaja en `target_hanger` como texto. La capacidad se conserva aparte
en `capacity_conditions`, y el helper dice que alcance y capacidad son
magnitudes distintas.

**El anillo de piñón fijo.** El `value_when` exige rosca a izquierdas cuando
`application = 'Piñón fijo'` **y** `owner_role = 'Anillo de bloqueo'` **y**
`interface_kind = 'Rosca'`. Es un estándar real, no una política de marca, y
comprobé que no se filtra al anillo de cassette. El antecedente de tres términos
es la misma técnica que resolvió SH-1 en suspensión.

## DT-1 — el nominal de la tabla es texto libre donde el del escalar es vocabulario cerrado

`fastener_component_configurations.thread_nominal` es `text` sin
`allowed_values`. Medido: una pieza con `thread_nominal = 'M8 x 1.25'`,
`pitch_unit = 'tpi'` y `pitch_value = '26'` no produce **ninguna** incidencia. El
nominal afirma un paso métrico y la celda explícita afirma 26 hilos por pulgada,
y la ficha guarda las dos.

La misma contradicción es **imposible** en el escalar: al intentar escribir
`M8 x 1.25` en `thread` la sonda fue rechazada con `option:thread`, porque es un
`single_select`. En este punto concreto la tabla que sustituye al escalar es más
débil que el escalar.

Es la clase de defecto que este proyecto ya documentó con `700x28`: una medida
pegada dentro de un texto que ninguna compuerta mira. El helper dice que la ficha
no convierte un M8 en M8 × 0,75 por su uso — y es cierto que no convierte; lo que
no impide es que el operador escriba el paso dentro del nominal.

Corrección acotada disponible sin tocar el motor: dar a `thread_nominal` el
vocabulario cerrado que ya existe y que este mismo paquete reutiliza
(`thread` viaja en `reused_definitions`), o poner `allowed_values` en la columna.
Las columnas de fila lo admiten: `interface_kind`, `pitch_unit` y `thread_hand`
lo usan en esta misma tabla.

## DT-2 — ninguna de las seis tablas del bloque declara `unique_by`

Las seis llevan sólo `version` y, cuatro de ellas, `ordered_pairs`. Consecuencia
medida, las tres en silencio total:

- mismo extensor, mismo cambio, misma combinación 11–42: una fila
  **«Recomendado»** y otra **«No compatible»**;
- misma placa, mismo montaje, 32T: `installed = true` y `installed = false`;
- mismo anillo, mismo `scope` «Rosca propia», mismo objetivo: rosca propia de
  **30 mm** y de **41 mm**.

El primero cae justo en el eje que pediste mirar con más cuidado, y su gravedad
se ve mejor junto a la fixture insignia del bloque: `ds_root_roadlink_dm_cassette_pair`
es legítima **porque** sus dos filas difieren en `smallest_cog_teeth`. Nada impide
dos filas que no difieran en nada y se contradigan. El esquema no distingue el
par que informa del par que deja al lector eligiendo veredicto al azar.

El mecanismo existe y el bloque hermano lo usa: `shock_end_configurations` en
suspensión declara `unique_by [["size_row_id","end_position"]]`, y su violación
sale como `row_shape` bloqueante. Elegir la clave es un juicio sobre qué columnas
individualizan una declaración —en `hanger_extender_claims` habría que incluir al
menos modelo, cambio, jaula, velocidades, tipo de declaración y los dos piñones,
porque variar cualquiera de ellos sí es legítimo—. Lo que hace silenciosa la
contradicción es que no haya ninguna.

Como en SH-1: no bloquea publicar, porque añadir `unique_by` después es una
edición de contrato que las guardas de deriva obligan a hacer explícita, mientras
que los hechos registrados sobre un par contradictorio son mucho más caros de
deshacer.

## Una tensión que no pude adjudicar

El documento dice que la página de RoadLink contiene una afirmación adicional de
**mejora parcial** para 10–42, y que el caso conserva el estado de su lista de
compatibilidad. El artefacto registra `No compatible` para 10–42, y el
vocabulario tiene `Condicional`, que es donde encajaría una mejora parcial.
**No pude releer la página**: `wolftoothcomponents.com/pages/roadlink-tech-page`
me devolvió sólo navegación y carrito, con el contenido técnico truncado, igual
que me pasó con su ficha del tapón de compresión. Así que no afirmo que la
elección sea equivocada —conservar el estado de la lista es la opción
conservadora— sino que no la pude verificar contra la fuente, y queda anotada por
si al integrar quieres revisar ese único valor.

## Lo que no verifiqué

No re-consulté la preimagen viva de las 01:06:19Z ni la ausencia de colisiones;
no corrí los 33 casos SQL, las cinco regresiones del publicador ni
`.tmp/db/drivetrain-small-parts-publication-tests.log`; no comprobé el respaldo
`20260908T0130Z`. Tampoco verifiqué que la migración de servidor que el archivo
de casos declara como requisito —`required_server_migration: 20260907025000`—
esté aplicada, y de ella depende que el lado SQL mida lo que dice medir. No releí
Wolf Tooth, OneUp ni Sheldon esta ronda; de las fuentes del documento sólo tenía
lectura propia previa de la página de roscas de Park, que sostiene la
independencia entre unidad de diámetro y de paso.

Mi dictamen cubre los siete hashes, la superficie de escritura, la aritmética del
paquete, las 37 pruebas Dart corridas por mí, y la conducta real del contrato y
del motor medida con catorce sondas adversariales.

| Artefacto | SHA-256 verificado |
|---|---|
| `compile_drivetrain_small_parts_catalog.py` | `c00397509c0a4ce6d24d7c5eb48366de4af9f744474bb2f314f2bf78e321a49a` |
| `drivetrain-small-parts-catalog-2026-09-07.json` | `1dbb2f526f09368d34550d5aca249ff4849dbb998fe47ad2bef6afce2a619213` |
| `drivetrain-small-parts-cases-2026-09-07.json` | `63ba1e2adb73aca43fec19c545289a4bc063db01cd9da2a51ea9aa770de62d59` |
| `drivetrain-small-parts-publication-preimage-2026-09-07.json` | `1e8c7dcf491b6f5ee10aabd74095ae3c5eeb184387c2ba9058e68ad5acc6a7d7` |
| `drivetrain-small-parts-publication-packet-2026-09-07.json` | `c8c29ccc44c4e31459857e5a7d2f24cc7734873e7dde65ada775d462a17bac4c` |
| `20260908013000_...templates.sql` (migración) | `9339b8193d8ce567e9a33659bb7ccf5e089886c29004b544e13996f7fd15a1da` |
| `20260908013000_...templates.sql` (verificador) | `3897a23d760390362605444f536769eb74a71474497ffe0f11e89150e768d7a2` |

---

## Adenda 01:55:04Z — DT-1 y DT-2 cerrados, verificados con trece sondas

Revisión acotada de la adjudicación del 18:44. Los siete hashes vigentes
coinciden uno por uno con los declarados; los artefactos **no se movieron**
durante esta revisión.

| Artefacto vigente | SHA-256 verificado |
|---|---|
| `compile_drivetrain_small_parts_catalog.py` | `977358216d6101b786c629b8d3e1a726e922409ae12ab3a64db0ea56d375d7f2` |
| `drivetrain-small-parts-catalog-2026-09-07.json` | `e847f24f1a6cac14a34d90f2cf54a713df621dced5bb2f9a9eda7cc07a10b25d` |
| `drivetrain-small-parts-cases-2026-09-07.json` | `3b9a86eb94fdb6fd5818162936998e9896928d2e25ff94a4217db7c0fac28f12` |
| `...publication-preimage-reviewed-2026-09-07.json` | `0b94c71cd171fbbbaac8936ad1b0319c9e9163142e80217a70ebc3c8d2a556d0` |
| `...publication-packet-2026-09-07.json` | `5f5fc45f590b7df15d962d8b499af86b3f3a21b3fc9a218ac939ada72387740c` |
| `20260908013000_...sql` (migración) | `56f02a5b82208478fcc086ed550dc8562e1afd76f6b92aede315c4e21c4c7eea` |
| `20260908013000_...sql` (verificador) | `2a3b84547900b861873d7b76af32e094e87dc31046bf0cf5717d53e77d8b1cbb` |

**50 pruebas Dart: las corrí yo, pasan.** Aritmética del paquete: 28 nuevas + 8
reutilizadas = 36; 52 opciones; 4 plantillas; 41 usos. Superficie de escritura
sin cambios y pin del motor `ac0738d5c2039412b603dc71adc41721`.

### DT-1 cerrado

`thread_nominal` **ya no existe**. En su lugar `diameter_value` (decimal) y
`diameter_unit` van gobernados por `interface_kind = 'Rosca'`, y la designación
OEM es un camino exclusivo. No queda ninguna celda de texto libre compitiendo
con el paso numérico, que era el vector exacto del hallazgo.

| Sonda | Resultado |
|---|---|
| diámetro 9 mm con paso 26 tpi | limpio — las unidades siguen independientes |
| diámetro **9,5 mm**, fuera del enum histórico | limpio — el universo no se cerró |
| designación OEM cargando además geometría descompuesta | bloquea `row_field_applicability` |
| pieza «Sin rosca» cargando diámetro | bloquea `row_field_applicability` |

El decimal es además lo que hace cierta la frase del documento sobre no cerrar el
universo: comprobé una medida que el `single_select` histórico no admite. Y el
escalar `thread` sigue viajando en `reused_definitions`, sin mutarse, para el
apretador que no es kit.

### DT-2 cerrado

Claves compuestas donde hay identidad de colección, tabla propia para el límite
sin cassette, y una elección inicial que abre lo que corresponde.

| Sonda | Resultado |
|---|---|
| misma configuración completa, «Recomendado» y «No compatible» | **bloquea** `row_shape` |
| misma combinación con **jaula distinta** | limpio — conserva su declaración |
| límite de piñón sin piñón menor, en su tabla | limpio — **no se inventa un cero** |
| forma «Límites de piñón» llenando la tabla de combinaciones | bloquea `field_applicability` |
| «Ambos alcances documentados» abriendo las dos tablas | limpio |
| misma placa, mismo montaje, misma configuración, instalada y no | **bloquea** `row_shape` |
| misma placa con **presentación distinta** | limpio — se conserva |
| dos roscas propias contradictorias del mismo anillo | **bloquea** `row_shape` |
| misma rosca con **edición distinta** | limpio — se conserva |

Las nueve confirman lo que el documento afirma, incluido lo más difícil: que la
compuerta distingue la contradicción de la variación legítima. Las tres tablas
sin `unique_by` —montajes de guarda, piezas de apretador y el legacy
`fastener_kit_members`— son precisamente aquéllas donde una fila repetida no es
contradictoria, así que la ausencia es deliberada y no un olvido.

### La tensión de RoadLink queda resuelta

El documento reporta la relectura: el apartado *11s Cassette Compatibility* de
RoadLink DM dice **Not Supported** para 10–42, y el comentario siguiente habla de
mejora parcial sin nivel de fábrica. La fixture conserva el veredicto de la
lista, guarda la salvedad en `conditions` y el apartado en `source_scope`. Es la
lectura que yo no pude hacer —la página volvió a entregarme sólo navegación—, y
con ella la observación que dejé abierta en el dictamen queda cerrada: el
artefacto registra la lista y no convierte una mejora en soporte OEM.

### Alcance de esta adenda

Verifiqué hashes, aritmética, superficie de escritura, las 50 Dart y la conducta
real de ambas correcciones con trece sondas. **No** corrí los 46 casos SQL ni las
cinco pruebas del publicador, no consulté la preimagen de las 01:41:12Z ni el
respaldo `20260908T014349Z`, y no verifiqué el estado de aplicación.

Un recordatorio que conviene dejar escrito para quien lea los resultados: un
`row_incomplete` o un `row_required_missing` marcan una fila **pendiente**, no un
guardado rechazado. Sólo las incidencias bloqueantes impiden cerrar. Y nada de lo
anterior es aprobación mecánica: el esquema ahora **representa** estas
declaraciones y **rechaza** contradecirse; que un producto real calce sigue
siendo una afirmación del fabricante, no del motor.
