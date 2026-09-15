# Revisión independiente: condiciones dentro de una configuración

Fecha: 2026-09-07. Responsable de revisión: `spec_boundary_review`.
Estado: dictamen local congelado. RC1–RC5 tienen corrección y evidencia focal
verificada; no quedan bloqueos reproducidos abiertos en este alcance. La
publicación y la ejecución SQL pertenecen a root.

## Alcance y evidencia

Se revisaron el contrato de `ProductSpecRowConditions`, su entrada desde
`SpecTemplate` y el lector atómico, `validateProductSpecDraft`, la construcción
del payload, el editor `ProductSpecRowsField` y la migración forward
`20260907022000_product_spec_row_conditions.sql`. La revisión siguió los
consumidores reales: `product_form_page.dart:1434` conserva la identidad del
widget al actualizar el borrador; `:4764` centraliza los problemas de la ficha;
`:4773` construye el comando; el campo activo recibe `rowConditions` en
`:7872`. La visualización de historia/referencia mantiene su esquema original
en modo de lectura.

Las fixtures son sintéticas. Comprueban representación, validación y
preservación; no constituyen evidencia mecánica, investigación de stock ni
llenado de productos. Este agente no ejecutó DB, runtime, Claude ni cambios de
implementación. Root conserva esas superficies y los archivos de implementación.

Archivos propios:

- `test/unit/product_spec_row_conditions_boundary_test.dart`: 14 regresiones.
- `supabase/tests/product_spec_row_conditions_boundary.sql`: 26 asserts pgTAP,
  transacción con rollback, IDs `c0bd…`.
- `.tmp/product-spec-catalog/row-conditions-review-concurrency.sql` y
  `row-conditions-review-concurrency-reverse.sql`, con su
  `row-conditions-review-concurrency-cleanup.sql`: probes locales de dos
  conexiones, IDs `c0bf…`; su ejecución corresponde a root.

## Hallazgos reproducidos

### RC1 — el dato retirado permanecía visible con requisito desconocido

Severidad: P2. Alcance: celdas de texto o número editadas bajo `allowed_when`
desconocido; sin bypass del servidor.

Fixture mínima: fila `a`, `detail="Retained original"`, `flag` ausente y regla
`detail allowed_when flag == true`. El control queda deshabilitado y conserva
la observación. Al pulsar **Retirar dato**, el callback elimina `detail` y
desaparece el botón, pero `EditableText.controller.text` continuaba mostrando
`Retained original`. El campo permanece montado porque la aplicabilidad sigue
desconocida. `TextFormField.initialValue` con la misma key no resincronizaba su
estado interno.

El test `retiring a value while prerequisite is unknown clears its control`
falló con esperado vacío / actual `Retained original`. También comprueba que
el retiro no cambia fuentes. Root sustituyó `initialValue` por controladores
sincronizados con cambios externos y conserva el cursor en las pulsaciones
locales. El mismo assert pasó en la repetición independiente de 14/14.

### RC2 — token abierto con opciones de plantilla seguía admitiendo texto libre

Severidad: P2. Alcance: una columna `type=token` sin vocabulario cerrado en el
esquema, acotada por `row_conditions.allowed_options`.

Fixture mínima: `kind` token abierto, opciones de plantilla `["A","B"]`.
SQL/Dart aceptan ese metadato y rechazan una respuesta conocida `C`. El editor
usaba selector únicamente si `column.allowedValues.isNotEmpty`, por lo que
presentaba un `TextFormField` y no ofrecía el dominio válido de la plantilla.
No se observó que `C` pudiera guardarse: la contradicción era bloqueante.

El test `allowed_options narrows an otherwise open token to a picker` encontró
cero selectores. Root cambió la condición para usar también las opciones
explícitas de plantilla. El mismo assert pasó en la repetición independiente.

### RC3 — el selector de referencias ignoraba las opciones de la plantilla

Severidad: P2. Alcance: token abierto que representa el ID de una configuración
referenciada y tiene `allowed_options`.

Fixture mínima: opciones de referencia `{member_a: Model A, member_b: Model B}`
y restricción de plantilla `ref_id=["member_a"]`. El contrato permite esta
composición; el picker ofrecía ambos IDs, aunque la validación rechazaba
`member_b`. No se confunden etiquetas con identidad: el filtro se aplica al ID.

