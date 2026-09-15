# Revisión independiente: límite legacy y relaciones por filas

Fecha: 2026-09-06. Revisor: subagente Codex `spec_boundary_review`.
Alcance: migraciones locales `20260906170000_product_spec_legacy_boundary.sql`
y `20260906180000_product_spec_scoped_relations.sql`, con `160000` como
dependencia; consumidores de escritura/lectura pertinentes, verificadores y
modelos Dart. La revisión inicial no modificó implementación. El integrador
amplió después el encargo exclusivamente para corregir E5 en `160000`, su
generador, su verificador y una nueva regresión SQL. Este revisor no escribió
en producción ni tocó el runtime. Las fixtures mutantes fueron sintéticas,
locales y con rollback; los reemplazos de funciones locales usaron guardias
MD5, sin replay completo de migraciones ni downgrade del writer de `170000`.

## Dictamen diferencial, 2026-09-06

**Sin bloqueos nuevos P1/P2 en el alcance revisado.** E1–E4 están corregidos en
las versiones identificadas abajo y sus reproducciones focales pasan. E5 se
reprodujo, corrigió por identidad de definición y verificó localmente. La
integración y el despliegue pertenecen a Codex raíz; este dictamen no sustituye
su read-back productivo ni los gates de consumidores, OEM y catálogo.

La coincidencia de fuentes, tipos y comparaciones es una propiedad del
contrato informático. No demuestra que una referencia describa un modelo
real correctamente ni que todas las familias estén listas para llenar.

## Dictamen inicial conservado

**Pendiente de correcciones y de nueva comprobación.** La separación de campos
retirados en los dos guardados principales funciona en las pruebas acotadas,
y la evaluación por filas conserva las combinaciones. Se encontraron dos
rutas de escritura fuera de ese límite y dos diferencias SQL/Dart. No hay
evidencia de que estos casos hayan dañado productos reales. Ninguna prueba
sintética certifica compatibilidad mecánica u OEM ni cobertura de familias.

Versiones de entrada leídas:

- `170000`: SHA-256 `b429cf331be162e4104fb0f2a229df706d661d85a76030feb510cf9d025d190a`.
- `180000`: SHA-256 `cbf6e7f0ddd282cb9cffd5bf327d6520ece3aae963fe9159ace9452c8d1a7656`.

El integrador está corrigiendo los hallazgos durante esta revisión. Esos SHA
identifican el dictamen inicial, no una aprobación de los archivos posteriores.

## E1 — P1: la lectura automática del nombre puede escribir campos retirados

**Hecho de producción leído, sin ejecutar una escritura:**
`record_product_spec_reading_v1(uuid,text,jsonb,text,text)` es SECURITY DEFINER,
ejecutable por `authenticated`; MD5 de `pg_get_functiondef`:
`8756b35a852f77e330715c587c2dc68f`. Selecciona una definición global/del tenant
filtrable y comprueba la cita, pero no resuelve la plantilla efectiva ni el rol
del campo. Por tanto, la nueva RLS restrictiva no limita este escritor.

**Consumidor real inspeccionado:**
`intelligent_purchasing_workspace_page.dart`, dentro de `_leerElCatalogo`, pasa
el recorder a `readCatalogNamesIntoFicha`; llama
`IntelligentPurchasingService.recordProductSpecReading`, que invoca esta RPC.
No es un método muerto. La definición viva se conservó, con su MD5, en
`.tmp/db/spec-reading-writer-before.json` a petición del integrador.

**Reproducción local:** fixture del límite legacy, producto sintético cuyo
nombre contiene `7.1 7.2`, `chain_outer_width_mm` filtrable marcado `legacy`.
Bajo `SET LOCAL ROLE authenticated`, ambas llamadas al escritor con `7.1` y
después `7.2` devolvieron `recorded`. El mismo hecho terminó con valor `7.2`,
fuente `name_reading` y rol `legacy`. `link_count` no reproduce esta ruta:
`is_filterable=false` hace que el escritor lo rechace antes.

La función local inicial es histórica y difiere del MD5 productivo. Se
reprodujo la omisión común a ambas definiciones; no se presenta esa ejecución
como prueba del SQL productivo exacto. El integrador recibió esa limitación y
está preparando la regresión contra la definición viva.

**Invariante y alcance:** cualquier producto del tenant accesible a la RPC;
campos retirados, fuera de plantilla o productos sin plantilla que aún tengan
una definición filtrable. Puede crear historia nueva que se supone retirada
o sustituir una observación `name_reading` conservada. No se encontró cruce de
tenant en esta ruta.

