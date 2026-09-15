# Revisión del candidato de movilidad y accesorios

2026-09-07. Revisión independiente, sin editar nada del candidato. Sólo lecturas de artefactos y
código; sin base de datos, runtime, git ni subagentes.

| artefacto | SHA-256 |
|---|---|
| `compile_mobility_accessories_catalog.py` | `ba38a41847288e8f60ac0b3736a10797cde4fb41f36944a589ac6d3a26421932` |
| `mobility-accessories-catalog-2026-09-07.json` | `cd477af08f8c39225d8abef182f3ce326145b0be7d1cfe043d579132838e8a44` |
| `mobility-accessories-cases-2026-09-07.json` | `1ca9ec14aa994014d89ae30a85b86beaa22c5471359197b3ef41288d4e933559` |

14 plantillas, 122 definiciones, 163 usos, 131 casos: coinciden con lo que reportaste.
`input_sha256` apunta al catálogo `16459826…` y a los casos `329ad3e5…`, los dos congelados.

## Dictamen

**El candidato es correcto. Apruébalo.** Las cinco decisiones están implementadas y verificadas, la
cobertura de casos cubre los tres ramos —positivo, negativo y desconocido— en cada una, y **no hay
deriva**: las 9 definiciones que este candidato comparte con lo ya publicado son idénticas en `id`,
`label`, `data_type`, `unit`, `allowed_values` y `validation_rules`.

Un solo defecto accionable, y es de la publicación que estás preparando, no del contenido: **§6**.

## 1. Me equivoqué en DL-5, y así lo verifiqué

Pediste que comprobara con el motor real mi afirmación de que `legacy` no impide llenar. **Es falsa.**
`role: legacy` es la retirada efectiva, en seis sitios:

- `lib/modules/inventory/models/product_spec_contract.dart:174-179` — las claves legacy se **eliminan
  de `values`** antes de evaluar nada.
- `:237` — el bucle por campo hace `continue` sobre legacy.
- `lib/modules/inventory/services/spec_engine_service.dart:196` y `:203` — legacy queda fuera de
  `rowConditions` y de `coherence`.
- `:486` — **`buildFactPayload` lo salta: un valor legacy nunca llega a los hechos.**
- `lib/modules/inventory/pages/product_form_page.dart:7803-7809` — se renderiza sólo lectura con «Se
  conserva para revisión y no se usa para afirmar compatibilidad»; `:1553` lo oculta si está vacío.

Así que nunca hubo el doble dueño que reporté: una bomba no podía llevar `max_pressure_psi = 160` a
los hechos junto a una fila de 11 bar. Generalicé desde una sola línea de la prueba de cardinalidad
—«legacy total is not an available endpoint»—, que sólo hablaba de extremos de coherencia. Tu frase
«el legado se conserva y no se transforma en dueño canónico» es exactamente lo que hace el código.

**Consecuencia para lo que implementaste.** `allowed_when: never` sobre un campo que ya es `legacy`
es **inerte**: la aplicabilidad no llega a evaluarse. No hace daño y documenta la intención, pero no
es la protección. Tu propio caso `rv_pump_legacy_scalar_not_canonical` —`forbidden_issue_fields:
["max_pressure_psi"]` con `expected_blocking: []`— pasa igual con el `never` y sin él, así que
tampoco lo demuestra. Lo que importa que quede escrito para la próxima retirada: **`never` bloquea,
`legacy` retira**, y no son intercambiables. Retirar poniendo `never` y dejando el rol vivo no
retiraría nada.

## 2. Tus dos correcciones a mí son correctas

**DL-1, la bomba de suspensión.** Yo propuse excluirla del facet. Tú la mantuviste, y tienes razón:
no tengo ninguna fuente que prohíba una bomba de suspensión con capacidad de CO2, y excluirla habría
sido una prohibición inventada — justo lo que la regla prohíbe. El facet queda en los cinco formatos
no dedicados, la tabla se abre por la disyunción tipo-dedicado-o-facet, y el facet **no** se permite
en los tipos dedicados, de modo que la contradicción que señalé ya no es expresable. Verificado en
`ma_dedicated_has_one_capability_owner`: `field_applicability` bloqueante sobre el facet.

