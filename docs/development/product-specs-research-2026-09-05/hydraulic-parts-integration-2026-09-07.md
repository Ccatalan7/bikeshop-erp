# Hidráulica: tres plantillas aplicadas

Migración `20260908024000` APPLIED y verificada a las **2026-09-08T02:49:51Z**. Familias: hydraulic_hose, hydraulic_fitting, brake_fluid. 16 definiciones nuevas, 7 opciones y 31 usos; 8 compartidas preservadas. Con este bloque: **60 plantillas nuevas activas**, 8 nuevas pendientes, correcciones de las 37 iniciales y saneamiento transversal abiertos. Asignaciones nuevas y llenado: cero.

[Decisiones root](hydraulic-parts-root-decisions-2026-09-07.md) y [revisión independiente de Claude](hydraulic-parts-final-adenda-2026-09-07.md).

**Evidencia:** 45 pruebas Dart, 42 casos SQL sobre las plantillas reales y cinco regresiones locales del publicador con rollback. Verificador antes: división por cero esperada; después: metadata exacta y 42 casos verdes. Lectura API autenticada a las 2026-09-08T02:52:07.047316+00:00: {"spec_templates": 3, "spec_template_fields": 31, "spec_definitions": 24, "spec_definition_values": 10} y 3 consultas de referencias; escrituras del lector: cero. La comparación independiente de fingerprints sólo cambió hora y última migración. Productos, facts, asignaciones, defaults, ACL, políticas y motor preservados; la transacción además verificó referencias.

Backup restringido y byte a byte verificado: `/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T023644Z-hydraulic-metadata`. El backup legacy completo `20260906T222802Z-pre-fill` permanece disponible. Recuperación: desactivar sólo plantillas sin ligaduras, conservando hechos posteriores; no es un ensayo de restauración total de PostgreSQL.

Recibo: `.tmp/db/migration-receipts/20260908024000.receipt`; API: `.tmp/product-spec-catalog/hydraulic-parts-authenticated-readback.json`.

| Artefacto | SHA-256 |
|---|---|
| `hydraulic-parts-catalog-2026-09-07.json` | `db035cb385f7d39a1f815c8331195c0939b251b846753fab7a6cb1b33e16a6d6` |
| `hydraulic-parts-cases-2026-09-07.json` | `1e49f0a889a59cbfc119c3e6654c1e7e6b8abbb32731bc2a469aff4892c4a9e1` |
| `hydraulic-parts-publication-preimage-2026-09-07.json` | `1670b9ef688a8c90879c1241e9390101ee632d3ab466b384a213ac8a8e080a3f` |
| `hydraulic-parts-publication-packet-2026-09-07.json` | `9c6303e982e8dc008696b50dfd8c8b0cd0c995ddb4b7b2eeba3a3284c1f10092` |
| `20260908024000_hydraulic_part_spec_templates.sql` | `6047e3f67fe812aad70bb1447b68b80db0bbe1909ec9cc77b8b4de553601e3f1` |
| `20260908024000_hydraulic_part_spec_templates.sql` | `08eea544afba0349997cf870284eba10af4e02c1663777227de9538f91bbb86e` |
| `hydraulic-parts-final-adenda-2026-09-07.md` | `62ebab35777c846840fc55006e8c42cade5e4b5ae67421404a08a3ba0fa71f32` |

Las pruebas no son certificación mecánica global. Faltantes requeridos siguen pendientes; contradicciones y enlaces colgantes bloquean. Sin nuevas asignaciones, llenado ni prueba visual de estas plantillas. El consumidor y el aplicador requieren identidad y fuente adjudicadas antes de usar claims.
