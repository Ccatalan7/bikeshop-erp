# Revisión independiente del transporte numérico de fichas

Fecha: 2026-09-07. Revisor: Codex, subtrabajo `spec_boundary_review`.

Alcance: números escalares en carga, borrador, validación, serialización y lectura de retorno. Revisión local de código y pruebas independientes; sin producción, runtime, Claude ni cambios de implementación. Las medidas de las pruebas son sintéticas y no son evidencia OEM. El integrador implementa las correcciones en paralelo.

**Resultado actual: 62/62 pruebas independientes pasan; analizador del archivo sin incidencias.** Los fallos NT01–NT10 de este límite están corregidos en el código revisado, con los matices de evidencia descritos abajo. No quedan bloqueos de implementación identificados en este dictamen acotado. La demostración del formulario real corresponde al integrador y sigue fuera de esta revisión; tampoco se aprueban familias completas ni llenado por pasar estas pruebas.

## Evidencia y continuidad

Se leyó el checkpoint [global-audit-and-sanitation-2026-09-06.md](global-audit-and-sanitation-2026-09-06.md): 190 y 200 aplicadas; transporte exacto para relaciones disponible; editor escalar antiguo explícitamente pendiente. Ese checkpoint registra despliegue y lecturas de producción realizados por el integrador, no por esta revisión. No se repitió ningún despliegue ni replay.

Preimagen de los archivos al ejecutar la primera regresión, SHA-256:

| Archivo | SHA-256 |
| --- | --- |
| `product_form_page.dart` | `d4d2ffbd76e497c79c91fd81f700d60aa661f981f07d0ef99df5dd6e061b86fb` |
| `spec_engine_service.dart` | `02207fbd391001ee88d928b328cfb8ab8b6ce94f4d1f218fb4476aa4fdbf2bb0` |
| `product_spec_contract.dart` | `a679ae521df3e817d475eeb11529e89c2e22b0d99b736e045d19f81b4e2381bc` |
| `spec_rule_evaluator.dart` | `8cd05f527dc9ecb455d487ad4a4468a2e87de85fccf1dc5d49b2d9057f0471bd` |

Regresión ejecutable: [product_spec_numeric_transport_boundary_test.dart](/Users/Claudio/Dev/bikeshop-erp/test/unit/product_spec_numeric_transport_boundary_test.dart).

```sh
fvm flutter test test/unit/product_spec_numeric_transport_boundary_test.dart --reporter expanded
```

Resultado inicial: **22 casos; 6 pasan, 16 fallan**, salida 1. Las pruebas invocan `validateProductSpecDraft` y `SpecEngineService.buildFactPayload`, y atraviesan `jsonEncode`/`jsonDecode`. No sustituyen esas funciones con copias. Los seis casos verdes prueban entradas inválidas/incompletas conservadas en el mapa y rechazadas antes de serializar. Los 16 rojos reproducen los problemas de transporte/rango y el contrato acordado de cadenas decimales. Esta ejecución fue Dart VM; no demuestra el comportamiento real de un navegador ni de la ficha montada.

## Camino observado en la preimagen

1. `getProductEditorContext` llama `get_product_spec_editor_context_v1`, después `_loadTemplate` lee `spec_definitions` por PostgREST. `getReferences` llama `get_product_spec_references_v1`.
2. En SQL, `spec_product_payload_internal_v1` construye `number` desde `spec_facts.value_number`; `spec_payload_display_internal_v1` conserva ese JSON number. El editor v1 y las referencias v1 usan esa proyección. PostgreSQL todavía conserva su precisión en este punto; el riesgo aparece al decodificar JSON number en un cliente de precisión limitada.
3. `_loadSpecs` copia `snapshot.values` al borrador por las claves activas. No vuelve a leer el dato exacto desde el RPC tipado. La referencia puede incorporar su propio valor al borrador.
4. El control escalar aplica el filtro `[0-9.,]`. `_parsedSpecNumberValue` pasa por `num.tryParse`, `toInt` y `toDouble` antes de `_updateSpecValue`; `_specNumericValue` y `_formattedSpecNumericValue` repiten la representación binaria para validar, comparar y rotular.
5. `validateProductSpecDraft` vuelve a usar `num.tryParse`, comparaciones de `num`, `% 1` y casts de `min/max` a `num?`.
6. `_specSaveCommand` usa `buildFactPayload`; su rama `number` emite JSON number. El escritor SQL v2 de 190 admite `number` como JSON number o string decimal válida y almacena `numeric` sin necesidad de `double`. El servidor puede preservar la cadena, pero no recuperar dígitos que el cliente ya cambió.
7. `get_product_spec_typed_configurations_v1` convierte la magnitud a `numeric::text` dentro de SQL, conserva ID/tipo/plantilla/revisión y no escoge miembros de conjuntos. Esto resuelve su propia lectura. `rg` sobre `lib`, `test` y `scripts/inventory` no encontró adopción por el editor Dart en esta preimagen; sí está permitido por el transporte Python de lectura. No se presenta un RPC disponible como integración ya hecha.

