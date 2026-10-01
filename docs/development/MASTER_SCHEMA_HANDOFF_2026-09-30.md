# Traspaso del cierre del Master Schema

Fecha: 2026-09-30, 08:37 UTC. **Master completo ABIERTO**.

Chat receptor creado: **Finish Master Schema with Claude**,
`01a0f17d-4e9c-7602-a5b5-e3f86b1b5f28`, host local, mismo checkout.
Runtime verificado en su primer turn_context: modelo `gpt-6.1-sol`, esfuerzo
`max`, `danger-full-access`, perfil de permisos `disabled`, aprobación `never`.
Chat anterior `01a0cef9-49cd-7411-a09f-647a21f6e09b`: deja la conducción al
completar esta transferencia; no retoma implementaciones por un wake antiguo.

**Actualización del receptor, 2026-09-30:** transferencia completa. El forward
`20260930020000` ya está instalado/probado **32/32** local y desplegado con
readback exacto, sello `APPLIED` y recibo; health 0 críticos/19 históricas.
El bloque «pendiente» de este traspaso describe el punto anterior. C1 formulario
real web pasó 1/1 en `.tmp/e2e/task-form-20260930-033442.log`, readback=1,
retirada_completa=1 y 24 frames; Codex los revisó sin repetir. Claude liberó
el turno DB y revisó en lectura C2. Codex integró sus hallazgos: el RPC real
instalado pasó **32/32**, incluidos WHEN/rules. Readbacks exactos local/remoto,
carreras de dos conexiones sin escritura y deploy guardado completo: forward
`20260930092309` APPLIED a 13:13:30 UTC. Cliente pareado nuevo, gate 18/18;
940 ventas/87 compras/2675 asientos sin cambio, sin restore productivo.
C1 Android está aceptado: `.tmp/e2e/android-task-form-20260930-055146.log`,
readback/retirada=1, 14 frames; no repetir. Claude corrigió visor oscuro/footer
con 31/31 reportados y ahora posee de nuevo en exclusiva DB local/servicios,
`bike_form_dialog.dart`, helper de origen y recorrido C1/C4 con repuestos.
Codex posee C2 y `BikeRecordPanel`/`BikeSystemController`: mapa/origen listos,
escritorio ancho/estrecho claro/oscuro aceptado, mapa 2/2 y origen 1/1. Claude
recibió aviso y ejecuta Android completo con un APK nuevo. El cuerpo de cierre
`20260930152000` quedó APPLIED a 15:34:04 UTC, idéntico al ya ejercido en local.
C2 preflight real mostró timeout/exception cruda; Codex corrige aviso/reintento
y prepara el motor completo sin repetir kernels. C1 completo/C2 pleno/C3/C4/C5 siguen abiertos.
`PLANS.md` manda sobre este snapshot; los bloques siguientes son históricos.

## Pedido directo del dueño

Continuar en un chat nuevo con GPT 6.1, esfuerzo Max y Full access. El dueño
pidió también dar libertad a Claude para implementar, correr consultas y
pruebas con criterio, sin permisos rutinarios ni comprobaciones redundantes.
El chat anterior transfiere la conducción y deja de implementar al completar
el traspaso; no deben existir dos supervisores dando órdenes a Claude.

## El resultado y el rumbo

Leer primero `PLANS.md`, `AGENTS.md`, `.github/copilot-instructions.md` y sólo
los documentos ruteados pertinentes. `BIKE_WORKSHOP_MASTER_SCHEMA.md` define
la arquitectura; el plan controla la entrega, en este orden:

1. **C1: recorrido usable del taller.** Guardar, encargar, corregir un cierre
   bloqueado, usar adjuntos y finalizar en las superficies canónicas, con app
   real de escritorio/teléfono, claro/oscuro.
2. **C2: recuperación completa.** Integrar el motor seguro con dependencias,
   columnas/defaults y aislamiento de efectos de stock, contabilidad y mensajes.
