# Revisión independiente del snapshot de investigación — 2026-09-07

Estado: **aceptación independiente acotada, congelada**. RS1–4 y la preservación/coherencia de filas están corregidos y verificados mediante 71 aserciones pgTAP independientes. Se revisaron el bloque final de preimágenes y el verificador de los seis cuerpos SQL. La aceptación se limita al snapshot y la simulación SQL autenticados: no aprueba compatibilidad física, fuentes OEM, publicación de metadatos ni llenado de productos.

## Alcance y evidencia

Se inspeccionaron `get_product_spec_research_snapshot_v1` y `preview_product_spec_research_v1`, sus lectores exactos de 0100, el validador canónico y los límites de referencias/filas de 180/190/200/0200/2200. El simulador Python y su esquema se leyeron sólo para distinguir simulación de aplicación. No se editaron implementación, migraciones ni pruebas del integrador. A petición posterior del integrador, se creó el test independiente `supabase/tests/product_spec_research_snapshot_boundary.sql`. No hubo consultas a producción ni control del runtime.

Las pruebas independientes usan datos sintéticos locales con prefijo UUID `f2222300`, `SET LOCAL ROLE authenticated`, el wrapper canónico y `ROLLBACK` final. Las inserciones preparan fixtures; las RPC bajo revisión sólo se invocan como lecturas. Una fixture tuvo inicialmente un código de opción con guion, rechazado por el dominio existente; se corrigió a `review_01`/`review_02` antes del resultado registrado. Eso fue un error del probe, no un hallazgo del producto.

Evidencia BEFORE congelada:

- `.tmp/product-spec-catalog/research-snapshot-review-boundaries.sql`: SHA-256 `6cccd9a56af25093e5d01d0c156ef1f27cb1f8729b6211e18aec310fe67f87c4`.
- `.tmp/product-spec-catalog/research-snapshot-review-boundaries.log`: SHA-256 `a1e627805c512e5c13de522c658f6dde80a8d4eb282cd2421ea0e6628110a592`. Ejecución exitosa, `ROLLBACK` confirmado.
- MD5 de `get_product_spec_research_snapshot_v1(uuid)` ejecutado: `139aac7ae044108393e15d0ae78f377b`.
- MD5 de `preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)` ejecutado: `b9a6e2e92ca8383aa6c153abe8920b62`.
- MD5 del validador canónico observado: `25a18d1d600cf2d8da7c30a59e54123f`. No fue sustituido por este probe.

Comando de reproducción local, previa coordinación de la ventana de DB:

```sh
VINABIKE_DB_WRITE_CONFIRM=local scripts/db/query.sh local --write --file .tmp/product-spec-catalog/research-snapshot-review-boundaries.sql > .tmp/product-spec-catalog/research-snapshot-review-boundaries.log 2>&1
```

La variante AFTER ejecutada usa `.tmp/product-spec-catalog/research-snapshot-review-after.sql`, SHA-256 `3b5760f0b70ba288a085907989cff06bb259b07aa3c07b311f9c23d0496540c0`. Log final de esta iteración: `.tmp/product-spec-catalog/research-snapshot-review-after-v2-origin.log`, SHA-256 `9d20048e8b137341df761fd8262afeb43c1bc15eee4bcbd76af7a3085270869f`, exit 0 y ROLLBACK. El SQL aplicado localmente tenía SHA-256 `ab106a123725a234fb9f8835608d98d32825514e0eaa2f6cc9e9c96f10cff36e`; los MD5 ejecutados fueron snapshot `981026d3283612b825ff3231d0d9ab41`, preview `a48f8882900af7d7e945ad4cbc561df2`. El validador conservó su MD5 anterior. No atribuir este resultado a una revisión posterior del archivo.

## Regresión final independiente

`just db-test product_spec_research_snapshot_boundary` terminó **71/71 PASS** contra SQL local SHA-256 `b8ad3c311bc335f41c24bc1f4708eb3fef5736fe8e30dfae853f0a6e27212c03`, después de corregir los lectores v1/v2. No se repitieron los probes de referencias/coherencia preparados por separado, porque el archivo versionado ya incluye sus aserciones y fixtures. Ninguna prueba requiere datos reales ni una asociación corrupta en producción.