El test `reference choices respect allowed_options of an open token` obtuvo
`[member_a, member_b]` cuando esperaba `[member_a]`. Root implementó la
intersección y un mensaje para un valor conservado fuera de alcance; el mismo
assert pasó en la repetición independiente.

### RC4 — deriva de clasificación ante filas mal formadas

Severidad: P3. Alcance: diagnóstico SQL/Dart; no aceptación de un tipo inválido.

En las regresiones SQL #7/#8, una celda numérica enviada como JSON number y
otra como texto `1,5` se rechazaban con `field_constraint` en el validador
central cuando el campo no tenía un vínculo `row_coherence`. Dart emitía
`row_shape`. Los asserts pedían explícitamente `row_shape` y fallaron; root
informó 24/26 PASS y confirmó que ambos casos eran bloqueantes.

Root añadió `row_shape` al helper de condiciones para documentos inválidos y
deduplicación cuando el mismo campo participa en coherencia. La clasificación
no debe confundirse con un bypass de precisión ni con aceptación de la coma
en el transporte: la coma sólo se normaliza al editar, y las filas del wire
requieren cadenas decimales válidas. El log de root
`.tmp/db/spec-row-conditions-pgtap.log` confirma después ambos archivos pgTAP
verdes, incluidos los 26 asserts independientes.

## Invariantes comprobadas

Las primeras 11 regresiones Dart pasaron antes de modificar el editor, y las
14 pasaron después de las correcciones RC1–RC3 mediante:

```sh
fvm flutter test --no-pub test/unit/product_spec_row_conditions_boundary_test.dart --reporter expanded
```

- `required_when: never` no retira `required: true` del esquema. La omisión
  conserva un problema no bloqueante de completitud; `allowed_when` no puede
  volver condicional una columna requerida del esquema.
- `"01"` y `"1"` son tokens distintos. No se convierten a número para satisfacer
  predicados. `false` es un valor conocido, no ausencia.
- `9007199254740993.125` se distingue de
  `9007199254740993.1249999999999999`. Los operandos numéricos JSON no sustituyen
  los operandos decimales de texto.
- JSON number dentro de una fila, `-`, `1,5` y `1e131072` son rechazados por el
  dueño del esquema y no se empaquetan mediante `buildFactPayload`.
- Un valor homónimo fuera de la fila no resuelve su prerrequisito. Se conserva
  el dependiente pendiente, la identidad de fila, fuentes y texto decimal en el
  payload; no se rellena el upstream.
- El ciclo que atraviesa `allowed_when` y `required_when` se rechaza. Un campo
  ajeno en los metadatos se convierte en un problema central bloqueante.

`buildFactPayload` es un serializador con validación de forma, no el dueño de
todas las condiciones. El formulario ejecuta `validateProductSpecDraft` antes
de guardar; el RPC termina en `spec_validate_product_internal_v1` y su
validador central. Esta distinción evita atribuir al serializador una protección
que no implementa por sí solo.

Las 26 regresiones SQL agregan los bordes de publicación y transporte que no
quedan demostrados por los tests Dart: invalidar el tipo/vocabulario/key de una
columna aun sin hechos, retirar el campo o volverlo legacy, población sólo en
referencias, adopción de una referencia coincidente pero contradictoria con la
plantilla, guardado autenticado con upstream desconocido y preservación total
tras una resolución contradictoria. Sus resultados se atribuyen a root.

## RC5 — ventana de publicación concurrente: confirmada y corregida localmente

Severidad: P1. Root ejecutó los probes por el wrapper local; la revisión leyó
los logs exactos. La hipótesis inicial se confirmó para **producto nuevo y
referencia**. El aggregate de producto existente ya quedaba bloqueado en este
intercalado; ese caso no demuestra protección del aggregate de alta.

| Schedule | Antes, log `spec-row-conditions-concurrency-expanded-before.log` | Después, log `spec-row-conditions-concurrency-after.log` |
|---|---|---|
| Producto existente | B rechazado `55P03`, cero hechos | B rechazado `55P03`, cero hechos |
| Producto nuevo, categoría propia → plantilla | B `written`, producto presente, un hecho y `row_field_applicability` bloqueante contra condiciones publicadas | B rechazado `55P03`, producto ausente, cero hechos |
| Referencia | B `written`, referencia presente y condiciones publicadas | B rechazado `55P03`, referencia ausente |

