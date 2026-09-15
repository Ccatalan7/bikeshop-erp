# Coherencia de filas — revisión crítica de la integración elegida (2026-09-07)

Revisión independiente de la elección de Codex (`form_contract.row_coherence` con `row.id` estable como valor del vínculo, y `form_contract.scalar_ordered_pairs`) contra el código real del árbol, incluida la implementación Dart en curso (`product_spec_coherence.dart`, aún sin migración SQL). No modifica nada: ni addenda, ni Dart, ni SQL, ni datos. Las fixtures que propone son sintéticas, sin SKU ni fuentes de relleno. Una prueba del generador contra sí mismo no cuenta como verificación; la sección 6 dice qué evidencia faltaría.

## 1. Corrección aceptada sobre la ruta de escritura

Tenía razón Codex y no yo. La integridad no vive «en el payload» sino en el validador central, y ese validador ya alcanza a todo escritor:

- `product_spec_fact_constraint` y `product_spec_value_constraint` son *constraint triggers* diferidos sobre insert/update/delete de `spec_facts` y `spec_fact_values` (070:646-653). Llaman `spec_product_constraint_internal_v1` (160:724-745), que llama `spec_validate_product_internal_v1` (160:366-406); ésta resuelve la plantilla, arma `spec_active_product_values_internal_v1` y ejecuta `spec_validate_draft_internal_v1`; un issue con `blocking` verdadero levanta 23514 con `detail = issues`.
- Además `save_product_with_specs_v1` la llama de inmediato tras `spec_write_payload_internal_v2` (160:481-560, líneas 62-66 del cuerpo), y `record_product_spec_reading_v1` también (170:539).

Por tanto, extender `spec_validate_draft_internal_v1` es suficiente y **no hay que crear una función paralela ni afirmar que el aplicador de fill evita triggers**: cualquier insert directo en `spec_facts` cae en el trigger diferido al commit. Retiro esa parte de mi propuesta. Dos consecuencias sí quedan en pie y se tratan abajo: el trigger valida **una vez por fila de hecho cambiada** (§2 E9) y **sólo cuando cambian hechos o identidad del producto**, nunca cuando cambia la plantilla (§2 E3).

## 2. Errores reales de la elección, con evidencia

### E1 — La identidad «estable» no la conserva ningún escritor

El vínculo guarda `row.id`. Ese id lo acuña el widget con `Uuid().v4()` al añadir (rows_field:162) y el servidor lo acepta tal cual. Ningún escritor está obligado a conservarlo:

- `spec_write_payload_internal_v2` reemplaza `value_json` completo (190:466-486). Un reemplazo del campo destino con ids nuevos —reimportación, borrar y volver a añadir la fila en el editor, una futura relectura del fill— deja **todos** los vínculos entrantes en `row_reference_unresolved`, bloqueante, y el producto no se puede guardar hasta revincular a mano.
- Las referencias son inmutables (070:874-883), así que una versión nueva de la misma referencia OEM son filas nuevas con ids nuevos salvo que el autor copie los ids a mano. Nada lo exige ni lo comprueba.
- No se puede «reconciliar» ids por clave natural en el destino cuando el destino es de la referencia: el validador compara el conjunto del producto con el de la referencia (`reference_conflict`, 190:686-695) y una fila con id reescrito ya difiere.

Es la contrapartida exacta de la ventaja elegida: el id sobrevive al cambio de etiqueta, pero no sobrevive a la reescritura. Mínimo que falta:

1. Regla de escritura para campos destino **no** gobernados por referencia: al reemplazar el campo, una fila entrante sin id (o con id nuevo) cuyo grupo `unique_by` coincide con una fila existente conserva el id existente. Se implementa en `spec_write_payload_internal_v2` y en el editor (no regenerar id al editar; hoy `_changeCell` lo conserva, `Añadir` lo acuña: correcto).
2. Convención obligatoria para autores de referencias: ids semánticos (`usb_c_1`, no UUID) y estables entre versiones; un pgTAP que inserte una versión sucesora con la misma marca/modelo y falle si una fila con iguales `label_columns` cambió de id (es lo máximo que se puede exigir sin un vínculo entre referencias).
3. Consulta de sólo lectura «vínculos huérfanos por producto» para correr tras publicar una referencia o cambiar metadatos (ver E3).

