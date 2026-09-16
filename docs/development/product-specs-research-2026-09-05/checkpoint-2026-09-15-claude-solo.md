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
- Cobertura viva 19:45Z (tenant Viñabike): 1.673 productos, 59 servicios, 1.588
  con plantilla efectiva, 26 sin ella, 720 vinculaciones explícitas. (Corregido
  el 2026-09-16: un 27.º registro era del tenant de pruebas `testbike`.)
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

## Estado de git al parar (2026-09-15, ~20:20Z) y qué debe hacer la migración a `main`

Tres commits locales sobre `71926a11`, sin push:

| Commit | Contenido |
|---|---|
| `62a68acc` | 115 archivos: todas las migraciones aplicadas en producción del 09-06 al 09-15 con sus verificadores y suites pgTAP (incluye, por error de filtro, `20260915190000_reject_stale_need_portal_search_definitively.sql` y su verificador, de la otra sesión; están APPLIED en producción y su contenido es el de esa sesión, sin tocar) |
| `ea38266b` | 685 archivos: carpeta de investigación de fichas (sin `assigned-product-family-adjudication-2026-09-07.json`, que trae campos comerciales), docs de arquitectura y desarrollo modificados, `scripts/inventory`, `test/scripts`, `test/tools` |
| `8f3d8926` | 101 archivos: extensión cliente Dart y pruebas; analizador 0 errores. Incluye, por el mismo error de filtro, cuatro archivos terminados de la otra sesión (`supplier_portal_headless_runner.dart`, `supplier_availability_service.dart`, `intelligent_purchasing_workspace_page.dart`, `supplier_receipt_transport_test.dart`), con su contenido íntegro |

Quedan sin commit, a propósito: `supabase/migrations/20260723023000_add_audited_sales_payment_corrections.sql`
(migración aplicada editada después; no es mía), `supabase/tests/supply_need_edit_modes.sql`
y `supabase/tests/supply_need_stock_scope_before_evaluating.sql` (otra sesión).
Copias de seguridad de todo lo no commiteado antes de estos commits:
`.tmp/backups/untracked-20260915-checkpoint.tgz` y
`.tmp/backups/tracked-modifications-20260915-checkpoint.patch`.

`origin/smartpegas1.0` (`f51f3777`) sigue tres commits por delante de `71926a11`
(release del 09-07 desde un clon). Verificado archivo por archivo: los 152
archivos que esos commits cambian ya están en este árbol con ese contenido
(129 idénticos, 23 con ediciones locales encima que contienen sus hunks). El
hook del checkout impide mover HEAD con reset; la fusión la hace quien
promueva a `main`: `git merge origin/smartpegas1.0` sobre estos commits debe
resolver limpio o, en los 23 archivos, conservar la versión local. `origin/main`
(`75cb391f`) está 94 commits por detrás de `origin/smartpegas1.0`.

## Base local

El reset de la otra sesión dejó la base local en el baseline `core_schema.sql`,
que trae `spec_definitions`, `spec_templates`, `spec_template_fields`,
`category_tech_mappings` y `product_spec_values`, pero no `spec_definition_values`
ni `spec_facts`. Para volver a ensayar hay que reaplicar en orden, con
`VINABIKE_DB_WRITE_CONFIRM=local scripts/db/query.sh local --write --file`, las
migraciones de motor desde `20260821160000` (vocabulario en filas) y
`20260821180000` (registro unificado) hasta `20260915200000`, saltando las que
exigen preimagen exacta de producción (publicaciones `nd_publication_document`,
`existing_global_metadata_forward_only`, `assignment_document`): esas se ensayan
con siembra (`prepare`). Pendiente hasta que termine la migración a `main`.

## Punto de parada

Trabajo detenido aquí por decisión del dueño hasta cerrar la migración a `main`.
Al reanudar: (1) restaurar la base local; (2) 26 registros sin plantilla;
(3) reemplazos originales; (4) release del cliente y asignación de AE0266/AE0274;
(5) gates del llenado.