3. **C3: privacidad heredada.** Dueño, copia con recibo y vínculos válidos antes
   de retirar datos públicos en un alcance autorizado.
4. **C4: siete criterios de arquitectura.** Modelo conocido inicia ficha útil;
   ficha manda en diagnóstico/servicios; asistentes reutilizan hechos;
   diagnóstico condicional; ejecución ligada a la bici/lado/componente correctos;
   memoria derivada consistente; historial visible claro.
5. **C5: cliente entregado.** Fuentes reconstruibles, gates pertinentes y
   publicación autorizada con comprobación en vivo. Publicación aún no autorizada.

El dueño corrigió una cadena de prototipos que no cerraba funciones usables.
Cada prueba debe decidir una casilla o defecto concreto y justificar por qué
la evidencia anterior no basta. Usar la mínima suficiente y volver a entregar.
No ampliar R1.b, contar archivos ni repetir baterías por heartbeat. Una sonda
no cuenta como función entregada. Las decisiones rutinarias de producto y UX
están delegadas a ambos agentes.

## Estado vivo y límites

- Checkout compartido `/Users/Claudio/Dev/bikeshop-erp`, **main**, HEAD
  `0cd98f00`. Hay muchos cambios propios y ajenos, índice vacío. Sin ramas,
  worktrees, stage, commit, push ni publicación del cliente.
- Debug canónica reconsultada: **PID 55996**, screen **payroll**.
  `scripts/dev/native_session.sh status|reload|restart` es su dueño. No arrancar
  otra sesión ni reemplazarla. Esta app nativa usa producción.
- Disco ~22 GiB al último chequeo. Preservar cachés activas, Papelera, Colima,
  WhatsApp y sesiones. Retirar sólo artefactos propios; no vaciar Papelera.
- SQL por `docs/development/AGENT_DATABASE_CONTRACT.md` y sus dos documentos
  ruteados. Queries mediante `scripts/db/query.sh`; forward de producción
  revisado mediante `scripts/db/deploy_migration.sh` con readback y stamp.
  SQL in-scope no destructivo está autorizado; no requiere otra confirmación.
  Nunca editar/reejecutar APPLIED, hacer backfill amplio/destructivo, probes de
  datos productivos ni purgar bytes huérfanos por ausencia/edad.

## Claude: autonomía, sesión y archivos exclusivos

Reusar **Análisis integral de sitio web y SEO**, Code/bikeshop-erp/main:
`claude.ai/epitaxy/local_d570e93f-1959-4f9d-aa24-7daa458b1723`.
Opus 5.5 / Ultracode visibles, Dynamic workflows OFF; no subagentes. La
excepción del selector está documentada en CODEX_CLAUDE_COLLABORATION.
No reenviar R0/R1 ya completados ni enviar mientras Running. Antes de cada
Send: identidad fresca de chat/composer, Code, repo, modelo y esfuerzo.
Computer Use es `mcp__cua_repl`; después de compacción recuperar su documentación.

Claude puede implementar, diagnosticar, correr consultas guardadas y pruebas
focales, corregir defectos y escoger la siguiente acción de su entregable.
Codex coordina la integración y protege el checkout; no debe reducirlo a
propuestas ni obligarlo a esperar autorización para cada comando. Turnos DB
local secuenciales y archivos exclusivos evitan interferencia. Al terminar,
leer y revisar su resultado, asignar inmediatamente otro paso implementable
seguro y verificar Running mientras el Master siga abierto.

Su corte actual C1 posee:

- `scripts/e2e/run_task_attachments_local.sh`
- `scripts/e2e/task_attachments_local_fixture.sql`
- `test/integration/task_attachments_local_test.dart`