**Corrección propuesta:** adquirir la llave compartida de producto antes de
leer texto/identidad, bloquear la fila del producto, resolver la plantilla
efectiva y exigir que el campo siga activo antes de validar o persistir la
lectura. Rechazar con el sobre normal `rejected`; conservar el escritor activo
y sus recibos de evidencia. Incluir la definición viva en drift guard y verify.

**Caducidad por identidad revisada:** la invalidación encontrada es de lectura:
`assistant_inventory_technical_predicate_source_internal_v1` compara el digest
del texto/vocabulario y devuelve `unresolved`. No borra hechos ni recibos. La
consulta de triggers productivos de `products` relacionados con fichas sólo
encontró revisión y validación; no un borrado por cambio de nombre. La
desaparición física por identidad no se ha reproducido.

## E2 — P2: una eliminación de `bike` puede borrar la proyección de producto

**Hecho productivo leído:**
`mirror_facts_into_product_specs_internal_v1()` tiene MD5
`4fd0207f766333c03381407fabeb15f7`, coincidente con la definición del archivo
existente `.tmp/db/spec-projection-triggers.json`. La rama de DELETE sobre
`spec_facts` borra de `product_spec_values` antes de comprobar el tipo y el
alcance del sujeto.

**Reproducción local:** con dos filas de proyección de un producto sintético,
un usuario `authenticated` inserta un hecho `bike` usando el mismo UUID como
`subject_id`, para la misma definición, y luego lo borra. La operación está
permitida por la política de bicicletas. La proyección baja de **2 a 1**;
los hechos canónicos `product` permanecen en **2**. No se borró el hecho
canónico en esta reproducción. Es una vía indirecta para eludir la nueva
prohibición de escritura directa de la proyección, dentro del propio tenant.

**Causa y corrección:** el espejo aplica la ruta de borrado sin exigir primero
`OLD.subject_type='product' AND OLD.subject_scope IS NULL`. Aplicar esa
condición antes de tocar la proyección. No restringir todos los sujetos de
`spec_facts`, porque bicicletas y visitas conservan sus flujos propios.

**Regresión reproducible:**
`.tmp/product-spec-catalog/spec-boundary-review-mirror-job.sql` contiene la
fixture con rollback y una expectativa de conservar ambas filas. Contiene
además INSERT/UPDATE/DELETE de opciones `job_bike`. Las tres operaciones de
opciones se ejecutaron correctamente con las nuevas políticas; los cambios
escalares `bike` también pasaron en la suite principal.

## E3 — P2: SQL acepta fuentes de relación que Dart rechaza

**Reproducido en ambos ejecutores reales:** `https://example.invalid:bad` y
`https://[bad]` pasan el patrón SQL de fuente absoluta y la relación resulta
`supported`. `ProductSpecRelation.fromJson` las rechaza con FormatException
mediante `Uri.tryParse`. La URL de control normal pasa en ambos.

**Alcance:** una futura referencia v2 con una de estas fuentes puede pasar el
trigger del servidor si la URL también pertenece a `reference.sources`, pero
fallar en `productSpecClaimSummary` al construir la presentación en Dart.
No existen fuentes OEM afectadas demostradas por este ensayo.

**Corrección:** definir y validar el mismo perfil de URL de fuentes en ambos
extremos, con host y puerto válidos. No relajar Dart para aceptar URLs rotas.
Probar el INSERT de referencia y la decodificación/presentación del mismo
documento, además del validador aislado.

## E4 — P2: el redondeo numérico puede producir una aprobación sólo en Dart

**Reproducido:** para `x >= "1.0000000000000001"` con `x=1`, Dart devuelve
`supported` y SQL `outside_declared_scope`. Lo mismo ocurre con `eq`. Para
igualdad entre el esperado `"100000000000000000000"` y el valor
`"9223372036854775807"`, Dart devuelve `supported` y SQL queda fuera del rango
declarado. Los controles de enteros `9007199254740993/9007199254740992` no
produjeron una discrepancia en los dos operadores ejecutados.

**Causa:** `normalizeSpecRuleValue` pasa por `num`/`double`, y convierte ciertos
valores integrales con `toInt`; SQL conserva `numeric`. El comparador relacional
nuevo reutiliza ese normalizador. La representación compartida no puede
prometer exactitud de todo decimal finito con esos dos comportamientos.