## Hallazgos reproducidos y límites

| ID | Severidad / alcance | Reproducción o evidencia | Corrección mínima |
| --- | --- | --- | --- |
| NT01 | P1, valores escalares que atraviesan el editor/escritor Dart | `buildFactPayload`: `0.12345678901234567890123456789` → `0.12345678901234568`; `9007199254740993.125` → `9007199254740994.0`; `1e-400` → `0.0`. Reproducido incluso en VM. El entero `9007199254740993` se conserva en la VM probada, pero viaja como JSON number: no afirmar que esta prueba reproduce también la pérdida en JS. | Mantener texto del borrador, validar decimal exacto y emitir string canónica. Rechazar `num` heredado fuera del rango común seguro en vez de presentarlo como precisión recuperada. |
| NT02 | P1, integridad de dominio de campos | `integer:true` permite `1.00000000000000001`; `max:0.1` permite `0.100000000000000001`. `positive:true` rechaza `1e-400` al reducirlo a cero. Reproducido. El servidor recibe el valor ya alterado, por lo que validarlo luego no repara la observación original. | Reutilizar comparación decimal exacta también para min/max/positive/integer; no convertir a entero binario para comprobar integralidad. |
| NT03 | P1 para entrada con signo; P2 para edición parcial, control escalar | Inspección de `TextFormField`: el filtro sólo permite dígitos, coma y punto. El signo y `e/E` quedan fuera del alfabeto de entrada aunque la validación acepte sus expresiones. Esta revisión no montó el widget ni ejecutó una interacción real: se registra como defecto de fuente, no como frame verificado. | Permitir el texto sin mutilarlo; conservar `-`, `1e-` y otros estados parciales en el borrador y mostrar error al validar/guardar. Un texto inválido no debe convertirse silenciosamente en otro número válido. |
| NT04 | P1 condicionado a valores de alta precisión almacenados; editor/referencia v1 | Inspección trazada de RPC y cliente: la lectura tipada es exacta, la usada por el editor v1 conserva JSON number y el cliente no adopta la lectura tipada. No se buscó un producto real con ese valor ni se leyó producción. | RPC editor/referencia v2 con conversión dentro de PG antes de JSON; cliente nuevo debe seleccionar v2 sin fallback silencioso a v1. Mantener lectores v1 estables para sus consumidores existentes. |
| NT05 | P2, paridad con límites de representación PostgreSQL | `0e-16384` y `0e1073741824` se consideran válidos por el validador Dart anterior. `1e309`, válido para el parser decimal PG ya existente en el repositorio, se rechaza porque no cabe en `double`. Reproducido en Dart; los límites PG proceden del parser compartido y de las probes locales de la revisión de 190, no de una nueva consulta SQL en esta ronda. | Compartir parser exacto y sus límites, incluso para cero, antes de guardar. Estos son límites de transporte, no tolerancias físicas. |
| NT06 | P2, metadata de límites | Un `min` textual exacto lanza `type 'String' is not a subtype of type 'num?'`. `_loadTemplate` recibe `validation_rules` directamente de PostgREST: convertir sólo las respuestas de productos a texto no protege un `min/max` JSON number inseguro. El crash con texto está reproducido; el redondeo real de metadata en JS queda pendiente. | Admitir límites textuales exactos. Un límite presente que no se pueda representar/interpretar debe fallar cerrado, no convertirse en ausencia de límite. Proyectar metadata exacta antes de JSON o cerrar su dominio de transporte. |
| NT07 | P2 latente, escritor Dart antiguo sin llamadas encontradas | `saveProductSpecValues` usa otro parser: `num.tryParse` sin coma local y `continue` cuando falla. La omisión viaja con el ID del campo en un comando de sustitución y podría retirar un dato activo. `rg` de `lib`, `test`, `scripts/inventory` sólo encontró su definición, no un consumidor actual. No se ejecutó ese escritor ni una escritura SQL. | Retirar explícitamente este camino de los nuevos flujos, o hacer que falle antes de enviar. Nunca degradar la cadena exacta a JSON number para satisfacer el RPC viejo. |

