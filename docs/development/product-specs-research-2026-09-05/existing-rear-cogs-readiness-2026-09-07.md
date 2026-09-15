# Sucesor de las cuatro familias de piñonería trasera

`cassette`, `freewheel`, `fixed_cog`, `cassette_spacer`. Candidato para revisión
de root. **Sin migración, sin producción, sin fill, sin cambios de asignación,
sin git y sin SQL.** Inventario y readback son de root.

| Artefacto | SHA-256 |
|---|---|
| `scripts/inventory/compile_existing_rear_cogs_catalog.py` | `0f9db1acba9d8c3080213c14f9fb4637646ed411061652f3882894ee839af5c8` |
| `existing-rear-cogs-catalog-2026-09-07.json` | `21b3b278bbee57c32d93b0a599196582db815be4117363121bf552d2329fd15b` |
| `existing-rear-cogs-cases-2026-09-07.json` | `436330e8d92d796e6880732b00cb8ed11b301085585d3d1eb8c44e3968bf786b` |

Entradas congeladas y verificadas por hash en cada corrida: catálogo
`16459826…fadf15`, casos `329ad3e5…3716d7`, preimagen completa de las 37
`0a21d85a…d08b2a6`. La compilación es reproducible: dos corridas dan el mismo
byte.

4 plantillas · 21 definiciones (10 vivas reutilizadas, 11 nuevas) · 36 usos de
campo · 36 casos ejecutados y 9 de propuesta: 7 corren contra estas plantillas y
hoy fallan, 2 son fixtures de referencia OEM y no son una superficie de producto.

## Punto de partida medido

Las cuatro llegaron **sin una sola compuerta**: cero `allowed_when`
condicionales, cero `row_conditions`, cero `row_coherence`, cero
`scalar_ordered_pairs` y **cero casos**. Todo era contestable a la vez, así que
una ficha podía declarar once piñones junto a una secuencia de diez, un piñón
menor mayor que el mayor, y una interfaz de cassette de la que no dependía nada.

## Fuentes abiertas y leídas de primera mano

- **Park Tool, *Determining Cassette / Freewheel Type*** — la prueba de taller y
  las dos fijaciones: «Spin the sprockets backwards. If the fittings spin with
  the cogs, it is a cassette system with a freehub»; «The cogs and ratcheting
  body assembly, called a 'freewheel,' threads onto the hub»; «'Cassette'
  sprockets slide over these splines. A lockring threads into the freehub».
  Y el extractor tampoco es un cruce libre: «Shimano-style and Falcon freewheels
  have similar but distinct tool fittings.»
- **Sheldon, *Freewheel or Cassette?*** — «The cassette Freehub incorporates the
  ratchet mechanism into the hub body».
- **Sheldon, *Shimano Cassettes & Freehubs*** — el separador pertenece al **par**,
  no al cassette: «Add a 4.5 mm spacer before installing a 7-speed cassette on an
  8-, 9-, or 10-speed hub, and the included 1-mm spacer before installing a
  10-speed cassettes on an 8- or 9- speed hub.» Y la aceptación no es simétrica:
  «7-speed hubs only accept 7-speed cassettes».
- **Sheldon, glosario *Lockring*** — «Fixed-gear hubs use a left (reverse)
  threaded lock ring to keep the sprocket from unscrewing when the cyclist
  resists the motion of the pedals.»
- **Sheldon, *Fixed Gear Conversions*** — sobre la segunda rosca del buje de
  pista: «This thread is a left (reverse) thread, and a special lockring screws
  onto it.»
- **Shimano, ficha de producto CS-HG50-8** (`bike.shimano.com`, leída en el
  navegador: `si.shimano.com` y el fetch a `bike.shimano.com` devuelven **403**,
  y un 403 no es ausencia de documentación). Un modelo con **siete**
  combinaciones publicadas de ocho piñones, cada una con su código de grupo:
  «11-13-15-17-19-21-24-28T (bf)», «11-13-15-17-20-23-26-30T (an)»,
  «11-13-15-18-21-24-28-32T (aw)», «11-13-15-18-21-24-28-34T (Ca)»,
  «12-13-14-15-17-19-21-23T (U)», «12-13-15-17-19-21-23-25T (W)»,
  «13-14-15-17-19-21-23-26T (V)». La misma ficha nombra la estría: «HG spline M
  (10/9/8-speed, MTB 11-speed, 7-speed CS-HG400/HG210)».
