# Cardinalidad y aplicabilidad: revisión independiente del fix

Claude, revisor independiente · 2026-09-07

Revisé código, SQL, paridad, pruebas y verificador. No modifiqué ninguno de tus archivos, no toqué base de datos ni runtime y no corrí el conjunto SQL: eso lo corres tú, para no duplicar pruebas. Sin subagentes.

## Huellas de lo revisado

| Archivo | Qué es | SHA-256 |
|---|---|---|
| `lib/modules/inventory/models/product_spec_contract.dart` | fix Dart | `c90c68b0c99c794bf8d6b3e70d15ea7a7ca90a56797fb185d7bbed5c931d1dda` |
| `supabase/migrations/20260907026000_product_spec_cardinality_applicability.sql` | forward SQL | `e8d1e7cb7b2f3c85338632f6e6ac948e2e2b291ddc715d1821b3a0debe692ee7` |
| `supabase/tests/product_spec_cardinality_applicability.sql` | pgTAP de aplicabilidad | `6270150bff7c06f4cced4d0bb584c6df3a37bdff45acd9e443f52d62de030f3e` |
| `supabase/tests/product_spec_row_cardinality.sql` | pgTAP de cardinalidad | `bbecff6fd2b6002e58df6d49ebc326bfff7d2800d608e3e2d5a276d31d94e3bb` |
| `supabase/tests/fixtures/product_spec_row_cardinality.sql` | fixture compartida, 41 casos | `1d1463c78c1bb3eafa5a7be8e0ed82a608265684b5dafd8b60056b6ea56d59c2` |
| `test/unit/product_spec_row_cardinality_test.dart` | prueba Dart | `718850c55b26bdcc4f1ba98bb4db915b17067099074894500bae68d7ae9acf90` |
| `docs/development/product-specs-research-2026-09-05/product-spec-cardinality-applicability-verify.sql` | verificador estricto | `e1ead025b1bacd6ca22d4aff986bc3aa90a6ceee75ec6d46fa45395309ff7592` |

Catálogo `16459826…` y 323 casos `329ad3e5…`, congelados por ti. El cambio que declaraste en la fixture de total cero es consistente con lo que leí: la fila vacía inválida ya no se omite del documento compartido.

## Veredicto

No encontré ningún defecto en el comportamiento del fix. Encontré **dos huecos de cobertura** y **tres límites** que conviene dejar escritos antes del deploy. Ninguno bloquea; el segundo hueco es el que yo cerraría primero.

## Lo que verifiqué, incluidas dos sospechas que se resolvieron a tu favor

**El fix suprime tres códigos, no uno.** Tu mensaje dice que suprime sólo `row_cardinality_pending`. El código suprime además `row_cardinality_conflict` cuando ya hay un `field_applicability` bloqueante del mismo campo, y `row_cardinality_total` cuando la validación escalar ya rechazó el total. Las dos supresiones extra conservan el bloqueo por otra vía, así que el efecto observable es el que describes; lo anoto porque la descripción se queda corta frente al diff.

**Sospecha 1, descartada.** En SQL la supresión del conflicto exige `i->'blocking'='true'` de forma estricta mientras la del total usa `coalesce(..., 'true')`. Parecía una inconsistencia que dejaría la primera sin disparar nunca. No lo es: `field_applicability` se emite con `'blocking', v_applicable is false`, es decir un único código para el caso «no» y para el «desconocido», y la prueba estricta de `blocking` es justamente lo que los separa. Quitar esa estrictez rompería el caso desconocido.

**Sospecha 2, descartada.** Dart busca `{type, integer, range, configuration}` y SQL busca `field_constraint`. Parecían conjuntos distintos. No lo son: `field_constraint` es el código paraguas del validador SQL para tipo, número inválido, positivo, entero, rango, forma de filas, cardinalidad de selects y opción desconocida. La correspondencia es completa.

**Paridad de aplicabilidad, confirmada.** SQL calcula `v_applicable` como `allowed_when` en conjunción con todas las `visibility_rules`; Dart hace lo mismo en `applicabilityFor`, que combina la expresión declarada con la aplicabilidad legada y devuelve `no` si cualquiera es `no`. La aritmética de tres valores coincide en los dos, y la prueba Dart «legacy visibility participates in cardinality applicability» y las dos aserciones finales del pgTAP lo fijan en ambos motores.

**Orden de evaluación, correcto.** En SQL `v_inapplicable` se llena en el bucle de campos, y el append ocurre **antes** del `continue` que salta los campos sin valor conocido. Eso es lo que hace que el caso real —un cable sin ningún valor de puertos— quede suprimido. Si el append estuviera después de ese `continue`, el fix no arreglaría el bug que reportaste.

