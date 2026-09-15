# Checkpoint · Claude en solitario, bloque «orden escalar y casquillo» (2026-09-15)

Propietario: Claude. Revisión previa de la sesión de Codex en
[`codex-session-review-2026-09-15.md`](codex-session-review-2026-09-15.md).
Dictamen técnico vigente: [`seatpost-shim-and-scalar-review-2026-09-15.md`](seatpost-shim-and-scalar-review-2026-09-15.md).

## Hecho en este bloque

| Paso | Resultado | Evidencia |
|---|---|---|
| 1 · Orden escalar estricto | `20260915200000_product_spec_strict_scalar` APPLIED en producción, verificado: 4 funciones exactas (ACL, dueño, modo), 106 contratos existentes validados, 11 casos, huellas de definiciones/plantillas/campos/hechos/referencias/productos sin cambio | migración `e25ce520e2085537…` (= candidato `e25ce520…`), verificador `704a0b8043cedd9f…`, recibo `.tmp/db/migration-receipts/20260915200000.receipt`; preimagen fresca idéntica a la revisada; verificador falló antes del deploy |
| 2 · Casquillo `seatpost_shim` | H1 corregido: reutiliza `shim_inner_diameter_mm`, `shim_outer_diameter_mm` y `seatpost_shim_length_mm` con los IDs de producción; 4 definiciones nuevas; longitud opcional (F2); guardia explícita sobre los cuatro md5 del motor (F1). `20260915203000_seatpost_shim_template` APPLIED: plantilla `bdd99089-75c5-5370-919c-38a6cdefd892` v11, 10 campos, 0 productos | preimagen `a9ab487c4cf97254…` (19:48:40Z), catálogo `c92456b25dd5a692…`, casos `eefd42623faf4982…`, paquete `f8767700cbaa1a57…`, migración `30b3937e23230b4a…`, verificador `3120a487990f5af7…`; ensayo SQL 25 · 1 + réplica + 9 aserciones del escritor; Dart 26/26; recibo `20260915203000.receipt` |
| 3 · Rama heredada de `seatpost` | `20260915210000_seatpost_legacy_shim_branch` APPLIED: v23 → v27; `shim_inner_diameter_mm`, `shim_outer_diameter_mm` y `seatpost_shim_length_mm` a legacy (`allowed_when never`, sección legacy); «Suplemento (shim)» fuera de `allowed_options.seatpost_kind` sólo en este contrato (vocabulario y definiciones intactos); 14 productos explícitos y 0 hechos conservados | compilador `scripts/inventory/compile_seatpost_legacy_branch.py`, preimagen `5c1f6ac4d985255b…` (19:54:15Z), catálogo `ec8466326fee2796…`, casos `24a4ed016a415a91…` (7), paquete `a48d0fcf47a56e88…`, migración `0a3e8f99828a9335…`, verificador `79af2a9df32dc1ca…`; ensayo forward + réplica 7 · 1; Dart 9/9; recibo `20260915210000.receipt` |

Archivos míos en este bloque: `scripts/inventory/compile_seatpost_shim.py`,
`scripts/inventory/test_seatpost_shim.py`, `scripts/inventory/compile_seatpost_legacy_branch.py`, los tres JSON del casquillo y los tres del delta de `seatpost`, la
adjudicación `seatpost-shim-architecture-evidence-2026-09-15.md` (sección de
cierre), las tres migraciones con sus verificadores, `progress-measurement-2026-09-08.json`
(contadores separados; `overall_percent` sigue en `null`) y este checkpoint.

## Contadores

- Plantillas globales: 107 (105 planificadas + `component_set` + `seatpost_shim`).
- Cobertura viva 19:45Z: 1.674 productos, 59 servicios, 1.588 con plantilla
  efectiva, 27 sin ella, 720 vinculaciones explícitas.
- Llenado técnico persistido: **0**. Perfiles persistidos: 0. Hechos escritos
  por este bloque: 0. Asignaciones de este bloque: 0.

## Qué no se hizo y por qué

- **AE0266 y AE0274 no se asignaron.** El cliente distribuido (release macOS
  1.0.3-177 / Android 65, commit `f51f3777`) rechaza un par de tres elementos
  con `FormatException` al montar el editor del producto: cierra en falso, no
  interpreta `≤`. Publicar la plantilla no afecta a ningún cliente mientras no
  haya productos asignados; asignar esos dos SKU haría que su editor no abra
  en las apps instaladas hasta una nueva distribución. La distribución
  requiere autorización del dueño (regla de cliente del handoff). Decisión
  pendiente: distribuir primero, o asignar aceptando el cierre en falso.
- **Git:** 23 migraciones aplicadas sólo en el árbol local y checkout tres
  commits por detrás de `origin/smartpegas1.0`; no hice commit ni reconcilié.
  Es la decisión más urgente del dueño.

## Siguiente acción concreta

1. Decisión del dueño sobre distribución del cliente; después, asignación
   aislada de AE0266 y AE0274 con recibo y read-back.
2. Reconciliar git con `origin/smartpegas1.0` (decisión del dueño).
3. Continuar por los 27 registros sin plantilla y los 32 reemplazos originales.

## Concurrencia observada al cerrar (no es trabajo mío)

- Otra sesión trabaja en este mismo checkout: apareció
  `supabase/migrations/20260915190000_reject_stale_need_portal_search_definitively.sql`
  con su verificador (12:52 local) y las modificaciones de archivos con
  seguimiento subieron de 55 a 60. No los toqué.
- A las 19:57:30Z el contenedor local `supabase_db_bikeshop-erp` recibió una
  recarga de esquema ajena a `query.sh` (el diario no registra escrituras
  locales desde las 02:53Z): hoy la base local no tiene `public.spec_facts` ni
  ninguna función `spec_*`, y sus jobs buscan `recover_whatsapp_outbox_v1` sin
  éxito. Mis tres ensayos locales (19:35Z, 19:56Z) corrieron antes y pasaron;
  las tres publicaciones están verificadas en producción y no dependen de la
  base local. Quien necesite ensayar de nuevo debe restaurar primero el esquema
  local; no lo hice yo para no pisar la sesión concurrente.

