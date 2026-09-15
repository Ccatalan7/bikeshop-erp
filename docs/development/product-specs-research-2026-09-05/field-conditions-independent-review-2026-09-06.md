# Revisión independiente de condiciones de ficha v2 — 2026-09-06

Revisión local anterior a las correcciones del integrador, sobre `20260906200000_product_spec_field_conditions.sql`, `product_spec_template_rules.dart`, `SpecTemplate` y `validateProductSpecDraft`. Se inspeccionaron los consumidores del editor y el canal de validación de producto; no se modificó SQL/Dart de implementación, no se abrió runtime y no hubo consultas ni escrituras en producción.

La función SQL reproducida tenía MD5 **`aeada187ea4e977e79110b88d76e2f57`** (`spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)`, PostgreSQL 17.6 local). El integrador recibió los hallazgos y está corrigiéndolos. Este documento registra la preimagen observada, **no una aprobación de los arreglos aún no comprobados**.

## Evidencia reproducible

- `.tmp/spec-conditions-review-2026-09-06.sql` → `.tmp/spec-conditions-review-2026-09-06-sql.log`.
- `.tmp/spec-conditions-review-scalar-parity.sql` → `.tmp/spec-conditions-review-scalar-parity.log`.
- `.tmp/spec-conditions-review-2026-09-06_test.dart` → `.tmp/spec-conditions-review-2026-09-06-dart.log`.

Comandos usados:

```bash
VINABIKE_DB_WRITE_CONFIRM=local bash scripts/db/query.sh local --write --file .tmp/spec-conditions-review-2026-09-06.sql
bash scripts/db/query.sh local --file .tmp/spec-conditions-review-scalar-parity.sql
fvm flutter test --no-pub .tmp/spec-conditions-review-2026-09-06_test.dart --reporter expanded
```

El primer SQL usa fixtures propias `a4cc2000-…` dentro de una transacción terminada en `ROLLBACK`; no instala ninguna función persistente. El harness Flutter **imprime observaciones y captura errores**: su `All tests passed` sólo significa que terminó el probe, no que la conducta observada satisfaga el contrato. La primera tentativa SQL falló por un `allowed_values` null de la fixture numérica; se corrigió a `[]` antes de la ejecución completa. Ese fallo fue del probe y no del producto.

## FC01 — P1: las condiciones decimales no consumen los números de la ficha

`evaluateProductSpecTemplateCondition` y `spec_template_condition_internal_v1` delegan la comparación en el evaluador estricto de relaciones v2. Éste convierte un valor actual `num` / JSON number en desconocido. Sin embargo, `product_form_page.dart::_parsedSpecNumberValue` devuelve int/double y los controles `case number` lo guardan directamente en `_specValues`. En el servidor, `spec_assert_product_contract_internal_v1` valida `spec_active_product_values_internal_v1`, no la proyección de configuraciones tipadas que convierte números a texto.

Reproducción: dependiente permitido si `amount >= "2"`, requerido siempre.

| Entrada | SQL | Dart |
| --- | --- | --- |
| `amount: 2`, dependiente ausente | `[]` | `[]`, applicability `unknown` |
| `amount: "2"`, dependiente ausente | `required_missing`, no bloqueante | mismo resultado, applicability `yes` |
| `amount: 2`, dependiente `"01"` | requisito desconocido, no bloqueante | mismo estado |

**Impacto:** una elección numérica válida no desbloquea el campo dependiente; un valor contradictorio puede quedar como desconocido en vez de evaluar su condición.

**Corrección acotada:** proyectar los números ordinarios de ficha según la definición numérica antes de evaluar estas condiciones, con la misma regla en SQL/Dart. El evaluador de relaciones conserva su transporte exacto y estricto; una condición de formulario no debe debilitarlo. Mantener límites y precisión del campo: convertir a texto no recupera precisión que ya se haya perdido en un transporte anterior.

**Gate:** comparar el mismo valor a través del editor ordinario y el valor activo de SQL; no basta probar a mano un string que el editor nunca produce.

## FC02 — P1: allowed_when sustituye visibility_rules en Dart, pero SQL aplica ambas

