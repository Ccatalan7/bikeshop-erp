# Página instantánea de la tienda

**Estado:** construida y medida en local el 2026-09-24; **no está en
producción**. Espera la trazabilidad de sus valores visuales a Design (ver
«Trazabilidad visual»). Cubre fichas y categorías; portada, catálogo raíz y
resto de las rutas siguen sólo con Flutter.

## Por qué existe

En un móvil lento (1,6 Mbps, 150 ms, CPU ×4) la tienda Flutter aparece a los
~20 s: antes baja ~1,3 MB de `main.dart.js` y ~1,6 MB de CanvasKit. Hasta
entonces el visitante veía sólo el logo, y el LCP que medía Google era ese logo
(PageSpeed móvil de la portada: 26, LCP 16,8 s, 2026-09-24). La página
instantánea muestra la ficha o la categoría con el primer paint, desde el HTML
que el generador de snapshots ya escribe para cada ruta, y Flutter la retira
cuando dibujó la suya.

Es la evolución HTML-first que permite `.github/copilot-instructions.md`
(«HTML-first storefront evolution is allowed»): un **consumidor**, nunca un
segundo dueño de contenido.

## Medición (2026-09-24)

Mismo build local, Chrome headless con red de 1,6 Mbps / 150 ms, CPU ×4 y
412×823, perfil nuevo por carga, cabeceras de caché iguales a `firebase.json`,
mediana de 3 cargas; «sin» es la misma página sin la plantilla:

| | Primer contenido | LCP | Tienda lista (`store_ready`) | Traspaso |
|---|---|---|---|---|
| Ficha, sin | 0,4 s (logo) | 0,5 s (logo) | 21,0 s | — |
| Ficha, con | 0,27 s | 2,6 s (foto) | 20,9 s | 22,3 s |
| Categoría, sin | 0,4 s (logo) | 0,5 s (logo) | 20,3 s | — |
| Categoría, con | 0,26 s | 0,26 s (título) | 20,3 s | 22,0 s |
| Categoría, con, escritorio 1366×900 | 0,36 s | 0,36 s (título) | 21,1 s | 23,1 s |

La tienda no llega más tarde. Lo que costaba ~1 s era el logo del
encabezado (PNG de 3300×887, 104 KB), que la instantánea bajaba en los
primeros segundos: se reemplazó por un WebP sin pérdida de 1000 px (15 KB),
que usa también la tienda.

## Dueño → control → operación → consumidores

| Dato | Dueño | Control | Consumidor instantáneo |
|---|---|---|---|
| Nombre, fotos, precio, SKU | `products` | Ficha del producto en el ERP | `buildSeoInstantProductTemplate`, vía `PublicCommerceProductProjection` (la misma proyección que la ficha Flutter) |
| Portada de la categoría (título, descripción, imagen, altura, velo, alineación) | `product_categories` + `WebsiteCatalogPresentation` | Catálogo web › Categorías › Presentación | `buildSeoInstantCategoryTemplate` |
| Colores y fuente de títulos | `website_settings` `theme_*` | Editor web › Tema | `SeoInstantPageTheme` (mismo lector de color que `WebsiteResolvedTheme`: `parseWebsiteThemeColorValue`) |
| Logo | `website_settings` `logo_url` → `tenants.logo_url` → empaquetado (sólo tienda canónica) | Editor web › Encabezado | `storefrontFirstLogoSource`, el mismo orden que `StorefrontLogoResolution` |

Nada de esto se edita en la instantánea ni tiene copia propia: se regenera en
cada build de la tienda.

## Rutas

- **Con instantánea:** `/productos/<slug>/<sku>` y
  `/productos/categoria/<slug>`.
- **Sin ella (Flutter solo, splash con logo):** portada, `/productos`,
  `/servicios`, páginas del CMS, carrito, checkout, cuenta y todo lo demás.
- La categoría muestra la portada real y, bajo 700 px, una **grilla
  reservada**, no productos: qué productos van primero lo decide la consulta
  de la tienda (orden, política de stock, tamaño de página según el ancho),
  que la instantánea no replica. Replicarla daría un reordenamiento visible al
  traspaso.
- Desde 700 px `ProductCatalogPage` pone los filtros en una columna lateral
  de 236 px y la grilla a su derecha. Una grilla a todo el ancho saltaría al
  traspaso (medido a 1366×900: empezaba ~90 px más abajo y 300 px más a la
  izquierda), así que bajo la portada queda el fondo y Flutter llena ese
  espacio vacío sin mover nada de lo que ya estaba.

## Traspaso

1. El generador inserta en cada snapshot `<template id="instant-page-template">`
   antes de `#app-shell`, el tema como `<style id="instant-page-theme">` y un
   `preload` de la foto principal con prioridad alta. Quita el `preload` del
   logo del splash y lo vuelve `lazy`: la instantánea lo tapa, y no debe
   competir con la foto.