**Nuevo resultado comprobado por Codex, sin repetir la prueba:** el log
`.tmp/e2e/task-attachments-20260930-013406.log` termina 08:36:17 UTC con
recorrido completo, readback=1 y retirada_completa=1. Un empleado mechanic
sintético entró por Auth real y TaskService subió/abrió/retiró su archivo:
apertura HTTP 200 con 55 bytes iguales; el otro taller no consiguió URL,
descarga ni vínculo; retiro completo y URL anterior HTTP 400. Prueba 1/1.
Un vínculo retirado/acuse, cero vínculos del taller B y cero objetos restantes.
El script separa preparación administrativa de la sesión del empleado; no
hay mocks de red. Se leyeron los tres archivos y el log.

La DB preparada se preservó al stop/start con su volumen. A 08:37 UTC Docker
muestra DB, Auth, REST, Storage y Kong activos; DB/Auth/Storage/Kong healthy.
No repetir el start no-op antiguo ni afirmar que Auth/Storage siguen apagados.
La descarga dirigida oficial necesaria para C1 fue aprobada en la sesión;
no es una descarga rutinaria y no se pide otra confirmación.

Claude aún figuraba Running terminando el corte al último chequeo. **Mantiene
el turno DB hasta su cierre**: Codex no ejecuta wrappers locales ni reinicia
contenedores entre tanto. Comprobar su respuesta final y liberación del turno.
El resultado de red NO cierra toda C1: falta el recorrido UI y teléfono.

## Codex: forward de protección de facturas pendiente

Archivos bajo conducción de Codex; Claude no los está editando:

- `supabase/migrations/20260930020000_guard_posted_invoice_delete_authorization.sql`
- `supabase/manual_checks/verification/20260930020000_guard_posted_invoice_delete_authorization.sql`
- `supabase/tests/posted_invoice_purge_authorization.sql`

El GUC antiguo abría la purga como authenticated porque el guard era SECURITY
DEFINER y veía current_user=dueño. Reproducción/candidato anterior local 38/38,
ROLLBACK. No se demostró una ruta PostgREST que permita fijar esa variable:
no atribuir una explotación de API ni tocar facturas reales.

Claude entregó el forward sin ejecutarlo: autorización privada de una fila,
taller y transacción, consumida una vez; sólo backend/owner autorizan por ACL.
Cancelación y borradores conservan su comportamiento. No es el motor de restore.
Codex comprobó que los tres cuerpos coinciden exactamente con el candidato
ya probado y corrigió precondición/readback: hashes exactos, search_path y
propietarios, no una mera coincidencia del nombre del helper. Añadió timeouts
de DDL y recuperación que no reinstala el bypass vulnerable. Whitespace limpio.

SHA-256 vigente del forward:
`b5717dc2a854e305208ea34bbca6c361b16faa133764ee26f3033ab519712204`.
Readback:
`46a1c9815d57a0867cbb242b134bb3c33eebbf446eb5cc420309f42ab62daf35`.
Lectura productiva focal: head `20260930010000`, candidate NOT_APPLIED, hash
del guard original `ddb0b13b7e4d511a3826c115efb79271`, cero otros lectores del
GUC en funciones y sin colisiones con los tres objetos nuevos; 905 ventas y
83 compras protegidas. Readback previo falló con division by zero esperado.

**Siguiente acción de integración:** tras liberar Claude el turno DB, aplicar
este forward exacto una vez en local y correr sólo
`scripts/db/test.sh posted_invoice_purge_authorization`. Es el gate pendiente
del forward instalado, distinto del candidato 38/38. Si pasa, completar su
deploy revisado, readback/stamp/recibo y health por el cambio; volver a C1/C2.
No afirmar prueba/despliegue del forward antes de eso.

## Evidencia reutilizable y pendientes grandes

- Última APPLIED `20260930010000_restore_legacy_column_preflight.sql`, SHA
  `f1bf6cc2ee96069312428c4bb9f6113cb6bf1f44959bc06e095d36e6023f8e00`.
  Readback `8215c083928c3fcd16d3482c7eea19a354e6411255216ed582adb56d1a2c4ff8`;
  pgTAP 11/11, widget 1/1, analyzer focal limpio. db-health previo 0 críticos,
  19 históricas. No repetir sin cambio. 25 migraciones/readbacks/recibos locales
  previos cotejados por SHA; un clon limpio sigue sin esas fuentes untracked.
