# Patillas, roldanas y guías: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916090000_drivetrain_service_parts_successors.sql`
(sha256 `9da2322f8d41984e2ed1d045acf69039b7438a12077c2d6cef7efe0599da9c9e`), verificado a las 06:57:57Z con
`supabase/manual_checks/verification/20260916090000_drivetrain_service_parts_successors.sql`
(sha256 `06f00ca5821004e8666fb9cf60378c4ae59eb8f9783e6febb50ea150a3451882`). Las tres plantillas originales conservan id: `derailleur_hanger` (`a505c7c6…`) 2→12 con 9 usos, `derailleur_pulley` (`e009fd36…`) 3→20 con 16 usos, `chain_guide` (`0aaec6de…`) 3→16 con 12 usos. Siguen como `legacy` la pista de cuadro, la interfaz de patilla y el tipo de montaje del desviador en la patilla, y el tipo de montaje y los dientes en la guía. Ningún producto, hecho, referencia ni asignación cambió; los 38 productos no tenían hechos.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-drivetrain-service-parts-catalog-2026-09-08.json` | `1c10d400a1bea3f26c33c67c5a81dece3cdae9c7a4f954eea74be695b0c2216f` |
| `existing-drivetrain-service-parts-cases-2026-09-08.json` | `5084eeb7d917e294ed21caaea4c7b266a7989cc6b963410f184c543a871fbb9b` |
| `existing-drivetrain-service-parts-final-preimage-2026-09-08.json` (preimagen congelada) | `09a0e6b26958535000cda8e234992b904c4371387dc47e0b702dbd8ba076e1c9` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-service-parts-preimage-20260916/preimage.json` | `22248354c235a71ad79cb16424bc95a67fc34c5015dafd0b24bf9535c8c2bfdc` |
| Delta de IDs `…/existing-service-parts-preimage-20260916/product-ids.json` | `2d5a65e4c728c1086a7e392211f1e5fa263070dffff857eb00b764cae5e86fa1` |
| Manifiesto de fichas `.tmp/product-spec-catalog/service-parts-snapshots-20260916/manifest-20260916T065240380322.json` | `fdc6c294350aadefc7ed4d74a201fd34adfa5b5474f798ca86002fa5cdc8987d` |
| `service-parts-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `a5a8832255288f39…` · `fc848f37c9ceb70b…` · `a64352f2cdf4b5ba…` |
| Auditoría de adopción `.tmp/product-spec-catalog/service-parts-adoption-20260916.json` | `a81753eade79303612921b6538d3e535b84b6d72d3c035ddf575248fe9238ed6` |

Compilador: `scripts/inventory/compile_service_parts_successors.py <preimagen-fresca>`.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 49 casos, rollback) | `representation_cases 49 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 52 pruebas, todas verdes |
| Adopción sobre 38 fichas frescas por RPC | 38 evaluadas · 0 bloqueantes · 38 pendientes · 0 observaciones |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916090000.receipt` |
| Cliente publicado (f51f3777) | decodifica `row_conditions`, `row_coherence` y el par de dos elementos de la guía |
| Lectura posterior | `derailleur_hanger=12/9 · derailleur_pulley=20/16 · chain_guide=16/12` · definiciones globales 833 → 858 (25 nuevas, 15 visibles y filtrables) · 38 vínculos · 38 revisiones iguales · 0 hechos |

## Adjudicaciones

1. **Adopción medida antes de publicar**, como pedía el límite declarado por Root: 38 productos, cero bloqueantes; la preimagen fresca fue idéntica a la final del 8 de septiembre y los vínculos pasaron de 23/7/3 a 28/7/3 por cinco asignaciones explícitas.
2. **Quince medidas visibles y filtrables**: interfaces de cuadro y desviador de la patilla; construcción, material, diámetros, ancho, posición, velocidades, tipo de envase, perfil y cantidad de la roldana; ajuste de línea de cadena y dientes mínimo/máximo de la guía. Las tablas de piezas, montajes, exclusiones y pesos quedan fuera.
3. **Fuera de esta publicación**: los tres títulos que se leen como extensores van por la cola de asignación a `derailleur_hanger_extender`; el desviador de montaje directo no es variante de patilla; orientación, par y perfil de roldana esperan el manual exacto (seis casos pendientes).

Llenado técnico persistido: 0.
