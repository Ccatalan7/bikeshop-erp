# Dirección: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916120000_headset_successor.sql`
(sha256 `59bd15ea738d9689f21b6cd35a159979178f40950eac44db55ca8cb39d77a803`), verificado a las
07:03:25Z con `supabase/manual_checks/verification/20260916120000_headset_successor.sql`
(sha256 `e249a97fe3a6b24383069176146531166af727faff068f6a0a04a944e1b7b311`). La plantilla original
`headset` (`f55b7846…`) pasa de la versión 2 con 4 usos a la 16 con 13 usos; `bearing_system`,
`headset_standard` y `steerer_type` siguen con rol `legacy`. Ningún producto, hecho, referencia
ni asignación cambió; los 4 hechos de los 16 productos conservan su md5.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-headset-catalog-2026-09-08.json` (candidato de Root por extremo) | `02968a0066cc3c51f401de205bc6dab933923b8cfe3ea4e9d2c42561f166db57` |
| `existing-headset-cases-2026-09-08.json` (22 casos + 1 pendiente) | `1eda457a90cf3e17c17a8c52ba420db1d755a2da47d1acc6fde342d1ad33fa75` |
| `existing-headset-publication-preimage-2026-09-08.json` (preimagen congelada) | `4112b2b4b7bbc970617aafcd0c5cca54903d7f3f82cdb1a0897959358a469131` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-headset-preimage-20260916/preimage.json` | `a3a711551609c42ea6975b6f9b037a98545289766f8c8f924c71bf642a1c0454` |
| Delta de IDs `…/existing-headset-preimage-20260916/product-ids.json` (16 productos) | `78b950fdc3c6056a83ac58c61dfabb59a37036962937c0fd868d502590a8df6e` |
| Manifiesto de fichas `.tmp/product-spec-catalog/headset-snapshots-20260916/manifest-20260916T065624299607.json` | `7eb8039014f980963b06ac44c8f4c8c850a9f899356dc8139f2d498f92446b1f` |
| `headset-2026-09-16-catalog.json` · `-cases.json` (25 casos) · `-packet.json` | `ee1ae0daf37d1c92…` · `72b520c7d3a67bed…` · `1895a0205b34c5e9…` |
| Auditoría de adopción `.tmp/product-spec-catalog/headset-adoption-20260916.json` | `aa24e66becf1c2dc3e5ea116404be047a0bc962b0c5f3a3ad6a498ff93492efa` |

Compilador: `scripts/inventory/compile_headset_successors.py <preimagen-fresca>`. La preimagen fresca
resultó idéntica a la congelada; los vínculos pasaron de 15 a 16 por una asignación explícita.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 25 casos, rollback) | `representation_cases 25 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 26 pruebas, todas verdes |
| Adopción sobre 16 fichas frescas por RPC | 16 evaluadas · 0 bloqueantes · 16 pendientes · 4 observaciones legacy conservadas |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916120000.receipt` |
| Cliente publicado (f51f3777) | decodifica `row_conditions`; sin pares escalares ni construcción de orden estricto en el catálogo |
| Lectura posterior | `headset=16/13` · definiciones globales 881 → 888 (7 nuevas, 4 visibles y filtrables) · 16 vínculos · 16 revisiones iguales · 4 hechos antes y después |

## Adjudicaciones

1. **H-2 de la revisión independiente, adjudicado: la pista de corona es del extremo inferior.**
   `crown_race_included` pasa de `always` a admitirse y exigirse sólo con alcance `Inferior` o
   `Completa`, con la misma forma de compuerta que usan los demás campos por extremo.
   [Park](https://www.parktool.com/en-us/blog/repair-help/headset-standards) la ubica en el stack
   inferior y [Sheldon](https://www.sheldonbrown.com/headsets.html) la describe prensada en la base
   del tubo de horquilla. Tres casos nuevos: un juego superior que la declara bloquea
   (`field_applicability`), un juego superior no la debe, un juego completo puede incluirla con su
   referencia y su fuente. El caso revisado de «pista ausente prohíbe su referencia» recibe el
   alcance `Inferior` que su intención suponía. Un kit superior que además empaquete una pista de
   corona no tiene token de alcance hoy y queda sin declarar, no aprobado por omisión.
2. **H-1 estaba cubierto**: el interior mayor que el exterior y el espesor de pared no positivo
   bloquean como `row_shape`; la extensión de orden estricto por fila se desplegó el 2026-09-08
   (`20260908185800`, recibo verificado).
3. **Cuatro medidas visibles y filtrables**: pista de corona incluida, partes incluidas y alturas
   instaladas superior e inferior. Las tablas de rodamiento y los códigos SHIS de texto quedan
   fuera de los filtros.

Llenado técnico persistido: 0. El caso pendiente espera la integración de referencias OEM con las
interfaces SHIS.
