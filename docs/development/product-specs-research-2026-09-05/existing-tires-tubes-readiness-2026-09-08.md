# Sucesor de las cinco familias de neumático y cámara — ronda 3

**Publicado el 2026-09-16** como `20260916030000_tire_tube_successors.sql` sobre 271
productos, con preimagen fresca idéntica a la de esta ronda; la compuerta de
`tire_tubeless_ready` quedó adjudicada. Ver
[tire-tube-successors-adjudication-2026-09-16.md](tire-tube-successors-adjudication-2026-09-16.md).
Lo que sigue abajo es el estado del candidato al 2026-09-08.

## Estado vigente integrado por Root, 2026-09-08

**Candidato sin activar.** 55 pruebas Dart del formulario, 50 casos SQL con
avance/repetición exacta y ROLLBACK. Ocho declaraciones de alcance ejecutadas en
Dart y SQL reales, con el auditor del repositorio; su conexión a referencias y
al editor sigue pendiente. Las cifras de mutación de las rondas inferiores son
históricas y no se trasladan automáticamente al candidato integrado.

Adopción de 264 productos capturados por API: cero bloqueantes, 808 observaciones
legacy preservadas, ninguna observación activa sin proyectar; los 264 tienen
información pendiente. No se rellenó ni modificó ninguno.

Root corrigió la identidad de aplicación de dosis, retiró la familia duplicada
del miembro de kit, ordenó mínimo/máximo dentro de su propia declaración y
acotó el ejemplo Zipp a su sistema documentado. El detalle y límites abiertos
están en [la revisión de Root](existing-tires-tubes-root-decisions-2026-09-08.md).

Catálogo `b9e30b145346d52489dc807400a56e7dd38788e74a0e0b269c48f2f35412e619`;
casos `7cc47f5df2e152547b3bb0795b3fa6fcd11403bfe88e20bec72010018ea4c9b5`.
La preimagen de publicación del bloque conserva las 19 definiciones compartidas.
Las rondas de Claude que siguen documentan la propuesta y sus correcciones;
este encabezado y la revisión de Root describen el estado vigente.

`tire`, `tube`, `rim_strip`, `tubeless_consumable`, `tubeless_valve`. Candidato
corregido tras la segunda revisión de root. **Sin migración, producción, fill,
asignaciones, SQL, git ni runtime.** Metadata fresca y colisiones de
definiciones publicadas siguen siendo de root.

| Artefacto | SHA-256 |
|---|---|
| `scripts/inventory/compile_existing_tires_tubes_catalog.py` | `029a4cef1fb6a28d21e3f51d9df07d52729eb2184dbd2ab0af8d64b6c312589f` |
| `existing-tires-tubes-catalog-2026-09-08.json` | `f89866960a157d57d038b9e97032d3ddbcb4af5fc91701e5dda16590c3e8eb81` |
| `existing-tires-tubes-cases-2026-09-08.json` | `e47ae36b02779119414b1303c8223898b1e553852b907af5b0704fcf799ff7d3` |

Entradas congeladas verificadas por hash en cada corrida; compilación
reproducible. 5 plantillas · 39 definiciones (19 vivas reutilizadas, 20 nuevas)
· 53 usos de campo · **47 casos verdes** y **5 casos pendientes** con su
resultado requerido.

## Primero: una afirmación mía que era falsa

En el bloque de piñonería escribí que `ProductSpecRelation` «sólo se resume en
prosa» y que **faltaba el evaluador**. **Es falso.**
`ProductSpecRelation.evaluate` existe en
`lib/modules/inventory/models/product_spec_relation.dart:78-132`, y su paridad
`spec_relation_assess_internal_v1` en
`supabase/migrations/20260906180000_product_spec_scoped_relations.sql:174`. Los
50 casos de `test/unit/product_spec_relation_test.dart` pasan y cubren los
cuatro veredictos.

El error fue de método: busqué «relation» en el **consumidor**
(`product_spec_contract.dart`) y no en el modelo, y de no encontrarlo ahí
concluí que no existía. Lo que falta es que el veredicto llegue a la validación
de la ficha — **integración, no otro motor**. Root tiene razón y no escribo
motor. El evaluador ya distingue lo que yo iba a «proponer»: OR entre
alternativas, AND dentro de cada fila, exclusiones que estrechan, desconocido
preservado, y `outsideDeclaredScope` con el comentario explícito de que no
coincidir «is only outside this declaration, never a physical incompatibility
proof».

