# Que nada se pierda al guardar

**Desde el 2026-11-04.** Lo que alguien guarda en el ERP llega al servidor, o
queda a la vista que no llegó. Nunca un «guardado» que no existe.

## Por qué existe

El 2026-11-04 el compañero que atiende el taller lo dijo así: «cosas que yo sé
que registré no quedan registradas… ese es como el mayor problema que hemos
tenido», y pidió «trabajar local primero y luego sincronizar» y «alguna especie
de salvado automático». El dueño: «aplica lo que hacen las empresas de software
de ERP profesionales».

La causa, medida ese día:

- El taller usa la app de macOS con internet VTR que se corta por minutos en
  horario de atención. Los registros del servidor muestran **cero errores**: lo
  que falla nunca llega, así que el servidor no puede verlo. Los huecos de
  `rpc/get_checked_in_employees` (una vez por minuto) son la señal de los
  cortes.
- Fuera de la bandeja del taller (`WorkshopCommandOutbox`), cada guardado salía
  **una sola vez, sin tiempo límite**. Un corte dejaba el botón girando o
  fallaba con un aviso de 4 segundos («Error guardando cliente: ClientException…
  uri=…») que se iba antes de que la persona lo leyera. Si había salido de la
  pantalla, lo escrito se perdía sin rastro.
- Lo escrito antes de «Guardar» vivía sólo en la memoria del formulario: un
  cierre, un «atrás» o un corte de luz lo borraba.

## Lo que garantiza

1. **Reintento solo, sin duplicar.** Cada envío tiene tiempo límite y se
   reintenta cuando repetirlo no puede dejar nada dos veces.
2. **Estado honesto, a la vista.** Un aviso abajo dice «Sin conexión ·
   Reintentando», «Guardando… · La conexión está lenta» o «Conexión
   recuperada». Nunca dice «guardado» si no llegó.
3. **Lo que no llegó queda en el equipo.** Cada guardado se anota en el equipo
   antes de salir; si no alcanza a llegar (o la app se cierra mientras dice
   «Guardando…») queda en la bandeja «Cambios sin guardar», sobrevive a cerrar
   la app, se reenvía solo si ni siquiera una repetición de la persona puede
   dejarlo dos veces, y si no espera su decisión.
4. **Lo escrito se guarda mientras se escribe.** Los formularios conectados
   guardan en el equipo lo que la persona teclea, y lo recuperan solos al
   volver a abrirlos, con «Deshacer».

## Las piezas y su dueño

| Pieza | Archivo | Qué hace |
|---|---|---|
| Transporte | `lib/shared/services/network/resilient_http_client.dart` | El `http.Client` de Supabase (`main.dart` → `createErpHttpClient`): tiempos, reintentos, bandeja |
| Qué es repetible | `lib/shared/services/network/request_safety.dart` | Clasifica cada petición: lectura, comando con llave, cambio repetible, alta, sesión, función |
| Etapa del fallo | `stage_aware_sender_io.dart` / `_stub.dart` | En escritorio y teléfono distingue «no salió» de «se cortó»; el navegador no puede |
| Estado de conexión | `lib/shared/services/network/connection_status.dart` | En línea / lenta / sin conexión, con sonda a `/auth/v1/health` |
| Bandeja | `lib/shared/services/network/unsaved_changes_journal.dart` | Lo que no llegó, en el equipo y por persona; la nota previa de cada guardado |
| Llaves sostenidas e identidades | `lib/shared/services/network/operation_identity.dart` | `StableOperationKeys` (qué se reenvía solo), `RecordIdentities` (la identidad de un registro nuevo con borrador), `HeldRecordIdentity` (la de un formulario sin borrador) |
| Altas con identidad | `lib/shared/services/database_service.dart` | `insert`/`insertIdentified`: el `id` desde el equipo en `clientIdentityTables` y el 409 de su propia fila |
| Aviso y bandeja en pantalla | `lib/shared/widgets/connection_status_prompt.dart` | El aviso abajo al centro y el panel «Cambios sin guardar» |
| Píldora | `lib/shared/widgets/vb_status_pill.dart` | El control compartido de los dos avisos |
| Borradores | `lib/shared/widgets/form_draft_scope.dart`, `lib/shared/services/form_drafts/form_draft_store.dart` | El salvado automático de un formulario |