`SpecTemplate.applicabilityFor` devuelve la condición nueva cuando existe y omite `field.applicability(values)`. SQL evalúa `allowed_when` y después recorre `visibility_rules` de todas maneras.

`v2_always_legacy_visibility_false`: nuevo `allowed_when=always`, visibilidad heredada `mode == A`, valores `{mode:B, child:"01"}`. SQL devuelve `field_constraint` bloqueante; Dart devuelve `[]`.

**Impacto:** el editor permite una ficha que el servidor rechaza; el orden visual y la corrección guiada no describen la validación real.

**Corrección acotada acordada por el integrador:** conjunción de ambas guardas en Dart para mantener las guardas SQL. La extracción de dependencias debe incluir ambas, no sólo la expresión nueva. Las reglas heredadas no deben desaparecer por precedencia accidental.

**Gate:** verdadero/falso/desconocido en cada lado, incluidos `allowed_when=yes + visibility=unknown` y el listado de dependencias que el editor usa para ordenar y explicar el bloqueo.

## FC03 — P2: Dart admite números como opciones de selección literales

El helper local `optionValues` hace `v.toString()` en v2. El guard de cardinalidad de `single_select` sólo rechaza List, sin exigir String. Con opciones globales `["01","1"]` y sin restricción local:

- `single_select_json_number`, valor `1`: Dart `[]`; SQL bloquea la forma.
- `multi_select_json_number`, valor `[1]`: Dart `[]`; SQL bloquea la opción por tipo JSON.

**Impacto:** discrepancia cliente/servidor ante valores importados o precargados con tipo equivocado. SQL mantiene el límite de guardado; no se ha demostrado persistencia inválida.

**Corrección acotada:** exigir String en selección simple y List de String en múltiple; igualdad de tokens literal. No convertir códigos, bool, mapas o números por `toString()`.

**Gate:** conservar la conversión declarada y explícita de bool a `"true"`/`"false"` sólo para el mapa `allowed_options` de un campo boolean. Su respuesta continúa siendo bool; `"true"` string sigue siendo tipo inválido.

## FC04 — P2: null y versión textual permiten metadatos que sus consumidores no aceptan

Dos reproducciones independientes:

1. `prerequisites:{child:[null]}` se acepta al actualizar la plantilla. SQL usa `jsonb_array_elements_text`, por lo que la validación de pertenencia no falla con SQL null. La validación del borrador produce `message:null`; Dart `List<String>.from` lanza `_TypeError`.
2. `rules_version:"2"` con `allowed_when:{alien:{kind:always}}` se acepta. El guard sale si la versión no es JSON number 2, pero SQL del borrador usa `->>'rules_version'='2'`. Dart tampoco comparte exactamente esa comparación de versión.

**Impacto:** metadatos guardados por compilador/admin pueden dejar un editor no renderizable o eludir el control de campos ajenos. No es una afirmación de que un usuario sin privilegios pueda editar metadatos.

**Corrección acotada:** validar elementos de prerrequisito como strings no vacíos y claves activas; validar tipo y conjunto de versiones soportadas, separando v1 legítimo de una versión v2 mal formada. Un formato desconocido debe fallar de forma controlada antes de renderizar.

**Gate:** null, number, boolean, object, clave vacía y versión `"2"`/`2.1`/null explícito. Ausencia legítima de metadatos antiguos no debe romperse por este guard.

## FC05 — P1: un campo activo puede depender de otro retirado

El conjunto `keys` de `spec_template_rules_validate_internal_v1` incluye todos los campos, sin excluir `roles=legacy`. `legacy_dependency_metadata` se acepta con una condición del campo activo sobre `mode`, retirado. El validador de borrador elimina `mode` antes de evaluar; tanto SQL como Dart devuelven requisito desconocido.

El consumidor visual presenta otra divergencia: `_specFieldBehaviorForValues` llama `template.applicabilityFor(field, _specValues)` con valores todavía conservados. `legacy_dependency_applicability_direct` devuelve `yes` para `{mode:A,child:"01"}`, mientras la validación de ese mismo borrador retira la respuesta legacy y devuelve desconocido.