La corrección equivalente en el archivo de piñonería no la hice: ese es un
quinto archivo y esta ronda me limita a estos cuatro. Queda pedida.

## R-1 · La dosis y la cantidad vendida tienen dueños distintos

Root: 120 ml de dosis con un frasco de 60 ml es **legítimo** —se usan dos
envases—. Mi desigualdad `dose <= volume` certificaba una regla falsa, y que
matara un mutante no la volvía verdadera.

- La desigualdad **se retira**.
- La dosis pasa a `sealant_dose_recommendations`: una fila por **aplicación
  documentada**, con su dosis, su documento y su URL, llaveada por la
  aplicación. Dos documentos con dosis distintas para la misma aplicación son
  un conflicto que alguien resuelve, no dos filas.
- El escalar `recommended_dose_ml` sale de la ficha. Era una definición nueva y
  **no publicada**: no hay lecturas que conservar, y lo digo en vez de
  suponerlo.
- `ttx_a_dose_larger_than_the_bottle_is_legitimate` afirma ahora lo contrario de
  lo que afirmaba antes: 120 ml con un frasco de 60 **no produce incidencia**.

## R-2 · Perfil y método no identifican una llanta

Root: dos modelos pueden compartir «sin gancho» y «tubeless» con anchos y
límites distintos, y mi llave declaraba duplicada la segunda configuración
válida.

- La fila gana identidad real: `scope_kind` (modelo y edición · familia
  declarada por el fabricante · norma y edición citadas · desconocido) y
  `scope_identity`, ambas obligatorias.
- La llave pasa a `(scope_kind, scope_identity)`. Perfil, método, anchos y
  límite son **parámetros de ese alcance** y viajan con él.
- La URL **no** entra en la llave: otra fuente del mismo alcance no crea otro
  objeto. `ttx_another_url_for_the_same_scope_is_still_one_scope` lo bloquea, y
  el mutante `configkeyurl` —que mete la URL en la llave— lo mata.
- `ttx_two_rim_models_sharing_profile_and_method_are_two_rows` es el caso que
  root pidió: dos modelos con la misma clasificación genérica, ambos válidos. El
  mutante `configkeycoarse`, que restaura la llave anterior, lo mata.

## R-3 · Una observación de taller no es una declaración del SKU

«Montaje verificado en el taller» **sale** de `claim_basis`. Quedan las tres
bases documentales y el desconocido. La observación se conserva con su dueño de
inspección de unidad; cambiarle la etiqueta a la procedencia no le cambia el
alcance, y por ella no se habilita la compatibilidad de todas las unidades del
SKU.

## R-4 · Los límites que le atribuí al motor, adjudicados

Van en `adjudicated_limits`. **Ninguno sobrevive como carencia del motor, y dos
eran errores míos de dominio.**

**L-1 — retirado.** Confundí tres magnitudes. La **presión máxima declarada del
neumático** vive en `tire_general_max_pressures`. El **límite del sistema o del
modelo** es de una rueda concreta con su edición —Zipp lo enuncia para «Zipp TSS
wheel and tire systems», no para la palabra *hookless*—. Y la **presión real de
uso** es de un montaje, que no es un hecho del SKU en ninguna de estas fichas.
Una cifra alta en la primera **no prueba** un montaje por encima de la segunda:
son afirmaciones sobre objetos distintos. Extender Zipp y ENVE a todo hookless
era una inferencia mía, no lo que dicen. Lo que faltaba era la distinción, y
ahora la lleva la identidad de alcance. `ttx_a_tire_max_and_a_system_limit_are_two_objects`
pone 100 psi impresos junto a un límite de 72 psi de un modelo con nombre, y
**no hay contradicción**.

**L-3 — retirado.** Es cierto que un par ordenado no compara bar contra psi, y
está bien que no lo haga: dos autoridades en unidades distintas no son
automáticamente datos contradictorios. Pedir una conversión era pedirle al motor
que adjudicara un conflicto que puede no existir.

**L-2 — resuelto dentro del encargo.** No hacía falta que root migrara nada:
clonar hacia una clave acotada ya estaba autorizado. `tubeless_kit_members` está
acotada a `tubeless_consumable`, con llave `(componente, familia, identidad del
modelo)` — la URL no es identidad. Dos modelos distintos del mismo rol son dos
filas (`ttx_two_models_of_the_same_role_are_two_members`); el mismo miembro
documentado dos veces **bloquea**
(`ttx_the_same_documented_member_twice_blocks`). La definición publicada
`kit_members` se conserva **retirada** en esta ficha: ni la global ni sus datos
se tocan.