### E2 — Cambiar la referencia del producto puede dejarlo inguardable en la misma transacción

Orden en `save_product_with_specs_v1`: `update products set spec_reference_id` → `spec_write_payload_internal_v2` (fusiona los hechos de la nueva referencia, ids nuevos) → `spec_validate_product_internal_v1`. Si el reparto de potencia es del mecánico y los puertos venían de la referencia, el cambio de referencia rompe los vínculos y la RPC levanta «La ficha técnica tiene conflictos». El cliente muestra sólo `e.message` (form:5344-5350): sin campo, sin fila.

Del lado cliente el escenario **debería** atraparse antes: al elegir referencia, `_resolveSpecInference` fusiona sus hechos en `_specValues` (form:1418-1424) y `_specIssues` se recalcula. Falta la prueba de widget que lo demuestre: cambiar referencia → la fila de reparto muestra «La configuración vinculada no existe en esta ficha» y el botón de guardar queda bloqueado por issue, no por excepción del servidor. Y para el caso latente (E3) hay que leer `PostgrestException.details` (trae el arreglo de issues con `field`/`row_id`) y volcarlo en `_specIssues`; hoy se descarta.

### E3 — Un cambio de metadatos crea conflictos latentes que nadie revalida ni avisa

Los constraint triggers disparan por cambios en `products`, `spec_facts` y `spec_fact_values` (070:646-653). Agregar un vínculo sobre una columna ya poblada, redirigir `target_field`, o pasar el destino a `legacy` valida sólo los metadatos (200:88-205). Los productos afectados:

- fallan en su **próximo** guardado de ficha, por cualquier motivo, con el mensaje genérico;
- desaparecen en silencio del sitio público: `get_public_product_technical_specs` ejecuta el validador sobre lo guardado y oculta el campo con issue bloqueante (190:915-919), sin señal para el operador;
- mantienen `contract_version` invalidando editores abiertos (070:889-897), lo único que hoy sí ocurre.

Mínimo: el guard de plantilla trata un vínculo nuevo o cambiado sobre una definición con hechos o valores de referencia igual que `spec_rows_definition_guard` trata un cambio de `rows_schema` (190:216-239): rechazo salvo migración explícita, y esa migración corre y publica la consulta de huérfanos antes de aplicar. Hoy los campos de los addenda no tienen hechos; el guard debe existir **antes** del sembrado o la regla no protege nada.

### E4 — El guard SQL ignora claves desconocidas del `form_contract`; Dart no

`spec_template_rules_validate_internal_v1` valida sólo `allowed_when`, `required_when`, `allowed_options` y `prerequisites` (200:110) y retorna sin mirar nada si `rules_version` es 1 (200:97-101). `row_coherence` y `scalar_ordered_pairs` pasan sin validar, y una clave mal escrita (`row_coherance`) también. Dart, en cambio, rechaza el contrato (`fromContract`) y **no monta el editor** de ningún producto de esa plantilla (engine:433-435). Resultado: metadatos aceptados en SQL, editor caído para toda una familia.

Mínimo: el guard SQL valida los dos bloques con las mismas reglas que Dart (regex `^[a-z][a-z0-9_]*$` para id/field/column/target_field —la misma que las columnas en 190:65—, extremos `json` con `rows_schema`, ninguno `legacy`, columna origen `text` o `token` sin `allowed_values`, `label_columns` ⊆ columnas destino sin repetir, ids y celdas sin duplicar, ciclos incluyendo `prerequisites`), rechaza los bloques cuando `rules_version` ≠ 2, y rechaza cualquier clave de nivel superior que no conozca. Sin esa última regla la parte «typo» no tiene arreglo.

### E5 — `range_order` tendrá dos dueños y el SQL actual no ve números en texto

- Dart: lista fija de cuatro pares (contract.dart:301-318) **más** `scalar_ordered_pairs` (coherence), y el dedupe por `(code, field)` (contract.dart:320-333) esconde que conviven. SQL: lista fija (190:781-790) que sólo compara cuando `jsonb_typeof = 'number'`; un valor en texto —la forma canónica del cliente desde el lector exacto— nunca se compara. Hoy no se nota porque al commit los números salen como jsonb number desde `spec_product_payload_internal_v1`; se notará en cuanto algo pase `p_values` en texto (fixtures, fill).
- La comprobación Dart de pares no exige la misma `unit`: `['tube_width_min_mm','tube_width_max_in']` es un par válido para `fromContract`.
- El issue se atribuye sólo a `pair[1]`; el sitio público oculta únicamente el límite superior y muestra el inferior de un par contradictorio (190:915-919).

