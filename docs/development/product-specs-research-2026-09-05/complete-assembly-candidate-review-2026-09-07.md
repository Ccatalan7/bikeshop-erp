# Complete assembly: revisión independiente del sucesor de root

2026-09-07. Revisión sólo lectura del candidato de tres plantillas
(`bicycle`, `frame`, `wheel`). No edité ningún archivo de root, no toqué la base
de datos, git ni el runtime. Todo lo que sigue está medido contra los artefactos
entregados; lo que no pude reproducir está dicho como tal.

**Veredicto: publicable.** Los seis cruces que root pidió revisar están cerrados
y cada mecanismo que los cierra es demostrablemente el que bloquea. Hay **una
corrección de documento**, no de código: la frase sobre la unidad local de
`rim_internal_width_mm` no es reproducible y la contradice la propia guarda del
publicador. El resto de las afirmaciones numéricas del documento de root
coinciden exactamente con lo que recomputé.

## Qué verifiqué y con qué

- **Los nueve hashes**, recomputados uno por uno: los nueve coinciden.
- **El arnés propio de root**: 53 pruebas Dart verdes (50 casos más las tres de
  metadata de plantilla), corridas con sus dos archivos congelados. Coincide con
  lo declarado.
- **Una batería independiente de 30 sondas** que escribí contra el catálogo sin
  modificar: 33 pruebas verdes. Ninguna sonda reutiliza un caso de root.
- **Once mutantes** del catálogo, para probar que cada compuerta es la que
  bloquea y no un efecto colateral de otra.
- **Las 16 definiciones compartidas**, comparadas atributo por atributo contra
  la preimagen viva.

Las sondas y los mutantes viven en el scratchpad de la sesión; el catálogo de
root quedó intacto (sus hashes siguen coincidiendo después de la revisión).

## Los seis cruces que root pidió revisar

### 1. Variante ≠ otras tallas

`assembly_variant_identity` tiene `scope` como token de **un solo valor** y
`unique_by [['scope']]`. Eso es lo que impide que una ficha documente dos
variantes: no hay segundo valor de `scope` que ocupar.

- Dos filas de identidad → bloquea `row_shape`. Al quitar ese `unique_by`, el
  caso deja de bloquear: la restricción es la que trabaja.
- Una variante con dos configuraciones pasa; la misma configuración dos veces
  bloquea `row_shape`.
- Las tallas ya no son filas de variante: `bicycle_size_configurations` es una
  declaración colgada de la configuración, con `unique_by
  [['configuration_row_id']]`. Dos declaraciones de talla sobre la misma
  configuración bloquean; dos configuraciones con su talla cada una pasan; un
  rango invertido bloquea por `ordered_pairs`.

### 2. Configuración → miembro → propiedad

La cadena está completa y cada eslabón rechaza un padre inexistente:
configuración→variante, geometría→configuración, montaje→configuración y
reclamo de rueda→miembro dan los cuatro `row_reference_unresolved`. Al vaciar
`row_coherence.links` los cuatro dejan de bloquear a la vez.

Dos refuerzos que no estaban declarados y conviene registrar:

- Una tabla requerida **vacía** bloquea `row_shape`. Una variante sin ninguna
  configuración, o una bicicleta sin ningún miembro de rueda, no pasa. «Requerida»
  aquí significa al menos una fila, no sólo la presencia de la tabla.
- La única tabla de aceptación que no colgaba de una configuración,
  `dropout_hub_acceptance_configurations`, quedó en `legacy` en `frame`. La
  sucesora, `assembly_frame_fitment_claims`, sí cuelga. El eslabón suelto se
  retiró en vez de conservarse en paralelo.

### 3. No duplicar el tipo físico en una fila hija sólo enlazada

Correcto, y verificado por estructura y por sonda. `assembly_component_members`
es la única tabla que declara `kind`, y **todas** las propiedades físicas cuelgan
de ese mismo `kind` en la misma fila: recorrido y eje-a-corona sólo con
`Horquilla`; ojo-a-ojo y carrera sólo con `Amortiguador`; energía sólo con
`Batería`; tensión de salida sólo con `Cargador`. Una fila de `Batería` que
declara recorrido de horquilla bloquea `row_field_applicability`, y ese bloqueo
desaparece al quitar la compuerta: no viene de otro lado.

