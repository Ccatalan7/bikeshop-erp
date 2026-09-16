# Mandos y desviadores: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916060000_shifting_successors.sql`
(sha256 `bcbe8f1742f733eac82ea57252ebe59abc9a7e4569b0213a525290eddc619765`), verificado a las
06:00:03Z con `supabase/manual_checks/verification/20260916060000_shifting_successors.sql`
(sha256 `d112ae43af6ad4aad4c2c15c23299df548efa2f89657f9b43cd2afc212577b5c`). Las tres plantillas
originales conservan id: `shifter` (`61005a7e…`) 2→21 con 18 usos, `rear_derailleur` (`0750e4ac…`)
5→24 con 18 usos, `front_derailleur` (`590232e5…`) 2→19 con 16 usos. Los selectores publicados de
plataforma, ecosistema, velocidades, familia de accionamiento, dientes mínimo/máximo/capacidad,
platos, abrazadera y tiro siguen presentes con rol `legacy`. Ningún producto, hecho, referencia
ni asignación cambió; los 94 productos del alcance no tienen ningún hecho registrado.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-shifting-adjudicated-catalog-2026-09-08.json` (candidato adjudicado por Root tras la revisión H1–H5) | `924a77009aff0db778c3e909c8e286edf9d80037c94f0739a0d800d89d145c39` |
| `existing-shifting-adjudicated-cases-2026-09-08.json` (48 casos + 7 pendientes) | `ca7feac7c5b72fb41b4fe495368e611aec1d40ad1a96ed05436186440bd3630a` |
| `existing-shifting-final-preimage-2026-09-08.json` (preimagen congelada) | `7cee2317b653acf176d48e4bbed3f3afdca54dafae6535de52262a415c40f655` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-shifting-preimage-20260916/preimage.json` (05:53:20Z) | `496e5a926c0ca318ec66d5bd88652acca7325a2e462f04809861c17eb275f3b9` |
| Delta de IDs `…/existing-shifting-preimage-20260916/product-ids.json` (94 productos) | `81bf6fb5dcd7530f516221b2bfe0e2359bdbb677f9377d94a77770cf7f92f00b` |
| Manifiesto de fichas `.tmp/product-spec-catalog/shifting-snapshots-20260916/manifest-20260916T055618042108.json` | `ea3c7d86f33aca92fed77d29b221cead7dc3626c9b4a0b33662eb8bc51843b16` |
| `shifting-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `a5bcdc1e5d7afa70…` · `e01c3830e48ed1d4…` · `d7896b9fa269cc2d…` |
| Auditoría de adopción `.tmp/product-spec-catalog/shifting-adoption-20260916.json` | `cf5cd06f72c27cdb1fe39aa70c93e87b6838062b97d35bd3796d3ee5442a029f` |

Compilador: `scripts/inventory/compile_shifting_successors.py <preimagen-fresca>`. La preimagen
fresca resultó idéntica a la congelada; los vínculos pasaron de 32/35/15 a 36/40/18 por once
asignaciones explícitas de la ronda de saneamiento; ninguno salió.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 48 casos, rollback) | `representation_cases 48 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 51 pruebas, todas verdes |
| Adopción sobre 94 fichas frescas por RPC | 94 evaluadas · 0 bloqueantes · 94 pendientes de información · 0 observaciones (no había hechos) · 0 activas sin proyectar |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916060000.receipt` |
| Cliente publicado (f51f3777) | decodifica `row_conditions` y `row_coherence`; sin pares escalares ni orden estricto |
| Lectura posterior | `shifter=21/18 · rear_derailleur=24/18 · front_derailleur=19/16` · definiciones globales 772 → 790 (18 nuevas, 8 visibles y filtrables) · `max_chainring_teeth` ausente · 94 vínculos · 94 revisiones iguales · 0 hechos antes y después |

## Adjudicaciones

1. **Un campo que nace muerto no se crea.** El catálogo adjudicado traía
   `max_chainring_teeth` como definición **nueva** y a la vez en la sección `legacy` del
   desviador delantero, resto de mover el máximo de dientes a las configuraciones
   documentadas. El rol `legacy` conserva lecturas publicadas; una clave sin ninguna
   observación no tiene nada que conservar, y ningún caso, ayuda ni fila la usaba. Se
   retiró de la plantilla y de las definiciones; las 48 representaciones siguen iguales.
2. **Ocho medidas nuevas visibles y filtrables**: modo de accionamiento, estilo de palanca
   y cantidad de mandos del envase; retorno del resorte y adaptador incluido del desviador
   trasero; anclaje del cable, dirección de tiro y construcción del delantero. Las tablas
   de configuraciones y declaraciones, y la relación de accionamiento en texto, quedan
   fuera de los filtros.
3. **Lo que sigue fuera de esta publicación**: los mandos combinados con freno pertenecen
   a `brake_shift_combined_control` a través de la cola de asignación; la identidad
   (modelo, MPN) se resuelve en el producto; los siete casos pendientes esperan la
   integración de referencias y editor.

Llenado técnico persistido: 0.
