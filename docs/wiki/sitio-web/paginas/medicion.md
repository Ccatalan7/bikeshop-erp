---
titulo: Medición (GA4, píxel de Meta y consolas)
resumen: qué eventos manda la tienda a Google Analytics, con qué datos, qué falta del embudo recomendado, cómo leer las consolas y el seguimiento diario de la presencia en Google dentro del ERP
fuentes: [ga4, consolas-google, repositorio, web-dev]
archivos: [supabase/functions/web-presence-collect/index.ts, supabase/functions/_shared/web_presence.ts, lib/modules/website/presence/presence_controller.dart, scripts/sync_seo_index.sh, services/storefront_html/tool/measure.mjs, services/storefront_html/lib/src/storefront_script.dart, services/storefront_html/lib/src/cart_page_view.dart, services/storefront_html/lib/src/checkout_page_script.dart, services/storefront_html/lib/src/product_card.dart, lib/public_store/services/ga4_commerce_events.dart, lib/public_store/services/ga4_bridge_web.dart, lib/public_store/services/meta_pixel_service.dart, lib/public_store/widgets/public_store_bootstrap.dart]
tablas: [website_settings, web_presence_search_daily, web_presence_search_terms, web_presence_urls, web_presence_index_daily, web_presence_traffic_daily, web_presence_notes, web_presence_runs]
revisado: 2026-10-14
---

# Medición (GA4, píxel de Meta y consolas)

## Lo esencial

La tienda manda eventos a GA4 (flujo web `G-FR5Q37BW43`, el ID se guarda en
`seo_ga_id`) a través de `gtag`, desde un solo dueño:
`lib/public_store/services/ga4_commerce_events.dart` `[Repo]`.

## Quién cuenta como visita (2026-10-04)

Sólo el dominio de la tienda. Hasta el 2026-10-04 el ERP web
(`project-vinabike.web.app`), los dominios por defecto de Firebase, las vistas
previas y `localhost` cargaban la misma etiqueta (`G-FR5Q37BW43`), porque se
construyen desde la misma página (`web/index.html`, generada por
`scripts/sync_seo_index.sh`). Cada vez que alguien abría el ERP en el
navegador, o un agente probaba la tienda en local, GA4 lo contaba como un
usuario de vinabike.cl. El dueño lo notó en el pico de fines de septiembre
`[Dueño 2026-10-04]`. Desde entonces el fragmento de GA4 se activa sólo si el
host, sin `www.`, es el de `store_url`; en otro host `gtag()` existe igual y los
eventos de la app se encolan sin enviarse. Los filtros de GA4 no son
retroactivos: para ver lo anterior sin ese ruido, se filtra por la dimensión
«Nombre de host» = `vinabike.cl`.

**«Seattle, Estados Unidos» somos nosotros.** GA4 ubica en Seattle la conexión
del Mac del dueño, y con ella todo lo que corre ahí: su Chrome, Claude in
Chrome, el navegador integrado y los Playwright de los agentes. Prueba: todas
las vistas en `localhost` y `127.0.0.1` (sólo pueden salir de ese Mac; ningún
flujo de CI abre el sitio en un navegador) están en Seattle. Del 6-sep al 3-oct
`[Consola 2026-10-04]`:

| Origen | Vistas | Parte |
|---|---|---|
| Total | 1.185 | 100 % |
| Fuera de vinabike.cl (`localhost` 128, `127.0.0.1` 85, ERP web 63, otros 3) | 279 | 24 % |
| vinabike.cl desde Estados Unidos (casi todo Seattle) | 515 | 43 % |
| vinabike.cl desde Chile y otros países | 391 | 33 % |

El «pico» del 24-sep, y el aviso de GA4 «United States traffic surge» (de 4 a 86
vistas en una semana), fue nuestro: ese día se publicó el portal por etapas y la
portada instantánea, y casi todas las vistas de `/cuenta/*` son de Seattle. El
arreglo de dominio de arriba no quita esas visitas, porque son del dominio real.
Para leer clientes, comparar con País = Chile o excluir la ciudad Seattle.

