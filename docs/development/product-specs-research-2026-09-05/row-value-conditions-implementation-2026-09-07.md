# Valores condicionados dentro de una configuración — 2026-09-07

**CPC-G01 tiene representación ejecutable en el motor local.** `value_when`
expresa implicaciones entre columnas de una misma fila y conserva el valor
observado. El catálogo, los productos y los metadatos publicados no cambiaron.
La adjudicación del catálogo, el despliegue de 2400 y la prueba de UI real son
responsabilidad de la integración principal y siguen pendientes en este paquete.

El [manifiesto](row-value-conditions-implementation-2026-09-07.json) conserva
gramática, hashes, funciones, casos y gates. Los ejemplos son fixtures
sintéticas de software; no son declaraciones OEM ni datos investigados del stock.

La gramática mantiene `rules_version: 2` y `row_conditions.version: 1`.
Cada columna destino de `value_when` recibe una lista no vacía de reglas con
exactamente `when` y `expected`. `when` usa el DSL existente. `expected` contiene
exactamente `value_type` y `value`:

```json
{
  "value_when": {
    "clamp_included": [{
      "when": {
        "kind": "when",
        "rows": [[{
          "field": "configuration_state",
          "operator": "eq",
          "value_type": "token",
          "value": "Con kit incluido"
        }]]
      },
      "expected": {"value_type": "boolean", "value": true}
    }]
  }
}
```

`boolean` exige un booleano JSON; `token`, un literal dentro del dominio de la
columna y de las opciones de plantilla; `decimal`, texto decimal exacto para
una columna decimal o entera. El parser de filas conserva los límites PG,
positividad, integridad y unidades declaradas. `01` no equivale al código `1`;
dos representaciones del mismo decimal sí son iguales. No se aplican conversiones
de unidades ni normalización del significado de un código.

| Estado | Resultado |
| --- | --- |
| Antecedente falso | Ninguna obligación de valor |
| Antecedente desconocido | `row_value_pending`, no bloqueante |
| Antecedente verdadero y dato ausente/desconocido | `row_value_pending`, no bloqueante |
| Antecedente verdadero y valor igual | Sin conflicto |
| Antecedente verdadero y valor conocido distinto | `row_value_conflict`, bloqueante |
| Dos reglas activas exigen valores incompatibles | Conflicto incluso con dato ausente; sin precedencia por orden |
| Columna no aplicable o con aplicabilidad desconocida | Conserva el propietario previo de aplicabilidad/prerrequisito |

`Con kit opcional` no implica `false`. Una fila diferente no satisface el
antecedente ni aporta el valor. La fixture de adaptadores usa dos booleanos
explícitos (`adapter_required` y `adapter_present`); un modelo de adaptador vacío
no se interpreta como ausencia declarada. No se agregaron columnas al catálogo.

Se rechazan referencias a columnas ajenas, tipos incorrectos, literales fuera
de dominio, listas vacías y ciclos, incluso cuando el ciclo combina
`allowed_when`, `required_when` y `value_when`. La ausencia de una tabla completa
continúa bajo las reglas de completitud del campo: este bloque no crea filas.

La implementación de [Dart](../../../lib/modules/inventory/models/product_spec_row_conditions.dart)
expone `valueWhen`, `rule.when`, `rule.valueType`, `rule.expected` y
`validateRow(field, rowId, values)`. Los mensajes muestran «Sí», «No», el código
o la magnitud exacta cuando hay una expectativa confirmada, y distinguen
contradicción del dato de contradicción entre reglas activas. El getter público
usa `_valueWhen ?? const {}`: una instancia anterior que sobreviva a hot reload
conserva sus metadatos previos y no accede a un mapa nuevo nulo. No se ejecutó
una recarga real desde este subtrabajo.

El consumidor central ya integra estos resultados en `validateProductSpecDraft`
([contrato](../../../lib/modules/inventory/models/product_spec_contract.dart),
línea 343). El formulario presenta `_specIssues` y bloquea guardar ante errores
([formulario](../../../lib/modules/inventory/pages/product_form_page.dart),
líneas 4795 y 7701). La inspección anterior a la integración UI mostró que
`ProductSpecRowsField._conditionedCell` sólo presentaba aplicabilidad: la
integración principal recibió el gap inline y el API estable para mostrar estas
mismas condiciones. Este paquete no atribuye como terminada esa interfaz.

