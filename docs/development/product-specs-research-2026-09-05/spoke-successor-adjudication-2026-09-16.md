# Rayos: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916040000_spoke_successor.sql`
(sha256 `441a1ce150070135d1edc5cbd7c7c93a5a7c65d01c83a373e9e2a905da6ce6dc`), verificado a las
02:45:39Z con `supabase/manual_checks/verification/20260916040000_spoke_successor.sql`
(sha256 `5e65db22a085ce90ac1828ca92e062aad172c3a006e1dece01f84ae15571796b`). La plantilla original
`spoke` (`a0cb2acf…`) pasa de la versión 3 con 4 usos a la 24 con 20 usos, conservando su id y
sus observaciones; `spoke_gauge` y `spoke_bend_type` siguen presentes con rol `legacy`.
Ningún producto, hecho, referencia ni asignación cambió.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-spoke-catalog-2026-09-08.json` (candidato corregido por Root tras las revisiones) | `4a604b432a05f598dc3d1233880c111e4714fed986a6823b71a3292142f2353f` |
| `existing-spoke-cases-2026-09-08.json` (31 casos + 2 pendientes) | `c3e3668e8d9124d72cb35a8c96c262238e9857ae9c78e4bf6b59649e565e5c4d` |
| `existing-spoke-review-preimage-2026-09-08.json` (preimagen congelada) | `4d62f70e114ea85457a1f4d29e8120dbef86edd418374dffe7fb7ca25ddaab3c` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-spoke-preimage-20260916/preimage.json` (02:43:09Z) | `0628ab8bad3d99b26b5b6372f1951c6d54361a348ad373b6c5731c0f74b04079` |
| Delta de IDs `…/existing-spoke-preimage-20260916/product-ids.json` (58 productos) | `5266d492365eae089706521eab1840481454e771b2d4f3e5e46e498d5bc71f58` |
| Manifiesto de fichas `.tmp/product-spec-catalog/spoke-snapshots-20260916/manifest-20260916T024418081365.json` | `86456de8f6544aa85ed0c30c34e14d6d721adcdd8a545fb0435ac7f945824d03` |
| `spoke-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `51a077f231351660…` · `8b813b9a3706aa56…` · `b05b9dfeabc9bbe7…` |
| Auditoría de adopción `.tmp/product-spec-catalog/spoke-adoption-20260916.json` | `b262de98a322e6bd2188b71cd32d966fb15fb37fa0bc1ead8b930a1d5b3ca3a5` |

Compilador: `scripts/inventory/compile_spoke_successors.py <preimagen-fresca>`; aborta si la
preimagen viva difiere de la congelada o si cambia la frontera legacy. La preimagen fresca
resultó idéntica; los vínculos crecieron de 48 a 58: los diez nuevos (13725, 2000000148663,
NNV142–NNV149) son asignaciones explícitas de la ronda de saneamiento; ninguno salió.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 31 casos, rollback) | `representation_cases 31 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 32 pruebas, todas verdes |
| Adopción sobre 58 fichas frescas por RPC | 58 evaluadas · 0 bloqueantes · 58 pendientes de información · 19 observaciones legacy conservadas · 0 activas sin proyectar |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916040000.receipt` |
| Cliente publicado (f51f3777) | el catálogo usa `row_conditions` sin pares escalares ni orden estricto; decodificable |
| Lectura posterior | `spoke=24/20` · definiciones globales 727 → 742 (15 nuevas, 7 visibles y filtrables) · 58 vínculos · 58 revisiones iguales a la captura previa · 67 hechos antes y después con el mismo md5 |

## Adjudicaciones

1. **Revisión independiente**: la hizo Claude sobre el candidato de Root en tres rondas
   (revisión, revisión del delta y revisión final de D1, 2026-09-08) sin bloqueos abiertos;
   Root corrigió las siete observaciones. Esta ronda repitió adopción y ensayo con datos
   frescos. No hubo un tercer revisor.
2. **Siete medidas nuevas salen visibles y filtrables**: `spoke_head_interface`,
   `spoke_thread_nominal_mm`, `spoke_thread_major_diameter_mm`, `spoke_thread_length_mm`,
   `spoke_head_elbow_angle_deg`, `nipples_included`, `spoke_nipple_thread_present`. Las
   designaciones OEM de texto libre y las dos tablas por fila quedan fuera de los filtros.
3. **Lo que no se publica como aprobado**: el cruce rayo–maza–niple–llanta sigue exigiendo
   modelos y condiciones documentados; ningún largo o diámetro coincidente certifica una rueda.

Llenado técnico persistido: 0. Los dos casos pendientes esperan la integración de
referencias y editor.
