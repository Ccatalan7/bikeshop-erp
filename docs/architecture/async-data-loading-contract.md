# Contrato de cargas asíncronas, caché y reconciliación

**Estado:** contrato arquitectónico transversal  
**Vigente desde:** 2026-08-04  
**Primer consumidor acotado comprobado:** Gestión de Trabajos (`/taller/pegas`)

## 1. Problema que resuelve

Una lista real puede necesitar datos por varias razones legítimas al mismo
tiempo: montaje inicial, precarga posterior al login, retorno desde un editor,
refresh manual, reanudación de la app, cambio de filtros, notificación de un
servicio o reconciliación realtime. La concurrencia en sí no es el defecto.

El defecto aparece cuando esas cargas no tienen un propietario que decida:

- qué identidad de usuario y tenant autoriza el resultado;
- qué consulta o conjunto de filtros representa;
- cuál carga vigente puede publicar datos, apagar el spinner o mostrar error;
- qué eventos se aplican como deltas quirúrgicos y cuáles exigen una lectura
  completa;
- qué resultado quedó obsoleto porque otra intención lo reemplazó.

Sin ese contrato, una respuesta antigua puede llegar última y sobrescribir una
tabla más nueva, una cancelación interna puede aparecer como banner de error y
varios triggers pueden repetir la misma consulta sin aportar frescura.

## 2. Vocabulario canónico

- **Read model:** proyección que consume una superficie: lista, mapa de filas,
  resumen, calendario o detalle compuesto.
- **Load owner:** único coordinador que decide qué carga puede publicar en ese
  read model. Puede vivir en la página, provider o servicio, pero no en los
  tres simultáneamente.
- **Authority scope:** identidad mínima que autoriza datos, normalmente
  `userId + tenantId`, más la generación de autenticación vigente.
- **Request key:** identidad semántica de la consulta: autoridad, filtros,
  orden, paginación, inclusión de eliminados y cualquier modo que cambie el
  resultado.
- **Generation/ticket:** número monotónico capturado antes del primer `await`.
  Una intención posterior invalida los tickets anteriores.
- **Carga completa:** lectura que recompone el read model desde sus fuentes.
- **Actualización quirúrgica:** inserción, reemplazo o eliminación puntual a
  partir de un evento autoritativo, sin volver a consultar toda la colección.
- **Resultado obsoleto:** éxito o error de una generación, authority scope o
  request key que ya no posee la pantalla.

## 3. Contrato no negociable

1. **Un read model tiene un solo load owner.** Los triggers solicitan trabajo al
   owner; no escriben la lista, el spinner o el error por caminos paralelos.
2. **Cada carga captura autoridad, request key y ticket antes del primer
   `await`.** La validación sólo al iniciar no basta: se vuelve a verificar
   antes de publicar.
3. **La última intención elegible gana.** Sólo el ticket vigente puede reemplazar
   datos, publicar vacío, apagar su loading state o mostrar un error.
4. **Éxito y error obsoletos son silenciosos.** No pintan datos, no vacían la
   pantalla, no apagan el spinner de una carga nueva y no muestran snackbars.
5. **Un cambio de authority scope es cancelación, no error operativo.**
   `AuthorityScopeChangedException` protege el aislamiento entre usuarios y
   tenants. Debe cortar la publicación y terminar el loading que todavía le
   pertenezca; nunca debe convertirse en banner rojo ni relajarse mediante un
   retry con autoridad dudosa.
6. **Los fallos genuinos del ticket vigente siguen visibles.** Timeout, error de
   red, contrato inválido o fallo de backend no se clasifican como cancelación
   para esconderlos.
7. **`dispose` invalida todo ticket vivo.** Una respuesta que llega después de
   cerrar la superficie ya no posee estado.
8. **La caché acelera el primer frame; no concede autoridad.** Sólo puede
   mostrarse si pertenece al mismo scope y request key y conserva la frescura
   exigida por la superficie. Una lectura fresca puede reconciliarla en segundo
   plano.
9. **Cache y realtime pueden coexistir.** Realtime actualiza la proyección/cache
   autoritativa mediante deltas. No se reemplaza automáticamente por un refetch
   completo, ni se declara que todo dato realtime sea incompatible con caché.
10. **Las mutaciones locales y realtime preservan actualizaciones quirúrgicas.**
    Insertar, modificar o eliminar una fila conocida debe fusionar esa fila y
    mantener selección, filtros, scroll y edición. La carga completa es el
    fallback cuando falta contexto o el evento no permite reconciliar con
    seguridad.
11. **Coalescer no es lo mismo que decidir ownership.** Un servicio puede
    compartir el mismo `Future` para requests con igual authority scope y
    request key. La superficie igualmente necesita ticket para impedir que una
    intención posterior sea sobrescrita.
12. **No usar polling de `_isLoading` como control general de concurrencia.** Un
    bucle de `Future.delayed(50ms)` espera, pero no identifica quién puede
    publicar, no distingue filtros, no cancela resultados obsoletos y puede
    transferir errores entre intenciones distintas.
13. **`forceRefresh` también tiene key y owner.** No puede saltarse el contrato
    ni compartir ciegamente un request con una consulta de otra forma.
14. **No se crea una abstracción global a partir de un único caso.** Primero se
    prueban dos o tres consumidores con las mismas invariantes; después se
    extrae el coordinador compartido más pequeño que represente evidencia real.
