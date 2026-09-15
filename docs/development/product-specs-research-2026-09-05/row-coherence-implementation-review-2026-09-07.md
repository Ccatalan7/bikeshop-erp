# Coherencia de filas — revisión de la implementación y regresiones de frontera (2026-09-07, re-revisión)

Revisión independiente del contrato implementado en Dart (`product_spec_coherence.dart`, `product_spec_contract.dart`, `ProductSpecRowsField`) y del forward SQL `20260907020000_product_spec_row_coherence.sql`, aplicado sólo en local. Sin datos, sin deploy, sin commit. Archivos de mi propiedad: `test/unit/product_spec_coherence_boundary_test.dart` (ejecutado), `supabase/tests/product_spec_row_coherence_boundary.sql` (escrito, **no ejecutado**: root lo serializa) y este documento. Esta versión cierra la re-revisión tras las correcciones de root a R1, R2 y R3.

## 1. Resultado de las pruebas

| Suite | Resultado |
|---|---|
| `flutter test test/unit/product_spec_coherence_boundary_test.dart` | 19 verdes, 0 rojos (antes 15 + 1 rojo a propósito; el reproductor de R2 ahora pasa y se agregaron ciclo largo, reversa de un par heredado y cadena transitiva) |
| `supabase/tests/product_spec_row_coherence_boundary.sql` | no ejecutado; sin bloques `todo`; toda aserción espera el contrato corregido |

Cómo correr el pgTAP cuando root lo serialice:

```bash
scripts/db/test.sh product_spec_row_coherence_boundary
```

**Antes de correrlo hay que regenerar el forward.** El archivo del árbol (02:20, SHA en §6) todavía tiene `create constraint trigger spec_coherence_publication_guard after update` y compara el bloque `row_coherence` completo; la versión corregida —`after insert or update`, comparación de vínculos sin `id` ni `label_columns`, metadatos validados antes de la comparación— está en `.tmp/db/coherence-helpers-local-iteration.sql:218` (02:24), que es lo aplicado en local. Contra el forward del árbol fallarían tres aserciones mías: la inserción de una segunda plantilla sobre definiciones pobladas, el cambio sólo de rótulo y el cambio sólo de id.

## 2. Estado de cada hallazgo

| Id | Estado | Verificación |
|---|---|---|
| R1 guard sólo en UPDATE | **Corregido** en el archivo de iteración local: `after insert or update`; en INSERT `previous = '{}'`, así que los extremos nuevos se comprueban contra hechos y referencias. Pendiente de regenerar en el forward. | pgTAP §5 «inserting a template with links over populated definitions is rejected like an update» (con constraints diferidas alrededor de los dos inserts) |
| R2 par invertido duplicado | **Corregido** en Dart y SQL: detección de ciclo sobre la salida del evaluador único, así que también rechaza ciclos de más de dos pares y la reversa de un par heredado. | Dart: 4 casos verdes (reversa, ciclo de tres, reversa de par heredado, cadena transitiva aceptada); pgTAP §1 los mismos cuatro más «cadena en orden no levanta nada» |
| R3 rótulo exige migración | **Corregido**: el guard compara `links - label_columns - id` y `scalar_ordered_pairs`; `spec_coherence_metadata_internal_v1` se ejecuta antes de la comparación, así que un rótulo inválido sigue rechazado. | pgTAP §5: cambio sólo de rótulo → `lives_ok`; cambio sólo de id → `lives_ok`; rótulo con columna ajena → `throws_ok` 23514 |
| R4 cambio observable en plantillas v1 | **En curso por root**, consultando producción. `.tmp/db/spec-coherence-legacy-impact.json` registra 169 pares observados, 0 invertidos y 0 desajustes de unidad en los pares heredados activos; no afirmo en qué entorno se tomó. | sin prueba mía |
| R5 dedupe SQL borra visibilidad | **Retirado.** La aplicabilidad tiene código propio `field_applicability` desde 200 (presente también en el forward), así que el dedupe de `field_constraint` no la toca. Queda una única ruta teórica: un campo de filas con rol `declaration` y valor mal formado perdería el mensaje «La referencia elegida no documenta…»; no es un caso real y no sostengo la afirmación. | — |
| R6 lectura rechazada por conflicto ajeno | **Reformulado** según root: `rejected` significa observación no persistida, no afirma cita falsa; `details` se conserva y la UI muestra campo y posición de fila. Sin acción. | pgTAP §5 conserva la aserción de que el hecho y la cita anteriores quedan intactos |
| R7 costo | **Medido por root**: guardado completo de 32 campos con 20 filas vinculadas, constraints diferidas incluidas, 155,288 ms (`.tmp/db/spec-coherence-performance.log`). Sin dato productivo. Cerrado. | — |

## 3. Qué verifiqué en código en esta ronda

