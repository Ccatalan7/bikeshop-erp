# Aplicador de investigación publicado: nada habilitado todavía — 2026-09-16

Publicado en producción como `supabase/migrations/20260916140000_product_spec_research_applier.sql`
(sha256 `bdef2895414ba32e9940a3bf63466a625a942a60d6456e0e123dbdafd48276e5`), verificado con
`supabase/manual_checks/verification/20260916140000_product_spec_research_applier.sql`
(sha256 `8c156e3f4eddf1fbc41ba4ab4af1961be935ae2a27d1dc44f141b3704f963b9d`), recibo
`.tmp/db/migration-receipts/20260916140000.receipt`. La migración es la compilación del candidato
revisado el 2026-09-07 (`scripts/inventory/sql/product_spec_application_candidate.sql`, sha256
`71db507e742e04c5450acdeb592fb4b236cf44fa07545f3071237223db6457b7`) por
`scripts/inventory/compile_research_applier_publication.py`.

**Lo que existe ahora en producción:** tres tablas con RLS y sin ninguna política ni privilegio
para `anon`, `authenticated`, `service_role` ni `codex_test_runner`
(`product_spec_research_readiness`, `product_spec_research_applications`,
`product_spec_research_receipts`); la restricción `spec_facts_source_known` admite la procedencia
`research`; y tres RPC `security definer` ejecutables sólo por `authenticated`:
`apply_product_spec_research_v1` (`dd356e99…`), `get_product_spec_research_receipt_v1`
(`eb079dec…`) y `get_product_spec_research_application_status_v1` (`c9f31a17…`).

**Lo que habilita:** nada. Cero filas de readiness, cero aplicaciones registradas, cero recibos y
cero hechos con procedencia `research`, comprobado por el verificador después del despliegue.
Ningún producto, hecho, referencia, plantilla ni asignación cambió. **Llenado técnico
persistido: 0.**

## Qué exige el aplicador antes de escribir un hecho

1. Una fila de readiness **habilitada** para el tenant, con los sha256 de la auditoría global y de
   la revisión independiente que cierran el saneamiento. Nace `enabled = false`; sólo se crea por
   una escritura privilegiada revisada, nunca desde el cliente ni desde el RPC.
2. Una aplicación registrada por producto (comando exacto, sha del comando, propuesta v2
   revisada con veredicto `accepted` de un revisor distinto del investigador, sha del paquete),
   vinculada a esa readiness. El registrador (`prepare_product_spec_registration.py`) emite el SQL
   para la ruta de escritura guardada de `scripts/db/query.sh`; no corre nada por sí mismo.
3. En el momento de aplicar, como el actor autenticado que registró: readiness todavía
   habilitada y aplicación no revocada; preimagen exacta (sha de la instantánea, huellas,
   revisión, `updated_at`, plantilla y versión de contrato; si cambió, `40001`); la vista previa
   canónica igual a los valores esperados; cada valor que cambia tiene su efecto revisado; sólo
   campos de la plantilla activa y nunca `legacy`; una observación confirmada exige un conflicto
   resuelto explícitamente; las opciones resuelven IDs únicos; las columnas del producto ajenas
   al efecto y las observaciones no incluidas quedan idénticas; recibo atómico con el antes y el
   después. Una respuesta perdida se recupera devolviendo el recibo sin repetir la escritura.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Revisión independiente del 2026-09-07 | los dos hallazgos ya estaban corregidos en el candidato antes de publicar: la llave del candado por producto se arma con el uuid canónico, y una observación confirmada no se pisa sin conflicto resuelto |
| pgTAP `supabase/tests/product_spec_research_application_candidate.sql` | 42 aserciones verdes sobre una base sin el aplicador (carga el candidato) y sobre la base local ya instalada (lo salta con `\if`); `rollback` en ambos casos. Se corre con `scripts/db/query.sh local --write --file`, porque `scripts/db/test.sh` no resuelve `\ir` fuera de `supabase/` |
| Pruebas unitarias Python (`test/scripts/test_product_spec_application.py`) | 32 verdes |
| Ida y vuelta local (`test_product_spec_application_roundtrip.py`) | `PASS` sobre base limpia y, con el aplicador ya instalado, otra vez `PASS` sembrando sólo el fixture: instantánea y vista previa SQL, revisión Python, registro exacto y su repetición, tres calendarios de contención entre dos sesiones, aplicación con rol autenticado, recibo completo, recuperación tras una edición posterior, rechazo de un recibo con el costo alterado y limpieza exacta |
| Ensayo local de la migración | rollback (identidades fijadas), luego camino de creación y camino de reejecución, verificador verde en local |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después |
| Primer intento de despliegue | la migración confirmó y el verificador falló en `exact_applier_tables`: producción concede por privilegio por defecto `SELECT` a `codex_test_runner` sobre toda tabla nueva de `public`, cosa que local no tiene. Sin sello, sin editar historia: la migración se rehizo reejecutable (creación condicional, `revoke` explícito a ese rol si existe) y el mismo comando de despliegue la completó, verificó y selló |

## Adjudicaciones

1. **Publicar la infraestructura antes de cerrar el saneamiento no adelanta el llenado.** El
   handoff exige actor autenticado real, plantilla y versión esperadas, revisión y `updated_at`
   esperados, clave idempotente por producto y lote, preservación de lo no tocado, rechazo por
   conflicto de revisión, identidad o asignación, y recibo con investigador, revisor, fuentes y
   hashes. El aplicador cumple cada punto y no puede escribir sin la readiness; tenerlo en
   producción permite ensayar el primer lote con el objeto real en vez de con un candidato.
2. **La fuente `research` existe pero no la escribe nadie.** Un efecto de origen `reference` se
   guarda como `catalog`; uno de origen `research`, como `research`, siempre `confirmed = false`.
   Una lectura de nombre o una medición del mecánico nunca se reetiqueta.
3. **Las tablas no se leen sin RPC.** Se revocó también a `codex_test_runner` para conservar la
   ACL revisada; el actor lee su recibo y su estado por los dos lectores definer. Un lector de
   auditoría para el dueño es una pieza pendiente y separada.
4. **Los fixtures habían envejecido.** El test sembraba una lectura sin `definition_id` ni
   `vocabulary_digest` y sobre un hecho `mechanic`; desde `20260831290000` una lectura exige ambos
   y sólo cuelga de un hecho `name_reading`. Se corrigió el fixture, no la regla.
5. **Bloqueo exclusivo acotado.** El cambio de restricción sobre `spec_facts` toma
   `ACCESS EXCLUSIVE` y revalida la tabla (2.502 filas): sub-segundo, con `lock_timeout` de 5 s.

## Qué falta antes del primer lote

- Cerrar el saneamiento con una readiness cuyos hashes apunten a una auditoría global y a una
  revisión independiente concretas; es una decisión, no un script.
- Revisión independiente del registrador, tan crítica como el RPC (el RPC confía en él para el
  esquema completo de la propuesta y la evidencia).
- Las compuertas 2 a 5 del handoff: definiciones con consumidores, matriz por familia,
  consumidores que resuelven la misma identidad y estado, y la marca por hallazgo.
- Identidad resuelta por producto antes que sus medidas; primer lote pequeño con fuentes fuertes.
