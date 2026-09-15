# Patillas, roldanas y guías: candidato sin aplicar — 2026-09-08

**Propuesta histórica de Claude.** El candidato vigente incorpora correcciones
de alcance del peso, identidad y declaraciones por ocurrencia en la
[adjudicación de Root](existing-drivetrain-service-parts-root-decisions-2026-09-08.md).
Las pruebas y limitaciones de esta propuesta se conservan como historial.

Sucesor local para las tres originales `derailleur_hanger`, `derailleur_pulley`
y `chain_guide`. **No aplicado.** Sin escrituras de producción, migración,
publicación, asignaciones ni llenado. Este documento contiene sólo agregados,
metadatos y ejemplos OEM públicos.

## 1. Entradas fijadas y salida

| entrada | sha256 |
|---|---|
| `all-family-port-cardinality-integrated-2026-09-07.json` | `16459826…fadf15` |
| `all-family-port-cardinality-cases-integrated-2026-09-07.json` | `329ad3e5…3716d7` |
| `existing-drivetrain-service-parts-preimage-2026-09-08.json` | `84cbb1c3…607cb3c` |

La preimagen trae diez definiciones publicadas y 33 asignaciones efectivas:
**23 patillas, 7 roldanas y 3 guías**. Salida: 3 plantillas, 33 definiciones,
35 usos de campo, **40 casos ejecutables y 6 pendientes**. El compilador es
determinista y el `catalogue_sha256` de los casos coincide con el catálogo.

**Las diez definiciones publicadas se reutilizan sin una sola diferencia** de
`id`, rótulo, tipo, unidad, dominio ni reglas, comparadas campo a campo contra
la preimagen. Las 23 definiciones nuevas tienen alcance de familia.

## 2. Los tres ejes que separa el candidato

Cada familia distingue **la pieza u ocurrencia física**, **cómo se monta** y
**qué declara un documento** sobre un cuadro o un cambio. Las tres tablas de
declaración comparten una misma forma: cada fila se identifica, elige su
alcance —modelo documentado o interfaz/estándar documentado— y lleva su
documento o envase, con URL tipada opcional. Cuando la fuente no enumera
modelos se declara la interfaz; **no se inventa un nombre de cuadro para llenar
una celda**, y un año ausente en la fuente se queda ausente.

## 3. Patilla

`hanger_interface` se retira a legacy y se sustituye por **dos** campos, porque
mezclaba los dos extremos de la pieza:

- `hanger_frame_interface` — cómo se une al cuadro.
- `hanger_derailleur_interface` — qué recibe el cambio.

SRAM lo sostiene: UDH **es una patilla física** sobre una interfaz
estandarizada del cuadro, y un cambio **Full Mount reemplaza esa patilla**
montándose al cuadro. Por eso «Full Mount» no es una opción de esta ficha: si
está, no hay patilla. Queda como pendiente explícito.

El código del fabricante deja de ser identidad: pasa a declaración, deja de ser
obligatorio y su ayuda dice que el modelo y el MPN del producto viven en su
ficha de identidad. **No se crea un segundo almacén de identidad**, y la
observación publicada se conserva. Wheels Mfg lo justifica con dos referencias
públicas: `DROPOUT-25` y `DROPOUT-70` se sujetan ambas con **un perno M8** y
mantienen códigos y listas de compatibilidad distintos; el perno no identifica
la pieza. En esa misma fuente hay marcas listadas **sin año**, que es la razón
de que el año siga siendo opcional.

## 4. Roldana

Se sustituyen los tres selectores no publicados que mezclaban conceptos:

- **posición**: `Par` deja de ser una posición y pasa a ser el contenido del
  envase. Un par puede ser **dos piezas iguales o dos repuestos**; el candidato
  no deduce de él una guía superior y una tensión. Park documenta que la
  superior guía y la inferior tensa, y el candidato conserva esa distinción
  **sólo cuando la fuente la declara**, con un tercer valor explícito para
  cuando no lo hace. En la población, **las tres referencias de par declaran un
  único número de dientes**, que es exactamente el caso de dos piezas iguales.
- **apoyo**: se separan `construcción` (buje, rodamiento de bolas, otra) y
  `material de los elementos` (acero, cerámico, otro). **Cerámico no es una
  construcción alternativa a un rodamiento**: es el material de sus elementos,
  y un buje no tiene elementos, así que ahí el material queda prohibido.
- **ancho**: se separan `perfil de dentado` (narrow-wide u otro), las cotas
  físicas —diámetro exterior, ancho, alojamiento— y las velocidades declaradas
  por la fuente. **El ancho no se deriva de las velocidades** y las velocidades
  son una declaración con procedencia, no una equivalencia universal.

Un envase individual usa los escalares; un par usa `pulley_units`, donde cada
ocurrencia lleva identidad, posición declarada, dientes, apoyo, perfil, cotas y
su fuente. La cantidad documentada se compara con sus filas mediante la
cardinalidad ya existente: una sola pieza deja el par **pendiente**, y repetir
una identidad bloquea.

## 5. Guía de cadena

- **Montaje**: el selector publicado se retira a legacy y el montaje pasa a una
  tabla de ocurrencias. Motivo medido: **una de las tres guías de la población
  documenta dos estándares en su propio título**, y el dominio publicado es de
  un solo valor y no incluye ISCG-03. Tener los anclajes tampoco certifica un
  cuadro.
- **Exclusiones**: tabla propia con la misma forma de declaración, por modelo y
  generación **o por clase de cuadro**. OneUp publica exclusiones de ambos
  tipos para su Bash Guide ISCG05 V2 —modelos y generaciones concretos, y
  también clases como cuadros de pivote alto y e-bikes—.