La bandeja del taller (`WorkshopCommandOutbox`) y la de WhatsApp siguen siendo
dueñas de lo suyo: sus comandos (`save_bike_aggregate`,
`save_mechanic_job_lines_v1`, `transition_mechanic_job_status`,
`create_mechanic_job_v1`, `record_workshop_command_attempts_v1`,
`enqueue_whatsapp_message_v1`) no entran a la bandeja general
(`_durableElsewhereRpcs`), para no tener dos dueños del mismo reenvío.

## El transporte

- **Tiempos:** 45 s para que llegue la respuesta de una lectura, 60 s de un
  cambio, 180 s de una función (las de IA cortan a 150 s); 60 s de silencio
  máximo mientras llega un cuerpo. Hasta 6 intentos en 40 s, con espera de 0,5 →
  8 s y ±20 %.
- **Lo que no salió se reintenta siempre:** si la conexión nunca se abrió (sin
  red, sin nombre, conexión rechazada, TLS sin terminar) el servidor no recibió
  nada.
- **Lo que se cortó después de salir sólo se reintenta si es repetible:**
  lecturas; comandos con llave de operación (`p_operation_key`,
  `p_idempotency_key`, `p_operation_id`, `p_checkout_key`); `PATCH`, `PUT` y
  `DELETE`; altas con `Prefer: resolution=merge-duplicates|ignore-duplicates`;
  y **altas con identidad**: un `POST` cuyas filas traen `idempotency_key` o un
  `id` con forma de uuid (ver abajo). Un alta simple (`POST` sin identidad) que
  se cortó **no** se repite: podría quedar dos veces.
- **503 y 429** (el servidor no lo procesó) se reintentan siempre; **502, 504 y
  520–524** sólo si es repetible.
- Una función con nombre de lectura que consume algo (`get_next_document_number`,
  `get_supplier_credential_v2`, `calculate_payroll`) **no** es lectura.
  `p_key` es el nombre de un ajuste, no una llave.
- Lo que la persona ve si al final falla es una frase, no una traza
  (`ErpConnectionException`, que sigue siendo un `ClientException` para quien
  lo atrapa por tipo): «Sin conexión: no se guardó. Quedó en este equipo;
  revísalo en el aviso de abajo.»

## La bandeja «Cambios sin guardar»

- **Qué entra:** todo cambio (no lectura, no sesión, no función) que agotó sus
  intentos sin respuesta, con su cuerpo (hasta 256 KB; una foto no), su
  etiqueta en palabras («Cliente · Dora Pérez») y si salió o no.
- **Qué nunca entra:** la sesión ni la llave pública. Al reenviar se ponen
  frescas.
- **Por persona:** se guarda con el usuario del token; otra cuenta en el mismo
  equipo no la ve.
- **Se anota antes de salir** (`beginWrite`), como el diario de una base de
  datos. La nota no se ve mientras espera; se borra con la respuesta (cualquier
  respuesta: un rechazo lo ve la persona en su pantalla) y pasa a la bandeja si
  el transporte se rinde. Una nota que aparece al abrir la app es un guardado
  que quedó a medio camino al cerrarse: «La app se cerró antes de saber si
  llegó».
- **Se reenvía sola** al volver la conexión, al volver la app al frente y al
  renovarse la sesión, sólo lo que no puede quedar dos veces **aunque la
  persona lo haya repetido**: un comando o un alta cuya llave **sostiene su
  dueño** (`StableOperationKeys`, hasta 24 h) y un cambio repetible que no
  salió (hasta 10 min); 4 veces como máximo.
- **Por qué la llave tiene que estar sostenida (2026-11-04, antes de
  publicar).** La primera versión reenviaba sola todo comando con llave. Una
  llave evita el doble sólo si el segundo intento lleva la misma, y un comando
  cuya llave nace en cada llamada (`'p_operation_key': const Uuid().v4()`)
  más la repetición a mano de la persona quedarían dos veces.
  **Corrección del mismo día, medida en el código:** de los 20 lugares que
  sacan la llave por llamada, ninguno podía duplicar. Los 16 de compras (lista
  y plan) y la edición del gasto mandan la versión que esperan; las tareas del
  portal de trabajadores y los ajustes fijan un estado; Nóminas saca la llave
  al abrir su diálogo, no al confirmar. El cambio de estado de un trabajo
  nunca pasó por esta bandeja: es de la del taller. Los ejemplos del primer
  texto («la lista de compras», «el estado de un trabajo») estaban mal. La
  regla queda igual, para lo que se agregue.
