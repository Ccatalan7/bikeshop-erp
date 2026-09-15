# Cuatro plantillas de suspensión y dirección aplicadas

Migración `20260908011000` APPLIED y verificada a las **2026-09-08T01:24:32Z**
(7 de septiembre en Los Ángeles). Horquilla, amortiguador, espaciador y piezas
de dirección: 35 definiciones nuevas, 45 opciones, 4 plantillas y 53 usos.
Se conservan exactamente diez definiciones compartidas. Son **49 plantillas
nuevas activadas en cinco bloques**; quedan 19 nuevas, las correcciones de
las 37 iniciales y el saneamiento transversal. Nuevas asignaciones y llenado: cero.

El amortiguador conserva longitud, referencia de medición, recorrido y unidades
en una misma configuración; cada extremo enlaza su ID estable. La horquilla
reutiliza interfaces con unidades independientes para diámetro y paso. Cada
espaciador conserva su geometría y cantidad, sin equiparar el nominal objetivo
con un diámetro interior medido. Dirección separa rangos, inserción y par por
elemento, y el material de espiga del contacto de la araña.

La excepción de Cervélo v3 (inserto OEM de aleación con araña preinstalada) se
verificó en el manual antes de publicar. La regla restringe el contacto directo
con carbono; no declara incompatible cualquier araña en cualquier horquilla de
carbono. El inserto requiere modelo, objetivo, condiciones y fuente. El detalle
y fuentes están en [la adjudicación](suspension-headset-parts-root-decisions-2026-09-07.md).
Claude comprobó esa corrección con tres sondas sobre el catálogo final y dejó
su adenda en [la revisión](suspension-headset-parts-candidate-review-2026-09-07.md).

**Evidencia:** 43 pruebas Dart; 39 casos SQL y cinco regresiones del publicador
en rollback; el verificador falló antes y pasó después en producción. La lectura
autenticada a las 01:25:18Z confirmó 4 plantillas, 53 campos, 45 definiciones y
83 opciones, incluidas las compartidas, más las cuatro consultas de referencias.
Productos, facts, categorías, ACL, políticas y motor permanecen iguales en la
comparación independiente. Referencias preservadas en la transacción.

| Artefacto | SHA-256 |
|---|---|
| Catálogo | `ae236f569f5dee24a23f5bce6adbd546de56f3ef29bcc2d25cd20271d9c1d4b0` |
| Casos | `7402081a03eaef225123e75cdd23a560ac81fceef41681b8ca086c0ccd3993d7` |
| Preimagen | `f38dd94f2d538af6a0d2f9574e04d56f7a9d433d8703e6f1379c2599d116595a` |
| Paquete | `99779c9b6f8bd80739b1f70cce2e836958daf49d1ce7ede31720d7cb74025cbf` |
| Migración | `cf951e4af802f3adab783da64f9d4aa82c1c53f6a07f6d4bfdda0b2d98f28568` |
| Verificador | `f02c0c93da9f839c7b37e3542a540e86d27b971ea8d3d9ad9ebdc63de5c96f0f` |
| Revisión Claude y adenda | `d2b36ae39d3fc33747c79d3139903be64cdf4c2f29b70afee24bd3f74ad622fc` |

Recibo `.tmp/db/migration-receipts/20260908011000.receipt` y lectura en
`.tmp/product-spec-catalog/suspension-headset-parts-authenticated-readback.json`.
Backup adicional restringido y verificado:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260908T0110Z-suspension-headset-metadata`.
El backup legacy completo `20260906T222802Z-pre-fill` sigue disponible. Recuperar
desactivando sólo plantillas sin ligaduras; no sobrescribir hechos posteriores.
Bloqueo máximo de espera 5 s y sentencia 120 s; cuatro tablas de metadatos.

Las ausencias siguen siendo incompletitud no bloqueante, incluso la tabla
obligatoria: se corrige aquí una frase del dictamen inicial que decía lo
contrario. Un ID colgante sí bloquea. No es evidencia de UI renderizada ni
certificación mecánica global; no habilita llenado. El consumidor local de
compras requiere próxima distribución.