- **SRAM, *SRAM XD and XDR Driver Body Explained*** — la divergencia legítima con
  su cifra: «The XDR interface is 1.85mm longer than XD and is designed for road
  hub applications» y «XDR driver bodies are compatible with all XD cassettes
  when the cassette is installed with a 1.85mm spacer behind it.»
- **SRAM, *What is the new XD SLIM driver body standard?*** (aportada por root;
  la abrí y la leí). El negativo dirigido y por modelo: «the standard XD XX DH
  cassette (XS-797) requires the standard XD driver body, and the XD SLIM
  version (XS-797S) requires the XD SLIM driver body. There is no cross
  compatibility between these two standards.» La misma página deja un enunciado
  **con reserva** que no se promueve a regla: «most hubs that are compatible with
  HG SLIM are likely able to be compatible with the XD SLIM diver body. Please
  consult your hub manufacturer».
- **Park Tool, *Cassette Removal and Installation*** — por qué la posición ordena
  la secuencia: «Freehub bodies and cassette stacks are designed so that there is
  only one possible orientation in which the cogs can be installed onto the
  freehub.»

Lo que **no** quedó citado textual: las medidas de contratuerca Campagnolo/Phil
Wood (1.32 × 24 TPI) llegaron en el resumen de la herramienta, no como cita del
glosario. No se codificaron como valor; el dominio de contratuerca ofrece la
inglesa 1.29, «Otra rosca izquierda» y «Desconocido».

Lo que **no** quedó leído: el sentido inverso del par XD/XDR —si un cassette XDR
entra en un cuerpo XD— no está enunciado en la página de SRAM que abrí, y no lo
afirmo en ninguna dirección. El PDF de despiece `EV-CS-HG50-8-3072C.pdf` no se
pudo leer (403 al fetch y el visor PDF del panel no renderiza texto): las siete
combinaciones salen de la ficha HTML del producto, que sí se abrió.

## Defectos corregidos del candidato congelado

1. **Cuatro asientos roscados dentro de la tabla de cuerpos de un cassette.**
   `freehub_bodies_accepted` ofrecía «Rueda libre roscada 1.37" x 24 tpi»,
   «Rueda libre roscada M30 x 1 (BMX)», el asiento de piñón fijo y «Contrapedal».
   Es exactamente el cruce que separan las dos fijaciones de Park. Retirados; el
   dominio queda en 10 asientos con estría. Además el compilador **afirma** la
   separación (`_assert_attachments`): ninguna plantilla puede poseer a la vez
   una rosca y una estría/cuerpo, y el dominio no puede recuperar los cuatro.
2. **Tres nombres vivos que la propuesta renombraba en silencio** —
   `Espaciador Cassette` → «Separador de cassette», `Piñón Fixie` → «Piñón fijo»,
   `Piñón / Rueda Libre` → «Rueda libre». El publicador los rechaza con
   `Unsupported template metadata change: name`; se conservan los vivos y el
   catálogo declara los rechazos en `renames_declined`.
3. **Dos dominios vivos vaciados y un `origin` falso.** `smallest_cog_teeth`
   (9 valores vivos) y `largest_cog_teeth` (29) llegaban con la lista vacía, y
   `target_rear_drive_interface` decía `new` estando publicado. El publicador
   habría fallado con `Shared definition must remain unchanged`. Se adopta la
   fila viva de las tres.
4. **`spacer_mm` era obligatorio.** Un par que no lleva separador quedaba
   obligado a inventar una cifra, y `0 mm` es un cero medido, no la ausencia de
   una pieza. La rama la posee ahora `spacer_requirement`
   (sin separador / requerido / no publicado) y el espesor sólo existe bajo
   «requerido».
