# Asistente IA · lenguaje natural → ficha técnica · handoff 2026-08-24

Documento autocontenido para continuar en un chat nuevo. No requiere leer el
chat anterior. Todo lo que aquí se afirma como verificado tiene su read-back
citado; lo que no lo tiene está marcado como **no verificado**.

**Antes de tocar nada:** lee `AGENTS.md` y los documentos que enruta
(`.github/copilot-instructions.md`, `.github/GUI_DESIGN_PRINCIPLES.md`,
`docs/development/AGENT_DATABASE_CONTRACT.md`,
`docs/architecture/product-identity-matching-contract.md`,
`docs/development/AGENT_MACOS_APP_CONTROL.md`), luego este handoff, y **vuelve a
consultar** branch/SHA/status, la sesión runtime y el estado de producción. No
confíes en los números de aquí sin reconfirmarlos: son del 2026-08-24.

---

## 1. Objetivo y contrato de producto

**Toda petición técnica entra en lenguaje natural.** El operador escribe como
habla en el taller —«camaras 26 con valvula VA de 48mm», «qué cámaras me sirven
para un neumático de 2.1»— y el sistema debe:

1. **Inspeccionar el esquema vigente** (`inspect_inventory_schema`), que anuncia
   las definiciones disponibles con su tipo, unidad, operadores permitidos,
   vocabulario cerrado (`allowedValues`) y **cuántos productos lo tienen
   poblado**.
2. **Traducir la intención** a definiciones + valores + IDs y **predicados
   tipados** (`field`, `operator`, `values`).
3. **Recién entonces** buscar, asignar productos o generar la acción.

El alcance del contrato es: **inventario, compras, proveedores, asignación de
productos y compatibilidad técnica.**

### Lo que está prohibido por contrato

- **No degradar a buscar la frase literal** contra el nombre del producto cuando
  existe ficha/esquema canónico. Ese fallback existe, pero es respaldo — no el
  mecanismo.
- **No resolver con sinónimos escritos a mano.** El vocabulario sale del
  catálogo y del registro de definiciones, nunca de una lista en el código. Ya
  hubo dos accidentes por listas a mano: «con uña / claw» convertía cualquier
  frase con «con una» en un filtro de patilla, y un patrón de válvula sin borde
  de palabra leía «cámara nue**VA**» como Schrader.

### El reparto de responsabilidad (decisión de diseño, 2026-08-24)

| Quién | Qué resuelve |
|---|---|
| **Servidor** (`assistant_infer_technical_predicates_internal_v1`) | Vocabulario **cerrado**: medida de rueda, tipo de válvula, largo de válvula. Es el **respaldo** cuando el modelo no estructura. |
| **Modelo** (vía `inspect_inventory_schema` + predicados tipados) | Lo que exige criterio: **rangos, contención, comparaciones**. Ej. «para un neumático 2.1» → `tube_width_min_in ≤ 2.1` **y** `tube_width_max_in ≥ 2.1`. |

Un número suelto es **ambiguo** entre varios campos numéricos (`tube_width_*`,
`rotor_thickness_mm`, `spoke_length_mm`, `sealant_volume_ml`), y el servidor no
debe adivinar. El modelo sí puede porque el anuncio le da tipo, unidad,
operadores y población.

---

## 2. Arquitectura y fuente de verdad

### Registro de specs (modelo sólido por PK)

La migración desde los blobs/JSON previos hacia el registro por clave primaria
**ya está hecha del lado de lectura**: la app lee `spec_facts` y
`product_spec_values` es una **copia espejada por disparador**.

| Tabla | Rol | Verificado |
|---|---|---|
| `spec_definitions` | Catálogo de campos. **127 filas, todas globales (`tenant_id IS NULL`)**. Columnas clave: `key`, `data_type`, `unit`, `allowed_values` (jsonb), `is_filterable`, `is_compatibility_relevant`, `group_name`. Índice único **parcial**: `unique (key) where tenant_id is null` | ✅ producción |
| `spec_definition_values` | Vocabulario cerrado de cada `single_select`: `code` (estable) + `label` (lo que ve el humano y **de donde la inferencia extrae tokens**) | ✅ producción |
| `spec_facts` | **El registro vivo.** `subject_type ∈ ('product','bike','job_bike')`, `subject_id`, `spec_definition_id`, escalares `value_number`/`value_boolean`/`value_text`, `source`, `confirmed`, `subject_scope` | ✅ producción |
| `spec_fact_values` | **Dónde vive el valor de un `single_select`**: `fact_id → spec_definition_values.id`. Los escalares quedan NULL. Confundir esto cuesta una ronda | ✅ producción |
| `spec_templates` / `spec_template_fields` | El **formulario**. `spec_templates.key='tube'` es la ficha de Cámara; los campos se enganchan por `template_id` + `spec_definition_id`, con `section_key` y `sort_order` | ✅ producción |
| `product_spec_values` | Copia legacy, **mantenida por el disparador** `mirror_facts_into_product_specs` → `mirror_facts_into_product_specs_internal_v1` (dispara en INSERT/UPDATE/DELETE) | ✅ producción |

**Restricciones que hay que respetar al escribir hechos:**

- `spec_facts_one_scalar`: `num_nonnulls(value_number, value_boolean, value_text) <= 1`
- `spec_facts_source_known`: `source ∈ ('mechanic','catalog','supplier_text','inferred','import')` — **vocabulario cerrado, no inventes `name_parse`**
- `spec_facts_subject_type_known`: `subject_type ∈ ('product','bike','job_bike')`
- Índice único: `(tenant_id, subject_type, subject_id, spec_definition_id, coalesce(subject_scope,''))`

### Cadena del asistente

```
mensaje en lenguaje natural
   ↓
inspect_inventory_schema  → assistant_inspect_inventory_schema_v3(p_query, p_category)
   ↓  anuncia: field · dataType · unit · operators · allowedValues · populatedCount
modelo traduce → technicalPredicates [{field, operator, values}]
   ↓
search_inventory → assistant_search_inventory_v7(
     p_query, p_category, p_availability, p_technical_predicates,
     p_operational_predicates, p_sort_field, p_sort_direction,
     p_limit (1..10), p_selection_mode ∈ ('all_matches','top_n'))
   ↓  (si llegan 0 predicados: traduce la frase server-side con
   ↓   assistant_infer_technical_predicates_internal_v1 — el RESPALDO)
envelope → assistant_tool_envelope_internal_v1(tenant, items, truncated)
   ↓
cards.ts arma la tarjeta `inventory` con listRef{query, entityIds, resultCount, hasMore}
   ↓
Flutter: entityIds != null → abre esos productos; null → busca `query` como texto
```

**Herramientas de compras** (mismo patrón, carril propio): `search_suppliers`,
`search_purchase_invoices`, `build_purchase_scenarios`, `prepare_supply_request`.
El armado de canastas resuelve cada línea con
`purchase_query_products_internal_v1` (escalera de degradación de 8 intentos) y
usa `presentation: "answer"`.

