# Cables de mando: cuatro plantillas aplicadas

Migración `20260908022000` APPLIED y verificada a las **2026-09-08T02:08:51Z**.
Cables, fundas, piezas de cable/funda y rotor BMX. 21 definiciones nuevas, 37 opciones y 36 usos;
8 definiciones compartidas preservadas. Con este bloque son **57
plantillas nuevas activas**; quedan 11 nuevas, las correcciones de las
37 iniciales y el saneamiento transversal. Asignaciones nuevas y llenado: cero.

La implementación y sus límites están en [la adjudicación de root](control-cable-parts-root-decisions-2026-09-07.md).
Claude revisó los artefactos finales y probó las correcciones con sondas
independientes: [dictamen](control-cable-parts-candidate-review-2026-09-07.md).

**Evidencia:** 40 pruebas Dart, 36 casos SQL y cinco regresiones
locales con rollback del publicador. El verificador de producción falló antes
y pasó después. Lectura API autenticada a las 2026-09-08T02:15:37.642404+00:00:
4 plantillas, 36 campos,
29 definiciones y 72 opciones
(incluidas las compartidas), más cuatro consultas de referencias. Escrituras
por el lector: cero. La comparación independiente de huellas sólo cambió hora
y última migración; productos, facts, asignaciones, defaults, políticas, ACL
y motor siguen iguales. La transacción además verificó las referencias.

| Artefacto | SHA-256 |
|---|---|
| Catálogo | `15a2f1d0aa97e6413cf79419f45a711e1c2cb4234dcd38ab87893bf6c83ba412` |
| Casos | `7f2aebcfd66e5c54d8abd39fd997b913f75e8f215f5a79b9409e08c9c9ccedce` |
| Preimagen | `0ef47fd09b3b61e01f7a873c706a7fc481365b375a5f5b9584bbd3cc4a274cf4` |
| Paquete | `ba73dfab4fc8e9df1617505b6ee0dbbd7af0ef31af82be65aee1fbff485de56d` |
| Migración | `4ea0e59f028b0fda341699fdeb881c7eba27850ce1ed959a0dbd6e8b60897d7b` |
| Verificador | `a06742a3e55afe7735646701b871c8edf7d408f2208d9389aaae81f1667132b3` |
| Revisión Claude | `a095203e8015ff37d8394f382f0dd77e6c478811932694eb4597f7c29361bee7` |

Recibo `.tmp/db/migration-receipts/20260908022000.receipt`; lectura API en
`.tmp/product-spec-catalog/control-cable-parts-authenticated-readback.json`.
Backup byte a byte comprobado y restringido:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T014349Z-control-cable-metadata`.
El backup legacy completo `20260906T222802Z-pre-fill` sigue disponible.
Recuperación: desactivar sólo plantillas sin ligaduras, preservando hechos
posteriores. No es un ensayo de restauración total de PostgreSQL.

Una ausencia requerida continúa pendiente, no bloquea guardar. Un valor
contradictorio o un enlace colgante sí bloquea. Las pruebas no son certificación
mecánica global ni demuestran el renderizado de las nuevas fichas. No hay nuevos
frames de UI ni productos asignados a estas plantillas. La corrección local del
consumidor de criterios de compras espera próxima distribución; no se atribuye
a los binarios macOS177/Android65 ya publicados.