5. **La tabla de cuerpos no tenía llave.** Dos fuentes podían contestar el mismo
   cuerpo con cifras distintas sin que nada objetara. Llave
   `(rear_drive_interface, source_scope)`, construida sólo con columnas
   obligatorias.
6. **Rosca de piñón fijo y contratuerca fundidas en un string** —
   «1.37" x 24 tpi (ISO) + contratuerca 1.29" x 24 izquierda» clava un estándar
   de contratuerca sobre una rosca de piñón y no puede expresar una maza sin
   segunda rosca. Separadas: `cog_thread_standard` (lado motriz) y
   `cog_lockring_thread` (izquierda), con «Sin contratuerca (maza sin segunda
   rosca)» como valor y no como blanco.
7. **`target_rear_drive_interface` era opcional** en la única ficha que existe
   para contestarlo. Pasa a obligatorio.
8. **`sprocket_count` no tenía piso.** `positive` no es un dominio entero no
   negativo y la gramática de cardinalidad lo rechaza; ahora lleva `min: "1"`.

## Compuertas, con su dueño y su rama

| Compuerta | Dueño | Positiva | Negativa | Desconocida |
|---|---|---|---|---|
| `cog_sequence` ← `sprocket_count ≥ 1` | cassette, freewheel | total y filas iguales | más filas que el total → `row_cardinality_conflict` | sin total → `row_cardinality_pending` |
| cardinalidad `declared_sprocket_occurrences` | cassette, freewheel | igualdad | conflicto | menos filas / sin tabla → pendiente |
| `smallest ≤ largest` | cassette, freewheel | 11–30 limpio | 16–14 → `range_order` en ambos | — |
| `freehub_bodies_accepted` ← estría declarada | cassette | abre y se exige | — | estría desconocida o ausente → `prerequisite` |
| `shift_technology` ← estría declarada | cassette | — | — | estría desconocida → `prerequisite` |
| `spacer_mm` ← `spacer_requirement` | cassette (fila) | requerido + cifra | sin separador / no publicado + cifra → `row_field_applicability` | — |
| `conditions` ← `status` | cassette (fila) | condicionado + texto | — | condicionado sin texto → `row_required_missing` |
| llave `(cuerpo, alcance)` | cassette (fila) | dos fuentes = dos lecturas | misma fuente dos veces → `row_shape` | — |
| dominio de cuerpos | cassette (fila) | asiento con estría | rueda libre roscada o contrapedal → `row_shape` | — |
| `remover_tool_standard` ← rosca declarada | freewheel | abre y se exige | — | rosca desconocida o ausente → `prerequisite` |
| `cog_lockring_thread` ← rosca del piñón | fixed_cog | abre; «sin contratuerca» es un valor | — | rosca desconocida o ausente → `prerequisite` |
| `spacer_thickness_mm` ← interfaz de destino | cassette_spacer | destino conocido → se exige | — | destino desconocido o ausente → no se exige |

Todo selector que alguna compuerta lee queda **obligatorio siempre**, calculado
desde las propias compuertas y no de una lista escrita a mano, para que una
compuerta agregada después no pueda olvidar su selector.

### Dos decisiones deliberadas sobre datos ya publicados

- `spacer_thickness_mm` y `cog_sequence` conservan `allowed_when: always`. Sólo
  la **exigencia** es condicional. Un espesor ya publicado, o una secuencia
  escrita antes del total, no pueden convertirse en un valor inaplicable por un
  cambio de contrato.
- `lockring_included` **no lleva compuerta**, a propósito. Todo cassette se
  sujeta con uno; si la caja lo trae es un hecho de envase siempre contestable, y
  un booleano no tiene rama «desconocido» donde caer. No se inventó una compuerta
  decorativa para completar la tabla.

## Semántica de «desconocido», verificada

`hasKnownSpecValue` (`lib/modules/inventory/utils/spec_rule_evaluator.dart:5-13`)
trata el literal `Desconocido / sin confirmar` como **ausencia de valor**. Por eso
declarar desconocido nunca produce `field_applicability`: produce `prerequisite`
pendiente, que es la conducta que pidió el encargo. Las compuertas se escriben
igualmente contra el dominio **sin** el valor desconocido (`known()`), para que el
contrato diga lo mismo que hace el motor y nadie escriba después una compuerta
que se abra con una ignorancia declarada.