> **Corrección 2026-08-24 (§11.b).** Ese `presentation: "answer"` **ya no** es
> lo que lo exime del gate: era el eje equivocado y dejaba pasar respuestas en
> prosa al operador armadas por nombre. Lo que exime hoy es el **abanico del
> turno** —varias búsquedas de inventario en un mismo turno son líneas de una
> lista— más el carril de compras (`purchasingDraftMode`).

### Rutas reales

- Gateway: `supabase/functions/ai-agent-gateway` (código en `_shared/ai_agent/`)
- Contratos cliente: `lib/modules/ai_assistant/models/ai_agent_gateway_contracts.dart`, `ai_assistant_turn_contracts.dart`
- Consumo de la tarjeta: `lib/modules/ai_assistant/widgets/ai_chat_bubble.dart:231`, `lib/modules/purchases/pages/intelligent_purchasing_workspace_page.dart:902`
- Motor de fichas en la app: `lib/modules/inventory/services/spec_engine_service.dart` (lee `spec_facts`, escribe por `save_product_spec_facts_v1`)

---

## 3. Todo lo realizado en este chat

> Este chat cubrió **dos frentes**: el módulo Asistente de compras (UI + pedidos)
> y el asistente IA de lenguaje natural. Ambos se listan porque comparten
> archivos y estado del checkout.

### 3.a Asistente de compras — UI y tablas

| Cambio | Archivos | Estado |
|---|---|---|
| Tabla de concentración de proveedores (`TB-01`) con columnas responsivas medidas, no declaradas | `lib/modules/purchases/widgets/supplier_concentration_table.dart` (nuevo) | ✅ probado en app |
| El ancho de la orden rotulada **se mide** con `TextPainter` sobre el estilo resuelto; la geometría del icono la fija la tabla (`IconButton.styleFrom`), no el `iconButtonTheme` | idem + `purchase_visual_language.dart` (`purchaseInlineActionWidth`) | ✅ 5 pruebas |
| Panel de evidencia reescrito de muro de texto a criterios con peso + tabla de compras | `lib/modules/purchases/widgets/supplier_evidence_panel.dart` (nuevo) | ✅ probado en app |
| Ficha del proveedor **dentro del bloque** (sin cambiar de ruta), con cabecera, métricas, catálogo paginado y buscador | `supplier_workspace_view.dart`, `supplier_open_orders_strip.dart` (nuevos) | ✅ probado en app |
| Compositor de pedido en split pane + vista previa viva del documento + PDF real | `supplier_order_composer.dart`, `purchase_order_document_preview.dart`, `purchase_order_message_preview.dart`, `lib/shared/utils/purchase_order_pdf_generator.dart` (nuevos) | ✅ probado en app |
| **Silo paralelo retirado**: el pedido es un documento de compra real en `purchase_invoices` estado `draft` | migración `20260824490000` | ✅ read-back |
| Toggle **con flete / sin flete**, por defecto **sin flete** | `purchase_visual_language.dart` (`PurchaseCostBasis`) + 3 migraciones | ✅ probado en app |

### 3.b Asistente IA — la cadena de lenguaje natural (el foco del final)

**Defecto 1 — la tarjeta tiraba los IDs cuando había truncamiento.**
`cards.ts` mandaba `entityIds: result.hasMore ? null : …`. Sin IDs, el cliente
caía a buscar la frase como texto contra el nombre del producto: **mientras más
acertaba la búsqueda, más vacía salía la lista.** «camaras 26 con válvula VA de
48mm» calzaba con 15 productos y abría **cero**.

El invariante vivía en **cuatro** lugares y se corrigió en los cuatro:

1. `supabase/functions/_shared/ai_agent/cards.ts` — construcción del `listRef`
2. `cards.ts` → `validateListRef` (~línea 1928) — validador al leer tarjetas guardadas
3. `lib/modules/ai_assistant/models/ai_agent_gateway_contracts.dart` — el parser Dart rechazaba con `lista_truncada_con_ids`, y por eso salía «No pude procesar esa solicitud ahora»
4. Pruebas: `cards_test.ts` y `test/unit/ai_agent_gateway_runtime_test.dart`

Se acepta `null` **al leer** (tarjetas guardadas por la versión anterior); se
prohíbe `null` cuando `hasMore` es false.

**Defecto 2 — el título no tenía referente.** «10+ resultados» no dice de
cuántos. Ahora: `hasMore ? "Los primeros N" : "N resultados"`.

**Defecto 3 — la contradicción del prompt.** El esquema de `search_inventory`
decía «predicados sobre claves que anunció `inspect_inventory_schema`; **no
inventes claves**» y en la misma frase «los valores van **como los dijo el
operador**». O sea: no uses claves que nunca te mostramos, y encima no
traduzcas. El modelo obedeció y mandó `technicalPredicates: []`.
Corregido en `tool_registry.ts`: ahora dice **«Los valores SÍ se traducen»** con
ejemplos, y advierte que si la petición nombra una medida y llega sin
predicados, el servidor pedirá inspeccionar.

**Defecto 4 — el gate era de un solo lado.** En `runtime.ts` sólo se disparaba
cuando el modelo mandaba predicados **sin** haber inspeccionado. No estructurar
nada pasaba libre, así que el camino premiado era el que no usa la ficha.
Se agregó la rama complementaria con tres guardas:

- `inventoryQueryNamesAMeasurement()` — **un número que sea token propio**, con
  unidad opcional: `26`, `48mm`, `27.5`, `700c`. **No** «trae dígitos»:
  `RD-M6100` y el SKU `6927116100261` también traen dígitos y **no son
  medidas** — para códigos, buscar por nombre es lo correcto. Largo acotado a
  4 dígitos por lo mismo.
  **Ampliado el 2026-08-24 (§11.b):** reconoce además la **medida compuesta**
  (`700x28`, `26x1.95`, `27.5×2.25`, `12x142`), que es como el mecánico escribe
  un calce y donde ninguno de los dos números es token propio.
- ~~`inventoryPresentationOpensAList()`~~ — **retirado el 2026-08-24, ver
  §11.b.** Eximía `presentation: "answer"` por considerarlo siempre un paso
  interno; no lo es, y por ese hueco «camara para 700x28» contestó en prosa
  saltándose una cámara con stock. Lo reemplaza el **abanico del turno**, que
  sí distingue una pregunta de una canasta.
- `!purchasingDraftMode` — el carril de compras resuelve la frase por diseño.

**Fichas de cámaras** — ver §4.

### 3.c Despliegues realizados en este chat

| Qué | Cómo | Estado |
|---|---|---|
| **21 migraciones** `20260824400000` … `20260824600000` | `scripts/db/deploy_migration.sh --migration X --verify Y` con `VINABIKE_DB_WRITE_CONFIRM=production` | ✅ las 21 con recibo en `.tmp/db/migration-receipts/` y estampadas en `supabase_migrations.schema_migrations` (17 de ellas ≥ `20260824440000`, verificado hoy) |
| **Gateway `ai-agent-gateway`** — desplegado **dos veces** | `scripts/supabase_cli.sh functions deploy ai-agent-gateway --project-ref xzdvtzdqjeyqxnkqprtf` | ✅ segundo deploy: 310 kB, respuesta `{"message":"Deployed Functions."}` |