- Gate Flutter completo verde y Chrome 5/5, una vez 03:50–03:55 UTC; analyzer
  lib/test sin errores, 28 advertencias ajenas/484 infos. Reutilizar.
- Restore cubre 38 tablas; 101 dependientes con filas en 10 talleres. Guardias
  niegan casos peligrosos; replay DELETE/reINSERT sigue sin ser seguro.
  Planner local Codex `restore_diff_plan_local.sql` 42/42, sólo pg_temp/SELECT,
  can_restore=false. R1 Claude `restore_effect_context_local.sql` 36/36,
  ROLLBACK, no integrado. Ambos son insumos: falta engine, CHECK/UNIQUE,
  membresía, efectos, concurrencia y volumen. No seguir expandiendo prototipos.
  statement_timestamp no separa sentencias de un mismo packet; permisos de
  efectos deben cerrarse por invocación. `app.syncing_job_to_invoice` también
  permite omitir contabilidad en reproducción local; sincronización legítima
  necesita contexto privado propio, no permiso genérico de restore.
- Teléfono sigue abierto: MLKit excluye arm64 simulator/M1; build genérico
  x86_64 pasó pero iPhone17e dio EBADARCH y x86 no produjo sesión útil. No
  repetir build/boot ni quitar exclusiones a ciegas. iOS16 alineado, Podfile.lock
  record_ios/share_plus preservar. Smoke iOS analyzer limpio, no ejecutado ni
  frame. Arnés aislado sólo probaría widgets/insets, no el cliente autenticado.
- Journal de uploads no excluye dos procesos del mismo usuario. No borrar
  bytes sin vínculo por absent/edad/claim SQL aislado: falta fencing de intento
  en Storage y vínculo, incluida subida tardía ya admitida.
- Assets públicos heredados: 8 imágenes mechanic_jobs (6 refs propias,
  2 HEIC no trazadas) y 8 PDFs presupuestos del chat antiguo. No demuestra
  orfandad ni ausencia de entregas/copias; no mover/borrar sin recibo/alcance.

## Automatización y primera respuesta

Heartbeat `revisar-trabajo-de-claude-en-sitio-vi-abike`, ACTIVE cada 2 minutos;
se transfiere al chat nuevo, sin duplicarlo. Actualizar hechos recientes y
preservar silencio salvo conclusión material, defecto nuevo, bloqueo real o
autoridad necesaria. No pausar hasta todo el Master o pedido del dueño.

Al iniciar: confirmar modelo/esfuerzo/permisos efectivos y leer este traspaso.
Durante el breve cierre de la transferencia, sólo lectura/monitor de Claude;
esperar el mensaje «takeover complete» antes de editar archivos compartidos.
Después, tomar la conducción y continuar sin pedir al dueño que repita contexto.

## Checkpoint C2 de Claude — motor integrado (2026-09-30, local, SIN DESPLEGAR)

Listo para la revisión de Codex. No se desplegó nada, no se tocó `PLANS.md`
ni SQL APPLIED, sin stage/commit/push. Turno DB local y servicios **devueltos
a Codex** al cierre de este checkpoint (DB, Auth, REST, Storage y Kong
arriba; preview local detenido; fixtures retiradas).

**Regla:** «vuelve lo que falta; lo que existe hoy manda». Nunca UPDATE ni
DELETE: sólo INSERT de identidades ausentes. Raíces bicis, trabajos y tareas;
sus 28 miembros vuelven sólo con su raíz; 7 catálogos independientes; 32
tablas de ventas, compras, contabilidad, stock, mensajería, sitio, ajustes,
productos y personal sólo se cuentan. El respaldo real de diciembre lo exige:
39 de sus 40 líneas ausentes son de trabajos vivos y facturados, y 34 clientes
cambiaron teléfono/RUT después. Detalle de diseño en
`BIKE_WORKSHOP_MASTER_SCHEMA.md`, cola operativa, «C2 motor integrado».

