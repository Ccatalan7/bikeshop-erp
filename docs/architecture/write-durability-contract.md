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
3. **Lo que no llegó queda en el equipo.** Un guardado que no alcanzó a llegar
   queda en la bandeja «Cambios sin guardar», sobrevive a cerrar la app, se
   reenvía solo si es seguro y si no espera la decisión de la persona.
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
| Bandeja | `lib/shared/services/network/unsaved_changes_journal.dart` | Lo que no llegó, en el equipo y por persona |
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
  `DELETE`; altas con `Prefer: resolution=merge-duplicates|ignore-duplicates`.
  Un alta simple (`POST` sin llave) que se cortó **no** se repite: podría quedar
  dos veces.
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
- **Se reenvía sola** al volver la conexión, al volver la app al frente y al
  renovarse la sesión, sólo lo que no puede quedar dos veces: comandos con
  llave (hasta 24 h) y cambios repetibles que no salieron (hasta 10 min), 4
  veces como máximo.
- **Espera a la persona** todo lo demás, sobre todo un alta que puede haber
  llegado: el panel dice «Puede que haya llegado» y pide revisar antes de
  «Reenviar». «Descartar» pide confirmación.
- **Se resuelve sola** si después llega un guardado igual (misma llave, mismo
  registro, o el mismo cuerpo sin `created_at`/`updated_at`/`p_client_sent_at`):
  la persona lo volvió a guardar desde su pantalla.
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
`FormDraftSkip`), producto, proveedor y gasto.

## Cómo hacer que un guardado nuevo se reenvíe solo

Un comando nuevo lleva su llave de operación (`p_operation_key` generada en el
cliente una vez por intención del usuario, y respetada por la función). Con eso
el transporte lo reintenta y la bandeja lo reenvía sola sin riesgo. Un alta por
tabla puede mandar su `id` generado en el cliente con
`Prefer: resolution=ignore-duplicates`, **sólo** si la tabla no tiene un
disparador `BEFORE INSERT` con efectos (folios, stock, asientos): ese
disparador corre aunque la fila choque.

## Límites conocidos

- Un alta sin llave que se cortó después de salir espera a la persona. Es lo
  correcto mientras no tenga llave; el siguiente paso es darles llave a las
  altas de clientes, ventas y pagos.
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
