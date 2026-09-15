# Aptitud de representación: 10 plantillas de puntos de contacto

2026-09-07. `pedal`, `pedal_peg`, `grip`, `handlebar_covering`, `handlebar`, `stem`, `seatpost`,
`seat_clamp`, `saddle`, `saddle_cover`. Sobre el catálogo congelado
`all-family-port-cardinality-integrated-2026-09-07.json`
(`16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`) y los informes anteriores.
Paquete: `contact-points-readiness-2026-09-07.json` —
`e8474abf2a5b2b25a509c536dc0a4b1a8cf635c2744856e844fb7dc2c243005f`.

Sólo lecturas de artefactos, código y dos consultas públicas. Sin base de datos, runtime, git,
escrituras ni subagentes. No reinicié la investigación general.

## Resultado

**Las diez son publicables: ninguna tiene impedimento estructural.** Las cinco interfaces que
priorizaste ya están representadas en dos lados y con vocabulario común — eso es lo que hay que
preservar, y lo detallo en §3 porque es el activo del bloque. Hay **un defecto concreto**, en `grip`,
y **una limpieza** que toca `pedal` y `seatpost`.

107 definiciones distintas: 98 nuevas y 9 ya publicadas que se reutilizan sin mutarse. 5 tablas de
filas. Un solo par escalar mín/máx en todo el bloque, y está ordenado — la clase de defecto de MA-1 no
se repite aquí.

## 1. CP-1 · Defecto: `grip` tiene dos diámetros sin decir cuál es la interfaz

`grip_bar_nominal_diameter_mm` es `required_when: always` y `grip_inner_diameter_mm` es
`allowed_when: always`: sin condición, sin token de referencia y sin helper. Las dos son
`used_by: ["grip"]`.

Mecánicamente son ejes distintos. En un puño deslizante el calibre interior es nominalmente el del
manillar; en un lock-on el manguito va montado **sobre** el manillar y su calibre interior es mayor
que 22,2 mm, mientras el manillar que calza sigue siendo 22,2. Los dos números son legítimos, pero
sólo uno es la interfaz — y hoy nada dice cuál, ni impide que se contradigan.

**Evidencia OEM y su límite.** En lo que pude leer, los fabricantes publican **longitud** y **par de
apriete**: ODI da 135 mm y 130 mm según modelo y 4,5–5,0 Nm para el v2.1. No encontré un calibre
interior publicado. Es resultado de búsqueda, no una tabla textual, así que **no propongo eliminar el
campo** sobre esa base. De paso, corrobora que `grip_clamp_torque_nm`, condicionado a los dos
lock-on, está bien fundado.

**Cambio mínimo.** El patrón ya existe en la familia vecina: `handlebar.bar_width_reference` declara
qué mide la anchura —centro a centro en extremos, en manetas, en drops, exterior a exterior—. A `grip`
le falta el equivalente. Sirve un token de referencia sobre el par, o condicionar
`grip_inner_diameter_mm` a donde el fabricante lo publique. Cuál de las dos es tu decisión; lo que no
puede quedarse es que los dos números convivan sin decir cuál es la interfaz.

No propongo derivar calce desde el diámetro, ni un mínimo mecánico, ni que un calibre interior
distinto de 22,2 sea un error.

| caso | valores | esperado |
|---|---|---|
| positivo | lock-on doble abrazadera, nominal 22.2, par 5 Nm | sin incidencia: la interfaz y el par publicado, sin calibre interior |
| negativo | nominal 22.2 **e** interior 31.8 | hoy **aceptado**; con el eje declarado, o queda fuera de alcance o se lee como lo que es |
| desconocido | sólo `grip_attachment` = Deslizante | `required_missing` no bloqueante sobre el nominal; se conserva pendiente |

## 2. CP-2 · Limpieza: reglas vivas sobre campos ya retirados

`pedal.pedal_thread` es `role: legacy` **y a la vez** `required_when: always`.
`seatpost.dropper_actuation` es `legacy` y lleva un `allowed_when` condicional.

Las dos reglas son **inertes**, y esto ya está verificado contra el motor: un campo legacy se elimina
de `values` en `product_spec_contract.dart:174-179` y el bucle por campo lo salta en `:237`, así que
ni el `required_missing` ni la aplicabilidad llegan a evaluarse.

No bloquea nada. Importa porque el próximo lector del contrato va a creer que `pedal_thread` es
obligatorio, y no lo es ni puede serlo. **Cambio mínimo: quitar la regla** — no agregar
`allowed_when: never`, que también sería inerte, como quedó establecido en DL-5.

Positivo: `pedal_thread_standard = 9/16" x 20 TPI` → sin incidencia, el dueño vivo es el estándar con
paso. Negativo: `pedal_thread = 9/16` → ninguna incidencia hoy ni después, el valor no llega a los
hechos. Desconocido: sin nada → `required_missing` sobre el estándar, no sobre el retirado.

## 3. CP-3 · Las cinco interfaces, verificadas

Esto es lo que conviene no romper al publicar.