**Impacto:** un dato retirado habilita una elección en el editor pero no sirve para validarla; en borradores nuevos la dependencia puede ser imposible de completar.

**Corrección acotada:** los campos activos no pueden depender de legacy mediante prerequisites/allowed_when/required_when. Proyectar valores activos también en los consumidores que deciden habilitación. Conservar los datos legacy como historia y sus condiciones históricas fuera del contrato activo.

**Gate:** cambio de role activo→legacy y plantilla cargada con datos históricos; deben preservarse los datos sin usarlos para habilitar campos activos.

## FC06 — P2: cambiar sólo spec_definitions.key deja referencias colgantes

Inspección de triggers reales: `product_spec_definition_revision` cubre `validation_rules,data_type,allowed_values,label`, pero no `key`. El guard nuevo vive en templates/template_fields; el guard de rows no valida estos nombres.

`rename_upstream_key`: se cambia sólo key y la actualización se acepta. `metadata_after_upstream_key_rename`: invocar explícitamente el validador inmediatamente después devuelve `23514`, requisito de otra ficha. El estado aceptado por los triggers no cumple su propio validador. La transacción de prueba termina en rollback.

**Impacto:** identidad de campo y condiciones se desincronizan por una edición de metadata; también falta invalidación del editor para esa edición.

**Corrección acotada:** guard diferido sobre definición que revalide sus plantillas dependientes, incluyendo cambios de key. Preservar actualizaciones atómicas legítimas de key+contrato; la revisión de contrato/editor debe aumentar cuando cambia la semántica. Si key es inmutable por política, imponerlo realmente.

**Gate:** cambiar sólo key debe fallar; cambiar key y referencias coherentemente dentro de la misma transacción puede permitirse si el contrato lo autoriza. Revisar ambos lados de un cambio de vínculo de campo entre plantillas.

## FC07 — P1: constraint_rules heredadas vuelven a normalizar 01 como 1

En v2, `SpecTemplate.constrainedOptionsFor` conserva `allowed_options` literal, pero intersecta el resultado de `field.constrainedOptionsFor`, que usa `intersectSpecOptionRules` y `specRuleValueSet`. SQL hace lo equivalente con `spec_rule_set_internal_v1(v_rule->'allow')`.

Probe Dart: `allowed_options.child=["01"]` y constraint activa `allow:["01"]` producen conjunto vacío. `literal_01_legacy_constraint_draft` bloquea `child:"01"` aunque ambas declaraciones originales lo permiten.

**Impacto:** una opción válida se vuelve imposible; normalizar el campo local no arregla una normalización posterior. La forma exacta de los operandos de condiciones heredadas también necesita una decisión explícita, pues siguen usando el evaluador v1.

**Corrección acotada acordada:** permitir conjuntos de `allow` literales en v2, sin normalización numérica. Mantener evaluación heredada donde esté expresamente requerida, sin atribuirle fidelidad de token v2 ni introducir reglas mecánicas nuevas.

**Gate:** `"01"` permitido no se vuelve `"1"`; misma selección en SQL y Dart; intersecciones múltiples y bool explícito siguen correctos.

## FC08 — P2: gramática decimal del operando distinta en SQL y Dart

`comma_decimal_operand` (`value:"2,5"`, actual `"2.5"`) y `spaced_decimal_operand` (`value:" 2 "`, actual `"2"`) devuelven true en SQL, mientras Dart lanza `FormatException`.

Causa: SQL valida con `spec_rule_number_internal_v1`, que normaliza coma/espacios; la validación Dart usa `SpecRuleDecimal.tryParse(choice)` directamente.

**Impacto:** un contrato validado por SQL puede romper la lectura del editor.

**Corrección acotada:** elegir una gramática común para los operandos de metadata. Es razonable exigir texto decimal canónico sin coma/espacios; si se normaliza, debe ser exactamente igual en ambos lados y antes de validar. Separar este problema del valor actual `num` de FC01.

**Gate:** espacios, coma, exponente, cero, boolean y valores grandes, sin confundir códigos de selección con decimales.

