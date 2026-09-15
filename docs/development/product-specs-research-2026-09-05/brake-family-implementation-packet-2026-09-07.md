# Paquete de implementación de frenos — 2026-09-07

Hay **87 parches de representación**, **17 definiciones nuevas**, **13 relaciones ejecutables schema2** y **65 casos de relación** preparados contra la base congelada de **105 plantillas**. La transformación pasa por el integrador existente y sus validadores; el probe Dart pasa **82/82** pruebas. El paquete cubre 19 plantillas de frenos y consumibles relacionados. **No está aplicado, no rellena productos y no declara ninguna familia mecánicamente completa.** Root conserva la adjudicación final y los despliegues.

El artefacto consumible es [brake-family-implementation-packet-2026-09-07.json](/Users/Claudio/Dev/bikeshop-erp/docs/development/product-specs-research-2026-09-05/brake-family-implementation-packet-2026-09-07.json). Su entrada es [all-family-reviewed-fields-2026-09-06.json](/Users/Claudio/Dev/bikeshop-erp/docs/development/product-specs-research-2026-09-05/all-family-reviewed-fields-2026-09-06.json), SHA256 `7ebf2b5b5e69784e3d146b81ad2bec8b7581113565cef022e8da70ba4c7a66fa`. Los `before` están ligados a esa base; deben volver a comprobarse al integrar A/B. No usé las interfaces narrativas del antiguo documento compilado como si fueran un lenguaje ejecutable.

## Qué se puede integrar

| Plantillas | Cambio concreto | Límite que conserva |
|---|---|---|
| `brake_caliper`, `brake_lever` | Circuito local frente a conexión de manguera externa; fluidos admitidos por modelo; conexiones por extremo; purga separada de herramienta y nominal de espesor del rotor previsto por el cáliper | Hidráulico no implica disco ni entrada hidráulica. El tiraje de cable sigue aplicando al híbrido |
| `hydraulic_disc_brake`, `mechanical_disc_brake`, `rim_brake` | Circuitos incluidos por posición, con modelos, manguera y rotor en la misma fila | Un par no es una lista global de longitudes/diámetros intercambiables |
| `rim_brake` | Accionamiento explícito, geometría de montaje por filas, soporte HSi, alcance mínimo/máximo ordenado | Un freno hidráulico de llanta no exige tiraje de cable |
| `brake_shift_combined_control` | Puerto de freno con su accionamiento y guardas propias | Las velocidades y el accionamiento del cambio no determinan el freno |
| `brake_pad` y cálipers | Posición/variante en filas de modelos, denominación OEM de compuesto y código del retén | Marca, número de pistones o un código libre no prueban geometría; orgánico no se convierte automáticamente en resina |
| `rotor`, `brake_mount_adapter`, `rotor_mount_adapter` | Separar nominal/desgaste y conservar ruta direccional, anclaje base, posición y diámetro en una fila | El máximo del adaptador no sustituye el de la horquilla/cuadro; no se inventa mínimo de 160 mm |
| `hydraulic_hose`, `hydraulic_fitting`, `brake_fluid` | Código completo, aplicaciones por modelo/extremo e inserto con su medida descriptiva | Diámetro exterior o clase de fluido iguales no prueban sellado ni formulación |
| `control_cable`, `control_housing`, `control_small_part` | Cabezas por extremo; función, construcción y diámetro de funda separados | Un control integrado tiene puertos diferentes; doble cabeza no significa compatibilidad universal |
| `brake_small_part`, `hub_brake`, `bmx_cable_detangler` | Conservar declaraciones por modelo y desconocidos | No se siembran compatibilidades de piezas genéricas sin OEM exacto |

Los resúmenes ambiguos de racores/purga, adaptadores y funda pasan a `legacy` mediante el contrato de roles; se conservan las definiciones y la historia. No hay conversión de datos ni sustitución automática de valores. `brake_hose` no existe como plantilla separada en la base: la posible asignación a `hydraulic_hose` requiere confirmar identidad y función.

