# Cantidad, contenido y pendientes requeridos — integración 2026-09-07

Checkpoint Root: catálogo derivado ensayado en Dart y PostgreSQL local. El
forward 2500 está aplicado y verificado en producción a las
`2026-09-07T15:44:15Z`, con historia registrada y lectura autenticada posterior.
Ningún producto, asignación o lote de llenado fue aplicado. Las 105 plantillas
ampliadas conservan todas sus compuertas de publicación y llenado cerradas.

## Artefactos y alcance

- Catálogo `all-family-cardinality-integrated-2026-09-07.json`, SHA-256
  `934ce172a6f3eaf8fa8dc616a912d161c965840b97b647fbee23870ccc154562`.
- Casos `all-family-cardinality-cases-integrated-2026-09-07.json`, SHA-256
  `bede596b90cabbe070faf3d1df9505be50b2adf682334fa8e37287e24af6bae6`.
- 105 plantillas, 711 definiciones, 58 campos de filas, 1.218 usos y 313 casos.
- Derivación reproducible:
  `scripts/inventory/compile_product_spec_cardinality_addendum.py`.

La única activación nueva está en `crankset`: cada fila de
`chainring_teeth_rows` representa una corona incluida, y
`included_chainring_count` documenta su cantidad. No se suman unidades de
`kit_members` ni se equipara una unidad comercial con una corona. Una pieza
monobloque puede incluir dos coronas. La posición es opcional y no identifica
una ocurrencia; cada fila conserva su propio ID estable.

Con más filas que el total conocido existe contradicción bloqueante; con
menos filas queda investigación pendiente. Un total desconocido no se deduce
de las filas. Dientes desconocidos no eliminan la ocurrencia del conteo.
Esto no cierra AG01: quedan representación de contenido del kit, asignación
condicional y consumidores, además de evidencia de cada producto.

El [contrato del motor](row-cardinality-implementation-2026-09-07.md) describe
`row_coherence.version = 2`, preservación v1 y seis reemplazos SQL. La corrección
central de celdas requeridas usa conocimiento del valor, no presencia de la
clave: desconocido sigue incompleto y los valores `false` y `0` son conocidos.

## Evidencia local

- 422 comprobaciones Dart del catálogo: `all-family-cardinality-dart.log`.
- 313 casos SQL más guards diferidos y preservación de facts/identidad:
  `.tmp/db/spec-all-family-cardinality-trial.log`, terminado en `ROLLBACK`.
- La etapa previa de contenido/fuentes también pasó sus 302 casos SQL tras
  2500: `.tmp/db/spec-all-family-evidence-scopes-trial-after-2500.log`.
  La expectativa de `row_incomplete` para unidad desconocida se conservó.
- 121 pruebas pgTAP nuevas de cardinalidad; 1.255 comprobaciones en 22 archivos
  de la suite `product_spec chain_connector_spec_contract`, todas pasaron.
  El conteo incluye los tests de fichas ya presentes en el checkout compartido.
- 210 pruebas Python de fichas pasaron. Los 79 casos Dart de frontera del
  implementador están vinculados en su entrega; no se atribuyen a una nueva
  ejecución de Root.
- Las seis postimágenes SQL y ACL coincidieron realmente en local. Root
  endureció el verificador: el `passed=false` informativo original se sustituyó
  por una aserción SQL que falla antes de registrar una migración.

La validación conserva valores, IDs y fuentes del input. Los casos no
certifican compatibilidad mecánica OEM ni equivalencia entre documentos.

## Concurrencia, producción y app

`scripts/inventory/test_product_spec_cardinality_concurrency.py` reutiliza las
dos secuencias revisadas de 2200 y cambia el extremo observado al total
numérico, dejando vacía la colección. El publicador primero bloquea al writer
(`55P03` acotado); el writer primero hace esperar al publicador y, tras commit,
éste rechaza la publicación por población (`23514`). Se verificaron producto
existente, producto nuevo y referencia en ambos órdenes. Todos los fixtures y
la extensión creada para la prueba se retiraron. Logs y SQL derivado bajo
`.tmp/product-spec-cardinality-concurrency/`. Una primera derivación falló en
un ancla de whitespace antes de conectar; no se alteraron expectativas SQL.