**Marca por navegador (2026-10-05).** Para que esas visitas dejen de contarse,
cada navegador propio se marca una vez abriendo cualquier dirección de la
tienda con `?sin_medir` (por ejemplo `https://vinabike.cl/?sin_medir`); la
página confirma con un aviso abajo y quita el parámetro de la dirección.
`?medir` saca la marca. Desde ahí ese navegador no carga Google Analytics ni
el píxel de Meta, en ninguna página. La marca es la cookie `vb_sin_medir` del
dominio (cubre `www.`; 400 días, el máximo de Chrome) más una copia en
`localStorage`, y cada visita la renueva. Safari borra en 7 días lo que
escribe un script si el sitio no se visita: en un iPhone que pasó una semana
sin abrir la tienda, se vuelve a abrir el enlace. Cada navegador y cada teléfono es aparte; los Playwright de
los agentes abren perfiles nuevos y por eso bloquean la analítica en el
script (abajo). Lo anterior a la marca no se corrige: GA4 no es retroactivo
`[Repo]` `[Dueño 2026-10-05]`.

**La marca la lee el navegador, nunca el servidor** (2026-10-05). Firebase
Hosting borra toda cookie salvo `__session` antes de reenviar una petición a
Cloud Run, así que la tienda HTML no ve `vb_sin_medir`: escribe la etiqueta y
su script (el mismo de `index.html`) revisa la marca antes de cargar nada. La
fase 0 la leía también en el servidor; ese camino nunca funcionaba detrás de
Hosting y se quitó `[Repo]` `[firebase.google.com/docs/hosting/manage-cache]`.
La tienda HTML manda los mismos eventos que Flutter (`view_item`,
`add_to_cart`, `contact`, `store_ready`), y desde el 2026-10-07 también el
resto del embudo recomendado (abajo); nunca mide en la ruta oculta `/_html`
ni en la vista HTML del editor.

Las herramientas que abren el sitio real con un navegador bloquean Google
Analytics y el píxel de Meta (`services/storefront_html/tool/measure.mjs`): cada
carga abre un perfil nuevo y contaría como un usuario más. Un script nuevo de
un agente que abra vinabike.cl hace lo mismo con
`context.route(/(google-analytics\.com|googletagmanager\.com|analytics\.google\.com|connect\.facebook\.net|facebook\.com\/tr)/, (r) => r.abort())`.
El navegador integrado de la app de Claude, en cambio, guarda su perfil: quedó
marcado con `?sin_medir` el 2026-10-29, antes de recorrer el carro y el pago
para los pantallazos de «Lo que te toca». Antes de recorrerlos otra vez, se
confirma en la consola que `window.vinabikeMeasurementAllowed` es `false`; el
carro que se arma para mirar se borra después de su `localStorage`. En
`localhost` la tienda nunca mide (sólo mide en el dominio de la tienda)
`[Repo]` `[Prod 2026-10-29]`.

## Eventos que se mandan

| Evento | Cuándo | Parámetros |
|---|---|---|
| `view_item` | se abre una ficha | `currency` CLP, `value`, `items` |
| `add_to_cart` | se agrega al carrito | `currency`, `value` (precio × cantidad), `items` |
| `view_item_list` | se muestra una lista de tarjetas: el catálogo y sus categorías (`productos`, `servicios` o el id de la categoría), un bloque de productos (`bloque-<id>`), los relacionados (`relacionados`), una capa de producto del lienzo (`lienzo-<id>`); una copia que una banda esconde no cuenta | `item_list_id`, `item_list_name` (el título que ve el cliente), `items` con su `index` |
| `select_item` | se abre una tarjeta de esas listas; en el buscador del encabezado, un producto o servicio sugerido (`item_list_id` `buscador`) | lo mismo, con la tarjeta abierta |
| `search` | el buscador del encabezado se envía o se pide «Ver los N productos» (HTML, 2026-10-24) | `search_term` |
| `view_cart` | `/carrito` muestra sus líneas (una vez por visita) | `currency`, `value`, `items` |
| `add_to_cart` / `remove_from_cart` | en `/carrito`, una unidad más o menos, una línea eliminada, o «Agregar» en «Te puede faltar» (2026-10-24) | `currency`, `value`, `items` con la cantidad que cambió |
| `begin_checkout` | se entra al checkout | `currency`, `value`, `items` |
| `add_shipping_info` | el cliente dice dónde se entrega: elige retiro o una dirección (sugerida o guardada), o al confirmar si la dejó como venía | `shipping_tier` `despacho` o `retiro`, `currency`, `value`, `items` |
| `add_payment_info` | el cliente elige cómo pagar, o al confirmar si dejó el medio que venía marcado | `payment_type` `mercadopago` o `transfer`, `currency`, `value`, `items` |
| `purchase` | se confirma un pedido | `transaction_id` (id del pedido: GA4 descarta una segunda compra con el mismo id), `currency`, `value`, `items` |
| `contact` | clic que saca al cliente para hablar con el local; desde el 2026-10-24 también una pregunta de la ficha enviada por el chat del portal | `method`: `whatsapp`, `phone`, `email`, `directions` (mapa) o `chat`; desde una ficha («Pregunta por este producto»), `item_id` (SKU) e `item_name` |
| `store_ready` | la tienda Flutter dibujó su primer cuadro armada | `value` (segundos), `load_ms`, `load_bucket`: `bueno_hasta_2_5s`, `mejorable_hasta_4s`, `lento_hasta_8s`, `muy_lento_mas_de_8s` (umbrales de LCP) |