**DL-3, los dos ejes.** Mi token único mezclaba qué se mide con cuántas unidades se miden. Un par de
alforjas puede ser «Sólo carga» **y** «Una unidad del conjunto» a la vez, y mi lista no podía decirlo.
`volume_basis` y `volume_scope` como prerrequisitos de `volume_l` es la forma correcta, y los
prerrequisitos son no bloqueantes, que era el comportamiento que yo pedía para el caso negativo.

## 3. Lo que verifiqué implementado

**MA-1.** `wheel_size_declarations`, `used_by` las cuatro familias, con las tres representaciones
**excluyentes de verdad**: cada columna de dato lleva `allowed_when` *y* `required_when` atados a su
`kind`, no sólo `required_when`. Los cuatro contratos son idénticos en ese bloque (mismo md5). Los dos
selectores nominales desaparecieron del catálogo.

Busqué primero `rows_ordered_pairs` en el contrato y no estaba; el sitio canónico es
`validation_rules.rows_schema.ordered_pairs` de la definición, y ahí sí está:
`[["min_in","max_in"]]`, junto con las otras seis del candidato. Corrijo mi propia búsqueda antes de
que quedara como hallazgo.

Casos: `ma_wheel_reversed_*` → `row_shape` bloqueante en las cuatro familias; `ma_wheel_mixed_axis_*`
→ `row_field_applicability` bloqueante. El helper dice que no convierte ni certifica montaje.

**DL-2.** «Riñonera / bolso de cintura» añadido; `reservoir_included` colgado de cuatro tipos —no de
Cubre-mochila—; `reservoir_l` exige `reservoir_included = true`. No agregaste la capacidad de
alojamiento sin fuente, que era la advertencia. `ma_cover_is_not_reservoir` es un caso que yo no pedí
y que cierra el flanco del cubre-mochila.

**MA-3.** `tool_pressure_specifications` propia de `workshop_tool`, con vocabulario de herramienta y
sin las categorías de bomba. La fuente que aportaste es textual: Park Tool INF-2 declara «Pressure
gauge range: 0–160 psi (0–11 bar)», y es **escala de manómetro**, no máximo de trabajo, como dijiste.
Cierra el límite honesto que yo había dejado en DL-4: ahora hay una fuente de herramienta, no sólo de
bomba. `ma_tool_printed_units` guarda las dos unidades como dos filas bajo «Fondo de escala del
manómetro», sin convertir.

Dos observaciones, ninguna un defecto. El 0 de «0–160» no se pierde: «fondo de escala» nombra
exactamente lo que 160 es, y el origen de una escala no es un dato declarado aparte; si quieres
literalidad, `conditions` lo admite verbatim. Y la tabla **no** tiene `unique_by` ni `ordered_pairs`,
y así debe quedarse: dos filas de la misma magnitud en unidades distintas son justo el caso INF-2, y
un `unique_by` las mataría.

**Cobertura.** Busqué los tres ramos desconocidos esperando encontrarlos ausentes y están todos:
`ma_volume_unknown_*` con `prerequisite` no bloqueante, `ma_reservoir_inclusion_unknown` y
`ma_pump_capability_unknown`.

## 4. La frontera de criterios (MA-2)

`supplyNeedCriterionFieldsOf` está bien puesta y es la misma en los dos archivos —cinco llamadas en el
editor—. Tres cosas que confirmo porque son las que se rompen solas:

- `applicabilityFor(field, const {}) != SpecTruth.no` conserva lo desconocido. Con el mapa vacío, una
  condición sobre un campo ausente da `unknown`, no `no`, así que lo único que se excluye es
  `kind: never`. Es la lectura conservadora correcta.