Dos miembros de tipos distintos conviven; el mismo miembro dos veces bloquea.
Ninguna tabla hija repite el tipo del padre para volver a juzgarlo — el enlace
prueba pertenencia y el tipo vive una sola vez.

### 4. Geometría con datum y signo

- El desnivel firmado tiene **su propia celda**, `offset_value`, sin regla
  `positive`, y por eso admite `-68`. La celda `value` sí es `positive`.
- Una medida de largo que intenta usar `offset_value` bloquea; el desnivel que
  intenta usar `value` bloquea. Las dos direcciones están cerradas, y cada una
  por una regla distinta: al quitar el `allowed_when` de `offset_value` cae la
  primera y la segunda sigue de pie.
- Un ángulo declarado en `mm` bloquea `row_value_conflict` por el `value_when`
  que fija `grados`. Al quitar ese `value_when`, el caso pasa.
- El `datum` forma parte de la clave: la misma medida con dos datums distintos
  convive, y repetida con el mismo datum bloquea.

**Un límite, no un defecto:** una fila de geometría **sin** `datum` no bloquea,
queda en `row_incomplete` no bloqueante. Es la regla del motor para celdas de
fila requeridas estáticamente, igual en los cinco bloques ya aplicados. Lo
señalo porque «geometría con datum» se cumple para la ficha completa, no para
cada fila tomada suelta.

### 5. Puertos de cuadro vs montajes admitidos

Son dos tablas con vocabularios que no se tocan, y el motor lo hace cumplir:

- `assembly_frame_interfaces` describe el **puerto intrínseco**. La forma manda:
  paso y sentido de rosca sólo con `Rosca medida`; designación sólo con
  `Designación OEM sin descomponer`. Un asiento sin rosca que declara un paso
  bloquea, y sigue bloqueando aunque sólo se escriba `pitch` a secas — las tres
  compuertas de rosca son redundantes entre sí, así que hay que quitarlas las
  tres para abrir el hueco. Lo verifiqué con las dos mutaciones.
- `assembly_frame_fitment_claims` describe el **montaje admitido** y sus celdas
  cuelgan del destinatario: ancho de maza sólo con `Maza`, BSD y ancho de
  cubierta sólo con `Neumático`. Un reclamo de neumático que declara un OLD de
  maza bloquea.
- Una caja sin rosca declarada como puerto y un OLD admitido declarado como
  montaje conviven sin interferirse, que es el caso que había que preservar.

### 6. Rueda por miembro, antes que globales

`assembly_wheel_members` lleva perfil de talón, orificio de válvula, ancho
interior, BSD, OLD, radios y todo el bloque de disco **por miembro**. Dos ruedas
con perfil y válvula distintos conviven sin conflicto — que era exactamente lo
que un escalar global impedía. El mismo miembro dos veces bloquea, y el rotor
montado mayor que el máximo bloquea por `ordered_pairs`; ambos mecanismos
mueren al quitarlos.

Los escalares globales quedaron en `legacy`: `rim_bead_profile`,
`rim_internal_width_mm`, `bead_seat_diameter_mm`, `wheel_configurations` en
`wheel`, y `bicycle_wheel_positions` en `bicycle`.

**Aquí sí hay que ser preciso.** Retirar un campo lo saca del formulario y de la
validación, pero **no rechaza un valor que llegue por otra vía**: el validador
salta los campos `legacy` antes de mirar el valor
([product_spec_contract.dart:237](lib/modules/inventory/models/product_spec_contract.dart:237)).
Lo comprobé: una ficha que escribe a la vez `rim_internal_width_mm` global y el
ancho por miembro no levanta ninguna incidencia. No es un defecto de este
candidato — es la semántica de `legacy` en los seis bloques, y existe para que
los datos ya guardados no bloqueen — pero significa que «por miembro antes que
globales» está garantizado para el formulario, no para un payload arbitrario.
Si alguna vez importa cerrarlo, se cierra en el motor, no aquí.

