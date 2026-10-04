---
titulo: Portal de clientes
resumen: lo que ve un cliente con cuenta en /cuenta — pedidos, taller, bicis, soporte — cómo entra, cómo se ve y qué sigue pendiente
fuentes: [repositorio]
archivos: [lib/public_store/pages/customer_dashboard_page.dart, lib/public_store/pages/customer_orders_page.dart, lib/public_store/pages/customer_service_history_page.dart, lib/public_store/pages/customer_bikes_page.dart, lib/public_store/pages/customer_chat_hub_page.dart, lib/public_store/pages/customer_auth_page.dart, lib/public_store/widgets/customer_portal_style.dart, lib/public_store/widgets/customer_portal_layout.dart, lib/public_store/models/customer_portal_presentation.dart, lib/public_store/services/customer_account_service.dart]
tablas: [customers, bikes, mechanic_jobs, online_orders, website_settings]
revisado: 2026-10-03
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
| `/cuenta/chats`, `/cuenta/chats/:id` | `customer_chat_hub_page.dart`, `customer_chat_detail_page.dart` | soporte |
| `/cuenta/perfil`, `/cuenta/direcciones` | `customer_profile_page.dart`, `customer_addresses_page.dart` | datos y direcciones |
| `/cuenta/login` | `customer_auth_page.dart` | entrar o crear cuenta |
| `/cuenta/descargas/android` | `android_app_download_page.dart` | la app Android |
| `/cuenta/mensajes`, `/cuenta/mensajes/:id` | `customer_chat_list_page.dart` (legado) | rutas viejas del chat |

Todas llevan `noindex` por cabecera ([rutas](rutas-y-navegacion.md)).

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

- El login `/cuenta/login` (1.411 líneas) no pasó por «Sendero».
- Código muerto: `customer_account_page.dart`, `premium_dashboard_widgets.dart` y
  la ruta legado `/cuenta/mensajes` (`customer_chat_list_page.dart`).
- Para mirar el portal sin sesión (un agente no ingresa contraseñas):
  `test/widgets/customer_portal_pages_test.dart`.

## En el código y la base

- Estilo y piezas: `customer_portal_style.dart`, `customer_portal_layout.dart`,
  `customer_job_row.dart`, `customer_order_row.dart`, `customer_bike_card.dart`,
  `customer_bike_drawing.dart`; reglas puras en
  `customer_portal_presentation.dart`; datos en `customer_account_service.dart`.
- Tablas: `customers` (`auth_user_id`), `online_orders`, `mechanic_jobs`, `bikes`.
- Superficie registrada: fila «Customer portal» de `canonical-ui-surfaces.md`.
