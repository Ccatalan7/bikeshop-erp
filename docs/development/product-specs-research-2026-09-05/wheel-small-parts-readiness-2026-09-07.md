# Rueda y piezas pequeñas: nueve familias (revisión ampliada)

2026-09-07. Sustituye a la versión 1 de este archivo. Catálogo inmutable
`all-family-port-cardinality-integrated-2026-09-07.json`
(`16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`). Paquete:
`wheel-small-parts-readiness-2026-09-07.json` —
`29911905eb6f0464ec49028443632528bde517d1dc3236ecd320c6dfd72327cd`.

Sólo lecturas de artefactos, código y fuentes públicas. Sin base de datos, runtime, git, escrituras ni
subagentes. Ningún relleno ni reasignación. **Ninguna fixture de este informe prueba calce**: todas
documentan declaraciones.

## Resultado, y retiro del anterior

**Mi «siete de nueve sin cambios» no se sostiene.** Con la evidencia que pediste, **ocho de las nueve
tienen un defecto de representación**; sólo `tubeless_tape` queda limpia. Ninguno impide publicar
metadatos, y todos importan antes de abrir el llenado.

## Correcciones a mis propias afirmaciones

**C-1 · WS-2 no era ejecutable.** Tienes razón: `value_when` existe **sólo** para celdas de fila
—vive en `product_spec_row_conditions.dart` y en `product_spec_row_condition_metadata.py`— y no hay
equivalente escalar. La alternativa sí ejecutable es la negación escalar:
`spec_rule_evaluator.dart:153-160` acepta `eq`, `neq`, `in`, `not_in`, `contains_any`,
`contains_all`, más `is_set`/`not_set` y `lt/lte/gt/gte`. Entonces la corrección es **`allowed_when`
sobre `axle_hollow` con `not_in` sobre los dos tokens «Hueco …»**: si la rosca ya declara el hueco,
el booleano deja de ser aplicable y cualquier valor da `field_applicability` bloqueante. Se comporta
bien con lo desconocido: con la rosca sin responder, la línea 164 devuelve `SpecTruth.unknown`, así
que el booleano queda pendiente y no bloqueado, y `required_missing` tampoco salta porque exige
aplicabilidad `yes`.

**C-2 · WS-1: afirmé de más.** Dije que ninguna de `rim`, `rim_strip`, `tube` y `tubeless_valve` está
publicada. Lo derivé de los tres packets, que sólo cubren nuestros tres bloques y no las 37 plantillas
globales anteriores. Ya nos pasó: la preimagen encontró `pedal_thread` como compartida histórica que
el catálogo no marcaba. Lo correcto: **no aparece en nuestros tres packets; si existe de antes, lo
dirá tu preimagen.**

**C-3 · La etiqueta no es identidad de forma inexorable.** En la base, `id` y `code` de una opción son
estables y una migración puede cambiar sólo `label` conservándolos. Lo que regenera ambos es
**recompilar** el paquete desde una etiqueta cambiada, porque los dos se derivan de ella. Corregir
antes de publicar evita necesitar esa migración; no es que después sea imposible. Vale para WS-1 y
WS-5.

## Hallazgos nuevos

### WS-6 · `spoke_nipple`: falta el eje de la llave

Park Tool organiza la selección por la **medida entre caras** del niple y la publica en el nombre de
cada herramienta: SW-0 3,23 mm, SW-1 3,30 mm, SW-2 3,45 mm, SW-3 3,96 mm. Y el SW-15 es de niple
**interno**, un accionamiento distinto. El catálogo tiene `nipple_head` —Cuadrado, Hexagonal, Doble
cuadrado, Otro— que es la **forma**, y nada para la medida ni para interno frente a externo. Con la
ficha completa no se puede contestar qué llave pide el niple, que es la pregunta del taller.

*Mínimo:* dos ejes junto a `nipple_head` —medida entre caras y accionamiento—, como declaraciones del
fabricante. Positivo: niple cuadrado con 3,45 mm declarados. Negativo: hoy un niple de 3,23 y otro de
3,45 son indistinguibles. Desconocido: medida no publicada → pendiente, y no se deduce de la forma.

### WS-7 · `tube_repair`: el alcance de material declarado no tiene campo

Park Tool acota el VP-1 a cámaras de butilo y lo excluye de cuerpos tubeless y de cámaras de TPU,
nombrando Tubolito y Schwalbe Aerothan. **Y conserva una excepción**: un pinchazo en tubeless UST u
otro con forro interior de butilo sí puede repararse con un kit vulcanizante. La familia sólo tiene
`repair_kind`, conteos, tamaño, volumen de pegamento y `toluene_free`.

*Mínimo:* filas de alcance declarado —material o carcasa de destino, compatible sí/no, condiciones y
fuente— capaces de guardar la excepción. **No** un booleano universal «sirve para tubeless»: la propia
fuente lo desmiente, y por eso no lo propongo. Esto documenta lo que el fabricante dice de su
producto; no certifica que un parche pegue en una cámara concreta.

### WS-8 · `tire_liner`: se exige BSD donde el fabricante publica designaciones