## La corrección: `rim_internal_width_mm`

El documento de root dice que la unidad local de `rim_internal_width_mm` difiere
y que el arnés conserva esa unidad local sin interpretarla, con una guardia que
rechaza uso activo. **No pude reproducir ni la premisa ni la guardia.**

- La definición compartida `rim_internal_width_mm` es **idéntica** en las tres
  fuentes: `unit='mm'`, `data_type` decimal, `validation_rules {positive:true}`,
  mismo `label` y mismo `id`, en la preimagen viva, en el catálogo y en el
  paquete.
- No existe tal guardia. Busqué en los tres compiladores: lo único que lleva ese
  nombre es una **columna** homónima dentro de `assembly_wheel_members`
  (`compile_complete_assembly_root.py:154`), que es una celda de fila nueva, no
  la definición compartida.
- Es más: la guarda de reutilización del publicador compara `unit` —junto con
  `id`, `key`, `label`, `data_type`, `allowed_values` y `validation_rules`— para
  las 16 compartidas, y aborta con *Shared definition must remain unchanged* si
  alguna difiere. El paquete compiló. Una unidad local divergente **habría
  impedido** compilarlo.

El **resultado** que root describe sí se sostiene: el uso es `legacy` en
`wheel`, la definición se reutiliza sin republicarse y no entra en `records`. Lo
que hay que corregir es la explicación, porque afirma una divergencia y un
mecanismo que no existen, y quien lea el documento mañana buscará una guardia
que no va a encontrar.

Las tres diferencias de valores que root sí declara son exactas y coinciden con
producción: `bb_shell_width_mm` con su lista viva de diez anchos,
`rotor_mount_type` con dos tokens y `wheel_position` con tres. Las 16
compartidas coinciden con la preimagen viva en los siete atributos comparados.

## Matriz de mutación

Once mutantes contra las 30 sondas. Cada uno mata al menos una sonda, y nueve
matan exactamente una: no hay compuerta decorativa ni sonda que pase por casualidad.

| Mutación | Sonda que cae |
|---|---|
| quitar `unique_by [['scope']]` de la identidad | dos variantes dejan de bloquear |
| quitar `allowed_when offset_value` | un largo puede llevar desnivel |
| quitar `value_when` de geometría | un ángulo puede medirse en mm |
| quitar `unique_by` de miembros de rueda | el mismo miembro dos veces |
| quitar `ordered_pairs` de rotor | rotor montado > máximo |
| quitar `unique_by` de tallas | dos tallas por configuración |
| quitar `ordered_pairs` de tallas | rango invertido |
| quitar la compuerta de `pitch` | un paso suelto en asiento sin rosca |
| quitar las tres compuertas de rosca | además, el paso completo |
| quitar `allowed_when travel_mm` | una batería con recorrido de horquilla |
| vaciar `row_coherence.links` | los cuatro enlaces colgados a la vez |

## Aritmética del paquete

55 definiciones nuevas más 16 reutilizadas dan las 71; 103 opciones; tres
plantillas; 101 usos. Retiros locales: 32 en `bicycle`, 23 en `frame`, 15 en
`wheel`. `row_coherence` es v1 en las tres plantillas, sin cardinalidades — lo
cual es coherente, porque aquí ningún conteo numérico compite con el número de
filas; la cardinalidad se necesitaba donde había una cantidad comercial que
podía contradecir a los miembros, y este bloque no la tiene.

## Lo que este candidato no hace, y sigue sin hacer

La identidad documental de `assembly_variant_identity` **no reemplaza a
`products`**: es la variante que la ficha describe, no el producto del ERP. El
binding y la adjudicación siguen siendo puerta global antes de cualquier
llenado. El paquete no escribe productos, hechos ni asignaciones, y las banderas
de cobertura y llenado siguen en `false`. Nada de lo que verifiqué es
certificación mecánica: es que el esquema no permite escribir la contradicción.