> `scripts/supabase_cli.sh functions deploy` **exige `--project-ref` explícito**
> o se niega («Refusing unsafe Supabase CLI invocation»).

---

## 4. Fichas técnicas de cámaras

### Punto de partida

**4 de 134 cámaras tenían ficha (3%).** Los nombres sí traían los datos.

### Campos creados (`20260824550000_the_tube_form_gets_its_real_specs.sql`)

Seis definiciones nuevas, globales, más su enganche a la plantilla `tube`:

| `key` | tipo | unidad | sección |
|---|---|---|---|
| `tube_width_min_in` / `tube_width_max_in` | `number` | `in` | compatibility |
| `tube_width_min_mm` / `tube_width_max_mm` | `number` | `mm` | compatibility |
| `tube_has_sealant` | `boolean` | — | specs |
| `tube_material` | `single_select` (Butilo/TPU/Látex/Otro) | — | specs |

**El ancho va como número, no como lista.** 45 pares distintos en 120 cámaras y
crecen con cada compra — pero la razón de fondo es que **un ancho es una medida,
no una categoría**: con números, «¿sirve para un 2.1?» se contesta con
aritmética; con texto, `1.95/2.125` nunca calzaría con `1.95 a 2.125`.

Read-back (`verify_tube_form_fields.sql`): **9 campos** en la ficha `tube`,
**4 numéricos**, 4 de ancho, sellante, material con 4 opciones, y
`ancho_sin_lista = t`.

### Poblado (`20260824560000` + `20260824570000`)

Regla: **sólo se escribe lo que el nombre dice**, `confirmed = false` siempre, y
**nunca se sobrescribe** un hecho existente.

`source` usado: `supplier_text` (leído del nombre) e `inferred` (deducido).

**Cuándo el silencio es evidencia** — la regla que decidió los seis campos:

- **Lo es** si el dato, de existir, se habría dicho. Una cámara con sellante
  siempre se vende diciéndolo. Corroborado con dos señales independientes: 8 lo
  declaran en el nombre, la categoría «Cámaras Anti-Pinchazo» tiene 4, y esas 4
  están entre las 8 — **cero desacuerdo**.
- **No lo es** si el dato existe igual (largo de válvula). Ahí vacío es la verdad.

**Estado verificado hoy en producción:** 134 cámaras · **133 con ficha** · **871
hechos**.

| campo | hechos | leídos | deducidos |
|---|---|---|---|
| `tube_has_sealant` | 133 | 8 | 125 |
| `tube_material` | 133 | 29 | 104 |
| `valve_type` | 131 | 127 | 0 |
| `wheel_size` | 131 | 127 | 0 |
| `tube_width_min_in` / `max_in` | 94 c/u | 94 | 0 |
| `valve_length_mm` | 91 | 88 | 0 |
| `tube_width_min_mm` / `max_mm` | 32 c/u | 32 | 0 |

Read-back `verify_tube_specs_filled.sql`: **0 falsos confirmados**, **0 hechos
sin valor**. `verify_tube_widths_complete.sql`: **126 con ancho** (94 in / 32
mm), **0 invertidas**, **0 fuera de rango**.

### Excepciones deliberadas (1 descartada + huecos)

- **«Cámara nueva + servicio de cambio»** — es un servicio, no recibe ficha.
- **«Camara Para Carretilla 3.50 X 8»** — no es de bicicleta.
- 2 dicen «V.Bicicleta», que no significa nada → sin válvula.
- 8 sin ancho porque el nombre no lo dice (`DKD 26''`, `Impinchable Aro 27.5, Slime`).

### Convenciones de escritura del catálogo (documentadas en `product-identity-matching-contract.md`)

| Convención | Ejemplo | Significa |
|---|---|---|
| Rango con barra / «a» / guion | `29 X 1.75/2.35`, `26 X 1.95 a 2.125` | rango |
| **Fracción** | `24 X 1.3/8` | 1‑3/8″ = **1,375″**, no «1,3 a 8» |
| **Ancho único** | `700X28C`, `ARO 29 X 1.95C` | mínimo = máximo |
| Ruta en mm | `700 X 18/25C` | 18–25 **mm** |
| Signo `×` | `20×1.5/2.5` | U+00D7, no la letra X |

La fracción se resuelve **antes** del rango y **sólo si es fracción de verdad**
—numerador < denominador, denominador potencia de dos—: sin ese guarda,
`1.5/2.5` se leía como 1 + 5/2 = 3,5.

**Válvula, once formas:** `V/AMERICANA`, `V/AUTO`, `V/A`, `VA`, `AV`, `A/V`,
`Válvula de auto`, `V.Auto`, `VAL AUTO`, `SV`, `LSV` → **Schrader**.
`V/FRANCESA`, `V/F`, `VF`, `FV`, `F/V`, `V.Francesa`, `VAL/FRANCESA`, `FV48`,
`LFV` → **Presta**. (`SV`/`FV` es nomenclatura Maxxis: Schrader/French Valve,
`L` = Long.)

### El arreglo de números recién completado (2026-08-24)

**Síntoma:** «48mm» no se resolvía en **ninguna** redacción. Tres capas:

**(a) `is_filterable = false`** — `valve_length_mm` tenía la bandera apagada y
la inferencia sólo considera campos filtrables: **el campo nunca fue candidato,
con 94 hechos cargados**. Había tres medidas más igual. Migración
`20260824590000_a_measurement_you_cannot_filter_is_invisible.sql` abre:
`valve_length_mm`, `rotor_thickness_mm`, `spoke_length_mm`, `sealant_volume_ml`.
`diagnosis_notes` **se deja fuera a propósito** (texto libre; filtrar por él
devuelve ruido).

**(b) El tokenizador no despegaba la unidad.** El separador corta por
caracteres no alfanuméricos, así que `48mm` quedaba de una pieza y jamás
igualaba al rótulo `48`. Con `48 mm` separado **sí** funcionaba —y nadie escribe
con espacio: el catálogo dice `48MM`—. Migración
`20260824600000_a_measurement_glued_to_its_unit.sql` reemplaza
`assistant_infer_technical_predicates_internal_v1` (lenguaje **`sql`**,
`stable`, `security definer`, firma `(p_tenant_id uuid, p_query text)`): la CTE
`tokens` ahora emite el número suelto **además** del token original, con la
**misma `ordinality`** para no romper la adyacencia. Patrón:
`^[0-9]+(?:[.,][0-9]+)?[a-z"]{1,10}$`. Entra `700c`, `2.1in`, `60mm`; **queda
fuera `26x1.95`** a propósito — es un calce de neumático y partirlo inventaría
un valor que nadie pidió.

**(c) El rango es responsabilidad del modelo.** «Cámara para un neumático 2.1»
→ `tube_width_min_in ≤ 2.1` **y** `tube_width_max_in ≥ 2.1`. El servidor no
adivina a qué campo numérico pertenece un número suelto; el modelo sí, porque el
anuncio le da tipo, unidad, operadores (`eq,neq,lt,lte,gt,gte,between,in`) y
población (92 productos con `tube_width_max_in`, 31 con `*_mm`).