`[Repo]` `[WD]`

`store_ready` existe porque el LCP del navegador no sirve en Flutter: el lienzo no
es candidato y el LCP que reporta es el logo ([rendimiento](rendimiento.md)).
`load_bucket` está registrado como dimensión personalizada «Tramo de carga» (24-sep)
`[Consola]`.

## El embudo recomendado, completo (2026-10-07)

GA4 recomienda `view_item_list`, `select_item`, `remove_from_cart`, `view_cart`,
`add_shipping_info` y `add_payment_info` además de los que ya mandábamos `[GA]`.
Faltaban, y sin ellos no se veía qué listado vende ni dónde se abandona el
checkout (envío o pago). Desde el 2026-10-07 los manda la tienda HTML, que es
donde están hoy el catálogo, el carrito y el checkout: el script de la tienda
(`storefront_script.dart`, las listas por `data-list-id` y las tarjetas por
`data-item-id`), el del carrito (`cart_page_view.dart`) y el del checkout
(`checkout_page_script.dart`). El `item_id` es el SKU (el id sin SKU), igual
que `view_item`, para que GA4 junte el producto de punta a punta. Probado en
la tienda local de prueba con un `gtag` falso: el recorrido completo, de la
lista al medio de pago. `ga4_commerce_events.dart` (Flutter) no los manda: la
app ya no dibuja esas páginas a un cliente `[Repo]`. Al ver los informes, un
evento nuevo tarda ~24 h en aparecer.

## Eventos clave

`purchase` ya es evento clave en GA4; `contact` hay que marcarlo con la estrella
(no aparecía para marcar el 24-sep: un evento nuevo tarda ~24 h) `[Consola]` `[GA]`.

## Píxel de Meta

El código existe (`meta_pixel_service.dart`: `ViewContent`, `AddToCart`,
`InitiateCheckout`, `Purchase`) pero **está apagado**: `seo_fb_pixel_id` está vacío
(2026-10-03) `[Prod]`. Si se activa, no duplicar eventos ni mandar datos
personales.

## Presencia en internet: las cifras de Google en el ERP (2026-10-14)

El dueño pidió seguir «todas esas métricas» dentro del ERP y analizarlas cada
cierto tiempo contra lo que vamos cambiando `[Dueño 2026-10-14]`. Desde ese día
no hay que entrar a las consolas para saber cómo vamos:

- **Quién trae las cifras:** la función `web-presence-collect` lee Search
  Console y Analytics con la cuenta de servicio de Viñabike (la misma de
  Merchant, ya con acceso total a Search Console) y guarda en las tablas
  `web_presence_*` ([mapa](mapa-del-sistema.md)). pg_cron la llama todos los
  días a las 09:23 UTC (`collect`: búsquedas por día, consultas y páginas por
  día, el sitemap, Analytics y el registro de este wiki) y cada dos horas a los
  41 (`inspect`: ~80 direcciones del sitemap por la inspección de URLs). El
  secreto del job vive en Vault (`web_presence_collect_secret`) y en la
  función (`WEB_PRESENCE_COLLECT_SECRET`), nunca en el texto del job. Todo es
  gratis: las dos APIs de Google no cobran y la función corre en el plan.
- **Dónde se ve:** `Sitio Web › Presencia en internet` (`/website/presence`):
  seis cifras del período contra el anterior del mismo largo, el gráfico día
  a día con los cambios del registro marcados debajo, consultas y páginas con
  los lugares ganados, la indexación del sitemap por estado (cada estado abre
  sus direcciones), visitas por canal y el embudo, y la bitácora. «Actualizar»
  pide una recolección en el momento.