- Test versionado: `supabase/tests/product_spec_research_snapshot_boundary.sql`, SHA-256 `415fa1bb310c3e46d6c0fa5e27e14adea248b6a49c451a775ea66cbd021311bc`.
- Resultado independiente: `.tmp/product-spec-catalog/research-snapshot-review-boundary-pgtap.log`, SHA-256 `ba31981226fa68302ea9daf6d8fbc858d86707c26f5cc255beb0ed8f0e0aefb8`; log del harness `.tmp/db/pgtap-20260907-053611.log`.
- Lectura local de estado: `.tmp/product-spec-catalog/research-snapshot-review-function-state.sql`, SHA-256 `3c68bcedb5600936afbbde9c1cbaefef2b57a2ed4320e205cfecb0bd302148ff`.
- Resultado de esa lectura: `.tmp/product-spec-catalog/research-snapshot-review-function-state.log`, SHA-256 `df7da0852537bd0395a6c6db7460b2d78e2ac6630f232193dc004e4ba273ee7c`.

Los casos con referencias corruptas usan SAVEPOINT, capturan el resultado autenticado en variables psql y ejecutan el assert **después** de `ROLLBACK TO`: así no revierten el contador del propio pgTAP. Las fixtures completas terminan con ROLLBACK. El test y la lectura de estado no modifican funciones.

| Firma | MD5 observado | Volatilidad / definer | EXECUTE efectivo |
|---|---|---|---|
| `get_product_spec_references_v1(text)` | `ac13815c1272725a784596953b771531` | STABLE / sí | authenticated, service_role; anon no |
| `get_product_spec_references_v2(text)` | `ffb27b5770dee7a7ce0675eea552ce9b` | STABLE / sí | authenticated, service_role; anon no |
| `get_product_spec_research_snapshot_v1(uuid)` | `981026d3283612b825ff3231d0d9ab41` | STABLE / sí | authenticated, service_role; anon no |
| `preview_product_spec_research_v1(uuid,text,jsonb,jsonb,text)` | `a48f8882900af7d7e945ad4cbc561df2` | STABLE / sí | authenticated, service_role; anon no |
| `spec_merge_research_rows_internal_v1(jsonb,jsonb)` | `079b3e15c5db9903476f94801394691d` | IMMUTABLE / no | service_role; authenticated/anon no |
| `spec_reference_global_scope_internal_v1(text)` | `f60238e0b53dabe706b1939af477b96a` | STABLE / no | service_role; authenticated/anon no |

En los seis casos el owner real es postgres y `search_path=pg_catalog, public, pg_temp`. El log conserva también el SHA-256 de cada definición. Las preimágenes productivas de v1/v2 que debe guardar el integrador son `a5b42a3914d654170a43b2c8a16c626f` / `9fa7a332a7002cbdfe9a815d246096fb`; su procedencia productiva fue comunicada por root, no consultada por esta revisión.

### Forward y verificador congelados

- `supabase/migrations/20260907023000_product_spec_research_snapshot.sql`: SHA-256 **`132e10acbbdba0ce66d4ecec27a486b3f22004855f32ac899f1adab26f9960a0`**.
- `docs/development/product-specs-research-2026-09-05/product-spec-research-snapshot-verify.sql`: SHA-256 **`2c81e62965ae8e3600c92d1b55c28f20aefcd143bb2dce6a712643e8ba83c11b`**.

El delta respecto de la versión probada agrega el guard inicial; los seis MD5 esperados coinciden con la lectura local independiente. El guard exige la preimagen conocida de los lectores existentes o su postimagen revisada. Para los cuatro nombres nuevos admite ausencia o la postimagen exacta; rechaza colisiones con otro cuerpo. Además verifica owner, definer, volatilidad, search_path y permisos efectivos, y rechaza grantors/grantees/grant options ajenos al contrato. La comprobación ocurre antes de los CREATE OR REPLACE.

El verificador es SQL SELECT de sólo lectura: no crea actores ni fixtures. Exige las seis firmas, MD5 y propiedades de seguridad, convierte una ausencia o comparación null en fallo y emite el estado encontrado. Se revisó por fuente; su ejecución final productiva y el registro de migración corresponden al integrador. Root comunicó reaplicación local exitosa del forward final; no se atribuye esa operación a esta revisión ni se repetió la suite por un guard inicial que deja los cuerpos intactos.

## Hallazgos reproducidos