## Controles confirmados y límites

- `cycle_rejected_control`: ciclo directo de prerequisites con versión numérica 2 → `23514`.
- `foreign_field_rejected_control`: condición sobre campo ajeno con versión numérica 2 → `23514`.
- Dart diferencia literalmente `"01"` de `"1"` en el evaluador nuevo; mismo `"01"` sí coincide.
- Los valores de campos fuera de la plantilla se eliminan antes de la validación de borrador; un dato ajeno no satisface una condición legítima.
- Los cambios upstream conservan la respuesta manual contradictoria para revisión; no se observó borrado automático en `_updateSpecValue`/`_resolveSpecInference`. Esto es inspección de consumidores y evaluación de borrador, no evidencia visual de runtime.
- La prueba `unreachable_local_option_metadata` muestra que no se analiza satisfacibilidad frente a `allowed_options` locales. **No es un blocker independiente**: una condición reusable puede no aplicar dentro de cierta subplantilla legítima. El compilador puede advertirlo y simplificar, sin prohibir toda rama localmente imposible.
- No se exige aciclicidad de `required_when` por sí sola: requisitos mutuos de completitud no necesariamente impiden contestar campos. El grafo que bloquea entrada incluye applicability/prerequisites; sus dependencias heredadas deben quedar explícitas.
- Queda pendiente confirmar que los cambios de metadatos invaliden/revaliden todos los contratos dependientes, que los arreglos pasen los probes y regresiones normativas, y el read-back del despliegue que hará el integrador.

No usar las salidas pre-corrección de este documento como estado actual después de que el integrador cambie las funciones. Comparar MD5 de función, reconstruir fixtures propias y guardar un log diferencial separado.

## Cierre diferencial de regresiones normativas

El integrador corrigió la implementación y autorizó al revisor a escribir exclusivamente las dos suites siguientes. A diferencia del harness exploratorio anterior, ambas contienen aserciones de conducta:

- `supabase/tests/product_spec_field_conditions_boundary.sql`: **54/54 pgTAP pasan** en la iteración local corregida. Incluye el writer agregado real bajo `SET ROLE authenticated`, no sólo llamadas al evaluador.
- `test/unit/product_spec_template_rules_boundary_test.dart`: **26/26 tests pasan**. Incluye la proyección ordinaria de `SpecEngineService.buildFactPayload` y conserva el transporte estricto del motor de relaciones.

Comandos y evidencia:

```bash
bash scripts/db/test.sh product_spec_field_conditions_boundary
fvm flutter test --no-pub test/unit/product_spec_template_rules_boundary_test.dart --reporter expanded
```

- Primer resultado diferencial SQL: `.tmp/spec-conditions-review-regression-sql.log`, **52/54**; fallaron los dos límites del grafo heredado descritos abajo. No fue un error de fixture.
- Resultado SQL tras la siguiente corrección del integrador: `.tmp/spec-conditions-review-regression-sql-after-legacy.log`, **54/54**; salida completa `.tmp/db/pgtap-20260906-214156.log`.
- Resultado Dart: `.tmp/spec-conditions-review-regression-dart.log`, **26/26**.
- Huellas de funciones leídas después: `.tmp/spec-conditions-review-local-functions-after.json`.
- Comprobación de rollback de fixtures `a4cc2100-…`: `.tmp/spec-conditions-review-regression-rollback.json`.

La prueba SQL usa una transacción terminada en rollback y funciones auxiliares sólo en `pg_temp`; no cambia funciones de implementación ni datos persistentes. No hubo producción ni runtime.

### FC09 — P1 reproducido y corregido: grafo de entrada incompleto al conservar visibilidad heredada

La primera implementación corregida conservaba la conjunción `allowed_when AND visibility_rules`, pero el grafo de aciclicidad seguía leyendo sólo las nuevas condiciones y `prerequisites`. Casos reproducidos:

1. `mode` permitido cuando `child == "01"`; `child` visible por regla heredada sólo cuando `mode == "A"`. El ciclo se aceptaba sin excepción, aunque ambos campos dependían de responder antes el otro.
2. La visibilidad heredada de `child` podía depender de `alien`, que no pertenece a la plantilla, sin que el guard rechazara la metadata.

