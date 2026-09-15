# Orden estricto de cotas: motor publicado, metadatos sin activar

Al mover ID/OD de escalares a columnas, la validación escalar no se hereda.
Declarar un par ordenado recupera el rechazo de la inversión, pero permite
igualdad: eso sirve para límites inclusivos y no para dos diámetros del mismo
cuerpo anular. Se agrega la comparación estricta al dueño existente de filas,
sin una regla universal por nombres de campos ni otro motor de compatibilidad.

`rows_schema.version: 2` admite `strict_ordered_pairs`. Sus pares necesitan dos
columnas numéricas distintas con la misma unidad. Si ambas cotas están
presentes exige primera < segunda, usando decimal exacto. Ausencia sigue siendo
dato pendiente; las columnas de filas diferentes nunca se prestan valores.
`ordered_pairs` conserva <= tanto en v1 como v2. Ambos tipos de par comprueban
las unidades. El grafo conjunto rechaza todo ciclo que contenga una relación
estricta; los ciclos sólo inclusivos pueden expresar igualdad y se conservan.
Un esquema v1 que introduzca
la clave nueva y un sobre v1 enviado a un esquema v2 se rechazan. Los clientes
anteriores tampoco pueden interpretar v2 como v1 en silencio.

Las dos tablas nuevas de direcciones adoptan v2 para ID/OD del cuerpo de su
propio extremo. Esto no establece ajuste SHIS, tolerancias, ángulos ni
compatibilidad entre dos componentes. Otras familias todavía necesitan declarar
su par estricto cuando corresponda; no se reinterpretan definiciones publicadas.

Evidencia local:

- 79 pruebas Dart: 30 de la frontera nueva y 49 anteriores de filas.
- 49 aserciones SQL de v2, orden inclusivo, borrador ordinario e incompletitud,
  con rollback; 60 regresiones SQL anteriores bajo la extensión, con rollback.
- Direcciones: 23 pruebas Dart y 22 casos SQL de avance/repetición exacta de
  metadatos bajo la extensión; rollback. Las 15 fichas conservan cuatro
  observaciones legacy, sin bloqueantes ni datos activos sin proyección.
- Analizador de los archivos Dart modificados: sin incidencias.

El compilador `scripts/inventory/compile_product_spec_strict_row_order.py`
construye la extensión desde el predecesor inmutable 190000. No modifica ninguna
migración aplicada. El test SQL incluye la extensión dentro de su propia
transacción local y revierte sus fixtures. El forward revisado ya está publicado.

La revisión independiente confirmó las comparaciones, exactitud y rechazo
antes de guardar. Sus observaciones G1/G2 (unidades en la ruta inclusiva y
ciclos entre las dos listas) ya están corregidas y tienen regresiones. La
[revisión final de Claude](service-parts-and-row-order-delta-review-2026-09-08.md)
las confirmó sin defectos vigentes, con ejecución Dart y lectura del SQL;
la ejecución SQL corresponde a Root. Una lectura productiva de las
93 definiciones de filas y sus 26 pares inclusivos encontró cero pares de
unidades distintas: no hay un esquema publicado conocido que dependa de esa
carencia. Los valores de filas no se reescribieron.

Una lectura productiva confirmó las preimágenes de las dos funciones:
`spec_rows_schema_validate_internal_v1(jsonb)` =
`e4147389be641a0c61e0f625c676e39b` y
`spec_rows_validate_internal_v1(jsonb,jsonb)` =
`79623b3e97219d95b035aa0705be7757`. No hubo escrituras productivas.
[Avance guardado, ACL, lectura real y registro de migración](strict-row-order-publication-2026-09-08.md)
completados a 2026-09-08T19:01:53Z. La distribución y verificación del cliente
siguen pendientes antes de activar metadatos v2. La revisión independiente del
delta está cerrada; no equivale a ese despliegue ni a verificación del editor.

Logs privados: `.tmp/product-spec-catalog/strict-row-order-tests.log`,
`.tmp/db/product-spec-strict-row-order-local.log`,
`.tmp/db/product-spec-strict-order-legacy-regression.log`,
`.tmp/db/existing-headset-strict-order-forward-replay.log`.