2. Un script inline de `web/index.html` clona la plantilla en `#instant-page`
   (capa fija encima del splash) y expone `window.vinabikeInstantPage`
   (`release`, `arm`).
3. `PublicStoreBootstrap` oculta el splash como siempre; `hideHtmlLoadingScreen`
   además llama `arm()`, que retira la instantánea a los 8 s si la ruta nunca
   avisa. Un error de arranque la retira de inmediato.
4. La ruta avisa con `releaseInstantPageWhenReady`: la ficha cuando tiene el
   producto (o sabe que no existe) **y** su foto principal está decodificada
   (máx. 1,5 s); el catálogo cuando dejó de cargar. La retirada ocurre después
   de ese frame, con un fundido de 200 ms, y el nodo se elimina del DOM (no
   queda un duplicado oculto para lectores de pantalla ni para el render de
   Google).

La instantánea no tiene botones de compra, carrito ni búsqueda: nada
interactivo que no funcione hasta que Flutter tome el control. Sus enlaces
(logo) son navegaciones reales.

## Frescura

El snapshot se genera en cada build (push a `main` y diario 05:00 Chile), así
que puede tener hasta un día.

- **Precio:** nace neutro (`data-ip-state="pending"`, un espacio del alto de
  precio + nota). El script relee por la API pública los campos que lo
  deciden (`seoInstantFreshnessFields`: `website_price`, `price`) y sólo lo
  muestra si su firma coincide con la del build. Sin respuesta, con error o
  distinto, queda neutro hasta que Flutter dibuja el vigente. Verificado en el
  navegador con la API real (se muestra), una conexión que nunca responde, una
  rechazada y un 401 (neutro en los tres).
- **Stock:** no se muestra. `get_public_products` descuenta las reservas
  vigentes de pedidos web (`online_order_inventory_reservations`), y una
  reserva puede agotar un producto sin cambiar ningún campo de la fila.
- **Ficha retirada:** la lectura anónima de `products` sólo ve fichas
  activas, publicadas y en la web (política `public_products_select`). Una
  respuesta vacía es una ficha retirada después del build: la instantánea se
  retira y vuelve el splash.
- **Lo que no se revalida:** el nombre y la foto de una ficha que sigue
  publicada (hasta un día de antigüedad, igual que el `<noscript>`), la
  portada de una categoría despublicada o renombrada después del build, y el
  precio de una ficha sin SKU (`/productos/<id>`), que queda neutro (0
  fichas publicadas sin SKU en Viñabike el 2026-09-24: caso residual).

La normalización de la firma está dos veces —`seoInstantFreshnessSignature`
en Dart y `norm` en `web/index.html`— y la prueba
`storefront_instant_page_test` exige que lean los mismos campos.

## SEO y medición

- Las fuentes se resuelven con `WebsiteFontRegistry`, como la tienda: sólo
  Oswald y Barlow; cualquier otro valor de `theme_heading_font` o
  `theme_body_font` cae en la de omisión. `web/index.html` declara ambas con
  los mismos archivos que `pubspec.yaml`.
- Oswald va sólo en peso 400: `pubspec.yaml` registra `Oswald-wght.ttf` para
  400–700 sin variar el eje, así que la tienda dibuja la instancia 400 y
  engruesa las negritas. Con el rango 200–700 el navegador usaba la negrita
  real, ~10 % más ancha, y el título cortaba en otra línea que la ficha.
- Un texto sin familia propia en la tienda hereda la de cuerpo (Barlow). El
  título de la portada de categoría pide 900; sin archivo 900, Flutter y el
  navegador usan el ExtraBold. Con la fuente del sistema, «CADENAS» medía
  otro ancho y saltaba al traspaso.
- La plantilla es inerte para quien no ejecuta JavaScript; el `<noscript>`
  sigue siendo el contenido para rastreadores sin JS. Usa `role="heading"` y
  `role="main"`, así cada snapshot mantiene un solo `<h1>` y un solo `<main>`
  (lo valida el generador).
- Con JavaScript, el LCP pasa a ser la foto o el título de la instantánea.
  `store_ready` sigue midiendo cuándo Flutter está listo.
- `window.vinabikeInstantPageReleased` guarda el motivo y el instante de la
  retirada, para medir el traspaso en el navegador.

## Trazabilidad visual

`AGENTS.md` exige que todo valor visual nuevo venga de un archivo de Design
leído con `DesignSync`. El 2026-09-24 eso no fue posible: en la sesión no
interactiva `DesignSync get_project` sobre `a0fa3196-…` respondió «needs
design-system authorization, and /design-login cannot run in this
non-interactive session», y no queda copia local de la guía
(`DESIGN_HANDOFF_SYNC_CONTRACT.md`). Ningún valor de la instantánea está
acreditado en Design:

