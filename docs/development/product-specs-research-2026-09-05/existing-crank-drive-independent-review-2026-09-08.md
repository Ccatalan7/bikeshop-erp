# Revisión independiente: bielas, platos y volantes adjudicados — 2026-09-08

Revisión sólo lectura de `compile_existing_crank_drive_root.py` y de
`existing-crank-drive-adjudicated-{catalog,cases}-2026-09-08.json`. No edité el
candidato ni ningún archivo de Root, no corrí SQL y no toqué motor, GUI,
migraciones ni runtime. Sólo agregados, metadatos y ejemplos OEM públicos.

**Versión revisada.** El catálogo se mantuvo idéntico durante toda la revisión
(`453a5852…975b02`); los casos avanzaron dos veces mientras trabajaba
(`215d01bf…` → `2901d855…`). Todo lo que afirmo abajo está medido contra el
catálogo congelado y reverificado contra el archivo de casos vigente.

## 1. Qué verifiqué directamente

- **Reejecuté el arnés Dart** sobre los archivos publicados, sin modificarlos:
  `+57: All tests passed!` (3 de plantilla y 54 casos). La cifra es correcta.
- **Las 20 definiciones publicadas siguen sin una sola diferencia** de `id`,
  rótulo, tipo, unidad, dominio ni reglas, contra la preimagen.
- **Barrido mecánico**: ningún prerrequisito ni condición apunta a un campo
  `legacy` o ausente en las tres plantillas.
- **Nueve sondas propias** contra el catálogo **sin modificar**, en scratch.
  Una de ellas refutó mi propia hipótesis y por eso el H1 está escrito al
  revés de como lo esperaba.
- No repetí la investigación OEM ya comprobada. El delta no la necesita: se
  apoya en separación de dueño, no en cifras nuevas de fabricante.

## 2. La pista que dejaste, respondida primero

**No encontré ninguna fuga.** Barrí las tres plantillas buscando qué campo
activo sigue admitido siempre —es decir, disponible para un envase de dos
piezas sin dueño—:

- `crank_arm`: sólo `crank_side` y `spec_evidence_source`. Todo escalar por
  pieza —largo, rosca de pedal, rosca de perno, asiento de platos,
  construcción, designación de eje, interfaz y declaraciones— quedó atado al
  envase individual.
- `chainring`: sólo `drivetrain_platform`, `spec_evidence_source` y
  `chainring_package_kind`.
- `crankset`: la lista es larga, pero ahí no es fuga: un volante **es** un solo
  conjunto, y sus escalares describen ese conjunto.

Las tablas de contenido tampoco reabren el hueco: `crank_arm_units` responde
por lado, `chainring_set_members` por plato —ahora también con montaje y cadena
por plato— y `chainring_teeth_rows` y `bottom_bracket_required` ya respondían
por ocurrencia y por combinación.

**Y el mecanismo de copia conserva las compuertas**, que era lo fácil de
perder: una interfaz **de unidad** con geometría estriada rechaza el estándar
de cuadradillo igual que la individual, y una declaración **por plato** con
alcance de interfaz no puede nombrar un modelo. Sondas
`probe_a_splined_unit_interface_also_rejects_a_taper_standard` y
`probe_a_member_interface_claim_cannot_name_a_model`: las dos **pasan**.

## 3. Hallazgos

### H1 · Un campo exigido siempre y admitido sólo a veces queda mudo (medio)

`chainring_mount_type` quedó **requerido siempre** y, tras el delta, **admitido
sólo cuando el envase es un plato individual**. Esperaba una exigencia
imposible; la sonda me desmintió: el motor Dart **suprime la exigencia cuando
el campo no aplica**, así que un juego de platos no produce ni bloqueo ni
pendencia sobre ese campo.

- `probe_a_required_always_field_that_is_inapplicable_is_silent`: juego sin
  montaje, con `forbidden_issue_fields: [chainring_mount_type]` → **pasa**, no
  hay ningún aviso.
- `probe_a_ring_set_that_answers_it_is_blocked`: el mismo juego respondiendo el
  campo → **bloquea** con `field_applicability`.

El resultado en uso es correcto, pero el contrato afirma dos cosas
contradictorias y sólo la supresión del motor las reconcilia. Alinear
`required_when` con `allowed_when` —una línea— deja escrito lo que hoy hay que
deducir. **No pude comprobar que la proyección SQL suprima igual**: si no lo
hace, ese juego pendería para siempre en un motor y estaría limpio en el otro.
Es la única parte de H1 que queda a tu corrida.

