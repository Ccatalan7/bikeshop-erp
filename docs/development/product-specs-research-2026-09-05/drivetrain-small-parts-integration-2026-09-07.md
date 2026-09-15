# Transmisión pequeña: cuatro plantillas aplicadas

Migración `20260908013000` APPLIED y verificada a las **2026-09-08T02:05:27Z**.
Extensor de patilla, anillo de cierre, protector de plato y tornillería. 28 definiciones nuevas, 52 opciones y 41 usos;
8 definiciones compartidas preservadas. Con este bloque son **53
plantillas nuevas activas**; quedan 15 nuevas, las correcciones de las
37 iniciales y el saneamiento transversal. Asignaciones nuevas y llenado: cero.

La implementación y sus límites están en [la adjudicación de root](drivetrain-small-parts-root-decisions-2026-09-07.md).
Claude revisó los artefactos finales y probó las correcciones con sondas
independientes: [dictamen](drivetrain-small-parts-candidate-review-2026-09-07.md).

**Evidencia:** 50 pruebas Dart, 46 casos SQL y cinco regresiones
locales con rollback del publicador. El verificador de producción falló antes
y pasó después. Lectura API autenticada a las 2026-09-08T02:06:51.377613+00:00:
4 plantillas, 41 campos,
36 definiciones y 110 opciones
(incluidas las compartidas), más cuatro consultas de referencias. Escrituras
por el lector: cero. La comparación independiente de huellas sólo cambió hora
y última migración; productos, facts, asignaciones, defaults, políticas, ACL
y motor siguen iguales. La transacción además verificó las referencias.

| Artefacto | SHA-256 |
|---|---|
| Catálogo | `e847f24f1a6cac14a34d90f2cf54a713df621dced5bb2f9a9eda7cc07a10b25d` |
| Casos | `3b9a86eb94fdb6fd5818162936998e9896928d2e25ff94a4217db7c0fac28f12` |
| Preimagen | `0b94c71cd171fbbbaac8936ad1b0319c9e9163142e80217a70ebc3c8d2a556d0` |
| Paquete | `5f5fc45f590b7df15d962d8b499af86b3f3a21b3fc9a218ac939ada72387740c` |
| Migración | `56f02a5b82208478fcc086ed550dc8562e1afd76f6b92aede315c4e21c4c7eea` |
| Verificador | `2a3b84547900b861873d7b76af32e094e87dc31046bf0cf5717d53e77d8b1cbb` |
| Revisión Claude | `3c43764a60f7b5a4c3409ff093406c5ed5ed70a7e9e889c6a5efc4b4c461c7b1` |

Recibo `.tmp/db/migration-receipts/20260908013000.receipt`; lectura API en
`.tmp/product-spec-catalog/drivetrain-small-parts-authenticated-readback.json`.
Backup byte a byte comprobado y restringido:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T014349Z-drivetrain-reviewed-metadata`.
El backup legacy completo `20260906T222802Z-pre-fill` sigue disponible.
Recuperación: desactivar sólo plantillas sin ligaduras, preservando hechos
posteriores. No es un ensayo de restauración total de PostgreSQL.

Una ausencia requerida continúa pendiente, no bloquea guardar. Un valor
contradictorio o un enlace colgante sí bloquea. Las pruebas no son certificación
mecánica global ni demuestran el renderizado de las nuevas fichas. No hay nuevos
frames de UI ni productos asignados a estas plantillas. La corrección local del
consumidor de criterios de compras espera próxima distribución; no se atribuye
a los binarios macOS177/Android65 ya publicados.
