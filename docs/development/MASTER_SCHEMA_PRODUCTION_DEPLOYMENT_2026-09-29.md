# Despliegue de la base del taller — 2026-09-29

La historia remota de Supabase y el readback del wrapper `scripts/db/deploy_migration.sh` confirman que estas 16 migraciones quedaron `APPLIED` en producción el 2026-09-29. Cada una se ejecutó de forma individual con su archivo de verificación SQL. Los recibos con SHA-256 están en `.tmp/db/migration-receipts/` (ignorados por Git).

| Versión | Cambio |
| --- | --- |
| `20260928052000` | Conflictos de ficha `PT409`, sin bucle de reintentos por `40001` |
| `20260928050000` | Bucket `bike-images` y políticas de escritura por taller |
| `20260928051000` | Intentos de comandos del taller |
| `20260928060000` | Hechos instalados al cerrar un trabajo |
| `20260928070000` | Aplicación al editar líneas de un trabajo terminado |
| `20260928080000` | Guardado transaccional de líneas, cabecera, bicicletas y factura |
| `20260928090000` | Bucket `job-images` y políticas de escritura por taller |
| `20260928100000` | Cambio de rotor y relación producto–bici |
| `20260928110000` | BSD del neumático |
| `20260928120000` | Cassette y piñón roscado |
| `20260928130000` | Maza |
| `20260928140000` | Llanta y puerta diferida de compatibilidad |
| `20260929010000` | Alta de trabajo con llave y recibo |
| `20260929020000` | Validación de URL nuevas de adjuntos administrados |
| `20260929030000` | Restauración: omitir URL administradas inválidas, informe y negativa antes de perder datos no respaldados |
| `20260929040000` | Tareas explícitas: retirar parser de descripciones y exigir que tarea, trabajo, línea y bici sean del mismo taller |

La primera aplicación de `20260928140000` confirmó el SQL pero **no** se registró: el readback interpretaba JSON `null` como valor presente al usar `->'value'`, y esperaba 44 BSD frente a 9 realmente documentados. Se corrigió sólo el readback a `->>'value'`, se ejecutaron sus tres aserciones con éxito y el wrapper reejecutó idempotentemente la migración y registró el sello `APPLIED`. No se editó el archivo de migración aplicado.

Readback final de esas 16: 19 relaciones en `bike_fact_spec_links`; ninguna fila nueva en `mechanic_job_line_saves`, `mechanic_job_creations`, `workshop_command_attempts` ni `mechanic_job_line_gate_deferrals` al corte inicial. Para `030000` pasaron 5 aserciones de estructura, alcance y permisos; para `040000`, 3 aserciones de parser retirado y guardias activas. La lectura posterior confirmó 1 respaldo completado sin informe de restauración, 370 tareas heredadas conservadas, 0 tareas cruzadas entre talleres y las dos versiones `APPLIED`. `just db-health production` pasó después de ambas con **0 controles críticos fallidos**; conserva una advertencia de 19 casos históricos de stock negativo. `just db-smoke production` había fallado en `products_with_sets_final_shape`: `products` tenía 101 columnas y la vista 71. Las 16 migraciones del taller no alteraron esa vista.

Esto desplegó la base, **no** publicó el cliente Flutter ni cerró el Master Schema. La restauración aún no es una recuperación completa: con los datos actuales se niega en los 10 talleres para preservar tablas dependientes que el respaldo no cubre. Las lecturas públicas de `bike-images` y `job-images` son deliberadas para los enlaces actuales, y la exposición anterior de documentos en `vinabike-assets` sigue pendiente del plan `VINABIKE_ASSETS_SECURITY_PLAN_2026-09-29.md`.

El canario REST de conflicto 409 no se ejecutó: sería una prueba mutante en producción y requiere la guardia específica de `docs/runbooks/STAGING_SUPABASE.md`. La definición y permisos de las dos funciones sí pasaron readback en vivo, y no había esperas de locks en el control posterior.

## Salud de la vista de productos — corte independiente