### H2 · Un par de brazos puede no declarar ningún largo; uno solo está obligado (medio)

`crank_arm_length_mm` es requerido para el brazo individual, pero
`length_mm` es **opcional** en `crank_arm_units`. Un par completo, con sus dos
filas y sus dos interfaces, valida sin que nadie pida un largo.

- `probe_a_pair_of_arms_needs_no_length_at_all`: par con dos brazos, sin ningún
  largo, prohibiendo avisos sobre `crank_arm_length_mm` y `crank_arm_units` →
  **pasa**: no hay aviso de ninguno de los dos.
- `probe_a_single_arm_must_state_its_length`: brazo individual sin largo →
  `required_missing`, como debe ser.

El contraste está dentro del mismo paquete: `chainring_set_members` **sí**
declara `teeth` como requerido, así que el juego conserva la exigencia que el
plato individual tiene. La familia de platos cruza bien la frontera del envase
y la de brazos la pierde. Corrección: `required=True` en `length_mm`, que es
definición no publicada.

### H3 · La construcción de dos brazos no se puede declarar en un envase de dos brazos (medio-bajo)

`crank_arm_system_construction` quedó admitida **sólo para el brazo
individual**, y a su dominio se le agregó justamente
«Dos brazos con semiejes solidarios y unión central». El efecto es una
inversión: esa opción describe un sistema de dos brazos y sólo puede elegirse
cuando se vende **uno**.

`probe_a_pair_cannot_declare_its_system_construction`: par declarando esa
construcción → **bloquea** con `field_applicability`.

El hecho no se pierde del todo, y lo verifiqué:
`probe_the_split_axle_survives_as_a_per_arm_geometry` —par cuyas dos filas
declaran `interface_geometry: 'Unión de semiejes'`— **pasa limpio**. Pero
geometría de la unión y construcción del sistema no son el mismo campo ni la
misma pregunta, y `crankset_construction` conserva la opción nueva mientras la
plantilla de brazos sólo la ofrece donde menos aplica. Dos salidas baratas:
admitir la construcción también en el par, que es propiedad del envase, o
quitarla del selector del brazo y dejar que la geometría por fila la lleve.

### H4 · Dos selectores globales que retiraste en mandos siguen activos aquí (medio-bajo)

En el paquete de mandos retiraste `drivetrain_platform` y los selectores de
ecosistema a legacy porque «recrean el producto cartesiano», y sacaste
`compatible_rear_speeds` de los dos desviadores para que las velocidades
vivieran dentro de cada configuración documentada. En este paquete:

- `drivetrain_platform` sigue **activo**, con rol `declaration`, admitido
  siempre en `crankset` y en `chainring`;
- `compatible_rear_speeds` sigue **activo y sin condición** en `crankset`, y en
  `chainring` sólo está acotado por tipo de envase.

O las familias de biela son distintas —y entonces conviene decir por qué un
volante sí puede declarar una plataforma y un cambio trasero no—, o el mismo
problema cartesiano que cerraste allá sigue abierto acá. Lo señalo como
contradicción entre adjudicaciones, no como defecto mecánico: los dos campos
tienen prerrequisito de evidencia y ninguno bloquea.

### H5 · El volante conserva el selector de eje que en el brazo llamaste prerrequisito imposible (bajo-medio)

El delta retira `spindle_interface` en `crank_arm` —correctamente: es un
selector publicado de catorce interfaces reales, sin término para un eje de
motor, y era requerido siempre— y lo sustituye por una tabla de interfaz
documentada con dueño del eje, designación exacta, geometría y estándar
condicionado. En `crankset` ese mismo campo **sigue activo y requerido
siempre**, sin retirar y sin tabla equivalente.

Dos consecuencias concretas: un volante para eje de motor central queda con el
mismo hueco que acabas de cerrar en el brazo, y la misma unión física pasa a
describirse con dos vocabularios que no se comparan —el volante responde
`Cuadrado JIS`, el brazo responde geometría `Cuadradillo` más designación y
estándar—, justo cuando emparejar un brazo con un volante es la consulta que
ese dato existe para responder. Entiendo que acotaste el delta al brazo; lo
dejo dicho con su costo para que sea una decisión y no un olvido.

## 4. No-hallazgos verificados