- **Contenido**: `chain_guide_included_parts` guarda cada pieza incluida con su
  función, su rango de plato propio, **cuál viene instalada de fábrica** y su
  peso publicado. La misma fuente lo hace explícito: incluye tres placas
  (28-30T, 32-34T, 36T), la de 32-34T viene instalada, y sus pesos publicados
  son 90, 105 y 110 g. La **capacidad total declarada** (28-36T) se conserva
  aparte y su ayuda dice que es la unión de esas piezas, no una garantía de que
  cualquiera sirva.
- **Línea de cadena**: se añade `chain_guide_chainline_adjustment_mm` para el
  **recorrido de ajuste** y un `chain_guide_chainline_datum` que es
  prerrequisito de la línea de cadena instalada. La ficha de OneUp rotula
  «Chainline: 7,5 mm adjustment» y sus instrucciones lo realizan **con
  separadores**: son 7,5 mm de recorrido, no una línea de cadena de 7,5 mm.
  Sin datum, la cifra queda pendiente y no se compara con otra ficha.

Las cotas OEM pertinentes se conservan aunque hoy no las consuma otro módulo:
peso por configuración incluida, rangos por pieza y recorrido de ajuste.

## 6. Pruebas

```bash
.fvm/flutter_sdk/bin/flutter test test/unit/product_spec_integrated_catalog_test.dart \
  --dart-define=SPEC_CATALOG_INPUT=$PWD/docs/development/product-specs-research-2026-09-05/existing-drivetrain-service-parts-catalog-2026-09-08.json \
  --dart-define=SPEC_CATALOG_CASES=$PWD/docs/development/product-specs-research-2026-09-05/existing-drivetrain-service-parts-cases-2026-09-08.json
```

Resultado: **43 verdes** (3 de metadatos + 40 casos).

**Mutación enfocada a los invariantes nuevos: 15 mutantes, 15 muertos.** Cada
compuerta, llave y exigencia introducida es observable por al menos un caso: el
alcance de las declaraciones en sus dos sentidos, la unicidad y el documento de
cada tabla, las compuertas de envase individual y de par, el material de
elementos en escalar y en fila, la cardinalidad del par, la exigencia de
montaje, el orden del rango por pieza, el prerrequisito de datum y el orden de
la capacidad declarada. No se corrió una ronda exhaustiva ni se auditó otra
familia.

## 7. Pendientes honestos

| id | resultado exigido |
|---|---|
| `hanger_extender_titles_await_assignment_review` | `assignment_review_required` |
| `hanger_and_pulley_identity_codes_belong_to_the_product` | `identity_pending` |
| `full_mount_derailleur_is_not_a_hanger_variant` | `outside_this_family` |
| `pulley_rotation_and_profile_need_the_exact_manual` | `unknown_without_model_scoped_manual` |
| `chain_guide_line_wide_interchange_is_not_a_sku_fact` | `unknown_without_model_scoped_evidence` |
| `oem_relation_and_editor_validation_pending` | `unknown_without_model_scoped_evidence` |

Sobre el primero: **tres de los 23 títulos ligados a patilla se leen como
extensores**, y dos de ellos declaran una capacidad de piñón, que es propiedad
del extensor y no de la patilla. La familia `derailleur_hanger_extender` ya
existe en el catálogo. **No ejecuto ni certifico el cambio**: queda como
revisión de asignación con la cola existente y la evidencia del producto.

Sobre el segundo: en los 33 registros el modelo y el MPN estructurados están
vacíos, mientras varios títulos contienen códigos identificables. Eso es
investigación de identidad en el producto, no un campo nuevo aquí.

## 8. Límites de la evidencia en esta ronda

- **No pude abrir el manual de servicio de Shimano citado en las notas.** El
  servidor respondió 403 tanto por descarga directa como por lectura asistida,
  y el visor del navegador no entrega texto. Por eso **no lo uso como fuente**
  de ninguna decisión: la distinción guía/tensión se apoya en Park, y no se
  extrapola orientación, par ni perfil de dentado a inventario genérico. Queda
  como pendiente explícito.
- **Las dos fichas de Wheels Mfg se leyeron con la herramienta de fetch**, no
  renderizadas, porque el sitio rechazó el navegador integrado. Lo que uso de
  ellas son cadenas literales y estructurales —código, «one M8 chainring bolt»,
  marcas listadas sin año—, no una interpretación.
- **No recibí captura de observaciones de producto** para estas tres familias,
  así que este documento **no reporta adopción**: no sé cuántas fichas tienen
  hoy lecturas en los campos que pasan a legacy. Medirlo es requisito antes de
  publicar, como en los bloques anteriores.
- Las fichas OEM citadas describen **esos** modelos. No se aplican a los
  productos genéricos del inventario ni autorizan rellenarlos.

## 9. Fuentes abiertas de primera mano

- SRAM, *Understanding UDH and Full Mount* —
  `https://www.sram.com/en/learn/understanding-udh-and-full-mount`
- Park Tool, *How a Rear Derailleur Works* —
  `https://www.parktool.com/en-us/blog/repair-help/how-a-rear-derailleur-works`
- OneUp Components, *Bash Guide ISCG05 V2* —
  `https://www.oneupcomponents.com/products/bashguide-v2-iscg05`
- OneUp Components, *Bashguard & Chainguide Install Instructions* —
  `https://eu.oneupcomponents.com/blogs/bashguides-chainguides/bashguard-chainguide-install-instructions`
- Wheels Mfg, *Derailleur Hanger 25* y *70* (leídas por fetch) —
  `https://wheelsmfg.com/products/derailleur-hanger-25`,
  `https://wheelsmfg.com/products/derailleur-hanger-70`
