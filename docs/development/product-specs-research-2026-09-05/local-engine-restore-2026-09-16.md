# Restaurar el motor de fichas en la base local — 2026-09-16

La base local se reconstruye con `just db-gate` / `scripts/db/ensure_local.sh --reset`
desde el esquema de referencia, que es una foto histórica: nace con **91
definiciones globales y 21 plantillas** frente a 707 y 107 en producción, y sin
ninguna función del motor de fichas. Los querys siempre se han corrido como
standalone, así que el motor se recupera **replayando las migraciones** una por
una, no editando el esquema de referencia.

## Procedimiento que funcionó

1. Replay en orden de nombre con `VINABIKE_DB_WRITE_CONFIRM=local scripts/db/query.sh local --write --file`,
   **saltando** los documentos de publicación (archivos que contienen
   `nd_publication_document`, `existing_global_metadata_forward_only` o
   `assignment_document`): siembran plantillas y definiciones que local no tiene
   y no hacen falta para ensayar, porque `test_existing_spec_candidate.prepare()`
   siembra copias de fixture con UUID remapeados.
2. Las migraciones ajenas al motor que fallan (`20260824100000` por sintaxis,
   `20260824450000/460000/470000` por `purchase_status` inexistente,
   `20260916000200` de índices) se saltan en blando; no afectan al motor.
3. `20260906150000_product_spec_numeric_domains.sql` **se detiene** con «Numeric
   specification baseline drifted»: exige 35 definiciones numéricas con sus
   reglas antiguas y local trae 28. La cura ya existía y está documentada en su
   propio encabezado: `supabase/tests/fixtures/product_spec_numeric_legacy_seed.sql`
   siembra las 12 que faltan («Local-only missing historical catalogue rows»).
   Aplicarla y reanudar desde esa misma migración.
4. Las guardias de deriva posteriores (`Structured rows preimage drift`,
   `Exact editor dependency drift`) pasan solas si el replay fue completo.

Verificación: comparar en local y producción los md5 de
`spec_validate_draft_internal_v1`, `assign_product_spec_template_v1`,
`get_product_spec_research_snapshot_v2` y las siete `spec_coherence_*`, y que
exista el trigger `spec_coherence_publication_guard`. Los once coincidieron.
`scripts/inventory/test_product_spec_assignment_rehearsal.py` pasa 4/4.

## Trampas que costaron tiempo

- El primer pase se detuvo en `20260824100000` y hubo que reanudar con fallo
  blando para lo no relacionado con fichas: dos pases y cerca de una hora y
  media. Un runner con esa clasificación desde el inicio lo habría hecho en uno.
- Las 33 definiciones y 16 plantillas globales pre-motor que siguen faltando
  (frenos, rotor, llanta, rayo, tubeless) **no se necesitan** para ensayos con
  rollback; sólo el baseline numérico se comprueba por conteo.
- Con otra sesión compartiendo la base local, avisar antes de escribir y esperar
  su aviso: la otra sesión aplicó su migración entre mis dos pases sin conflicto.
- La captura de fichas por RPC con `set local role authenticated` no puede leer
  `product_spec_bindings_internal_v1` («permission denied for view»): resolver
  los IDs con el rol por defecto y pasarlos en línea al SQL que cambia de rol.
