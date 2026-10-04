---
titulo: Rutas, redirecciones y navegación
resumen: cada URL pública de vinabike.cl, cuáles indexa Google, las redirecciones de URL viejas, el 404 y los menús
fuentes: [repositorio, google-search-central]
archivos: [lib/public_store/routes/public_store_router.dart, firebase.json, web/robots.txt, lib/public_store/utils/product_url.dart]
tablas: [website_navigation, website_pages, product_categories, product_url_aliases]
revisado: 2026-10-04
---

# Rutas, redirecciones y navegación

## Lo esencial

La tienda usa rutas limpias con la History API (sin `#`), que es lo que Google
sabe seguir `[GSC]`. Firebase reescribe toda ruta desconocida a `index.html` y
Flutter la resuelve en `public_store_router.dart`; por eso el 404 real lo decide
la app, y una ruta inexistente responde «Página no encontrada» con `noindex`
para no ser un soft 404 `[Repo]` `[GSC]`.

## Rutas públicas (tienda)

| Ruta | Qué es | ¿Indexable? |
|---|---|---|
| `/` | portada (página CMS `inicio`) | sí |
| `/productos` | catálogo raíz | sí |
| `/productos/categoria/:category` | categoría de productos (slug limpio) | sí, si está publicada y tiene productos elegibles |
| `/productos/:slug/:sku` | **ficha canónica** de un producto | sí |
| `/productos/:id`, `/producto/:id` | ficha por UUID (histórica): el snapshot apunta al canonical | no (canonical a la ficha) |
| `/servicios` | servicios del taller (57 con precio, 2026-09-23) | sí |
| `/servicios/categoria/:category` | categoría de servicios | sí, con las mismas reglas |
| `/pagina/:slug` | página CMS dinámica | según su publicación |
| `/contacto`, `/nosotros`, `/terminos`, `/privacidad`, `/devoluciones`, `/envios` | páginas fijas con su página CMS | sí, si su página está publicada; si no, `noindex,follow` |
| `/carrito`, `/checkout` | compra | no (`X-Robots-Tag`) |
| `/pedido/:id` | confirmación de un pedido (con token de acceso) | no |
| `/cuenta`, `/cuenta/login`, `/cuenta/perfil`, `/cuenta/direcciones`, `/cuenta/pedidos`, `/cuenta/bicicletas`, `/cuenta/servicios`, `/cuenta/chats`, `/cuenta/chats/:id`, `/cuenta/mensajes`, `/cuenta/mensajes/:id`, `/cuenta/descargas/android` | portal de clientes ([portal-de-clientes](portal-de-clientes.md)) | no |
| `/auth/callback` | vuelta del inicio de sesión | no |
| `/shop/:slug` | URL de la tienda vieja | redirige 301 |
| (cualquier otra) | «Página no encontrada» | no |

`[Repo: public_store_router.dart, firebase.json, 2026-10-03]`

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
  carga diferido); URL de producto: `lib/public_store/utils/product_url.dart` y
  la función `product_public_url_path`.
- Cabeceras y redirecciones: `firebase.json` (target `store`); robots:
  `web/robots.txt` (el build lo reescribe).
- Menús: `website_navigation`; páginas: `website_pages`; categorías:
  `product_categories`.