Todos los datos de mis sondas son sintéticos y usan `example.invalid`.

---

# Adenda 2026-09-07: retiro mi objeción sobre la unidad local

**Mi objeción era falsa, y lo fue por dos errores de método míos, no por una
imprecisión tuya.** El documento de root decía dónde mirar; yo miré en otra
parte y llamé irreproducible a algo que sí se reproduce.

## Error 1: comparé cuatro fuentes y ninguna era la que divergía

Verifiqué congelado, candidato, preimagen y paquete, encontré `mm` en las cuatro
y concluí que no había divergencia. **La divergencia está en la base local**, que
es una quinta fuente que nunca consulté. La lectura guardada
(`.tmp/db/complete-assembly-local-shared-types.json`, con su consulta en el
`.sql` de al lado) da `rim_internal_width_mm` con `data_type=number` y
**`unit=null`**, mientras el resto declara `mm`. De los dieciséis claves
consultadas la base local sólo tiene tres, y ésta es la que difiere.

Mi frase «idéntica en las cuatro fuentes» era cierta y a la vez irrelevante:
comprobé las cuatro que no divergían.

## Error 2: busqué la compuerta sólo en los compiladores

Grepeé los tres compiladores del bloque, no la encontré y escribí que no existe.
**Existe, y está en el arnés de pruebas**, que es donde tiene que estar porque es
el enrutado local el que la necesita:
`scripts/inventory/test_mobility_accessories_publication.py`, funciones
`legacy_only_field` y `main(..., allow_legacy_unit_drift=False)`.

Y es una compuerta estrecha, no un permiso general. La comprobé evaluando el
predicado contra el propio paquete: `legacy_only_field` sólo devuelve verdadero
cuando el campo tiene usos y **todos** son `legacy`. Da verdadero para
`rim_internal_width_mm`, y da **falso** para `spec_evidence_source`, que sigue
activo — es decir, si el que derivara fuera un campo en uso, la corrida se
detendría con *Local routing cannot change an active shared unit*. El log
`.tmp/db/complete-assembly-publication-tests.log` registra exactamente una línea
de retención para ese campo retirado y los cinco PASS detrás.

Anotado sin convertirlo en otra objeción: la llamada que habilita el flag no está
bajo `scripts/` —ahí sólo se ve el valor por defecto `False`—, y el log es lo que
acredita que esa corrida tomó la rama.

## Corrección sobre lo que afirmé de `legacy`

También acoto mi apartado sobre campos retirados. Yo medí que el validador Dart
salta los campos `legacy`, lo cual es cierto, y de ahí salté a que un valor puede
llegar «por otra vía». **Esa sonda no persiste nada**: medí la capa de formulario
y hablé como si hubiera medido la de escritura.

La capa que importa ya está protegida. Según la lectura viva de root
(`.tmp/db/complete-assembly-legacy-writer-live.json`, escritor v2 con MD5
`4000850abcb96fe223f1df53584eadfb`): rechaza `legacy` nuevos o cambiados,
conserva los idénticos, compara contra la observación almacenada y no es
invocable directamente por un cliente autenticado. No es mi medición y no la
presento como tal.

Así que el párrafo «retirar un campo no rechaza un valor que llegue por otra vía»
queda **corregido**: en la capa de formulario el campo desaparece; en la capa de
escritura el valor se rechaza. No queda hueco, no hay trabajo que abrir, y mi
sugerencia de «cerrarlo en el motor» sobraba.

## Lo que sigue en pie

El veredicto no cambia: **publicable**. Las 30 sondas, los once mutantes, la
aritmética del paquete y las seis revisiones dirigidas se sostienen tal como
están. Lo que cae es este apartado, y cae entero.

La lección que me llevo, porque es la que se repite: **irreproducible sólo
significa que no lo reproduje.** Antes de escribir esa palabra hay que decir
dónde se buscó, y buscar donde el documento indica antes que donde uno espera
encontrarlo.