El escritor SQL de 190 admite texto decimal y verifica el valor antes del cast. La validación SQL de 200 compara `numeric`, pero no sustituye el límite de cliente: si el cliente transmite `0` en lugar de `1e-400`, SQL valida el dato que llegó. Esto distingue corrección del almacenamiento de fidelidad de la captura.

## Contrato acordado con el integrador y revisión diferencial pendiente

API anunciada por el integrador en `models/product_spec_number.dart`:

- `productSpecNumber(Object?) → SpecRuleDecimal?`.
- `productSpecNumberWireValue(Object?) → String` canónica o `FormatException`.
- `productSpecNumberErrorCode(Object?, Map<String,dynamic>) → null/type/min/max/positive/integer`.
- Texto con coma decimal local y espacios exteriores; estados inválidos/incompletos permanecen como texto y bloquean guardar.
- `num` heredado sólo finito y de magnitud como máximo `9007199254740991`. Aceptar un `num` dentro de ese rango expresa su valor decimal recibido; no certifica los dígitos que existían antes de una eventual conversión anterior.
- Nuevos RPC `editor_context_v2` y `references_v2` convierten magnitudes dentro de PostgreSQL; v1 permanece estable.

Pendiente al primer registro: revisar implementación nueva, ampliar regresiones a las APIs públicas anunciadas, probar selección del RPC con transporte HTTP simulado y cerrar metadata insegura. No se ha observado aún una recarga ni un guardado real de la UI. El cierre de compatibilidad de todas las familias y el llenado de productos quedan fuera de esta prueba de números.

### Primer contraste diferencial

El integrador incorporó el helper exacto a `validateProductSpecDraft` y `buildFactPayload`, preservó texto crudo en `_parsedSpecNumberValue` y retiró el filtro de caracteres del número y el escritor Dart antiguo sin consumidores encontrados. Se inspeccionaron esos cambios sin editarlos. Los **22 casos iniciales pasan** con el código nuevo. El envío canónico conserva los dígitos probados, los dominios usan comparación exacta y se rechazan magnitudes `num` heredadas fuera de la frontera segura.

La suite ampliada a ese punto obtuvo **29 pasan / 1 falla**. El caso rojo era `min:null`, agregado por el revisor al interpretar «límite presente no interpretable». El seguimiento de SQL200 confirma que `null` significa «lado sin límite»; se corrigió esa expectativa de prueba para conservar la paridad existente. No se cuenta como defecto de implementación ni como un guard omitido; min/max no nulos ilegibles ya fallan cerrado y ambas capas Dart los rechazan.

Una hipótesis adicional de coma/espacios en prerrequisitos quedó **descartada por ejecución y seguimiento completo de llamadas**: los cuatro casos del grupo `raw local decimal input` pasan sin cambio en `product_spec_template_rules.dart`. El evaluador de relaciones usa `specRuleNumber` para la observación textual, que ya normaliza coma y espacios. La gramática estricta que valida las constantes de la condición no era el parser de esa observación. Se conservan los cuatro casos como regresiones de coherencia, no como evidencia de un arreglo que no ocurrió.

### NT08 — desbordamiento al restar la escala del exponente