**Rieles de sillín vs mordazas.** `saddle.saddle_rail_geometry` y
`seatpost_saddle_configurations.rail_geometry` tienen los **mismos siete valores en el mismo orden**:
Redondo 7 mm, Oval 7x9, 7x9.6, 7x10, 8x8.5, Sistema propietario, Otro. Una pregunta de calce es
contestable sin tabla de traducción, que es justo lo que suele faltar.

**Rosca de pedal vs retención.** `pedal_thread_standard` lleva la designación completa —9/16" × 20
TPI, 1/2" × 20 TPI, M14 × 1.25 y 1" × 24 TPI (Shimano Dyna Drive)—, que es la taxonomía de Sheldon
Brown, y está separada de `pedal_type` y `cleat_system`, que son el eje de retención y calas. El viejo
`pedal_thread`, que decía «9/16» sin paso, quedó retirado.

**Diámetro de manillar donde se sujeta cada pieza.** `bar_clamp_diameter_mm` es **una** definición
compartida por `handlebar` y `stem`, condicionada en cada lado por su propia construcción —
`bar_construction = "Manubrio separado"` y `stem_kind`—, y `grip_area_diameter_mm` es otro eje. La
zona de sujeción y la de agarre no se confunden, y `handlebar_covering.inner_diameter_mm` queda
condicionado a su tipo de funda.

**Diámetro de tija vs abrazadera del cuadro.** `seatpost_diameter_mm` es `used_by [seatpost, bicycle,
frame]` y `seat_tube_outer_diameter_mm` es `used_by [seat_clamp, bicycle, frame]`: **definiciones
distintas**. El collarín habla del tubo, la tija habla de sí misma, y el cuadro declara las dos. El
shim tiene además su par exterior e interior. Nota de alcance: esas dos definiciones llegan a `frame`
y `bicycle`, que aún no se publican.

**Control de tija telescópica vs simple longitud.** `dropper_control_kind` y `dropper_cable_routing`
reemplazan a `dropper_actuation`, que mezclaba accionamiento con ruteo en una sola lista.
`dropper_travel_mm` es distinto de `seatpost_length_mm`, y `dropper_control_configurations` exige
`seatpost_scope`, así que un mando compatible no se nombra sin decir para qué tija vale.

Ninguno de estos ejes autoriza a derivar compatibilidad de la medida sola, y no propongo ningún mínimo
mecánico universal.

## 4. CP-4 · Las nueve ya publicadas que se reutilizan

Ninguna se muta. Cualquier propuesta sobre ellas es un forward que afecta a todos sus usuarios, no una
definición inédita — aunque el catálogo congelado todavía las llame `origin: new`.

| definición | publicada en | familias que la usan | aquí |
|---|---|---|---|
| `spec_evidence_source` | bloque 14 | 105 | 10 |
| `color` | bloques 12 y 14 | 37 | 6 |
| `material` | bloques 12 y 14 | 27 | 6 |
| `kit_members` | bloques 12 y 14 | 23 | 1 |
| `pack_quantity` | bloque 14 | 19 | 2 |
| `length_mm` | bloque 14 | 3 | 1 |
| `weight_g` | bloque 12 | 3 | 1 |
| `padding` | bloque 12 | 2 | 1 |
| `conflicting_claims` | bloque 14 | 2 | 1 |

`conflicting_claims` merece el aviso: su otro usuario es `bike_bag`, ya publicada.

## 5. CP-5 · Una observación que comprobé antes de reportarla como defecto

`dropper_control_configurations` y `pedal_bearing_configurations` no tienen columna `source_url`, a
diferencia de las demás tablas de estos bloques. **No es un defecto.** Toda fila lleva un arreglo
`sources` en su sobre, validado como URLs únicas y bien formadas en `product_spec_rows.dart:100-106`,
independiente de cualquier columna. Lo que queda es la observación inversa, y no es de este bloque:
donde la columna existe, la evidencia de una fila puede vivir en dos sitios.

## 6. Veredicto por familia

| familia | veredicto |
|---|---|
| pedal | apta, con la limpieza CP-2 |
| pedal_peg | apta |
| grip | **defecto concreto CP-1** |
| handlebar_covering | apta |
| handlebar | apta |
| stem | apta |
| seatpost | apta, con la limpieza CP-2 |
| seat_clamp | apta |
| saddle | apta |
| saddle_cover | apta |

`seat_clamp` merece una nota, porque revisé una sospecha y era infundada: `clamp_thread`,
`clamp_thread_pitch_mm`, `clamp_bolt_length_mm` y `length_datum` están condicionados a
`clamp_kind = "Aguja / palanca de repuesto"` —son del repuesto, no del collarín— y
`seat_tube_outer_diameter_mm` es incondicional porque todo tipo de collarín, repuesto incluido, se
escala por el tubo al que va. Es coherente.

## Proyección

Nada nuevo respecto de lo ya medido: la tienda no lee fichas, y compras consume los escalares detrás
de la frontera `supplyNeedCriterionFieldsOf`. De los 107 campos, 5 son tablas de filas que esa
frontera ya excluye por tipo.

Compuertas sin cambio: `fill_allowed`, `compatibility_rules_integrated`,
`all_product_assignment_review_complete`, `all_family_domain_review_complete` — todas `false`.