El diagnóstico leyó 34 columnas de `products` ausentes en
`products_with_sets` (entre ellas `spec_revision`, `spec_reference_id` y
`spec_template_id`). `p.*` se fija al crear la vista; los `ALTER TABLE`
posteriores no la amplían. La historia confirmó que
`20260712210000_stabilize_products_with_sets_view.sql` ya estaba `APPLIED`,
así que no se reejecutó. El catálogo no mostró objetos dependientes de la
vista, y sus permisos efectivos eran sólo `authenticated`, `service_role` y
`codex_test_runner`, con `security_invoker=true`.

La migración independiente `20260929050000_refresh_products_with_sets_columns.sql`
recreó la vista sin `CASCADE`, conservó las cuatro columnas calculadas y los
permisos anteriores, y no cambió filas de `products`. Pasó la verificación
local (94 columnas de producto + 4), el pgTAP de la vista (8/8) y el lector
de inventario del asistente (89/89). El despliegue
guardado, su readback y el sello remoto `APPLIED` pasaron en producción:
101 columnas de producto + 4 calculadas, nombres y tipos iguales, sin `SELECT`
para `anon` y con `security_invoker=true`. El fingerprint de negocio fue
idéntico antes y después: 1681 productos, 1243 unidades de stock sumadas y
6 sets. `just db-smoke production` pasó los seis controles; `just db-health
production` mantuvo 0 críticos y la advertencia histórica de 19 casos de
stock negativo. Esto cierra la deriva de la vista, no el cliente Flutter ni
los otros criterios del Master Schema.

## Cierre atómico del trabajo — corte posterior

La migración `20260929060000_guard_job_completion_bike_facts.sql` quedó
`APPLIED` en producción a las 19:57 UTC. Antes del despliegue, su readback
falló con división por cero como debía (`semantic_guard=f`,
`transient_retry=f`); después pasó la aserción ejecutable
`guarded_atomic_completion=1`, los permisos (`authenticated` sí, `anon` no),
`SECURITY DEFINER`, el `search_path` y el `lock_timeout`. La historia remota y
el recibo SHA-256 `20260929060000.receipt` confirmaron el sello. Se conservó
la función anterior salvo el guard de cierre, y se probó localmente rollback,
corrección y reintento con la misma llave en las suites de hechos instalados y
piezas.

El guard revierte FINALIZADO/ENTREGADO, hechos parciales, eventos y recibo si
una línea marcada es incompatible o carece de destino inequívoco. Los fallos
transitorios del parche se exponen como `55P03` para conservar la llave del
outbox. La lectura en producción encontró 1519 líneas vivas, ninguna con
`part_change` u `hole_count`, y 516 trabajos vivos (462 terminados o
entregados); no se hizo un canario mutante en producción. `just db-health
production` dio 0 críticos y la advertencia histórica de 19 casos de stock
negativo. El cliente Flutter que explica y corrige el bloqueo aún no está
publicado, por lo que este corte no cierra la arquitectura.

## Adjuntos privados de tareas — corte aditivo

`20260929070000_private_task_attachments.sql` quedó `APPLIED` en producción
el 2026-09-29. La historia remota decía `NOT_APPLIED`, el bucket no existía y
el readback falló antes con división por cero; tras el wrapper pasó
`private_task_attachment_contract=1`, se leyó el sello `APPLIED` y quedó el
recibo SHA-256. La prueba focal local pasó 24/24. El cambio crea un bucket
privado por tarea, una fila por archivo y comandos de alta/baja con recibo;
no modifica los arreglos JSONB ni mueve bytes existentes. En producción había
0 adjuntos de tareas al corte previo. El cliente Flutter correspondiente está
solamente en el checkout local; una subida, URL firmada y borrado físico en la
app real siguen sin comprobarse. Tampoco mueve los PDF y archivos de trabajos
del bucket público heredado.