- **Se reenvía solo, entonces:** lo que su dueño sostiene (la caja, con una
  llave por carro hasta confirmar la venta; el cobro rápido, el formulario de
  pago y el de proveedor mientras están abiertos; los registros nuevos con
  identidad, abajo) y todo comando con llave que **dice qué versión espera**
  (`p_expected_version`, `p_expected_plan_version`, `p_expected_updated_at`…
  con valor, `RequestSafety.versionGuarded`): si ya se aplicó, la versión
  cambió y el servidor rechaza el segundo, así que no puede quedar dos veces
  aunque la persona lo haya repetido con otra llave. Si el reenvío llega tarde
  y ya no calza, queda en «Revisar» con el motivo del servidor.
- **Espera a la persona** todo lo demás. El panel dice «Puede que haya
  llegado» y pide revisar antes de «Reenviar» si es un alta simple, o «Si ya lo
  volviste a hacer, descártalo» si reenviarlo no duplica lo suyo pero sí una
  repetición. «Descartar» pide confirmación.
- **Se resuelve sola** si después llega un guardado igual (misma llave, mismo
  registro, o el mismo contenido sin `created_at`/`updated_at`/
  `p_client_sent_at` y, en un alta con identidad, sin el `id`): la persona lo
  volvió a guardar desde su pantalla.
- **Lo más nuevo manda, campo por campo.** Un `PATCH` posterior que llega al
  mismo registro le quita al pendiente sólo los campos que él también fijó: si
  el pendiente cambiaba el teléfono y el nuevo el correo, el teléfono sigue
  esperando. Un guardado con la misma llave que un pendiente lo reemplaza: es
  la misma operación con lo último que la persona dejó.
- **Rechazos:** si el servidor dice que no (4xx), queda con su motivo y ya no
  se reenvía solo. Si una edición vuelve sin filas (`[]`: el filtro de
  `updated_at` ya no calza), **no** se da por guardada: «No se aplicó: el
  registro cambió o ya no existe». Un 5xx al reenviar no corta el reenvío de
  los demás.

## Los borradores (salvado automático)

`FormDraftScope` envuelve el formulario sin tocar sus campos. Reglas, para que
recuperar nunca deje algo donde no va:

- Sólo campos con **etiqueta propia y única** (`labelText`). Dos «Precio» —las
  líneas de un documento— no se distinguen con seguridad y no se guardan; un
  buscador (sólo pista) tampoco.
- Sólo lo que la persona **tecleó** (el campo tuvo el foco). Lo que el
  formulario llena solo no es suyo.
- Nunca una contraseña (`obscureText`), un campo de sólo lectura ni lo que está
  dentro de un `FormDraftSkip`. Las claves de portal de proveedores se escriben
  en su propio diálogo, fuera del borrador.
- Se guarda el valor de antes y el de después. Al recuperar, un campo que otra
  persona cambió entretanto **no se pisa**: se deja y el aviso lo dice («no
  tocamos Teléfono: cambió mientras tanto»). Por eso sirve también al editar.
- Lo de una pestaña cerrada se pone cuando la pestaña se abre, con la misma
  regla.
- Se guarda cada segundo, al cambiar de campo, al irse la app al fondo y al
  salir del formulario; 14 días como máximo; por persona.
- Al abrir, se recupera solo y el aviso «Recuperamos lo que escribiste»
  ofrece «Deshacer» hasta que la persona sigue escribiendo o lo cierra.

**Conectar un formulario** son tres cosas:

1. Envolverlo: `FormDraftScope(key: _draft, draftKey: 'cliente:${id ?? 'nuevo'}',
   ready: !_isLoading, child: …)`. La llave nombra el registro; un formulario
   nuevo que viene con datos de otro lado los lleva en la llave
   (`producto:nuevo:<código>`), para no ofrecer el borrador de uno en otro.