15. **`dispose` no notifica sincrónicamente a un provider ancestro.** Flutter
    finaliza el árbol con los elementos bloqueados; llamar `notifyListeners()`
    desde el `dispose` de un descendiente puede corromper el frame completo con
    `widget tree was locked` y luego `_dependents.isEmpty`. La limpieza visible
    se publica después del frame y lleva identidad del owner, de modo que una
    superficie que sale tampoco pueda borrar el contexto que una superficie
    nueva publicó antes del callback. La regresión mínima desmonta el publisher
    real bajo el provider y prueba tanto ausencia de excepción como protección
    contra un clear obsoleto.
16. **Un payload nullable no es un estado de carga.** `null` puede ser un dato
    ausente o un fallo cerrado legítimo; no puede significar también «el request
    sigue vivo». Loading, dato listo y error tienen discriminadores separados,
    y toda espera externa posee un límite que desemboca en error visible y
    retry. La regresión completa primero un request con `null` y deja otro sin
    completar hasta el timeout: ninguno puede conservar un spinner perpetuo.

## 4. Flujo de referencia

```text
Trigger
  -> Load owner captura authority + request key + ticket
  -> puede pintar cache elegible
  -> inicia o comparte la lectura exacta
  -> valida authority + key + ticket después de cada frontera async
  -> sólo el owner vigente publica datos/loading/error
  -> realtime y mutaciones siguen fusionando deltas quirúrgicos
```

La forma mínima en una superficie stateful es:

```dart
final ticket = coordinator.start(authority: authority, key: requestKey);

try {
  final value = await repository.load(requestKey);
  if (!ticket.isCurrent || !mounted) return;
  setState(() {
    model = value;
    loading = false;
  });
} on AuthorityScopeChangedException {
  if (!ticket.isCurrent || !mounted) return;
  setState(() => loading = false);
} catch (error) {
  if (!ticket.isCurrent || !mounted) return;
  setState(() => loading = false);
  surfaceCurrentError(error);
}
```

Este ejemplo expresa ownership, no obliga a copiar una clase local. Si el
servicio ya usa `AuthorityScopedLoad<T>`, su lease protege la caché del servicio
y el ticket de la superficie protege qué intención visible puede adoptar el
resultado. Son fronteras complementarias.

## 5. Matriz de triggers obligatoria

Cada read model debe inventariar, como mínimo:

| Trigger | ¿Carga completa? | ¿Puede compartir request? | ¿Conserva UI? |
|---|---:|---:|---:|
| Primer montaje sin caché | Sí | Sólo misma key/scope | N/A |
| Primer montaje con caché fresca | Background o no | Sólo misma key/scope | Sí |
| Refresh explícito | Sí | No, salvo refresh idéntico deliberado | Sí |
| Cambio de filtros/página | Sí o derivación local | Sólo key idéntica | Sí |
| Retorno de create/edit | Sólo si el comando no devolvió delta suficiente | Key exacta | Sí |
| Realtime insert/update/delete | No por defecto; delta quirúrgico | N/A | Sí |
| `notifyListeners` del servicio | Repintar caché; full load sólo sin proyección | N/A | Sí |
| Cambio de usuario/tenant | Invalidar y recargar con scope nuevo | Nunca cruza scope | No mezcla datos |
| Resume/reconnect | Reconciliación según frescura | Key exacta | Sí |

Dos triggers pueden coincidir sin ser dos bugs. Lo que se audita es si ambos
terminan ejecutando la misma lectura innecesaria y, sobre todo, si ambos creen
ser dueños del mismo estado.

## 6. Implementación comprobada: Gestión de Trabajos

El incidente observado mostraba `Error: ERP authority scope changed during
load` después de actualizaciones/refrescos. La causa no era Supabase Realtime ni
el guardarraíl de autoridad. `PegasTablePage` tenía varios triggers de carga
completa, ningún owner entre ellos y un `catch (e)` genérico que presentaba una
cancelación interna como error del operador.

El cierre acotado vive en:

- `lib/modules/bikeshop/services/workshop_jobs_load_coordinator.dart`
- `lib/modules/bikeshop/pages/pegas_table_page.dart`
- `test/unit/workshop_jobs_load_coordinator_test.dart`

Comportamiento vigente:

- cada `_loadData` obtiene un ticket monotónico;
- sólo la carga más reciente puede reemplazar tabla, loading o error;
- éxito y error de una carga anterior se descartan;
- `AuthorityScopeChangedException` del ticket actual termina su spinner sin
  banner ni rethrow;
- un error real del ticket actual conserva el contrato de superficie/rethrow;
- `dispose` invalida respuestas pendientes;
- la caché fresca sigue dando primer frame instantáneo;
- `_onBikeshopServiceChanged` conserva la ruta quirúrgica
  `_refreshFromCache` y sólo cae a `_loadData` cuando no existe cache;
- `_surgicalUpdateJob` y `_surgicalRemoveJob` siguen siendo dueños de los
  deltas realtime; no se sustituyeron por recargas completas.

**Corrección 2026-08-24 — transición de estado sin recarga universal.**
`transition_mechanic_job_status` ya devolvía la fila base autoritativa, pero la
tabla la descartaba y esperaba otra `_loadData` de toda la mesa. El servicio
ahora fusiona ese snapshot en el caché del lease exacto, preserva únicamente
las proyecciones derivadas del mismo trabajo/tenant y la superficie reemplaza
esa fila sin perder filtros, orden, selección ni scroll. La ficha del estado
elegido sólo decora el snapshot cuando coincide en ID y tenant; nunca sustituye
la autoridad del RPC. La proyección temporal se reconcilia después con una
lectura acotada y guardas de status/`updated_at`, por lo que una respuesta lenta
no puede revertir una transición posterior. Un resultado fallido o todavía
ambiguo sí invalida y recarga: esa sigue siendo la frontera segura.