**Vocabulario del taller en los rótulos** (`20260824580000`): `Schrader
(americana / auto)`, `Presta (francesa)`, `Dunlop (inglesa)`, sincronizado con
`allowed_values`. **`VA`/`VF` quedan fuera a propósito**: dos letras, y «va» es
un verbo común — aceptarlo convertiría cualquier frase con «va» en un filtro de
válvula. Control verificado: `'el pedido va manana'` → `[]`.

> ⚠️ Este cambio de rótulo **mejora el respaldo y el desplegable del
> formulario**, pero **no era el arreglo**: el arreglo real fue el gate + el
> prompt, que hacen que el modelo traduzca sin depender de sinónimos.

### Estado de `migration history`

Las 21 migraciones tienen recibo local en `.tmp/db/migration-receipts/` y las
17 con versión ≥ `20260824440000` están estampadas en
`supabase_migrations.schema_migrations` (confirmado hoy con lectura directa).

---

## 5. Evidencia de aceptación

### 5.a Prueba de punta a punta: rango/contención ✅

Consulta real escrita en el Asistente IA de la app (build debug, datos de
producción):

> **«que camaras 26 me sirven para un neumatico de 2.1»**

Chips visibles en la tarjeta: **`Cámaras · 10 fichas técnicas · Todos · 26" ·
≤ 2.1 · ≥ 2.1`** — el modelo emitió predicados de rango sobre
`tube_width_min_in` / `tube_width_max_in`.

Respuesta observada (transcrita del pantallazo):

> Para un neumático **26 x 2.1**, te sirven las cámaras cuyo rango de ancho
> cubra esa medida (generalmente rangos como 1.75-2.35, 1.9-2.125 o 1.95-2.20).
> **Con válvula de Auto (Schrader):** CST 26x1.9/2.125 (48 mm) $5.500 (SKU 25247
> · Stock 10) · RideXC 26x1.95/2.125 (35 mm) $6.000 (SKU 10371 · Stock 7) ·
> 10Ten 26x1.95/2.20 (48 mm) $3.990 (SKU 23209 · Stock 6) · KENDA 26x1.75-2.35
> (48 mm) $7.000 (SKU 4417 · Stock 1). **Con válvula Francesa (Presta):**
> 26x1.95/2.125 (48 mm) $5.000 (SKU 6938112671129 · Stock 2). La elección
> dependerá de la perforación de tu llanta y del largo de válvula requerido.

### 5.b Prueba de punta a punta: válvula + medida ✅

> **«encuentrame camaras 26 con valvula VA de 48mm»**

- **Antes:** tarjeta «10+ resultados», lista **vacía** («No se encontraron
  productos»), `entityIds: null`, `listRef.query` = la frase cruda.
- **Después:** título **«Los primeros 10»**, chips `Todos · 26" · Schrader
  (americana / auto)`, y la lista abre **10 cámaras 26, todas V/AUTO**, con
  «10 de 10 resultados» al pie.

Verdad de contraste medida contra la ficha: **15 cámaras** son 26" + Schrader +
48 mm; el tope de `p_limit` es 10, de ahí `hasMore`.

### 5.c Read-backs de la inferencia (SQL directo, producción)

| Frase | Predicados devueltos |
|---|---|
| `camaras 26 valvula de auto 48mm` | `wheel_size in ["26\""]`, `valve_type in ["Schrader (americana / auto)"]`, `valve_length_mm in ["48"]` |
| `camaras 29 francesa 60mm` | `wheel_size in ["29\""]`, `valve_type in ["Presta (francesa)"]`, `valve_length_mm in ["60"]` |
| `neumatico 26x1.95` (control) | `[]` — el calce **no** se parte |
| `el pedido va manana` (control) | `[]` — «va» no es vocabulario |

### 5.d Suites que realmente pasaron

| Suite | Resultado |
|---|---|
| `deno test --allow-read supabase/functions/_shared/ai_agent/` | **250 passed, 0 failed** después del cierre del 2026-08-24 |
| `flutter test test/widget/` + contratos (`ui_guidance_contract`, `ai_agent_gateway_runtime`, `ai_action_card_render`, `purchase_order_document`, `supplier_confirmed_scope`) | **416 passed** en la corrida más amplia; **51 passed** en la última corrida focalizada tras el cambio de contratos |
| `scripts/run_flutter_test_gate.sh` | **Suite Flutter completa + 3 pruebas Web Locks en Chrome, todo verde** después de los cambios de fichas, compras, portal y gates |

> `deno test` necesita **`--allow-read`** o la prueba de eval de negocio falla
> por permisos, no por lógica.

---

## 6. Lecciones y trampas

1. **No le prohíbas al modelo usar lo que nunca le mostraste.** El prompt decía
   «no inventes claves» y jamás se le mostraba ninguna. El modelo obedeció y no
   filtró nada. Si una herramienta exige vocabulario cerrado, el vocabulario
   tiene que **llegar** —por un gate que obligue a inspeccionar o inlineado.
2. **Una compuerta va en los dos sentidos.** La que había castigaba estructurar
   sin inspeccionar y premiaba no estructurar.
3. **Una medida que no se puede filtrar es invisible.** Antes de culpar al
   lenguaje, revisa `is_filterable`. Orden de diagnóstico ante «no entiende este
   número»: (1) ¿el campo es filtrable? (2) ¿el token trae la unidad pegada?
   (3) ¿lo que se pide es igualdad o **contención**?
4. **Un número sin referente no informa.** «10+ resultados», «12 de 12» sobre
   un barrido de otra cosa. Un recuento en una fila tiene que poder
   relacionarse con algo visible en esa misma fila.
5. **Un resultado truncado entrega las filas que pudo mostrar.** Mandar `null`
   «para no mentir» produce una lista vacía, que miente peor.
6. **Un invariante que vive en N lugares se corrige en los N.** Éste vivía en 4.
7. **`create or replace` con un parámetro nuevo SOBRECARGA**, no reemplaza
   («is not unique»): va `drop function` explícito de la firma vieja. Y **los
   defaults se conservan exactamente**: cambiarlos hace que Postgres se niegue
   («cannot remove parameter defaults»). Léelos con `pg_get_function_arguments`.
8. **Índice único parcial** (`unique (key) where tenant_id is null`) no sirve
   para `on conflict (key)` a secas: usa `where not exists`.
9. **Un `single_select` guarda su valor en `spec_fact_values`**, no en las
   columnas escalares. Escribir `value_text` ahí deja el hecho sin valor.
10. **Lee los disparadores antes de escribir** en una tabla que nadie usaba.
11. **El corredor de verificaciones rechaza `do $$ … $$`** («cannot manage
    transactions»): el JWT se fija con `select set_config(...)` suelto.
12. **`scripts/dev/app_control.sh shot` no ve vistas nativas**; `type`/`key` van
    por System Events y pueden estar denegados. `enter-text --label` a veces
    devuelve «sin coincidencias»: ahí conviene Computer Use.