## Pruebas

**40 verdes**, sobre el arnés parametrizado real:

```
.fvm/flutter_sdk/bin/flutter test test/unit/product_spec_integrated_catalog_test.dart \
  --dart-define=SPEC_CATALOG_INPUT=docs/development/product-specs-research-2026-09-05/existing-rear-cogs-catalog-2026-09-07.json \
  --dart-define=SPEC_CATALOG_CASES=docs/development/product-specs-research-2026-09-05/existing-rear-cogs-cases-2026-09-07.json
→ +40: All tests passed!
```

4 de metadatos ejecutables (una por plantilla) y 36 casos: positivo, negativo y
desconocido por compuerta. Los positivos llevan `forbidden_issue_fields`; sin eso
un «positivo» pasa igual cuando el campo quedó callado pendiente, que es como se
colaron dos afirmaciones vacías en bloques anteriores de este proyecto. Los casos
que afirman un pendiente sobre `shift_technology` y `remover_tool_standard`
rellenan `spec_evidence_source`, porque esos dos campos tienen además un
prerrequisito documental que produce **el mismo código** `prerequisite`.

**Batería de mutación: 20 mutantes, 18 muertos.**

| Mutante | Casos que lo matan |
|---|---|
| `crossings` (devolver los cuatro asientos roscados) | 2 |
| `cardinality` | 5 |
| `spacergate` | 5 |
| `xdslim` (borrar el valor XD SLIM del dominio) | 1 |
| `variantprereq` (quitarle la procedencia a la variante resuelta) | 1 |
| `bodiesgate`, `removergate`, `lockringgate` | 2 cada uno |
| `bodykey`, `seqkey`, `spacerreq`, `condreq`, `condban`, `shiftgate`, `seqreq`, `thicknessreq`, `thicknessban` | 1 cada uno |
| `orderflip` (invertir el par declarado) | 30 de 36, más los metadatos de `cassette` y `freewheel` |

Un mutante sobrevivió dos veces en rondas anteriores —el `required` de una
columna cuyo único efecto era un aviso que ningún caso afirmaba—. La lección
quedó: cada bandera necesita el caso de lo único que produce, y por eso
`variantprereq` tiene el suyo desde el principio.

**Dos sobrevivientes, y la causa es real, no una prueba floja:** `order`
(vaciar `scalar_ordered_pairs`) y `orderdrop` (quitar la clave). El par
`['smallest_cog_teeth','largest_cog_teeth']` está **cableado en los dos motores**
—`lib/modules/inventory/models/product_spec_coherence.dart:227-238` y
`supabase/migrations/20260907020000_product_spec_row_coherence.sql:110-122`— y
ambos deduplican contra lo declarado. Mi declaración es, hoy, inerte: no agrega
una restricción, la **migra a metadatos**, que es literalmente lo que pide el
comentario de ambos lados («Until legacy metadata is migrated…»). Se conserva por
eso y se reporta como inerte, no como cubierta. `orderflip` sí demuestra que la
dirección declarada es la única no contradictoria: invertirla crea un ciclo y
tumba la batería entera.

## Paquete del publicador

El candidato pasa entero por `compile_packet` del publicador de plantillas
existentes contra la preimagen viva (ensamblado puro, ninguna escritura):

```
familias 4 · definiciones reutilizadas 10 · definiciones nuevas 11
parches 24 (20 campos, 4 plantillas) · product_writes false · fill_allowed false
cassette         Cassette              cv 4 → 18
freewheel        Piñón / Rueda Libre   cv 4 → 17
fixed_cog        Piñón Fixie           cv 3 → 11
cassette_spacer  Espaciador Cassette   cv 3 →  8
```

Ninguna plantilla pierde un campo publicado: el compilador lo afirma contra la
preimagen (`would lose published fields`) y el publicador lo vuelve a exigir
(`Retire existing fields explicitly; never remove observations`).