La transición tampoco hace una prelectura del trabajo: el recibo inmutable ya
contiene el estado anterior para el evento de término. Los tres hidratadores
independientes de una carga completa —objeto recibido, garantía de servicio y
métricas— salen en paralelo, igual que los lotes acotados de atención de
abastecimiento. La regresión vive en
`test/unit/workshop_job_status_cache_reconciliation_test.dart` y prueba el
merge tenant/job, la ausencia de `_loadData` en éxito y la concurrencia de los
lotes; la falla conserva el fallback autoritativo.

Esto protege el flujo multiusuario: un cambio de trabajos hecho desde otro
cliente llega por el canal tenant-scoped, actualiza la fila/cache y repinta la
tabla sin reiniciar toda la colección. Las proyecciones derivadas que no tienen
evento suficiente todavía pueden requerir una reconciliación acotada; eso debe
documentarse por consumidor, no ocultarse bajo un reload universal.

**Corrección 2026-08-26 — el snapshot cacheado debe aceptar cambios de
cardinalidad.** La hidratación paralela anterior devolvía una
`List.generate(..., growable: false)`. Reemplazar una fila existente seguía
funcionando y por eso la transición de estado era instantánea, pero un INSERT
realtime fallaba en `_cachedJobs.add` con `Unsupported operation: Cannot add to
a fixed-length list`; Notificaciones veía el alta mientras Trabajos quedaba
obsoleto hasta un refresh completo. DELETE tenía la misma incompatibilidad
latente. El reconciliador de la colección ahora aplica insert/update/delete
sobre una copia growable y publica esa proyección, aunque el snapshot entrante
sea fixed-length. La regresión debe comenzar deliberadamente con una lista de
tamaño fijo y probar las tres operaciones; probar sólo el reemplazo de estado
no certifica actualizaciones quirúrgicas.

El cierre actual prueba ownership entre cargas completas y conserva el camino
realtime que ya existía. No pretende certificar por sí solo toda la futura
adopción app-wide. En particular, cualquier cambio posterior que mezcle un
snapshot completo con deltas realtime simultáneos debe añadir la regresión de
interleaving del apartado 9 antes de ampliar o extraer el coordinador.

### 6.1 Editores compuestos: verdad exacta antes que catálogos secundarios

**Validado el 2026-08-13 en el editor de Trabajos.** Abrir un registro existente
no autoriza a poner todos los catálogos que sus controles podrían usar en el
camino bloqueante. El editor separa ahora dos conjuntos:

- el agregado exacto que protege la edición —trabajo, estado financiero
  vinculado, cliente, bicicletas, líneas, productos referenciados y metadatos
  de servicio de esas líneas— se lee antes de habilitar el formulario y falla
  cerrado si queda incompleto;
- los universos de selección que no explican el registro actual —todos los
  clientes, una vista previa de productos, estados alternativos, componentes y
  chat colapsado— se cargan sólo cuando el operador abre el control que los
  necesita, o desde una caché elegible ya disponible.

Una precarga invisible de miles de filas no es «background refresh» útil si
compite por red, RPC o CPU con el primer estado operable. Un control colapsado
o sin foco no inicia su consulta por existir en el árbol. Al abrirse, toma su
propio ticket/request serial y conserva sus estados de carga/error locales.

Cuando cada fila del agregado necesita la misma metadata relacional, el owner
agrupa primero las identidades y carga mappings, targets y preguntas por lote.
No se permite un waterfall por fila. La regresión mínima debe probar tanto que
el editor existente retorna antes del catálogo amplio como que los consumidores
dormidos no ejecutan lecturas antes de una interacción explícita.

Referencias vigentes:

- `lib/modules/bikeshop/pages/mechanic_job_form_page.dart`
- `lib/modules/bikeshop/services/service_wizard_service.dart`
- `lib/shared/widgets/product_autocomplete_field.dart`
- `lib/modules/messaging/widgets/entity_chat_sidebar.dart`
- `test/unit/mechanic_job_editor_loading_contract_test.dart`
- `test/unit/service_wizard_batch_loading_test.dart`
- `test/widgets/product_autocomplete_field_test.dart`
- `test/widgets/entity_chat_sidebar_deferred_loading_test.dart`

### 6.2 Proveedores con cuota: reconciliar la proyección, no cada fila

**Corrección 2026-08-15 — Gmail.** Reconciliar las 500 filas cacheadas mediante
un `messages.get` por fila preservaba correctamente el estado leído/no leído
entre dispositivos, pero dejó de ser una lectura válida bajo el límite vigente
de Gmail de 6.000 unidades por usuario/proyecto/minuto: cada `messages.get`
cuesta 20, por lo que un solo refresh consumía más de 10.000 unidades y
producía 429 antes de considerar otro dispositivo.

La proyección acotada de Inbox se recompone ahora con las identidades de los
500 mensajes más recientes y las identidades de los 500 no leídos más
recientes. Cualquier no leído dentro de la primera ventana necesariamente está
en la segunda; así se derivan pertenencia a Inbox y estado leído para todo el
caché mediante listas baratas. Sólo los IDs nuevos visibles y los reemplazos
necesarios para llenar huecos del caché exigen detalle completo, con el mismo
límite de una página. Un ID cacheado ausente de la ventana autoritativa se
elimina, y cualquier 5xx al leer detalle se propaga: no se convierte una
respuesta parcial en éxito. El 429 tiene el contrato diferido acotado que
sigue.