13. **AppleScript a System Events está denegado** en esta máquina: no se puede
    redimensionar la ventana por esa vía.
14. **Correr la suite Flutter completa por costumbre cuesta ~11 min** y el dueño
    la mató a mano. Corre los archivos afectados; la completa sólo si te la
    piden o antes de publicar.

---

## 7. Estado exacto del checkout

```
branch : smartpegas1.0
HEAD   : 59b1c0a75948a1ea1333d58bcde93c083b007e8c
status : 182 rutas modificadas/sin seguimiento  ← ÁRBOL SUCIO Y COMPARTIDO
```

**El árbol contiene trabajo que NO es de este chat.** Al iniciar la sesión ya
había ~125 rutas cambiadas. Trátalo como checkout compartido.

### Archivos que son míos (de este chat)

**Nuevos:**
`lib/modules/purchases/models/{purchase_order_document,purchase_order_draft,purchase_order_message,purchase_order_summary,supplier_catalog}.dart`,
`lib/modules/purchases/widgets/{purchase_order_document_preview,purchase_order_message_preview,supplier_concentration_table,supplier_evidence_panel,supplier_open_orders_strip,supplier_order_composer,supplier_workspace_view}.dart`,
`lib/shared/utils/purchase_order_pdf_generator.dart`,
`test/unit/{assistant_follow_up_catalog,purchase_order_document,supplier_confirmed_scope,supplier_portal_reading}_test.dart`,
`test/widget/{supplier_catalog_context,supplier_concentration_table_responsive,supplier_workspace_navigation}_test.dart`,
las 21 migraciones `20260824400000`–`20260824600000` y sus `manual_checks`.

**Modificados por mí (ediciones acotadas dentro de archivos que ya venían
sucios):**
`supabase/functions/_shared/ai_agent/{cards.ts,runtime.ts,tool_registry.ts}`,
`lib/modules/ai_assistant/models/{ai_agent_gateway_contracts,ai_assistant_turn_contracts}.dart`,
`lib/modules/purchases/{models/intelligent_purchasing_models.dart,pages/intelligent_purchasing_workspace_page.dart,services/intelligent_purchasing_service.dart,widgets/purchase_visual_language.dart}`,
`.github/{copilot-instructions.md,GUI_DESIGN_PRINCIPLES.md}`,
`docs/architecture/{canonical-ui-surfaces,product-identity-matching-contract}.md`.

> ⚠️ `cards.ts` (+771 líneas) y `tool_registry.ts` (+563) traen **mucho más que
> mis cambios**: el grueso ya estaba sucio antes de este chat. Mis ediciones son
> las marcadas con comentarios sobre `entityIds`, el título «Los primeros N» y
> «Los valores SÍ se traducen». **No asumas autoría del resto.**

### Prohibiciones explícitas

**No** limpiar, revertir, `git restore`, `git stash`, stagear, commitear,
pushear, abrir PR ni desplegar nada más **sin cerrar los gates y con
autorización explícita del dueño**. Antes de mover `origin`: comprobar que Codex
no esté publicando desde este mismo checkout (árbol limpio, sin procesos de
gate, `HEAD == origin`).

### Sesión Flutter canónica — NO MATARLA

```
screen : 72630.payroll  (Detached)
flutter run : PID 72633  (-d macos -t lib/main.dart)
app         : PID 74175  build/macos/Build/Products/Debug/vinabike_erp.app
```

Es **una sola** sesión y es la canónica. Recuperación:

```bash
scripts/dev/native_session.sh reload      # hot reload
scripts/dev/native_session.sh restart     # hot restart
scripts/dev/native_session.sh log 80
scripts/dev/native_session.sh errors
open build/macos/Build/Products/Debug/vinabike_erp.app   # traerla al frente
```

Antes de lanzar cualquier `flutter run`, inspecciona si ya hay proceso vivo.
**Nunca** arrancar una segunda ni matar la existente; si pierdes el handle,
repórtalo y recupera el control deliberadamente.

> Tras un `restart`, un `hot reload` que agrega un **campo nuevo a una clase**
> deja instancias viejas sin él y produce
> `type 'Null' is not a subtype of type 'int'`. Es artefacto del reload: reinicia
> antes de concluir que hay un defecto.

---

## 8. Pendientes y riesgos residuales (priorizados)

| # | Pendiente | Observable | Riesgo |
|---|---|---|---|
| 1 | **CERRADO 2026-08-24:** suite Flutter completa tras los cambios de fichas y del gate | `scripts/run_flutter_test_gate.sh` + Web Locks en Chrome | Sin bloqueo residual del gate |
| 2 | **`rotor_floating`** (boolean, 3 hechos) sigue `is_filterable = false` | consulta de §6.3 | Bajo |
| 3 | **Sólo cámaras están pobladas.** Neumáticos, llantas, cadenas, cassettes… siguen con ficha vacía | `spec_facts` por categoría | **Alto** — el asistente sólo brilla en cámaras |
| 4 | El **fallback** resuelve vocabulario cerrado pero **no rangos**; si el modelo no estructura, «2.1» se ignora en silencio | comparar frase con y sin predicados | Medio — divergencia fallback/estructurado |
| 5 | **Unidades compuestas y no cubiertas**: `26x1.95` (calce), pulgadas con `"`, `700x28C`, fracciones en la frase (no en el nombre) | matriz §9 | Medio |
| 6 | El gate **no cubre** peticiones técnicas **sin número** («cámara reforzada», «tubeless ready») | matriz §9 | Medio |
| 7 | **`presentation:"answer"` está exento del gate**: si el modelo elige «answer» para una petición del operador, no filtra por ficha | receipts de `assistant_tool_receipts` | Medio |
| 8 | **Documento de compra de prueba** `PED-202608-47947` (RBX, borrador, $8.060) quedó en «Documentos de compra» | lista de compras | Bajo — el dueño decide si lo borra |
| 9 | **`p_limit` tope 10** en `assistant_search_inventory_v7`: con 15 coincidencias el operador ve 10 y `hasMore`. La lista **no** puede abrir las 15 | tarjeta «Los primeros 10» | Medio |
| 10 | Estado de producción/deploy/migration history **debe releerse** antes de asumir nada | §7 | — |

---

## 9. Campaña obligatoria de pruebas del chat nuevo

**Producción read-only por defecto.** Ejecutar **en la app real** (sesión
canónica de §7), en el **Asistente IA** y en el **Asistente de compras** según
corresponda. Registrar por cada fila: inspección de esquema observada, tool
call/predicados reales (de `assistant_tool_receipts` y `assistant_messages`),
filtros visibles en la tarjeta y productos devueltos. **Corregir sólo defectos
reproducidos**, y verificar cada arreglo con read-back.

> El chat nuevo **debe generar más preguntas propias** además de esta matriz.

### Nivel simple