El integrador agregó extracción recursiva de las dependencias heredadas activas y su pertenencia/rol al mismo grafo. Se repitieron **los mismos 54 asserts sin cambiarlos** contra la aplicación local posterior: ambos casos ahora rechazan con `23514`. La inspección confirma recorrido de los nodos `all`/`any`; esta suite focal no pretende cubrir exhaustivamente toda combinación de la gramática heredada.

### Correcciones verificadas y alcance

| Hallazgo | Evidencia diferencial |
| --- | --- |
| FC01 | JSON number y texto numérico guardados por el agregado autenticado producen número activo y disparan el mismo requisito; la condición de relación estricta conserva `unknown` para JSON number. |
| FC02 | Visibilidad heredada y condición nueva se conjugan; contradicción bloquea, desconocido no exige respuesta ausente, ambas verdaderas habilitan. |
| FC03 | Selecciones numéricas no se convierten a tokens; string y listas de strings válidos siguen pasando. |
| FC04 | Versiones con tipo incorrecto y miembros de prerequisites null/number/bool/object/vacío rechazan. |
| FC05 | Dependencias nuevas y prerequisites sobre datos retirados rechazan; valores ajenos/legacy se conservan fuera de la validación activa. |
| FC06 | Cambiar key, tipo, dominio o quitar el binding no puede dejar una dependencia colgante. Key y contrato sí pueden cambiar juntos con validación diferida. |
| FC07 | Intersección local + `allow` heredado conserva literalmente `"01"` frente a `"1"`; bool requiere una respuesta bool real. |
| FC08 | Operand metadata con coma/espacios rechaza en SQL y Dart. |
| FC09 | Ciclo cruzado nuevo/heredado y dependencia heredada ajena rechazan tras la corrección local. |

Huellas SQL de esta aceptación local:

| Función | MD5 de `pg_get_functiondef` |
| --- | --- |
| `spec_template_condition_internal_v1(jsonb,jsonb)` | `b069c020eac9ddc2c088dbbab3bdd091` |
| `spec_template_rules_guard_internal_v1()` | `93b6939f2eac40107abfdabb2d27895c` |
| `spec_template_rules_validate_internal_v1(uuid)` | `faba814953aff0ae8c099c5dbd6c3e93` |
| `spec_validate_draft_internal_v1(uuid,jsonb,text,text,text,text)` | `0fdb9858a2fc3a0ac597c65df183e62a` |

No quedan fallos reproducidos pendientes **dentro de esas dos suites**. Su aceptación no equivale a validación mecánica/OEM del catálogo ni prueba visual del editor. La serialización metadata se inspeccionó (`template FOR UPDATE`, definiciones `FOR SHARE`); no se ejecutó una prueba nueva de dos sesiones concurrentes.

Gate residual de FC06 comunicado al integrador: el trigger heredado `product_spec_definition_revision` escucha `validation_rules,data_type,allowed_values,label`, pero no `key`. La nueva regresión verifica cambios de key referenciada y edición atómica con contrato, que sí incrementa versión; no demuestra invalidación de un editor ante un rename de key sin referencias. Si se permiten esos renames, incluir key en el trigger de revisión o imponer inmutabilidad. Este punto es distinto del guard de dependencias ya verificado.

La aceptación final de despliegue, read-back y runtime corresponde al integrador. Las pruebas sintéticas verifican el contrato de software; las reglas mecánicas y el llenado de productos conservan sus gates de fuentes y cobertura.


## Integración del responsable — 2026-09-06

La invalidación residual por `key` y `unit` quedó incorporada en el trigger de revisión, con cuatro regresiones adicionales. Migración `20260906200000` aplicada y verificada en producción a las `2026-09-07T05:02:10Z`; SHA-256 `643f526a7dbb2a794373c3a90a169806906abf116a144efdd187832eabe1ecda`. El integrador ejecutó 379 pgTAP y 135 pruebas Dart/widget. No se cambió ningún producto. La revisión mecánica de familias sigue siendo otro gate.