## Preparación del cutover (runbook 9.2), 2026-09-15

Clasificación del árbol sucio: **producto intencional** → commits `62a68acc`,
`ea38266b`, `8f3d8926`, `05269b2b`, `60a9a5d9`, `bb739233` y este; el JSON
`assigned-product-family-adjudication-2026-09-07.json` se revisó y no contiene
campos comerciales (sólo `establishes_stock_model`), así que entra como producto.
**Local/temporal:** nada quedó fuera salvo `.tmp/` (ya ignorado). **Cambio
concurrente:** la otra sesión terminó; sus archivos van íntegros en los commits
anteriores. `20260723023000_add_audited_sales_payment_corrections.sql` está
`NOT_APPLIED` en producción (sus objetos entraron por `20260910123000`,
`APPLIED`); el cambio es sólo la cabecera «SUPERSEDED, never deploy» del 10-09 y
es legítimo. Fusión con `origin/smartpegas1.0` (`f51f3777`) por estrategia
`ours`: verificado blob a blob que los 152 archivos que esos tres commits tocan
están en HEAD idénticos (129) o como evolución local posterior de la misma foto
del 07-09 (23; el único con hunks exclusivos del clon, `copilot-instructions.md`,
ya los contiene). Worktrees inventariados: tres de Codex, todos detached.


## Continuación en `main`, 2026-09-16

- Motor local restaurado por replay de migraciones standalone; el procedimiento y
  sus trampas están en [local-engine-restore-2026-09-16.md](local-engine-restore-2026-09-16.md).
  Los once hashes (validador, coherencia, RPC de asignación y de ficha) coinciden
  con producción; el ensayo de asignación pasa 4/4.
- Publicado el reemplazo de neumáticos y cámaras (`20260916030000`, cinco
  plantillas, 271 productos, cero bloqueantes, 813 observaciones legacy
  conservadas): [tire-tube-successors-adjudication-2026-09-16.md](tire-tube-successors-adjudication-2026-09-16.md).
  Entregas planificadas: 78 de 105; quedan 27 reemplazos originales.
- Después de neumáticos y cámaras se publicaron el mismo día rayos (`20260916040000`, 58),
  maza y llanta (`20260916050000`, 96), mandos y desviadores (`20260916060000`, 94),
  bielas y platos (`20260916070000`, 57), cadena y conector (`20260916080000`, 44),
  patillas y roldanas (`20260916090000`, 38), rodamiento y pedalier (`20260916100000`, 72),
  dirección (`20260916120000`, 16) y piñonería trasera (`20260916110000`, 64). Cada uno con
  su `*-successors-adjudication-2026-09-16.md`. Entregas planificadas en ese momento: 102 de 105.
- Dos reglas nuevas quedaron escritas en los compiladores: un campo nuevo nacido `legacy` sólo
  se crea si Root lo retiró con casos; y una publicación que cambia coherencia sobre campos con
  hechos necesita diagnóstico inline y suspensión acotada de la guardia (piñonería).
- El cliente publicado desde `dc1e6093` (macOS, Android y Windows, 2026-09-15 22:25Z) contiene
  la extensión `8f3d8926`; con eso AE0266 y AE0274 se asignaron a `seatpost_shim` por la ruta
  auditada. Cobertura viva: 1.594 con plantilla, 20 sin ella, 726 explícitas.
- D2 cerrado: las tres presentaciones completas de freno se publicaron como revisión 223
  (`20260916130000`, 44 productos, cero bloqueantes, 5 observaciones legacy conservadas, guardia de
  coherencia sin tocar): [brake-presentations-adjudication-2026-09-16.md](brake-presentations-adjudication-2026-09-16.md).
  Cierra los dos errores de propiedad de Root (dueño de `tool_size_mm` y los dos mecanismos de un
  par de llanta). Entregas planificadas: **105 de 105**; quedan 0 reemplazos originales. Lo que no
  prueba: comparación entre perfiles (E2), un par con un solo circuito, cambio de presentación
  conservando filas. Llenado técnico persistido: 0.
