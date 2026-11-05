---
titulo: Portal de clientes
resumen: lo que ve un cliente con cuenta en /cuenta — pedidos, taller, bicis, soporte — cómo entra, cómo se ve y qué sigue pendiente
fuentes: [repositorio]
archivos: [services/storefront_html/lib/src/claim_page_view.dart, services/storefront_html/lib/src/claim_page_script.dart, services/storefront_html/lib/src/delivery_document_pdf_route.dart, packages/vinabike_public_core/lib/public_store/documents/delivery_warranty_pdf.dart, packages/vinabike_public_core/lib/public_store/models/customer_claim_words.dart, packages/vinabike_public_core/lib/public_store/models/customer_phone_words.dart, supabase/functions/customer-phone-verification/index.ts, services/storefront_html/lib/src/portal_page_view.dart, services/storefront_html/lib/src/portal_forms_view.dart, services/storefront_html/lib/src/portal_page_route.dart, packages/vinabike_public_core/lib/public_store/models/customer_portal_forms.dart, packages/vinabike_public_core/lib/public_store/models/customer_portal_plans.dart, packages/vinabike_public_core/lib/public_store/models/customer_portal_snapshot.dart, packages/vinabike_public_core/lib/public_store/models/customer_portal_presentation.dart, lib/public_store/pages/customer_dashboard_page.dart, lib/public_store/pages/customer_orders_page.dart, lib/public_store/pages/customer_service_history_page.dart, lib/public_store/pages/customer_bikes_page.dart, lib/public_store/pages/customer_chat_hub_page.dart, lib/public_store/pages/customer_auth_page.dart, lib/public_store/widgets/customer_portal_style.dart, lib/public_store/widgets/customer_portal_layout.dart, lib/public_store/services/customer_account_service.dart, services/storefront_html/lib/src/android_download_page.dart, packages/vinabike_public_core/lib/public_store/models/android_download_words.dart, services/storefront_html/lib/src/portal_chat_view.dart, services/storefront_html/lib/src/portal_chat_script.dart, packages/vinabike_public_core/lib/public_store/models/customer_chat_words.dart]
tablas: [customers, bikes, mechanic_jobs, online_orders, website_settings, conversations, messages, messaging_attachments, mechanic_job_delivery_documents, customer_portal_claim_codes, customer_portal_phone_verifications, customer_portal_verified_phones, customer_workshop_notice_preferences, workshop_customer_notices]
revisado: 2026-11-05
---

# Portal de clientes

## Lo esencial

El cliente entra en `/cuenta` (correo o Google) y ve lo suyo del ERP: sus pedidos
web, sus trabajos en el taller (con presupuestos por aprobar), sus bicicletas y
el soporte por chat. No es otra base: lee los mismos `online_orders`,
`mechanic_jobs`, `bikes` y conversaciones, filtrados a su ficha de cliente
(`customers.auth_user_id`) `[Repo]`.

## Páginas

| Ruta | Página | Qué muestra |
|---|---|---|
| `/cuenta` | `customer_dashboard_page.dart` | Resumen: lo que necesita atención (presupuesto por aprobar, bici lista) y lo último |
| `/cuenta/pedidos` | `customer_orders_page.dart` | pedidos web |
| `/cuenta/cotizaciones` | sólo HTML (`portal_quotes_view.dart`, 2026-11-02) | cotizaciones de la cuenta (`list_my_customer_quotes_v1`); cada una abre `/cotizacion#q=<id>` |
| `/cuenta/servicios` | `customer_service_history_page.dart` | trabajos del taller; `?bike_id=` filtra por bici |
| `/cuenta/bicicletas` | `customer_bikes_page.dart` | sus bicis (dibujadas por tipo: 0 de 472 bicis tienen foto) |
| `/cuenta/chats`, `/cuenta/chats/:id` | `portal_chat_view.dart` del servidor HTML (2026-10-08); en el ERP sigue `customer_chat_hub_page.dart` | soporte: la lista y cada conversación |
| `/cuenta/perfil`, `/cuenta/direcciones` | `customer_profile_page.dart`, `customer_addresses_page.dart`; en el perfil, «Avisos del taller» sólo en HTML (2026-11-05) | datos, direcciones y por dónde le avisamos de su bici |
| `/cuenta/login` | `customer_auth_page.dart` | entrar o crear cuenta |
| `/cuenta/descargas/android` | `android_download_page.dart` del servidor HTML (2026-10-08); en el ERP sigue `android_app_download_page.dart` | la app Android privada, para el equipo |
| `/cuenta/mensajes`, `/cuenta/mensajes/:id` | redirigen a `/cuenta/chats` y `/cuenta/chats/:id` (2026-10-07) | enlaces viejos del chat |
| `/cuenta/vincular#c=<código>` | `claim_page_view.dart` del servidor HTML (2026-11-04) | el QR de la recepción o del comprobante: saluda por el nombre, crea la cuenta (Google o correo) y la liga a la ficha del taller |
| `POST /cuenta/comprobante.pdf` | `delivery_document_pdf_route.dart` (2026-11-04) | el comprobante de entrega y garantía de un trabajo de la cuenta, dibujado con su sesión |