**P2; parser compartido de escalares, condiciones, relaciones y filas. Reproducido.**

```sh
fvm flutter test --no-pub test/unit/product_spec_numeric_transport_boundary_test.dart --reporter expanded --name 'very negative exponent'
```

Resultado rojo: `productSpecNumber('0.0e-9223372036854775808')` devuelve `SpecRuleDecimal` en lugar de `null`. En VM, `rawExponent` cabe justo en el entero mínimo y restarle un dígito de escala desborda antes de evaluar `exponent < -16383`. El camino de cero acepta el decimal inválido después del desbordamiento. La prueba no llama `canonical` sobre un resultado indebidamente aceptado para no intentar materializar una representación extrema. Incluye además casos de mantisa no nula y distinto número de dígitos fraccionarios; el primer fallo corta ese bucle en esta ejecución inicial.

Corrección propuesta al integrador: rechazar `rawExponent < -16383` **antes** de restar el tamaño fraccionario. Una mantisa sólo puede bajar ese exponente, por lo que el guard no elimina entradas que PostgreSQL acepte. Conservar el guard de escala final, puesto que `0.0e-16383` también debe rechazarse aunque su exponente inicial sí esté dentro del rango. Pendiente repetir el caso después del arreglo y registrar la lectura nueva v2.

## Estado previo al lector v2 — histórico

Última ejecución íntegra del archivo independiente: **35 casos; 34 pasan y 1 falla** (`very negative exponent`, NT08), salida 1. Los seis casos de texto incompleto/incorrecto ahora atraviesan también `isMeaningfulProductSpecValue`, `pruneStaleAutoDerivedProductSpecValues` y `omitAutoDerivedProductSpecValues`, los helpers reales del borrador; conservan el texto y bloquean el payload.

SHA-256 de la regresión: `ad30c905ddafb9908db80433291743676da662ecda596b4e8ea117a142ab1ee9`.
SHA-256 del parser aún sin el guard bajo: `8cd05f527dc9ecb455d487ad4a4468a2e87de85fccf1dc5d49b2d9057f0471bd`.
SHA-256 del helper nuevo revisado: `6aa10694f95458cdf90dba786f5cb1a0781c4d0d29322fbedbeb78dc271112e9`.

Gates residuales concretos:

- Corregir NT08 en el parser compartido y repetir este archivo. Los demás 34 casos verdes no cubren ese fallo.
- Terminar y revisar `decodeProductSpecEditorContext`, la selección de RPC v2, snapshot/plantilla/versión coherentes y min/max exactos. En la última lectura de `spec_engine_service.dart` esas APIs nuevas todavía no existían. El integrador anunció una sola respuesta atómica que incluye plantilla y snapshot; no se aprueba por el anuncio.
- Comprobar escritura→lectura SQL mediante las nuevas APIs y el flujo real del formulario, incluidos signos, estados parciales y recuperación de borrador. Esta revisión no accedió a producción, no lanzó la app y no simuló un guardado SQL. Los tests JSON VM no constituyen read-back del servidor ni prueba de Dart web.
- Mantener los gates globales de familia y llenado independientes del cierre numérico. No se llenó ningún producto en esta revisión.

## Lector v2 — revisión diferencial posterior

NT08 está corregido: el parser rechaza el exponente inferior a `-16383` antes de restar la escala. La regresión independiente ya ejecuta y rechaza los tres casos extremos, incluido el de mantisa no nula. Conserva los casos representables en los bordes positivo y negativo.

Se probó `SpecEngineService.decodeProductSpecEditorContext` con el shape emitido por el nuevo SQL: encabezados, plantilla, usos de campo, definiciones y las listas de reglas explícitas. La fixture atraviesa JSON, decodificador, borrador, validación y payload. Conserva `9007199254740993.125`, su mínimo `9007199254740993.12`, máximo `9007199254740993.13` y valor inicial textual; no convierte el token `01` ni el booleano `false`. El valor `9007199254740993.131` puede leerse exactamente y después queda bloqueado por su máximo: lectura correcta no equivale a validación de dominio aprobada.

Hallazgos del lector y estado:

| ID | Evidencia y alcance | Resolución |
| --- | --- | --- |
| NT09 | P2 defensivo. Reproducidos en VM: `read_schema_version:2.0` se aceptaba por igualdad con `2`; `snapshot.contract_version:7.0` se aceptaba frente al entero `7` de la plantilla. El SQL nuevo ya emite enteros: no se afirmó una pérdida productiva por estos casos. | Guard de tipo entero en ambos encabezados, además de igualdad y dominio de revisión. Ambas regresiones pasan. |
| NT10 | P2, pérdida de reglas. Reproducido: `validation_rules:'invalid-rules'` era convertido en `{}` por el constructor heredado y se aceptaba la lectura sin límites. El decoder v2 también tenía defaults de `data_type` ausente → `text` y `form_contract` ausente → `{}`, identificados por lectura; sus nuevas regresiones se ejecutaron después del arreglo, no se presentan como un rojo previo reproducido. | El decoder exige los metadatos antes de llamar `fromJson`. Las cinco regresiones pasan. El constructor usado por contratos antiguos conserva sus defaults. El integrador también protege las listas de reglas y el booleano `is_required`; el SQL los emite explícitamente. |

Las discrepancias de ID, key, familia y versión entre snapshot/plantilla bloquean; también el ID distinto entre campo y definición, y la repetición de ID o key. El dato numérico, default, mínimo y máximo recibidos como JSON number, coma local, espacios exteriores o decimal fuera de PG se rechazan en el **lector**. La coma y los espacios sí se permiten en el **borrador de entrada**, antes de empaquetar la cadena canónica. Son dos contratos deliberadamente distintos.

No se amplió esta revisión a exigencias cosméticas ni se convirtió el DTO en un segundo validador completo de metadatos. Las guardas SQL de plantillas siguen siendo la autoridad sobre su grafo y dominios.

## Revisión de SQL 20260907010000

Archivos leídos, sin editarlos ni ejecutar DB:

- [Migración exact_editor_reads](/Users/Claudio/Dev/bikeshop-erp/supabase/migrations/20260907010000_product_spec_exact_editor_reads.sql), SHA-256 `8c5603bdf7064532b51515af03e1f1fc70b6183396fbb49c8271fd4ce5cc1e4b`.
- [Pruebas SQL del integrador](/Users/Claudio/Dev/bikeshop-erp/supabase/tests/product_spec_exact_editor_reads.sql), SHA-256 `aafba8b3e2c0aa2517ced787b4178dd95bfd35f1a864d678cb7d72e89ca352a0`.

No se identificó un fallo nuevo de tenant, ACL, atomicidad o precisión en este delta por inspección de fuente. La afirmación queda limitada a los caminos revisados:

| Límite | Evidencia de código |
| --- | --- |
| Producto/categoría/identidad | `get_product_spec_editor_context_v2` llama primero a v1, que exige principal/tenant, comprueba producto y categoría y resuelve la plantilla efectiva. La plantilla leída debe estar activa y ser global o del tenant. Un campo/definición enlazado de otro tenant produce rechazo; las opciones se filtran por tenant. |
| Autoridad | RPC v2 `SECURITY DEFINER` con `search_path` explícito, `PUBLIC`/`anon` revocados y `authenticated` autorizado. Helpers privados revocados para esos roles y concedidos a `service_role`. El RPC de referencias exige principal y tenant y conserva el catálogo global autenticado de v1; no pretende que las referencias tengan un tenant propio. |
| Una observación consistente | El RPC y sus lecturas anidadas son `STABLE`: hechos, binding, metadata y versión se obtienen dentro de una sola sentencia. El cliente ya no consulta la plantilla mediante otra petición. Un cambio posterior a esa lectura puede volver obsoleto el borrador y corresponde al guard de revisión al guardar; no exige mezclar dos snapshots de carga. |
| Precisión | `numeric::text` se produce en PG antes de JSON para los hechos; defaults, límites y operandos numéricos se convierten dentro del servidor. Versiones, orden, booleanos y texto de tokens conservan sus tipos. Los valores estructurados de filas mantienen su contrato existente. |
| Legado | La migración fija cinco preimágenes y crea nombres nuevos; no sustituye lectores v1 ni cambia hechos, referencias o plantillas. El valor de un hecho sin ficha se convierte para mostrarlo y conserva su identidad/fuente. El array de lecturas de auditoría heredado no se transforma aquí: no se certifica transporte arbitrario de todos sus campos mediante esta revisión del editor. |