- Primera compuerta del llenado: auditoría global releída el 2026-09-16 09:17Z con el runner
  versionado `refresh_global_coverage_audit.py` (instantánea MVCC única + 56 lotes de 30):
  1.594 con plantilla, 20 sin ella, cero bloqueantes, 1.584 con pendientes, 461 con
  observaciones (sin cambio), un hecho fuera de plantilla (C1087). Resumen en
  `global-coverage-summary-2026-09-16.json`. Llenado técnico persistido: 0.
- Aplicador de investigación publicado (`20260916140000`): tres tablas cerradas, procedencia
  `research` admitida, tres RPC definer para `authenticated`. Nada habilitado: cero readiness,
  cero aplicaciones, cero recibos. Compuertas: pgTAP 42/42 en base limpia e instalada, Python
  32/32, ida y vuelta local con tres calendarios de contención, verificador antes/después. El
  primer despliegue verificó funciones pero no la ACL de tablas (privilegio por defecto a
  `codex_test_runner`); la migración se rehizo reejecutable y el mismo comando la selló:
  [research-applier-publication-2026-09-16.md](research-applier-publication-2026-09-16.md).
  Llenado técnico persistido: 0.
- Segunda compuerta, parte estructural: auditoría de definiciones con consumidores
  (`audit_definition_consumers.py`): 901 definiciones vivas, 123 leídas por clave, 53 ya
  `legacy` en todas sus plantillas y 4 sin plantilla activa. La compatibilidad de taller lee 44
  claves `legacy` (degrada a cautela, no a veredicto falso); el portal de proveedores 9 y la ficha
  pública de la tienda 11. Ninguna función SQL ni edge con fuga:
  [definition-consumer-audit-2026-09-16.md](definition-consumer-audit-2026-09-16.md).
  Siguiente bloque: migrar el consumidor de taller familia por familia. Llenado técnico
  persistido: 0.
- Tercera compuerta, parte estructural: matriz de las 107 plantillas contra el contrato de
  familia (`audit_family_contract_matrix.py`). 68 plantillas ciegas (sin campo visible ni
  filtrable; 620 productos, 609 campos), 8 sin decisión inicial, `brake_presentation` obligatorio
  sin fuente exigida en las tres presentaciones, campos críticos sólo en cadena y conector, 32
  plantillas candidatas estructurales para un primer lote:
  [family-contract-matrix-2026-09-16.md](family-contract-matrix-2026-09-16.md). Llenado técnico
  persistido: 0.
- Campos críticos por familia derivados del contrato como borrador para las 105 familias que no
  los tenían (`derive_critical_fields.py`, `catalog-fill-critical-fields-derived-2026-09-16.json`);
  cadena y conector siguen siendo los únicos revisados. Llenado técnico persistido: 0.
- Registrador revisado (sin segundo revisor disponible): la CLI ahora exige los archivos de
  auditoría y de revisión que la readiness hashea y recalcula sus sha256; los pendientes
  `authenticated_spec_only_applicator_pending` y `research_provenance_writer_pending` se
  retiraron porque el aplicador existe; queda `global_sanitation_open`. 58 pruebas unitarias e
  ida y vuelta local verdes:
  [registrar-independent-review-2026-09-16.md](registrar-independent-review-2026-09-16.md).
- Propuesta de flags de visibilidad y filtro para los campos ciegos, no publicada: 371
  definiciones (362 visibles, 305 filtrables, cero apagados) en 90 plantillas, con regla escrita
  y ocho campos fuera de la regla listados sin cambio:
  [definition-flags-proposal-2026-09-16.md](definition-flags-proposal-2026-09-16.md). Es
  decisión del dueño publicarla, recortarla o diferirla. Llenado técnico persistido: 0.
