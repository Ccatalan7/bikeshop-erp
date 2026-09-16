# Bielas, platos y volantes: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916070000_crank_drive_successors.sql`
(sha256 `387bd273bb631fadb0152abcc9d5f6da46d5a5ca677f94057e00d168d0d6d86f`), verificado a las
06:15:34Z con `supabase/manual_checks/verification/20260916070000_crank_drive_successors.sql`
(sha256 `eda64fffbdf1c78d1dbbe9ecea1491dce84a678ffde547d9db4f9f7fb3ba6387`). Las tres plantillas
originales conservan id: `crankset` (`91a0c6d5…`) 4→34 con 29 usos, `crank_arm` (`1a4ff9ad…`)
3→20 con 16 usos, `chainring` (`11aa1aa7…`) 4→30 con 25 usos. Los selectores publicados de
plataforma, velocidades, dientes, círculo de pernos, desplazamiento, familia de pedalier y de
perfil, e interfaz de eje siguen presentes con rol `legacy`. Ningún producto, hecho, referencia
ni asignación cambió; los 57 productos del alcance no tienen ningún hecho registrado.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-crank-drive-adjudicated-catalog-2026-09-08.json` (candidato adjudicado por Root con cinco cierres) | `b477332c223b3d667a0a2542701fca8697802d5bee5c98f703e05588448b5458` |
| `existing-crank-drive-adjudicated-cases-2026-09-08.json` (69 casos + 8 pendientes) | `f5dbf16cd23ccab9283b8f42778b4a2ded82ed4752e60c091e94216a376f8da4` |
| `existing-crank-drive-final-preimage-2026-09-08.json` (preimagen congelada) | `e74791e3bd5809d37902b5b920b4c03d67c0df53e2b24275fee1b8728e325afe` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-crank-drive-preimage-20260916/preimage.json` (05:58:50Z) | `2c52f98f88e2cc22e238be3bc15ea88e2a04d2edf4d9463f3974a067373da9df` |
| Delta de IDs `…/existing-crank-drive-preimage-20260916/product-ids.json` (57 productos) | `13631a4650cb2578e3a78a1b55ebae2ef07df497e0478ed498e2eefacf9d527a` |
| Manifiesto de fichas `.tmp/product-spec-catalog/crank-drive-snapshots-20260916/manifest-20260916T060012207816.json` | `b15d2b25443367efe73b17236a8da31d87c1fc6512e948e55612d8677a66236a` |
| `crank-drive-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `2937cf7988e7642e…` · `f8adbcee6a2ff01c…` · `cfc0e2a9d29d068a…` |
| Auditoría de adopción `.tmp/product-spec-catalog/crank-drive-adoption-20260916.json` | `4093a4aac1ad746beafc63f5bfb7a78eeb33c5aee2750b300d9ed06c64b94b8f` |

Compilador: `scripts/inventory/compile_crank_drive_successors.py <preimagen-fresca>`. La preimagen
fresca resultó idéntica a la congelada; los vínculos pasaron de 28/7/16 a 32/8/17 por seis
asignaciones explícitas; ninguno salió. Ninguna de las 36 claves nuevas existía en producción.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 69 casos, rollback) | `representation_cases 69 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 72 pruebas, todas verdes |
| Adopción sobre 57 fichas frescas por RPC | 57 evaluadas · 0 bloqueantes · 57 pendientes · 0 observaciones (no había hechos) |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916070000.receipt` |
| Cliente publicado (f51f3777) | decodifica `row_conditions` y `row_coherence`; sin pares escalares ni orden estricto |
| Lectura posterior | `crankset=34/29 · crank_arm=20/16 · chainring=30/25` · definiciones globales 797 → 833 (36 nuevas, 16 visibles y filtrables) · `spindle_taper_standard` y `compatible_rear_speeds` presentes como selectores retirados · 57 vínculos · 57 revisiones iguales · 0 hechos |

## Adjudicaciones

1. **Dos selectores retirados se crean retirados, no se descartan.** `spindle_taper_standard`
   y `compatible_rear_speeds` nacen como definiciones nuevas con rol `legacy`, igual que
   `max_chainring_teeth` en mandos; pero aquí Root los retiró con ayuda escrita y diecinueve
   casos revisados los llevan como valor inerte, cuatro de ellos afirmando que «el selector
   retirado ya no responde». La retirada es evidencia adjudicada y se conserva tal cual.
   Quien los active en otra familia (pedalier, desviadores) debe adoptarlos como vivos.
2. **El eje de motor integrado no recibe un token inventado.** El dominio publicado de la
   interfaz de eje no lo contempla; la designación del fabricante vive en
   `crank_arm_spindle_designation`.
3. **Dieciséis medidas nuevas visibles y filtrables**: pedalier, eje, perno de fijación y
   cubrecadena incluidos; construcción y montaje; tipo y posición del envase de plato;
   cantidad de miembros y de platos; rosca del perno; dientes. Las tablas de declaraciones,
   pares OEM y desplazamientos quedan fuera de los filtros.
4. **Identidad**: los códigos de fabricante en los títulos (50 registros sin modelo ni MPN)
   se resuelven en el producto; los ocho casos pendientes esperan referencias y editor.

Llenado técnico persistido: 0.
