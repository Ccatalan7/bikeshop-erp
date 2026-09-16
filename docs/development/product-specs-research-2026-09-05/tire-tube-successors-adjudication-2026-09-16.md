# Neumáticos y cámaras: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916030000_tire_tube_successors.sql`
(sha256 `93355d963197c72005204ba07d2decdc61a32a54430c8f1acff8a85227e812ca`), verificado a las
02:27:18Z con `supabase/manual_checks/verification/20260916030000_tire_tube_successors.sql`
(sha256 `8a844a0cc4c0a0f367039b840d41175c2169f0cf6966039712b83bdae3af4d3e`). Cinco plantillas
originales conservan su id y sus observaciones: `tire` 4→19, `tube` 6→21, `rim_strip`
2→12, `tubeless_consumable` 3→11, `tubeless_valve` 2→12. Ningún producto, hecho,
referencia ni asignación cambió. Claude es el único dueño desde el 2026-09-15; Root
había integrado el candidato el 2026-09-08 tras dos revisiones y lo dejó sin activar.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-tires-tubes-catalog-2026-09-08.json` (candidato integrado por Root) | `b9e30b145346d52489dc807400a56e7dd38788e74a0e0b269c48f2f35412e619` |
| `existing-tires-tubes-cases-2026-09-08.json` (50 casos + 8 pendientes) | `7cc47f5df2e152547b3bb0795b3fa6fcd11403bfe88e20bec72010018ea4c9b5` |
| `existing-tires-tubes-publication-preimage-2026-09-08.json` (preimagen congelada) | `48b5602be1decc4ff156bae62ffd1dec409407a0815e9dbf38b67f2dc81097d5` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-tires-tubes-preimage-20260916/preimage.json` (02:15:36Z) | `a54128f63015b0d7ac93e2ad429942df1d91066d4ed95259591504e182eccdb1` |
| Delta de IDs `…/existing-tires-tubes-preimage-20260916/product-ids.json` (271 productos) | `296150d4954bdf43b700a5e940686be59e07a42f6d6d2794a98459f79378e449` |
| Manifiesto de fichas `.tmp/product-spec-catalog/tire-tube-snapshots-20260916/manifest-20260916T022114009504.json` | `d2aa15d0c7a489d5890ff74b6d0524f9eb4a762e00ce67d2e4fef6010885402c` |
| `tire-tube-2026-09-16-catalog.json` (salida del compilador) | `ce9bb503e4647d045b049f9f90c53b6e908f91e2b4068ed56dc4fd464a3f318c` |
| `tire-tube-2026-09-16-cases.json` (53 casos + 8 pendientes) | `22127506e0477814633e0fe45af51d658eee47c0328bffa1535f768e98fea175` |
| `tire-tube-2026-09-16-packet.json` | `212106a956b4ccc25e94d3aca37319242e42dfa8cbe1d7d4e739adc5d9e9460c` |
| Auditoría de adopción `.tmp/product-spec-catalog/tire-tube-adoption-20260916-v2.json` | `b326ae357c99b329b6710b4bca158a3ed22228c81a063aeeec1b914fe79919bc` |
| Ensayo local `.tmp/db/tire-tube-2026-09-16-forward-candidate/forward-replay-and-cases.log` | `14d453a9b5ea211083886be2f3c12fcc730cbfe3ac952d7a6a0008acfa403637` |

Compilador: `scripts/inventory/compile_tire_tube_successors.py <preimagen-fresca>`. Aborta
si la preimagen viva difiere de la congelada en plantillas, campos o definiciones
compartidas, o si la compuerta de tubeless cambió. La preimagen fresca resultó
idéntica en esas tres secciones; sólo crecieron los vínculos: 264 → 271.

## Delta exacto de IDs

Siete productos entraron al alcance desde el 8 de septiembre, todos por asignación
explícita de la ronda de saneamiento del 2026-09-15/16; ninguno salió.

| Familia | SKU | Nombre |
|---|---|---|
| `rim_strip` | 19273 | 50 Cubre Camara 26" Goma |
| `tire` | 18504 | NEUMATICO KEVLAR BICICLETA ARO 27.5 X 2.25 SPECTRE RALCO |
| `tire` | NNV107 | Neumático Duro 26x1.5 |
| `tire` | NNV108 | Neumático Negostone 12x2.125 |
| `tire` | NNV109 | Neumático Vuelta USA 26 x 2.1 |
| `tire` | NNV163 | Rueda Sólida Scooter Xiaomi M365 8 1/2 x 2 |
| `tube` | 6927116185398 | Cámara Chaoyang 700x33/37c F/v 60mm |