Todas llevan `noindex` por cabecera ([rutas](rutas-y-navegacion.md)).

## En HTML desde el 2026-10-06

`/cuenta`, `/cuenta/pedidos`, `/cuenta/servicios` y `/cuenta/bicicletas` las
responde el servidor HTML (y `/cuenta/cotizaciones`, que nació ahí el
2026-11-02, sin página Flutter), y desde la fase 4b también `/cuenta/perfil` y
`/cuenta/direcciones`, y desde la fase 4c `/cuenta/login`; el soporte y los
enlaces que vuelven de un correo o de Google siguen en Flutter, y entre unas y
otras se pasa con una carga completa. La
página llega sin datos; el navegador pide `POST /cuenta/vista` con el token
del cliente y el servidor lee Supabase como ese cliente: la base decide qué
ve (RLS) y cada lectura filtra la tienda. El token no se guarda ni se anota.
Las reglas (qué va en «Para ti ahora», los estados, el dibujo de la bici, la
garantía) están en el núcleo y Flutter usa las mismas `[Repo]`. Medido contra
Flutter con datos reales anonimizados a 1440 y 412 px: mismos bordes y el
texto a ±1 px `[Repo 2026-10-06]`.

Lo que se guarda (el perfil, la contraseña, agregar, editar, hacer principal o
borrar una dirección) va a `POST /cuenta/accion`: el servidor revisa con las
reglas de `customer_portal_forms.dart`, escribe como el cliente con la tienda
en cada filtro (el cliente y la tienda los pone el servidor) y responde la
página de nuevo; la contraseña va a Supabase Auth con la misma sesión, sin
guardarse. Arreglado en las dos tiendas al mudarlo (2026-10-06): borrar el
RUT o el teléfono ahora los borra (volvían), un obligatorio con sólo espacios
ya no pasa y las fechas de una dirección se escriben en UTC (iban 3 a 4 h
corridas) `[Repo 2026-10-06]`.

**Entrar (fase 4c).** El login HTML entra, crea la cuenta, abre Google y
manda el enlace de «¿Olvidaste tu contraseña?», con las palabras y reglas de
`customer_auth_forms.dart` (Flutter usa las mismas). El navegador llama a
Supabase Auth directo, como Flutter: Auth cuenta los intentos por dirección y,
pasando por el servidor, todos los clientes compartirían una. Lo que Auth da
queda donde lo deja `supabase_flutter` (la sesión en `sb-<ref>-auth-token`, el
verificador PKCE en `flutter.supabase.auth.token-code-verifier`), así que
quien canjee el enlace del correo o la vuelta de Google lo encuentra. Desde el
2026-10-08 la vuelta de Google (`/auth/callback?code=`) y la confirmación de
una cuenta (`/cuenta/login?confirmed=true&code=`) las canjea el mismo login
HTML (`POST /auth/v1/token?grant_type=pkce`, como `exchangeCodeForSession`)
y sigue con `enter`; el código y el verificador se olvidan cuando Auth
contesta (un corte de red los deja para reintentar al recargar); un enlace abierto en otro navegador
no tiene verificador y queda el aviso «Tu cuenta ha sido confirmada». Los
enlaces que fijan una contraseña también son del login HTML (2026-10-08): el
correo de recuperación o de invitación pasa por `auth-action.html` y llega con
`#token_hash=…&type=recovery|invite`; un guion antes de pintar lo lee y lo saca
de la dirección, el login lo verifica (`POST /auth/v1/verify`) y pide «Nueva
contraseña» o «Crea tu contraseña». La sesión del enlace queda sólo en la
página (nunca como la sesión del navegador), cambia la clave por la tienda
(`set-password`: el comando del portal sin código de verificación, que cierra
las demás sesiones; la invitación primero pasa por `enter`), se cierra y el
login dice «Contraseña actualizada / creada». Un enlace usado o vencido dice
«El enlace de recuperación venció…» o muestra «No pudimos validar esta
invitación». Sólo la vuelta de Google del editor (su intención
`google_oauth_editor_intent` en este navegador) vuelve al servidor con
`?enlace=1`, que responde Flutter.
Antes de llamar a Auth el servidor revisa los campos (`check`); la contraseña
no le llega, sólo su forma (cada letra, número o signo cambiado por uno de su
tipo), que es todo lo que miran las reglas. Con la sesión, `enter` crea o
confirma el cliente de la tienda; si no puede serlo, la sesión se cierra y
dice lo mismo que Flutter. Al terminar una recuperación o una invitación el
login vuelve a `/cuenta/login?clave=…` y dice lo que Flutter decía.
Arreglado en las dos tiendas (2026-10-06): el teléfono escrito al crear la
cuenta se perdía si había que confirmar el correo (1 de 7 cuentas); ahora se
guarda al entrar si el cliente no tiene. El gris del panel de la izquierda
llega al fondo de la tarjeta `[Repo 2026-10-06]`.

