# Consumidores del retiro legacy en cáliper, pastilla y rotor (2026-09-15, ronda 226)

Revisión acotada a `brake_caliper`, `brake_pad` y `rotor`. Sólo lectura de
código, migraciones y de la adopción autenticada de Root
(`.tmp/product-spec-catalog/brake-pieces-20260915/adoption.json` y
`snapshots/`, agregados sin datos comerciales); sin producción, sin código, sin
sondas nuevas. No repite las 46 pruebas ni entra en D2.

## 1. Dictamen

**Ninguna ruta viva usa una observación legacy como dato nuevo ni como
compatibilidad.** Los tres consumidores que Root nombra leen por funciones que
excluyen `roles = legacy` o resuelven el campo por la plantilla vinculada:
la ficha pública, el matcher del asistente y de necesidades, y la
compatibilidad de taller. Lo que sí ocurre al aplicar es **pérdida de
visualización y de criterio**, porque las 23 definiciones sucesoras nacen
invisibles al cliente y no filtrables, y ningún consumidor Dart lee todavía
`rotor_diameter_mm_value`. No encontré inferencia mecánica peligrosa: la única
regla de freno del taller nunca emite veredicto, sólo cautelas.

Queda un proyector dormido (`product_spec_values`, §4 R5) que sí conserva los
valores legacy como si fueran vigentes; hoy no lo lee nadie para frenos.

## 2. Qué hay en juego (adopción de Root, agregados)

| Familia | Productos | Observaciones legacy conservadas | Pendientes propuestos más frecuentes |
|---|---|---|---|
| rotor | 18 | `rotor_diameter_mm` 10 · `rotor_thickness_mm` 3 | `rotor_diameter_mm_value` 18 · `rotor_mount_type` 18 · `rotor_material` 15 |
| brake_pad | 53 | `brake_system` 4 | `braking_surface` 53 · prerrequisito `compound_type` 10 |
| brake_caliper | 11 | ninguna | `braking_surface` 11 · `brake_actuation` 11 |

Cero bloqueos, cero observaciones activas sin proyectar, 59 de 82 productos
sin observación alguna. Los 17 hechos legacy están en 13 rotores y 4
pastillas; en cáliperes no hay nada que perder.

Flags de las definiciones (paquete `0346fe79…`): los legacy retirados son
`is_customer_visible = true` y, salvo `tool_size_mm`, `hose_fitting_type`,
`bleed_port` y `reach_adjust`, también `is_filterable = true`. Las 23 nuevas
son `is_customer_visible = false` e `is_filterable = false`; `brake_actuation`
y `brake_external_hose_connection` (existentes, publicadas el 09-07) también
son invisibles y no filtrables.

## 3. Rutas revisadas

**R1 · Ficha pública** (`get_public_product_technical_specs`, anon).
Excluye `legacy` (ronda 223). Al aplicar: 10 rotores pierden «Diámetro del
Rotor», 3 pierden «Espesor», 4 pastillas pierden «Sistema de Freno». Ningún
sucesor aparece aunque se rellene, porque son invisibles. **Pérdida de
visualización, no de verdad.** Comprobación: lectura anónima antes/después de
uno de los 10 rotores con `rotor_diameter_mm` en `retained_legacy_observations`
(ids en `adoption.json`, sin datos comerciales): la fila desaparece y ninguna
nueva la reemplaza.

**R2 · Matcher del asistente y de necesidades** (`assistant_search_inventory_v7`
→ `assistant_inventory_technical_predicate_source_internal_v1`, edge
`tool_executor.ts`). El evaluador resuelve el campo por
`spec_product_field_definition_internal_v1(tenant, product, key)`, que exige
campo de la plantilla vinculada con rol distinto de `legacy`
(`20260906160000:160-183`) y además `is_filterable`; si no, devuelve
`unresolved`. La inferencia de predicados (`assistant_infer_technical_predicates…`,
`20260906191000:36,51-54`) y el inspector de esquema v3 (`:3308-3309`) excluyen
legacy y exigen filtrable. **No hay fuga.** Efectos: (a) un predicado sobre
`rotor_diameter_mm`, `mount_standard`, `brake_type`, `piston_count` o
`fluid_type` pasa a `unresolved` para todo producto de estas familias, es
decir silencio, no falso; (b) `rotor_diameter_mm_value`, `braking_surface`,
`brake_actuation`, `piston_count_value` y `cable_pull_required` no pueden ser
criterio porque no son filtrables: el rotor deja de poder pedirse por
diámetro en el asistente y en necesidades. **Pérdida de criterio.** Las
interpretaciones ya guardadas (`supply_need_interpretation_revisions.constraints`)
que nombren esas claves quedan mudas: Root puede contarlas en producción con
una lectura sobre `constraints::text` y reinterpretarlas.

**R3 · Búsqueda por criterios de proveedor** (`supply_need_effective_criteria.dart`
→ `supplier_need_portal_search.dart`). Los criterios salen de
`supplyNeedCriterionFieldsOf`, que descarta `roleFor(key) == 'legacy'` (:134) y
alimenta `supplyNeedSearchFieldsOf` (:243). **No hay fuga.** Efecto: el mapa
`_identityKindByField` (:2607-2627) traduce `rotor_diameter_mm` y
`rotor_mount_type` a `PartSpecKind`; el sucesor `rotor_diameter_mm_value` no
está, así que una necesidad de rotor pierde el discriminador de búsqueda y la
extracción de diámetro desde el texto del proveedor. `rotor_mount_type` sigue
activo y sigue mapeado. **Pérdida de capacidad, no de verdad.**