2. Al guardar bien, **antes** de salir: `_draft.currentState?.markSaved()` y
   `unawaited(FormDraftScope.forget(llave))` (por si la persona salió mientras
   se guardaba). Sin esto, un formulario **nuevo** ofrecería otra vez lo ya
   guardado.
3. «Cancelar»/«Descartar» explícitos: `_draft.currentState?.discard()`. La
   flecha de volver sólo sale: lo escrito espera.

Conectados el 2026-11-04: cliente (`customer_form_page.dart`), trabajo del
taller (`mechanic_job_form_page.dart`; la pestaña Productos y Servicios va en
`FormDraftSkip`), producto, proveedor, gasto y la ficha de la bici
(`bike_form_dialog.dart`, con `bannerAtBottom`: en el diálogo el aviso va sobre
sus botones y no tapa el título del paso; su «Cancelar» sólo cierra, así que lo
escrito vuelve con «Deshacer»). El aviso «Recuperamos lo que escribiste» dura
como máximo un minuto.

**La venta manual no tiene borrador local.** Lo que se escribe a mano ahí son
las líneas, y un borrador por etiquetas no las distingue (dos «Precio»). Le
corresponde un borrador propio de la venta, como el carro de la caja; mientras,
«Guardar borrador» la deja en el servidor y un segundo «Guardar» tras un corte
no crea otra venta (`HeldRecordIdentity`).

## Altas con identidad

Un alta lleva su `id` desde el equipo: si el primer envío llegó y la respuesta
se perdió, el segundo choca con su propia llave primaria (409, código 23505) y
no crea otra fila. Medido en producción el 2026-11-04: toda tabla con columna
`id` la tiene como llave primaria, ningún disparador reasigna `NEW.id`, toda
columna `idempotency_key` tiene índice único, y el rol `authenticated` puede
escribir `id` en las 34 tablas de `clientIdentityTables` sin que ninguna
política de alta lo mire.

**El choque no dice con qué fila.** Con RLS, Postgres no pone los valores de la
llave en el detalle del 23505 (ensayo que se deshace, como `authenticated`, el
mismo día: el detalle llegó vacío), y el choque puede ser con otra llave única
(el RUT). Por eso la fila propia se reconoce **leyéndola por su identidad**
con la misma sesión, nunca buscando el `id` en el texto del error. La primera
versión lo buscaba en el texto y habría tratado como rechazo cada reintento
que sí había llegado.

- **Por llamada.** `DatabaseService.insert` le pone un `id` a toda alta de
  `clientIdentityTables` (34 tablas `uuid` con valor por defecto) que no trae
  el suyo. Basta para los reintentos del transporte: el mismo envío, repetido.
  Si choca (23505) y la fila con ese `id` existe, `insertIdentified` la
  devuelve con `alreadySaved`; si no existe, el choque era con otra llave y el
  error sigue su camino. La bandeja hace lo mismo al reenviar: un 409 se da por
  guardado sólo si la lectura por su identidad trae la fila.
- **Sostenida entre intentos.** Para que un segundo «Guardar», el reenvío de la
  bandeja y el de después de cerrar la app lleven **el mismo** `id`, el dueño
  lo sostiene:
  - con borrador, `RecordIdentities.of(llaveDelBorrador)`: vive en el equipo
    con el borrador y se suelta con él (`markSaved`, `discard`, «Deshacer»,
    `FormDraftScope.forget`). Cliente nuevo (`cliente:nuevo`).
  - sin borrador, `HeldRecordIdentity` en el `State`: vive mientras el
    formulario está abierto. Sin borrador, un formulario nuevo vacío es otra
    intención: si la identidad le sobreviviera, un intento viejo que sí llegó
    quedaría pisado por la venta siguiente. Venta manual
    (`invoice_form_page.dart`, `sales_invoice_editor.dart`).
- **El dueño reconoce su intento anterior.** La identidad sola no basta si el
  servicio revisa antes de insertar: «Ya existe un cliente con este RUT» y «Ya
  existe una factura con el número…» no cuentan la fila con el propio `id`.
  Cuando `alreadySaved` llega en `true`, queda lo último que la persona dejó
  (se actualiza por el camino normal de edición) y no se repite lo que vino
  después del alta (la ficha de puntos del cliente se crea sólo si falta).