La regresión mínima vive en
`supabase/functions/_shared/gmail_mail_contract_test.ts` y debe comprobar que
un snapshot mezcla leído/no leído, deduplica IDs y omite correos archivados sin
emitir consultas por fila. Si el proveedor ofrece un cursor de cambios
confiable por cliente, éste puede reemplazar el snapshot periódico; el cursor
compartido de una suscripción push no sirve como cursor consumible por varios
dispositivos.

**Corrección 2026-08-15 — contrato integral Gmail/Zoho.** Un 429 activa un
cortacircuito durable por cuenta y proveedor antes de cualquier otra llamada a
su API. `Retry-After` puede venir como segundos, fecha HTTP, timestamp dentro
del payload o no venir: el backend lo normaliza a una ventana acotada y usa
cinco minutos cuando el proveedor no publica la duración. Como `Retry-After`
es un límite inferior y no garantiza que la ventana móvil ya drenó, cualquier
reanudación espera además un minuto de resguardo y las listas que reconstruyen
Gmail se ejecutan secuencialmente. Si el primer intento posterior vuelve a ser
rechazado, el backend duplica de manera durable la espera por intento hasta una
hora; un éxito autoritativo limpia tanto el contador como el cooldown. Esto
también cubre los 429 de Gmail por ancho de banda o límites diarios, que Google
documenta que pueden persistir durante varias horas aunque el timestamp de
reintento avance de quince en quince minutos. El estado vive en
`email_accounts.provider_metadata`, por lo que una segunda sesión o dispositivo
adopta el mismo cooldown en vez de volver a presionar la cuota.

La app transforma ese resultado en
`EmailProviderRateLimitException`, conserva todas las filas conocidas, no
publica una frescura ficticia y omite el proveedor hasta el vencimiento. Esto
es un resultado explícitamente diferido, no una lectura fresca: sólo se usa
cuando existe caché conocida; un primer montaje vacío sigue fallando cerrado.
La frescura se registra además por proveedor: una cuenta diferida no vuelve
«fresca» a la bandeja completa, pero tampoco puede provocar que otra cuenta que
acaba de responder sea consultada repetidamente por eventos de fondo durante
los siguientes 30 segundos.
Al vencer, la siguiente lectura exitosa limpia el cooldown tanto local como
servidor. La regresión compartida vive en
`supabase/functions/_shared/mail_provider_rate_limit_test.ts` y
`test/unit/mail_folder_read_model_test.dart`; todo proveedor nuevo de Correo
debe adoptar este contrato antes de entrar al polling unificado.

Zoho ya entrega el resumen de cada correo dentro de la lista y no necesita un
detalle por fila. Su Inbox usa ahora el máximo documentado de 200 mensajes por
página para que una reconciliación de 500 filas requiera como máximo tres
listas, no diez. El cortacircuito de `zoho-oauth` cubre lecturas, mutaciones y
envíos; el de Gmail cubre Inbox, detalle, adjuntos, mutaciones, envíos y la
renovación de push. Si el proveedor no divulga el período de bloqueo, el
fallback impide que el polling de varios dispositivos lo prolongue. Gmail
conserva además la respuesta diferida retrocompatible para las versiones ya
instaladas.

**Corrección 2026-11-08 — todas las carpetas, no sólo Entrada.** El código con
que Meta verifica el correo del negocio nunca apareció en el ERP, aunque el
dueño refrescó varias veces: el filtro inteligente de Zoho lo había movido a
«Notification», la app sólo conocía las cinco carpetas de sistema y
`mail-sync` sólo recorría Entrada y Enviados. Había que abrir Zoho en la web
para verlo. Además, `/folders` de Zoho entrega Notification y Newsletter con
`folderType` «Inbox», igual que la Entrada: tomar la Entrada por el primer
`folderType` Inbox podía leer otra carpeta. El tipo que publica un proveedor
no identifica la carpeta.

- La Entrada de Zoho es la de ruta `/Inbox` (o nombre Inbox / Bandeja de
  entrada) y, si ninguna viene así, la primera de tipo Inbox; las otras de ese
  tipo son carpetas de la cuenta. La app (`resolveZohoFolders`, en
  `lib/modules/mail/models/mail_folder.dart`) y el sync (`zohoSyncFolders`, en
  `supabase/functions/_shared/mail_sync_parse.ts`) aplican la misma regla.
- Las cinco de sistema se fusionan entre cuentas. Toda otra carpeta es de una
  cuenta, se identifica por `proveedor:id` y sólo la lee su proveedor
  (`MailFolder.appliesTo`). En Zoho son Notification, Newsletter, Archivar,
  Pospuesto y las del usuario; en Gmail, las categorías y etiquetas
  (`gmail-oauth` `list_labels`). El filtro de cuenta no se aplica a una carpeta
  de cuenta: la carpeta ya dice de qué cuenta es.
- `mail-sync` recorre todas las carpetas de correo de Zoho y deja fuera
  borradores, plantillas, bandeja de salida, spam y papelera, igual que en
  Gmail. La lista de carpetas se guarda 6 h en `sync_state.folder_list`. Los
  labels usan el vocabulario de Gmail para que las dos cuentas se lean igual:
  - Notification: `INBOX` + `CATEGORY_UPDATES`;
  - Newsletter: `INBOX` + `CATEGORY_PROMOTIONS`, y queda como masivo;
  - Pospuesto: `SNOOZED`;
  - Archivar y las del usuario: sin labels.

  Un correo conocido que cambió de carpeta se vuelve a etiquetar.