El integrador informó inicialmente 19 pgTAP verdes y luego **23 nuevas / 117 integradas** en tres archivos. La revisión leyó los asserts de escritura autenticada de la cadena exacta, lectura v2, datos huérfanos, referencias, consumidor por categoría, rechazo de producto/categoría/campo de otro tenant, preservación del sobre de filas y conservación del JSON number en v1. No ejecutó la suite ni una segunda DB en paralelo. La igualdad de versión en un fixture no es por sí sola una prueba de carrera; el argumento de snapshot anterior se apoya en la estructura SQL, con el guard de revisión existente para el guardado.

## Consumidores del servicio

Los siete casos de transporte usan `MockClient` con JSON y los métodos reales `getProductEditorContext`, `getTemplateForCategory` y `getReferences`. No usan una sesión Debug ni una conexión de red real.

- Producto y categoría viajan juntos a `get_product_spec_editor_context_v2`; una sola petición devuelve metadata exacta.
- El consumidor que sólo conoce la categoría también usa v2, con `p_product_id:null`.
- Producto o categoría de respuesta distintos se rechazan sin reintento ni fallback.
- Las referencias se leen por v2 antes de construir `ProductSpecReference`; un encabezado v1 se rechaza.
- RPC v2 no disponible produce error; no se obtiene una lectura imprecisa como fallback.

Detalle reproducible del harness: `http.Response` debe conservar `request:request`, porque el cliente PostgREST consulta esa identidad al procesar éxito y error. El primer ensayo del mock omitía esa propiedad y falló antes del servicio; se corrigió la fixture, no implementación. Tampoco se cuentan como defectos del lector los tipos inferidos demasiado estrechos de un literal Dart de fixture: las mutaciones adversas ahora se hacen después de decodificar JSON, igual que un payload de red.

## Cierre independiente

```sh
fvm flutter test --no-pub test/unit/product_spec_numeric_transport_boundary_test.dart --reporter compact
fvm dart analyze test/unit/product_spec_numeric_transport_boundary_test.dart
```

Resultados propios: **62 pasan, 0 fallan**, salida 0; analizador **No issues found**, salida 0. Incluyen 35 pruebas de parser/borrador/payload, 20 del decoder y 7 del servicio con HTTP simulado. El integrador inició además una ejecución del mismo archivo en `.tmp/product-spec-catalog/numeric-final-boundary-tests.log`; no se necesitó repetir el trabajo después de recibir ese aviso.

Huellas del cierre:

| Archivo | SHA-256 |
| --- | --- |
| Regresión independiente | `e5d65f24c87bdf2e9b0c0a40587f6a0b7fdaa869e4eddd4f18b23a1869a7edc2` |
| `spec_engine_service.dart` | `3a7049a5e3b417980397f5b7b724db43dab66dfbb9c161d541e881a32cf516df` |
| `spec_rule_evaluator.dart` | `5d56d5211dccd71fcf4ddfc768500d3f2c19f51a2e60b68bfdb97c23899268b1` |

El integrador informó que 0100 fue **APPLIED y verificada en producción a 2026-09-07 07:45:05Z**, con hashes/ACL/v1 y conservación de datos comprobados, y un smoke autenticado de 38 productos, 35 familias y 17 valores/límites exactos. Esa evidencia pertenece al integrador; esta revisión no hizo consultas productivas, no escribió datos y no tocó la sesión nativa. Los hashes de la migración y del archivo SQL inspeccionado permanecían iguales a los registrados arriba al cerrar.

Pendiente fuera de este dictamen: evidencia real de edición con signo/coma/estado parcial, carga/retorno tras guardar y preservación del borrador en las superficies de la ficha. Esto no reemplaza la auditoría mecánica, asignación de plantillas ni investigación y llenado del catálogo.