## Correcciones tras las dos revisiones de root

### Primera: un producto de ocho velocidades no se convierte en 56

Estaba adaptando el significado del producto a la limitación del contador del
motor. `sprocket_count` vuelve a ser **«Cantidad de coronas»** —las de la unidad
que se edita— y su cardinalidad plana vuelve a la secuencia de esa unidad: ocho
contra ocho, exigible hoy. Desaparecen los totales 16 y 56.

### Segunda: separar tablas no cambia el dueño

Mi corrección anterior movió las variantes del modelo a `cog_configurations` y
`cog_configuration_teeth` creyendo que ponerlas en tablas distintas de
`cog_sequence` bastaba. **No bastaba, y root tiene razón:** seguían siendo campos
del producto, así que cada SKU habría publicado como hechos suyos las siete
variantes del CS-HG50-8. El contrato canónico §4.1 separa las referencias OEM del
inventario del tenant.

Las dos definiciones **salen del candidato**. No están en `definitions` ni como
campo de ninguna plantilla, y el compilador lo verifica al filtrar por claves
usadas. Lo que llega a la ficha del SKU es lo que root pidió: la unidad y **la
variante resuelta con su procedencia**.

| Qué | Dónde | Estado |
|---|---|---|
| Coronas y secuencia de la unidad | `sprocket_count`, `cog_sequence` | campo productivo, cardinalidad exigible |
| Cuál combinación publicada **es** esta unidad | `published_variant_label` | campo productivo, con `prerequisites` → `spec_evidence_source` |
| Las siete combinaciones del modelo | `oem_variant_reference` del catálogo | **referencia OEM, `is_product_fact: false`** |

Los datos OEM investigados quedan **íntegros**: combinación, código de grupo,
piñones declarados y secuencia completa de las siete, con su URL. No se pierden
al corregir el dueño, y sirven como fixtures de referencia del motor agrupado sin
legitimarse como ubicación productiva.

`rcx_the_resolved_variant_belongs_to_the_unit` afirma que la ficha puede decir
«11-30T (an)» sin incidencia alguna; `rcx_a_resolved_variant_without_its_source_is_pending`
afirma que sin fuente queda pendiente, y el mutante `variantprereq` lo mata.

Esto no cierra la puerta a configuraciones de montaje realmente admitidas por el
mismo SKU ni a conjuntos de varias piezas incluidas. Ninguna de las dos existe
hoy en estas cuatro familias, y no inventé una para justificar una capacidad.

### P-1: la carencia era de dueño, no de contador

Con el catálogo fuera de la ficha, **estas cuatro familias ya no necesitan la
forma agrupada**. Lo digo así de claro porque fui yo quien la pidió: el hueco que
la motivaba se cierra corrigiendo el propietario. La forma agrupada sigue siendo
útil para un grupo que sí sea del mismo SKU, y root ya tiene un candidato de
motor. Las dos fixtures de variantes quedan marcadas
`surface: oem_reference_fixture`, `runnable_against_templates: false`.

### P-2′: evaluar la relación que ya existe, no duplicarla

Root pidió mirar `ProductSpecRelation` antes de inventar otro evaluador. Tenía
razón: la clase **ya tiene** la semántica completa —`interface`, filas de
`alternatives` y `exclusions`, cada una con `conditions` tipadas y `sources`
obligatorias validadas como URL absoluta— y las condiciones **son** los
parámetros del montaje: `spacer_mm eq 1.85` se escribe tal cual. Retiro mi
conjunto de relaciones propio.

