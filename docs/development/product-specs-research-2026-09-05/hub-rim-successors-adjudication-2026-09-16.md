# Mazas y llantas: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916050000_hub_rim_successors.sql`
(sha256 `e390aeb7cca05c34fb35fb59c240d6e1f115265982425bb6fc29107da64ee266`), verificado a las
05:53:15Z con `supabase/manual_checks/verification/20260916050000_hub_rim_successors.sql`
(sha256 `63de11716575040b92b79734f30cbfdfaa13b5ffb2130853d2b76877cf52406d`). Las dos plantillas
originales conservan id y observaciones: `hub` (`5e92fbe9…`) 2→34 con 31 usos y `rim`
(`81547e3f…`) 5→35 con 29 usos. Siguen presentes con rol `legacy`: en `hub`
`wheel_position`, `hub_spacing_mm`, `axle_type`, `thru_axle_thread`, `spoke_holes`,
`rear_drive_interface`, `freehub_type`; en `rim` `wheel_size`, `spoke_holes`, `valve_hole`,
`valve_type`. Ningún producto, hecho, referencia ni asignación cambió.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-hub-rim-catalog-2026-09-08.json` (candidato de Root tras la revisión del delta) | `7585bdb1f1b5365e7474324b37e6d20a287d92cbce74319ed53af3ffb663b1a3` |
| `existing-hub-rim-cases-2026-09-08.json` (63 casos + 5 pendientes) | `bab19fbb361c1823c01c373704298013ba6ff3c56027bb44f01eb972552f774c` |
| `existing-hub-rim-final-preimage-2026-09-08.json` (preimagen congelada) | `247c106d4aab8d342931739dc4acb964ddbe6184fd18f0c9a4d8357e653f5b78` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-hub-rim-preimage-20260916/preimage.json` (02:45:45Z) | `3d78e287e3825d192e9cf6a06e92194a5882039fbacb4e2cf611e03de6318c34` |
| Delta de IDs `…/existing-hub-rim-preimage-20260916/product-ids.json` (96 productos) | `88d284f0f06c96defd9c16a2ebdee9176694902810fc3d36a4a596e9eec796f3` |
| Manifiesto de fichas `.tmp/product-spec-catalog/hub-rim-snapshots-20260916/manifest-20260916T024657444949.json` | `c098b5adaf07247f8a8d0d4b2c9a4ea71f07fa59cb927a509307c54c4260bbc4` |
| `hub-rim-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `307a147ae752b898…` · `8f7a22531a9d074f…` · `ae2a441272e4a244…` |
| Auditoría de adopción `.tmp/product-spec-catalog/hub-rim-adoption-20260916.json` | `a0d5ec2dd13cd11a337abebac9f5550bf6db6d779683e07f5563ff76556b03e3` |

Compilador: `scripts/inventory/compile_hub_rim_successors.py <preimagen-fresca>`; aborta si la
preimagen viva difiere de la congelada o si cambia la frontera legacy. La preimagen fresca
resultó idéntica; los vínculos pasaron de 48 mazas y 41 llantas a 52 y 44 por siete
asignaciones explícitas de la ronda de saneamiento; ninguno salió.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 63 casos, rollback) | `representation_cases 63 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 65 pruebas, todas verdes |
| Adopción sobre 96 fichas frescas por RPC | 96 evaluadas · 0 bloqueantes · 96 pendientes de información · 22 observaciones legacy conservadas (7 mazas, 15 llantas) · 0 activas sin proyectar |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916050000.receipt` |
| Cliente publicado (f51f3777) | decodifica `row_conditions` y `row_coherence` (`product_spec_coherence.dart` ya los leía en ese commit); sin pares escalares ni orden estricto |
| Lectura posterior | `hub=34/31 · rim=35/29` · definiciones globales 742 → 772 (30 nuevas, 20 visibles y filtrables) · 96 vínculos · 96 revisiones iguales a la captura previa · 29 hechos antes y después con el mismo md5 |

## Adjudicaciones

1. **Revisión independiente**: la adjudicación de Root y la revisión independiente del
   delta (2026-09-08) dejaron dos hallazgos no bloqueantes y ningún bloqueo. El límite que
   Root declaró —«no recibí captura de observaciones de producto; medirlo es requisito
   antes de publicar»— quedó cubierto con la adopción de esta ronda sobre 96 fichas.
2. **Veinte medidas nuevas visibles y filtrables**: las cotas de pestaña y círculo de
   agujeros, diámetro y montaje de eje, receptor de transmisión y su presencia, posición y
   piezas del envase, presencia de anclaje de rotor, anclaje de rayo, eje pasante incluido,
   altura de perfil, agujeros de rayo y válvula, acceso al lecho y conteo de agujeros. Las
   tablas por fila, los datos de referencia y el indicador de desgaste (texto literal del
   fabricante) quedan fuera de los filtros.
3. **Lo que no se publica como aprobado**: la relación maza–llanta–rayo–niple y cualquier
   rueda montada; una medida coincidente no certifica compatibilidad.

Llenado técnico persistido: 0. Los cinco casos pendientes esperan la integración de
referencias y editor.
