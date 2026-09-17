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
  La búsqueda en portales de proveedor recibió los mismos sucesores en su mapa de medidas (122
  pruebas verdes, 1 nueva); la ficha pública de la tienda no necesita cambio.
- **Rótulos en el idioma de las tiendas chilenas.** El dueño vio «Posición de las mazas de este
  envase» y secciones en inglés en vinabike.cl. Con referencias de Bike Factory, Viaja en Bici,
  Faucon, Trek Chile, Imperio Bikers, Rideshop y Oxford Store se relabelaron 126 definiciones y 20
  opciones (`20260916180000`, `181000`), se sincronizó la segunda copia de las opciones que el
  validador usa (`182000`, sin ella la tienda ocultaba las fichas con opciones renombradas) y las
  secciones `primary/measurement/contents/declaration` se muestran como Características, Medidas,
  Qué incluye y Según el fabricante. Las lecturas de nombre pasaron a 896 hechos en 609 productos
  (13 nuevas gracias a los rótulos: Resina, Tiro arriba/abajo, Clave):
  [customer-facing-labels-2026-09-16.md](customer-facing-labels-2026-09-16.md). Llenado técnico
  persistido: 607 productos, 897 hechos, nada confirmado.
- **Rótulos, segunda pasada global (`20260916190000`).** Las 301 definiciones visibles que
  faltaban (427 de 570 relabeladas en total; el resto ya era lenguaje de tienda) y las opciones
  que los contratos nombran («Alambre», «Plegable (kevlar)», «Juego (delantera y trasera)», «Un
  plato», «Ahead (sin rosca)»…), renombradas en fila, `allowed_values` y contrato en una sola
  transacción verificada. Se queda `shifter_position` porque el cliente Dart distribuido compara
  sus textos exactos: requiere distribución. Sin hechos fuera de opciones tras el cambio; ficha
  pública leída como anónimo con los rótulos nuevos.
- **Compatibilidad de taller, transmisión, pedalier y freno, migrada a los sucesores.** Las 44
  claves `legacy` que el servicio seguía leyendo (velocidades, cuerpo de maza, piñón máximo,
  familia de indexado, platos, eje, caja, ancho, fluido, rotor…) quedan de respaldo detrás de sus
  sucesores; los sucesores de filas llegan como texto JSON y se decodifican, y una negación del
  fabricante en una fila refuta. 124 pruebas verdes (24 nuevas). La dirección no cambia porque la
  bici no registra dirección ni tubo. Los hechos `legacy` no migran solos (34 pedalieres con caja
  vieja y 0 con montajes declarados):
  [workshop-compatibility-drivetrain-bb-brake-successors-2026-09-16.md](workshop-compatibility-drivetrain-bb-brake-successors-2026-09-16.md).
- **Aplicador de observaciones retiradas de rueda (`20260916200000`).** 406 hechos en 263
  productos: rodado → diámetro ISO (tabla de Sheldon; ambiguos por la notación de ancho del
  nombre), pulgadas → mm, rodado + anchos → fila de ajuste de la cámara, válvula y calibre
  retirados → sucesor; misma fuente, sin confirmar. Fuera: rotores (prohibición de frenos) y
  pedalieres (filas con URL obligatoria). El taller compara neumáticos y cámaras por ISO y la
  tienda muestra «29" / 700c (ISO 622)»:
  [legacy-projections-2026-09-16.md](legacy-projections-2026-09-16.md).
- **Cámaras con aro visible en la tienda y auditoría global releída.** `tube_fit_rows` pasa a
  visible bajo «Aro y ancho de neumático» (`20260916202000`) y la tienda lo redacta como «26"
  (ISO 559), neumático 38.1-44.4 mm». Auditoría global de 22:34Z: físicos con hechos 461 → 844,
  pendientes 1.584 → 1.458, cero bloqueantes; hechos vivos 1.885 en 824 productos
  ([global-coverage-summary-2026-09-16b.json](global-coverage-summary-2026-09-16b.json)).
- **Filtros técnicos en la tienda (`20260916210000`).** `get_public_products_faceted_v2` y
  `get_public_product_facets_v2` aceptan `p_spec_filters`; el snapshot devuelve una fila por valor
  (`spec:<clave>:<tipo>:<unidad>`) con cobertura. Sólo campos filtrables y visibles del contrato
  vivo, sin `legacy` ni inferencias sin confirmar. La página ofrece los filtros que describen ≥30 %
  de lo que el cliente mira (válvula y largo en «Cámaras»; aro y ancho en neumáticos; velocidades
  y piñón mayor en cassettes), con conteos, URL y chips. 11 pruebas pgTAP nuevas (66 verdes) y
  8 pruebas Dart del formateador («2.1" · 53 mm», «29" / 700c (ISO 622)»). «Largo del rayo»
  reemplaza al único rótulo filtrable de ingeniero:
  [storefront-spec-facets-2026-09-16.md](storefront-spec-facets-2026-09-16.md).