## «Soporte» en HTML (2026-10-08)

Los chats del portal (7 conversaciones en toda su vida al 2026-10-06, 105
mensajes, todos de texto `[Prod 2026-10-08]`) los dibuja el servidor desde la
fase 4h, con las palabras y reglas del núcleo (`customer_chat_words.dart`)
que la copia Flutter del ERP también usa. La página calza la ventana bajo el
encabezado, sin franja: la lista con su «Nueva consulta», o la conversación
con sus avisos («Esperando respuesta del equipo…», archivada, cerrada), los
mensajes por día, las solicitudes de la tienda (aprobar o pedir cambios a un
presupuesto, confirmar una entrega; un pago sólo informa) y los archivos, y
al lado, en ancho, el trabajo del que trata.

- Lee y escribe **como el cliente**: la base decide qué conversación, mensaje
  o archivo ve (`messaging_can_read_conversation_messages`,
  `messaging_attachment_storage_can_read`) y las acciones son sus funciones
  auditadas (`create_customer_support_request`, `mark_conversation_read`,
  `respond_to_action_request`). Cada lectura nombra la tienda.
- En vivo con Supabase Realtime (la sesión del cliente; la seguridad de filas
  filtra los cambios); sin conexión, pregunta cada 15 s mientras se ve.
- Un mensaje lleva su `client_message_id`: si se pierde la respuesta y se
  reenvía, no queda dos veces. Lo asegura la base
  (`messages_one_per_client_key`, 2026-10-08), no la consulta previa: dos
  envíos a la vez no alcanzan a verse.
- Una consulta o un mensaje llegan hasta 8.000 caracteres y la nota de
  «Solicitar cambios» hasta 1.000, los topes de la base; las dos tiendas cortan
  ahí (`customerChatMessageMaxLength`, `customerChatNoteMaxLength`), contando
  puntos de código como la base, no caracteres de Flutter ni unidades UTF-16.
- El contexto de una factura no se muestra: `sales_invoices` deja leer a la
  tienda (`customer_id = auth.uid()` nunca calza con un cliente del portal);
  el de un trabajo sale de los trabajos del propio cliente `[Prod 2026-10-08]`.

## La descarga de Android del equipo (2026-10-08)

`/cuenta/descargas/android` no es del cliente: el equipo entra con su correo y
baja el APK privado del ERP. La dibuja el servidor HTML con las palabras de
`android_download_words.dart` (las mismas de la copia Flutter del ERP). El
servidor firma y lee el manifiesto **como la cuenta** (`POST
/cuenta/descargas/android/version`): Storage sólo lo deja leer a un perfil
activo del tenant, y lo valida `AndroidReleaseManifest` del núcleo. El
navegador baja las partes, revisa tamaño y SHA-256 de cada una y del total, y
guarda el archivo. Storage esconde lo que no deja leer: una cuenta sin perfil
ve «todavía no está publicada», igual que en Flutter `[Repo 2026-10-08]`.

## La cuenta queda con la ficha del taller (2026-11-04 → 05)

