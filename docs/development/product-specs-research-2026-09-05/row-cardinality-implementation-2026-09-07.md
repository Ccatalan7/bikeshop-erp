# Cardinalidad explícita de colecciones — implementación local, 2026-09-07

Estado de entrega: Dart y Python probados; forward SQL y pgTAP preparados para ejecución serializada por Root. Esta tarea no ejecutó SQL, no publicó metadatos, no cambió productos y no usó el runtime. Los gates de llenado y cierre mecánico siguen cerrados. AG01 no queda cerrado por contar filas.

## Contrato mínimo y alcance

La extensión pertenece a `row_coherence.version = 2`, dentro de una sola plantilla con `rules_version = 2`:

```json
{
  "row_coherence": {
    "version": 2,
    "links": [],
    "cardinalities": [
      {
        "id": "collection_occurrences",
        "field": "items",
        "total_field": "total"
      }
    ]
  }
}
```

`field` debe ser una definición activa de filas de esa plantilla. `total_field` debe ser una definición numérica activa con `validation_rules.integer = true` y un mínimo explícito interpretable no negativo. Se conservan sus límites adicionales. Se rechazan claves ajenas, campos retirados, esquemas ausentes, identificadores inválidos, IDs de regla duplicados —también respecto de `links`—, dos totales para una misma colección y ciclos con prerrequisitos/visibilidad.

La definición editorial de la colección debe garantizar que cada ID de fila representa una ocurrencia del objeto contado. El motor no decide si esa ocurrencia es una pieza separable, una corona integrada, una unidad comercial o una posición de montaje. Tampoco puede certificar que la investigación distinguió dos ocurrencias reales de dos descripciones de la misma. Ese alcance se adjudica antes de activar cada relación en catálogo.

| Observaciones disponibles | Resultado |
|---|---|
| Total `N` entero exacto no negativo y `R > N` filas válidas | `row_cardinality_conflict`, bloqueante |
| `N` conocido y `R < N` | `row_cardinality_pending`, no bloqueante |
| `N` ausente, nulo, vacío o marcado desconocido | Pendiente; no se calcula desde las filas |
| `N = R` | Ningún conflicto de cardinalidad; las celdas pendientes siguen pendientes |
| `N = 0`, sin tabla observada | Ningún dato o fila se crea para representar ese cero |
| Total de tipo/formato/dominio inválido | Error bloqueante de total; nunca se usa para contar |
| Documento de filas inválido, ID duplicado o celda presente inválida | `row_shape`; no se descartan filas para producir un conteo menor |
| Fila válida con ID estable y celdas pendientes | Cuenta como ocurrencia; su incompletitud se informa por separado |
| Tabla poblada ya rechazada por `field_applicability` | Ese conflicto conserva la autoridad; no se duplica con cardinalidad |

El validador numérico ordinario conserva sus códigos (`integer`, `type`, `range` en Dart; `field_constraint` en SQL). `row_cardinality_total` cubre la evaluación aislada y los tipos que el criterio genérico de ausencia no debería convertir en un total desconocido, por ejemplo un array vacío. Un documento de tabla vacío o un array vacío explícito no equivale a una observación válida de cero filas.

No se suman `kit_members`, campos de cantidades distintos ni otra colección. No se cuentan sólo filas con dientes/medidas completos. No hay nombres de familias ni claves de transmisión en el evaluador. Un subconjunto de filas tampoco genera un total derivado. Se conserva la distinción documentada en `package-contents-boundary-review-2026-09-07.md`: una unidad comercial o monobloque puede representar más de una ocurrencia del objeto contado.

## Versionado, almacenamiento y consumidores

La forma v1 conserva `version` y `links`; no acepta `cardinalities`. La forma v2 requiere explícitamente `version`, `links` y `cardinalities`. Un cliente que sólo conoce la versión anterior rechaza v2 al parsear la coherencia. El servidor sigue validando el agregado y la versión vigente de la plantilla, incluso si un cliente omite una comprobación visual.

Los valores no reciben una versión nueva: se reutilizan los documentos de filas con IDs estables y fuentes existentes. Validar no modifica el mapa del borrador. Empaquetar conserva IDs y fuentes y mantiene la normalización numérica ya existente; no agrega un total omitido. Los totales se comparan con `SpecRuleDecimal`/`numeric`, sin convertir el conteo declarado a `double` ni a un entero de ancho fijo. La UI puede admitir texto decimal localizado o exponencial; el transporte normal del editor lo canonicaliza. Un `num` heredado inseguro por encima de `2^53 - 1` se rechaza en Dart, mientras un texto decimal exacto sigue siendo representable. Esto no limita físicamente la cantidad de contenido de un producto.