**Lo que usa el cliente** (misma entrada `Configuración > Respaldos`, mismos
RPC `restore_backup_merge_preflight`/`restore_backup_merge`, contrato
`workshop_graph_v1`, modo `restore_missing_keep_live`): la revisión dice qué
vuelve (trabajos, bicis, tareas y clientes primero, con su nombre), qué no
vuelve y por qué, qué vínculo vuelve suelto, cuántos registros existen y se
quedan, y que ventas/compras/contabilidad/inventario/mensajes/productos/ajustes
no se tocan. Sin nada que recuperar no ofrece Restaurar. El resultado repite
lo que volvió; «Ver detalles» dice cuántos registros volvieron. Negativas
`restore_merge_not_safe`, `_constraint_conflict`, `_busy`, `_timeout`.

**Fuentes exactas del primer corte (SHA-256)** — el ajuste de abajo cambia
`172000`, su verificador y los md5 de cuatro cuerpos:

| Archivo | SHA-256 |
|---|---|
| `supabase/migrations/20260930170000_capture_complete_workshop_backups.sql` | `8a6097edb3085369bf03095210c9c380a9e829f91c787503ebb9f56d0f16cb00` |
| `supabase/migrations/20260930171000_restore_workshop_effect_packets.sql` | `a7e2f3f8da046a0db27711c75bc7161f8f84025f67e09df9a07960f8fae2bfb2` |
| `supabase/migrations/20260930172000_restore_workshop_graph_engine.sql` | `b81bc8790a1ec93c13af1a8e4e9a94778abe976b39c485b4f0e1fad00ea46aca` |
| `supabase/manual_checks/verification/20260930170000_…sql` | `b4f2402c03bdd3dba059cd7b26f138d64e761b76d34e435c74f2cb303cfddaf3` |
| `supabase/manual_checks/verification/20260930171000_…sql` | `70a411358201a537c16261ffaab0ff03f02e0bda6856f371ec9ce6c5b4e1bd3b` |
| `supabase/manual_checks/verification/20260930172000_…sql` | `f2db48eccec3725ca8b3345adb30865b094dc4d710e0ba397aac5279bb6a1a2f` |
| `supabase/tests/restore_workshop_graph.sql` | `65754a725c3331c138406d30cb893ba17c503817a3057b5137c20b2da5d62a1f` |
| `supabase/tests/restore_backup_merge.sql` | `1f7b49228eb3242a83abb562785cfbf5461aa3f964986b0431f70a83bee692ab` |

Cliente: `lib/shared/models/backup.dart`,
`lib/modules/settings/widgets/backup_restore_dialogs.dart`,
`lib/modules/settings/pages/backup_management_page.dart`,
`test/widgets/backup_restore_dialogs_test.dart`. Recorrido:
`e2e/backup_local.spec.ts`, `scripts/e2e/backup_journey_local_fixture.sql`,
`scripts/e2e/run_android_local_journey.sh` (`--journey backup`, sólo web).
Los verificadores fijan el md5 de cada cuerpo instalado (22 funciones); por
ejemplo `restore_backup_merge` `279f3ff230ac1a9adbbd5e30d5a7e17f`,
`restore_backup_merge_preflight` `021523db73704f7a91b977a0c05bacaa`,
`workshop_restore_table_internal` `4356249bae700b6ea10ac830570b7d83`,
`capture_workshop_backup_internal` `8ef8245d928f7d5fe9311eec484c1449`.

**Resultado local:**

- pgTAP `restore_workshop_graph` 24/24 + `restore_backup_merge` 10/10,
  `.tmp/db/pgtap-20260930-130018.log`; preflight 272 ms, recuperación 259 ms
  con 1.000 contactos y 300 líneas posteriores.
- Tres verificadores `verification_passed=1`.
- Dos conexiones con el motor nuevo: `restore_backup_merge_race_probe.sh`,
  fila del respaldo y escritor de clientes retenidos → `restore_merge_busy`,
  sin datos ni informe; fixture retirada.