`20260929080000_ack_private_task_attachment_cleanup.sql` quedó `APPLIED` el
2026-09-29 con readback `private_task_attachment_cleanup_contract=1` y recibo
SHA-256. Antes, la historia indicaba `NOT_APPLIED` y el readback falló como
esperado; el preflight contó 0 vínculos y 0 objetos en el bucket privado.
Añade una cola acotada de tombstones visibles sólo para escritores de sus
tareas y un acuse idempotente que exige la ausencia del objeto en Storage.
El pgTAP focal pasó 32/32 en local. `just db-health production` mantuvo 0
fallos críticos y 19 advertencias históricas de stock. El cliente que retoma
el retiro al iniciar y pide ese acuse sigue local; no hubo borrado físico ni
prueba real de archivo en producción, y el cliente no está publicado.

`20260929090000_private_task_orphan_storage_cleanup.sql` quedó `APPLIED` el
2026-09-29. `080000` estaba aplicado y `090000` no; el readback previo de
`090000` falló como se esperaba. La migración sólo reemplazó la política
SELECT del bucket privado: el uploader puede leer su propio objeto sin
vínculo mientras todavía puede escribir la tarea, de modo que Storage acepte
retirarlo tras un error SQL definitivo. Los demás usuarios no reciben ese
acceso. El pgTAP focal pasó 35/35 local; readback remoto
`private_task_orphan_cleanup_contract=1`, 0 objetos privados, historia remota
`APPLIED` y recibo SHA-256
`1d6d95a1257b9b81c0cfe44a2a0b7c052ddb60c4a76d6cb03c7944d985dbda12`.
No se borró ningún archivo productivo. El cliente que hace la limpieza sigue
local y falta probar una subida interrumpida con Storage real.

`20260929100000_scope_task_attachment_cleanup_queue.sql` quedó `APPLIED` el
2026-09-29. El readback anterior falló como se esperaba; después del wrapper
dio `scoped_task_attachment_cleanup_contract=1` y 0 vínculos pendientes,
historia remota `APPLIED` y recibo SHA-256
`f22056866447af9ec911c4e59e3a6654f40125bf0b14969563aa31c4c78d8a63`.
La nueva RPC recibe el taller, filtra antes de limitar a 25 y conserva la
comprobación de permiso por archivo. No revocó v1 ni cambió filas u objetos.
PgTAP local 45/45 y transporte HTTP simulado 7/7; no hubo prueba con Storage
real ni publicación del cliente. La lectura adicional de producción mostró
0 usuarios con dos perfiles ERP activos y 0 solapamientos ERP/portal activos;
el índice único y las guardias estaban habilitados. El riesgo de una página
con archivos de otro taller era latente, no una pérdida observada.

`20260929110000_task_attachment_recovery_status.sql` quedó `APPLIED` el
2026-09-30. La historia previa contenía `100000` y no `110000`; su readback
falló como se esperaba con división por cero. Después del wrapper, el
readback dio `task_attachment_recovery_status_contract=1` con 0 vínculos,
historia remota `APPLIED` y recibo SHA-256
`9412d1a3163d55c0bde2143b251297cf90ad2a04d127b28da483097e2b29f44f`.
El pgTAP focal pasó 53/53 local: autoriza al uploader escritor de la tarea,
distingue activo, tombstone y ausencia; observador, otro taller e identidad de
otro uploader fallan cerrados. No escribió filas ni borró objetos productivos.
La RPC sólo informa el estado del vínculo. Una respuesta `absent` no prueba
que otra sesión haya terminado de subir o vincular el objeto y no habilita
DELETE automático. El cliente Flutter la llama sólo en este checkout: un
intento `removed` pasa a la cola durable, `absent` se conserva y el transporte
simulado pasó 8/8 sin DELETE. No está publicado; falta resolver la exclusión
de subida concurrente y probar Storage
real antes de cerrar la limpieza de huérfanos.

## Restauración: negativa temprana por facturas — corte posterior

`20260929120000_restore_posted_invoice_preflight.sql` quedó `APPLIED` en
producción el 2026-09-30, con recibo SHA-256
`54012be660a5dada40dd6aa9be9922c9e5366712d25a83dabb7ad3c9a8a2fd9d`.
Antes, la historia remota indicaba que faltaba y el readback falló como se
esperaba. Después del wrapper, el readback dio
`invoice_delete_blocker_contract=1` y
`restore_entrypoints_reject_before_motor=1`; la historia confirmó `APPLIED`.
La definición de las funciones de restore y el guard de borrado coincidían
entre local y producción antes del despliegue.