- **Lo que se recolecta:** Search Console guarda 16 meses; la primera carga
  trajo desde el 2025-07-23 (448 días, 5.521 filas de consultas y 10.463 de
  páginas, en 57 s). Cada día se vuelven a pedir los últimos 4 días porque
  Google los corrige.
- **El análisis periódico:** la tarea `vinabike-presencia-semanal` (lunes en
  la mañana de Chile) lee estas tablas, relaciona los movimientos con los
  cambios de la semana y deja su nota `analisis` en `web_presence_notes`, que
  la bitácora del portal muestra.
- **Analytics conectado el 2026-10-23:** el dueño agregó la cuenta de
  servicio como Lector (Viewer) de la propiedad 498064152, sin aviso por
  correo: una cuenta de servicio no tiene buzón. Lector basta para leer
  informes; si algún día el ERP tiene que crear un evento clave o una
  dimensión, se sube a Editor. La primera lectura trajo desde el 19-sep-2025
  (1.539 filas: 629 de Chile y 910 del sitio) `[Prod 2026-10-23]`.
- **La tarea semanal no corrió nunca** (0 ejecuciones al 2026-10-23, tampoco
  la medición única de las guías del 16-oct): las tareas programadas del Mac
  esperan un permiso la primera vez. Hay que abrirla en la app de Claude
  (Programadas) y darle «Run now» una vez `[Consola 2026-10-23]`.

Trampas que costaron una vuelta al armarlo:

- El período termina en el **último día que Search Console tiene** (2–3 días
  de atraso), no hoy; si no, la mitad reciente sale vacía y todo «baja».
- `supabase-dart` ordena **descendente** si no se le dice
  `ascending: true`: la primera versión mostró julio de 2025 como «los
  últimos 28 días». El controlador además ordena lo que recibe.
- Una inspección de URL tarda ~7 s; con 6 a la vez entran ~80 por llamada y
  ~1.000 al día, bajo el tope de 2.000 por propiedad. La foto de indexación se
  guarda al final de cada llamada aunque quede poco tiempo.
- El total «enviado» del sitemap que da Search Console suma también las
  **imágenes**: se cuentan sólo las entradas `web` (2.467 → 1.283).
- Analytics se filtra por `hostName` (con y sin `www.`) y, en «Sólo Chile»,
  por país: sin eso cuentan las visitas del propio Mac (Seattle).
- En la app de debug, una lectura a veces no responde o vuelve 400 «Project
  not specified» del portal de Supabase; cada lectura del portal tiene límite
  de 15 s y un reintento, y cada bloque carga por su cuenta.

## Consolas

Search Console, GA4 y Merchant se leen en el Chrome del dueño con la cuenta de
Viñabike (`/u/2`); trampas y mediciones archivadas en la
[ficha de consolas](../fuentes/consolas-google.md).

## Tareas programadas

- `vinabike-presencia-semanal` (lunes 05:30 hora del Mac, 09:30 de Chile,
  desde el 2026-10-19): análisis semanal de la presencia en internet (arriba).
- `vinabike-store-ready-review` (8-oct-2026, 10:00 local, ya corrió) leyó
  `store_ready` por tramo y recomendó la tienda HTML ([rendimiento](rendimiento.md)).

## Trampas

- Mandar `purchase` sin `transaction_id` o dos veces con ids distintos para el
  mismo pedido (infla ventas).
- Un evento con nombre propio no entra a los informes de comercio de GA4.
- Medir rendimiento con el LCP del navegador en una página Flutter.
- Leer en el servidor una cookie que puso la página: detrás de Firebase Hosting
  sólo llega `__session`.

## En el código y la base

- Presencia: `supabase/functions/web-presence-collect/index.ts` (recolector),
  `supabase/functions/_shared/web_presence.ts` (sitemap, registro del wiki,
  ventanas de días, resumen de indexación; pruebas Deno al lado),
  `supabase/functions/_shared/google_service_account.ts` (token de la cuenta
  de servicio), `supabase/migrations/20261014150000_web_presence.sql` (tablas,
  `web_presence_terms_v1`, `web_presence_save_settings_v1`,
  `invoke_web_presence_collect` y los dos jobs), `lib/modules/website/presence/`
  (portal) y `test/widgets/website_presence_page_test.dart`.

- Eventos: `ga4_commerce_events.dart` (y `ga4_bridge_web.dart` que llama a `gtag`).
- Píxel: `meta_pixel_service.dart`, ID en `seo_fb_pixel_id`; GA en `seo_ga_id`
  (lo carga `public_store_bootstrap.dart`).