- Gasto nuevo: identidad del borrador (`gasto:nuevo`); si el intento anterior
  llegó, el encabezado queda con lo último y las líneas se reemplazan (no se
  suman). Gasto rápido del riel: `HeldRecordIdentity`.
- **El error de conexión pasa tal cual.** Un servicio que envuelve todo error
  en `Exception('No se pudo guardar…: $e')` le quita a la pantalla la forma de
  saber que quedó a salvo: `ErpConnectionException` se relanza sin envolver
  (gasto y venta lo hacían; corregido el 2026-11-04).
- **No** con `Prefer: resolution=ignore-duplicates`: con `ON CONFLICT DO
  NOTHING` los disparadores `BEFORE INSERT` corren y sus efectos quedan aunque
  la fila choque (un folio, un movimiento). Con el alta simple el 409 deshace
  la sentencia entera.

## El aviso de un guardado que no terminó

`showSaveFailure(context, error, failed: 'Error guardando cliente')`
(`lib/shared/widgets/save_failure_feedback.dart`) es el aviso de todos los
formularios. Si el cambio quedó en el equipo (`ErpConnectionException.kept`)
muestra el mensaje del transporte tal cual, en el tono de atención y 8 s: dice
dónde quedó y si se envía solo. Si falló de verdad, `«$failed: $error»` en el
tono de peligro. Antes cada formulario anteponía su «Error guardando…» en rojo
a un mensaje que decía que estaba a salvo, y eso invita a repetirlo o a darlo
por perdido. Lo usan cliente, gasto, gasto rápido, venta (página y editor),
pago y cobro rápido.

## Cómo hacer que un guardado nuevo se reenvíe solo

1. Lleva una llave (`p_operation_key` respetada por la función) o una
   identidad de fila (arriba). Con eso el transporte lo reintenta sin riesgo.
2. La llave nace **una vez por intención** de la persona (un carro, un
   formulario abierto, un borrador), no en cada llamada, y su dueño la
   sostiene: `StableOperationKeys.hold(llave)` antes de mandarla y
   `release(llave)` cuando la intención termina (se confirmó, se vació, se
   cerró). Sólo entonces la bandeja la reenvía sola.
3. Una llave por llamada (`const Uuid().v4()` en el cuerpo) queda protegida
   contra sus propios reintentos; si falla, se reenvía sola sólo si el comando
   manda la versión que espera. Si no, espera a la persona.

## Límites conocidos

- Un alta sin identidad sostenida que falló espera a la persona. Cliente nuevo,
  venta manual, caja, cobro rápido y pagos ya la sostienen; el resto (gasto,
  proveedor y los 25 servicios con llave por llamada) espera.
- Dos formularios de cliente nuevo abiertos a la vez comparten borrador e
  identidad (`cliente:nuevo`): el segundo continúa lo del primero.
- La nota previa se borra apenas llega la respuesta; si la app se cae justo en
  ese instante, al abrirla aparece algo que sí llegó («Puede que haya
  llegado»).
- Una edición con `updated_at` que llegó la primera vez y se reintentó vuelve
  sin filas: la pantalla dice que otro la cambió, aunque fue el propio primer
  intento. No se pierde nada (lo guardado está); al recargar se ve.
- En la web el navegador no dice si la petición salió: un corte se trata como
  «puede que haya llegado».
- Las líneas de los documentos no van al borrador.

## Cómo se prueba

- `test/unit/resilient_http_client_test.dart` (clasificación, transporte,
  bandeja), `test/unit/stage_aware_sender_io_test.dart` (contra un servidor
  real), `test/widget/connection_status_prompt_test.dart` y
  `test/widget/form_draft_scope_test.dart`.
- En la app de depuración: `scripts/dev/app_control.sh offline on` simula el
  corte **sin que nada salga del equipo** (se puede guardar sin escribir en
  producción; lo que quede en la bandeja se descarta antes de `offline off`).
  `offline off` vuelve y debe mostrar «Conexión recuperada».
