# Piñonería trasera: reemplazo publicado con activación revisada sobre datos poblados — 2026-09-16

Publicado en producción como `supabase/migrations/20260916110000_rear_cog_successors.sql`
(sha256 `7c46c1a9e08511a9adac1927c4f47b15a9de2a574d6542c6fdd36a53f4d23767`), verificado a las
07:32:01Z con `supabase/manual_checks/verification/20260916110000_rear_cog_successors.sql`
(sha256 `2c47a87fc26dd3a74aedb33b4f623f7d1fc6ec950cf76f0cdd978ad168033c0b`). Las cuatro plantillas
originales conservan id y observaciones: `cassette` (`6a02a0c2…`) 4→18 con 13 usos, `freewheel`
(`c97799a4…`) 4→17 con 12, `fixed_cog` (`be18a720…`) 3→11 con 7, `cassette_spacer` (`564abb7f…`)
3→8 con 4. La secuencia de coronas antigua, las velocidades y el tipo de núcleo siguen con rol
`legacy`. Ningún producto, hecho, referencia ni asignación cambió; los 137 hechos de los 64
productos conservan su md5.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| `existing-rear-cogs-catalog-2026-09-07.json` (candidato tras las tres revisiones de Root) | `21b3b278bbee57c32d93b0a599196582db815be4117363121bf552d2329fd15b` |
| `existing-rear-cogs-cases-2026-09-07.json` (36 casos) | `436330e8d92d796e6880732b00cb8ed11b301085585d3d1eb8c44e3968bf786b` |
| `.tmp/db/existing-37-candidate-preimage.json` (preimagen congelada de las 37, 2026-09-08, restringida a estas cuatro) | `0a21d85a1539c330e661e0c5c1aa2fde0bbf29ddad67a452a018ed767d08b2a6` |
| Preimagen fresca `.tmp/product-spec-catalog/existing-rear-cogs-preimage-20260916/preimage.json` | `764969965198c2d4e8001f42975123ead2dd8ede503068e978e8b24e29ba02cb` |
| Delta de IDs `…/existing-rear-cogs-preimage-20260916/product-ids.json` (64 productos: 32 cassettes, 29 ruedas libres, 3 espaciadores, 0 piñones fijos) | `223f892daf7f360af0711b267a4ff9a9e1e4826003ee4b0b690fc0e73fa34de1` |
| Manifiesto de fichas `.tmp/product-spec-catalog/rear-cogs-snapshots-20260916/manifest-20260916T065248580908.json` | `b2f080594cc1ed280449d147dfc4e5406778fc98652324d5ed340dbd52afff10` |
| Diagnóstico de datos poblados `.tmp/product-spec-catalog/rear-cogs-readback-20260916/facts-probe.csv` | `1f0495337458e364bb7fbfe70446b3edf3deae400d1c25ce45e2d7d6819a3c1f` |
| `rear-cogs-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `76df9fb0bea32aa7…` · `1feaf4cad18799c6…` · `b7850947e1c6fd19…` |
| Auditoría de adopción `.tmp/product-spec-catalog/rear-cogs-adoption-20260916.json` | `de88d37edb9ae375eb7950fa4f06c195b9213a8586ce9d570f1da5cfc0ea7f71` |

Compilador: `scripts/inventory/compile_rear_cogs_successors.py <preimagen-fresca>`. Este candidato no
tenía preimagen propia: la referencia congelada es la de las 37 familias del 8 de septiembre
restringida a estas plantillas, y la preimagen fresca resultó idéntica en plantillas, campos y
definiciones compartidas. Ninguna de las 11 claves nuevas existía en producción.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto de la migración revisada, 36 casos, rollback) | `representation_cases 36 · deployed_behavior_matches 1`, `ROLLBACK` |
| Arnés Dart del formulario | 40 pruebas, todas verdes |
| Adopción sobre 64 fichas frescas por RPC | 64 evaluadas · 0 bloqueantes · 64 pendientes · 49 observaciones legacy conservadas (29 cassette, 20 rueda libre) |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916110000.receipt` |
| Guardia de coherencia | primer intento rechazado con `23514` «La coherencia de datos poblados requiere una migración revisada con diagnóstico previo» y revertido entero; segundo intento con la migración revisada aplicado; `spec_coherence_publication_guard` vuelve a estar habilitada (`tgenabled = O`) |
| Cliente publicado (f51f3777) | decodifica `row_conditions`, `row_coherence` y los dos pares de dos elementos |
| Lectura posterior | `cassette=18/13 · freewheel=17/12 · fixed_cog=11/7 · cassette_spacer=8/4` · definiciones globales 888 → 899 (11 nuevas, 8 visibles y filtrables) · 64 vínculos · 64 revisiones iguales · 137 hechos antes y después con el mismo md5 |

## Adjudicaciones

1. **Activación revisada sobre datos poblados.** El par ordenado `smallest_cog_teeth ≤
   largest_cog_teeth` y la cardinalidad `cog_sequence ← sprocket_count` cambian la coherencia
   de dos plantillas cuyos extremos ya tienen hechos: 44 mínimos y 44 máximos poblados. La
   guardia rechaza toda activación en sitio sobre hechos, por diseño, y no tiene marcador de
   revisión. El diagnóstico previo leyó los 44 pares en producción: cero contradicciones, cero
   valores no numéricos, cero hechos en las claves nuevas. La migración repite ese diagnóstico
   en su propia instantánea (aborta al primer par invertido o al primer hecho en una clave que
   debe nacer vacía), suspende la guardia sólo para sus actualizaciones de plantilla dentro de
   la misma transacción, la restaura y revalida la metadata de las cuatro plantillas antes de
   confirmar. No lee, escribe ni reetiqueta ningún hecho. Es la forma que el repositorio ya usa
   para reparaciones revisadas (`disable trigger` acotado), aplicada a una publicación.
2. **Los casos revisados sólo habían corrido en Dart.** Nueve fallaban en SQL por dos motivos
   mecánicos: un pendiente por compuerta sin resolver es `field_applicability` aunque el campo
   también tenga prerrequisito, y sin compuerta es `prerequisite_missing`; y los bloqueos se
   comparan como JSON ordenado por (código, campo). El compilador deriva los subconjuntos SQL
   con esa regla y ordena los bloqueos; el arnés Dart sigue en 40.
3. **Dueño de la variante**: la unidad y su variante publicada resuelta son hechos del producto;
   las variantes del modelo son referencias OEM, como adjudicó la tercera revisión de Root.
4. **Ocho medidas visibles y filtrables**: estría del cassette, rosca del piñón y de su
   contratuerca, rosca de la rueda libre, contratuerca incluida, extractor, tecnología de cambio
   y cantidad de coronas. La secuencia por fila, los cuerpos admitidos y la etiqueta de variante
   quedan fuera de los filtros.

Llenado técnico persistido: 0. `fixed_cog` no tiene productos vinculados hoy.