**Alcance:** declaraciones futuras con límites o identificadores numéricos
fuera de la exactitud compartida. La reproducción no demuestra que un dato
mecánico del catálogo actual use esa precisión o magnitud. Es una diferencia
real de contrato y puede producir un falso positivo, aunque los casos físicos
habituales de la fixture pasen.

**Corrección:** comparar decimales canónicos sin redondeo o definir un dominio
compartido que rechace/deje desconocidos los valores no representables. Nunca
redondear para conceder soporte. Mantener separados los identificadores
textuales y las medidas cuando el contrato de campos los distingue.

**Reproducciones E3/E4:**

```sh
fvm dart .tmp/product-spec-catalog/spec-boundary-review-probe.dart
scripts/db/query.sh local --file .tmp/product-spec-catalog/spec-boundary-review-relations.sql
```

Estos archivos usan exclusivamente valores sintéticos `example.invalid`.

## E5 — P1: los lectores confundían IDs globales y privados con la misma key

**Hecho de esquema comprobado:** `spec_definitions.key` es único dentro del
espacio global y dentro de cada tenant, pero no entre ambos. Una definición
privada ajena a la plantilla podía compartir `chain_outer_width_mm` con la
activa global. Las proyecciones reducían primero IDs a keys y filtraban después;
el valor privado podía rellenar el campo global o satisfacer sus criterios.

**Reproducción:** fixture tenant/global independiente, sin datos de productos
reales. Antes del parche fallaron las cinco expectativas de excluir el valor
privado en valores activos, contexto, snapshot, predicado tipado y filtro
legacy. El diagnóstico está en
`.tmp/product-spec-catalog/spec-boundary-review-shadowing-before.sql` y
`.tmp/db/spec-boundary-review-shadowing-before.log`. Un writer que resolviera
sólo por key podía elegir el mismo ID privado; E1 ahora usa el resolver por ID.

**Corrección implementada por encargo expreso del integrador:**

- `spec_product_field_definition_internal_v1` devuelve el único ID activo de
  esa key dentro de la plantilla efectiva y del tenant; una ambigüedad da NULL.
- `spec_product_definition_is_active_internal_v1` aplica ese límite cuando el
  lector ya tiene el ID. Inferencia, rangos, cobertura, búsqueda v7 y candidatos
  de stock conservan el ID hasta comprobar la plantilla y el sujeto product
  con alcance NULL.
- `spec_template_product_payload_internal_v1` filtra el payload normalizado
  antes de convertirlo a keys. Snapshot, editor con categoría de borrador,
  contextos y storefront reciben la proyección correcta. Una plantilla con dos
  IDs visibles para la misma key falla con `23514`: no produce un draft vacío
  cuya omisión pudiera borrar hechos después.
- La historia no asignada renderiza cada valor desde su singleton por ID, y
  `catalog_keys` sólo atribuye fuente automática a IDs de la plantilla.
  La validación del valor requerido por referencia también compara el ID.

**Alcance:** lectores de fichas de productos y sus consumidores de búsqueda,
criterios, tienda y compras. No se alteraron esquemas de bicicleta/visita ni
hechos de catálogo. Los helpers son privados; los puntos públicos conservan
sus verificaciones de actor y tenant.

**Verificación local:** `supabase/tests/product_spec_template_identity.sql`
pasa **18/18**, incluyendo la lectura autenticada que guarda 7.1 en el ID
global mientras preserva 7.2, fuente y presentación del ID privado; el
storefront muestra 7.1 y el snapshot rechaza metadatos ambiguos. La suite
existente de binding pasa **73/73**. Esto es una regresión sintética de IDs,
no evidencia de un ancho válido para una cadena OEM.

**Integración reproducible:** se cambiaron 15 funciones locales mediante
`.tmp/db/spec-boundary-review-binding-apply.sql` y el ajuste posterior de un
único helper en `.tmp/db/spec-boundary-review-payload-apply.sql`, cada uno con
predecesores MD5 exactos. No se ejecutó el writer antiguo de `160000`.
`.tmp/db/spec-boundary-review-binding-after.json` guarda las definiciones finales.
El generador se reejecutó sin alterar el SHA resultante. Se conservaron los
28 pins `before` originales y se añadieron tres helpers nuevos; el verify de
`160000` ahora contiene 31 funciones. Los 15 MD5 afectados y las ACL privadas
pasan en `.tmp/db/spec-boundary-review-binding-targeted-verify.log`.
El verify integral de la etapa `160000` no se usa contra un local ya situado
en `170000`, que legítimamente tiene otro cuerpo de `save_product_spec_facts_v1`.

