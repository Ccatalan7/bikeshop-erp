---
titulo: Rutas, redirecciones y navegación
resumen: cada URL pública de vinabike.cl, cuáles indexa Google, las redirecciones de URL viejas, el 404 y los menús
fuentes: [repositorio, google-search-central]
archivos: [lib/public_store/routes/public_store_router.dart, firebase.json, web/robots.txt, packages/vinabike_public_core/lib/public_store/utils/product_url.dart, services/storefront_html/lib/src/storefront_handler.dart]
tablas: [website_navigation, website_pages, product_categories, product_url_aliases]
revisado: 2026-10-05
---

# Rutas, redirecciones y navegación

## Lo esencial

La tienda usa rutas limpias con la History API (sin `#`), que es lo que Google
sabe seguir `[GSC]`. Desde el 2026-10-05, la portada `/`, `/productos`, sus
categorías, las fichas, `/producto/<uuid>`, `/servicios` (y sus categorías),
`/contacto` y las páginas de información
(`/nosotros`, `/envios`, `/devoluciones`, `/terminos`, `/privacidad`) las
responde el **servidor HTML** (Cloud Run
`storefront-html`, reescrituras del target `store` en `firebase.json`): su 404 y
sus 301 son respuestas reales del servidor `[Repo]`. Toda otra ruta desconocida
Firebase la reescribe a `app.html` (la página de Flutter; no se llama
`index.html` para que `/` sea del servidor) y Flutter la resuelve en
`public_store_router.dart`; ahí el 404 lo decide la app, y una ruta inexistente
responde «Página no encontrada» con `noindex` para no ser un soft 404 `[Repo]`
`[GSC]`. Flutter sólo arranca en el checkout, la cuenta y el portal (el
carrito es del servidor desde el 2026-10-06); un clic suyo hacia una ruta del servidor hace una carga completa
(`storefrontHtmlServes` en el núcleo, comparada con `firebase.json` por una
prueba), salvo en el editor, su vista previa y `/tienda` `[Repo]`.

## Rutas públicas (tienda)

| Ruta | Qué es | ¿Indexable? |
|---|---|---|
| `/` | portada (página CMS `inicio`); la dibuja el servidor HTML y, si tiene un bloque que el HTML aún no dibuja, responde la página de Flutter con la cabeza de la portada | sí |
| `/productos` | catálogo raíz | sí |
| `/productos/categoria/:category` | categoría de productos (slug limpio) | sí, si está publicada y tiene productos elegibles |
| `/productos/:slug/:sku` | **ficha canónica** de un producto | sí |
| `/productos/:id`, `/producto/:id` | ficha por UUID (histórica): 301 a la ficha canónica (Hosting o el servidor HTML) | no |
| `/servicios` | servicios del taller (59 publicados, 2026-10-05): el mismo catálogo que `/productos` con `p_product_type = service`, dibujado por el servidor HTML; cada servicio en el JSON-LD con su precio | sí |
| `/servicios/categoria/:category` | categoría de servicios (servidor HTML) | sí, con las mismas reglas |
| `/pagina/:slug` | página CMS dinámica | según su publicación |
| `/contacto`, `/nosotros`, `/terminos`, `/privacidad`, `/devoluciones`, `/envios` | páginas fijas con su página CMS, todas dibujadas por el servidor HTML; las cinco de información sin nada que leer y `/contacto` sin publicar responden 404 con `noindex`. `/contacto` muestra los datos de Configuración (correo, teléfono, dirección, WhatsApp, redes, horario, Maps) y un formulario que abre un correo a la tienda | sí, si su página está publicada (y, las de información, tienen algo que leer); si no, `noindex,follow` |
| `/carrito` | carrito; lo dibuja el servidor HTML y sus líneas llegan de `/carrito/lineas` (JSON, `no-store`) | no (`X-Robots-Tag` y meta) |
| `/checkout` | compra (Flutter); la versión HTML está en `/_html/checkout` y sus líneas en `/checkout/lineas` (JSON, `no-store`) hasta abrirla | no (`X-Robots-Tag` y meta) |
| `/pedido/:id` | confirmación de un pedido (con token de acceso) | no |
| `/cuenta`, `/cuenta/login`, `/cuenta/perfil`, `/cuenta/direcciones`, `/cuenta/pedidos`, `/cuenta/bicicletas`, `/cuenta/servicios`, `/cuenta/chats`, `/cuenta/chats/:id`, `/cuenta/mensajes`, `/cuenta/mensajes/:id`, `/cuenta/descargas/android` | portal de clientes ([portal-de-clientes](portal-de-clientes.md)) | no |
| `/auth/callback` | vuelta del inicio de sesión | no |
| `/shop/:slug` | URL de la tienda vieja | redirige 301 |
| (cualquier otra) | «Página no encontrada» | no |

`[Repo: public_store_router.dart, firebase.json, 2026-10-05]`

**`/tienda/*`** repite todas las rutas para la tienda montada **dentro del ERP**
(el editor la usa para editar en vivo). En el target público, `/tienda` y
`/tienda/**` llevan `noindex` y una ruta `/tienda/*` desconocida vuelve a la ruta
pública `[Repo]`.

## Redirecciones (`firebase.json`, target `store`)

1.668 reglas, todas 301 salvo una (2026-10-03) `[Prod]`:
- 1.542 de URL de producto viejas o alias a la ficha canónica; las genera el
  build (`scripts/generated_product_redirects.json`) a partir de
  `product_url_aliases`; en vivo, `resolve_public_product_url_alias` sólo
  resuelve un alias de un producto activo, publicado, visible en la web y de
  tipo `product`;
