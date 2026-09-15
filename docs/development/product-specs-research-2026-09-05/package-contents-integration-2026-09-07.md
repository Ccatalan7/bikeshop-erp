# Contenido de conjuntos y asignaciones observadas — 2026-09-07

**Corrección posterior:** la [revisión de límites](package-contents-boundary-review-2026-09-07.md)
reprodujo que la unicidad por posición heredada bloqueaba repuestos incluidos
para una misma posición. La etapa `evidence-scopes` elimina esa unicidad y hace
opcional la posición, preservando IDs y dientes. El total cuenta coronas
dentadas, incluso si dos forman un monobloque comercial. La comparación entre
total y filas necesita el contrato de cardinalidad todavía en implementación.
Los hashes y resultados de abajo conservan el checkpoint previo a esa corrección.

La revisión de los 20 productos observados encontró dos límites de
representación: J253 es un juego de bielas fotografiado con eje y rodamientos;
1062 es un conjunto fotografiado con cálipers y discos. La ausencia de platos
o manillas en una imagen no prueba su exclusión del paquete vendido.

`compile_product_spec_package_contents_addendum.py` integra una etapa local
sobre la base congelada `58e68f0c…`, sin reescribirla. Diferencia cantidad de
platos **incluidos** (entero mayor o igual a cero, desconocido permitido como
pendiente) de la configuración que podría admitir un montaje. El antiguo
`chainring_count` queda legacy en crankset y drivetrain_kit; conserva su
semántica anterior en bicycle. No se transforma ningún valor anterior en un
conteo nuevo. Las filas de dientes de crankset se rotulan como contenido:
con cero no corresponden; sin cantidad su requisito queda pendiente.

El nombre de plantilla «Freno mecánico de disco completo» cambia localmente a
«Conjunto de freno mecánico de disco». Se conservan ID, clave, familia técnica,
contrato y referencias; el nombre no presume una lista de miembros. El helper
de contenido exige que cada miembro y su inclusión tengan evidencia. El
integrador sólo permite sustituir ese rótulo mediante su preimagen exacta;
dos pruebas de límites cubren preservación y rechazo de deriva/cambio de ID.

Root volvió a inspeccionar las fotografías de J253 y 1062 y consultó
[Profile No Boss Race Crankset](https://www.profileracing.com/product/no-boss-3-piece-chromoly-race-crankset/).
Ese modelo documenta un juego de bielas, eje y accesorios que requiere plato
o spider aparte. Sirve como contraejemplo a «todo juego incluye al menos un
plato»; no identifica J253. La lectura de TeknoBike por Root terminó en
timeout; la evidencia del conflicto Logan/Ozono sigue atribuida a la revisión
independiente y no se sobrescribe marca/modelo del ERP.

| Resultado local | Evidencia |
| --- | --- |
| 105 plantillas, 707 definiciones, 57 campos de filas, 1.214 usos | all-family-contents-integrated-2026-09-07.json, SHA `20a9c1eabdf84dd5e3e9cb5a4a922a695c6e91deff53bebdb2e0c584b5e8edee` |
| 272 casos; 13 nuevos | all-family-contents-cases-integrated-2026-09-07.json, SHA `f87a94087f0a325d637f58833d61c5568e95cc52bb5e27fd126a1306aa5eb1ae` |
| 381 pruebas Dart | .tmp/product-spec-catalog/all-family-contents-dart.log |
| 272 casos SQL, guards y preservación, ROLLBACK | .tmp/db/spec-all-family-contents-trial.log |
| 180 pruebas Python | .tmp/product-spec-catalog/contents-python-tests.log |

Los primeros fixtures se corrigieron para nombrar los diagnósticos reales
`integer`, `required_missing` y `field_applicability`; no cambió la expectativa
de bloqueo o pendiente. Sigue pendiente comprobar coherencia entre cantidad
de platos incluidos, cantidad de filas de dientes y miembros del kit. Tampoco
se ha aprobado la configuración opcional de platos ni la asignación o llenado
de J253/1062. Esta etapa cierra la confusión de contenido y rótulo, no AG01 en
su totalidad ni la revisión global.

La revisión de asignaciones está congelada en
`assigned-product-family-adjudication-2026-09-07.json`, SHA
`852577ba7176e438be9a145be4327d70d936e464ca613a6571eb46d15a9b155a`:
12 deltas propuestos (9 directos, 2 condicionados, 1 especialización opcional),
6 conservar y 2 pendientes. Se preservan las 20 preimágenes y sus 10 facts.
Las dos búsquedas adicionales por GZ0009/GZ0010 no localizaron una fuente exacta;
productos parecidos de otras marcas no resuelven sus identidades.

Publicación de estos metadatos, reasignaciones y llenado: **0**. El gate global
no se abre al resolver un subconjunto de casos.