La mayoría de los clientes del taller nunca dejó correo: de 1.800 fichas
activas, 536 tienen teléfono y 83 correo `[Prod 2026-11-04]`. Una cuenta nueva
del portal nace con su propia ficha vacía; para ver sus trabajos tiene que
quedar con la del taller. Hay tres caminos, y los tres terminan en el mismo
paso de la base (`link_portal_account_to_customer_internal`: archiva la ficha
vacía, copia sus direcciones y la ficha del taller toma la cuenta y el
correo):

1. **El QR** del comprobante o de la recepción (`/cuenta/vincular#c=…`). El
   código va en el fragmento, que no llega a ningún servidor ni a GA4; la
   página lo pasa a la pestaña y saluda por el nombre de pila
   (`peek_customer_portal_claim_code_v1`, sin teléfono ni correo). Con Google
   liga al volver; con correo deja el código en los metadatos de la cuenta y
   liga al entrar, en el navegador donde se confirme. El teléfono que escribe
   tiene que calzar con el de la ficha (`phone_mismatch`).
2. **El correo confirmado**: si el taller ya tenía ese correo, liga al crear
   la cuenta (`provision_current_public_store_customer`, arreglado en
   20261104240000: antes lo frenaba la guardia de identidad). El correo es
   único por tienda, así que no hay dos fichas que elegir.
3. **El teléfono confirmado por WhatsApp** (20261105010000). Ligar por un
   teléfono escrito le mostraría a un extraño los trabajos y facturas de
   otro, así que primero se confirma: el portal ofrece «Confirma tu teléfono»
   a una cuenta sin historial propio, `customer-phone-verification` manda un
   código de 6 dígitos con la plantilla de autenticación
   `codigo_verificacion_v1` (10 minutos, 5 intentos, un código por minuto,
   cinco al día por cuenta y por número) y, al escribirlo, la cuenta queda con
   la única ficha sin cuenta que tiene ese número. Con varias fichas no elige
   (teléfono compartido); con historial propio no archiva nada. Es
   bidireccional: si el taller crea la ficha después, el portal la liga al
   entrar (`customer_portal_phone_state_v1`, `linked_now`). El código nunca
   vuelve a quien llama ni queda en el chat; la base sólo guarda su hash con el
   id.

Lo enciende el taller en Configuración › WhatsApp («Confirmar teléfono en el
portal», `customer_portal_phone_verification_enabled`), sólo con la plantilla
aprobada por Meta. El trabajo entregado muestra en `/cuenta/servicios` su
garantía (días que quedan) con «Descargar comprobante», y su factura.

## Los avisos del taller y lo que elige el cliente (2026-11-05)

Desde la 1.0.48 el taller avisa solo en cuatro momentos: la bici recibida, el
presupuesto listo, la bici lista para retirar y la entrega con su comprobante
y su garantía (20261105130000; cómo y cuándo, en
`BIKE_WORKSHOP_MASTER_SCHEMA.md` «Avisos del taller al cliente»). Cada aviso
lleva a `/cuenta/servicios` a quien ya tiene cuenta, o a
`/cuenta/vincular#c=…` con un código nuevo a quien todavía no: el aviso de la
recepción es la otra puerta del QR, y la que llega a quien no estaba en el
mesón `[Repo]`.

Avisa todo trabajo con la bici o el componente en el taller, también los de
«Presupuestar primero» (`quotation` con la bici recibida), que son casi todos:
la primera versión miraba sólo `service` y callaba 64 de 71 recepciones de los
60 días anteriores (corregido en 20261105185000). Probado de punta a punta el
2026-11-05 con el cliente «Test» (PG-00667): los cuatro correos salieron, y
por WhatsApp el presupuesto y la lista con las plantillas antiguas mientras
Meta revisa las `taller_*_v1` `[Prod 2026-11-05]`.

En «Mi cuenta › Perfil», entre «Datos personales» y «Seguridad», la sección
«Avisos del taller» tiene un interruptor por canal (correo, WhatsApp): se
guarda al tocarlo (`notice-prefs` → `set_my_workshop_notice_preferences_v1`) y
dice qué queda. Un canal que la ficha no puede recibir —sin correo, o un
teléfono que no es celular— se ve apagado y deshabilitado con lo que falta, y
conserva lo que el cliente eligió para cuando lo agregue. Sin elegir, por los
dos: es lo que pidió el dueño («correo y WhatsApp las dos, dale con todo»); y
que el cliente pueda apagar uno es la regla que dejó para las cotizaciones
(«que el cliente pueda elegir») `[Dueño]`. Sólo en el servidor HTML: ninguna
ruta de vinabike.cl dibuja el perfil en Flutter desde el 2026-10-08.