- **Espejo de la tienda** (copiados del código Flutter, que tampoco acredita
  la fuente): alto y paddings del encabezado y tamaño del logo
  (`PublicStoreHeaderGeometry`), escenario de la foto
  (`_productImageStageHeight`), tipografía y tamaños de título y precio de la
  ficha, portada de la categoría (`CatalogCollectionPresentationHeader`), y
  los colores `theme_*` del tema publicado.
- **Propios de la instantánea**: la barra de progreso bajo el encabezado, los
  esqueletos (radio 6 px, tono `--ip-soft` al 7 % del texto, pulso de 1,4 s,
  proporciones de las líneas) y el tono secundario `--ip-secondary`.

No se despliega hasta que el dueño corra `/design-login` desde un `claude`
interactivo y cada valor se compare con `GUÍA GENERAL Viñabike -
Componentes` (en particular, si la guía ya tiene un estado de carga que
reemplace los esqueletos y la barra).

### Carrusel en teléfono: las flechas tapan el texto y no se ocultan

En un teléfono las flechas del carrusel (46×46 px, centradas en el alto)
tapan el texto del slide. Moverlas exige medidas nuevas, así que quedaron en
su lugar hasta Design. Se evaluó (2026-09-24) ocultarlas sólo en
`WebsiteViewport.mobile` cuando hay puntos (`showIndicators`, el caso del
único carrusel público de hoy), dejando deslizar y puntos, sin ninguna medida
nueva. **Se descartó por accesibilidad**, medido con una prueba de widget a
375 px:

- Cada punto mide 22×22 con paso de 22 px, pero sólo toma el toque el
  círculo de 12 px (el `GestureDetector` delega la prueba de toque en el
  hijo): un toque a 5 px del centro cambia el slide; a 7 px, no.
- WCAG 2.2, 2.5.8 (AA) pide 24×24 px o que círculos de 24 px centrados en
  cada objetivo no se toquen; con 12 px a 22 px de paso se tocan. Hoy se
  cumple por la excepción de **control equivalente**: las flechas de 46 px
  hacen lo mismo. Sin flechas, el único control de un toque serían los
  puntos (deslizar no cuenta: 2.5.1 pide una alternativa de un solo puntero).
- Agrandar el toque de los puntos a su caja (`HitTestBehavior.opaque`) no
  alcanza: 22 px con paso de 22 siguen fallando; llegar a 24 es una medida
  nueva.
- Ni puntos ni flechas tienen etiqueta ni rol de botón para un lector de
  pantalla (defecto previo, aparte de éste).

El arreglo necesita valores de Design: el tamaño de toque de los puntos o la
posición de las flechas en teléfono.

## Revisión independiente (Codex, 2026-09-24)

| Hallazgo | Resolución |
|---|---|
| Precio y stock visibles sin verificar | Precio neutro hasta verificar; stock fuera |
| Ficha retirada sigue a la vista | Se retira con una lectura vacía |
| Logo roto si falla `logo_url` | Se oculta; el encabezado Flutter prueba los siguientes |
| `aria-busy` nunca vuelve a `false` | Quitado: la región no es una actualización en curso |
| Fuente no declarada (Barlow) o no admitida | Registro de la tienda + `@font-face` de Barlow |
| Arrastre lento no cambia el slide; en el editor sí | Cuarto del ancho o `kMinFlingVelocity`; sin gesto con `editBinding` |
| `arm()` sólo lo llama Flutter: si no arranca, queda encima | Sin cambio: antes quedaba el splash igual de indefinido |
| El validador cuenta el `<h1>`/`<main>` del `<noscript>` | Sin cambio: valida el snapshot sin JS, como antes de este cambio |
| Categoría y nombre/foto sin revalidar | Documentado en «Frescura» |

## Rollback

Quitar la llamada a `injectSeoInstantPage` en el generador y publicar: sin
plantilla, el script no hace nada y la tienda vuelve al splash. No hay datos ni
migraciones involucrados.

## Verificación

- Local: `test/unit/storefront_instant_page_test.dart`, el validador del
  generador y un build con snapshots reales medido con Chrome headless
  limitado (1,6 Mbps / 150 ms / CPU ×4) contra el mismo build sin plantilla.
- Para probar un cambio de `web/index.html` sin recompilar no basta copiarlo
  a `build/web_store/index.html`: el build reemplaza `$FLUTTER_BASE_HREF` y
  **pega `flutter_bootstrap.js` en `{{flutter_bootstrap_js}}`**. Con el
  marcador sin reemplazar Flutter nunca arranca y la instantánea se queda
  encima sin error visible (costó una medición de 90 s).
- Producción: PageSpeed móvil de una ficha y una categoría, el traspaso visto
  en un teléfono (sin cuadro en blanco ni salto de contenido) y el evento
  `store_ready` sin cambios de tendencia.