- **Ciclo de orden (R2).** SQL: `with recursive edges(a,b)` sobre `spec_coherence_pairs_internal_v1(p_contract,p_fields)`, es decir sobre pares declarados **y** heredados ya filtrados por tipo y unidad; error «El orden de límites no puede contradecirse en un ciclo». Dart: `visitRange` sobre `rangeEdges` construido a partir de `pairs`, que ya incluye el fallback heredado. Ambos rechazan `[a,b],[b,a]`, `[a,b],[b,c],[c,a]` y `[largest,smallest]` cuando `[smallest,largest]` es heredado; ambos aceptan `[a,b],[b,c]`.
- **Guard corregido (R1/R3).** Orden dentro del trigger: metadatos primero, después comparación de extremos y celda, después población. Un cambio sólo de presentación retorna antes de tocar hechos; un rótulo con columna inexistente cae en el guard de metadatos. Doble validación de metadatos por `spec_template_rules_guard` y `spec_coherence_publication_guard`: inofensiva.
- **Aplicabilidad (R5).** `field_applicability` aparece en `20260906200000` y en el forward, con `blocking = (v_applicable is false)`; el filtro del dedupe sólo elimina `field_constraint`.

## 4. Paridad Dart/SQL verificada por lectura (sin hallazgo)

Regex de claves `^[a-z][a-z0-9_]*$`; columna `token` con `allowed_values` rechazada; rótulo del destino que es otro vínculo rechazado; cadenas de vínculos permitidas; unidad idéntica en pares; fallback heredado con las mismas tres reglas (tipo, unidad, no duplicar); ciclos de orden rechazados sobre el mismo conjunto de pares; comparación exacta entre `"2"` y `2.0`; id sin recorte y sensible a mayúsculas; `row_shape` bloquea y anula el vínculo sin degradarlo a destino vacío; pendiente no bloquea; ACL de los siete helpers revocada a `anon`/`authenticated`; lector tipado sólo `authenticated`.

## 5. Lo que este bloque no cubre

- La prueba de widget (propiedad de root; root reporta 4 combinaciones verdes: cambio de etiqueta → borrar destino → relink conservando evidencia).
- Ejecución del pgTAP. Las aserciones de §5 dependen de la firma actual de `save_product_with_specs_v1` y de que `record_product_spec_reading_v1` acepte las citas numéricas «10» y «30» dentro de `name || ' ' || description`; si una falla, el primer sospechoso es mi fixture, no el contrato.
- Rebinding por `category_tech_mappings`: un producto que cambia de plantilla por mapeo de categoría no se revalida; clase heredada, igual que para cualquier condición.
- R4: el veredicto es de root con su consulta en producción.

## 6. Entradas leídas (SHA-256)

| Archivo | SHA-256 |
|---|---|
| supabase/migrations/20260907020000_product_spec_row_coherence.sql (árbol, guard aún `after update`) | `b0b6ec6bccb75f87c6b9e27f646a5144a1b8c72deca5813c4e82695204ed796a` |
| .tmp/db/coherence-helpers-local-iteration.sql (guard corregido, aplicado en local) | `36e0a5b824c306013763bf8a985202b810a63eb5b499b8327423139883dd4c66` |
| lib/modules/inventory/models/product_spec_coherence.dart | `8e592e8070bb3d956a975f399f5fef4e84e4f13b4616e69d6248c90bbba0858a` |
| lib/modules/inventory/models/product_spec_contract.dart | `7cbd29624d6d4837f59d7226e516bffc9dac33145d0b558bd14eb6e2c525bcc5` |
| lib/modules/inventory/widgets/product_spec_rows_field.dart | `daa2a2482391a054ccff0e66be9c6a5760c4ae8d34d37e5c0db317689179750d` |
| lib/modules/inventory/services/spec_engine_service.dart | `213beec775e84ab652915ddb15e32cdca95b937f7a54fb324e00f3f719643715` |
| test/unit/product_spec_coherence_test.dart | `832ac9202532448214a49e1bf80e61add12860ff7a0e6803d40ff060d89ab6c7` |
| test/fixtures/product_spec_coherence.json | `189f73c3099d490e9cd28ef02b89fa39c5ca970eb3f9b8f8e6f31476d8478666` |
| supabase/tests/product_spec_row_coherence.sql | `2d61d94a96d3f70416b7faa45012498be33e9063465e46eaf6adbb618ff277d2` |
| supabase/tests/fixtures/product_spec_coherence.sql | `efe4979d09eebb4829fa2fd986a4f0ca4cfddd9a39b10876a431b7b4bc2fc239` |

Salidas (congeladas con esta versión):

| Archivo | SHA-256 |
|---|---|
| test/unit/product_spec_coherence_boundary_test.dart | `ec58abce66eded9d3be4ef27c008372c69bc0675b2d7d7f278ec7b62d22cedc5` |
| supabase/tests/product_spec_row_coherence_boundary.sql | `6b02eab7812308d651857e8c1777c6a44eb05b5f4423435dd5e203d20c8d86e3` |
