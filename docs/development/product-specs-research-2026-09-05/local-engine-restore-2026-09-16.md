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

## 2026-09-30: la base se reconstruyó otra vez y el motor volvió a faltar

La base local se reconstruye desde `supabase/sql/core_schema.sql`, que incluye
migraciones sólo hasta `20260816162400`; cada reconstrucción borra el motor.
Ese día faltaban `spec_facts`, los lectores y 120 funciones, pero **sí** estaban
las funciones de cambio de partes de `20260928100000`–`140000` que los llaman:
sus pgTAP reemplazan el lector dentro de la transacción y pasaban igual. Un
recorrido por la app con un repuesto habría fallado recién al terminar.

La lista exacta que funcionó, en orden, está en
`local-engine-replay-2026-09-30.txt` (89 archivos, un pase, ~9 min). Lo que la
decide:

- **Empieza antes de lo que dice este documento**: el bloque del pedalier
  (`20260820220000`–`20260821120000`) crea `option_rules`, que
  `20260906070000` escribe; y `20260821160000`/`170000` crean
  `spec_definition_values`, que exige `20260821180000`. En este pase el bloque
  del pedalier entró después de `20260821160000`: sus valores pueden no estar
  como filas; en una base nueva, seguir el orden del archivo.
- **Se dejan fuera a propósito** `20260817150000`, `20260817160000` y
  `20260821130000`–`150000`: tocan fichas, pero sólo redefinen funciones de
  compras y del buscador del asistente que migraciones posteriores ya
  reemplazaron; aplicarlas después las haría retroceder.
- **`20260916000100`** (higiene de RLS de todo el esquema) se detiene en una
  tabla de compras que local no tiene y reescribiría políticas más nuevas: se
  salta.
- **Desde `20260916150000`** son publicaciones de catálogo con guardias de
  preimagen: exigen los ids de plantilla de producción (el `tire` local es otro
  uuid) y el validador del día; se niegan por diseño y así se dejan. Lo que el
  recorrido necesita de ellas —el BSD del neumático— lo pone
  `supabase/tests/fixtures/part_change_tire_bsd_local_seed.sql`, con la fila de
  producción, validado por los disparadores del propio motor.

Verificación: `just db-drift local production` y el snapshot de cuerpos,
políticas y permisos antes y después. Los lectores que usan la app y el cierre
quedaron idénticos a producción; ninguna función o política que ya igualaba a
producción cambió; 9 más pasaron a igualarla. Lo que sigue distinto es código
de investigación y de facetas públicas que ningún recorrido del taller toca.