Ambos logs están en `.tmp/db/`. En el schedule de producto nuevo el servidor
había aceptado y commiteado una observación bajo el contrato anterior mientras
la publicación ya había terminado de revisar sus endpoints vacíos. No era
sólo una clasificación equivocada del mensaje. En la referencia, el camino de
inserción evitaba la misma barrera de población usada por la publicación.

Puntos de entrada comprobados en código:

| Frontera | Primera lectura / bloqueo relevante |
|---|---|
| Aggregate `save_product_with_specs_v1` | Migración 160000, líneas 503–507: resuelve y lee plantilla/version sin `FOR SHARE`, antes de comparar `p_contract_version`. Ya tiene lock del producto y advisory por producto. |
| Hecho estructurado | Migración 190000, `spec_rows_fact_guard_internal_v1`, línea 247: `spec_definitions … FOR SHARE`, antes de validar la fila. |
| Referencia estructurada | Migración 190000, `spec_rows_reference_guard_internal_v1`, líneas 269–277: cada definición `FOR SHARE`, antes de validar y sustituir el valor de filas. |
| Publicación | Forward 2200, `spec_coherence_publication_guard_internal_v1`: chequea población de endpoints sin bloquearlos en exclusiva; la validación de metadatos sólo toma `FOR SHARE` de definiciones. |

Plan de reproducción controlado:

1. Crear y commitear únicamente el fixture local `c0bf…`, con filas definidas y
   producto existente pero sin hechos/referencias.
2. A actualiza la plantilla para añadir `detail allowed_when flag == true`.
   Fuerza `SET CONSTRAINTS ALL IMMEDIATE`, completando el chequeo de vacío.
3. B, con sesión autenticada de ese tenant, guarda mediante el aggregate
   `flag=false` junto con `detail`, mientras ve la plantilla anterior. Se prueban
   producto existente y alta con categoría propia, pues el alta carece de la
   fila de producto que podría bloquearse indirectamente. B fuerza sus
   constraints y hace COMMIT. A hace COMMIT.
4. Leer el hecho persistido y los problemas contra la nueva plantilla. Un
   hecho guardado más `row_field_applicability` bloqueante probaría la ventana.
5. Repetir sobre otro endpoint vacío con la inserción de una referencia. Esa
   ruta tiene su propio guard por definición y no usa el aggregate.
6. El script elimina sólo sus IDs y confirma la limpieza. Se corrigieron dos
   errores de su primera limpieza: la referencia es inmutable y el FK del
   sujeto polimórfico no elimina `spec_facts` con el producto. El cleanup final
   retira los hechos por tenant + `subject_type=product` + dos IDs propios antes
   del producto; suspende únicamente `product_spec_reference_immutable` bajo
   lock de tabla, retira la referencia propia y restaura el trigger en la misma
   transacción. No suspende los triggers de hechos ni usa replication role.
   El log AFTER confirma `row_conditions_review_fixture_removed=true`.

El probe utiliza `dblink` dentro de la conexión del wrapper local. Descubre el
schema de la extensión existente, no instala extensiones ni imprime el secreto
de conexión. B tiene `lock_timeout=750ms` y `statement_timeout=4s`; después de
una corrección, esperar y devolver `55P03` es el resultado acotado previsto.

Root incorporó en 2200, aún local al revisar, `FOR SHARE OF t` en la primera
lectura de plantilla/version del aggregate y `FOR UPDATE OF d`, con orden UUID
estable, sobre las definiciones endpoint de la publicación. La consulta de
población está en una sentencia posterior, para tomar el snapshot después de
una espera. Es compatible con los guards existentes que toman `FOR SHARE` de
definiciones al insertar hechos/referencias. El probe AFTER demuestra bloqueo
cuando la publicación tiene prioridad.

El probe inverso mantiene primero la escritura y sus locks; publica en la
segunda conexión, comprueba que espera, commitea la escritura y exige un
rechazo `23514` de publicación por población. Un simple timeout `55P03` sería
inconcluso para esta dirección. Root ejecutó
`.tmp/db/spec-row-conditions-concurrency-reverse-after.log`: en las tres rutas
(`aggregate`, `aggregate_new`, `reference`) se observó `publisher_busy=true` y
`publisher_waiting_on_lock=true` antes del COMMIT de escritura, seguido de
`23514` por población después de ese COMMIT. La limpieza volvió a confirmar
`row_conditions_review_fixture_removed=true`. Se leyó el log, no se infirió el
resultado de la existencia del lock en el código.
La edición de una definición también debe revisarse por orden de locks:
actualmente empieza por definición y su trigger de revisión toca la plantilla,
mientras publicar empieza por plantilla y después definición. Un deadlock
debería abortar/reintentarse, nunca ser interpretado como éxito.