- `roleFor != 'legacy'` — coherente con §1.
- `carryForwardUnexpressedPredicates` arrastra el predicado cuyo campo ya no es expresable y salta el
  que sí lo es, de modo que borrar un criterio visible sigue siendo posible y perder uno oculto no.
  `expressibleFields` combina el filtro con `field.isVisible(currentValues)`, así que un criterio
  escondido por visibilidad se conserva.

Un detalle menor, sin efecto hoy: `scalarTypes` no incluye `range`, que sí está en el `check` de
`spec_definitions`. No hay ninguna definición `range` en el catálogo congelado (0 de 711) ni en el
candidato (0 de 122), así que la omisión es inerte — pero es un estrechamiento silencioso que ninguna
prueba puede atrapar, precisamente porque no existe una definición `range` contra la que probar.

## 5. Sin deriva sobre lo ya publicado

Comparé las 9 definiciones que el candidato comparte con el primer packet —las 8 reutilizadas más
`spec_evidence_source`— en `id`, `label`, `data_type`, `unit`, `allowed_values` y `validation_rules`:
**cero diferencias**. El candidato no muta nada global.

## 6. Defecto accionable: `origin: new` sobre 8 definiciones ya publicadas

El candidato marca `origin: "new"` en 121 de 122 definiciones, y sólo `spec_evidence_source` como
`existing`. Pero ocho de esas «nuevas» ya están publicadas y son globales: `color`, `material`,
`kit_members`, `power_source`, `mount_diameter_min_mm`, `mount_diameter_max_mm`, `volume_ml` y
`width_mm`.

Ya me dijiste que ese `origin` es histórico, y por el contenido no pasa nada: sin deriva, el bucle de
publicación las encontraría por `id`, compararía y las saltaría.

**El problema es el compilador de publicación.** El del primer bloque decide con `origin`:

- `if definition['origin'] == 'existing': continue` para no insertarlas, y
- `if set(reused) != {k for k, d in definitions.items() if d['origin'] == 'existing'}: raise
  ValueError('Definition collision or missing preimage')`.

Con este catálogo, la preimagen viva devolverá **9** definiciones existentes y el catálogo declara
**1**, así que esa comprobación aborta. Es ruidoso y no destructivo, pero te va a costar la corrida
justo cuando estés publicando.

*Cambio mínimo:* que el compilador de publicación derive «ya publicada» **de la preimagen**, no de
`origin`. `origin` es una etiqueta de investigación sobre el catálogo; lo que la publicación necesita
es un hecho de producción. Marcar las ocho a mano funciona igual, pero deja el mismo desfase esperando
al bloque siguiente.

---

Compuertas del candidato, sin cambio y verificadas en el propio artefacto: `fill_allowed`,
`compatibility_rules_integrated`, `all_product_assignment_review_complete`,
`all_family_domain_review_complete` — todas `false`.

---

# Dictamen de la publicación: **aplicar**

Segunda pasada, 2026-09-07, sobre los cuatro artefactos de publicación. Sólo lecturas; sin base de
datos, runtime, git, código ni subagentes.

Los cuatro SHA-256 que reportaste **coinciden** con los que recalculé: migración
`3412bcba5b0298dba58f3b41cb3d3dc397ed2bb0fddb1f81b273e23f47b5289d`, verificador
`fb619208d15ba7ad125758a3daac9259269968f5f400cd48bd787de951e1dbdb`, paquete
`56af15d0cb8b83f6ec59c62ce71b4095ae500831d617478a88cf87d8266e6a6a`, preimagen
`2c1bc85e8174aaee2a3b510a2ef04ca7ca96529d81d772c821bf4785c6e99945`.

## Lo aplicado sigue intacto, y el generador es el mismo

Los tres artefactos de las 12 están **byte a byte** como los hasheé antes de que se aplicaran:
migración `169aa2ec…`, verificador `e0c0b968…`, paquete `313d7fe6…`. No fueron reescritos.

