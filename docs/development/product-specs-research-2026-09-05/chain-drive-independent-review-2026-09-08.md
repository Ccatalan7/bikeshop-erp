# Revisión independiente: cadenas, conectores y kits — 2026-09-08

Revisión sólo lectura del candidato de Root (`compile_existing_chain_drive_catalog.py`,
catálogo `57c6cdbc…fb6a3`, casos `6a2c2781…dd723`, paquete de publicación y
readiness). No edité ninguno de sus archivos, no corrí SQL y no toqué motor,
GUI ni migraciones. Sólo agregados, metadatos y ejemplos OEM públicos.

## 1. Qué verifiqué directamente

- **Reejecuté el arnés Dart** contra el catálogo y los casos publicados por
  Root, sin modificarlos: `00:05 +35: All tests passed!` (3 plantillas y 32
  casos). La afirmación de 35 pruebas es correcta y reproducible.
- **Barrido mecánico de las tres plantillas**: ningún prerrequisito y ninguna
  condición de `allowed_when`/`required_when` apunta a un campo `legacy` ni a
  un campo ausente de la plantilla. Ese es el fallo que deja una pendencia
  imposible de cerrar, y aquí no está.
- **Cuatro sondas propias** contra el catálogo **sin modificar**, con fixtures
  en scratch; las cuatro pasan y por eso las cuatro afirmaciones de abajo están
  medidas, no leídas.

Qué **no** verifiqué, y no doy por bueno por este mensaje: los 32 casos SQL de
avance/repetición/rollback, las tres relaciones en el evaluador, la captura y
adopción de 41 productos y los alias `field_constraint`. Son evidencia privada
y la instrucción de esta ronda me prohíbe correr SQL local.

## 2. Hallazgos

### F1 · El campo de evidencia de la ficha del kit quedó inerte (medio)

`drivetrain_kit` termina con el diccionario de prerrequisitos **vacío**, frente
a ocho entradas en `chain` y siete en `chain_link`. `spec_evidence_source`
sigue activo en la plantilla, pero nada depende de él: una ficha de kit con
miembros y evidencias por fila **no muestra ni una pendencia** sobre el campo
de evidencia de la ficha.

Sonda `probe_kit_evidence_field_is_never_demanded`: valores `kit_members` más
una fila de `drivetrain_kit_member_evidence`, sin `spec_evidence_source`, con
`forbidden_issue_fields: [spec_evidence_source]`. **Pasa**, es decir, no hay
ningún aviso sobre ese campo.

La corrección es de una línea y ya existe en las otras dos plantillas:
`prerequisites['kit_members'] = [EVIDENCE]`, y lo mismo para las tres tablas
nuevas. No propongo motor ni columnas: sólo la simetría que el propio paquete
ya aplica.

### F2 · Un miembro del kit no tiene dónde guardar una medida (medio)

El kit retira, correctamente, las medidas globales: longitud de biela, dientes
de plato, velocidades traseras, familia de caja, interfaz de eje y
homologación e-bike. Pero las tres tablas nuevas —evidencia, interfaces y
destinos— **no tienen una sola columna numérica**: identidad, código,
edición, extremo, designación, condiciones, veredicto y fuente. El resultado
es que la medida de una pieza incluida en un kit no es representable en
ninguna parte: ni global (retirada) ni por miembro (no existe).

Con un solo kit en el alcance el costo hoy es nulo, y por eso lo dejo como
hallazgo de diseño previo a la adopción y no como bloqueante: retirar la medida
global es correcto, pero «sin sucesor» no es lo mismo que «no aplica». Si la
decisión es que un miembro de kit nunca lleva medidas, conviene que quede
escrito en la readiness, porque hoy se lee como un olvido y no como una
decisión.

### F3 · Un modo único de transmisión bloquea una lista de velocidades que la tabla ya sabe repartir (bajo-medio)

`chain_speeds` tiene prerrequisito `['drivetrain_mode', spec_evidence_source]`.
`drivetrain_mode` es un `single_select` publicado con «Derailleur» y «Single
speed / BMX / IGH» como opciones excluyentes, mientras la tabla de
aplicaciones del propio sucesor admite —a propósito y bien— una fila con
desviador externo y otra con cambio interno en la misma cadena.

