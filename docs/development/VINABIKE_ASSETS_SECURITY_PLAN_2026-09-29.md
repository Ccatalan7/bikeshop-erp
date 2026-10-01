# Separar archivos privados de `vinabike-assets`

## Hecho verificado (2026-09-29)

En producción, `storage.buckets.public = true` para `vinabike-assets`. Las
cuatro políticas existentes de `storage.objects` (SELECT, INSERT, UPDATE y
DELETE) comprueban solamente el bucket para usuarios autenticados. Un bucket
público sirve un objeto a quien conozca su URL sin consultar la política SELECT
([contrato de Supabase](https://supabase.com/docs/guides/storage/buckets/fundamentals)).

Lectura agregada de `storage.objects`, sin descargar ni abrir archivos:

| Carpeta inicial | Archivos | Observación |
|---|---:|---|
| UUID de catálogo heredado | 2280 | Imágenes de productos |
| `inventory` | 521 | Imágenes |
| `product-images` | 216 | Imágenes |
| `suppliers` | 71 | 70 imágenes y 1 PDF |
| `website`, `website-images` | 84 | Activos del sitio |
| `company_logos`, `brand-logos`, `payment-icons`, `shared` | 44 | Activos visuales |
| `presupuestos` | 8 | PDF |
| `mechanic_jobs` | 8 | 8 imágenes según MIME: 4 `.jpeg`, 2 `.jpg`, 2 `.heic` |

La presencia de PDF y archivos de trabajo en este bucket es un riesgo de
exposición por URL. Esta lectura no demuestra que alguien externo los haya
consultado, ni determina su contenido. `TaskService.addAttachment` también
escribe futuros adjuntos de tareas bajo `tasks/attachments/<tenant>/<task>` en
este bucket y guarda una URL pública; la carpeta todavía no tiene objetos en
el conteo anterior.

**Inventario agregado de referencias, 2026-09-30:** la consulta de sólo
lectura `supabase/manual_checks/verification/legacy_public_asset_reference_counts.sql`
en producción encontró los mismos 8 objetos bajo `mechanic_jobs/` y 8 bajo
`presupuestos/`. Seis rutas de objetos de trabajos aparecen literalmente en
`mechanic_jobs.image_urls`; dos objetos de trabajos y los ocho PDF no tuvieron
coincidencia literal en los campos candidatos examinados. El catálogo de
columnas que guió esa selección quedó en
`supabase/manual_checks/verification/legacy_public_asset_reference_catalog.sql`.
La consulta no devuelve nombres, URLs, filas ni bytes. **Sin coincidencia no
significa huérfano:** puede existir una referencia codificada, una tabla aún
no examinada o uso fuera de la base. Antes de mover o retirar un objeto hay
que resolver cada referencia y su dueño, además de verificar los bytes y la
lectura privada. No se escribió ni descargó dato productivo.

**Corrección del inventario y alcance del dueño, 2026-09-30:** los dos objetos
antes contados como «otro tipo» son imágenes HEIC según la extensión y el MIME
de Storage; el conteo anterior sólo reconocía los formatos de imagen más
habituales. Ambos son los dos sin coincidencia literal en los campos
examinados. La lectura agregada de metadatos y cruces de IDs
(`legacy_public_asset_owner_shape.sql`, `legacy_public_asset_owner_join_counts.sql`
y `legacy_public_job_image_ownership.sql` en la misma carpeta) encontró que
las ocho rutas de `mechanic_jobs/` llevan en el segundo segmento un ID de
cliente existente, no un ID de trabajo ni de taller. Las seis imágenes con
referencia literal pertenecen a trabajos cuyo cliente y taller coinciden con
esa fila de cliente; esto identifica un camino de migración para esas seis,
sin probar todavía la lectura privada ni el contenido de los archivos. Las
ocho rutas de `presupuestos/` no llevan UUID, por lo que la ruta sola no
atribuye el PDF a un taller. Storage registra un uploader para cada objeto,
pero ese usuario tampoco establece por sí solo el taller o la referencia de
negocio. Quedan sin atribución de uso los dos HEIC y los ocho PDF. Ninguna
consulta devolvió IDs, nombres, URLs, filas ni bytes; no se movió un objeto.

**Origen probable de los PDF, 2026-09-30:** el historial del cliente en
`5ee031bc` muestra que el chat subía un presupuesto generado desde una factura
de venta a `presupuestos/presupuesto_<invoice_number>_<epoch_ms>.pdf` y pasaba
su URL pública al envío por WhatsApp; `f24a5f30` retiró esa subida. Los ocho
objetos actuales cumplen exactamente esa forma de ruta, según la consulta
agregada `legacy_public_budget_pdf_invoice_join.sql`. Ninguno de los ocho
números extraídos coincide hoy con `sales_invoices.invoice_number`; esto puede
deberse a renumeración, eliminación u otro cambio, y **no demuestra** que el
PDF no se haya entregado ni que no tenga dueño. El catálogo de producción no
tiene tablas cuyo nombre incluya budget/quote/presupuesto/estimate; esa
ausencia tampoco descarta un recibo en mensajería o el proveedor externo.
Antes de cambiar URL o borrar bytes hay que reconstruir la referencia de
entrega y la identidad autorizada por otro recibo, sin inferirla del uploader.
No se consultó el contenido de los PDF ni se devolvieron rutas o números.

**Recibos examinados, 2026-09-30:** el envío actual filtra campos de URL como
`documentUrl` de la metadata de `messages`, y la migración de adjuntos también
retira URLs públicas de esa metadata. Por eso la ausencia de URL actual no
descarta entrega histórica. Las consultas agregadas
`legacy_public_budget_pdf_messaging_receipts.sql`,
`legacy_public_budget_pdf_filename_receipts.sql` y
`legacy_public_budget_pdf_quarantine_receipts.sql` buscaron las ocho rutas o
sus nombres de presentación en `messages.metadata`, `messages.content`,
`whatsapp_outbox.request`, `messaging_attachments.original_filename` y los
recibos de cuarentena por el hash de ruta que usa el migrador. Resultado:
**0 de 8** con coincidencia en esos campos, **0 de 8** con recibo de
cuarentena/copia privada correspondiente. Son límites de estas fuentes,
no prueba de que WhatsApp no enviara el PDF ni de que otra copia privada no
exista. La atribución requiere otro recibo verificable, histórico o del
proveedor, antes de tocar el objeto público; no se hizo escritura ni descarga.

**Corte de tareas, lectura de producción del 2026-09-29:** `smart_tasks` tiene
0 tareas con `attachments` no vacío y 0 entradas de adjunto. La ruta futura
puede corregirse antes de migrar datos de tareas. `vinabike-files` ya es un
bucket privado, pero sus políticas autorizan por `<tenant>`: una tarea
`private` exige además `smart_task_can_view_v1(task_id)`. Añadir otra política
permisiva a ese mismo bucket no restringiría la política existente. La ruta
de tareas requiere un bucket privado dedicado con políticas por tarea (o una
revisión segura de todas las políticas del bucket compartido). El objeto
debe vivir bajo `<tenant>/<task>/<id>/<nombre>`, con vínculo estable por
bucket/ruta (o id de `app_files`) y URL temporal sólo al mostrar o descargar.
La ruta actual `tasks/attachments/<tenant>/<task>` tampoco cumple el contrato
de primer segmento del bucket compartido. Hay que adaptar la miniatura de
`PegasTasksWidget._buildAttachmentCell` y el borrado de `TaskService` y
`TaskFormDialog`: hoy ambos identifican el adjunto por su URL pública.

`TaskService.addAttachment` lee el arreglo JSONB completo y luego lo reemplaza
sin versión en `smart_tasks`. Dos altas simultáneas pueden sobrescribirse;
`removeAttachment` tiene la misma carrera. La corrección privada debe escribir
el vínculo con un comando atómico/versionado y comprobar el recibo antes de
retirar un objeto. No basta con cambiar el nombre del bucket ni con guardar
una URL firmada que vencerá. Este riesgo se infiere de la secuencia de código;
no se hizo una prueba de dos sesiones ni se afirma pérdida observada.

**Corte local previo, superado por `070000` y su cliente local:** el nombre de objeto ya incluye un
UUID y la subida no hace `upsert`, porque antes dos archivos de igual nombre
podían reemplazar los bytes del primero. El formulario conserva el ID de una
tarea creada y los adjuntos aún pendientes cuando una subida falla, para que
reintentar no cree otra tarea. En ese corte la escritura de vínculos seguía en
JSONB y la ruta era pública; el siguiente corte privado se describe abajo.

**Base privada desplegada y leída en producción (2026-09-29):**
`20260929070000_private_task_attachments.sql` crea `task-attachments` privado,
vínculos normalizados por UUID, RLS por visibilidad de la tarea y RPC de alta y
baja con recibo. Su pgTAP focal pasó 24/24: otro taller no ve bytes ni vínculos,
un observador del mismo taller no puede subir, dos archivos no se pisan, la
misma llave no duplica y un archivo activo no se borra directamente. Un archivo
sin vínculo no se lee por otros usuarios, y el tombstone sólo deja SELECT temporal al escritor
que debe retirar los bytes: Storage requiere SELECT además de DELETE para
limpiar. El readback remoto pasó tras un fallo previo esperado y el stamp
`APPLIED` quedó registrado. **El cliente Flutter editado está sólo en este
checkout; no se ha publicado. La subida, lectura temporal, reintento y retiro
físico en la app web real local quedaron comprobados el 2026-09-30 en el
checkpoint siguiente. Teléfono nativo y archivos heredados siguen abiertos.** En el corte `070000`, la columna
`storage_deleted_at` todavía no recibía acuse; el corte siguiente lo agrega.

**Cierre aditivo de limpieza, desplegado el 2026-09-29:**
`20260929080000_ack_private_task_attachment_cleanup.sql` expone al escritor
autorizado sus tombstones pendientes y registra `storage_deleted_at` sólo si
`storage.objects` ya no contiene la ruta. La migración quedó `APPLIED` con
readback; el pgTAP focal pasó 32/32, incluyendo rechazo del acuse con bytes
presentes, aislamiento del observador y reintento de acuse. El cliente local
reanuda los retiros pendientes en tandas de 25 al iniciar, borra por Storage y
pide el acuse. Continúa mientras la tanda completa termine bien; si falla un
retiro se detiene para no consultar indefinidamente los mismos tombstones y
deja el resto para otra sesión. Comprueba la identidad entre borrado y acuse.
La revisión del 2026-09-29 encontró que v1 no filtra por taller antes de
paginar; su rama de asignación admitiría una tarea ajena al taller activo si
una misma identidad pudiera reunir ambas autoridades. En producción hay 0
perfiles ERP activos duplicados y 0 solapamientos ERP/portal, con índice único
y guardias habilitados: no se observó ese cruce. El cliente local omite por
defensa cualquier ruta fuera de su lease y termina las propias de esa página
(prueba HTTP focal 1/1). `20260929100000` añadió y desplegó v2: recibe el
taller del lease, filtra filas antes del límite y mantiene la autorización
por archivo. PgTAP 45/45 con dos talleres y página de tamaño uno; el transporte
HTTP 7/7 exige enviar el taller. Readback productivo verde y sello `APPLIED`,
con 0 vínculos pendientes. `080000` aplicado permanece intacto.
El retiro del cliente local ahora conserva el lease desde la RPC que oculta
el vínculo hasta Storage DELETE y el acuse. Si el taller cambia justo después
del tombstone, devuelve limpieza pendiente y deja bytes/acuse a la cola del
taller original; no refresca la bandeja anterior bajo la identidad nueva.
Valida también que la ruta recibida comience por taller/tarea/UUID esperado.
Prueba focal con cambio de scope tras RPC 1/1: 0 DELETE y 0 acuses; analyzer
limpio. No sustituye un retiro real con Storage/RLS.
Esta recuperación pasó con archivo real en la app web local el 2026-09-30;
ningún dato productivo se borró durante el despliegue (0 vínculos, 0 objetos
privados al preflight).

El formulario local abre cada adjunto por separado: para el privado solicita
una URL firmada de cinco minutos al tocar «Abrir» y usa el visor de archivos
existente; no persiste la URL temporal. Al guardar cambios de la tarea filtra
estos metadatos de `smart_task_attachments` antes de construir el modelo
legacy, y `TaskService.updateTask` no reescribe el JSONB `attachments`. Esto
evita duplicar el vínculo privado al editar. La apertura y el borrado físico
pasaron en escritorio local; el teléfono nativo sigue pendiente.

**Reintento de alta, 2026-09-29:** el recibo idempotente cuenta qué pasó en
el primer comando; no demuestra que el vínculo siga activo si alguien retiró
el archivo después. Además, repetir `uploadBinary` sobre un vínculo ya creado
puede recibir una negativa RLS antes de un conflicto de ruta. El cliente local
consulta por el mismo UUID autorizado: si los metadatos coinciden, omite la
segunda subida y valida el recibo; tras el RPC vuelve a comprobar que el
vínculo esté activo. Una ruta con bytes pero sin vínculo todavía se resuelve
por el conflicto de Storage y el RPC. Este flujo no tiene prueba real de
interrupción entre Storage y RPC, por lo que no se declara cerrado.

**Limpieza de bytes sin vínculo, desplegada el 2026-09-29:** el permiso de
DELETE para un objeto huérfano propio era ineficaz mientras SELECT lo ocultaba:
Storage exige ambos para retirarlo. `20260929090000` añade SELECT sólo al
uploader original, sólo cuando conserva permiso de escritura sobre la tarea y
el objeto aún no tiene vínculo. Los demás siguen sin ver esos bytes. El
pgTAP focal pasó 35/35, la lectura estructural en producción dio 1 y el sello
quedó `APPLIED`; había cero objetos privados al corte. **Corrección del
2026-09-29:** el cliente local inicialmente borraba ese objeto tras error SQL
si una lectura autorizada no veía vínculo. Eso era inseguro: otra sesión puede
seguir subiendo o vinculando el mismo UUID. Ahora un rechazo SQL o timeout
conserva objeto e intención para reintento; ninguna lectura puntual de
ausencia autoriza DELETE sin claim del servidor que excluya al otro productor.
La prueba focal de rechazo SQL pasó 1/1 (bytes e intención conservados, cero
DELETE), analyzer de servicio/prueba limpio. Falta Storage real.
Si la tarea ya quedó guardada y la subida falla, el formulario local impide
salir mientras la petición está en curso y luego pide confirmar antes de
descartar los archivos pendientes. La prueba widget con subida suspendida y
fallida pasó 1/1 para Atrás, Cancelar, continuar y salir. Si se elige salir
tras un timeout ambiguo, los bytes pendientes dejan de estar en el formulario
y un objeto privado sin vínculo podría quedar para limpieza posterior. El UUID
queda en el registro local descrito abajo; todavía falta una reconciliación
que lo use. No se afirma un huérfano observado en producción.
Se creó sólo local `TaskUploadCleanupJournal`, un registro por UUID de adjunto
en preferencias, acotado por taller y usuario. Guarda ID de tarea, usuario,
sesión y tiempos, sin nombre, ruta ni bytes. Su prueba focal pasó 2/2 para
persistencia entre lectores y rechazo de un valor bajo una clave ajena; el
analizador de servicio y prueba dio cero issues. `TaskService.addAttachment`
ya escribe la intención antes de la primera petición remota, con lease de
taller y usuario, y la quita sólo después de comprobar el vínculo activo tras
el recibo. El test HTTP focal pasó 7/7: la intención existe antes de que
Storage vea el envío, desaparece con el vínculo confirmado y permanece ante
un replay rechazado. **Corrección local 2026-09-29:** una segunda sesión podía
sobrescribir la intención pendiente que compartía UUID. Ahora `remember`
rechaza sesión o tarea distintas y `forget` deja intacta la intención ajena;
la suite del journal pasó 3/3 y el replay de transporte 1/1. La
lectura/escritura de preferencias no forma una transacción entre procesos y
no reemplaza el claim del servidor
necesario antes de borrar un huérfano. Al confirmar «Cerrar sin adjuntar», el
formulario pide al servicio marcar como abandonados sólo los intentos de esa
tarea, usuario y sesión; espera el guardado antes de cerrar. Si falla,
mantiene formulario y bytes. Test widget 1/1 con esa negativa y el cierre
posterior; transporte 7/7 con la marca de un objeto sin vínculo; analizador
focal limpio.
Al iniciar, el cliente local consulta el vínculo activo con el lease de
taller/usuario y retira del registro sólo la entrada cuyo UUID, tarea,
uploader y prefijo privado coinciden. Transporte focal 8/8: sin vínculo la
entrada permanece, con vínculo confirmado desaparece, sin DELETE de Storage;
analizador focal sin issues. **No reanuda todavía el borrado de un objeto sin
vínculo.** La política SELECT de `smart_task_attachments` oculta tombstones:
una respuesta vacía puede ser un vínculo retirado y no prueba ausencia. El
contrato `smart_task_attachment_recovery_status_v1` ya distingue `active`,
`removed` y `absent` para el uploader que aún puede escribir la tarea. Está
desplegado y leído en producción desde el 2026-09-30, con pgTAP focal 53/53.
El cliente sólo local ya lo llama bajo el lease de taller/usuario: quita del
journal las intenciones con `active` o `removed`, conserva `absent` o falta de
permiso y no emite DELETE de Storage. El transporte simulado pasó 8/8 y el
analyzer de servicio/prueba quedó limpio. `absent` no descarta una subida o RPC concurrente:
antes de borrar un huérfano hay que excluir ese productor con un claim del
servidor. Una fecha vieja por sí sola tampoco autoriza borrar.

**Contrato pendiente de exclusión, auditado el 2026-09-30:** el journal usa
`ownerSession`, pero la ruta Storage desplegada tiene sólo
`<tenant>/<task>/<attachment UUID>/<file>` y
`smart_task_attachment_storage_allowed_v1` decide por usuario, tarea y
vínculo. Ni Storage RLS ni `smart_task_attachment_add_v1` ven la sesión del
intento. Por eso dos procesos autorizados del mismo usuario pueden actuar
sobre el mismo UUID aunque las preferencias locales rechacen una colisión
secuencial. `recovery_status_v1 = absent` sólo describe el vínculo: no es un
acuse de que terminó `uploadBinary`.

El próximo contrato servidor/cliente debe reservar un intento exclusivo antes
de Storage, con token opaco emitido por el servidor y generación de ruta
distinta por intento; Storage INSERT y la RPC de vínculo deben validar esa
generación vigente. La transición a abandono debe impedir nuevos productores
y demostrar que un envío ya admitido terminó antes de autorizar DELETE. Hay
que probar dos procesos con el mismo UUID, un upload que termina después de
abandonar, retry con bytes iguales/distintos, cambio de taller, revocación
entre Storage y vínculo y crash/reinicio. Si Storage no ofrece una garantía
comprobable para el envío ya admitido, el sistema debe conservar la intención
y los bytes sin vínculo para revisión autorizada; no basta un TTL, una lectura
`absent`, ni un claim sólo sobre la fila de vínculo. No modificar las
migraciones `070000`–`110000` ya aplicadas para introducir este contrato.

El cliente local comprueba de nuevo el lease de taller/usuario después de
Storage y antes de vincular el objeto: si cambia durante la subida, conserva
la intención para reconciliación y no manda la RPC del taller anterior. La
prueba HTTP focal de cambio de scope durante Storage pasó 1/1 (una subida,
cero vínculos, intención persistente); analyzer de servicio/prueba sin issues.
Un objeto podría haber quedado guardado, por lo que este caso tampoco autoriza
borrarlo sin exclusión del productor.
La identidad del vínculo y el tamaño no acreditan que los bytes sean los
mismos: en un replay con vínculo, o si `uploadBinary` devuelve error tras haber
guardado el objeto, el cliente local descarga el objeto autorizado y compara
el contenido completo. Sólo si coincide continúa al recibo de la RPC; si
difiere, no vincula el archivo y pide retirarlo del pendiente y seleccionarlo
de nuevo. La API Storage local estaba detenida en este corte; no se levantó
porque sus imágenes faltaban y había ~17 GiB libres con otros builds activos.
`task_private_attachment_transport_test` pasó 6/6 con el transporte HTTP de
Supabase simulado: mismo UUID y mismos bytes no vuelven a subir, bytes distintos
impiden pedir el vínculo, y una ruta huérfana ocupada sólo se reaprovecha si
sus bytes coinciden. Al retirar, tanto un borrado físico exitoso como uno
fallido dejan el vínculo oculto; sólo el exitoso solicita el acuse y el fallido
devuelve limpieza pendiente. No prueba las políticas de Storage ni una
interrupción real. Trampa de la prueba: el SDK envía `uploadBinary` como
multipart; el servidor simulado debe extraer el archivo de esa envoltura
antes de comparar bytes. Comparar la petición HTTP completa daba un falso
fallo de contenido.
El mismo test comprueba que 26 tombstones se procesan en dos tandas de 25 y
que una tanda con un DELETE fallido se detiene sin ciclo; una invocación
posterior termina los pendientes. Son respuestas simuladas, no bytes reales.

**Retiro visible antes de limpieza física:** la RPC de baja marca el vínculo
como retirado antes de que el cliente pueda borrar bytes y pedir el acuse.
Si ese segundo paso falla, el archivo ya no pertenece a la tarea visible; el
formulario local lo quita de la lista y avisa que la limpieza se retomará desde
la cola autorizada al iniciar. Un adjunto del arreglo heredado, aunque tenga
un campo `id`, no se manda a la RPC privada sin `storage_bucket` privado.
El fallo intermedio y su reanudación pasaron en la app web real local el
2026-09-30, según el checkpoint siguiente.

**Checkpoint real de C1, 2026-09-30:**
`.tmp/e2e/task-form-20260930-033442.log` pasó 1/1 con `lib/main.dart`, login
real de mecánico y Auth/REST/Storage locales. Guardó la tarea con Storage
caído, mostró el aviso dentro del diálogo, reintentó dos archivos sin duplicar
la tarea, descartó un tercero pendiente, abrió mediante firma/visor con HTTP
200 y retiró ambos. Un retiro con Storage caído ocultó el vínculo y explicó
la limpieza pendiente; al volver con Storage activo obtuvo el acuse. Readback
y teardown confirmaron una tarea, dos vínculos retirados/confirmados, cero
bytes, ningún vínculo del archivo descartado y ningún residuo sintético.
Codex revisó fuentes, log y capturas reales: 24 frames de escritorio
claro/oscuro y web de 390 px. Esto sustituye las afirmaciones anteriores de
falta de Storage real para ese recorrido; no demuestra upload interrumpido
entre procesos, migración heredada ni cliente publicado.

**Teléfono nativo aceptado, 2026-09-30:**
`.tmp/e2e/android-task-form-20260930-055146.log` y 14 frames/semántica
acreditan la app completa en AVD oficial, mecánico real de Auth local,
asignación a compañera, dos archivos privados abiertos/retirados/acusados.
Readback y retirada=1, cero bytes/residuos. Codex revisó fuente, log y hoja de
contacto sin repetir. La captura oscura encontró el encabezado claro del visor;
la corrección usa roles de tema en el dueño compartido, con regresión de
contraste. La siguiente compilación y el recorrido del taller la comprobarán.
Este resultado tampoco acredita traslado heredado ni cliente publicado.

## C3: bytes y contenido examinados, 2026-09-30

El manifiesto de revisión por objeto se obtiene con
`supabase/manual_checks/legacy_workshop_asset_review_manifest.sql` mediante
el wrapper guardado. Se guarda con permisos privados en `.tmp`; no se
publican rutas, IDs ni contenido de cliente.
`scripts/e2e/audit_legacy_workshop_assets.py` lee exclusivamente las dos
carpetas y el origen productivo conocidos, limita objetos/bytes, valida la
referencia exacta y el par cliente/taller, y calcula SHA-256. No usa claves ni
hace operaciones de Storage distintas de GET.

Resultado `.tmp/e2e/legacy-assets-source-audit-20260930.log`: 16 objetos HTTP
200, tamaño igual al inventario, **13.953.499 bytes**, seis fotos con
referencia exacta y dueño coherente. Hay ocho PDF de una página, con ocho
hashes distintos; siete tienen el mismo texto extraído. Los dos HEIC tienen
bytes idénticos pero rutas distintas: la igualdad de bytes no autoriza borrar
ninguno ni atribuir su uso. Los recibos de origen contienen `copy_verified`,
`references_changed` y `public_retired` en false. Todavía no hay copia privada.

La lectura completa del texto de los ocho PDF aporta una referencia de
trabajo que el nombre de archivo no contenía. La consulta privada de esa
referencia junto al cliente no encontró el trabajo actual; el número de
factura del contenido tampoco coincide. El nombre de cliente corresponde a
dos filas actuales del mismo taller, sin identidad de cliente inequívoca.
Once fuentes de historia/auditoría del taller y contabilidad tampoco contienen
los números de documento/trabajo del contenido (consulta agregada privada
`.tmp/db/legacy-budget-history-references.json`). Estas coincidencias parciales
no reconstruyen la entrega ni autorizan atribuir el PDF a una fila de cliente. No inferir el dueño del logo, uploader, texto
idéntico o coincidencia de nombre. El contenido/consulta quedan privados
como recibos privados bajo `.tmp/e2e/legacy-assets-review-20260930` y `.tmp/db`.
Las ocho páginas completas se renderizaron y revisaron; PDFs, texto y renders
de lectura ya se movieron a Papelera, conservando sus hashes y el manifiesto.

## C3: destino y consumidores integrados en fuentes, 2026-09-30

El forward `20260930180000_private_legacy_workshop_asset_reads.sql` está
APPLIED y verificado a21:18:31 UTC. Crea `workshop-legacy-private`, un recibo privado por copia y lectura
para staff activo o el cliente del trabajo. El recibo exige el vínculo literal
actual, cliente/taller/trabajo concordantes y tamaño/hash de ambos objetos.
Un cerco restrictivo impide que otra política permisiva de Storage abra este
bucket a anónimos, otro taller o escrituras del cliente. Privacidad local19/19,
Auth/Storage reales staff/cliente/otro taller/anon/delete y bytes exactos
aceptados. Readback productivo pareado=1, selloAPPLIED y recibo SHA; no prueba
mutante de producción.

La referencia heredada conserva su identidad. `WorkshopAssetService` pide
autorización vigente y resuelve el recibo a una URL temporal; una copia
registrada ausente o revocada explica el fallo y no vuelve al origen público.
El dueño compartido `WorkshopAssetContent` alimenta `HoverZoomImage` en las
tablas ERP y las miniaturas del formulario. `WorkshopAssetGallery` abre el
visor canónico desde el detalle del trabajo del portal. El generador de
presupuesto/diagnóstico incorpora las fotos como bytes autorizados en el PDF.
Corrección del supuesto anterior: esos dos consumidores portal/PDF no abrían
las fotos del trabajo; se implementan aquí, no se acreditan como migrados por
encontrar una URL pública o un comentario antiguo.

Gates de fuente aceptados: transporte privado 3/3 (lectura, negativa sin
fallback y cambio de actor), PDF con foto 1/1 y revisión de los píxeles de su
segunda página, analyzer limpio de los consumidores. No sustituyen la copia,
lectura real ni frames de la app. `run_workshop_private_files_local.py` prepara
el gate sintético acotado con subida/copia/hash, staff/portal/otro taller y
retirada exacta; no inicia ni reemplaza los servicios de otro agente.

`scripts/storage/copy_legacy_workshop_assets.py` prepara por defecto el plan
de las seis fotos atribuidas o un subconjunto. Revalida dueño/vínculo/versión
del objeto, descarga original y copia, compara bytes y registra el recibo.
Su ejecución exige el hash del plan revisado; no reemplaza objetos, escribe
referencias ni retira originales. 181000 APPLIED a21:27:55 UTC incluye
recibos en captura y recuperación C2 como miembros del trabajo. El gate real
capturó y recuperó trabajo/recibo2/2 idénticos y volvió a abrir la copia para
staff/cliente con original sintético404; cero paquetes. La miniatura del ERP
y miniatura/visor del portal real están comprobados (escritorio/390px);
Android nativo focal153334 claro/oscuro aceptado por Codex: miniatura privada
con original sintético ausente; readback recibo1/copia1/vínculo1/original0.
La conducción tuvo un fallo de identificación del encabezado/Adjuntos y se
completó focalmente: el log inicial no se presenta como PASS automático.
Claude devolvió DB local y AVD; las dos fixtures retenidas para escritorio se
retiraron al terminar, sin residuos ni originales productivos retirados.
Evidencias `.tmp/e2e/c3-private-real-20260930.log` y
`.tmp/e2e/c3-private-recovery-real-20260930.log`.

Límites revisados con Claude: cambiar el cliente del trabajo no reasigna un
recibo ni expone la foto a otro dueño; se cierra la lectura. Un objeto privado
faltante niega la recuperación completa y el PDF no omite silenciosamente
una foto requerida. Un recibo ausente de un trabajo que sigue vivo no se
reintroduce desde historia. Las FK bloquean borrados físicos de ese trabajo,
cliente o taller mientras haya recibos. Los originales públicos siguen
expuestos hasta su retirada autorizada después del cliente publicado.

La instrucción humana vigente mantiene C2/C3 y exige terminar lo empezado.
La copia productiva acotada está completada: **6/6, 7.908.102 bytes**, con
recibos verificados y lectura independiente de hashes/tamaños, dueño/vínculo
actuales y presencia en el bucket privado. Cero referencias modificadas y
cero originales retirados. Evidencias:
`.tmp/e2e/legacy-assets-copy-production-20260930.log`,
`.tmp/e2e/legacy-assets-review-20260930/private-copy-production-receipt.json`
y `.tmp/db/c3-six-private-copies-readback.sql` (6/t/t/t/t/0).
La publicación del cliente y cualquier retirada pública
conservan su autorización explícita. Los diez objetos sin vínculo atribuido
conservan bytes/estado hasta obtener autoridad de cuarentena e identidad de
acceso; no se retiran por ausencia. Mientras el original siga público, la
copia privada no constituye cierre de su exposición.

**Retiro público, 2026-10-01 (decisión del dueño):** el dueño autorizó cerrar
la exposición sin esperar más trazado. «Sin dueño» no se trató como basura:
los diez objetos sin atribución (2 HEIC, 8 PDF) se preservaron byte a byte en
la cuarentena privada que ya existía para bytes heredados sin referencia
(`messaging-attachment-quarantine/legacy-orphans/<sha256>`, recibo en
`messaging_legacy_orphan_quarantine_receipts`, sólo `service_role`), en vez de
inventar otro destino. `scripts/storage/retire_legacy_workshop_public_assets.py`
fija el alcance (8 + 8, 6 atribuidas), compara cada original con su gemelo
privado, vuelve a compararlo justo antes de borrar y marca la cuarentena como
retirada sólo cuando el catálogo ya no tiene el objeto. Resultado: plan
`197a62f4…`, 16/16 borrados, 0 públicos, 6 copias y 10 cuarentenas presentes,
10 recibos marcados; evidencia `.tmp/e2e/legacy-assets-public-retirement-20260930.log`
y recibo privado en `.tmp/e2e/legacy-assets-review-20260930/`.

**Trampa:** después del borrado el CDN de Storage siguió sirviendo 11 de las
16 URL públicas con 200 durante algo menos de un minuto. El catálogo vacío
no prueba que la URL ya no responda: se mide la URL pública sin credencial
hasta que las 16 den «no existe» (03:44 UTC). Las fotos referidas en
`mechanic_jobs.image_urls` conservan su referencia; un cliente anterior al
corte publicado las muestra rotas, el actual las lee de la copia privada.

## Dirección de corrección

1. Dejar públicos solamente los activos destinados al catálogo, sitio y
   logotipos. La apariencia simple para el trabajador o cliente no requiere
   debilitar la separación de datos en Storage.
2. Enviar los nuevos adjuntos internos a buckets privados con rutas de tenant
   y autorización basada en la fila de negocio. Los buckets `job-images` y
   `bike-images` ya están diseñados localmente para fotos nuevas del taller;
   las tareas y presupuestos necesitan su propia ruta privada y lectura
   temporal/autorizada.
3. Para los objetos heredados, inventariar referencias vivas; copiar bytes por
   Storage API a destino privado; verificar tamaño/hash y autorización;
   cambiar las referencias de forma controlada; sólo después retirar el objeto
   público. Una migración SQL de políticas no mueve bytes ni protege una URL
   pública existente.
4. Restringir INSERT/UPDATE/DELETE y LIST del bucket heredado por ruta y
   capacidad después de mapear cada carpeta a su dueño. Rechazar una regla
   genérica que trate el primer segmento como tenant: varias carpetas activas
   empiezan por `inventory`, `website` o `suppliers`.
5. No convertir el bucket entero en privado antes de migrar las referencias:
   rompería imágenes públicas del catálogo y sitio. Despliegue, movimiento de
   datos y read-back requieren el flujo guardado de producción y la autoridad
   correspondiente.

La decisión de producto aquí es concreta: los clientes siguen viendo imágenes
de venta sin fricción; los empleados abren adjuntos internos desde el ERP sin
manejar URLs ni permisos manualmente. La complejidad de buckets, relaciones y
políticas queda detrás de esa interfaz.