- Regresión mínima: `test/unit/mail_folder_contract_test.dart` (forma real de
  `/folders` y prioridad de `/Inbox`) y
  `supabase/functions/_shared/mail_sync_parse_test.ts`. Un proveedor nuevo
  entra con todas sus carpetas, no sólo con la Entrada.

### 6.3 Una bandeja parcial no tiene un filtro definitivo

**Diagnóstico y corrección comprobados el 2026-09-04.** En
`QuickSupplierMessagesPanel`, los hints del `ChatProvider` pueden mostrar ya
el documento y su estado mientras `_invoicesBySupplierId` sigue vacío. Los
hints se restauran de una caché persistente; el índice de compras depende de
otra carga y de la caché en memoria de `PurchaseService`. Un hot restart vuelve
a exponer esa diferencia de disponibilidad.

El vacío inicial se entrega a `ConversationActivity.hasActiveSupplierWork`
como si significara «no tiene compras»: un hilo abierto pasa el filtro Activos.
Cuando llegan las compras, un vínculo sin mensajes y con compras solamente
recibidas deja de pasar. Además, `_buildSupplierResult` publica el teléfono
cuando todavía no encuentra una compra relevante y lo reemplaza por el monto
al encontrarla. El resultado observado fue **8 → 6 filas y teléfono → monto**,
reproducido con compras diferidas en la misma instancia del panel. No requiere
un cambio en el hint ni desmontar la bandeja.

La caché de proveedores por sí sola no certifica que el índice de compras esté
listo. `_isLoadingSuppliers` tampoco lo representa: se activa sólo cuando no
hay proveedores. Un filtro cuyo resultado depende de compras debe distinguir
**pendiente, cargado vacío y cargado con datos**, y la publicación inicial debe
usar un conjunto coherente para identidad, pertenencia, contador y metadata.

La regresión mínima debe dejar pendiente la lectura de compras, inspeccionar
el primer frame y luego completarla, con hilos vacíos, compras abiertas y
compras recibidas con mensajes. Una prueba que empieza con ambas cachés llenas
o inspecciona sólo después de completar todos los futures no detecta el salto.

La implementación publica proveedores y compras juntos, comparte la lectura en
curso de `PurchaseService` por autoridad y reconoce una caché vacía completa.
La apertura con caché completa sigue siendo inmediata; una carga inicial fallida
ofrece reintento y un refresh fallido conserva el último conjunto. Tanto el panel
rápido como `/chat` omiten contadores provisionales. Guardas:
`quick_supplier_messages_panel_loading_test.dart` y
`purchase_invoice_list_loading_test.dart`.

## 7. Antipatrones que una revisión debe rechazar

- dos `initState`/listener/post-frame callbacks que llaman la misma carga sin
  owner;
- `_isLoading` usado a la vez como indicador visual y mutex;
- esperar con polling hasta que otro request termine y adoptar cualquier cache;
- un `catch (e)` que muestra toda excepción, incluidas cancelaciones tipadas;
- `notifyListeners -> fetch completo` cuando el servicio ya fusionó el delta;
- limpiar la lista antes de cada refresh y degradar trabajo continuo;
- cache global sin `userId + tenantId + request key`;
- un retry que vuelve a ejecutar con tenant o filtros recalculados a mitad de la
  misma operación;
- una respuesta vieja que puede apagar el spinner de la respuesta nueva;
- refetch completo después de cada update “por seguridad”, destruyendo las
  actualizaciones quirúrgicas y aumentando latencia/carga;
- un `Timer.periodic` de segundos que relee una lista entera aunque Realtime
  esté vivo, o que relee en cada `subscribed` sin mirar cuándo se leyó (ver
  «Con Realtime vivo, releer es la red de seguridad», 2026-10-31).

## 8. Ruta incremental para toda la aplicación

La adopción es un refinamiento gradual, no un refactor global de una vez.

### Fase A — Inventario y riesgo

Para cada lista/read model, registrar:

- owner actual y todos sus triggers;
- authority scope y request key reales;
- cache, TTL, preload e invalidaciones;
- canales realtime y calidad de sus payloads;
- mutaciones locales y deltas disponibles;
- spinner, vacío y error owners;
- consultas duplicadas observadas y costo aproximado;
- riesgo de negocio: dinero/stock, frecuencia y exposición multiusuario.

Priorizar primero superficies de alta frecuencia y colaboración: Inventario,
Ventas/POS, Compras/Recepción, Clientes/CRM, RR.HH. y demás mesas operativas. La
prioridad concreta se decide con evidencia, no por orden de carpetas.

### Fase B — Corrección por consumidor

1. Centralizar los triggers detrás de un owner local.
2. Definir authority scope y request key completas.
3. Añadir ticket/latest-eligible-wins y manejo tipado de cancelaciones.
4. Preservar cache-first y deltas realtime existentes.
5. Eliminar sólo las cargas duplicadas demostradas.
6. Añadir pruebas adversariales y smoke real antes de migrar el siguiente.

### Fase C — Extracción compartida

Después de dos o tres consumidores verdes, comparar invariantes y extraer sólo
lo común: ticket/generation, clasificación de cancelación, ownership de
loading/error y, si aplica, coalescing por key. Las reglas de merge, filtros y
dominio permanecen en sus owners específicos.

### Fase D — Observabilidad y presupuesto

Agregar telemetría de desarrollo o métricas de bajo ruido para:

- requests iniciados, compartidos, superseded y publicados;
- latencia cache-first versus reconciliada;
- número de full fetches por navegación/refresh;
- errores genuinos versus cancelaciones de autoridad;
- eventos realtime aplicados quirúrgicamente versus fallback completo.

