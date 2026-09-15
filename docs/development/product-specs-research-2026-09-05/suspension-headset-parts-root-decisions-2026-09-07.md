# Suspensión/dirección: adjudicación independiente antes de publicar

2026-09-07. El candidato inicial de Claude queda sustituido por este sucesor.
No se ha aplicado 20260908011000. 4 plantillas, 45 definiciones, 53 usos, 37 casos.

- Longitud y recorrido son una sola fila por configuración de amortiguador,
  cada cifra con su unidad y referencia de longitud. Una fila sólo de recorrido
  ya no satisface ambas dimensiones. Los extremos usan IDs estables hacia esa
  configuración; no se cruzan extremos homónimos de dos medidas distintas.
  Las fixtures históricas reciben sólo el ID de contexto, sin inventar medidas.
- La ficha oficial [FOX FLOAT DPS PERFORMANCE](https://ridefox.com/products/fox-float-dps-performance)
  publica 972-01-490, Imperial, 7.875 × 2. Es el ancla exacta de la fixture;
  el índice de dibujos no permitía leer sus dibujos incrustados y no se presenta
  como si se hubieran visto. No convertir unidades ni fijar tolerancias.
- [Wolf Tooth Compression Plug](https://www.wolftoothcomponents.com/products/compression-plug),
  CPLUG-STEM5MM-BLK, conserva rango para espiga metálica, profundidad y los dos
  aprietes con sus condiciones. La cifra de tapa incluye grasa ligera sólo en
  las roscas. La interfaz admite nominal, rango y designación literal; no exige
  que toda pieza publique un rango ni confunde exterior e interior.
- Se retiran carbon_safe y steerer_fit escalares de piezas de dirección: ahora
  los objetivos viven por componente. Wolf Tooth excluye araña en espiga de
  carbono. La condición bloquea ese cruce, sin heredarlo a la tapa de un kit.
  [Park Tool](https://www.parktool.com/en-us/blog/repair-help/star-fangled-nut-and-expansion-plug-installation)
  explica la diferencia constructiva, pero su texto recuperado no contiene esa
  prohibición literal; la fuente de la exclusión es Wolf Tooth.
- [Wolf Tooth SPACER-BLK-KIT1](https://www.wolftoothcomponents.com/collections/misc-components/products/wolf-tooth-headset-spacers)
  contiene espesores distintos. Separadores pasa a piezas con cantidad, sistema,
  espesor e interfaz. La designación objetivo y la medición física pueden
  coexistir: no se igualan ni se deriva el agujero desde 1 1/8. La geometría
  circular permite comparar orden interior/exterior dentro de la misma pieza.
- Horquilla reutiliza la definición wheel_part_interfaces ya aplicada y sus
  condiciones. El enum cerrado thru_axle_thread queda legacy en esta plantilla;
  no se modifica la definición compartida. El positivo de paso 1,25 es sintético,
  no afirma que un eje trasero TRA225 sea de horquilla. La envolvente por BSD
  conserva los siete casos previos de suspensión/dirección.

41 pruebas Dart correctas. El primer ensayo SQL detectó dos expectativas de
código, no cambios de conducta: con row_coherence el duplicado se reporta como
row_shape; sin él conserva field_constraint. Se corrigen las dos expectativas
por evidencia del validador real, manteniendo exactamente el bloqueo. No se
modifica el motor. Ensayo completo del publicador en curso en
.tmp/db/suspension-headset-parts-publication-tests.log; debe pasar antes de aplicar.

Preimagen viva 00:53:24Z: 10 compartidas exactas, cero colisiones. Publicador
idéntico al de las nueve ruedas, parametrizado: 35 definiciones/45 opciones
nuevas, 4 plantillas/53 usos. Backup adicional restringido en
/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T0110Z-suspension-headset-metadata.
Sin llenado, asignaciones, cambios de motor ni escrituras de productos.
Disponibilidad del esquema no certifica compatibilidad completa.

| Artefacto | SHA-256 |
|---|---|
| scripts/inventory/compile_suspension_headset_parts_catalog.py | `0fc87078c6357625dc1661679ee3735153e5c5dfc6866aa6edc25f717e2b9192` |
| docs/development/product-specs-research-2026-09-05/suspension-headset-parts-catalog-2026-09-07.json | `148788b9a4be8f5d9ad6b9ba202439934b125063bb9d5e22b880d322859b8887` |
| docs/development/product-specs-research-2026-09-05/suspension-headset-parts-cases-2026-09-07.json | `e065788bfc26cf5bbaddb7d00f10e97e7c4283447bb15accf7cfe46b5457c98f` |
| docs/development/product-specs-research-2026-09-05/suspension-headset-parts-publication-preimage-2026-09-07.json | `f38dd94f2d538af6a0d2f9574e04d56f7a9d433d8703e6f1379c2599d116595a` |
| docs/development/product-specs-research-2026-09-05/suspension-headset-parts-publication-packet-2026-09-07.json | `2f26273067e038239431dbba1ef291bb1a3efe11acf3ce98336b61f27a406ba1` |
| supabase/migrations/20260908011000_suspension_headset_part_spec_templates.sql | `9750503489c6ce08bb3f2a27191159e3e5147b0b095565c1302749b7d4fe3e7d` |
| supabase/manual_checks/verification/20260908011000_suspension_headset_part_spec_templates.sql | `d89c010de62fcec1e928a72329dccb56f3e2f6ac19f5e67e9703f24e657fa7a8` |

## Corrección final SH-1: inserto OEM confirmado antes de publicar

El manual primario [Cervélo Fork Owner’s Manual v3](https://cervelo.cdn.prismic.io/cervelo/ffe12d7a-81fc-499c-981e-65904298ad93_fork_owners_manualv3.pdf), página impresa 3 (página PDF 2), recomienda el inserto de aleación suministrado con araña preinstalada. Es el contraejemplo real al criterio basado sólo en material de la espiga; no una excepción hipotética. No se publicó el candidato anterior.

El anclaje de la araña ahora declara superficie: carbono directo, metal de espiga, inserto de aleación OEM u otro. El cruce bloqueado es araña sobre carbono directo. Un inserto OEM exige su identidad, objetivo, condiciones y fuente; la fixture conserva ese contexto y no autoriza cualquier manguito. Superficie desconocida queda pendiente, sin inventar incompatibilidad. 43 Dart, 39 casos; ensayo SQL/publicador se repite sobre este delta.

Corrección al dictamen Claude: una tabla obligatoria ausente también produce `required_missing` **no bloqueante**, igual que la fila parcial produce `row_incomplete`; conserva el borrador. Ninguna de esas ausencias autoriza certificar o llenar por inferencia.

Hashes finales que sustituyen los de arriba:

- scripts/inventory/compile_suspension_headset_parts_catalog.py: `5d32197b1e31dc4ce3e39d4b8a4c8ea2eb2f4aae452f4d94fc0bf9e88d80561e`
- docs/development/product-specs-research-2026-09-05/suspension-headset-parts-catalog-2026-09-07.json: `ae236f569f5dee24a23f5bce6adbd546de56f3ef29bcc2d25cd20271d9c1d4b0`
- docs/development/product-specs-research-2026-09-05/suspension-headset-parts-cases-2026-09-07.json: `7402081a03eaef225123e75cdd23a560ac81fceef41681b8ca086c0ccd3993d7`
- docs/development/product-specs-research-2026-09-05/suspension-headset-parts-publication-packet-2026-09-07.json: `99779c9b6f8bd80739b1f70cce2e836958daf49d1ce7ede31720d7cb74025cbf`
- supabase/migrations/20260908011000_suspension_headset_part_spec_templates.sql: `cf951e4af802f3adab783da64f9d4aa82c1c53f6a07f6d4bfdda0b2d98f28568`
- supabase/manual_checks/verification/20260908011000_suspension_headset_part_spec_templates.sql: `f02c0c93da9f839c7b37e3542a540e86d27b971ea8d3d9ad9ebdc63de5c96f0f`