## Lo comprobado sin hallazgos en el ámbito acotado

- **23/23 pgTAP legacy:** omisión y round trip sin cambios preservan hechos,
  opciones, posiciones, procedencia y recibos; cambios de campos retirados se
  rechazan; el valor booleano `false` persiste. Bloqueo real de DML de producto
  bajo `authenticated`, no sólo inspección textual de políticas.
- **43/43 pgTAP de relaciones:** alternativas OR, condiciones AND por fila,
  no préstamo entre BSD/anchos ni extremos de dirección, configuración plural
  desconocida, exclusión explícita y desconocida, fuentes adjuntas a la
  referencia y rechazo de versión no soportada.
- **45/45 pruebas Dart focales:** `product_spec_relation_test.dart` y
  `product_spec_contract_test.dart`. La paridad de los 17 casos compartidos se
  verifica, pero no cubre E3/E4.
- `BulkProductEditService.loadSpecSearchIndex` tiene un consumidor real en
  `bulk_product_edit_dialog.dart`; el cambio actual usa contextos efectivos y
  omite metadatos `__`. La búsqueda de la utilidad eliminada
  `clearProductSpecValues` no encontró llamadas en `lib`.
- Las funciones relacionales son privadas; el resultado describe una interfaz,
  no la bicicleta completa. `outside_declared_scope` no se convierte en una
  afirmación de imposibilidad mecánica. Las exclusiones desconocidas impiden
  aprobar una alternativa positiva.

## Comprobación diferencial final

- **E1 cerrado en el candidato:** el recorder usa la misma llave de producto
  que el guardado, adquiere `FOR UPDATE` antes de leer el texto, exige actor y
  definición activa por ID, y valida el producto antes de devolver `recorded`.
  La suite nueva comprueba rechazo de campo retirado/contradicción y
  conservación de la lectura. La caducidad de lectura por digest sigue sin
  borrar datos.
- **E2 cerrado en el candidato:** el mirror comprueba `OLD.subject_type` y
  `OLD.subject_scope` antes del DELETE de proyección. La reproducción original
  pasa **5/5**, incluyendo actualización y eliminación de opciones `job_bike`.
- **E3/E4 cerrados para el contrato v2 revisado:** la misma gramática HTTP(S)
  valida las fuentes en SQL y Dart. Cada condición declara `value_type`
  decimal/token/boolean; las magnitudes se transportan como texto decimal y
  se comparan exactamente. Un JSON number observado queda desconocido;
  una declaración con ese operando se rechaza. Los tokens `01` y `1` siguen
  distintos y `false` no se confunde con el texto `false`.
- **Reejecución independiente:** **31/31** pgTAP legacy, **86/86** relaciones,
  **73/73** Dart en los dos archivos relation/contract, además de los **18/18**
  nuevos y **73/73** binding indicados en E5. Son pasadas focales distintas;
  no se suman a las iniciales para aparentar cobertura adicional. Los
  verificadores exactos de `170000` y `180000` también pasan localmente.

Evidencia de esta reejecución:

- `.tmp/db/spec-boundary-review-legacy-after.log`
- `.tmp/db/spec-boundary-review-relations-after.log`
- `.tmp/db/spec-boundary-review-mirror-job-after.log`
- `.tmp/db/spec-boundary-review-template-identity.log`
- `.tmp/db/spec-boundary-review-binding-tests.log`
- `.tmp/db/spec-boundary-review-final-verify.log`
- `.tmp/product-spec-catalog/spec-boundary-review-dart-after.log`

## Transporte autenticado de preparación

`scripts/inventory/product_spec_session.py` obtiene la sesión del contenedor
Debug explícito, comprueba coincidencia de linked/config/issuer y caducidad,
y confirma el actor mediante `/auth/v1/user`. No confía en la decodificación
local del JWT como autenticación. No renueva sesión ni usa login/refresh.
`read()` y CLI aceptan exclusivamente seis RPCs de lectura; los errores HTTP
omiten cuerpos/headers y las redirecciones se rechazan antes de reenviar
Authorization. El archivo de salida se crea con modo `0600` y `O_EXCL`.