Las operaciones del JSON son las que ya admite `apply_reviewed_field_addendum`: 44 `add_field`, 33 `replace_field_contract`, cuatro `append_allowed_values`, tres `append_row_columns` y tres `replace_template_coherence`. Estas últimas usan los vínculos por **ID de fila** y el orden de escalares de 0200, ya disponibles. No agregué `row_match`, `counterpart_field`, `allOf`, cierre por `exhaustive` ni un DSL nuevo.

## Reglas intrínsecas, modelos y desconocidos

Sólo se presentan como condiciones intrínsecas necesarias la categoría de puerto **directo** y el uso declarado de funda para la carga del puerto de freno. Puertos del mismo tipo dejan otras interfaces pendientes. Un convertidor intermedio es otra ruta, incluso cuando las parejas directas de tiraje están excluidas. También se validan tipos, cardinalidad, dimensiones positivas, orden de rangos y vínculos existentes; esas reglas estructurales no certifican ajuste mecánico. [Sheldon Brown](https://www.sheldonbrown.com/cantilever-adjustment.html), [Park Tool: cables y fundas](https://www.parktool.com/en-us/blog/repair-help/brake-housing-cable-installation-drop-bars).

Las relaciones por modelo conservan sus fuentes dentro de cada fila. Los casos representativos son:

| Casos | Declaración acotada | Resultado esperado |
|---|---|---|
| PL01–PL06 | FR-5/BB7 MTB y BL990/BB7 Road; FR-5/BB7 Road en conexión directa | Las parejas documentadas pasan esta interfaz; el cruce directo de tiraje se excluye. Una ruta con convertidor queda fuera de esta declaración |
| FL01–FL06 | S-900 Aero HRD, edición 2019 Rev B | DOT 4/5.1 sólo bajo la condición OEM registrada; DOT 5 y mineral excluidos. La regla no se traslada a otro SRAM |
| FL07–FL12 | Maven con el fluido Maxima identificado; MAGURA HS2017 con Royal Blood | La formulación/producto importa. Mineral sin identidad no se aprueba; DOT contradice esos sistemas |
| HY01–HY05 | HY/RD Flat Mount delantero con FF-5 | La presencia del adaptador satisface sólo ese requisito; ausencia/identidad desconocida impiden confirmar la ruta, sin exclusión global |
| PD01–PD05 | TRP HD-M803 / HD-R802, pastilla y posición según tabla 2024 | Se conserva la fila completa. Intercambiar delantero/trasero o unir listas no fabrica una aprobación |
| PD06–PD09 | SM-RT56 y compuesto de pastilla | Resina documentada satisface esta interfaz; metálico contradice la restricción. Orgánico sin equivalencia OEM queda sin confirmar |
| AD01–AD16 | SM-RTAD05 y aplicaciones seleccionadas SM-MA-F180P/P2 | Dirección, límite de 203 mm, exclusiones RT86/RT76, posición y anclaje base se comprueban por separado |
| HO01–HO05 | Inserto dedicado BH90/BH59 | No intercambiar aplicaciones. Medir 11.2 mm no identifica por sí solo un inserto BH90 ni aprueba la manguera completa |
| CA01–CA07 | Funda para freno y extremo de cable BL990 | Cambio solamente no sirve para el puerto de freno. Una lista de cabezas no sustituye la cabeza elegida |

Fuentes de esas declaraciones: [SRAM Frame Fit, página impresa 135](https://www.sram.com/globalassets/document-hierarchy/frame-fit-specifications/mtb/2024-mtb-frame-fit-specifications.pdf), [BL990 Rev A](https://www.sram.com/globalassets/document-hierarchy/user-manuals/sram-road/brakes/1355244027_95-5215-003-000_rev_a_bl990_aero_brake_lever1.pdf), [S-900 Aero HRD](https://www.sram.com/globalassets/document-hierarchy/service-manuals/sram-road/brakes/gen.0000000005452-rev-a-s-900-aero-hrd-service-manual.pdf), [Maven](https://support.sram.com/hc/en-us/articles/23147687539099-Which-is-the-right-brake-fluid-for-my-SRAM-Maven-mineral-oil-brake), [MAGURA HS2017](https://api.magura.com/medias/sys_master/maguracom-medias/h4c/hd0/9603888545822/hs_manual_2017_en/hs-manual-2017-en.pdf), [HY/RD](https://trpcycling.com/products/hy-rd), [tabla TRP de pastillas](https://cdn.shopify.com/s/files/1/0840/7783/8623/files/2024_TRP_disc_pad_compatibility_0827.pdf?v=1725392452), [Shimano SM-RT56](https://bike.shimano.com/en-NA/products/components/pdp.P-SM-RT56.html), [Shimano MDBR001](https://si.shimano.com/en/pdfs/dm/MDBR001/DM-MDBR001.pdf), [Shimano C-193/C-195](https://productinfo.shimano.com/en/compatibility/C-193). El JSON registra sección, edición y alcance individual; no se adjudicaron colores de matrices.

Hay límites deliberados. SRAM documenta más de 32 mm de tiraje con BB7 MTB como compatible con menor potencia: no corresponde inventar un corte universal. Las fichas de Park remiten al fabricante para espesores/límites; sus ejemplos históricos no son una tabla universal actual. Además, dos URL consultadas conservan nombres de revisiones viejas: `2024-mtb...` entrega Rev C ©2026 y la URL `rev-a` de S-900 entrega contenido Rev B ©2019. Una referencia publicada debe conservar la edición real y su recibo de fuente, no sólo el enlace. [SRAM Frame Fit](https://www.sram.com/globalassets/document-hierarchy/frame-fit-specifications/mtb/2024-mtb-frame-fit-specifications.pdf), [Park Tool: rotores](https://www.parktool.com/en-us/blog/repair-help/disc-brake-rotor-removal-installation), [S-900](https://www.sram.com/globalassets/document-hierarchy/service-manuals/sram-road/brakes/gen.0000000005452-rev-a-s-900-aero-hrd-service-manual.pdf).

## Consumidores reales y reproducción

La ruta pública `buildAutocompleteAssessments`, con `primeCompatibilityCaches` y sin DB, reprodujo tres problemas/limitaciones antes de la corrección de root:

1. HY/RD, circuito mineral y bici `mechanical_disc`: `incompatible` por inferir hidráulico desde el fluido.
2. HS33, circuito mineral y bici `rim`: el mismo falso bloqueo.
3. Una exclusión schema2 se podía parsear y evaluar como `excluded` directamente, pero el consumidor devolvía idéntico `caution` con y sin `__reference_claims`.

El probe anterior permanece congelado en [brake-packet-review-probe.dart](/Users/Claudio/Dev/bikeshop-erp/.tmp/product-spec-catalog/brake-packet-review-probe.dart), con **3/3** assertions del comportamiento anterior. No se capturó el hash del servicio en ese primer run: el hash actual del JSON es posterior y no se atribuye a esa prueba. Las dos primeras expectations describen el defecto antiguo y no deben exigirse verdes después del arreglo.

Root retiró el atajo de fluido. Mi lectura diferencial confirma el cambio en [bike_product_compatibility_service.dart:2363](/Users/Claudio/Dev/bikeshop-erp/lib/modules/bikeshop/services/bike_product_compatibility_service.dart:2363), que ahora compara superficie explícita y trata el fluido como dato insuficiente. Sus pruebas y runtime pertenecen a root. Permanece la conexión completa de referencias con el extremo elegido: [productSpecClaimSummary:41](/Users/Claudio/Dev/bikeshop-erp/lib/modules/inventory/models/product_spec_contract.dart:41) sólo forma un resumen; no hallé llamadas de los consumidores versionados a `ProductSpecRelation.evaluate`. El assessor SQL aparece en su definición/revoke de [180000:174](/Users/Claudio/Dev/bikeshop-erp/supabase/migrations/20260906180000_product_spec_scoped_relations.sql:174). Esto es evidencia del código inspeccionado, no una consulta del catálogo de funciones productivo.

La política de integración debe conservar cuatro estados: `excluded` bloquea confirmar/usar **esa configuración**; `supported` sólo cubre la interfaz nombrada; `outside_declared_scope` y `unknown` no confirman y no se convierten en imposibilidad global. Una ruta que requiere un adaptador conocido ausente tampoco puede confirmarse. Guardar investigación parcial y vender la existencia física de un producto son decisiones diferentes de certificar su montaje.

## Qué queda antes del llenado

- **EG01/02:** proyección por IDs de referencias y por rueda/circuito; conectar y agregar las relaciones sin mezclar posiciones ni inferir modelo desde nombre, marca o velocidades.
- **EG03:** 0200 enlaza filas, pero no expresa todavía `adapter_required=true → adapter_model` ni `fluid_class=Mineral → formulación` dentro de una fila. Ambos faltantes se reprodujeron como no bloqueantes. Hace falta validación de completitud mecánica antes de compilar claims o marcar una ficha verificada.
- **EG04:** vincular contenido del kit, cantidades y uniformidad de escalares. El vínculo de una manguera a un circuito existe en este paquete; no certifica por sí solo toda su composición.
- **EG05/08:** el motor de relaciones compara con constantes; no calcula el mínimo dinámico entre límites de cuadro/horquilla/cáliper/adaptador ni expresa grados OEM de rendimiento. Se entregan casos de aceptación pendientes, separados de los ejecutados.
- **EG06:** `hose_length_mm` y `rotor_thickness_mm` tienen `unit=null`. El integrador preserva unidades estables; se entregan dos cambios `before:null → after:mm` como metadata diferida, con auditoría y revisión de datos previa. No se reescala nada.
- **EG07/09/10:** falta investigar geometrías, modelos genéricos y consumibles concretos. Campos obligatorios desconocidos se conservan como investigación parcial; no autorizan llenado verificado. Codex/Claude realizan la investigación, sin trasladar al dueño la digitación rutinaria.

El índice de inventario incluido contiene **190 IDs cribados** del registro del 6 de septiembre: 124 con familia asignada y 66 sin ella. Incluye cables y fundas compartidos con cambios, por lo que **190 no es un conteo de frenos confirmados**. Ni un nombre nominal ni una coincidencia de categoría generó hechos. Se conservan `mechanical_approval:false` y `fill_applied:false` para cada entrada.

A13/A15 ya estaban representados en la base congelada y sus regresiones lo confirman. A12, A14C/L, A17A/B, A18–A22 quedan con parches/relaciones trazados, pero pendientes de consumidor, investigación y verificación de productos. A27–A29 se reflejan en la separación de evidencias y contadores. Los hallazgos de transmisión y W01–W11 permanecen fuera de alcance; este paquete de frenos no cierra ruedas, dirección o suspensión.

## Verificación y entrega

El [probe de contratos](/Users/Claudio/Dev/bikeshop-erp/.tmp/product-spec-catalog/brake-packet-contract-probe.dart) contiene **65 casos schema2 y 17 pruebas de representación**: literales/decimales exactos, desconocidos, cruces de filas, cambio de upstream, relaciones por ID, orden de alcances y límites actualmente no expresables. Pasó con `fvm flutter test --no-pub .tmp/product-spec-catalog/brake-packet-contract-probe.dart --reporter expanded`. Los valores ficticios de pruebas estructurales se marcan como fixtures; no son evidencia OEM.

La compilación pura pasa por `apply_reviewed_field_addendum` y `validate_contract` sobre las 105 plantillas. Las decisiones efímeras usadas para probar la transformación sólo autorizan esa ejecución en memoria; no sustituyen la aceptación final de root. El [generador propio](/Users/Claudio/Dev/bikeshop-erp/.tmp/product-spec-catalog/brake-packet-build.py) sólo escribe los artefactos de este paquete y su archivo temporal.

No ejecuté wrappers SQL, migraciones, lecturas productivas ni runtime en este subtrabajo. Cero escrituras de productos; cero familias declaradas completas. Antes de cualquier llenado quedan la aceptación final de parches/claims, pruebas SQL por el flujo serializado de root, backup/recibos de revisión y fuente, investigación por producto/variante y comprobación del consumidor real.