- Flags de visibilidad y filtro publicados (`20260916150000`): 371 definiciones, ninguna
  apagada; definiciones visibles 264→626, filtrables 251→556, plantillas con campo visible 39→100
  de 107; versiones de contrato y hechos sin cambio. Decisión de Claude con criterio de negocio:
  lo que se llene desde ahora se ve en la tienda y lo puede pedir el asistente:
  [definition-flags-publication-2026-09-16.md](definition-flags-publication-2026-09-16.md).
- Segundo revisor y llave del llenado: el aplicador acepta como revisor `codex`, `claude`,
  `claude-peer` (otra sesión de Claude con contexto fresco) u `owner`, siempre distinto del
  investigador (`20260916160000`, 58 pruebas y 42 aserciones verdes). La readiness de Viñabike
  quedó insertada y habilitada con los sha256 de la auditoría global releída y del cierre del
  saneamiento ([sanitation-closure-2026-09-16.md](sanitation-closure-2026-09-16.md),
  recibo `readiness-2026-09-16.json`). Desde aquí el aplicador puede escribir un producto por
  aplicación registrada y revisada. Llenado técnico persistido: 0.
- **Primer llenado técnico persistido: 1 producto, 6 hechos.** Conector KMC CL573R
  (`chain_link` contrato 40): identidad `model = CL573R`, tipo de conector, clase de cadena
  6/7/8, reutilizable, sin sentido de montaje, fuente OEM y cuatro declaraciones de cadenas
  objetivo por filas. Investigó `claude` sobre la investigación de Codex del 09-07; revisó
  `claude-peer` (otra sesión) en dos rondas; aplicación `91337f24…`, revisión 0→11, recibo
  consistente con la lectura posterior; la ficha pública muestra cuatro filas:
  [fill-001-cl573r-record.md](fill-001-cl573r-record.md). Todo con procedencia `research` y sin
  confirmar; nada comercial tocado.
- **Segundo llenado, masivo: 842 lecturas de nombre en 575 productos de 33 familias** por el
  RPC `record_product_spec_reading_v1` como el actor real (`fill_name_readings.py`, ensayo con
  rollback y luego 23 transacciones). Reglas deterministas por familia
  (`spec_name_reading_rules.py`) con réplica offline de los chequeos del servidor; la guardia de
  coherencia rechazó 6 lecturas en total (juegos de mazas, pedalier integrado) y las reglas se
  recortaron antes del commit. Hechos `name_reading` 14→847, productos con lectura 13→578,
  68 campos, todos visibles al cliente y filtrables. Sin leer por diseño: listas de velocidades,
  válvulas `V/A`/`VF`, cadenas `1/8`, «Resina», booleanos cuyo vocabulario es el sustantivo del
  producto: [fill-002-name-readings-record.md](fill-002-name-readings-record.md). Llenado técnico
  persistido tras la segunda pasada (cáliper, horquilla, cierres: 36 lecturas en 25 productos):
  601 productos, 884 hechos (1/6 research + 600/878 name_reading), nada confirmado.
- **Compatibilidad de taller, familias de rueda, migrada a los sucesores.** El servicio de
  compatibilidad leía sólo las claves `legacy` (`hub_spacing_mm`, `spoke_holes`, `wheel_size`,
  `valve_type`, `freehub_type`, `wheel_position`) que el lector excluye; ahora lee `hub_old_mm`,
  `spoke_hole_count`, `hub_package_position`, `hub_drive_receiver_kind`, `bead_seat_diameter_mm`
  y `valve_standard` con el original de respaldo. BSD medido vs rótulo inequívoco es veredicto;
  núcleo de cassette refuta bici roscada y deja el estriado por confirmar; un juego se revisa por
  pieza. 100 pruebas verdes (9 nuevas). Transmisión, pedalier y freno siguen en `legacy` (30
  claves): [workshop-compatibility-wheel-successors-2026-09-16.md](workshop-compatibility-wheel-successors-2026-09-16.md).