- **La pendencia del eje de motor ya no contradice al delta.** En la versión de
  casos que leí primero seguía presente
  `an_integrated_motor_spindle_has_no_published_token`, que declara que el
  campo requerido no se puede responder: exactamente lo que este delta
  resuelve. En el archivo vigente ya **no está**, y quedan seis pendencias.
  Lo anoto sólo para que conste que se revisó y está cerrado.
- **Cada plato del juego posee su desplazamiento, su emparejado y sus
  declaraciones**, con vínculo real a la fila del plato: una referencia a un
  plato ajeno bloquea con `row_reference_unresolved`, y el juego no puede
  heredar un desplazamiento único.
- **Cada brazo del par posee su interfaz y sus declaraciones**, con el mismo
  vínculo, y el par no puede heredar una sola interfaz de eje.
- **El par es exactamente dos**, por dominio del contador.
- **La geometría estriada no admite estándar de cuadradillo**, y la compuerta
  viaja a la tabla del par por copia de `row_conditions`, no sólo en la
  individual.
- **La construcción no autoriza compatibilidad**: el helper lo dice y ningún
  campo la usa como condición de otro.

## 5. Límites de esta revisión

No corrí SQL, adopción ni publicador, así que la paridad de la supresión de H1
entre los dos motores queda sin verificar por mí y no la doy por buena en
ninguna dirección. No reabrí las fuentes OEM ya comprobadas la ronda anterior,
porque este delta no depende de cifras nuevas de fabricante. Nada de lo
verificado aquí aprueba un montaje ni autoriza llenar un producto: los 54 casos
siguen siendo representaciones sintéticas, con `facts_verified_for_product` y
`automatic_fill_authorized` en falso.

---

# Cierre de H1–H5 — implementado 2026-09-08

Root me transfirió propiedad **temporal** de
`scripts/inventory/compile_existing_crank_drive_root.py` y de sus dos salidas
para implementar los cinco cierres. No toqué la propuesta original
(`compile_existing_crank_drive_catalog.py`), ni publicadores, SQL, motor, GUI o
documentos globales. Sin escrituras de producción ni llenado.

## Hashes nuevos

| archivo | sha256 |
|---|---|
| `scripts/inventory/compile_existing_crank_drive_root.py` | `6807ae7c…858ac82` |
| `existing-crank-drive-adjudicated-catalog-2026-09-08.json` | `b477332c…48b5458` |
| `existing-crank-drive-adjudicated-cases-2026-09-08.json` | `f5dbf16c…376f8da4` |

Salida: 3 plantillas, **56 definiciones**, 70 usos de campo, **69 casos y 8
pendientes**. Determinista: dos corridas, bytes idénticos. Las **20
definiciones publicadas siguen sin una sola diferencia**; el compilador aborta
si alguna cambia o si queda una definición sin dueño.

## Ejecutado

`+72: All tests passed!` — 3 de plantilla y 69 casos, primera corrida sin
fallos, con el arnés parametrizado.

**Diez mutantes acotados** sobre el catálogo generado, con los mismos casos.
Cada uno mata exactamente lo que nombra:

| mutante | caso que cae |
|---|---|
| largo de brazo opcional otra vez | `car_a_pair_without_an_arm_length_is_pending` |
| sin columna de construcción por brazo | `car_each_arm_declares_its_own_system_construction` |
| construcción escalar admitida siempre | `car_a_pair_cannot_declare_one_system_construction` |
| plataforma reactivada en el volante | `ckr_the_retired_cross_lists_no_longer_answer` |
| lista de velocidades reactivada en el plato | `crr_the_retired_cross_lists_no_longer_answer` |
| selector de eje reactivado en el volante | `ckr_the_retired_axle_selector_no_longer_answers` |
| sin compuertas de fila de la interfaz | los tres casos de cuadradillo más el de dueño |
| sin compuerta de dueño del eje | `ckr_an_offered_axle_names_no_owning_system` |
| sin vínculo por miembro | `car_a_foreign_arm_interface_blocks` |
| interfaz individual admitida en el par | `car_a_pair_cannot_inherit_one_axle_interface` |

## Los cinco cierres, uno por uno

**H1 · `required_when` alineado con la aplicabilidad.**
`chainring_mount_type` pasa a exigirse **sólo** cuando el envase es un plato
individual, igual que su `allowed_when`. El barrido confirma que ya no queda
ningún campo exigido siempre y admitido a veces en las tres plantillas.
Advertencia honesta: **este cierre no es observable en Dart** —el motor ya
suprimía la exigencia inaplicable, y confirmaste que SQL también—, así que su
valor es que el contrato deje de afirmar dos cosas distintas. Para que la
conducta quede fijada y no supuesta, ambos lados están escritos como caso:
`crr_a_set_is_not_asked_for_a_package_mount_type` y
`crr_a_single_ring_is_still_asked_for_its_mount_type`.