**El desconocido de la válvula — resuelto por semántica, no por compuerta.**
Root señaló que abrir permisos para que un mutante fuera observable no es razón
de producto, y tenía razón. `valve_type` publicada deletrea «Desconocido» a
secas, que `hasKnownSpecValue` no reconoce como ausencia
(`spec_rule_evaluator.dart:5-13`), así que ahí una ignorancia declarada
**prohibía** el campo dependiente. La ronda anterior arregló el síntoma abriendo
la aplicabilidad. Ahora se arregla el vocabulario: `valve_standard`, acotado a
cámara y válvula tubeless, con el mismo dominio, «Otra», y el desconocido que el
motor entiende. La publicada queda **retirada** en ambas fichas, y las compuertas
que la leían —incluida la del núcleo desmontable, que sólo aplica a Presta— se
repuntan al sucesor. Con eso, condicionar la **aplicabilidad** vuelve a ser
correcto: desconocido → pendiente, ausente → pendiente, conocido → exigido.

## Ronda 3 · Dos reglas de dominio que yo había certificado como falsas

Root señaló dos, y las dos eran mías. Fui a las fuentes antes de tocar nada.

### El núcleo desmontable no se deduce del tipo de válvula

La propuesta congelada abría `valve_core_removable` **sólo para Presta**, y yo
la repunté al sucesor sin comprobarla. Peor: escribí un caso que **bloqueaba** un
núcleo desmontable en una Schrader, convirtiendo una fixture sintética en
certificación de una regla falsa.

**Park Tool, VC-1 Valve Core Tool**, abierta y leída: la herramienta saca e
instala «Schrader valve cores» y «Removable Presta valve cores», y la propia
ficha aclara «(not all Presta valve cores are removable)». Para Dunlop u otras
normas la página **no dice nada** — ABSENT — así que aquí no se afirma nada en
ninguna dirección.

- La compuerta **se retira**: el núcleo desmontable es una propiedad de la
  válvula, no de su norma.
- La afirmación pasa a exigir su documento (`prerequisites` sobre la evidencia):
  se lee del producto, no se infiere.
- El caso falso se borró. En su lugar hay cuatro: Presta desmontable, Presta
  fija, **Schrader desmontable** y Dunlop, más el que exige el documento. El
  mutante `corepresta`, que restaura la regla vieja, mata dos de ellos.

### No-listado no es exclusión, y tampoco es aprobación

Mi caso pendiente declaraba `excluded` para una llanta TSS que no aparece en la
lista. **Zipp dice lo contrario**, y lo leí en la segunda pasada: «This list is
not exhaustive of all TSS compatible tires and is provided as a convenience to
help guide your tire purchases», y «If you are interested in a tire that is not
listed here, you should check with the tire manufacturer or reference their
website». Ausencia de declaración, no prohibición.

La prohibición **expresa** que sí existe no es una lista: es una regla con
parámetro. «Zipp TSS rims are NOT compatible with tires that require a minimum
pressure higher than 5 bar (72 psi).» Esa cifra no estaba en la ficha, así que
la regla no era evaluable: `tire_general_max_pressures` gana la columna
`min_pressure_value` —junto a su unidad y su alcance, donde ya viven las demás—
y la definición se relabeló a «Presiones declaradas del neumático».

La reclamación pendiente quedó así, y separa las dos cosas:

| Caso | Configuración | Veredicto requerido |
|---|---|---|
| `ttp_a_listed_tss_rim_is_supported` | hookless, listado, mín. 40 psi | `supported` |
| `ttp_an_unlisted_tss_rim_is_outside_the_declaration` | hookless, no listado | `outsideDeclaredScope` — **ni `excluded` ni `supported`** |
| `ttp_a_tire_needing_more_than_the_ceiling_is_excluded` | hookless, mín. 80 psi | `excluded` por la regla expresa |
| `ttp_an_unanswered_minimum_pressure_stays_unknown` | hookless, sin mínima | `unknown` |
| `ttp_a_tubular_rim_is_outside_the_declaration` | tubular | `outsideDeclaredScope` |