- Flutter `backup_restore_dialogs_test` + contrato 24/24, analyzer sin issues
  en los archivos tocados.
- App completa (`lib/main.dart`, Auth/REST locales, Chrome):
  `.tmp/e2e/web-backup-20260930-125358.log`, 1/1. Operadora admin; grafo
  creado por una mecánica; respaldo real; después cambia el teléfono, se borra
  una línea de un trabajo vivo y nace otro trabajo; pérdida. Revisión →
  Restaurar → resultado → a 390 px «No falta nada» sin Restaurar → la ficha del
  trabajo abre con Camila Rojas, Trek Marlin 7, sus dos líneas ($57.990) y la
  solicitud. Readback `c2_readback=1`: 18/18 filas en 15 tablas idénticas al
  respaldo, autora la mecánica, teléfono de hoy, la línea borrada del trabajo
  vivo no vuelve, trabajo posterior intacto, 0 avisos nuevos, 0 paquetes
  abiertos; `grafo_identico=1`; `retirada_completa=1`. Frames claro/oscuro y
  hoja `.tmp/e2e/web-backup-20260930-125358/hoja-de-contacto.png`.
- Producción, sólo lectura (`.tmp/db/c2/prod_trigger_readiness.sql`): los 41
  disparadores revisados existen, habilitados y sin WHEN; los 11 validadores
  tienen el md5 revisado; ningún INSERT trigger ni regla sin revisar en las 38
  tablas; objetos nuevos ausentes. `171000` aplicaría tal cual.

**Deploy propuesto tras la revisión:** los tres forwards en orden
(`170000`, `171000`, `172000`) por `scripts/db/deploy_migration.sh` con su
`--verify`. `172000` reemplaza con `create or replace` los cuerpos públicos de
`20260930092309`; ese archivo APPLIED no se edita. **Corrección de Codex:**
el preflight corre el motor y lo deshace en una subtransacción, así que es
una sonda mutante y no se mide en producción bajo el contrato DB; su
rendimiento queda acreditado por la evidencia local (272/259 ms con volumen)
y el cliente conserva la negativa por tiempo y el reintento.

**Defectos y pendientes concretos:**

1. Web: un `AlertDialog` cuya única acción es un `VbButton` no publica ese
   nodo («Entendido» del resultado, «Cerrar» de la revisión sin cambios); el
   árbol del framework sí lo tiene y el diálogo de dos acciones expone ambas.
   Salidas accesibles: barrera «Cerrar» y Escape. Causa sin aislar; trampa en
   `docs/development/WEB_PREVIEW.md`.
2. El costo con el respaldo real de diciembre no se mide en producción:
   el preflight es una sonda mutante (corrección de Codex). Queda la
   evidencia local y la negativa por tiempo con reintento.
3. `supabase/tests/restore_backup_merge.sql` se reescribió al contrato nuevo:
   el 32/32 del motor `092309` hacía UPDATE de filas vivas, que la regla nueva
   prohíbe. Su texto previo está en
   `.tmp/db/c2/restore_backup_merge.before-c2.sql` para la revisión.
4. Fallas pgTAP ajenas a C2, iguales con la captura anterior:
   `auth_tenant_provisioning_hardening` 115/116/127/361,
   `supplier_relationship_foundation` 28/38, `notification_counter_lifecycle`,
   `financial_projection_realtime`, `restore_backup_missing_images` 27–29 y
   `restore_backup_replay_reposts_invoice` 6.
5. El recorrido es web (escritorio y 390 px), no teléfono nativo.

### Ajuste C2 tras la revisión de Codex (2026-09-30, fuentes sin instalar)

Codex tiene la DB local y los servicios; Claude no ejecutó wrappers ni SQL.
Codex instala y corre los gates en serie. Archivos de este ajuste, en
exclusiva de Claude hasta la devolución: `20260930171000` (sin cambios),
`20260930172000`, su verificador y `supabase/tests/restore_workshop_task_graph.sql`.

