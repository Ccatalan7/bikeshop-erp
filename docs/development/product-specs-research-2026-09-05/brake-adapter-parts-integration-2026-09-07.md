# Frenos y adaptadores: cuatro plantillas aplicadas

Migración `20260908025000` APPLIED y verificada a las **2026-09-08T02:53:47Z**. Familias: brake_mount_adapter, rotor_mount_adapter, brake_small_part, hub_brake. 19 definiciones nuevas, 33 opciones y 28 usos; 6 compartidas preservadas. Con este bloque: **64 plantillas nuevas activas**, 4 nuevas pendientes, correcciones de las 37 iniciales y saneamiento transversal abiertos. Asignaciones nuevas y llenado: cero.

[Decisiones root](brake-adapter-parts-root-decisions-2026-09-07.md) y [revisión independiente de Claude](brake-adapter-parts-candidate-review-2026-09-07.md).

**Evidencia:** 46 pruebas Dart, 42 casos SQL sobre las plantillas reales y cinco regresiones locales del publicador con rollback. Verificador antes: división por cero esperada; después: metadata exacta y 42 casos verdes. Lectura API autenticada a las 2026-09-08T02:57:07.309201+00:00: {"spec_templates": 4, "spec_template_fields": 28, "spec_definitions": 25, "spec_definition_values": 87} y 4 consultas de referencias; escrituras del lector: cero. La comparación independiente de fingerprints sólo cambió hora y última migración. Productos, facts, asignaciones, defaults, ACL, políticas y motor preservados; la transacción además verificó referencias.

Backup restringido y byte a byte verificado: `/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T025312Z-brake-adapter-metadata`. El backup legacy completo `20260906T222802Z-pre-fill` permanece disponible. Recuperación: desactivar sólo plantillas sin ligaduras, conservando hechos posteriores; no es un ensayo de restauración total de PostgreSQL.

Recibo: `.tmp/db/migration-receipts/20260908025000.receipt`; API: `.tmp/product-spec-catalog/brake-adapter-parts-authenticated-readback.json`.

| Artefacto | SHA-256 |
|---|---|
| `brake-adapter-parts-catalog-2026-09-07.json` | `a5e3add682ae2ee881daaa158b55478d3762341de2f7fb35ddf05525a928897a` |
| `brake-adapter-parts-cases-2026-09-07.json` | `44afed36113d8e87c755fdf438be1b96119f6a5d25e3f7fbd523466fce608135` |
| `brake-adapter-parts-publication-preimage-2026-09-07.json` | `1732859b6960a51dee0ee5b7de7eec5c91aad57dc10f83515f63d491b7aefceb` |
| `brake-adapter-parts-publication-packet-2026-09-07.json` | `ff81bded7371a74c2e497402f557be8c2512f0da4ae84e6f751b93834ca34ac8` |
| `20260908025000_brake_adapter_part_spec_templates.sql` | `0a635869bbc6459c645c361e46ea3bb3bbcd00233d744cfa408665b6f38bcc6b` |
| `20260908025000_brake_adapter_part_spec_templates.sql` | `0c3eef4c2329e68d05b0ae2c0c7a7e1c90da21de5dcf6b05693b4f8c8fbb80c9` |
| `brake-adapter-parts-candidate-review-2026-09-07.md` | `47f0cd8756b1992c8d52b6a8f73faab28daf7de3315a1aa5dfeec751d0b3c1aa` |

Las pruebas no son certificación mecánica global. Faltantes requeridos siguen pendientes; contradicciones y enlaces colgantes bloquean. Sin nuevas asignaciones, llenado ni prueba visual de estas plantillas. El consumidor y el aplicador requieren identidad y fuente adjudicadas antes de usar claims.