| ID | Severidad | Reproducción y consecuencia | Corrección acotada | Estado |
|---|---|---|---|---|
| RS1 | P2 | `TEXT_OBJECT`, `BOOLEAN_UNKNOWN_STRING`, `NUMBER_JSON_NUMBER`, `SELECT_ARRAY_NULL`, `ROWS_UNKNOWN_STRING` devolvieron `valid_draft=true`, sin issues. Un objeto en text, string `unknown` en boolean/rows, `[null]` en single select y JSON number `10` pasan por omisiones deliberadas del validador de borrador. | Validar el tipo de transporte antes de invocar reglas: decimal exacto como texto, bool real, cardinalidad y opción activa por ID, parser de filas para JSON. | AFTER: los cinco casos rechazan con 23514. La validación cubre todos los valores activos candidatos, también los derivados. |
| RS2 | P2 | `REFERENCE_OUTSIDE_RETIRED` deriva `review_outside` y `review_retired` desde una referencia, con `valid_draft=true`. El validador filtra esas claves antes de juzgar el borrador, pero la respuesta conserva el candidato ampliado. | Validar cada UUID de `reference.fact_values` contra endpoints activos de la plantilla antes de proyectar claves, y rechazar legacy. Una definición homónima no es el mismo endpoint. | AFTER: campos outside/legacy y definición tenant homónima rechazan con 23514. |
| RS3 | P2 | Tras retirar de la plantilla un campo con un hecho de opción, cambiar el label de la opción altera `editor.unassigned_facts` y mantiene iguales el hash global y observations. La preimagen anterior sigue aceptándose. | Incluir hashes de definición y opción completas también para hechos huérfanos, y cubrir editor completo en el hash de la preimagen. | AFTER: cambian observations/editor/hash; la preimagen anterior rechaza con 40001. |
| RS4 | P1, requiere asociación global corrupta | Una referencia global enlazada por UUID a definición/opción privada del tenant B expone su label al tenant A a través del getter v2 y del snapshot. La lectura directa de la opción bajo RLS devuelve cero filas. | Validar definición y opciones de referencias globales por ID, pertenencia al mismo endpoint y `tenant_id IS NULL` antes de toda proyección; fallar sin exponer metadata privada. Aplicar al lector compartido con su preimagen exacta. | AFTER final: v1/v2/snapshot rechazan con 42501 las diez variantes de definición/opciones/cardinalidad del test. |

RS1/RS2 producen una simulación falsamente válida; no se demostró que el writer tipado aceptara esos valores ni que estas RPC escribieran. RS3 omite una deriva efectiva del contenido revisado; su alcance incluye opciones históricas fuera de la plantilla, no sólo el editor activo.

### Preservación al llenar filas

`ROWS_REPLACEMENT` confirmó BEFORE una semántica de sustitución completa: proponer sólo `original-row.length=10` elimina del candidato `second-row` y `original-row.note`. El snapshot persistido permanece idéntico (`PERSISTED_UNCHANGED=true`). Para una simulación de reemplazo explícito esto sería una limitación documentable, pero el integrador confirmó que el contrato de esta RPC será **fill sin borrados implícitos**.

AFTER verifica el merge por ID estable: cambiar length conserva `second-row`, `note` y `https://example.com/synthetic-original-row`; agregar `added-row` conserva íntegramente las dos anteriores, incluido `0.100000000000000001`. Una celda null o un ID duplicado rechazan con 23514. El snapshot persistido vuelve a ser idéntico tras todas las simulaciones. El helper privado es puro, conserva el orden original y une fuentes antes de validar la tabla final. No se detectó un borrado implícito residual en estos casos.

La regresión versionada agrega un requisito de la misma fila: note sólo aplica cuando length < 5. Proponer length=10 mantiene note y su fuente, devuelve `valid_draft=false` y señala `row_field_applicability` bloqueante en `original-row/note`. Cambiar length a 1 y agregar una fuente conserva la fila y produce una unión ordenada de fuentes. Esta es evidencia del motor de coherencia y merge, no una regla mecánica de bicicleta.

### Extensión del AFTER: referencias

- Shape estricto de hechos derivados: una referencia con objeto text, string boolean o una opción inactiva se rechaza con 23514 después del arreglo. El bucle de validación ahora cubre todos los valores activos candidatos. Las referencias son catálogo global privilegiado; no se demostró que un usuario autenticado pueda insertar estos objetos.
- Guard por ID homónimo: una referencia a la definición tenant `...0058` con key `review_text`, mientras la plantilla vincula el ID global `...0055`, se rechaza con 23514 aunque el valor coincide con el ya presente. No se usa igualdad de label como identidad de definición.
- RS4 se reproduce al final, después de todos los demás casos, para no contaminar sus snapshots: se insertan definición privada `...0072`, opción privada `...0064` y referencia global `review-local-foreign-definition`. `FOREIGN_OPTION_DIRECT_READ` devuelve count 0; `SNAPSHOT_FOREIGN_REFERENCE_DEFINITION` y `DIRECT_V2_FOREIGN_REFERENCE_DEFINITION` devuelven ambos `review_foreign_select: "Foreign tenant private option"`. La proyección exacta anterior usa su privilegio de definer y no comprueba ese grafo antes de resolver el label. El contrato global no debe aceptar endpoints tenant aunque pertenezcan al solicitante, porque la misma referencia es legible por los demás tenants. El hallazgo es condicionado a integridad de catálogo; no hay evidencia de que exista una asociación así en producción.
- El cierre usa un guard compartido por ambos lectores, antes del formatter. El test final verifica rechazo de definición ajena, definición propia homónima, opción tenant en definición global, opción de otro endpoint global, IDs inexistentes, opción inactiva, dos respuestas de single select, duplicados e ID null. Una referencia global válida conserva false y el literal 01. V1 sigue entregando JSON number y sin cabecera v2; v2 conserva el string exacto `9007199254740993.125`. El test no sustituye v1 por el transporte v2.