El preflight y `restore_backup` rechazan antes del motor una factura de venta
o compra que no sea borrador o tenga un pago activo, con
`restore_invoice_delete_blocked` y un motivo legible. La función interna que
busca el bloqueo es privada. El pgTAP transaccional
`restore_backup_replay_reposts_invoice.sql` pasó 12/12 local: negativa temprana
de venta contabilizada, compra cancelada y control en borrador. También
conserva la demostración de que habilitar sólo la purga para alcanzar el
replay choca con las cuentas/asientos reconstruidos y revierte; por eso no se
habilitó. No se restauró un respaldo ni se mutaron filas de negocio en
producción. La lectura agregada de ventas contabilizadas siguió en 905 antes
y después. `just db-health production` dio 0 críticos y 19 advertencias
históricas de stock.

Esta guardia cierra el falso positivo del preflight frente al validador de
facturas. **No hace segura ni completa la restauración**: la negativa por
tablas dependientes fuera del respaldo sigue vigente en los 10 talleres, y el
motor heredado aún necesita replay por diferencia y aislamiento de efectos
sin desactivar validadores de integridad. El cliente Flutter tampoco está
publicado.

## Restauración: columnas incompatibles con el replay legado — 2026-09-30

`20260930010000_restore_legacy_column_preflight.sql` quedó `APPLIED` por
`deploy_migration.sh`, readback y sello. Antes del despliegue la historia
indicaba `NOT_APPLIED` y el readback falló como se esperaba; después devolvió
`restore_legacy_column_guard_contract=1`. El recibo local conserva SHA-256 de
la migración
`f1bf6cc2ee96069312428c4bb9f6113cb6bf1f44959bc06e095d36e6023f8e00`
y del readback
`8215c083928c3fcd16d3482c7eea19a354e6411255216ed582adb56d1a2c4ff8`.
La función interna no concede `EXECUTE` a `anon`, `authenticated` ni
`service_role`; ambas entradas públicas de restore la consultan antes del
motor. No se cambió el motor ni se ejecutó una restauración.

La guardia detecta filas del respaldo sin columna `NOT NULL` o con `DEFAULT`,
un `NULL` explícito inválido, claves que el esquema ya no conoce y una
identidad `GENERATED ALWAYS` que el `INSERT` implícito no puede reponer. Una
sonda transaccional local obtuvo SQLSTATE `428C9` para esa identidad; el
pgTAP focal pasó 11/11. El cliente Flutter local muestra el motivo del
preflight, oculta Restaurar y conserva Descargar JSON (widget focal 1/1);
también reconoce el mismo código si el estado cambia entre consulta y
comando. Aún no está publicado ni se vio esta causa específica en la app.

Una lectura agregada tras el despliegue confirmó un sello `APPLIED`, 1
respaldo completado y 905 ventas contabilizadas, iguales a los conteos
previos; el único respaldo completado también activa este nuevo guard, pero
su primera negativa visible sigue siendo la de tablas ausentes. `just
db-health production` volvió a dar 0 críticos y 19 advertencias históricas
de stock. El cambio no escribió filas de negocio. La restauración completa
sigue bloqueada por dependencias fuera del respaldo, efectos de disparadores
y la necesidad de un replay por diferencia con columnas explícitas.

## Purga de facturas: autorización privada integrada — 2026-09-30

`20260930020000_guard_posted_invoice_delete_authorization.sql` quedó
`APPLIED` a 09:02 UTC mediante el wrapper apply/readback/stamp. Se instaló
antes una vez en la base local y `posted_invoice_purge_authorization` pasó
**32/32** con rollback (`.tmp/db/pgtap-20260930-020023.log`), comprobando el
archivo instalado; el resultado anterior 38/38 era del candidato.

El guard conserva el rechazo a facturas contabilizadas y con pagos. Su
salida de mantención ahora consume una autorización privada de una fila,
taller y transacción, abierta sólo por backend/owner. Ni la variable pública
ni claims inventados autorizan el borrado. Borradores y cancelación conservan
su comportamiento. El readback exacto verificó los tres cuerpos, dueños,
search_path, ACL, tabla privada y ambos triggers; no se probaron mutaciones
productivas ni se ejecutó restore.