| # | Intención | Frase natural | Inspección esperada | Predicados esperados | Resultado esperado |
|---|---|---|---|---|---|
| S1 | Encontrar por medida | `camaras 29` | `wheel_size` | `wheel_size in ["29\""]` | Sólo cámaras 29 |
| S2 | Unidad pegada | `camaras 26 de 48mm` | + `valve_length_mm` | `+ valve_length_mm in ["48"]` | Filtro de largo aplicado |
| S3 | Unidad separada | `camaras 26 de 48 mm` | igual que S2 | igual que S2 | **Idéntico a S2** |
| S4 | Vocabulario de taller | `camaras 26 valvula de auto` | `valve_type` | `valve_type in ["Schrader (americana / auto)"]` | Sin Presta en la lista |
| S5 | Sinónimo local | `camaras 29 francesa` | `valve_type` | `... ["Presta (francesa)"]` | Sin Schrader |
| S6 | Código, **no** medida | `RD-M6100` | **ninguna** (no debe gatillar el gate) | `[]` | Búsqueda por nombre |
| S7 | SKU | `6927116100261` | ninguna | `[]` | El producto exacto |
| S8 | Control lingüístico | `el pedido va manana` | ninguna | `[]` | **No** filtra válvulas |

### Nivel intermedio

| # | Intención | Frase natural | Predicados esperados | Resultado esperado |
|---|---|---|---|---|
| M1 | **Contención de rango** | `que camara me sirve para un neumatico 26x2.1` | `wheel_size 26"`, `tube_width_min_in ≤ 2.1`, `tube_width_max_in ≥ 2.1` | Sólo cámaras cuyo rango cubra 2.1 |
| M2 | Rango en ruta (mm) | `camara para 700x28` | `wheel_size 700c`, `tube_width_min_mm ≤ 28`, `max_mm ≥ 28` | Cámaras de ruta que cubran 28 mm |
| M3 | Tres atributos | `camaras 26 schrader 48mm con stock` | los tres + `availability in_stock` | Sólo con stock > 0 |
| M4 | Booleano | `camaras con liquido sellante` | `tube_has_sealant eq true` | Las 8 declaradas |
| M5 | Material | `camaras de butilo 29` | `tube_material`, `wheel_size` | Filtro aplicado |
| M6 | Negación | `camaras 26 que no sean presta` | `valve_type neq Presta` | Sin Presta |
| M7 | Nombre incompleto | `camara ornate` | por nombre + posible ficha | Encuentra la ORNATE |
| M8 | Técnico **sin número** | `camaras tubeless ready` | ⚠️ el gate no lo cubre hoy | Observar y documentar |

### Nivel complejo

| # | Intención | Frase natural | Esperado |
|---|---|---|---|
| C1 | Compras · concentración | `a quien le compramos mas camaras 29` | Ranking de proveedores con participación y costo, eje **sin flete** por defecto |
| C2 | Proveedor · catálogo | Abrir ficha de RBX desde la tabla | Catálogo encabezado por lo que coincide, con rótulo y aviso de búsqueda ampliada |
| C3 | Asignación a pedido | Agregar 2 productos → split pane | Documento vivo, totales que cambian, PDF real |
| C4 | Sustituto/compatibilidad | `que camara reemplaza a la CST 26x1.9/2.125` | Debe proponer equivalentes por rango + válvula, **no** por nombre |
| C5 | Compatibilidad cruzada | `esta camara sirve para una llanta de 21mm interno` | Observar: hoy probablemente **no** hay puente cámara↔llanta |
| C6 | Ficha técnica | Abrir Ficha Técnica de una cámara | 9 campos, ancho numérico, sellante, material |
| C7 | Medida compuesta | `camara 27.5 x 2.25 valvula americana 48` | Los cuatro predicados |
| C8 | Fracción en la frase | `camara 24 x 1 3/8` | ⚠️ el nombre lo soporta; **la frase probablemente no** |
| C9 | Compras · lista | `necesito camaras 26 y 29, dime a quien le compro` | Cobertura de canasta y reparto |
| C10 | Proveedores | `que proveedores tienen camaras schrader` | Cruce proveedor × ficha |

---

## 9.bis Resultado de la campaña (ronda del 2026-08-24, chat nuevo)

Ejecutada en la app real, sesión canónica, datos de producción. Read-back por
fila: recibos de `assistant_tool_receipts` (`provider_attempt_id`, `status`,
`failure_code`) y el texto de `assistant_messages`, que **embebe las chips de la
tarjeta** (`autoOpenListAnswer` las concatena). Las tarjetas **no** se persisten:
`assistant_messages.cards` está en `[]`.

### Simple: 8/8 ✅

`camaras 29`, `camaras 26 de 48mm`, `camaras 26 de 48 mm`, `camaras 26 valvula
de auto`, `camaras 29 francesa` disparan el gate (`schema_discovery_required`),
inspeccionan y filtran por ficha. S3 es **idéntico** a S2, así que la unidad
pegada quedó cerrada. `RD-M6100` y el SKU `6927116100261` **no** gatillan y
buscan por nombre, que es lo correcto. `el pedido va manana` ruteó a tareas y
dejó la tarea **por confirmar**, sin escribir.

### Intermedio: 8/8, con un defecto que se corrigió

M1, M3, M4, M5, M6, M7 correctos. Verdad de contraste medida: M1 → 24 cámaras
26" cubren 2.1 y **7 tienen stock**; el asistente listó exactamente esas 7.

- **M2 `camara para 700x28` — defecto, corregido.** Ver §11.
- **M8 `camaras tubeless ready`** degrada a búsqueda literal: el gate no cubre
  peticiones técnicas **sin número**. Pendiente #6, confirmado.

### Complejo

- **C1 / C10 — defecto, corregido.** Ver §11.
- **C4** (sustituto de la CST 26x1.9/2.125) responde bien, pero por un camino
  frágil: **una sola búsqueda por nombre** de 10 filas, leyendo la ficha desde
  `technicalSpecs`. Acertó porque los 5 candidatos cabían en el tope de 10.
- **C7** `camara 27.5 x 2.25 valvula americana 48` aplica **los cuatro**
  predicados: 3 dan 8 productos, con la contención de 2.25 dan **2**, y devolvió
  2. Pero **las chips técnicas están capadas en 3** (`chips.slice(0, 3)` en
  `cards.ts`), así que el rótulo muestra 3 de 4 y el operador no ve el filtro que
  redujo 8 → 2.
- **C8** `camara 24 x 1 3/8` acierta (2 de 8), pero **por el nombre**: chips
  sólo `24"`, sin contención de ancho. La fracción no se traduce a 1.375; sale
  bien únicamente porque el catálogo la escribe igual. Pendiente #5.
- **C5** (cámara ↔ llanta 21 mm interno) se respondió con **cero recibos**:
  conocimiento general del modelo, sin puente en la ficha. Una respuesta sin
  recibos se ve idéntica a una fundamentada.
- **C9** intacto: `rank_basket_suppliers` en **una** llamada.

### Preguntas propias agregadas