**6/6 pruebas Python ejecutadas** desde
`python3 test/scripts/test_product_spec_session.py`; registro en
`.tmp/product-spec-catalog/spec-boundary-review-session-tests.log`. Se usaron
mocks con credenciales sintéticas; este revisor no abrió el plist real ni
repitió la lectura HTTP del integrador. El comando `python3 -m unittest
 test/scripts/test_product_spec_session.py` no sirve en este checkout porque
resuelve otro paquete `test`; no es un fallo del transporte.

**Observaciones acotadas, no bloqueos del CLI actual:** `_request()` sigue
siendo un método privado genérico que puede construir POST fuera de la
allowlist si un futuro importador lo llama directamente. Conviene llevar la
frontera a ese método antes de reutilizarlo como transporte compartido. La
identidad validada es proyecto/actor; no acredita el tenant del backup. El
futuro aplicador debe exigir esa correspondencia y mantener su gate propio.
No se observó una vía del CLI hacia una RPC de escritura ni fuga de token
en los casos probados.

## Versiones del dictamen diferencial

Los SHA-256 finales están en `.tmp/db/spec-boundary-review-final-sha256.json`:

- `20260906160000_product_spec_template_binding.sql`: `bf46ca8592500abdbcb6435740a3657653ec97450fdc9364c9d193f2cf179694`.
- `20260906170000_product_spec_legacy_boundary.sql`: `7aac4171546c39ba5ff66c3c3add3776bb67a52b4b7d0ef5e1e2567f44d3b53b`.
- `20260906180000_product_spec_scoped_relations.sql`: `8fcecbf5f43f1f99bcfe25f9a6c9c02dd5d1ce8e3cfc820a4f6070e77076b54f`.
- `product-template-binding-verify.sql`: `11893d8d58781152496474d685b9e150c03e41467a315742a5fae6a8277bbc66`.
- `product-spec-legacy-boundary-verify.sql`: `c2f1889d22b6968140691dc63ab8619b80411d64e9062c255f136da6be709640`.
- `product-spec-scoped-relations-verify.sql`: `2b5757b5bf7196cb9df2a556407bde6e3245648a2df3c3f91b4294cd322440d9`.
- `product_spec_session.py`: `7d9c42e848169925062af4b81cbbaf962909ef23c0146f04e5bf80abb1e08984`.

## Gates residuales

1. Read-back productivo exacto y permisos/objetos efectivos tras cada etapa
   desplegada por el integrador. El resultado local de este revisor no
   sustituye su receipt y registro de migración.
2. Guardado real y presentación del editor en la sesión canónica, conservando
   el borrador existente. Este revisor no tocó esa sesión.
3. Proyección SQL a configuración relacional con decimales como texto y
   conexión efectiva con los consumidores que afirman compatibilidad. V2 es
   infraestructura; todavía no demuestra uso de sus resultados en todos los
   recorridos del producto.
4. Evidencia OEM por familia/modelo, asignación de plantillas y saneamiento
   global antes del llenado. Las pruebas sintéticas no completan ese gate del
   catálogo ni acreditan los 37 diseños como fichas mecánicamente correctas.

## Revisión adicional 190000: configuraciones por filas

Revisión independiente del borrador `20260906190000_product_spec_structured_rows.sql`,
`product_spec_rows.dart`, su uso en validación de referencias y los consumidores
de guardado/lectura existentes. El integrador conservó la propiedad del SQL,
Dart y UI; este revisor sólo creó probes `.tmp` y ejecutó transacciones locales
con rollback. No hubo escrituras productivas ni interacción con el runtime.

### Hallazgos reproducidos y correcciones revisadas