Recibo `.tmp/db/migration-receipts/20260930020000.receipt`: forward SHA-256
`b5717dc2a854e305208ea34bbca6c361b16faa133764ee26f3033ab519712204`,
readback SHA-256
`46a1c9815d57a0867cbb242b134bb3c33eebbf446eb5cc420309f42ab62daf35`.
La historia pasó de `20260930010000` a `20260930020000`. Antes y después:
940 ventas, 87 compras, 2675 asientos y 905 ventas/83 compras protegidas;
cero autorizaciones de purga. Health conservó 0 críticos y 19 alertas
históricas. La recuperación completa y la publicación del cliente siguen
abiertas.

## Recuperación por diferencias — alcance inicial del 2026-09-30

`20260930092309_restore_backup_merge_engine.sql` quedó `APPLIED` a
13:13:30 UTC. Gate local del RPC instalado **32/32** en
`.tmp/db/pgtap-20260930-060836.log`: recreación y actualización por columnas
presentes, defaults seguros, 1.000 contactos posteriores preservados, identidad
portal vigente, aislamiento financiero y negativas/rollback de integridad,
triggers WHEN y rules desconocidos. Dos conexiones reales ya habían comprobado
espera acotada de fila de respaldo y de clientes sin escribir; no se repitieron.

El readback exacto local pasó. En producción falló antes del deploy con división
por cero; el wrapper instaló, verificó trece cuerpos/dueños/ACL/search_path,
hashes de los dos triggers revisados y timeout, y leyó el sello remoto. Recibo:
`.tmp/db/migration-receipts/20260930092309.receipt`.
Migración SHA-256 `b8954ba099d084a12757602bc4e69d70beb211a0b4d0f338382815bfcdc41fa2`;
verificación SHA-256 `989efd0c334a1ddca38051eded408ea003e156a5e5d5e97149040d3ead4ce5fa`.
Ambos archivos quedan inmutables. Antes/después: 940 ventas, 87 compras,
2675 asientos, un respaldo completado. No hubo restore productivo de prueba.

El cliente del checkout selecciona `restore_backup_merge_preflight` y
`restore_backup_merge` después del deploy. Conserva filas nuevas, campos omitidos
y vínculos vivos; presenta el mensaje del servidor incluido cero cambios.
UI/modelos/contrato focal 18/18 y analyzer limpio. Los informes legados conservan
sus omisiones; no se los interpreta como merge.

**Límite:** escritura revisada sólo en clientes, marcas y modelos de bicicleta.
Otros cambios se rechazan antes de escribir; el merge no prueba recuperación
completa del taller. C2 y consumidor real siguen abiertos, y Flutter no publicado.

## Fuente del cierre de trabajos reconstruible — 2026-09-30

`20260930152000_capture_workshop_job_lifecycle.sql` quedó APPLIED a
15:34:04 UTC. Captura exactamente el cuerpo que ya existía en producción y
el seed ejercido por el recorrido local; no modifica su comportamiento.
Readback de definición normalizada (md5 `fbf44c605a0925f4186f7ebe0a9369c2`),
dueño, SECURITY DEFINER, search_path, ACL y dos triggers activos. El readback
previo ya daba 1 porque el cuerpo efectivo precedía a su fuente versionada.

Recibo `.tmp/db/migration-receipts/20260930152000.receipt`: forward SHA-256
`385f57c1c47e2f4b73d5fbc321a38e115387d8f444caad215a85c60151babb30`;
verificación SHA-256
`5715c704001607dc4ac69975b5ed56d8fc19eb59e2919b2d7b20e01fc9a323c9`.
Ambos archivos son inmutables. No se ejecutaron comandos de negocio ni restore
en producción. Lectura posterior: 940 ventas, 87 compras, 2677 asientos; el
entorno sigue recibiendo operaciones concurrentes, por lo que no se presenta
este conteo como comparación de filas congeladas. C5 completo sigue abierto.