| # | Frase | Resultado |
|---|---|---|
| N5 | `cual es la camara 29 mas barata que tenga stock` | ✅ correcta; hay **empate a $7.000 entre tres** y eligió la de más stock, pero no dice que hay empate |
| N6 | `tengo un neumatico 27.5x2.4, que camara le sirve` | ✅ encuentra la MAXXIS 1.75/2.4 con stock 7 y separa las agotadas |
| N7 | `que ficha tecnica tiene la camara CST 26x1.9/2.125` | ✅ seis campos correctos en una llamada, vía `technicalSpecs` |

### Medición de ruido, no regresión

`search_inventory` rechazada por `invalid_tool_arguments`: **7,7 % hoy**, dentro
de la banda histórica (3,8 % – 11,4 %). Es intermitente —la misma frase pasó
limpia al repetirla—, no determinista, y no se tocó.

---

## 11. Defectos corregidos en esta ronda

### 11.a `rank_purchase_suppliers` estaba muerta en producción (P0)

**Síntoma:** «que proveedores tienen camaras schrader» → cuatro llamadas
fallidas, presupuesto agotado y **ninguna respuesta**: el operador leía «No pude
procesar esa solicitud ahora. Intenta de nuevo en unos segundos», y reintentar
no iba a funcionar nunca. «a quien le compramos mas camaras 29» sobrevivía sólo
porque el modelo se replegaba a `rank_basket_suppliers`.

**Causa:** `validateEnvelope` exige claves exactas. La migración
`20260824530000_cost_with_or_without_freight.sql` agregó `averageBaseUnitCostNet`
al motor de concentración y la lista `fields` de `tool_executor.ts` no se
actualizó. La RPC devolvía `status: success` y el ejecutor botaba cada fila.

**Read-back:** 7/7 correctas el 23-08 → 6/6 caídas el 24-08 → **1 llamada
exitosa con 5 proveedores** tras el arreglo.

**Arreglo:** declarar `averageBaseUnitCostNet`. La regla general quedó en
`docs/development/AGENT_DATABASE_CONTRACT.md`.

### 11.b La compuerta era ciega a las medidas compuestas (P1)

**Síntoma:** «camara para 700x28» → sin inspección, respuesta en prosa armada
por nombre que enumeró 5 cámaras con SKU y stock **saltándose una con 2 unidades
disponibles** (`NNV25`) y 7 del catálogo. Por ficha: **12 cubren 28 mm, 3 con
stock**.

**Dos causas, las dos deterministas:**

1. `inventoryQueryNamesAMeasurement` exigía que el número fuera **token
   propio**, de modo que `700x28`, `26x2.1`, `26×1.95`, `12x142` no se veían.
   Esto **no** contradice que el tokenizador del servidor se niegue a partir
   `26x1.95`: partirlo inventa un valor, reconocerlo sólo obliga a mirar la
   ficha.
2. La exención de `presentation: "answer"` estaba trazada en el eje equivocado.
   Una prosa que enumera SKUs engaña **más** que una lista equivocada.

**Lo que reemplaza la exención:** el **abanico del turno**. Varias búsquedas de
inventario en un mismo turno son líneas de una canasta; una sola es la respuesta
del operador. Verificado con los recibos: las dos búsquedas de «700x28» llegaron
con `provider_attempt_id` distinto; las de una canasta comparten turno.

**Read-back:** «camara para 700x28» ahora inspecciona y devuelve **8**, con
`NNV25` encabezando. «26x2.1» pasa de prosa sin filtro a chips
`26" · ≤ 2.1 · ≥ 2.1` con lista abierta.

### 11.c Cobertura

`deno test --allow-read supabase/functions/_shared/ai_agent/` → **248 passed,
0 failed** (eran 244; se agregaron 4). La rama de la compuerta **no tenía
ninguna prueba** antes de esta ronda. La regresión de proveedores se comprobó
que muerde: se quitó el campo, quedó roja, se restauró y quedó verde.

**Gateway desplegado** con autorización explícita del dueño en esta tarea:
`scripts/supabase_cli.sh functions deploy ai-agent-gateway --project-ref
xzdvtzdqjeyqxnkqprtf` → 311 kB, `{"message":"Deployed Functions."}`. **No se
desplegó ninguna migración ni se escribió en producción.**

---

## 12. El defecto que queda diagnosticado y sin corregir

**`populatedCount` cuenta la categoría entera, no el alcance preguntado.**

Tras el arreglo, «camara para 700x28» filtra por `wheel_size = 700c` pero **no**
emite la contención `≤ 28 · ≥ 28`, y por eso todavía deja fuera `19005`
(Presta, **stock 4**). No es falta de traducción ni de datos:

- El inspector anuncia `tube_width_min_mm` / `max_mm` con **31 de 128**
  poblados. El modelo ve un campo que el 76 % del catálogo no tiene y
  razonablemente evita filtrar con él, porque eso escondería casi todo.
- Pero los datos están **correctos y completos**: read-back por aro →
  **28 de 28 cámaras 700c tienen ancho en mm y ninguna en pulgadas**; las 26",
  29" y 27.5" lo tienen en pulgadas y ninguna en mm. El reparto es exactamente
  el que corresponde: ruta en mm, montaña en pulgadas.

O sea: la cifra es exacta por categoría y **engañosa como respuesta**, que es el
mismo defecto de «un número sin referente». Para una consulta de 700c la
cobertura real es 100 %.

**Por qué no se corrigió acá:** el arreglo vive en
`assistant_inspect_inventory_schema_v3` (migración, escritura en producción) y
`populatedCount` lo consume además `firstUnpopulatedTechnicalField` en
`runtime.ts` para decidir `missing_structured_data`. Cambiar su semántica sin
diseñar las dos puntas rompería ese guard. Si además se agrega una clave nueva
al sobre, hay que declararla en `fields` **en la misma tarea** (§11.a).

### Otros pendientes con costo ya medido

| # | Pendiente | Medición de esta ronda |
|---|---|---|
| 1 | `p_limit` tope 10 | «26x2.1» calza con 24 productos: con `availability: any` los 10 primeros dejaron fuera **2 con stock**. El filtro es correcto; la respuesta se trunca |
| 2 | Chips técnicas capadas en 3 | C7 aplicó 4 predicados y el rótulo muestra 3: el filtro que redujo 8 → 2 es invisible |
| 3 | Gate sin cobertura para lo técnico **sin número** | M8 `camaras tubeless ready` |
| 4 | Fracciones en la frase | C8 acierta por coincidencia de escritura, no por ficha |
| 5 | Sólo cámaras pobladas | sigue siendo lo de mayor valor de negocio |

---

## 13. Segunda ronda del 2026-08-24 — cerrar los pendientes

El dueño pidió mejorar todo lo que la ronda anterior dejó diagnosticado. Esto
es lo que se cerró, con su read-back.

### 13.a Neumáticos: de 0 a 113 fichas (el pendiente de más valor)

Era el pendiente #3 —«sólo cámaras pobladas»— y **Neumáticos es la segunda
categoría del catálogo**: 113 productos con **cero** ficha, y la contraparte
natural de la cámara.