- **Aro de cámara desde sus filas (`20260916220000`).** El núcleo de facetas proyecta la celda
  `bead_seat_diameter_mm` de «Aro y ancho de neumático» sobre el campo global «Aro (diámetro
  ISO)»: en «Cámaras» el cliente filtra por aro (21 de 23 cámaras) igual que en neumáticos. 2
  prueba pgTAP más (67).
- **«Lado» del shifter en lenguaje de tienda (`20260916230000`).** «Izquierdo (delantero)» y
  «Derecho (trasero)» en fila de opción, `allowed_values` y contrato de «Shifter / Mando Cambio»
  en una transacción verificada; sin release, porque el cliente Dart canonicaliza por palabras y
  no por texto exacto (corrige la nota del 2026-09-16). Las reglas de lectura de nombre apuntan a
  los textos nuevos.
- **Revocación de una aplicación de investigación (`20260916240000`).**
  `revoke_product_spec_research_application_v1` devuelve cada hecho a su preimagen archivada (o
  lo borra) sólo si sigue siendo lo que la aplicación escribió; conserva lo que un mecánico tocó;
  identidad de vuelta; recibo en `product_spec_research_revocations` y lector para el actor.
  Escenario pgTAP al cierre del test del aplicador (59 verdes):
  [research-revocation-2026-09-16.md](research-revocation-2026-09-16.md).
- **Publicación del ERP a los compañeros.** macOS, Windows y Android despachados desde el commit
  4ac87117 (gate 35162024511) con `publish_release=true`; las reglas de compatibilidad del taller
  con las claves sucesoras llegan con esta versión.
- **Sinónimos de lectura: no hacen falta.** Tras las dos pasadas de rótulos y fill-002c, sólo 3
  cámaras activas quedan sin tipo de válvula: «V.Bicicleta» / «V/Bicicleta» (ambiguo: no dice
  francesa ni auto) y una «F/v» sin stock. Un mecanismo de sinónimos en la guardia de lecturas
  costaría una columna y un cambio del validador para un producto; se descarta con esta cuenta.