El cambio de Dart queda en `ProductSpecCoherence` y en dos conexiones existentes: `SpecTemplate.coherence` entrega las reglas numéricas; `validateProductSpecDraft` conserva un único dueño de los conflictos ya informados. El acceso nuevo a `cardinalities` tiene backing nullable para instancias antiguas retenidas durante hot reload. No se editó el renderer. La representación visible de los resultados sigue el flujo existente de `ProductSpecIssue` y su etiqueta de campo; esta entrega no atribuye evidencia visual al runtime.

Una referencia es una observación independiente. Su inserción no constituye aprobación para todas las plantillas de una familia. Al adoptarla o validar su contenido contra una plantilla, una coincidencia literal con la referencia no omite la cardinalidad. El pgTAP incluye una referencia que documenta `N = 1` y dos filas: el validador debe conservar el conflicto aun cuando borrador y referencia coincidan.

## Forward SQL y preservación

`20260907025000_product_spec_row_cardinality.sql` reemplaza seis funciones, conserva firmas, propietario, volatilidad, `search_path` y ACL privadas. No cambia tablas, políticas, filas de catálogo, facts, opciones, lecturas, referencias, identidad ni campos comerciales.

| Función | Preimagen MD5 | Postimagen esperada MD5 |
|---|---|---|
| `spec_coherence_fields_internal_v1(uuid)` | `e3b437887bdcbb2766d46805beb3a719` | `842a6575f1eedcef45b7749b76e458e9` |
| `spec_coherence_metadata_internal_v1(jsonb,jsonb)` | `863ba9ce738f2c6d497e1a3786c02eb5` | `62b9c8349bf9d4fa4f983d3009980171` |
| `spec_coherence_issues_internal_v1(jsonb,jsonb,jsonb)` | `48f01ef6f5343dfe3a45285ad227fb60` | `d57404a97c12b336e64b59202b3d56f4` |
| `spec_coherence_publication_guard_internal_v1()` | `1d9f691d7e044034255f7500c21feb7c` | `235850d2afe7e1571431c7f7c4942b7b` |
| `spec_template_rules_validate_internal_v1(uuid)` | `273b46c7568552a6e2641eec4f69f59c` | `61cc6156d8ec2f36a7e9a1cc47b95c53` |
| `spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)` | `25a18d1d600cf2d8da7c30a59e54123f` | `9ea12d82761d6ffd0584d460cbc998d6` |

Las postimágenes se calcularon sobre el texto canónico de `pg_get_functiondef`; la misma normalización reproduce las seis preimágenes conocidas. Eso es una comprobación estática, pendiente de read-back SQL real. Root suministró la captura productiva `.tmp/db/spec-cardinality-production-preimages.json`; se leyó y coincide en esas seis preimágenes, ACL, propietario, configuración y volatilidad. Esta revisión no efectuó esa consulta.

El guard de publicación compara las relaciones efectivas antiguas/nuevas e incluye **ambos extremos**, colección y total. Mantiene el patrón ya revisado de 2200: bloquea las definiciones por ID en orden estable con `FOR UPDATE`, en una sentencia separada anterior a releer la población. Los writers de facts y referencias conservan su `FOR SHARE`; la validación de metadatos conserva los locks de plantilla/definiciones. Así se evita que una referencia que sólo contiene el total quede fuera del límite de publicación. La prueba nueva cubre esa población de referencia sin filas de la colección.

No se implementó otro orden de locks ni se hizo una nueva reproducción de dos conexiones en esta subentrega. Se conservaron las rutas y la separación de sentencias verificadas durante 2200. Los resultados anteriores de concurrencia no se presentan como una ejecución nueva de cardinalidad.

Por solicitud expresa de Root se incorporó una corrección localizada al mismo evaluador central: una celda requerida se considera pendiente cuando `NOT spec_rule_known_internal_v1(row->'values'->key)`, en lugar de mirar sólo si existe la clave. Conserva `false` y `0` como conocidos; un token requerido `Desconocido / sin confirmar` sigue pendiente y no se convierte en bloqueo. La evidencia previa fue `tpdu_unit_declared_unknown_is_still_only_pending` en `.tmp/db/spec-all-family-evidence-scopes-trial.log`, reportada por Root. La regresión SQL propia verifica desconocido, cero y false sin bajar la exigencia del caso de catálogo.

La recuperación anterior a activar v2 consiste en restaurar las seis definiciones verificadas mediante un forward guardado, sólo después de comprobar que ningún contrato activo usa v2. Una vez publicada esa gramática, retirar el evaluador o degradar la versión podría omitir restricciones: la recuperación debe mantener el contrato o aplicar una corrección revisada junto con su estado legacy. No hay borrado automático de filas para facilitar la recuperación.

