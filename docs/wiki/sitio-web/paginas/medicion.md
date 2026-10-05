---
titulo: Medición (GA4, píxel de Meta y consolas)
resumen: qué eventos manda la tienda a Google Analytics, con qué datos, qué falta del embudo recomendado y cómo leer las consolas
fuentes: [ga4, consolas-google, repositorio, web-dev]
archivos: [scripts/sync_seo_index.sh, services/storefront_html/tool/measure.mjs, lib/public_store/services/ga4_commerce_events.dart, lib/public_store/services/ga4_bridge_web.dart, lib/public_store/services/meta_pixel_service.dart, lib/public_store/widgets/public_store_bootstrap.dart]
tablas: [website_settings]
revisado: 2026-10-05
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

Las herramientas que abren el sitio real con un navegador bloquean Google
Analytics y el píxel de Meta (`services/storefront_html/tool/measure.mjs`): cada
carga abre un perfil nuevo y contaría como un usuario más. Un script nuevo de
un agente que abra vinabike.cl hace lo mismo con
`context.route(/(google-analytics\.com|googletagmanager\.com|analytics\.google\.com|connect\.facebook\.net|facebook\.com\/tr)/, (r) => r.abort())`.

## Eventos que se mandan

| Evento | Cuándo | Parámetros |
|---|---|---|
| `view_item` | se abre una ficha | `currency` CLP, `value`, `items` |
| `add_to_cart` | se agrega al carrito | `currency`, `value` (precio × cantidad), `items` |
| `begin_checkout` | se entra al checkout | `currency`, `value`, `items` |
| `purchase` | se confirma un pedido | `transaction_id` (id del pedido: GA4 descarta una segunda compra con el mismo id), `currency`, `value`, `items` |
| `contact` | clic que saca al cliente para hablar con el local | `method`: `whatsapp`, `phone`, `email` o `directions` (mapa) |
| `store_ready` | la tienda Flutter dibujó su primer cuadro armada | `value` (segundos), `load_ms`, `load_bucket`: `bueno_hasta_2_5s`, `mejorable_hasta_4s`, `lento_hasta_8s`, `muy_lento_mas_de_8s` (umbrales de LCP) |

`[Repo]` `[WD]`

`store_ready` existe porque el LCP del navegador no sirve en Flutter: el lienzo no
es candidato y el LCP que reporta es el logo ([rendimiento](rendimiento.md)).
`load_bucket` está registrado como dimensión personalizada «Tramo de carga» (24-sep)
`[Consola]`.

## Lo que falta del embudo recomendado

GA4 recomienda `view_item_list`, `select_item`, `remove_from_cart`, `view_cart`,
`add_shipping_info` y `add_payment_info` además de los que mandamos `[GA]`. Sin
ellos no se ve qué listado vende ni dónde se abandona el checkout (envío o pago).
Agregarlos va en el mismo dueño.

## Eventos clave

`purchase` ya es evento clave en GA4; `contact` hay que marcarlo con la estrella
(no aparecía para marcar el 24-sep: un evento nuevo tarda ~24 h) `[Consola]` `[GA]`.

## Píxel de Meta

El código existe (`meta_pixel_service.dart`: `ViewContent`, `AddToCart`,
`InitiateCheckout`, `Purchase`) pero **está apagado**: `seo_fb_pixel_id` está vacío
(2026-10-03) `[Prod]`. Si se activa, no duplicar eventos ni mandar datos
personales.

## Consolas

Search Console, GA4 y Merchant se leen en el Chrome del dueño con la cuenta de
Viñabike (`/u/2`); trampas y mediciones archivadas en la
[ficha de consolas](../fuentes/consolas-google.md).

## Tarea programada

`vinabike-store-ready-review` (8-oct-2026, 10:00 local) lee `store_ready` por
tramo y recomienda si conviene la tienda HTML ([rendimiento](rendimiento.md)).

## Trampas

- Mandar `purchase` sin `transaction_id` o dos veces con ids distintos para el
  mismo pedido (infla ventas).
- Un evento con nombre propio no entra a los informes de comercio de GA4.
- Medir rendimiento con el LCP del navegador en una página Flutter.

## En el código y la base

- Eventos: `ga4_commerce_events.dart` (y `ga4_bridge_web.dart` que llama a `gtag`).
- Píxel: `meta_pixel_service.dart`, ID en `seo_fb_pixel_id`; GA en `seo_ga_id`
  (lo carga `public_store_bootstrap.dart`).