**H2 · Largo requerido en cada brazo.** `length_mm` pasa a requerido en
`crank_arm_units`. Los positivos quedaron completos: cada fixture de par lleva
largo en sus dos filas, y se agregó
`car_a_pair_without_an_arm_length_is_pending`, que deja `row_incomplete` cuando
falta el largo de un brazo. Ahora el par exige lo mismo que el brazo suelto.

**H3 · Construcción del sistema por brazo.** `crank_arm_units` gana la columna
`system_construction` con **la misma taxonomía** que el campo individual,
incluida la construcción de semiejes con unión central. El escalar sigue
admitido sólo para el envase individual, así que **no vuelve una declaración
global a todo el par**: `car_each_arm_declares_its_own_system_construction`
muestra la forma correcta y `car_a_pair_cannot_declare_one_system_construction`
bloquea la incorrecta.

**H4 · Listas globales retiradas a legacy.** `drivetrain_platform` y
`compatible_rear_speeds` quedan `legacy` en volante y plato, conservando sus
observaciones; ninguna definición queda sin dueño y ningún prerrequisito o
condición apunta a ellas. Sobreviven las declaraciones por destino, por
configuración y por pieza: las tablas de declaraciones con su componente y su
grado, `chain_declaration` por plato del juego, y las combinaciones de
pedalier. La ayuda de la fuente dice explícitamente que **una lista descriptiva
no aprueba un montaje**, y una pendencia lo repite para que reconstruir la
lista no cuente como cierre. Los dos casos de retiro usan un valor **fuera de
dominio**, así que prueban que el campo se despoja y no sólo que calla: un
selector activo lo habría rechazado.

**H5 · Una sola representación tipada de la unión biela/eje.** Una definición
nueva compartida con nombre neutro, `crank_axle_interface_declarations`
(`used_by: crankset, crank_arm`), y una variante por miembro,
`crank_axle_interface_by_member`, con vínculo real a la fila del brazo. Cada
fila declara:

- **rol de la unión** (`junction_role`, requerido): eje ofrecido por esta pieza
  o asiento que lo recibe;
- **sistema dueño cuando corresponde** (`axle_owner`): admitido y exigido
  **sólo** cuando la pieza recibe el eje —una pieza que lo ofrece no nombra un
  sistema dueño, y eso bloquea;
- **geometría documentada** (requerida) y **designación exacta** (requerida);
- **estándar de cuadradillo** condicionado a la geometría de cuadradillo;
- **fuente en cada declaración** (`source_document` requerido).

El selector publicado `spindle_interface` queda `legacy` en **ambas** familias,
con sus observaciones y **sin ampliar su dominio**: un eje de motor central se
describe por designación y geometría documentadas, nunca convertido en JIS o
ISIS. La regresión mecánica no se perdió con el retiro: la prohibición vive
ahora en la representación nueva, y se ejerce en las tres superficies —brazo
individual, brazo del par y conjunto—.

## Qué queda abierto

1. **Publicador, SQL y adopción** siguen siendo de Root; no corrí SQL.
2. **La relación dirigida sigue faltando**: dos uniones tipadas que se leen
   igual no son compatibles. Está escrito como pendencia
   `the_axle_junction_still_needs_a_directed_relation`.
3. **La lista descriptiva no es aprobación**: pendencia
   `a_descriptive_list_is_not_a_mechanical_approval`, para que reconstruir un
   selector global no se cuele como cierre.
4. **La pendencia del eje de motor no vuelve.** Decía que el campo requerido
   no se podía responder, y H5 lo responde con la unión tipada; al reescribir
   el compilador la reintroduje sin querer y la quité de nuevo antes de cerrar.
5. **Las cinco pendencias heredadas** siguen vigentes: identidad en el
   producto, JIS/ISO no deducible por marca, pulgadas de una biela americana,
   ancho de caja en un título y las columnas de intercambiabilidad no mapeadas.
6. **Ninguna familia está completa y ningún producto se llenó.** Los 69 casos
   son representaciones sintéticas, con `facts_verified_for_product` y
   `automatic_fill_authorized` en falso y `mechanical_coverage_complete: false`.
7. **La propiedad de estos tres archivos vuelve a Root** con este cierre, para
   que incorpore el delta al catálogo integrado y renueve hashes.
