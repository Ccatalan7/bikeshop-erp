---
titulo: Portal de clientes
resumen: lo que ve un cliente con cuenta en /cuenta — pedidos, taller, bicis, soporte — cómo entra, cómo se ve y qué sigue pendiente
fuentes: [repositorio]
archivos: [services/storefront_html/lib/src/portal_page_view.dart, services/storefront_html/lib/src/portal_forms_view.dart, services/storefront_html/lib/src/portal_page_route.dart, packages/vinabike_public_core/lib/public_store/models/customer_portal_forms.dart, packages/vinabike_public_core/lib/public_store/models/customer_portal_plans.dart, packages/vinabike_public_core/lib/public_store/models/customer_portal_snapshot.dart, packages/vinabike_public_core/lib/public_store/models/customer_portal_presentation.dart, lib/public_store/pages/customer_dashboard_page.dart, lib/public_store/pages/customer_orders_page.dart, lib/public_store/pages/customer_service_history_page.dart, lib/public_store/pages/customer_bikes_page.dart, lib/public_store/pages/customer_chat_hub_page.dart, lib/public_store/pages/customer_auth_page.dart, lib/public_store/widgets/customer_portal_style.dart, lib/public_store/widgets/customer_portal_layout.dart, lib/public_store/services/customer_account_service.dart]
tablas: [customers, bikes, mechanic_jobs, online_orders, website_settings]
revisado: 2026-10-06
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
| `/cuenta/servicios` | `customer_service_history_page.dart` | trabajos del taller; `?bike_id=` filtra por bici |
| `/cuenta/bicicletas` | `customer_bikes_page.dart` | sus bicis (dibujadas por tipo: 0 de 472 bicis tienen foto) |
| `/cuenta/chats`, `/cuenta/chats/:id` | `customer_chat_hub_page.dart` (con la conversación abierta en `:id`) | soporte |
| `/cuenta/perfil`, `/cuenta/direcciones` | `customer_profile_page.dart`, `customer_addresses_page.dart` | datos y direcciones |
| `/cuenta/login` | `customer_auth_page.dart` | entrar o crear cuenta |
| `/cuenta/descargas/android` | `android_app_download_page.dart` | la app Android |
| `/cuenta/mensajes`, `/cuenta/mensajes/:id` | redirigen a `/cuenta/chats` y `/cuenta/chats/:id` (2026-10-07) | enlaces viejos del chat |

Todas llevan `noindex` por cabecera ([rutas](rutas-y-navegacion.md)).

## En HTML desde el 2026-10-06

`/cuenta`, `/cuenta/pedidos`, `/cuenta/servicios` y `/cuenta/bicicletas` las
responde el servidor HTML, y desde la fase 4b también `/cuenta/perfil` y
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
no tiene verificador y queda el aviso «Tu cuenta ha sido confirmada». Lo que
termina en fijar una contraseña (recuperación: verificador marcado con
`/passwordRecovery`; invitación; un token en el fragmento) y la vuelta de
Google del editor (su intención `google_oauth_editor_intent` en este
navegador) vuelven al servidor con `?enlace=1`, que responde Flutter.
Antes de llamar a Auth el servidor revisa los campos (`check`); la contraseña
no le llega, sólo su forma (cada letra, número o signo cambiado por uno de su
tipo), que es todo lo que miran las reglas. Con la sesión, `enter` crea o
confirma el cliente de la tienda; si no puede serlo, la sesión se cierra y
dice lo mismo que Flutter. Un enlace del correo (recuperar, invitación,
confirmar con `code`, un error) lo responde Flutter: el servidor lo ve en la
dirección, y si viene en el fragmento la página lo devuelve con `?enlace=1`
antes de pintar. Al terminar una recuperación o una invitación Flutter vuelve
a `/cuenta/login?clave=…`, y el login HTML dice lo que Flutter decía.
Arreglado en las dos tiendas (2026-10-06): el teléfono escrito al crear la
cuenta se perdía si había que confirmar el correo (1 de 7 cuentas); ahora se
guarda al entrar si el cliente no tiene. El gris del panel de la izquierda
llega al fondo de la tarjeta `[Repo 2026-10-06]`.

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
- Superficie registrada: fila «Customer portal» de `canonical-ui-surfaces.md`.