**Hallazgo:** el WHEN suprimía enteras cuatro guardas de tareas que mezclan
relaciones con reescrituras de tiempos, autores y snapshots. El motor sólo
juzgaba cada FK y el taller por separado: podía aceptar dos contextos
principales, un servicio con `task.linked_job_id`, `item.job_id` y
`link.job_id` distintos, o una nota sin su vínculo.

**Corrección:** `workshop_restore_task_graph_internal`, llamada por
`workshop_restore_table_internal` para `smart_tasks`, `smart_task_job_items` y
`smart_task_job_item_notes`, después de padres y vínculos blandos y antes de
escribir. Juzga la fila tal como se guardaría y contra lo que existe ahora,
incluido lo restaurado antes en la misma invocación:

| Relación | Resultado |
|---|---|
| Más de un contexto principal | niega todo: `task_primary_context` |
| Nota en curso/terminada/bloqueada | niega todo: `task_note_lifecycle` |
| Privada con responsable o trabajo | niega todo: `task_private_personal` |
| Nota con servicios | niega todo: `task_note_has_services` |
| Servicio con línea de otro trabajo, o activo con trabajo distinto al de la tarea | niega todo: `task_link_job_mismatch` |
| Servicio activo cuya línea ya no existe | no vuelve; `parent_missing` (líneas) |
| Nota cuyo servicio no vuelve | no vuelve; `parent_missing` (servicios) |
| Servicio invalidado sin su línea | vuelve tal cual, sin crear ni reasignar la línea |
| Responsable ya no elegible, trabajo archivado | historia: vuelve como estaba |

El servicio activo sin línea no se niega: es lo que pasa cuando un mecánico
borra la línea después del respaldo (lo de hoy manda), igual que una FK
obligatoria ausente. Negar todo por eso dejaría sin recuperación cualquier
tarea perdida. Las contradicciones del respaldo, en cambio, sí niegan todo.
`restore_backup_merge` vuelve a decidir `can_manage_tenant_backups` después
de tomar los candados y antes del escritor.

**Fuentes (SHA-256):**

| Archivo | SHA-256 |
|---|---|
| `supabase/migrations/20260930171000_restore_workshop_effect_packets.sql` (sin cambios) | `a7e2f3f8da046a0db27711c75bc7161f8f84025f67e09df9a07960f8fae2bfb2` |
| `supabase/migrations/20260930172000_restore_workshop_graph_engine.sql` | `71dc6efce49b87a4d9b0526a8b87e6e50a8b494c27136bc47df2ad281bb67356` |
| `supabase/manual_checks/verification/20260930172000_restore_workshop_graph_engine.sql` | `21e0caa952b54ae78e2372a3f1d7ad232ac56aaa75f03a174984e5f77157c86e` |
| `supabase/tests/restore_workshop_task_graph.sql` | `5cdec0e103a396f7ad54962ad85c7e846d714786908477bc80fa66826516643e` |

md5 de cuerpo que fija el verificador, calculado del archivo (el mismo cálculo
reproduce los md5 instalados de las funciones sin cambios):
`workshop_restore_task_graph_internal` `337f6ea060db761d11e3749eaaa06430`,
`workshop_restore_table_internal` `7a8e516f874ab44795e24d46acf4605f`,
`workshop_restore_record_label` `a8c260d301fd4adf0c95024117887bc4` (nombra el
servicio retenido), `restore_backup_merge` `44729ec7df7cf9e9c61dd04291f0635c`.
El verificador suma `authority_rechecked_after_locks` y
`task_relations_reverified`.

**Orden sugerido para Codex:** reinstalar `172000` en local (sólo cuerpos
`create or replace`; `171000` y `170000` no cambian), su verificador `=1` y
`scripts/db/test.sh restore_workshop_task_graph`. `restore_workshop_graph` y
`restore_backup_merge` no cambian de expectativa: la tarea del grafo tiene un
solo contexto y su servicio está en la línea de su trabajo.