## Verificación propia y pendientes de integración

- 264 pruebas Dart pasaron en cuatro archivos de cardinalidad, coherencia, condiciones de fila y `value_when`, antes de las tres últimas regresiones. Después, el archivo propio actualizado pasó **79/79**, incluyendo los dos arrays vacíos inválidos y un identificador con salto de línea.
- **47/47 pruebas Python** de cardinalidad y condiciones de fila pasaron por `unittest discover`. El primer comando intentó importar `test.scripts` como paquete y falló antes de ejecutar pruebas; se corrigió el descubrimiento, sin modificar expectativas.
- Fixture común final: **41 casos de valores y 26 metadatos inválidos**, idénticos en JSON y en la envoltura SQL. Incluye formas inválidas, límites PG, decimales equivalentes, total exacto mayor que `2^53`, desconocidos, celdas pendientes y conservación del input.
- Analizador focalizado: **0 errores, 0 warnings y 7 infos**. Los infos son llaves de control de flujo y la dependencia ya referenciada `collection`; no se declara un análisis global limpio.
- `git diff --check` de los cuatro archivos de implementación compartidos no devolvió errores.
- Se preparó `supabase/tests/product_spec_row_cardinality.sql` con rollback, aislamiento sintético, evaluador/metadata central, agregado autenticado, versión obsoleta, escritura directa de facts, preservación de datos y fuente, referencia contradictoria y guard de publicación. **Su resultado SQL queda pendiente de Root** al congelar esta entrega.
- Root informó 422 pruebas Dart en su catálogo derivado `934ce172…` / casos `bede596b…`. Es evidencia de integración suministrada por Root; esta tarea no escribió ni activó ese catálogo.

Logs propios: `.tmp/product-spec-catalog/cardinality-dart-boundary.log`, `cardinality-python-boundary.log` y `cardinality-analyzer.log`.

Los tres archivos reservados por Root (`product_spec_catalog_trial.py`, `product_spec_field_patches.py` y `product_spec_integrated_catalog_test.dart`) no se editaron. No se amplió el motor para sumar componentes ni decidir equivalencia de piezas, variantes o montajes. Las asignaciones, evidencia OEM, relación entre `kit_members` y contenido, ensayo SQL, despliegue y lectura/UI posterior siguen siendo gates independientes.

## Hashes al congelar

| Archivo | SHA-256 |
|---|---|
| `lib/modules/inventory/models/product_spec_coherence.dart` | `503e8896f5ce467f955df5a0ad1d0acb951d6ff8ec01736c8a2925372f537322` |
| `lib/modules/inventory/models/product_spec_contract.dart` | `77ff6c54a5a30ecb3752e2a4de9f1018a76c1bd66e8910a7996b165be4d269ea` |
| `lib/modules/inventory/services/spec_engine_service.dart` | `83035fec72c778a94fa4bf635c744dfc59119218e0f79a540229294369ce4aec` |
| `scripts/inventory/compile_product_spec_catalog.py` | `f72a3aac62a30afb81d414e00fc19d9cfcd43d20f2c5f2b7faa3e5f572486881` |
| `scripts/inventory/product_spec_row_cardinality_metadata.py` | `2ff0e7566dd3d338f55fa84209c7197a0863619ab80c8d7dd451df132fdd5c6c` |
| `test/unit/product_spec_row_cardinality_test.dart` | `563e123a856e4257dbdaed052e2b9fda737b5ed5d100468c40ed03079e4346ab` |
| `test/scripts/test_product_spec_row_cardinality_metadata.py` | `da511c71f968c998049d53ee40be8f222bc94ee0f96885327ac13eb28d3d77e4` |
| `test/fixtures/product_spec_row_cardinality.json` | `8702a9b5a7cc1fa7fd5714d33ddf7682c300b36f908b18bdcd6ea831fc788a5b` |
| `supabase/tests/fixtures/product_spec_row_cardinality.sql` | `1d1463c78c1bb3eafa5a7be8e0ed82a608265684b5dafd8b60056b6ea56d59c2` |
| `supabase/migrations/20260907025000_product_spec_row_cardinality.sql` | `6a4cd99868055020a2671b1574ccff56f347848156e80a41f2d0f66aa0a23b92` |
| `supabase/tests/product_spec_row_cardinality.sql` | `bbecff6fd2b6002e58df6d49ebc326bfff7d2800d608e3e2d5a276d31d94e3bb` |
| `product-spec-row-cardinality-verify.sql` | `ea2b5c86a93fafc25fb2b0a6270f5b40ff4b1fdeaf8d4f2a6191f77f29eee655` |