**Cómo están verificados, con precisión.** La forma de la reclamación pasa una
comprobación estructural que replica `ProductSpecRelation.fromJson` y
`SpecRelationRow.fromJson` (claves, condiciones no vacías, fuentes como URL
absoluta, ids únicos entre alternativas y exclusiones, comparaciones sólo sobre
`decimal`): **aceptada**. Los cinco veredictos están **trazados leyendo**
`evaluate` (`product_spec_relation.dart:78-132`), **no ejecutados**: el test de
relaciones lee una fixture de ruta fija y compararla con el SQL embebido, así que
no puedo apuntarlo a mi archivo sin tocar archivos que no son míos. Ejecutarlos
es un paso de root, y lo digo en vez de presentarlos como corridos.

### Revisión crítica de mis otras compuertas

Root pidió no dar por buenas las suyas ni las mías. Encontré tres más que
sobraban, todas del mismo vicio: **deducir una medida física de un token de
tipo**.

| Compuerta | Veredicto | Por qué |
|---|---|---|
| `rim_maker_lists_this_tire` permitida sólo en hookless | **retirada** | Cualquier fabricante de llanta puede publicar una lista. La *exigencia* sí es de hookless, y eso sí está en la fuente. |
| largo de válvula colgado de la norma | **retirado** | El largo es una medida de la pieza que se tiene en la mano; se exige siempre, se sepa o no la norma. |
| forma de la base colgada de la norma | **retirado** | Igual. |
| ancho de la tira colgado del material | **retirado** | Igual; el material no es requisito para medir. |
| diámetro del agujero colgado de la norma | **retirado el permiso**, se conserva el documento | Es una declaración sobre la llanta, no una medida de la válvula. |
| `tire_tubeless_ready` colgada del tipo de talón | **conservada, y declarada sin fuente propia** | Viene de la propuesta congelada y es sobre la aplicabilidad de un concepto, no una inferencia física. No la verifiqué con una cita; queda dicho. |

Las llaves las revisé de nuevo y las sostengo: `(scope_kind, scope_identity)` por
R-2; `(componente, familia, identidad)` porque dos modelos del mismo rol son dos
piezas; `(aplicación)` porque otra fuente no crea otra aplicación; y `(BSD)`
porque Sheldon dice que ese número decide el calce.

## Pruebas

```
flutter test test/unit/product_spec_integrated_catalog_test.dart \
  --dart-define=SPEC_CATALOG_INPUT=…/existing-tires-tubes-catalog-2026-09-08.json \
  --dart-define=SPEC_CATALOG_CASES=…/existing-tires-tubes-cases-2026-09-08.json
→ +52: All tests passed!

flutter test test/unit/product_spec_relation_test.dart → +50: All tests passed!
```

5 de metadatos y 47 casos. **Batería de mutación: 26 mutantes, 26 muertos.** Un
mutante de la ronda anterior —`listinggate`— quedó **obsoleto**: ponía en
`always` lo que ahora es el estado entregado, así que no mutaba nada. Se retiró y
se reemplazó por su inverso con sentido, `listinghooklessonly`, que sí muere.

## Paquete del publicador

```
familias 5 · reutilizadas 19 · nuevas 20 · parches 30 · product_writes false
tire 4→19 · tube 6→21 · rim_strip 2→12 · tubeless_consumable 3→11 · tubeless_valve 2→12
```

Ninguna plantilla pierde un campo publicado; `valve_type` y `kit_members` siguen
presentes con rol `legacy`.

## Pendientes y límites, dichos

1. **La integración del evaluador de relaciones a la ficha** — de root/motor.
   Sus cinco casos están arriba con el resultado requerido, y **trazados, no
   ejecutados**.
2. **`tire_tubeless_ready` sobre el tipo de talón no tiene fuente mía.** Es la
   única compuerta heredada que conservo sin verificar; si root quiere, se cae.
3. **Dunlop y otras normas de válvula**: la fuente de Park no las menciona. El
   contrato no decide por ellas, y eso es deliberado.
4. **Las relaciones declaradas viven en `product_spec_references.claims`**
   (§4.1). Mi candidato no crea ninguna referencia: la reclamación pendiente es
   sintética y de forma.
5. **Root debe abrir Zipp, ENVE y Park** antes de aceptar estos límites; mis
   citas son textuales pero no suplen esa lectura.
6. **No corrí SQL.** La paridad servidor/Dart es readback de root.
7. **La corrección de mi afirmación falsa sobre el evaluador sigue sin hacerse en
   el archivo de piñonería**, que es un quinto archivo. Queda pedida.
