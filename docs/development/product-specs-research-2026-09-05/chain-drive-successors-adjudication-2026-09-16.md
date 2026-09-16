# Cadenas y conectores: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916080000_chain_drive_successors.sql`
(sha256 `e221e8403ff176c78bc6daf02530f59a8bddbd49d31bcbc1fbd0a1f3ad3be8e6`), verificado a las
06:07:55Z con `supabase/manual_checks/verification/20260916080000_chain_drive_successors.sql`
(sha256 `ddca63772b184e239e8b260bbe8a3ee3eaa35dcec2a95c8801cadd36953f70e6`). Las dos plantillas
originales conservan id y observaciones: `chain` (`a9d0494f…`) 6→25 con 18 usos y `chain_link`
(`9c93c819…`) 24→40 con 15 usos. Los selectores publicados de perfil, plataforma, ecosistema,
modo y destino del conector siguen presentes con rol `legacy`. `drivetrain_kit`, que viajaba
en el mismo catálogo revisado, ya se publicó por su cuenta el 2026-09-15 (`20260915023000`) y
no se toca. Ningún producto, hecho, referencia ni asignación cambió.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-chain-drive-catalog-2026-09-08.json` (candidato de Root tras la revisión F1–F4) | `ab1e52a97a73ea1530d48845b7b470871f35ec7898687bbbcda71e4d80dcd1f5` |
| `existing-chain-drive-cases-2026-09-08.json` (34 casos; 28 de cadena y conector) | `987ec6c10317ea76e1702cd660c18dcc347e4ed97a1faaafc7523801a09dd653` |
| `existing-chain-drive-final-preimage-2026-09-08.json` (preimagen congelada, tres familias) | `7a1fdb10197ec113d062d5dda761c60429cff1238d4db027d0985e91fb08cbab` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-chain-drive-preimage-20260916/preimage.json` (05:59:03Z, dos familias) | `3be25e7f602ac924decc97eb969a5037c60daf65843ebfa9185667b4b7709ab9` |
| Delta de IDs `…/existing-chain-drive-preimage-20260916/product-ids.json` (44 productos) | `58b027ebc277a31683020900709667eae46067220a964ca5b5f2a274d4deaec0` |
| Manifiesto de fichas `.tmp/product-spec-catalog/chain-drive-snapshots-20260916/manifest-20260916T060016611429.json` | `4b6e563e78c0bcad27ff67c1da051f2f77670aea7da1191782de0319de67d1d6` |
| `chain-drive-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `45de821a2b427cc9…` · `92e791d1954b0b77…` · `7b4bf96b694c3cb8…` |
| Auditoría de adopción `.tmp/product-spec-catalog/chain-drive-adoption-20260916.json` | `f2b23bdb0e1c6933bd7ef68d4ac4f00209ef12d7dfcf5916ab4abd4ba083577a` |

Compilador: `scripts/inventory/compile_chain_drive_successors.py <preimagen-fresca>`; compara la
preimagen viva con la congelada restringida a cadena y conector y aborta si una clave «nueva»
ya existe en producción. La preimagen fresca resultó idéntica; los vínculos pasaron de 31
cadenas y 9 conectores a 35 y 9 por tres asignaciones explícitas; ninguno salió.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 28 casos, rollback) | `representation_cases 28 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 30 pruebas, todas verdes |
| Adopción sobre 44 fichas frescas por RPC | 44 evaluadas · 0 bloqueantes · 44 pendientes · 1 observación legacy conservada · 0 activas sin proyectar |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916080000.receipt` |
| Cliente publicado (f51f3777) | decodifica `row_conditions` y `row_coherence`; sin pares escalares ni orden estricto |
| Lectura posterior | `chain=25/18 · chain_link=40/15` · definiciones globales 790 → 797 (7 nuevas, 2 visibles y filtrables: paso de cadena y límite de reutilización del conector) · 44 vínculos · 44 revisiones iguales · 42 hechos antes y después con el mismo md5 |

## Adjudicaciones

1. **El kit no viaja aquí.** El catálogo revisado traía `drivetrain_kit` con versión 3; el vivo
   ya está en su sucesor de miembros. Compilar sólo cadena y conector evita rebajar ese
   contrato y deja F2 (perfil tipado por miembro) donde ya se resolvió.
2. **Ancho y designación son declaraciones separadas**; ningún ancho se deduce de las
   velocidades. Un conector declara sus destinos documentados y su límite de reutilización;
   un paso coincidente no aprueba una cadena.
3. **Lo que sigue fuera**: la exclusión dirigida PowerLock → T-Type y las demás relaciones
   viven en referencias; los tres casos pendientes esperan esa integración.

Llenado técnico persistido: 0.