## Cómo se ve: dirección «Sendero» (2026-09-26)

El dueño encontró el portal anterior «AI'ish and childish» y aprobó la dirección
D «Sendero», sacada de sitios de marcas MTB (Commencal, Fox, RockShox, YT…):
contenedores rectos, títulos condensados en mayúsculas con etiquetas chicas
espaciadas, base clara con **un** acento, botones rectos de 40–48 px, foto a
sangre con el texto abajo, líneas de 1 px en vez de sombras. El primario del
sitio (navy `#123F68` desde el 2026-09-26) es la acción; el naranjo marca «te
necesita». Las reglas están en `.github/GUI_DESIGN_PRINCIPLES.md` «Portal de
clientes: dirección Sendero» `[Dueño]` `[Repo]`.

Las fotos del portal salen del editor (`theme_customer_portal_image`,
`theme_customer_portal_workshop_image`), no del código.

## Seguridad de las cuentas

- Cualquiera puede crear cuenta (correo o Google). Una cuenta de cliente **no**
  es personal del taller: desde el 2026-09-23 no ve el catálogo por la tabla
  (lo ve por las funciones públicas, como cualquier visitante), y no lee costos
  ([seguridad](seguridad.md)).
- El portal sólo muestra filas del cliente dueño de la sesión.

## Pendiente

- El login `/cuenta/login` no pasó por «Sendero» (en Flutter y en HTML se ve igual).
- Para mirar el portal sin sesión (un agente no ingresa contraseñas):
  `test/widgets/customer_portal_pages_test.dart`.

## En el código y la base

- Estilo y piezas: `customer_portal_style.dart`, `customer_portal_layout.dart`,
  `customer_job_row.dart`, `customer_order_row.dart`, `customer_bike_card.dart`,
  `customer_bike_drawing.dart`; datos en `customer_account_service.dart`.
- Reglas puras, en el núcleo (`packages/vinabike_public_core`):
  `customer_portal_presentation.dart`, `customer_portal_plans.dart`,
  `customer_portal_snapshot.dart`, `customer_bike_drawing_geometry.dart`,
  `portal_time_zone.dart`.
- HTML: `services/storefront_html/lib/src/portal_page_view.dart` (la vista),
  `portal_page_css.dart`, `portal_page_script.dart` y
  `portal_page_route.dart` (`/cuenta/vista`, `/cuenta/archivo`,
  `/cuenta/accion`); el perfil y las direcciones en `portal_forms_view.dart`;
  lecturas en `SupabasePublicReads.customerPortal`, escrituras en
  `customerWrite` y `customerAuth`; la búsqueda de Maps en `places_script.dart`
  (la misma del checkout).
- El login en HTML: `login_page_view.dart`, `login_page_css.dart`,
  `login_page_script.dart`; `check` y `enter` en `portal_page_route.dart`, el
  alta en `SupabasePublicReads.customerEnter`.
- Reglas de los formularios en el núcleo: `customer_portal_forms.dart`,
  `customer_auth_forms.dart`, `self_password_rules.dart`,
  `customer_address.dart`, `auth_input_validation.dart`.
- Tablas: `customers` (`auth_user_id`), `customer_addresses`, `online_orders`, `mechanic_jobs`, `bikes`.
- El QR y la cuenta: `claim_page_view.dart`, `claim_page_script.dart`,
  palabras en `customer_claim_words.dart`; `claim-peek` y `claim` en
  `portal_page_route.dart`. El comprobante: `delivery_document_pdf_route.dart`
  y el PDF compartido con el ERP, `delivery_warranty_pdf.dart`.
- El teléfono: `phone-send` y `phone-confirm` en `portal_page_route.dart`,
  el diálogo en `portal_forms_view.dart` (`_phoneDialog`), palabras en
  `customer_phone_words.dart`; la función `customer-phone-verification` y la
  plantilla en `supabase/functions/_shared/whatsapp_templates.ts`.
- Tablas del QR y del teléfono: `customer_portal_claim_codes`,
  `customer_portal_claim_attempts`, `customer_portal_phone_verifications`
  (sólo hash), `customer_portal_verified_phones`.
- Superficie registrada: fila «Customer portal» de `canonical-ui-surfaces.md`.