Mínimo: mover los cuatro pares fijos a `scalar_ordered_pairs` de cada plantilla y borrar ambas listas fijas **en el mismo release**; SQL compara vía `spec_rule_normalize_internal_v1` + `numeric`; guard exige `unit` idéntica y tipo `number` en ambos extremos; el issue se emite para los dos campos. La igualdad se permite explícitamente (un producto de talla fija declara min = max); dejarlo escrito en el contrato.

### E6 — «Desconocido» no es «null» en el evaluador de vínculos

`ProductSpecCoherence.validate` salta un campo sólo si `values[key] == null`; el bucle por campo del validador salta todo lo que `hasKnownSpecValue` considera desconocido. Un campo de filas con el marcador de desconocido (texto) se vuelve `row_shape` bloqueante únicamente cuando participa en un vínculo. En SQL el espejo es `spec_rule_known_internal_v1`. Alinear los dos antes de escribir la migración; fixture F2.

### E7 — El escritor de lecturas devuelve excepción donde promete veredicto

`record_product_spec_reading_v1` escribe un escalar y llama `spec_validate_product_internal_v1` (170:539). Con `scalar_ordered_pairs`, una lectura de `tube_width_min_mm` mayor que el máximo guardado levanta 23514 en vez de retornar `verdict: rejected`. El bucle del asistente distingue rechazos de fallos; aquí verá un fallo. Mínimo: el par se comprueba en `spec_reading_rejection_internal_v1` (o se captura la excepción y se mapea a `rejected` con la razón).

### E8 — Todos los lectores imprimen el id

`spec_rows_display_internal_v1` (190:204-215) y por tanto `get_public_product_technical_specs` (190:927), `get_product_spec_typed_configurations_v1` (190:295-328, lo que lee el asistente) y el resumen del selector de filas (`_summary`, rows_field:196-201) muestran el valor crudo de la celda: un UUID. No es un error del contrato pero sí del producto: el cliente del sitio y el asistente verán `a1b2c3…` donde debía decir «USB-C 1». La función de display es `immutable` con firma `(schema, value)` y no puede resolver etiquetas de otro campo; necesita el payload completo y los vínculos. En Dart `_summary` puede usar `referenceOptions`.

### E9 — Costo del trigger diferido, ahora multiplicado por las filas vinculadas

Un guardado con N hechos cambiados dispara N validaciones completas al commit (una por fila de `spec_facts`), más la inmediata de la RPC; cada una ahora parsea todos los campos de filas vinculados. No es un defecto de corrección; sí una medición obligatoria antes de aceptar: cronometrar un payload de 30 campos con dos campos de filas de 10 filas. Si molesta, deduplicar por transacción con una tabla temporal `on commit drop` de productos ya validados.

### E10 — Cadenas y etiquetas que son ids

Los vínculos encadenados (A→B→C) están permitidos; `label_columns` de un destino puede incluir la columna de vínculo del propio destino y el rótulo mostrará un id. Guard: una columna que es origen de vínculo no puede ser `label_column` de nadie.

### E11 — Ambigüedad de rótulo

`label_columns` no tiene por qué identificar la fila; Codex lo resuelve anteponiendo la posición (`'${i+1} · …'`). La posición cambia al borrar o reordenar filas, así que el operador verá «2 · USB-C» hoy y «1 · USB-C» mañana para el mismo id. El dato no cambia; la confianza sí. Alternativa barata: exigir en el guard que `label_columns` cubra un grupo `unique_by` del destino cuando el destino lo declara, y usar la posición sólo si no lo declara.

### E12 — Ciclo con `prerequisites`: correcto, pero por otra razón

Una condición no puede apuntar a un campo `json` (200:130-134), así que un ciclo vínculo→condición→vínculo es imposible; sí es posible vía `prerequisites`, que admite cualquier campo. Un ciclo así **no** bloquea al operador (pendiente y `prerequisite_missing` son no bloqueantes, se puede llenar en cualquier orden); lo que rompe es el orden topológico del formulario (form:7744-7760, que descarta el arco de vuelta en silencio). Vale rechazarlo; el mensaje debe decir «orden de edición», no sugerir un bloqueo de datos.

