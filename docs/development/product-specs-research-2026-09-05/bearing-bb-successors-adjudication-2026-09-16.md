# Rodamiento, pedalier, eje y cubeta: reemplazo publicado — 2026-09-16

Publicado en producción como `supabase/migrations/20260916100000_bearing_bb_successors.sql`
(sha256 `3c39939f5e35a2ae88d1f60e47fff00a9fdf1cbe3f6b4247200806674fd38d77`), verificado a las 06:58:29Z con
`supabase/manual_checks/verification/20260916100000_bearing_bb_successors.sql`
(sha256 `f83e0e141211456c307a7ff9e7406be992b2abe630ef92eb559e1bb7ea181a17`). Las cinco plantillas originales conservan id y observaciones: `bearing` (`d293dc44…`) 2→22 con 19 usos, `bottom_bracket` (`a4f78fa2…`) 9→31 con 21, `bottom_bracket_axle` (`047523e5…`) 4→13 con 8, `bottom_bracket_bearing` (`98f78948…`) 7→19 con 11, `bottom_bracket_cup` (`50c9c0f2…`) 4→19 con 14. Las lecturas publicadas de caja, cubeta, construcción, bolas, código de cartucho, separadores y eje admitido siguen con rol `legacy`. Ningún producto, hecho, referencia ni asignación cambió; los 198 hechos de los 72 productos conservan su md5.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-bearing-bb-catalog-2026-09-07.json` | `62bd5a7e860000bbc3e36ce2b2a10e9640052b8e501ffca8b6690640a29bc2b6` |
| `existing-bearing-bb-cases-2026-09-07.json` | `5f61afff3507aaca14679858a7904fe9a97c2eed16267d997d108c826b65c4ff` |
| `existing-bearing-bb-publication-preimage-2026-09-07.json` (preimagen congelada) | `385f6924ded3e54254bd4f974792c444f651d0b92e89527648b77a5b2b3868f8` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-bearing-bb-preimage-20260916/preimage.json` | `cdf62f8088cc6fa080edf8c2c6029e2acb1dbdb1cb280a9648daddc077b68b6c` |
| Delta de IDs `…/existing-bearing-bb-preimage-20260916/product-ids.json` | `b71eadcd4235e8bec39cc85ba988f21371c08de59be3c9074f5b65deb8851e42` |
| Manifiesto de fichas `.tmp/product-spec-catalog/bearing-bb-snapshots-20260916/manifest-20260916T065244969717.json` | `3d556bbf43e29f250af4b208c1ae296348b5610c2d5a1e89fbc942472b0f229a` |
| `bearing-bb-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `d71cffcc87168d50…` · `61595815e373f5fc…` · `6c81c7a02fe14515…` |
| Auditoría de adopción `.tmp/product-spec-catalog/bearing-bb-adoption-20260916.json` | `57e1b7b0ece647304697ca1864c2950944a22d608b46f285f45011a4d499dab7` |

Compilador: `scripts/inventory/compile_bearing_bb_successors.py <preimagen-fresca>`.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 76 casos, rollback) | `representation_cases 76 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 81 pruebas, todas verdes |
| Adopción sobre 72 fichas frescas por RPC | 72 evaluadas · 0 bloqueantes · 67 pendientes (cinco pedalieres ya sin pendencia) · 132 observaciones legacy conservadas (99 pedalier, 27 cubeta, 3 eje, 3 rodamiento de motor) · 0 activas sin proyectar |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916100000.receipt` |
| Cliente publicado (f51f3777) | decodifica `row_conditions`; sin pares escalares ni orden estricto |
| Lectura posterior | `bearing=22/19 · bottom_bracket=31/21 · bottom_bracket_axle=13/8 · bottom_bracket_bearing=19/11 · bottom_bracket_cup=19/14` · definiciones globales 858 → 881 (23 nuevas, 16 visibles y filtrables) · 72 vínculos · 72 revisiones iguales · 198 hechos antes y después |

## Adjudicaciones

1. **Una definición compartida se adopta en vez de crearse.** `crank_bolt_thread` nació con el reemplazo de bielas de esta misma jornada (`20260916070000`) con el mismo id determinista, rótulo, tipo y opciones que este catálogo proponía; el compilador la marca existente y aborta si el vivo difiere. Es la regla «lo congelado no es lo vivo» aplicada en el mismo día.
2. **Un hecho, un dueño**: caja, cubeta, eje y rodamiento guardan cada dato con su pieza; la nota no bloqueante del dictamen final sobre `bb_accepted_spindles` se conserva como límite documentado.
3. **Dieciséis medidas visibles y filtrables**: bolas por envase, ángulos y bisel de asiento, retención, rodamiento incluido, ángulos de contacto, tipo de pista, reengrasable, hileras, sello, geometría de asiento, forma de suministro y ancho. Las tablas de ejes admitidos, sistemas, puertos y miembros quedan fuera.

Llenado técnico persistido: 0.
