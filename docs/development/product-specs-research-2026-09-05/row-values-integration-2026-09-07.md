# Integración de valores condicionados por configuración — 2026-09-07

El catálogo local incorpora dos implicaciones de contenido: una configuración
de tija «Con kit incluido» exige `clamp_included=true`, y un montaje «Con
espaciador incluido» exige `included=true`. Cada regla pertenece a su propia
fila. Una pieza opcional puede estar incluida; no se fuerza `false`. La ausencia
del valor o de su requisito queda pendiente y no dispara autofill.

La base congelada es `all-family-remaining-nd-integrated-2026-09-07.json`
(`f1826a9a782a200754b21ba6c5420af0f9c39b89482503cab77f96779fc739b1`).
El compilador `scripts/inventory/compile_product_spec_row_value_addendum.py`
verifica esa base y el archivo completo de 240 casos antes de crear la nueva
etapa. No reescribe paquetes independientes ni abre gates de publicación.

| Artefacto nuevo | SHA-256 |
| --- | --- |
| `all-family-row-values-integrated-2026-09-07.json` | `58e68f0c4f0d7b8e824a84a3931cf9f7bd03767f8a65aaa55020bc6af7465f03` |
| `all-family-row-values-cases-integrated-2026-09-07.json` | `0eb5dfda6a7087cf115afd54e08a9908b00511acbae59d58217b783d371da810` |

Son 105 plantillas, 706 definiciones, 57 campos de filas, 1.212 usos de campo
y 259 casos. Pasan los 259 en SQL, con los guards diferidos y la preservación
de hechos e identidad, dentro de un ensayo local que termina en `ROLLBACK`:
`.tmp/db/spec-all-family-row-values-trial.log`. Los 368 tests de Dart pasan
con los mismos metadatos ejecutables. Los dos casos que documentaban la
contradicción antes permitida (`RCF08`, `CPC_GAP_INCLUDED_CLAMP_FALSE`) ahora
exigen `row_value_conflict`. Se agregan 19 casos de inclusión, desconocidos,
aislamiento entre filas, legacy y completitud.

El primer ensayo de la base ND detectó diferencias de nombres diagnósticos
preexistentes entre validadores, no de resultado: en SQL `field_constraint`
equivale aquí a `range` u `option`, y `field_applicability` o
`prerequisite_missing` a `prerequisite`. Cinco fixtures tienen una expectativa
SQL explícita y acotada; no se omite ninguna comprobación de bloqueo o de
pendiente. El ensayo exploratorio que listó las diferencias no es prueba de
aprobación; la evidencia válida es el ensayo estricto posterior.

La UI usa los controles existentes: restringe opciones sólo con antecedentes
confirmados, conserva valores contradictorios y sus fuentes, explica el valor
esperado junto al campo y mantiene «Sin dato». Pasan 22 pruebas de widget,
incluyendo edición y lectura a 390, 768 y 1280 px en claro y oscuro. No se
agregaron valores visuales. La sesión canónica `payroll` se recargó sin reinicio
(147/5.383 bibliotecas, 8,496 s). El texto semántico del borrador abierto de
HV408 quedó idéntico antes/después y se inspeccionó el frame real
`.tmp/product-spec-catalog/row-values-runtime-after.png`. Esto verifica la
preservación del editor; las nuevas reglas aún no están en el catálogo
productivo y su ejercicio real queda pendiente de esa publicación.

El forward `20260907024000_product_spec_row_value_conditions.sql` está
revisado: SHA `86c54bfe71e343a7e146747f6a320bbba44decf7c058d927093e6d4a10cee7aa`.
Sólo cambia dos helpers privados inmutables, con pre/postimagen y ACL fijados;
no toca filas, productos ni versiones de plantilla. Pasan 1.090 pgTAP en 20
archivos (`.tmp/db/spec-row-value-full-pgtap.log`). Se aplicó, verificó y registró
en producción a las `2026-09-07T14:12:33Z`; recibo
`.tmp/db/migration-receipts/20260907024000.receipt`. Pasan las 46 sondas puras
y las 7 comprobaciones de funciones/ACL del verificador, y la preservación de
la preimagen actual antes y después. El smoke autenticado posterior leyó 38
productos y 35 familias de referencias sin errores ni escrituras. Pasan 178
pruebas Python; el análisis de `lib` y `test` no tiene errores, pero conserva
27 advertencias y 486 infos ajenos al cambio. La recuperación, antes de publicar
metadatos que usen el bucket nuevo, es un forward revisado que restaura las
dos definiciones de 2200; no se modifica una migración aplicada. Después de
publicar reglas debe conservarse un motor que las comprenda. El reemplazo
de funciones toma locks breves; no ejecuta backfill.

**Preimagen productiva, no restauración del legacy.** La afirmación histórica
del 6 de septiembre dejó de coincidir antes del despliegue de 2400. La lectura
actual mantiene 1.665 productos globales y 1.653 hechos de los 1.664 productos
del respaldo Viñabike: ningún hecho de ese alcance agregado o eliminado. Frente
al respaldo, un hecho de HV408 (`8375d694-6fc5-4508-a776-cd4398225268`) cambió
`source` de `supplier_text` a `mechanic` y `updated_at` a
`2026-09-07T13:23:47.965977+00:00`; el producto
`7a7c152f-1a45-4ff9-98df-d6c59fa1a8e7` tiene revisión 3, sin cambios en marca,
modelo, MPN, categoría o referencia. No se atribuye autor a esa modificación.
Los valores técnicos coinciden con el respaldo. Los 849 hechos restantes de
la lectura global pertenecen a `bike` y `job_bike`, fuera de ese respaldo; no
son 849 productos rellenados. Se conserva intacta la afirmación histórica y
se crea `product-spec-row-values-preserved-data-2026-09-07.sql` para comprobar
la preimagen actual antes y después de 2400.

La revisión de Claude `91ae0160…` valida las ocho adjudicaciones ND. Su N5
pasaba por alto que la presión escalar de bomba ya tiene rol `legacy`: los
fixtures nuevos verifican que no recupere autoridad. N6 queda resuelto como
completitud pendiente, sin inventar una referencia ni convertir texto en
identidad. N4, contradicciones con alcance incompleto entre filas, sigue
abierto. Las cotas máximas independientes de FOX no son dos medidas reales
que deban ordenarse; no se agrega esa desigualdad. La regla universal entre
carrera y entrecentros tampoco se incorpora sin referencias de medida.

Publicación del catálogo ampliado y llenado de productos: **0**. Siguen
pendientes la adjudicación de familias/asignaciones, consumidores mecánicos,
ambigüedades entre declaraciones y el aplicador autenticado de fichas.