### E13 — Verificado sin error: concurrencia y borradores

- Dos operadores: candado consultivo por producto, `for update` sobre `products`, `p_expected_revision` (160, líneas 19-21 del cuerpo) y `p_contract_version` (línea 27). Un vínculo hacia una fila que otro operador borró termina en 40001 «Recarga antes de guardar», nunca en huérfano silencioso. Falta la prueba unitaria de la RPC con revisión vieja que lo demuestre para filas (existe para escalares; no lo verifiqué).
- Etiquetas: cambiar el rótulo del destino reescribe **su** hecho (borra sus lecturas, `confirmed=false`), pero el hecho origen no cambia porque el write path salta los hechos cuyo conjunto no varió (190:459-465): las lecturas del origen se conservan. Coincide con lo prometido.
- Fuentes: un vínculo no lleva fuente; la afirmación («este puerto entrega 45 W en C1+C2») sigue con sus URLs en la fila origen. Sin cambio.
- Borradores: el widget se remonta por `_loadedSpecDraftKey` y las opciones salen de `_specValues` en cada build. Correcto; el costo es que el getter `coherence` reparsea el contrato y todas las filas en cada acceso (`_specIssues` se evalúa varias veces por build: form:4795, 7698, 7701, 7734). Medir con una ficha de 40 campos; cachear por `contractVersion` si hace falta.

## 3. Lo que acepto de la elección frente a mi propuesta

- El vínculo en la plantilla y no en `rows_schema` evita el problema de despliegue que yo tenía: un parser Dart viejo rechaza cualquier clave desconocida en una columna (rows.dart:148-164); con `form_contract` los datos guardados no cambian de forma y la versión 1 sigue válida.
- Guardar el id y no la etiqueta es correcto **siempre que** E1 se resuelva; sin la regla de conservación, la etiqueta era el más estable de los dos.
- Pendiente no bloqueante / no resuelto bloqueante / forma inválida no se degrada a destino vacío: coincide, y el código lo hace (`invalid` en `validate`).
- Sin cascada destructiva, valor huérfano conservado y visible como error (rows_field:206-231). Correcto; el selector S-06 no revienta con un valor fuera de opciones (`selected?.label ?? placeholder`, vb_searchable_select:215).

## 4. Fixtures adicionales (sintéticas; ids `p1/p2`; sin SKU; `sources: []`)

| Id | Tipo | Qué prueba | Esperado |
|---|---|---|---|
| F1 target_rewritten_keeps_id_by_unique_by | positivo | reemplazar `ports` sin ids con igual `unique_by` | los vínculos siguen resueltos; el id no cambió |
| F1b target_rewritten_without_unique_by | negativo | reemplazar `ports` (esquema sin `unique_by`) con ids nuevos | `row_reference_unresolved` bloqueante en cada fila origen; el guardado se rechaza entero |
| F2 unknown_marker_on_linked_rows | desconocido | `allocations` = marcador de desconocido | sin issue de vínculo ni `row_shape` (paridad Dart/SQL) |
| F3 reference_switch_shows_orphans_before_save | widget | cambiar referencia con reparto del mecánico | issue visible en la fila; guardar deshabilitado; sin llamada a la RPC |
| F4 scalar_pair_unit_mismatch | metadatos | `['a_mm','b_in']` | rechazado por Dart y por el guard SQL |
| F4b scalar_pair_equal_allowed | positivo | `lower = upper = "31.8"` (texto) | sin issue en Dart y en SQL |
| F4c scalar_pair_text_numbers_sql | negativo | `p_values` con `"32"` y `"31.8"` en texto | `range_order` en SQL para ambos campos |
| F5 unknown_contract_key | metadatos | `row_coherance` | rechazado por el guard SQL |
| F5b coherence_on_rules_v1 | metadatos | `rules_version: 1` + `row_coherence` | rechazado por el guard SQL (Dart ya lo hace) |
| F6 label_column_is_link_source | metadatos | `label_columns: ['port_row_id']` | rechazado |
| F7 reading_conflict_returns_rejected | RPC | lectura de `lower` mayor que `upper` guardado | `verdict: rejected`, sin excepción |
| F8 public_specs_hide_both_pair_fields | lector | par contradictorio | ni `lower` ni `upper` en el sitio público |
| F8b display_resolves_link_label | lector | fila vinculada | el display muestra «USB-C 1», no el id |
| F9 link_over_populated_column_needs_migration | guard | agregar vínculo sobre definición con hechos | rechazado sin migración explícita; la consulta de huérfanos lista el producto |