Sonda `probe_speeds_pend_until_one_mode_is_chosen`: una cadena con evidencia,
`chain_speeds` y dos aplicaciones documentadas, una externa y una interna, sin
`drivetrain_mode`. **Pasa** con `prerequisite` sobre `chain_speeds`: la
pendencia sólo se cierra eligiendo **uno** de los dos modos, es decir,
contradiciendo una de las dos filas que la ficha ya documenta.

El dominio publicado no se puede cambiar, así que la salida barata es mover el
prerrequisito al dueño correcto: que `chain_speeds` dependa de la tabla de
aplicaciones o sólo de la evidencia, y dejar `drivetrain_mode` como
descriptivo, que es exactamente el papel que la readiness le da a la lista de
velocidades.

### F4 · Las cinco fixtures del kit no arman un miembro completo (bajo)

`kit_members` publica seis columnas y **tres son requeridas**: `member_role`,
`family` y `position`. Las filas de las cinco fixtures de kit omiten
`member_role`, así que los cinco casos arrastran un `row_incomplete` sobre
`kit_members` que ninguno declara.

Sonda `probe_root_kit_members_rows_are_incomplete`: las mismas filas de la
fixture, esperando `row_incomplete` sobre `kit_members`. **Pasa**.

No cambia ningún veredicto —`row_incomplete` no bloquea y el conjunto exacto de
bloqueantes sigue correcto—, pero significa que ninguna fixture ejercita un
miembro bien formado, y `member_role` es justo la columna que separa contenido
de configuración. Añadirla a las filas cuesta una palabra por fila.

### F5 · Una declaración sin dueño sólo pende (informativo, no es de este paquete)

Una fila de `drivetrain_kit_member_fitments` sin `member_reference` queda
pendiente y no bloquea: `row_incomplete` por la columna requerida y el vínculo
sin resolver como pendencia. Sonda `probe_a_fitment_without_owner_only_pends`:
**pasa**. Lo anoto porque el objetivo declarado es que una afirmación no se
herede entre piezas, y una afirmación sin dueño no se hereda pero tampoco se
rechaza. Es gramática del motor, común a todos los paquetes de esta serie
—incluidos los míos—, y no una decisión de este candidato.

## 3. No-hallazgos verificados

Los reviso explícitamente porque descartarlos también es resultado:

- **`kit_members` no lleva `unique_by`, y no puede llevarlo.** Es definición
  publicada y su esquema está congelado por la guardia del publicador. Los
  vínculos resuelven por id de fila, no por rótulo, así que dos filas
  parecidas no vuelven ambiguo el enlace.
- **Los `label_columns` de `row_coherence` existen.** `family`, `position` e
  `identity_model` son columnas reales del esquema publicado de `kit_members`.
- **`brand`, `model` y `manufacturer_sku` dentro de los cierres incluidos y de
  la evidencia por miembro no son una fuga de identidad.** Describen **otra**
  pieza física que viene en el envase, no la identidad del producto de la
  ficha, que sigue en su registro canónico. Lo miré expresamente porque es el
  patrón que sí sería fuga si nombrara al propio producto.
- **`chain_profile_family` retirada en las tres plantillas.** Su dominio es de
  ecosistemas —«Universal 5-8v», «Shimano HG+», «SRAM Eagle», «Campagnolo»—,
  así que cae dentro del retiro de ecosistemas globales que la readiness sí
  declara, aunque no la nombre. No es una pérdida silenciosa de un eje
  mecánico.
- **`included_chainring_count` retirado no pierde el contenido**: la cantidad
  de platos suministrados se expresa como `quantity` en la fila del miembro.
- **`kit_contents` aparece en el conjunto `keep` del compilador pero no es
  campo de esa plantilla**: la entrada es inerte, no conserva ni pierde nada.

## 4. Límites de esta revisión

No corrí SQL, ni el evaluador de relaciones, ni la adopción, y no reproduje la
captura de 41 productos: las cuatro afirmaciones de la readiness sobre esas
piezas quedan sin verificación independiente en esta ronda, y no las contradigo.
Tampoco abrí las fuentes OEM citadas por Root en esta revisión, así que no
certifico ni desmiento la lectura de KMC, Shimano, SRAM, Park ni Sheldon: lo
que revisé es el modelo, sus compuertas y su comportamiento medido.