**R4 · Compatibilidad de taller** (`BikeProductCompatibilityService` →
`get_product_spec_contexts_v1`). El lector excluye legacy
(`20260906160000:345+`, `<> 'legacy'`) y adjunta `__spec_issues`. La única regla
de freno con datos del producto es `_assessBrakeCompatibility` (:2223-2290): lee
`rotor_diameter_mm`, `fluid_type`, `brake_position` y `braking_surface`, y sus
tres salidas son `caution`; nunca `compatible` ni `incompatible`. Al aplicar,
sin `rotor_diameter_mm` ni `fluid_type` cae a la cautela genérica y el texto
«Coincide el diámetro…» o «Rotor X mm frente a Y/Z mm» deja de aparecer para
los 10 rotores. La rebaja por pendientes (:216) sólo afecta a `compatible`,
que aquí no existe. **Pérdida de texto, sin veredicto perdido ni inventado.**
Latente y ya inerte: `_parseRotorSize` toma con regex el primer `140|160|180|203`
de un texto, de modo que un `180/160` de cáliper (par de freno completo) se
leería como 180; hoy ningún cáliper tiene esa observación y el retiro la
excluye del lector.

**R5 · Proyección `product_spec_values`.** El trigger
`mirror_facts_into_product_specs_internal_v1` (`20260906190000:793`) copia todo
hecho raíz de producto sin mirar el rol: los legacy siguen ahí como vigentes.
Lectores: el inspector v3 ya cuenta hechos (`:3318`), el único lector SQL
restante es el de ejes de pedalier (`20260820220000`), sin lector Dart ni en
`supabase/functions`. **Dormido; único lugar donde legacy parece nuevo.**

**R6 · Otros.** Índice de búsqueda de edición masiva
(`bulk_product_edit_service.dart:150-180`) usa el mismo lector sin legacy:
pierde los tokens del diámetro en 10 rotores (búsqueda, no verdad). Editor y
snapshot (`get_product_spec_editor_context_v3`, `get_product_spec_snapshot_v1`)
muestran legacy rotulado: correcto. Escritores: el guardado rechaza crear o
cambiar un valor legacy («El campo retirado se conserva como legacy…») y la
lectura por IA resuelve el campo con el mismo resolutor sin legacy
(`record_product_spec_reading_v1`, `20260907020000:630`): ningún llenado puede
producir un legacy nuevo. `search_products` no lee hechos.

## 4. Correcciones mínimas y comprobables (en orden de valor)

1. **Flags de los sucesores en el propio paquete, antes de publicar** (cambio
   de `records.spec_definitions`, cero migraciones extra): decidir
   `is_customer_visible` e `is_filterable` para `rotor_diameter_mm_value`,
   `rotor_nominal_thickness_mm`, `rotor_wear_limit_mm`, `piston_count_value`,
   `braking_surface`, `cable_pull_required`, `pad_retention`,
   `rim_pad_stud_type`, `rim_pad_construction`, `rim_pad_length_mm` y la nueva
   `caliper_mount_interface`. `brake_actuation` es definición global ya
   publicada y compartida: su visibilidad es una decisión aparte con su propio
   delta. No asumo aprobado dejar la web sin diámetro de rotor. Comprobación:
   verificador `exact_metadata` (los flags son parte del registro) y lectura
   anónima de un rotor tras la adopción.
2. **Matcher y necesidades:** con `is_filterable` en `rotor_diameter_mm_value`
   el predicado vuelve a resolverse. Comprobación pgTAP: hecho legacy
   `rotor_diameter_mm` → `unresolved`; hecho nuevo `rotor_diameter_mm_value`
   → `match`/`conflict` según valor. Además, conteo y reinterpretación de
   `constraints` guardadas que nombren claves retiradas.
3. **Portal de proveedor (código, Root):** añadir
   `'rotor_diameter_mm_value': PartSpecKind.rotorDiameterMm` en
   `_identityKindByField`; comprobación por prueba unitaria del discriminador
   de una necesidad de rotor.
4. **Taller (código, Root):** `_assessBrakeCompatibility` lee
   `rotor_diameter_mm_value` (numérico; `_parseRotorSize` ya acepta `num`) y
   deja de leer `rotor_diameter_mm`; comprobación con la prueba existente de
   cautela por diámetro usando la clave nueva. Sigue siendo cautela, no
   veredicto.
5. **`product_spec_values`:** no agregar lectores; si alguno aparece, debe
   pasar por `spec_product_field_definition_internal_v1`. No propongo
   filtrar el espejo: borraría historia de la proyección.

## 5. Sobre la decisión de arquitectura de Root

- `caliper_mount_interface` obligatorio en Disco: de acuerdo (H2 de 225).
- Receta OEM opcional con `caliper_mount` y `caliper_model` vetados **sólo en
  este dueño** por `row_conditions` `allowed_when never`: de acuerdo; conserva
  la definición compartida para conjuntos y el motor de filas ya evalúa
  `allowed_when` por columna. Comprobación: una fila con `caliper_mount` bajo
  el cáliper bloquea; la misma fila bajo un conjunto no.
- Puertos de la pinza sólo `Entrada` y purgadores sólo en `brake_bleed_ports`:
  de acuerdo; elimina el doble hogar señalado en 225.
- Recambio de cartucho sin espárrago, con construcción requerida para
  decidirlo: de acuerdo; «Desconocido» en construcción deja el espárrago
  pendiente, que es lo correcto. Cuesta un pendiente más en la adopción de
  las zapatas.

## 6. No afirmo

No leí producción; no rendericé fichas; no juzgo montaje ni compatibilidad; los
conteos vienen de la adopción de Root; la decisión de visibilidad es del dueño.