La infraestructura ya existía y nadie la había usado: plantilla `tire` con seis
campos (`wheel_size`, `tire_width_in`, `tire_width_mm`, `tire_bead_type`,
`tire_tubeless_ready`, `tire_etrto`), la categoría mapeada a la familia `tire`,
y las seis definiciones `is_filterable`. Faltaba **leer los nombres**.

Migración `20260824610000_fill_the_tire_specs_from_their_names.sql`, verificada
con `verify_tire_specs_filled.sql` (cuatro afirmaciones que muerden):

| | |
|---|---|
| neumáticos | 113 |
| con ficha | **113** |
| hechos | **257** |
| aro | 113 |
| ancho en pulgadas / en mm | 86 / 26 |
| talón | 29 |
| tubeless ready | 3 |
| leídos del nombre / deducidos | **257 / 0** |
| confirmados falsos · hechos sin valor · anchos fuera de rango | **0 · 0 · 0** |

Las cuatro trampas del parseo y la razón por la que **no se dedujo** el talón
—los techos de precio se solapan, a diferencia del sellante— quedaron en
`docs/architecture/product-identity-matching-contract.md`.

**Capacidad nueva verificada en la app**, que antes era imposible:

> «vendi el neumatico maxxis ardent 29x2.4, que camara le pongo»

resolvió el neumático por ficha (29″, 2.4″), buscó cámaras cuyo rango cubriera
2.4 y devolvió **exactamente las 2 que existen con stock** (SKU 4717784040202
y 4420), separando las de rango ajustado con una advertencia honesta.

Y «que neumaticos tubeless ready tengo» —el pendiente #6, técnico sin número—
ahora devuelve **los 3 exactos** con su ficha, diciendo que están agotados.
Antes devolvía 10 neumáticos cualesquiera.

### 13.b La cobertura ya no hace que el modelo descarte un campo

El defecto de §12: el inspector anuncia `populatedCount` sobre toda la
categoría (31 de 128 para el ancho en mm) cuando para una consulta de 700c la
cobertura real es 28 de 28. El modelo veía un campo escaso y no filtraba.

Se corrigió **donde estaba la causa alcanzable sin migración**: la descripción
de `technicalPredicates` ahora dice que una cobertura baja **no** significa un
dato faltante —el ancho vive en dos campos según la unidad, y cada uno cubre su
mitad—, que el campo se elige por la **unidad** de lo que dijo el operador, y
que una fracción de taller es un número (`1 3/8` = 1.375).

| Frase | Antes | Después |
|---|---|---|
| `camara para 700x28` | chips `700c`; **2 de 3 con stock** | chips `700c · ≤ 28 · ≥ 28`; **las 3 con stock**, con la Presta de 4 unidades que faltaba |
| `que camara me sirve para un neumatico 26x2.1` | 5 de 7 con stock | **las 7**, que es la verdad de contraste |
| `camara 24 x 1 3/8` | chips `24"`; acertaba **por el nombre** | chips `24" · ≤ 1.375 · ≥ 1.375`: por ficha |

### 13.c La lista truncada dice de cuántas

«Los primeros 10» no decía de cuántos. Ahora el título dice **«Los primeros 10
de 31»**, verificado en la app y contra la base (31 cámaras 26″ exactas).

**Dos cosas que costó descubrir:**

1. **El total NO puede viajar en `listRef`.** El decodificador Dart exige claves
   exactas (`_requireExactKeys`), así que una clave nueva ahí haría que las apps
   ya publicadas rechacen toda tarjeta de inventario. Va en el **título**, que
   es texto libre de 160 bytes. (`spokenSubject` ya usaba ese mismo patrón de
   campo server-only.)
2. **`totalMatches` del sobre está mal.** `assistant_search_inventory_v7`
   devuelve `hasMore: true` y `totalMatches: 10` a la vez —contradictorio
   consigo mismo— mientras `matchedCount`, que viaja en **cada fila**, decía 24,
   que es la verdad. El título lee `matchedCount`. Arreglar `totalMatches` en la
   RPC queda como pendiente, pero ya no bloquea nada.

### 13.d Gates

`deno test --allow-read supabase/functions/_shared/ai_agent/` → **248 passed,
0 failed** después de cada cambio. Las dos regresiones nuevas se comprobó que
muerden: se rompió el código a propósito, se vieron rojas y se restauraron.

Gateway desplegado cuatro veces en total esta jornada (última: 313 kB).
Migración `20260824610000` aplicada, verificada y estampada.

### 13.e Lo que sigue abierto, en orden de valor

| # | Pendiente | Estado medido |
|---|---|---|
| 1 | **El resto del catálogo sin ficha** | Pastillas 49, Rayos 48, Llantas 41 (6 con ficha), Maza 40, Desviador trasero 34, Shifters 32, Cadenas 31. El procedimiento está probado dos veces: ensayo en seco → migración → verificación |
| 2 | `p_limit` tope 10 | Ahora al menos se **ve** («de 31»), pero la lista sigue sin poder abrir las 31 |
| 3 | `totalMatches` de la RPC de búsqueda | Devuelve el tamaño de página; necesita migración. `matchedCount` ya da la verdad |
| 4 | `populatedCount` por categoría | Mitigado por el prompt, no corregido en la fuente (§12) |
| 5 | Chips técnicas capadas en 3 | C7 aplica 4 predicados y el rótulo muestra 3 |

---

## 10. Próximo paso exacto para el chat nuevo

1. **Leer `AGENTS.md`** y los documentos que enruta, y **este handoff completo**.
2. **Reconfirmar estado real**, sin confiar en los números de aquí:
   ```bash
   git rev-parse --abbrev-ref HEAD && git rev-parse HEAD && git status --porcelain | wc -l
   ps ax -o pid,command | grep -E "[v]inabike_erp.app|[f]lutter run"
   screen -ls
   ls -1 .tmp/db/migration-receipts/ | tail -25
   scripts/db/query.sh production --sql "select version from supabase_migrations.schema_migrations where version >= '20260824440000' order by version"
   ```
3. **Confirmar lo ya cerrado** (§3, §4, §5) para **no repetirlo**: las 21
   migraciones, los dos deploys del gateway, las fichas de cámaras y los cuatro
   defectos de la cadena de lenguaje natural están hechos y con read-back.
4. **Continuar desde la primera aceptación abierta**, que es **§9 · la campaña
   de pruebas**. Empezar por el nivel simple (S1–S8), porque valida la cadena
   completa con el menor costo, y seguir con M1–M8 y C1–C10 generando además
   preguntas propias.
5. Ante un defecto: **reproducirlo primero**, diagnosticar con los receipts
   (`assistant_tool_receipts`, `assistant_messages`) y la inferencia SQL antes de
   tocar código, corregir en la capa correcta (§6.3) y verificar con read-back.
6. Cerrar §8 en orden de prioridad. El pendiente **#3 (sólo cámaras pobladas)**
   es el que más valor de negocio desbloquea, y el procedimiento para poblar otra
   categoría está descrito en §4 y en
   `docs/architecture/product-identity-matching-contract.md`.

**No commitear, pushear, desplegar ni limpiar sin autorización explícita.**