## Invariantes evaluados

| Invariante | Evidencia y límite |
|---|---|
| Principal y tenant | Ambas RPC exigen `auth.uid()` y tenant resuelto por la función canónica. El producto se busca por ID y tenant. Ausente y ajeno comparten 42501. No se toma la categoría del borrador como autoridad de binding. |
| ACL | Lectura final local: las cuatro RPC tienen EXECUTE para authenticated/service_role y no para anon; los dos helpers privados no son ejecutables por authenticated/anon. La tabla superior fija los cuerpos efectivos. |
| Grafo de observaciones | Snapshot rechaza hechos con tenant ajeno, definiciones privadas ajenas, lecturas de otro tenant y opciones de otro campo/tenant; conserva observations fuera de plantilla y legacy. RS4 está en la proyección de referencias globales, no en estos controles de hechos del producto. |
| Precisión | `value_number` se transporta como texto desde PostgreSQL; el JSON de observations se entrega como `value_json_text`. La fixture guarda `9007199254740993.125` y una celda `0.100000000000000001`; no se convierte a float en el probe. |
| Datos comerciales e identidad | El producto completo entra al fingerprint; la respuesta usa una lista explícita de identidad/binding/estado. No publica price/cost como contenido del snapshot. El delta de identidad se limita a brand/model/manufacturer_sku/gtin; no cambia nombre/SKU/categoría/precios. |
| Lecturas y fuentes | Observations contiene los registros de readings y sus fuentes/digest/quote. El preview no invoca el escritor de readings ni elimina evidencias. El futuro escritor deberá preservar esa propiedad mediante su propio contrato. |
| Ausencia de escritura | Las dos RPC se declaran STABLE y sus rutas leídas invocan lectores y validadores. El snapshot completo antes y después de todas las simulaciones BEFORE resultó idéntico. Esto no convierte en read-only a cualquier función sólo por su etiqueta. |
| Unknown y compatibilidad | Un dato requerido desconocido puede generar issue no bloqueante. `valid_draft` sólo significa que no hay issues bloqueantes; no significa ficha completa, evidencia suficiente ni compatibilidad confirmada. `mechanical_approval` y `apply_authorized` permanecen false. |

## Concurrencia y residuals de aplicación

PostgreSQL fija para las consultas internas de una función STABLE el snapshot de la sentencia que la llama. Eso sustenta que producto, editor, observaciones y fingerprints se lean sobre una sola vista MVCC; la etiqueta STABLE no basta si una ruta anidada ejecuta escrituras. Se inspeccionaron los consumidores concretos, además de su volatilidad. [PostgreSQL — Function Volatility Categories](https://www.postgresql.org/docs/current/xfunc-volatility.html).

La RPC de preview compara la preimagen dentro de su propia lectura. No reserva esa versión para una escritura futura. Un aplicador posterior necesita repetir el control de preimagen/revisión/contrato dentro de su frontera transaccional y de locks, conservar hechos legacy/opciones/readings y exigir recibos de evidencia y backup. El snapshot es una preimagen de investigación, no un backup restaurable por sí solo ni una capacidad de escritura.

`p_reference_id=null` conserva la referencia actual mediante `coalesce`; esta RPC no expresa el retiro explícito de una referencia. No se ha presentado como un comando de edición general. Las sustituciones escalares explícitas deben seguir identificadas como cambio de evidencia, y un fill no debe convertir silenciosamente una omisión en borrado.

No quedan escapes reproducidos abiertos en los seis cuerpos de esta revisión. El integrador conserva el gate de suite integrada, despliegue/read-back del mismo estado y registro de migración; sus pruebas integradas, lecturas productivas y runtime no se atribuyen a esta revisión. El saneamiento global, la evidencia por producto, el respaldo restaurable y el aplicador autenticado de hechos con preimagen/procedencia siguen siendo trabajo independiente. Todos los gates de llenado y aprobación mecánica continúan false.