Los clientes anteriores rechazaban cualquier bucket fuera de los tres ya
existentes; por eso `value_when` falla cerrado en ese parser. Es evidencia del
código inspeccionado, no una prueba contra un binario antiguo. La publicación
de reglas que usen el nuevo bucket necesita el gate de cliente correspondiente.

El [forward 2400](../../../supabase/migrations/20260907024000_product_spec_row_value_conditions.sql)
reemplaza únicamente dos helpers privados inmutables. Mantiene propietario
`postgres`, `SECURITY INVOKER`, `search_path` fijo y ejecución sólo para
`postgres`/`service_role`. Pinea las cinco dependencias existentes de 2200 que
integran la validación y los locks; no modifica sus cuerpos, triggers ni
versiones. El guard rechaza preimágenes desconocidas y permite la postimagen
exacta para replay. También comprueba los hashes al finalizar.

| Helper | Antes | Después |
| --- | --- | --- |
| `spec_row_conditions_metadata_internal_v1(jsonb,jsonb)` | `bdc9903e785f45355d16840963128554` | `f3a61c7ddb5ae221d977207eb692588b` |
| `spec_row_conditions_issues_internal_v1(jsonb,jsonb,jsonb)` | `ff9dfdc494187854222afcf70cb036dc` | `74312e56c452d640b3ced5633f729b7c` |

La publicación conserva la comparación del bloque completo `row_conditions`,
los locks de definición por orden estable y la lectura de población después de
esperar. El agregado conserva el lock de plantilla anterior a leer versión y
validar. No se repitió un experimento con dos conexiones para 2400: las cinco
funciones que poseen esos límites conservan sus hashes revisados de 2200.

La verificación local cerró con:

- **216 pgTAP nuevos**: 46 comportamientos compartidos, 4 metadatos válidos,
  51 inválidos, validador central, publicación, guardado autenticado, trigger
  directo de facts, conservación de producto/hechos y adopción de referencia.
- **101 pgTAP existentes de 2200** en otros dos archivos, sin cambios.
- **155 tests Dart** en la ronda final (106 nuevos y 49 existentes): parser y
  consumidor real de borrador, tipado, precisión, mensajes y conservación de
  observaciones.
- **119 tests Python** nuevos y existentes del validador de metadatos.
- **Verificador SQL de sólo lectura**: hashes/ACL de siete funciones y los 46
  comportamientos compartidos. Ambas aserciones devolvieron `1`.

Los logs están en `.tmp/row-value-pgtap-final.log`,
`.tmp/row-value-pgtap-regression.log`, `.tmp/row-value-dart-final.log`,
`.tmp/row-value-python-final.log`, `.tmp/row-value-verify-final.log` y
`.tmp/row-value-migration-final.log`. Los pgTAP terminan en rollback y no dejan
fixtures. La base local fue devuelta a la integración principal al cerrar esos
comandos; no se utilizó producción.

Dos correcciones surgieron de las pruebas. Primero, `when: null` era rechazado
con `22023` por el DSL previo; el nuevo bloque ahora comprueba el objeto y
normaliza su error de condición como metadato inválido `23514`. Segundo, el
helper Python previo permitía exponentes de cero hasta int64. Una lectura local
confirmó que PG acepta `0e1073741823` y rechaza `0e1073741824`; Python se alineó
con ese límite y con el parser Dart vigente. No hubo aceptación de datos
contradictorios en estos dos fallos iniciales.

Para repetir la verificación de postimagen, usar
`scripts/db/query.sh local --file docs/development/product-specs-research-2026-09-05/product-spec-row-value-conditions-verify.sql`.
El archivo contiene dos SELECT; no usar `--format json` para envolverlos como una
única consulta. Esa combinación provocó un fallo sintáctico en una ejecución
del verificador y se corrigió al ejecutar el archivo normalmente.

Permanecen fuera de alcance: comparaciones entre dos celdas como operandos,
aritmética, destinos de texto/URL, relaciones entre filas, identidad del miembro,
certificación mecánica, publicación de reglas de catálogo y llenado. Una
referencia puede conservar una observación independiente; que coincida con el
borrador no anula un conflicto de la plantilla. Ninguna de estas pruebas
habilita el llenado ni declara completa una familia de productos.
