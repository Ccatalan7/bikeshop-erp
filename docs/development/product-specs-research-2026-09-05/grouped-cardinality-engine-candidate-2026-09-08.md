# Conteo por configuración: candidato local V3

Estado: código y SQL candidatos, sin despliegue, activación, asignaciones ni
llenado. Codex posee el motor; Claude revisa separadamente el dominio de
piñonería y el aplicador. Las 68 nuevas plantillas publicadas siguen usando
sus contratos anteriores; las 37 originales aún no se activan.

## Comportamiento comprobado

La forma `{id, field, group_by, total_column}` es alternativa a
`{id, field, total_field}` y sólo se admite en `row_coherence.version: 3`.
El grupo resuelve un link de la misma tabla hacia una fila padre estable,
cuya columna de total tiene dominio entero no negativo. No suma variantes,
no inventa totales ni reescribe el escalar de velocidades del SKU.

Una configuración corta y otra larga producen dos incidencias distintas. El
campo, ID y columna de la incidencia corresponden al padre real, mientras
`collection_field` conserva la aplicabilidad de la colección hija. Un padre o
colección inaplicable no pide documentación adicional; las observaciones
contradictorias conservan el error de aplicabilidad. Filas sin dueño quedan
pendientes; IDs explícitos inexistentes bloquean. Un ID real llamado `unknown`
sigue resolviéndose por identidad y no se confunde con una etiqueta de estado.

Un guardado rechazado conserva todo el producto y todos sus hechos/fuentes.
El guard de publicación impide retirar el conteo sobre datos poblados; renombrar
un link junto con su referencia o cambiar etiquetas no redirige sus filas.
Las relaciones mecánicas no se aprueban por igualdad de conteos.

## Evidencia

- 624 pruebas Dart: extensión, conteo anterior, vínculos y catálogo integrado.
- 49 pruebas Python de metadata V2/V3 y compilación del candidato.
- 78 pruebas SQL: evaluador/validador central, metadata, guardado bajo rol
  authenticated local, conservación, guard de publicación y ACL.
- Regresiones SQL anteriores: 121 + 70 + 57 + 10, todas con rollback.
- Analizador: sin errores/advertencias; dos informaciones preexistentes en
  `product_spec_contract.dart` (import transitivo collection y llaves de if).

Los 24 casos de observaciones y 14 rechazos de metadata de la fixture V3 se
comparten entre Dart y PostgreSQL. Son fixtures sintéticas; no prueban por sí
mismas una relación OEM. El caso de versión futura del fixture V2 se mueve de
3 a 4 porque V3 es ahora conocido; su resto permanece igual.

Logs: `.tmp/product-spec-catalog/grouped-cardinality-{dart,python,analyzer}.log`,
`.tmp/db/product-spec-grouped-cardinality.log`,
`.tmp/db/product-spec-grouped-predecessor-regressions.log`.
El SQL sale del compilador contra funciones predecesoras inmutables, y queda
fuera de `supabase/migrations`. Cada ejecución SQL local termina en rollback.

## Pendiente de integración

Revisión independiente del diff final; ventana de migración con hashes/ACL
exactos y lectura posterior; distribución del cliente que comprende V3 antes
de activar esas reglas en fichas usadas. Tampoco se ha hecho verificación de
esta extensión en la app real. El defecto anterior del editor de compras
sigue exigiendo runtime/distribución antes de activar las 37 originales.

El catálogo de alternativas del modelo pertenece a referencias OEM, no a facts
de cada SKU. P-1 habilita conteo agrupado donde el dueño sea correcto; no obliga
a instalar las tablas de alternativas propuestas en cassette/rueda libre.
Las relaciones dirigidas de interfaces se revisan aparte; un comentario nunca
levanta una incompatibilidad.

## Revisión independiente y corrección del consumidor — 2026-09-08

Claude revisó las seis huellas y construyó contraejemplos propios; el informe
está en `grouped-cardinality-independent-review-2026-09-08.md`. G-2 era real:
el consumidor final perdía `collection_field`. Ahora lo conserva al decodificar
SQL y al fusionar la validación Dart, y el mensaje identifica la colección por
su etiqueta. La deduplicación también distingue sus dueños cuando falta la
tabla padre: entonces ambos tienen el mismo campo/código y ningún ID de fila.
Dos colecciones que comparten una cantidad ya no se vuelven indistinguibles.
87 pruebas Dart focalizadas pasaron, incluidas ambas regresiones y decodificación
del servidor: `.tmp/product-spec-catalog/grouped-cardinality-review-fixes.log`.
No cambió el evaluador SQL.

G-1 no era un hueco de cobertura: la prueba SQL existente hace UPDATE real de
`spec_definitions.validation_rules` y exige rechazo cuando el total pierde su
tipo entero. Por ello detecta también que la cláusula WHEN deje de disparar.
No se modifican ni retiran migraciones históricas aplicadas. G-3 conserva el
estado pendiente del vínculo desconocido; una plantilla puede exigir la
columna, pero el motor no inventa un padre ni transforma ausencia en conflicto.

Piñonería retiró sus tablas de alternativas OEM del SKU y ya no necesita P-1.
Este candidato no se despliega sin una familia cuyo dato real requiera conteo
por grupo y sin cerrar sus gates de cliente y base de datos.

## Huellas del candidato

| Archivo | SHA-256 |
|---|---|
| `lib/modules/inventory/models/product_spec_coherence.dart` | `05baf5b32871de5ad6e0abf5edecc9a04aafc7c29d05408da2e4bbd16570a749` |
| `lib/modules/inventory/models/product_spec_contract.dart` | `2b92d7052405edd6104b7680349edd76ec63140ebbb818391add886035267c90` |
| `scripts/inventory/product_spec_row_cardinality_metadata.py` | `89a3a6698f5dbc7cac790c699bf34cd0f6ce353871f2644bc4c192fce78a7e4c` |
| `scripts/inventory/compile_product_spec_grouped_cardinality.py` | `dcd2dfc5020bcb6b73b81b0f99ec1af46b117f59ded52b051e168767d94a184f` |
| `scripts/inventory/sql/product_spec_grouped_cardinality_candidate.sql` | `b3264ecb3d4320598004979a69a7c246399a4a2ef0cc8412a7aeacbbec12c458` |
| `test/fixtures/product_spec_grouped_cardinality.json` | `27fcdefca388b4ec0f5ef076a694531286a39d18c1a4cc4e740420862bdfc306` |