## Estado exacto revisado

La comparación del cuerpo de `save_product_with_specs_v1` de 160000 con el
nuevo de 2200 sólo cambia la primera lectura de plantilla añadiendo
`FOR SHARE OF t`. El resto de la autenticación, controles de tenant,
idempotencia, revisión, product lock y validación final se preserva.

La lectura del receipt `.tmp/db/spec-row-conditions-function-state.json`
concuerda con las siete entradas de
`product-spec-row-conditions-verify.sql`. Los siete owners son `postgres` y
mantienen `search_path=pg_catalog, public, pg_temp`. Sólo el aggregate entre
estas siete funciones es ejecutable por `authenticated`; los helpers no
conceden EXECUTE a `authenticated`, `anon` ni PUBLIC. Es lectura de evidencia
capturada por root, no una consulta DB realizada por el revisor.

| Función | MD5 de `pg_get_functiondef` revisado |
|---|---|
| `save_product_with_specs_v1` | `007ed3a67a009527c24ed54ee3380b99` |
| `spec_coherence_issues_internal_v1` | `48f01ef6f5343dfe3a45285ad227fb60` |
| `spec_coherence_metadata_internal_v1` | `863ba9ce738f2c6d497e1a3786c02eb5` |
| `spec_coherence_publication_guard_internal_v1` | `1d9f691d7e044034255f7500c21feb7c` |
| `spec_row_conditions_issues_internal_v1` | `ff9dfdc494187854222afcf70cb036dc` |
| `spec_row_conditions_metadata_internal_v1` | `bdc9903e785f45355d16840963128554` |
| `spec_template_rules_validate_internal_v1` | `273b46c7568552a6e2641eec4f69f59c` |

SHA-256 del material congelado al dictaminar:

| Archivo | SHA-256 |
|---|---|
| `20260907022000_product_spec_row_conditions.sql` | `6d18c2e1e985d73ca935987a5615bf6365e8a32e26720a5068e78bbb878f16a7` |
| `spec-row-conditions-function-state.json` | `5769f54ce17d491cceccf277b508de08a7279b442b9cb87680f001bece3a4c53` |
| `product-spec-row-conditions-verify.sql` | `2f71f70f7c904edb0b7a9765898fa49b6a022fbfccb633e29dc5dfe25a2e3acc` |
| `product_spec_row_conditions_boundary_test.dart` | `c6e3b0a560879127bc2780e5cc312640de12bfe9da56fddcf5509c9740eeecc5` |
| `product_spec_row_conditions_boundary.sql` | `25e3b8f1cfbb02b026bf20d70b426298e667a45728e5c9e7a8156aed33c438a2` |
| `row-conditions-review-concurrency.sql` | `a92862760edd10a86c7c7cb04426e215fb4f3093c003d56fb6445f77505a2d0b` |
| `row-conditions-review-concurrency-reverse.sql` | `55118ebe18162dd9de0166cd83c6169bfb98a35385966cdf9325a7cde5cb4fbd` |
| `row-conditions-review-concurrency-cleanup.sql` | `a2beae662c889a920d7b22570e86699a58cedcddd3c579a30571bb3949f29556` |

## Límites del dictamen

- Evidencia independiente ejecutada: 14/14 Flutter. Evidencia SQL ejecutada
  por root y leída: 101/101 pgTAP, 75 del archivo raíz y 26 del archivo propio;
  tres rutas concurrentes en ambas direcciones tras corrección.
- No se probó exhaustivamente todo intercalado posible entre ediciones de
  definiciones y plantillas. El orden opuesto de locks descrito arriba es un
  riesgo operativo de abortos/reintentos, no una aceptación incorrecta
  observada en los probes.
- El estado de despliegue, hashes/ACL efectivos y verificación de la app real
  no pertenecen a este dictamen local. Los resultados focales no cierran el
  saneamiento mecánico de todas las familias ni autorizan llenar productos.