El recibo `.tmp/db/migration-receipts/20260907025000.receipt` identifica el
forward SHA-256 `6a4cd99868055020a2671b1574ccff56f347848156e80a41f2d0f66aa0a23b92`,
verificador estricto `b946523f12a10c0ba785965d47754d03b710d9d5732637130bb420b1febb61f1`
y preservación `3a7c6189a61590e858a049cb7ae2835db7cbfd429c03d373a0d6af36b47a89a0`.
La comprobación de seis funciones, propietarios, ACL, volatilidad y search_path
pasó en la base real. La prueba negativa local del verificador rechazó una
postimagen falsa con error SQL; nunca podría registrar un `false` silencioso.
Las preimágenes técnicas de producto del 7 de septiembre se verificaron antes
y después: no se alteraron facts, identidad ni asignaciones.

El smoke autenticado posterior leyó **38 productos y 35 familias de
referencias, cero errores y cero escrituras**:
`.tmp/product-spec-catalog/authenticated-research-snapshot-cardinality-verification.json`.
La comprobación posterior de todo el inventario leyó los **1.664 productos**
en 24,886 s mediante el actor autenticado: cero errores, cero escrituras y
ningún ID añadido o perdido respecto de la auditoría inicial. Conserva 863
asignaciones por categoría y 801 registros sin asignación (742 físicos y 59
servicios). Los diagnósticos existentes son 801 `unmapped`, 18
`prerequisite_missing` y 29 `field_applicability`, sin bloqueos. Esto comprueba
el lector contra el catálogo vigente, no la cobertura mecánica de las 105
plantillas propuestas. Evidencia completa:
`.tmp/product-spec-catalog/authenticated-cardinality-all-products-verification.json`.
El análisis completo `lib test` terminó sin errores, con 27 warnings fuera de
los archivos de esta entrega y 486 infos; no se declara análisis global limpio.
La sesión `screen payroll`, PID 90499, recargó 143/5.383 bibliotecas en 6,855 s.
Los árboles semánticos antes/después son idénticos y Root inspeccionó el frame
real `cardinality-runtime-after.png`: el borrador KMC conserva 6/7/8, 11/128 y
7.1. No hubo guardado, descarte ni reinicio. Esto prueba preservación en el
editor existente; no representa ejercicio visual de la colección de platos
inédita ni del autocomplete de taller.

## Revisión de Claude que no se integró

`tire-configuration-source-scope-proposal-2026-09-07.json` (`d2687315…`)
proponía unicidad por perfil, método y documento. Root rechazó esa clave:
un mismo documento puede declarar condiciones o subrangos diferentes. La
ausencia de un ejemplo en dos sitios no justifica un veto mecánico.

La alternativa `tire-mounting-linked-declarations-proposal-2026-09-07.json`
SHA-256 `1cc2e216f4ea051a6f5f767437025fec7514afcdd2b83f98af17c965339f50f6`
separa declaraciones y cifras enlazadas por ID, sin duplicar alcance/ancho.
Documento SHA-256 `eff3f2f6f5f500ada32ac04ab144e86070aa04a820e467f4c7f1089bc043a451`.
Root leyó la entrega completa en el chat Code «Diagnóstico fichas técnicas
Viñabike», Message 80, con Opus 5 Fast / Ultracode. **No se integra aún**:

1. Se pierde la parte de R6 que exige unidad a un montaje sin gancho.
2. Una declaración sin cifras enlazadas no genera aviso: el motor sólo
   recorre origen → destino, sin cobertura inversa.
3. Conservar declaraciones discrepantes no equivale a detectar su conflicto
   ni emitir un estado pendiente. El evaluador no puede presentarse como si
   hubiera adjudicado o aprobado esas fuentes.

No se retiró el dueño anterior ni se alteraron sus casos para ocultar esos
límites. La investigación/adjudicación continúa a cargo de Codex y Claude.
Claude recibió después 33 registros distintos: 22 `ambiguous` y 11
`business_record_review` de la revisión de productos sin ficha. Su entrega
será otro paquete de evidencia; no autoriza asignaciones ni llenado.