Mr Tuffy vende por designación nominal, y **una misma referencia abarca dos asientos de talón**: la
roja se lista como «700x20-25 | 27x1 1/8», y existen «26x1.95-2.5», «29x1.9-2.35» y «700x28-32».
`bead_seat_diameters_supported` es requerido y su única columna es un entero en mm, así que llenarlo
obliga a **convertir** 700c y 27" a milímetros — justo lo que no se hace — y ni siquiera da un valor
único. Encima `tire_width_min_mm`/`max_mm` es un intervalo único aplicado sobre la lista de diámetros:
afirma el producto cartesiano de anchos por diámetro, que no es lo que el fabricante pareó.

*Mínimo:* una fila por designación publicada, con la designación literal y, opcionalmente, el diámetro
y los anchos **de esa fila**. Es el patrón de tres representaciones de `wheel_size_declarations`, ya
aprobado. Negativo actual: BSD 622 y 630 con un solo intervalo 20-25. Desconocido: sin designación,
pendiente.

*Límite de fuente:* `mrtuffy.com/sizes` devolvió HTTP 500 y no lo leí. Las designaciones salen de
títulos de producto de varios minoristas independientes, uno de ellos una tienda Trek; la estructura
—una referencia que cubre 700c y 27"— es consistente entre ellos.

### WS-9 · `wheel_retention`: falta un paso real, y un par no admite dos miembros

`thru_axle_thread` ofrece M12 x 1.0, 1.5 y 1.75, y **no M12 x 1.25**. El TRA225 de Robert Axle es
exactamente M12x1.25, 180 mm, para 12x148: un producto real que hoy no se puede describir. Además
`wheel_position` admite «Par» mientras `skewer_length_mm` y `thru_axle_length_mm` son valores únicos,
así que un par cuyos dos miembros difieren no se representa. Y no hay campo para la cabeza ni el
accionamiento —el TRA225 se instala con hexagonal de 5 mm, una aguja clásica lleva palanca— ni para
espaciadores incluidos.

*Mínimo:* agregar el paso al vocabulario; para el par, una fila por miembro con su posición y su
longitud, el patrón de miembros que ya usan `light` y `bike_bag`; cabeza y espaciadores, campos
propios. *Límite:* `what-axle-do-i-need` devolvió 403; el TRA225 se confirma por su ficha de producto.

### WS-10 · `hub_small_part`: un adaptador sin rosca debe declarar una rosca

`hub_part_kind` incluye «Adaptador de eje» y `adapter_to` es texto libre que sí admite una interfaz no
roscada. Pero `axle_diameter_thread` es `required_when: always` en toda la plantilla y su
`allowed_options` son sólo roscas más «Desconocido / sin confirmar». Un adaptador de punteras de eje
pasante no tiene rosca: el operador sólo puede poner una rosca falsa o el token de desconocido, que es
ausencia y deja la ficha pendiente para siempre.

*Mínimo:* condicionar `axle_diameter_thread` a los tipos que sí tienen rosca. Es más pequeño que
añadir una opción y no toca el vocabulario compartido.

### WS-11 · `tubeless_repair`: un repuesto no puede decir a qué herramienta pertenece

Los repuestos de tapón y boquilla se venden por modelo de herramienta. La familia sólo tiene
`plug_count`, `plug_size` —Estándar, Fina, Mixta—, `tool_included` y `kit_members`, cuyo vocabulario
nombra familias y no modelos. Dos repuestos de herramientas distintas son idénticos en la ficha.

*Mínimo:* un campo de herramienta o modelo de destino declarado por el fabricante. No una matriz de
compatibilidad ni una inferencia por tamaño.

### WS-12 · `valve_small_part`: un alargador no declara si exige sacar el obús

`valve_part_kind` incluye «Alargador», pero `core_thread` está condicionado sólo a «Obús (núcleo)» y
nada distingue el alargador que se rosca sobre la válvula íntegra del que exige retirar el obús. Es la
diferencia que decide si sirve con esa válvula.

*Mínimo:* un campo de requisito de extracción del obús, condicionado a «Alargador».

## Veredicto por familia

| familia | veredicto |
|---|---|
| hub_axle | defecto WS-2 (mecanismo corregido en C-1) y hueco WS-3 |
| hub_small_part | defecto WS-10 |
| wheel_retention | defecto WS-9 |
| spoke_nipple | defecto WS-6; WS-5 observación |
| tubeless_tape | **apta** |
| tubeless_repair | defecto WS-11 |
| valve_small_part | defectos WS-1 y WS-12 |
| tire_liner | defecto WS-8; WS-4 a tu criterio |
| tube_repair | defecto WS-7 |

Sigue en pie lo que acepté antes: el acotado por familia de `material` con `allowed_options`, que
`nipple_thread` y `nipple_thread_standard` no son dos dueños, la separación por `retention_kind`, el
par ordenado de anchos de `tire_liner` y `patch_size_mm` como texto.

Compuertas sin cambio: `fill_allowed`, `compatibility_rules_integrated`,
`all_product_assignment_review_complete`, `all_family_domain_review_complete`.