## 5. Lo que sigue sin cubrir (a propósito)

Igual que en la propuesta anterior: predicados de condición sobre filas, comparaciones numéricas entre campos (sumas, tope por puerto), referencias a filas de otro producto, aplicabilidad de una celda según otra celda, procedencia por fila, completitud de una combinación compuesta, y cualquier veredicto físico. Se agrega uno: **estabilidad del id entre versiones de una referencia**, que no es verificable sin un vínculo entre referencias sucesoras y queda como convención con pgTAP parcial (E1.2).

## 6. Qué evidencia faltaría para aceptar

1. **Paridad independiente Dart/SQL**: un pgTAP que lea `test/fixtures/product_spec_coherence.json` (el mismo archivo que consume el test Dart) y compare, caso por caso, `code`/`field`/`row_id`/`blocking` de `spec_validate_draft_internal_v1` contra `expected`. Eso es verificación cruzada; el test Dart contra su propio fixture no lo es.
2. Postimágenes md5 de las funciones tocadas, como en 190/200, y el guard SQL rechazando F4/F5/F5b/F6/F9.
3. Prueba de widget F3 y prueba de la RPC con revisión vieja para un vínculo a fila borrada (E13).
4. Medición de E9 y del reparse en el cliente (E13) con una ficha de tamaño real.
5. Lectores (E8) resolviendo etiquetas: sin eso el contrato es correcto y el producto muestra UUIDs.

## 7. Entradas leídas (SHA-256 al momento de la revisión)

| Archivo | SHA-256 |
|---|---|
| lib/modules/inventory/models/product_spec_coherence.dart (sin rastrear, en curso) | `12ce1c3ac86bffa55915acf35712417e5022afa0b84e477a0cc74c9fa740e8df` |
| lib/modules/inventory/models/product_spec_number.dart | `6aa10694f95458cdf90dba786f5cb1a0781c4d0d29322fbedbeb78dc271112e9` |
| lib/modules/inventory/models/product_spec_contract.dart | `9b04203f4401a2bf67c4bb46d455d6bd61685ee311f4c5df54a7358864c35578` |
| lib/modules/inventory/widgets/product_spec_rows_field.dart | `c273df3c98db9d94d3ab59230e60dd7dc7a3b49c29eac08c8a64f01d1db098cf` |
| lib/modules/inventory/services/spec_engine_service.dart | `a59730dfa831de363e5fb2c47154462379c0fe04b207bfcf3b7ac0b4a5520d78` |
| lib/modules/inventory/pages/product_form_page.dart | `8795e47a2e98e7fd6f869b656a3e06592be090f36ec4ba96d4fce09b7d5b887a` |
| test/unit/product_spec_coherence_test.dart | `42f8c8b7b5e4d957de8d5775862371403caa8c490dd295d15d578742a0ce6e78` |
| test/fixtures/product_spec_coherence.json | `53c080b23d4dadabe65fece1345467e3fe6005a6b841a8ca1eb79707512af37f` |
| supabase/migrations/20260906070000_product_spec_contract.sql | `007450b4bcd89b36b1afc6cc55b000c99a6c42c1828537abd8500929e1ae5d4d` |
| supabase/migrations/20260906160000_product_spec_template_binding.sql | `bf46ca8592500abdbcb6435740a3657653ec97450fdc9364c9d193f2cf179694` |
| supabase/migrations/20260906170000_product_spec_legacy_boundary.sql | `7aac4171546c39ba5ff66c3c3add3776bb67a52b4b7d0ef5e1e2567f44d3b53b` |
| supabase/migrations/20260906190000_product_spec_structured_rows.sql | `53e0ac8b6313ae226ecba9d6b69aebf16f359223f78698434653836055866483` |
| supabase/migrations/20260906200000_product_spec_field_conditions.sql | `643f526a7dbb2a794373c3a90a169806906abf116a144efdd187832eabe1ecda` |
| supabase/migrations/20260907010000_product_spec_exact_editor_reads.sql | `8c5603bdf7064532b51515af03e1f1fc70b6183396fbb49c8271fd4ce5cc1e4b` |