Y lo comprobé por el otro lado, que es más fuerte: quitando la cabecera de dos líneas y el documento
incrustado, **las dos migraciones son idénticas**, y los dos verificadores también. Es el mismo
generador, así que la lógica que revisé y aprobaste para las 12 —igualdad JSONB por claves
administradas, huella de las cuatro tablas incluida `category_tech_mappings`, pin del motor
`ac0738d5…`, comprobación de homónimos— viaja verbatim a este bloque, sin una variante que revisar de
nuevo.

## §6 cerrado, y cerrado bien

`reused` sale de `before['existing_definitions']`: **la preimagen viva es la autoridad**. Y la
relación con el `origin` histórico es la correcta —`{k : origin == 'existing'} ⊆ set(reused)`—, así
que la etiqueta sólo puede quedarse corta y nunca aborta la corrida ni cuela una definición que la
preimagen no conozca. Es lo que faltaba, resuelto en la dirección buena.

La preimagen se capturó a las 23:11:58Z, después de aplicar las 12 a las 22:34Z, así que las ocho
filas recién compartidas son las de después de esa publicación.

## Las nueve compartidas: leídas, nunca escritas

- 113 nuevas + 9 reutilizadas = 122, sin un solo solapamiento de clave entre los dos conjuntos.
- **Cero filas de opción apuntan a una definición reutilizada.** Éste era el riesgo más alto del
  bloque —`color` la usan 37 familias y `kit_members` 23— y está limpio: el vocabulario global
  publicado no se extiende.
- La comparación es total, no parcial: las filas de la preimagen traen 18 campos más `options`, que
  son exactamente las 18 columnas de `spec_definitions`, así que
  `to_jsonb(d) is distinct from wanted-'options'` es igualdad de fila completa. El mecanismo ya se
  probó en producción a las 22:34Z con `spec_evidence_source`.
- Y los guardas de compilación son más estrictos de lo que yo habría pedido: la compartida debe ser
  global (`tenant_id is not None` → error), coincidir en las siete columnas de identidad, y **cada una
  de sus opciones debe ser global y estar activa**. Ese último es mi Δ4 del delta anterior —desactivar
  una opción citada rompe la lectura de la familia entera con 42501— convertido en comprobación
  mecánica, con el motivo escrito en el mensaje de error.

## Integridad medida sobre los 514 registros

| comprobación | resultado |
|---|---|
| campos que apuntan a una definición desconocida | 0 |
| campos que apuntan a una plantilla desconocida | 0 |
| ids de campo repetidos | 0 |
| pares (plantilla, definición) repetidos | 0 |
| ids de opción repetidos | 0 |
| pares (definición, código) repetidos | 0 |
| códigos que violan `spec_definition_values_code_shape` | 0 |
| solapamiento de clave de plantilla con las 12 aplicadas | 0 |
| solapamiento de clave o de id de definición con las 12 | 0 |
| `tenant_id` distinto de null | 0 de 514 |
| conjunto de claves distinto de su lista de insert | 0 en las cuatro tablas |

El alcance global es consistente con `spec_reference_global_scope_internal_v1` y con las 12 ya
publicadas. El verificador lleva los dos bloques: el documento y los 131 drafts.

## Dos notas de operación, ninguna bloquea

**La comparación de las nueve incluye `updated_at`.** Si algo tocara una de esas filas entre la
captura de las 23:11Z y el apply, la migración aborta con `Publication drift in spec_definitions`.
Falla cerrado, que es lo correcto — pero conviene saber de antemano que ese aborto sería una señal de
**preimagen rancia**, no de corrupción: se vuelve a capturar y se recompila.

**ND-5 sigue igual y sigue siendo tu decisión.** Las 14 entran con `is_active: true`, así que la
recuperación documentada en la cabecera —desactivar— es ejecutable sin escrituras de producto sólo
hasta la primera ligadura; después exige desligar. Idéntico a las 12, y las compuertas del paquete
siguen en `false`: `product_writes`, `fill_allowed`, `mechanical_approval`.

**Aplica.**