La optimización se considera efectiva cuando reduce lecturas y latencia sin
perder frescura, aislamiento, errores reales ni actualizaciones multiusuario.

### Una selección conocida no espera a sus datos derivados (2026-09-07)

En el ingreso OCR, el selector ya devolvía el proveedor completo, pero su nombre
se publicaba sólo después de verificar todas las líneas contra inventario. La
latencia de esas consultas parecía una selección ignorada. La selección y su
plantilla local se publican al cerrar el selector; los vínculos anteriores se
invalidan y la verificación conserva su estado y su bloqueo de continuación.
Su resultado sólo puede publicarse si sigue vigente la generación del documento.
La regresión mantiene las consultas pendientes y comprueba el nombre visible
antes de resolverlas, además de rechazar resultados tras reemplazar el documento.

### Guardar contra la versión leída: el texto de `updated_at`, no un `DateTime` (2026-10-03)

La hoja «Datos» del cliente guarda sólo las columnas que cambiaron con
`.eq('updated_at', <lo que leyó>)`: si otro guardó entre medio, la fila no
coincide, no se escribe nada y la página relee y pone la edición encima. La
versión leída se guarda como **el texto que devolvió la base**
(`ClientRecord.updatedAtToken`), no como un `DateTime`: en la web un `DateTime`
de Dart tiene milisegundos y `updated_at` microsegundos, así que comparar el
valor de vuelta nunca coincidiría y todo guardado parecería «viejo». El `+` del
desfase viaja bien (`Uri` lo codifica como `%2B`). Comprobado el 2026-10-03 con
tres guardados reales sobre el cliente de prueba «Test Taller» (agregar, quitar
y uno rechazado por un cambio ajeno), restaurado después.

### Un `if (_isLoading) return;` le miente a quien espera (2026-10-03)

`SalesService.loadInvoices` volvía de inmediato si otra pantalla ya estaba
leyendo facturas. Quien hacía `await` recibía la caché todavía vacía y sin
`invoiceError`, así que la lista de clientes nueva habría mostrado «nadie debe
nada» con $0 por cobrar. Lo encontró la revisión de Codex leyendo el código,
no una prueba. Ahora la lectura en curso se guarda y se devuelve la misma
(`_invoicesLoad`): quien espera recibe el resultado o el error de esa lectura
(regla 11). La misma salida temprana sigue en `SalesService.loadPayments`,
`PaymentMethodService` y `PaymentTerminalProfileService` (2026-10-03): quien
los consuma con `await` tiene que contar con que pueden volver antes de leer.

### Un oyente de estado que toca canales mata el socket de Realtime (2026-10-08)

`RealtimeClient` (2.7.0 y también 2.13.0) recorre su lista de canales para
avisarles que el socket se cerró y **después** programa la reconexión. Si un
callback de `subscribe(...)` quita o crea un canal en ese mismo instante —la
bandeja de chats caía a `postgres_changes` al primer `channelError`—, el SDK
lanza «Concurrent modification during iteration», la reconexión nunca se
programa y `connect()` sale sin hacer nada porque el socket muerto sigue
asignado. Desde ahí todo `subscribe` vence: en el Mac del dueño fueron 3 201
reintentos fallidos, los registros del servidor decían «Tenant has no
connected users» con dos apps abiertas y la foto de un proveedor llegó sólo al
teléfono. Tres reglas:

- Un callback de estado o de evento del SDK nunca toca canales en el mismo
  turno: `TenantBroadcastHub` entrega estados y eventos con `Timer.run`.
- Un socket que puede quedar así necesita vigilante: `RealtimeHealth` mira cada
  15 s y al volver la app al frente; si hay canales y el socket no está abierto
  ni abriéndose, marca los canales en error, suelta el socket y vuelve a unir
  los temas (sólo API pública del SDK).
- Broadcast no repite lo que se mandó mientras nadie escuchaba: todo
  `subscribed` que sigue a otro estado, el socket revivido y la vuelta al frente
  releen la bandeja y el hilo abierto (`ChatProvider.resyncAfterRealtimeGap`),
  más una relectura de seguridad con la app al frente (cada 90 s sin el tema;
  cada 5 min con él desde el 2026-10-31, ver la sección siguiente). Un
  `channelError` de red no justifica cambiar de transporte: sólo un join
  rechazado de entrada (`isRefusedRealtimeJoin`).

Diagnóstico rápido: `realtime_logs` del proyecto (conector de Supabase o
dashboard) dice cuándo no había nadie conectado; el log de la sesión de debug
(`.tmp/native-session/run.log`) muestra el `RealtimeCloseEvent(code: 1006)` y
la traza del SDK.

### Con Realtime vivo, releer es la red de seguridad, no el transporte (2026-10-31)

El ciclo anterior gastó 20,8 GB de tráfico de Supabase, 94 % PostgREST, para
una tienda con un puñado de usuarios: lo normal ronda 1–3 GB. No eran visitas,
eran relecturas con un temporizador que no miraba si Realtime funcionaba. Con
dos equipos abiertos todo el día: avisos cada 20 s (tres consultas, la lista de
100 avisos con `data`, 16 kB comprimidos: ~13.000 lecturas al día por equipo),
la bandeja de tareas cada 30 s (cuatro tablas; 76 tareas, 64 cerradas, ninguna
nueva en 30 días: ~3.400 por equipo) y el chat cada 90 s (~47 kB la bandeja).
Reglas:

- El temporizador sólo mira el reloj; la relectura corre cuando le toca. Con el
  canal o tema vivo, cada varios minutos (avisos y chat 5 min, tareas 30 min,
  por lo que Realtime no trae); sin él, cada uno o dos minutos.
- Un `subscribed` después de un hueco relee sólo si la última lectura es más
  vieja que la red de seguridad: un hueco largo ya se leyó mientras el canal
  estaba caído, y uno corto lo cubre la relectura siguiente.
- Antes de bajar un plan o aceptar una cifra de uso, medir por ruta en
  `edge_logs` (`query_logs`: pedidos por `request.path`, por IP y por
  `request.sb.jwt.authorization.payload.session_id`) y el peso real de cada
  respuesta comprimida (`json_agg` a un archivo y `gzip -c | wc -c`), y
  compararlo con lo que el negocio necesita.
- Un arreglo del ERP baja el tráfico recién cuando lo tiene la app que usa la
  gente, y esa app no es la web. Medido el 2026-11-01, 18 h después de
  publicar la 1.0.44 sólo en la web del ERP: los pedidos siguieron iguales
  (~1.150 de avisos y ~280 de tareas por hora), y todo el tráfico con sesión
  venía de las dos apps de Mac instaladas, la del taller y la del dueño
  (`request.headers.x_client_info` = `supabase-flutter/2.12.0`, la versión
  anterior); la web no aparecía. Se mide por `x_client_info` e IP en
  `edge_logs` después de publicar macOS y Android, no después de la web.

**El socket que se corta cada 51 s.** Desde el 2026-10-30 a las 12:00 de
Chile la sesión del computador del taller abre un socket nuevo cada ~51,6 s,
también de noche (1.189 en un día). 51,6 s es dos latidos de 25 s más el
reintento de 1 s: el SDK no recibe la respuesta a un latido antes del
siguiente y cierra («heartbeat timeout», `RealtimeClient.sendHeartbeat`). Los
joins sí responden (la bandeja de tareas se suscribe después de cada
conexión). El 27 y 28 de octubre pasó lo mismo en el taller (desde las 14:00
UTC) y en el Mac del dueño en Seattle (desde las ~17:00), y se detuvo en cada
equipo al reiniciar la app: no es la red sino estado de la app que no
sobrevive a reiniciarla. `realtime_logs` no registró nada. Con las reglas de
arriba, cada reconexión ya no relee todo. Diagnóstico: conexiones
`/realtime/v1/websocket` por IP y por hora en `edge_logs`, y el intervalo
entre una y otra (`lagInFrame`): 51,6 s es el latido vencido; 26,5 s, la
señal heredada de abajo.

**Lo que se encontró (corrección 2026-10-31, misma tarde).** El SDK era
`supabase_flutter` 2.12.0 con `realtime_client` 2.7.0, que fija `supabase`
2.10.2 exacto: subir `^2.6.0` no lo movía. Esa versión tiene fallas
documentadas aguas arriba en este mismo camino, y todas dejan estado que sólo
se limpia reiniciando la app:

- Un canal que se vuelve a unir mientras su join anterior sigue pendiente se
  da de baja a sí mismo y queda fuera de la lista del cliente, pero su
  temporizador lo sigue uniendo cada ~10 s para siempre, con ref vacío
  (supabase-flutter #1932 y #1942, corregidas en 2.13.1 y 2.13.2). Cada intento
  saca al canal vivo del mismo tema. Se reprodujo contra este proyecto el
  2026-10-31 con un script Dart aparte, con la llave pública en un tema
  público: el fantasma botó al canal nuevo en 8 s y siguió uniéndose cada 10 s.
- Al desconectar no se cancelaba la escucha de la conexión vieja (2.9.0), y
  `connect()` no se protegía de un `disconnect()` a mitad de camino (2.7.3).
  El `onDone` tardío de una conexión vieja puede dejar como cerrada la
  conexión vigente y cancelarle el latido.
- La señal de vida pendiente no se borra al reconectar, y esto sigue igual en
  2.13.2. Si el socket se cae con una señal en camino, la conexión nueva se
  corta sola en su primer latido. En el taller, la mañana del 30, cada
  reconexión venía seguida de una conexión de 26,5 s.

Se subió a `supabase_flutter` 2.18.3 (`realtime_client` 2.13.2, protocolo
2.0.0 por defecto, probado contra el servidor real). `RealtimeHealth` borra la
señal pendiente en cada apertura (`clearStaleHeartbeatOnOpen`), con prueba en
`test/unit/realtime_stale_heartbeat_test.dart`, que incluye un caso de control:
falla el día que el SDK la borre solo. Medido el mismo día contra el servidor:
contesta el latido en 0,1–0,2 s, también con 15 canales fantasma uniéndose en
paralelo; cierra un socket mudo a los ~66 s; un join público con token
inválido igual responde `ok`. O sea, el servidor no explicó la pérdida del
latido; lo que no se pudo ver desde aquí es el instante en que la app del
taller dejó de procesar la respuesta. Se confirma o se descarta con la misma
consulta de conexiones por hora una vez que el taller tenga la versión nueva.
Si sigue, el paso siguiente es leer el registro del cliente en ese equipo, no
seguir adivinando desde el servidor.

Lo que el salto de `supabase_flutter` 2.12 a 2.18.3 cambió además, medido el
mismo día:

- **Las lecturas fallidas se reintentan solas.** Un GET o HEAD que recibe 503
  o 520, o que falla por red, se repite tres veces más, a 1, 2 y 4 s: el error
  llega a la pantalla ~7 s después. Las escrituras y los RPC por POST nunca se
  reintentan. `PostgrestClientOptions(retryEnabled: false)` no lo apaga, porque
  `SupabaseClient.from()` arma el builder sin esas opciones (`supabase` 2.16.5).
  Sólo se apaga por consulta con `.retry(enabled: false)`. Una prueba que simula
  un 503 de lectura avanza el reloj falso 8 s, y cuenta cuatro pedidos.
- **Un socket sin canales se cierra 50 s después**, no al tiro
  (`disconnectOnEmptyChannelsAfter`), y `disconnect()` espera el cierre con
  un tope de 6 s. En una prueba de widgets cuyo Supabase apunta a una URL
  local apagada, esos dos temporizadores sobreviven a la prueba («A Timer is
  still pending»). Se usa `test/support/silent_realtime.dart`: un socket que
  nunca abre y se suelta con el último canal.
- **El ciclo de vida lo sigue un `AppLifecycleListener`**, que exige los pasos
  reales (`inactive` → `hidden` → `paused` y de vuelta). Una prueba que salta de
  `paused` a `resumed` falla con «Invalid state transition».

### `didChangeDependencies` no avisa que la pantalla volvió (2026-11-02)

La lista de productos borraba sola la categoría, todos los filtros y la
búsqueda. Desde enero, `ProductListPage` usaba `didChangeDependencies` como
«la pantalla volvió a verse»: si habían pasado más de 30 s desde la llamada
anterior, reiniciaba todo y recargaba. Pero ese método corre cuando cambia
cualquier `InheritedWidget` del que el `State` depende —el tema, el tamaño
(`MediaQuery.sizeOf` vía `ResponsiveViewport`)—, no cuando la pantalla vuelve
a la vista. Medido en la app: cambiar a oscuro, o angostar la ventana 34 px,
más de 30 s después de abrir la lista llevó «Neumáticos · 122» a 1.568
resultados, con el log `Away for 59s - resetting to fresh state`. Lo destapó
la categoría que abre el buscador global: el filtro que prometía el resultado
se perdía con el primer cambio de tamaño.

La regla: una página montada conserva su estado, y volver a verla no es un
cambio de dependencias. Salir a otro módulo la desmonta, y restaurar o empezar
de cero se decide en `initState`. Si una pantalla de verdad necesita saber que
volvió a la vista, usa una señal de visibilidad —`RouteAware`, el ciclo de vida
de la app—, nunca el reloj entre dos `didChangeDependencies`.

### Lo que se monta en el cromo o en una ficha ajena no arranca nada hasta tener sesión (2026-11-06)

El correo nuevo sumó tres piezas a pantallas que no eran suyas: el número de
«Correo» en el menú (`MailTodayBadge`, iniciado en `MainLayout.initState`
con un `Timer.periodic` de 3 minutos), y la historia de correos de un registro
dentro de la ficha del proveedor y del panel de chat (`MailRecordList`). El
gate completo falló con 50 pruebas en 14 archivos que nunca habían mirado el
correo: 13 por «A Timer is still pending» (todas montan el menú), 37 de la
ficha del proveedor porque la lista creaba `MailWorkService()`
—`Supabase.instance`— al nacer el `State`, y el panel de chat porque la lista
pedía `VinabikeThemeRoles` antes de saber si tenía algo que pintar. Costó una
corrida entera del gate.

La regla para lo que vive dentro de una superficie compartida:

- Un temporizador o una lectura periódica arranca sólo con Supabase
  inicializado y una sesión (`auth.currentSession`); sin ellos no se lee ni
  queda nada corriendo.
- El servicio se crea al cargar, dentro del `try`, nunca como campo del
  `State`: si no se puede crear, la sección no aparece.
- Lo que depende del tema de la app se pide después de los retornos
  tempranos: una sección vacía no exige nada a su anfitrión.
- Antes de cerrar, se corren las pruebas de las pantallas que lo hospedan
  (`main_layout_*`, la ficha, el panel), no sólo las del módulo nuevo.

## 9. Regresiones mínimas por consumidor

1. Respuesta A empieza, B empieza, A termina última: sólo B publica.
2. A falla después de B: A no muestra error ni cambia loading.
3. B falla de verdad: B sí muestra el error previsto.
4. Cambia authority scope durante la lectura: no se filtran datos y no aparece
   el texto interno como banner.
5. La superficie se dispone con request vivo: no hay escritura posterior.
6. Dos requests con igual key pueden coalescer; keys distintas no se mezclan.
7. `forceRefresh` no adopta por accidente una respuesta cacheada anterior.
8. Realtime update/insert/delete modifica sólo las filas correspondientes y
   conserva filtros, selección y scroll.
9. Realtime durante una carga completa se reconcilia determinísticamente; el
   resultado final no revierte el delta más nuevo.
10. Cache elegible da primer frame; cache de otro scope/key nunca aparece.
11. Sólo el ticket vigente apaga el spinner.
12. Un refresh repetido no duplica banners ni deja la tabla vacía.

## 10. Relación con el refinamiento de módulos

Toda ronda regulada por
`docs/architecture/APP_REFINEMENT_MASTER_PLAN.md` debe auditar el read model
además de sus mutaciones. El mapa mínimo es:

```text
Trigger -> Load owner -> Authority/request key -> Read -> Commit -> Reconcile
```

El objetivo no es introducir coordinadores por reflejo. Es demostrar que cada
superficie posee una sola verdad visible, conserva el trabajo del usuario y se
mantiene fresca frente a otros clientes sin carreras ni lecturas redundantes.