> **Corrección del 2026-09-08.** Aquí escribí que «lo único que falta es el
> evaluador» y que la clase «sólo se resume en prosa». **Es falso.**
> `ProductSpecRelation.evaluate` existe en
> `lib/modules/inventory/models/product_spec_relation.dart:78-132`, con su
> paridad `spec_relation_assess_internal_v1`
> (`supabase/migrations/20260906180000_product_spec_scoped_relations.sql:174`) y
> 50 casos verdes en `test/unit/product_spec_relation_test.dart`. Ya distingue
> `supported`, `excluded`, `unknown` y `outsideDeclaredScope`, y su propio
> comentario advierte que no coincidir con una alternativa «is only outside this
> declaration, never a physical incompatibility proof». El error fue de método:
> busqué «relation» en el consumidor (`product_spec_contract.dart`) y no en el
> modelo, y de no encontrarlo ahí concluí que no existía. Lo que falta es la
> **integración** del veredicto a la validación de la ficha, no otro evaluador.
> P-2′ se reduce a esa integración.

Y la distinción que root exigió queda en dos códigos separados:

| Estado | Código | Bloquea |
|---|---|---|
| Fila en `exclusions` | `row_relation_excluded` | sí, y ningún texto lo levanta |
| Parámetro de la relación **ausente** | `row_relation_parameter_pending` | no — no saber no es contradecir |
| Parámetro **presente que no cumple** | `row_relation_parameter_conflict` | sí |
| Par que no está en ninguna lista | `row_relation_unlisted` | no |
| Interfaz propia desconocida | `row_relation_pending` | no |

`SRAM XD SLIM` sigue siendo un valor propio del dominio: sin él, el cruce que
SRAM niega queda indistinguible del legítimo.

### Los casos que hoy fallan

Siete de los nueve corren contra estas plantillas; los otros dos son fixtures de
referencia OEM y no se ejecutan aquí. Contra el motor actual:

```
rcp_a_note_cannot_authorise_an_excluded_body                    Expected row_relation_excluded — Actual []
rcp_an_absent_spacer_is_pending_not_a_contradiction             Expected row_relation_parameter_pending — Actual []
rcp_a_contradicted_spacer_is_not_the_same_as_an_absent_one      Expected row_relation_parameter_conflict — Actual []
rcp_an_unlisted_pair_is_not_a_verdict                           Expected row_relation_unlisted — Actual []
rcp_equal_labels_still_need_an_alternative_row                  Expected row_relation_unlisted — Actual []
rcp_an_unknown_own_interface_is_never_a_conflict                Expected row_relation_pending — Actual []
→ +5 -6: Some tests failed.
```

`rcp_the_published_spacer_satisfies_the_relation` **pasa hoy**, y esa es la mitad
que importa: la capacidad no debe empezar a emitir donde el parámetro publicado
está declarado y es igual.

## Huecos abiertos, dichos y no disimulados

1. **P-2′ es una integración pendiente, no un evaluador que falte** (ver la
   corrección del 2026-09-08 más arriba). El evaluador existe y está probado;
   lo que no llega a la validación de la ficha es su veredicto. Hasta que
   llegue, un cruce que SRAM niega sigue siendo escribible; lo que este
   candidato ya impide es que sea *indistinguible*, porque XD SLIM tiene su
   propio valor y ninguna fila puede nombrar una rueda libre roscada ni un
   contrapedal.
2. **P-1 no la necesitan estas cuatro familias.** Queda como capacidad general
   con su candidato de motor, y las variantes sólo como fixtures de referencia.
3. **Cambiar el cuerpo de una maza por otro es otra intervención** y ni este
   contrato ni P-2′ la representan.
4. **Las generalizaciones históricas de Sheldon sobre 7–11 velocidades no se
   promovieron a reglas.** Siguen como fuente de la rama del separador, que es
   una declaración por fila con su fuente.
5. **`expected_sql_issue_subset` lo genera el helper compartido `case()`.** No
   corrí SQL —la sesión es tuya—, así que la paridad servidor/Dart de
   `row_required_missing`, `row_incomplete`, `row_cardinality_pending` y
   `prerequisite` es readback tuyo.
6. **`scalar_ordered_pairs` es inerte hoy** (ver Pruebas): los dos motores
   cablean ese par. Se declara como migración a metadatos, no como cobertura.
7. **Ninguna interfaz se universalizó por marca.** HG S/M/L/L2 siguen separados,
   XD ≠ XDR ≠ XD SLIM, Campagnolo ≠ N3W, y el bloque no agrega ninguna regla de
   compatibilidad.