- **fill-017: dos piezas VP Components rescatadas de la lista de taller (2026-09-16).** Segunda pasada por marca sobre los 318 «sin fuente»: VP tenía ficha oficial del motor VP-BC73 (rosca BC1.37” x 24T, eje incluido) y del pedal VPE-536 (cuerpo de nylon; identidad por eliminación sobre el listado oficial archivado). Beto, KMC, A-FORGE, Kalloy, Neco, SunRace y Saiguan se quedan con motivo corregido. Recibos en `fill-017-record-2026-09-16.md`.
- **fill-016: dieciocho Shimano en stock aplicados desde productinfo.shimano.com (2026-09-16).** bike.shimano.com redirigía toda URL a la portada; productinfo.shimano.com renderiza la tabla de especificaciones en el navegador integrado y se archivó literal por modelo (más las fichas hermanas usadas para eliminación y un registro de «No results»). Mandos SL-M315/SL-TX30/ST-EF500/SL-M5100/SL-M7100, cambio RD-M5100-SGS, desviador FD-TZ510-DS6, bielas FC-TY501/TY301, cassettes CS-HG200-7/8, pedalier SM-BB94-41A y kit BL/BR-MT200. Dos rondas de revisión par (113 hechos): la segunda sólo por una frase del método (el OPTICAL GEAR DISPLAY no discrimina indexado de fricción) y dos lecturas de código (un «(R)» ambiguo, un «41» del código de modelo). Sin modelo donde el nombre no distingue variantes (2A/4A, R/IR). 23 Shimano sin ficha van a la lista de taller con motivo. Recibos en `fill-016-record-2026-09-16.md`.
- **fill-014/015: dos mandos SunRace y un eje pasante ZTTO aplicados (2026-09-16).** SLM2T R7 y SLM2T LF (ficha oficial + listado oficial de los cuatro SLM2T para fijar LF por eliminación) y eje ZTTO 12x177LxM12(P1.5)x19 (ficha Shopify + JSON de variantes: `manufacturer_sku` TZG13, sin modelo porque la designación dimensional no es un modelo; enlace `thread_interface_id` entre filas). Dos rondas de revisión par, 10 hechos, recibos en `fill-014-015-record-2026-09-16.md`. Bloqueado con motivo: el juego Saiguan KD-20, cuya lectura de nombre previa deja de aplicar con «Par» y sólo una persona puede vaciar en el editor.
- **fill-011/012/013: diez productos varios aplicados (2026-09-16).** Topeak TJB-S6, Giyo GP-46L, Zoom SP-C261 y AT-115 ×2, Alligator HK-HST04/08, Finish Line Wet, Liqui Moly 6055 y Avid FR-5 con ficha oficial archivada, dos rondas de revisión par, 38 hechos, recibos en `fill-011-013-record-2026-09-16.md`. Huecos de contrato anotados: token de lubricante de cadena universal y campos técnicos de `rim_brake`.
- **fill-009 y fill-010: cinco llantas y dos motores Neco aplicados (2026-09-16).** Weinmann ZAC19/U32 TL/DISC BULL (catálogo PDF transcrito), Mavic XM 319 Disc (Technical Manual + índice) y Race Face AR Offset; Neco B910 73x118 y 73x122.5 (ficha + plano). 54 hechos, recibos en `fill-009-record-2026-09-16.md` y `fill-010-record-2026-09-16.md`. El lote de llantas destapó que el contrato cerraba el ETRTO a toda llanta cuyo perfil de talón la fuente no publica: migración `20260916270000_rim_etrto_without_bead_profile` («Otro» y «Desconocido / sin confirmar» abren ETRTO y tubeless). El constructor de propuestas leía la preimagen de un single_select desde las columnas del hecho (None) y no desde el valor resuelto del editor: corregido.
- **fill-007: cuatro horquillas SR Suntour aplicadas (2026-09-16).** XCT30, XCM30, XCR32 y AURON35 Boost EQ con ficha oficial y los manuales generales (tablas de neumático y rotor) archivados, una ronda de revisión par, 34 hechos, recibos en `fill-007-record-2026-09-16.md`. Criterio fijado con el revisor: el nombre puede fijar una opción de la lista que publica la ficha si el token coincide literalmente (o es una abreviatura sin otra lectura) y el hecho cita ambas fuentes.
- **fill-006: nueve herramientas de taller aplicadas (2026-09-16).** Super B (TB-6616, TB-6617, TB-PF35, TB-1906-L, TB-1925), IceToolz (62M1, 04D2), PRO (PRTLB051) y Topeak (TPS-SP26) con ficha oficial archivada, tres rondas de revisión par, 28 hechos, recibos en `fill-006-record-2026-09-16.md`; doce fuera con motivo. Hallazgo: la marca no viaja por la investigación (el preparador exige el comando canónico de identidad de marca); el simulador lo bloquea ahora desde la simulación.
- **fill-005: ocho investigaciones aplicadas y un hueco del refactor cerrado (2026-09-16).** Cambios, desviadores y manillas en stock con ficha OEM archivada (Shimano RD-TZ500-GS, RD-TY500, RD-M7100, FD-TZ510-DS6, SL-TZ500-LN; SunRace RDM41; Saiguan HG-38A y KD-20-03F), dos rondas de revisión par, 27 hechos, recibos en `fill-005-record-2026-09-16.md`. Doce productos quedan fuera con motivo (Sensah sin sitio, sin modelo en el nombre, fichas Shimano no renderizables). El lote destapó que la fusión de filas de investigación, el preview y la sonda de condiciones de fila tenían la versión 1 del rows_schema cableada mientras tres definiciones ya iban en v2: migración `20260916260000_research_rows_schema_version` (+ pgTAP), esquema de propuestas y simulador corregidos, y el simulador ahora bloquea `evidence_kind_insufficient` según `evidence_requirements` del contrato. Medición honesta: 1551 fichas activas, 452 con dato investigado, 395 sólo lectura de nombre, 704 sin nada; en stock 506, 401 pendientes de investigar.
- **fill-003 y fill-004: seis investigaciones aplicadas.** Conectores KMC CL559R, CL555R y CL566R
  (18 hechos: tipo, fuente OEM, clase de cadena, reutilizable, sentido de montaje, cadenas
  objetivo por filas) y pedalieres Shimano BB-UN300, SM-BB52 y BB-MT501 (11 hechos: montajes de
  caja por filas, puertos, ejes admitidos HOLLOWTECH II, fuente OEM), cada uno con propuesta
  contra el contrato vivo, evidencia OEM archivada con hash, revisión independiente de otra
  sesión (tres rondas: identidades cerradas por eliminación con las fichas hermanas de KMC; BSA y
  eje del BB-UN300 atribuidos al nombre guardado; nada que la ficha Shimano no diga) y recibo del
  aplicador. RISK (5 conectores) y 45 pedalieres sin ficha OEM quedan fuera con razón:
  [fill-003-004-record-2026-09-16.md](fill-003-004-record-2026-09-16.md).