- 125 de `/shop/*` (la tienda anterior);
- `/app/open` se reescribe a `web/app-open.html`, la página puente del enlace
  compartido a la app.

Una redirección 301 es la señal de canonical más fuerte que existe `[GSC]`;
cambiar un slug sin alias rompe ese hilo.

## Lo que Google no debe indexar

`X-Robots-Tag: noindex, nofollow, noarchive` a nivel de respuesta en `/carrito`,
`/checkout`, `/pedido`, `/pedido/**`, `/cuenta`, `/cuenta/**`, `/auth/**`,
`/tienda`, `/tienda/**` `[Prod]`. Va en la cabecera porque el `noindex` dentro de
la app llega tarde: Google puede no renderizar una página cuyo HTML original ya
dice otra cosa `[GSC]`.

`robots.txt` además bloquea `/cuenta/` y `/pedido/`, **y se queda así**
(decidido 2026-10-04, corrige la propuesta del 2026-10-03 de quitarlo). Es cierto
que Google no lee el `noindex` de una URL bloqueada y que una URL bloqueada y
enlazada puede salir como resultado sin contenido `[GSC]`. Pero `/pedido/<id>`
lleva el token de acceso al pedido: con el bloqueo, el rastreador nunca abre ni
renderiza el detalle de un pedido aunque alguien filtre el enlace, y la cabecera
sigue cubriendo a quien llegue sin pasar por robots.txt. Ninguna de esas URL
está enlazada desde páginas públicas. El test
`google_merchant_identity_contract_test.dart` exige las dos líneas.

## Tienda en HTML (fase 1)

El servidor HTML (`services/storefront_html`) responde `/productos`,
`/productos/categoria/<slug>`, `/productos/<slug>/<sku>`, `/productos/<uuid>` y
`/producto/<uuid>`: primero bajo `/_html/...` con `noindex` (2026-10-05), y
desde ese mismo día en las rutas públicas, con el sí del dueño al costo
([rendimiento](rendimiento.md)) `[Repo]` `[Dueño 2026-10-05]`. Firebase
Hosting resuelve primero sus 301 exactos (`redirects`, los genera el build),
después un archivo estático y recién después la reescritura: por eso el
generador ya no escribe instantáneas bajo esas rutas y el build falla si queda
un archivo ahí (`SeoServerRenderedRoutes` en
`scripts/generate_product_seo_snapshots.dart`, que lee las reescrituras de
`firebase.json`; quitar una reescritura devuelve las instantáneas en el build
siguiente). `/tienda/producto/<uuid>` sigue como instantánea `noindex` que
manda a la ficha. Lo que decide cada ruta es el mismo código que usa Flutter
(`packages/vinabike_public_core`), con estas respuestas de servidor que
Flutter sólo podía imitar en el navegador:

- **301** a la ficha canónica cuando el nombre en la ruta no es el del producto
  (manda el SKU), desde `/productos/<uuid>`, `/producto/<uuid>` y desde una ruta
  vieja de `product_url_aliases`; la consulta se conserva. Un slug viejo de
  categoría (alias de «Catálogo web») y el viejo `/productos?category=<id>`
  también redirigen a la ruta limpia. Los enlaces de menús y bloques
  guardados así ya salen escritos con la ruta limpia
  (`StorefrontShell.categoryHref`), sin pasar por el 301.
- **404** con la página de la tienda para una categoría desconocida o no
  publicada («Esta colección no está disponible») y para un producto que no se
  ve (borrador, sin foto con la regla «exigir foto»). Flutter respondía 200 con
  `noindex`.
- `noindex,follow` (meta y `X-Robots-Tag`) para búsqueda, orden, página y
  filtros, incluidos los técnicos (`spec.<clave>`), con la canónica limpia.
- Las fichas cuyo SKU tiene un espacio (5 el 2026-10-05, p. ej. `RDM41 LD`)
  recibían de Firebase la portada con su título, porque la instantánea del
  build no calzaba con la ruta codificada; el servidor HTML las sirve bien
  `[Prod 2026-10-05]`.

## Menús y destinos

- Encabezado y pie salen de `website_navigation` (`Estructura > Navegación y
  menús`); un botón de campaña no es un ítem de menú.
- `Estructura > Destinos y enlaces` audita a dónde lleva cada botón y menú.
- Las categorías del menú se muestran según la publicación real de la
  categoría (`Catálogo web > Categorías`).
- Pendiente del dueño: la tarjeta «MOUNTAIN BIKE» de la portada enlaza a Cadenas
  (2026-09-24).

## Trampas

- Rutas con `#`: Google no las resuelve `[GSC]`.
- Cambiar el slug de un producto o categoría sin alias: se pierde la URL que
  Google tenía.
- Un `/tienda/...` en un enlace público: es la ruta del ERP, no la de la tienda.

## En el código y la base

- Router: `lib/public_store/routes/public_store_router.dart` (y
  `deferred_commerce_routes.dart`, `deferred_customer_routes.dart` para lo que se
  carga diferido); URL de producto: `packages/vinabike_public_core/lib/public_store/utils/product_url.dart` y
  la función `product_public_url_path`.
- Cabeceras y redirecciones: `firebase.json` (target `store`); robots:
  `web/robots.txt` (el build lo reescribe).
- Menús: `website_navigation`; páginas: `website_pages`; categorías:
  `product_categories`.
