# Revisión independiente: mandos y desviadores adjudicados — 2026-09-08

Revisión sólo lectura de `compile_existing_shifting_root.py` y de
`existing-shifting-adjudicated-{catalog,cases}-2026-09-08.json`. No edité
archivos de Root, no corrí SQL, y no toqué motor, GUI, migraciones, runtime ni
archivos globales. Sólo agregados, metadatos y ejemplos OEM públicos.

## 1. Qué verifiqué directamente

- **Reejecuté el arnés Dart** contra el catálogo y los casos publicados, sin
  modificarlos: `+51: All tests passed!` (3 de plantilla y 48 casos). La cifra
  es correcta y reproducible.
- **Las 21 definiciones publicadas se conservan sin una sola diferencia** de
  `id`, rótulo, tipo, unidad, dominio ni reglas, comparadas campo a campo
  contra la preimagen.
- **Barrido mecánico de las tres plantillas**: ningún prerrequisito ni ninguna
  condición apunta a un campo `legacy` o ausente. Ocho campos quedan en legacy
  en el mando, ocho en el cambio trasero y nueve en el desviador, todos con su
  observación conservada.
- **Cinco sondas propias** contra el catálogo **sin modificar**, con fixtures en
  scratch. Las cinco pasan, así que las cinco afirmaciones de abajo están
  medidas.
- **Abrí las fuentes yo mismo**, no las di por leídas por el encargo: las dos
  páginas del manual como imagen renderizada —p. 140 desviador delantero,
  p. 197 cambio trasero—, la página de producto RD-U6000 con el navegador
  autorizado después de que WebFetch devolviera **403**, y la vista despiezada
  `EV-FD-R2000-4160` extraída localmente.

Qué **no** verifiqué y no doy por bueno: el SQL, la adopción, y la extensión
estricta compartida `20260908185800`. Tampoco mapeé las columnas de
intercambiabilidad de la vista despiezada, por la misma razón de siempre: esa
asociación no se afirma desde el texto extraído.

**Versión revisada.** Empecé sobre el catálogo `924a7700…d145c39` y los casos
`52778d70…82a57079`. A mitad de la revisión Root aplicó el ajuste de alias SQL
que había anunciado: los casos pasaron a `200db82a…aa63bfd8` con cuatro
`expected_sql_blocking` en `field_constraint` y un alias de subconjunto. **El
catálogo no cambió**, así que la semántica revisada es la misma, y volví a
correr el arnés sobre el par vigente: `+51: All tests passed!`. Verifiqué
además que los cuatro hallazgos siguen presentes en el archivo nuevo.

## 2. Hallazgos

### H1 · La misma página publica el par (48, 50) con dos significados, y el ejemplo se queda con uno (medio)

La página de producto de RD-U6000 dice las dos cosas:

- en la **tabla de especificación**: `Low sprocket Max. 50T` y `Min. 48T`, para
  la columna única de «Rear speeds 11/10»;
- en la **viñeta de características**: `Max low sprocket: 50T (1x11-speed), 48T
  (1x10-speed)`.

La página del manual (p. 197) coincide con la primera lectura: una sola columna
`11/10` con `Low sprocket Max. 50T / Min. 48T`.

Las filas de Root toman la segunda lectura —dos configuraciones, máximo 48 para
1x10 y 50 para 1x11— y **dejan `largest_sprocket_min_teeth` vacío en las dos**,
pese a que la misma página que citan publica ese mínimo. La lectura de la tabla
valida igual de bien: sonda
`probe_the_specification_table_reading_also_validates`, una sola fila de
11 velocidades con mínimo 48 y máximo 50, **pasa sin bloqueos**.

No es un defecto de esquema —las dos columnas existen— sino del ejemplo: dos
lecturas incompatibles del mismo documento pasan la validación, y la que quedó
escrita descarta un número publicado. Corrección de una celda: llenar
`largest_sprocket_min_teeth` con 48 en ambas filas, que es lo que dicen las dos
fuentes.

### H2 · Una declaración que cubre dos conteos de velocidad se parte en dos filas y nada marca que era una sola (medio-bajo)

`rear_sprocket_count` es un entero requerido por fila, así que la columna
`11/10` del fabricante no se puede representar tal cual. Sonda
`probe_one_row_cannot_hold_two_speed_counts`: un valor `11/10` **bloquea con
`row_shape`**, correctamente.

La consecuencia es que una declaración única del fabricante se convierte en dos
filas con límites duplicados, indistinguibles de dos declaraciones
independientes. Con RD-U6000 se nota poco porque los máximos difieren; con
RD-U8000, cuya columna del manual cubre 11 velocidades con un solo juego de
límites, o con cualquier fila `11/10` de límites idénticos, las dos filas
resultantes afirman más de lo que el documento dice. La salida barata ya existe
en el esquema: usar `conditions` para escribir qué conteos cubre la declaración
original, o añadir una columna opcional que las agrupe.

### H3 · Los ejemplos OEM descartan valores publicados en la página que citan (bajo-medio)

Además del mínimo de piñón grande de H1, la fila positiva del desviador
delantero, `fdr_top_gear_bounds_belong_to_the_large_ring`, omite dos datos que
están en la misma p. 140 que cita:

- `Chain line (mm) 43.5` — sólo aparece en el caso diseñado para **pendear**,
  no en el ejemplo que representa el producto;
- `Compatible chain: HG 8/7/6-speed` — la columna `chain_declaration` existe y
  queda vacía.

Los casos son la documentación de hecho del modelo: quien llene mirando el
ejemplo aprenderá a dejar fuera lo que el documento sí publica. Ninguno de los
tres huecos necesita esquema nuevo.

### H4 · Cuatro casos heredados ejercitan las declaraciones sin las dos columnas adjudicadas (bajo)

`scope_claims` añade a cada tabla `*_compatibility_claims` dos columnas
**requeridas**, `target_component` y `declaration_result`, que son justamente
las que llevan la adjudicación. Cuatro casos heredados de la propuesta
—`sh_a_claim_names_a_model_or_an_interface`,
`sh_a_model_claim_without_its_model_is_pending`,
`sh_an_interface_claim_cannot_name_a_model` y
`rd_an_interface_claim_cannot_name_a_model`— traen filas sin ellas, así que
arrastran un `row_incomplete` no declarado y **ninguna mitad heredada ejercita
una declaración bien formada**. Sonda
`probe_inherited_claim_rows_lack_the_adjudicated_columns`: **pasa**.

No cambia ningún veredicto —`row_incomplete` no bloquea—, y es la misma forma
que la observación de las fixtures de kit en cadenas: conviene arreglar las dos
de una vez.

### H5 · El datum obligatorio deja pendiente toda línea de cadena publicada (nota de decisión)

`chainline_datum` es requerido cuando hay `chainline_mm`, y el manual publica
`43.5` **sin** declarar desde dónde se mide. Sonda
`probe_a_published_chain_line_without_its_datum_pends`: **pasa**, la fila queda
pendiente. La regla es la correcta —una cota sin referencia no es una cota—,
pero como la fuente primaria nunca publica el datum, la consecuencia es una
pendencia permanente en cada desviador con línea de cadena, o un datum
inventado. Conviene que sea una decisión escrita: un valor de vocabulario
explícito del tipo «convención del fabricante, no declarada en el documento»
resuelve el caso sin inventar una referencia, o se acepta la pendencia y se
dice por qué.

## 3. No-hallazgos verificados

Los declaro porque descartarlos también es resultado, y tres de ellos parecían
defectos antes de mirar la fuente:

- **La partición 48/50 por conteo de velocidades es del fabricante, no de
  Root.** Sospeché que `Min. 48T` se había convertido en «máximo de 1x10»;
  la página de producto declara literalmente `Max low sprocket: 50T
  (1x11-speed), 48T (1x10-speed)`. La lectura es correcta.
- **La dirección del reductor es la correcta y la referencia también.** La
  vista despiezada lista `Y2B198010 Clamp Band Adapter Unit for S-size /
  ø 28.6 mm` y `Y2B198020 Clamp Band Adapter Unit for M-size / ø 31.8 mm`. La
  fila de Root mete un tubo de 31,8 en una abrazadera de 34,9 con
  `Y2B198020 / M`: coincide con el documento, y el par estricto bloquea tanto
  agrandar como igualar.
- **Perder la clave única por diámetro no es una regresión.** Con contacto
  directo y reducción separados, el mismo tubo nominal aparece legítimamente
  dos veces. Sonda `probe_two_rows_may_share_one_nominal_diameter`: 31,8
  directa y 31,8 con reductor conviven **sin bloqueo**, que es lo correcto.
- **La compuerta de diferencia plato grande–medio está bien fijada en tres
  platos.** La p. 140 publica `Applicable top-mid tooth difference: -` para el
  FD-R2000 de 2 platos y `11T` para el FD-R2030 de 3. La condición sobre
  `front_chainring_count == 3` reproduce exactamente eso.
- **Los límites del plato grande son los del plato grande.** La p. 140 publica
  `Top gear teeth 46-52T` y `Total capacity 16T` para el FD-R2000-B; los
  valores de la fila y sus rótulos coinciden, y la confusión con el plato
  pequeño está corregida.
- **Los números de RD-U6000 que sí están en la fila son correctos**: capacidad
  total 39T, diferencia máxima de platos 0T y piñón pequeño 11T aparecen en la
  tabla de especificación de la página de producto, no sólo en el manual.
- **La adjudicación del par se sostiene**: una declaración global sobre un par
  bloquea, cada declaración pertenece a su mando por vínculo de fila, y una
  referencia a un mando ajeno al envase bloquea.
- **La fila del adaptador S de 28,6 mm no está en el ejemplo**, pero el esquema
  la representa sin cambios; es ausencia del ejemplo, no del modelo.

## 4. Límites de esta revisión

No ejecuté SQL, adopción ni la extensión estricta compartida, así que esas
afirmaciones quedan sin verificación independiente y no las contradigo. Nada de
lo verificado aquí aprueba un montaje mecánico ni autoriza llenar un producto:
los 48 casos siguen siendo representaciones sintéticas, con
`facts_verified_for_product` y `automatic_fill_authorized` en falso y el
catálogo con `mechanical_coverage_complete: false`. Un ejemplo OEM correcto
sigue siendo un ejemplo, no un hecho del inventario.