| Id | Severidad y alcance | Reproducción | Corrección del integrador leída |
|---|---|---|---|
| R1 | P1. Semántica de referencias publicadas que aún no tienen hechos de productos/bicis. | Una referencia inmutable contenía longitud `10` con unidad `mm`. Cambiar únicamente `rows_schema.columns[0].unit` a `in` pasó porque el guard sólo consultaba `spec_facts`; el lector devolvió `Length: 10 in`. | El guard ahora consulta también `product_spec_references.fact_values ? OLD.id::text` antes de permitir cambiar esquema o tipo. La referencia y los hechos toman `FOR SHARE` sobre la definición al validar. |
| R2 | P2. Comparación cliente de filas con una referencia. SQL rechazaba la contradicción, pero UI podía bloquear valores válidos o indicar que coincidían datos distintos. | `evaluateSpecCondition` comparaba mapas por `toString()`: el mismo JSON con otro orden de claves dio `no`; una sola celda `{a: "x, b: y"}` colisionó con dos celdas `{a: "x", b: "y"}` y dio `yes`. JSONB produjo respectivamente `true` y `false`. | `validateProductSpecDraft` detecta el esquema, valida/canonicaliza ambos valores y usa `DeepCollectionEquality`; conserva la comparación previa para campos no estructurados. |
| R3 | P3. Paridad de entradas fuera de contrato, sin aprobación incorrecta persistida. | Dart aceptaba `ordered_pairs: null`, `validation.positive: null` y el cero `0e-9999999999999999`; PostgreSQL rechazaba estas entradas. | Se revisó la distinción entre ausencia y `null` que añadió el integrador. Se entregaron 20 casos de límites de exponente/escala; la integración del límite numérico seguía en curso al cerrar este bloque. |
| R4 | P2. Conservación del esquema al borrar metadata referenciada. | `DELETE spec_definitions` pasó para una definición de filas usada por una referencia: `fact_values` permaneció, pero faltó su definición y el lector devolvió `facts: {}`. | Trigger ampliado a `BEFORE DELETE`; bloquea el borrado si la definición de filas tiene hechos o referencias y conserva la posibilidad de borrar una definición vacía. |

La revisión del delta también confirmó el rechazo añadido de una referencia
con `rows` y un escalar simultáneos, y de fuentes de filas que no pertenecen
a `reference.sources`. Estos dos últimos guards fueron inspeccionados en código;
el integrador lleva sus regresiones. El noveno reemplazo,
`spec_unassigned_facts_internal_v1`, sólo añade `rows_schema` al sobre histórico
existente: conserva selección por definición, tenant, sujeto y scope.

### Pruebas adicionales de este revisor

**12 pgTAP pasan** en `.tmp/db/spec-boundary-review-rows-rls.sql/.log`, bajo
`SET LOCAL ROLE authenticated` cuando corresponde:

- Inserción y actualización de filas en `bike` y `job_bike` a través del
  validador privado; decimal `9007199254740993.2` y booleano `false` conservados.
- Rechazo de JSON numérico en celdas decimales y del intento de mover filas
  a `value_text` desde la ruta directa de bicis/trabajos.
- Otro tenant no puede leer, reemplazar ni insertar hechos del primero.
- Borrar ambos hechos no producto no altera la proyección del producto
  que comparte el mismo UUID de sujeto.

Las filas incompletas y sus fuentes vacías en una observación son decisiones
explícitas del contrato, no evidencia negativa. El cliente devuelve una falta
de completitud no bloqueante; ninguna de estas pruebas afirma compatibilidad
física ni cobertura OEM.

### Evidencia exacta y gates

- `.tmp/db/spec-boundary-review-rows-probe.sql/.log`: R1 y comparación JSONB.
- `.tmp/product-spec-catalog/spec-boundary-review-rows-probe.dart/.log`: R2 y
  casos de paridad. El probe directo del evaluador documenta su comportamiento
  previo; el arreglo está en el consumidor de referencias, no en ese helper.
- `.tmp/db/spec-boundary-review-rows-parity.sql/.log`: `null` y representación
  decimal, con errores explícitos, todo en rollback.
- `.tmp/db/spec-boundary-review-rows-zero-exponents.sql/.log`: PostgreSQL 17.6
  acepta `0e1073741823` y rechaza `0e1073741824`; admite escala de entrada
  16383 y rechaza 16384, incluso si la mantisa sólo tiene ceros. Por eso
  `0e-16383` pasa y `0.0e-16383` no. Los ceros finales de la mantisa no pueden
  quitarse antes de evaluar el límite de entrada.
- `.tmp/db/spec-boundary-review-rows-delete.sql/.log`: R4 antes del guard.
- `.tmp/db/spec-boundary-review-rows-state.sql/.log`: RLS, triggers y lector
  automático real. La lectura de nombres rechaza tipos JSON no verificables;
  no puede convertirse en vía alternativa para escribir filas.

Los cambios R1/R2/R4 leídos resuelven las causas reproducidas. Este bloque no
certifica su despliegue: quedan las suites que el integrador ejecuta tras su
última edición, los pins/postimages y read-back productivo de 190000, y la
verificación UI de referencias/legacy/unassigned. Las pruebas de 190000 y
sus observaciones numéricas no acreditan el saneamiento de todas las familias.