Alcance publicado: 118 neumáticos, 138 cámaras, 4 fondos de llanta, 3 consumibles
tubeless, 8 válvulas tubeless.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 53 casos, rollback) | `representation_cases 53 · deployed_behavior_matches 1 · exact_metadata 1`, `ROLLBACK` |
| Arnés Dart del formulario (`product_spec_integrated_catalog_test.dart`) | 58 pruebas, todas verdes |
| Adopción sobre 271 fichas frescas capturadas por RPC (`product_spec_catalog_adoption_audit.dart`) | 271 evaluadas · 0 bloqueantes · 271 con información pendiente · 813 observaciones legacy conservadas · 0 activas sin proyectar · 0 escrituras |
| Verificador antes de publicar (producción, sólo lectura) | `ERROR: division by zero` |
| Despliegue `scripts/db/deploy_migration.sh --verify` | `APPLIED and verified`; recibo `.tmp/db/migration-receipts/20260916030000.receipt` |
| Cliente publicado (macOS 1.0.3-177 / Android 65, commit f51f3777) | decodifica `row_conditions` y pares escalares de dos elementos; el catálogo declara un par de dos elementos (`rim_strip`) y ningún orden estricto de tres |

Lectura posterior en producción (`.tmp/product-spec-catalog/tire-tube-readback-20260916/`):

| Lectura | Valor |
|---|---|
| Plantillas versión/usos | `rim_strip 12/9 · tire 19/14 · tube 21/14 · tubeless_consumable 11/7 · tubeless_valve 12/9` (53 usos) |
| Definiciones globales | 707 → 727; las 20 nuevas presentes, 14 marcadas visibles y filtrables |
| Vínculos efectivos | 271 |
| Revisión de ficha de los 271 productos | 271 iguales a la captura previa, 0 cambiadas |
| Hechos de los 271 productos | 1.138 antes (observaciones en las fichas capturadas) y 1.138 después; última actualización 2026-08-24 |
| Ficha por RPC tras publicar | NNV107 recibe `tire` contrato 19 con 14 campos; 6927116185398 recibe `tube` contrato 21 |

## Adjudicaciones de esta ronda

1. **Compuerta `tire_tubeless_ready` sobre el tipo de talón: se conserva.** Root la
   dejó sin verificar. «Tubeless Ready» es la propiedad clincher de talón y llanta
   compatibles. Un tubular ([TUFO](https://www.tufo.com/en/tubular/): carcasa
   estanca, reparación con sellante, montaje pegado) o un neumático sólido no
   pueden declararla aunque no lleven cámara separada; un talón «Desconocido /
   sin confirmar» la deja disponible pero pendiente. Tres casos nuevos la fijan
   en los dos motores: sólido bloquea (`field_applicability`), alambre no produce
   incidencia sobre el campo, desconocido queda pendiente en ambos campos.
2. **Un pendiente de aplicabilidad tiene dos nombres.** El editor Dart lo emite
   como `prerequisite` y SQL como `field_applicability`, ambos no bloqueantes y
   sobre el mismo campo. Los casos lo declaran por separado
   (`expected_issue_subset` / `expected_sql_issue_subset`); una expectativa
   única falla en uno de los dos motores.
3. **Catorce medidas nuevas salen como visibles y filtrables**: `tire_tpi`,
   `tire_weight_g`, `tire_use`, `valve_standard`, `valve_length_mm_value`,
   `valve_core_removable`, `valve_base_shape`, `strip_width_mm`, `strip_material`,
   `strip_fit_internal_width_min_mm`, `strip_fit_internal_width_max_mm`,
   `rim_hole_diameter_mm`, `consumable_kind`, `sealant_base`. Quedan fuera las
   tablas por fila, la membresía de kit y `tire_max_pressure_psi`, que nace con
   rol `legacy` porque la presión de portada no es un límite de configuración
   (L-1 de Root) y los consumidores excluyen `legacy`.
4. **No hubo revisión independiente de un tercero.** Root hizo dos revisiones e
   integró el candidato; Codex se detuvo el 2026-09-15. Esta ronda verificó la
   compuerta con datos reales, repitió adopción y ensayo con preimagen fresca y
   adjudicó lo que Root dejó abierto. Eso es lo que hay; no se presenta como más.

## Lo que sigue abierto

- Los ocho casos pendientes de relaciones (Zipp TSS, sistema desconocido, gancho
  solo) siguen esperando la integración de referencias y editor; no son parte de
  la publicación de metadata.
- Llenado técnico persistido: 0. Los 271 productos quedan con información
  pendiente; ningún valor legacy se convirtió ni se borró.
- Los consumidores (web, taller, matcher, criterios) excluyen `legacy`: las 813
  observaciones conservadas no se ven ahí hasta que exista un aplicador revisado.
- Normas de válvula fuera de Presta/Schrader/Dunlop: el contrato no decide.