**Guardas e idempotencia.** El guard previo acepta el MD5 anterior y el posterior, así que reaplicar es seguro; el guard posterior fija sólo el nuevo. Ambos pinnean dueño, `security definer`, volatilidad, `search_path` y ACL. El verificador estricto añade que `anon` y `authenticated` no ejecutan y `service_role` sí, y afirma con `1/case … else 0`, que falla ruidosamente en vez de devolver un falso silencioso.

## Hueco 1 — el pgTAP no tiene ninguna aserción de ausencia

El archivo no contiene ni un `not exists`. `count_pending` sólo cuenta `row_cardinality_pending`, así que la supresión del pendiente sí queda afirmada por conteo, pero las otras dos ramas que el forward cambia en producción no se afirman en SQL:

- **Supresión del conflicto** con aplicabilidad «no» y tabla poblada: el pgTAP afirma que el conflicto **sobrevive** con aplicabilidad desconocida y que la tabla poblada **bloquea** por aplicabilidad, pero no afirma que el `row_cardinality_conflict` duplicado esté ausente. En Dart sí está cubierto por «known inapplicability owns zero plus populated table once».
- **Supresión del total** por `field_constraint`: no hay ninguna aserción en SQL. En Dart la cubre «ordinary scalar validation owns an invalid total without duplicates».

Corrección mínima sugerida: dos `select ok(not exists(...))` sobre `pg_temp.applicability_issues` para esos dos casos. Como el forward toca justamente esas dos ramas y tú corres el conjunto SQL, es la aserción que más rinde antes del deploy.

## Hueco 2 — el verificador estricto no ejercita la rama corregida

La segunda consulta llama al validador con `'{}'::jsonb`. Con valores vacíos ningún discriminante está respondido, así que toda aplicabilidad es **desconocida**, `v_inapplicable` queda vacío y ninguna de las tres supresiones se ejecuta. El verificador prueba identidad, seguridad y que la función corre sobre las plantillas activas; no prueba el comportamiento que motivó el cambio. Tú ya lo rotulas como smoke, así que esto es precisión y no contradicción: significa que la prueba conductual del fix descansa entera en el pgTAP y el Dart locales.

Si quieres que el verificador toque la rama, basta una tercera consulta que evalúe una plantilla con su discriminante puesto en el valor que vuelve inaplicable la colección, y afirme que no aparece `row_cardinality_pending` de ese campo.

## Tres límites, sin acción obligatoria

1. **Alcance del smoke.** Itera las plantillas ligadas en el tenant `5443b130…`. Si `consumer_electronics` no está ligada a ningún producto ahí, la plantilla que originó el bug no se evalúa. No puedo comprobarlo sin base de datos; queda como condición a confirmar en tu readback.
2. **Un código Dart sin gemelo SQL.** Dart suprime el total también ante `configuration`, que emite cuando las reglas numéricas del propio campo no se pueden interpretar. El validador SQL no tiene esa rama. Es metadato malformado que el validador de contrato rechaza aguas arriba, así que es una diferencia acotada y no una divergencia viva.
3. **La aplicabilidad desconocida conserva el pendiente.** Es lo que describes y lo que las pruebas fijan. Vale la pena tenerlo presente como decisión de producto: mientras el operador no responda el discriminante, la ficha pide completitud de una tabla que puede no aplicarle. No bloquea, y la alternativa —suprimir ante lo desconocido— sería peor.

## Corrección conceptual a mi informe de puertos

Tienes razón y lo corrijo aquí, dejando congelado `port-cardinality-independent-review-2026-09-07.md` (`7a5146ab9b93f36d445110d2d3e9eb8e4b0b8768deb9a1426931e3191b2f4ac5`), porque esta ronda me pide escribir un solo archivo.

Escribí que «la cardinalidad no aprieta nada nuevo» porque `unique_by` ya impedía dos filas del mismo puerto. Confundí dos validaciones distintas: `unique_by` define qué cuenta como una ocurrencia y prohíbe repetirla; la cardinalidad **sí añade** una restricción nueva, entre el número de ocurrencias y un total declarado. Sin ella, tres filas distintas con un `ports_count` de 1 pasaban; con ella, bloquean. Son restricciones sobre cosas distintas y la segunda no se sigue de la primera. El resto de aquel informe no depende de esa frase.

## Sobre la propuesta de presencia

Registro tus cuatro objeciones y no las trabajo aquí, ya que las resuelves en paralelo: litros no equivalen a medidas exteriores, un solo extremo no completa un rango, una interfaz declarada no obliga a inventar contraparte, y el ejemplo MIK con Racktime Standit 2.0 no tiene evidencia OEM y no debe usarse como fixture de compatibilidad. Esa última es la que me corrige más de fondo: escribí un par concreto en un campo de caso de usuario, y en este proyecto un par concreto se lee como calce verificado aunque yo lo pusiera de ejemplo.

## Compuertas

No escribí hechos, no abrí llenado y no desplegué nada. Los artefactos anteriores quedan como estaban.
