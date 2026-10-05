---
titulo: Estado y pendientes
resumen: qué está en vivo hoy, qué falta y de quién depende — la lista de trabajo del sitio, con fecha
fuentes: [repositorio, consolas-google, google-search-central]
archivos: [supabase/migrations/20260728223000_harden_website_navigation_seed.sql, supabase/migrations/20260728230000_add_storefront_publication_contract.sql, docs/architecture/storefront-instant-page.md, docs/architecture/storefront-html-migration-plan.md]
tablas: [website_navigation, website_settings, products, online_shipping_rate_tiers]
revisado: 2026-10-05
---

# Estado y pendientes

Se actualiza cada vez que algo cambia de estado; cada línea con su fecha.

## En vivo (2026-10-03) `[Prod]`

- Build de la tienda: commit `c4ed2fde`, `built_at` 2026-10-04T05:20:54Z
  (`release.json`).
- Sitemap: 1.315 URL. La tienda lista 539 productos con stock y 59 servicios.
- Checkout con Mercado Pago y transferencia funcionando (desde el 2026-09-23).
- Página instantánea en fichas, categorías y portada; semántica para rastreadores.
- Merchant: suspendido («Información engañosa»), en período de bloqueo.

## Depende del dueño

| Desde | Qué | Por qué |
|---|---|---|
| 2026-09-23 | Crear una cuenta de Google Ads (gratis, sin campaña) y pasar su ID | el formulario de soporte de Merchant no avanza sin él ([merchant](merchant-y-perfil-de-google.md)) |
| 2026-09-23 | Ficha de Google: fotos, horario, pedir reseñas | reputación entra en la revisión de Merchant |
| 2026-09-24 | Fotos de 16 productos antiguos | sin foto no se listan |
| 2026-09-24 | Tarjeta «MOUNTAIN BIKE» de la portada enlaza a Cadenas | contenido del editor |
| 2026-09-24 | Crear la GitHub App (APP_ID, INSTALLATION_ID, llave privada) | sin ella «Publicar» del editor no puede disparar el build ([publicacion](publicacion-y-despliegue.md)) |
| 2026-09-24 | Marcar `contact` como evento clave en GA4 | es una configuración de la cuenta |
| 2026-09-23 | Reconectar la cuenta Google del ERP con el permiso de Search Console | el centro SEO no ve Google hasta entonces |

## Lo puede hacer un agente

El plan de SEO completo, medido contra los referentes y ordenado por impacto, está
en [seo-de-referentes](seo-de-referentes.md); lo que sigue es la lista de trabajo.

| Desde | Qué | Página |
|---|---|---|
| 2026-10-04 | **Contenido real y visible en el HTML** de fichas, categorías y portada (hoy en `<noscript>`, ~100–150 palabras contra 700–2.500 de los referentes). Si el dueño aprueba la migración a HTML, la fase 1 lo resuelve y no se completa la página instantánea | [seo-de-referentes](seo-de-referentes.md) |
| 2026-10-04 | **Descripciones de producto**: 29 de 1.541 publicados tienen texto; el JSON-LD y la página no tienen qué mostrar en el resto (contenido, no marcado) | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | Términos de devolución (días, quién paga, reembolso) como campos del editor, para declararlos además del link (regla 1: primero el control) | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | Los tramos de envío no tienen control en el editor y la página `/envios` los repite como texto: un cambio de tarifa hay que hacerlo en dos lados. Llevarlos al editor y que la página los lea de `get_public_online_shipping_tiers` | [checkout](checkout-y-pedidos.md) |
| 2026-10-04 | `geo` del local y `addressCountry` como `CL` (hoy «Chile»; `seo_address_country_code` sin dueño) | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | Textos de presentación de las 11 categorías visibles | [seo-de-referentes](seo-de-referentes.md) |
| 2026-10-04 | Artículos/guías en el editor (capacidad nueva) y páginas de aterrizaje de filtros | [seo-de-referentes](seo-de-referentes.md) |
| 2026-10-04 | Ver en vivo los correos de pago, preparación, retiro, envío y entrega: ningún pedido real los ha disparado (la última venta web pagada es del 3-may) | [checkout](checkout-y-pedidos.md) |
| 2026-10-04 | Avisar al taller por correo o WhatsApp cuando entra un pedido web (hoy sólo el aviso dentro del ERP) | [checkout](checkout-y-pedidos.md) |
| 2026-10-03 | Eventos GA4 que faltan: `view_item_list`, `select_item`, `remove_from_cart`, `view_cart`, `add_shipping_info`, `add_payment_info` | [medicion](medicion.md) |
| 2026-10-03 | Comparar Search Console contra la línea base del 23-sep (filtrada al sitemap) y mirar `/servicios` | [seo-tecnico](seo-tecnico.md) |
| 2026-09-24 | Carrusel en teléfono: las flechas tapan el texto (antes esperaba Design; desde el 27-sep el aspecto lo decide el agente) | `storefront-instant-page.md` |
| 2026-09-24 | La tienda llama `get_public_store_data` directo además de usar la precarga (sin investigar) | [rendimiento](rendimiento.md) |
| 2026-09-24 | Imágenes pesadas: campaña de cámaras en PNG de 2 MB, WebP de 312 KB en la grilla de categorías | [rendimiento](rendimiento.md) |
| 2026-09-26 | Login `/cuenta/login` sin la dirección «Sendero» | [portal](portal-de-clientes.md) |
| 2026-10-03 | Código muerto: `banners_management_page.dart`, `content_management_page.dart`, `customer_account_page.dart`, `premium_dashboard_widgets.dart`, ruta `/cuenta/mensajes`; clave `header_nav_links` | [editor](editor-del-sitio.md) |
| 2026-10-08 | Leer el resultado de la tarea `vinabike-store-ready-review` | [rendimiento](rendimiento.md) |
| 2026-10-04 | **Fase 0 de la migración a HTML:** anotar el costo mensual real de Cloud Run (`storefront-html`) después de unos días; lo demás está hecho y medido ([rendimiento](rendimiento.md)) | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-05 | Precalcular los valores técnicos de las facetas (`spec_public_facet_values_internal_v1`, ~270 ms de los ~410 ms de `get_public_product_facets_v2` en cada visita al catálogo, Flutter y HTML) | [rendimiento](rendimiento.md) |
| 2026-10-05 | Regla de limpieza de imágenes viejas en Artifact Registry (cada despliegue del servidor HTML guarda 5,5 MB; la cuota gratis es 0,5 GB) | `storefront-html-migration-plan.md` |
| 2026-10-04 | Paridad latente de la ficha técnica: el generador de snapshots arma la identidad con `color`, `size`, `material` y `weight` leídos de `products`, y la página pública no los recibe; un producto que los tenga mostraría en el snapshot filas que la página no. 0 productos afectados hoy | [datos-estructurados](datos-estructurados.md) |

## Hecho

| Fecha | Qué | Página |
|---|---|---|
| 2026-10-05 | **Miniaturas de tarjeta** (opción gratis que eligió el dueño): copias de 400 y 800 px de las 1.294 fotos de tarjeta en `public_image_thumbnails`, hechas por `generate_public_image_thumbnails.dart` en cada publicación; las tarjetas HTML las ofrecen en `srcset` (120 KB → 20 KB por foto en un teléfono). Un producto sin SKU se dibuja en `/productos/<uuid>` (`get_public_product_page_v2`) | [rendimiento](rendimiento.md) |
| 2026-10-05 | **Rutas públicas abiertas a la tienda HTML** con el sí del dueño al costo (alerta de presupuesto de CLP 4.800 ≈ US$5): `/productos`, categorías, fichas y `/producto/<uuid>` las responde Cloud Run; el build deja de escribir sus instantáneas (`SeoServerRenderedRoutes`) y la publicación de la tienda revisa el servidor en los dos orígenes, incluida su fuente (`check_storefront_html_routes.mjs`). Las 5 fichas con espacio en el SKU, que la instantánea servía con la portada, quedan bien | [rutas](rutas-y-navegacion.md) |
| 2026-10-05 | **Fase 1 de la migración a HTML** en la ruta oculta: `/productos`, categorías y fichas con encabezado, pie, carrito compatible con Flutter, GA4/píxel, `noindex`/canónica/301/404; las 1.290 fichas comparables idénticas a la instantánea Flutter (las otras 5 son un defecto de la instantánea) y las 12 colecciones salvo el orden de su lista; revisión de Codex (1 P1, 4 P2, 1 P3) corregida con pruebas. Requisitos de la fase 0 resueltos: ficha técnica en una pasada (`20261005090000`), `BikeStore`, menús, submenús, set availability en la lectura | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-05 | Filtros técnicos `spec.<clave>` en la URL ahora son `noindex` también en Flutter; categorías con nombre repetido abren igual en Flutter y HTML (regla en el núcleo) | [catalogo](catalogo-y-fichas.md) |
| 2026-10-04 | Servidor HTML en Cloud Run (`storefront-html`, `southamerica-east1`) detrás de la reescritura `/_html/**` del target `store`. El dueño instaló `gcloud`, inició sesión y dio `roles/run.builder` a la cuenta de compilación | [mapa](mapa-del-sistema.md) |
| 2026-10-04 | El dueño aprobó la migración del sitio y su editor a HTML. Fase 0 en local y en la base: núcleo Dart en `packages/vinabike_public_core` (18 archivos movidos, sin copiar), `get_public_storefront_shell_v1` + `get_public_product_page_v1` desplegadas y verificadas (`20261004180000`, `20261004190000` tras la revisión de Codex), servidor Jaspr con pruebas | [mapa](mapa-del-sistema.md) |
| 2026-10-04 | Ficha técnica (`additionalProperty`), `model` y migas completas en el JSON-LD de cada producto, con un solo armado para el snapshot y la página | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | `BikeStore` con logo, imagen, mapa, horario y link a la política de devoluciones. El envío se dejó fuera: Google no puede acotar «Chile continental» | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | El script que evita la doble navegación de un enlace de Flutter llega por fin a producción (estaba sólo en `web/index.html`, que el build regenera) | [publicacion](publicacion-y-despliegue.md) |
| 2026-10-04 | Descartado: quitar `Disallow` de `/pedido/` en `robots.txt`. Esas URL llevan el token privado del pedido; con el bloqueo Google nunca las abre, y la cabecera `noindex` cubre el caso de que alguna se filtre | [rutas](rutas-y-navegacion.md) |

## Migraciones en git, no en producción

| Migración | Estado | Efecto |
|---|---|---|
| `20260728223000_harden_website_navigation_seed` | `NOT_APPLIED` (2026-10-03) | el editor llama `ensure_default_footer_navigation` (`website_service.dart:4350`) y esa función no existe en producción |
| `20260728230000_add_storefront_publication_contract` | `NOT_APPLIED` (2026-10-03) | registro de publicaciones del editor; espera la GitHub App |

Antes de aplicarlas: revisar si otra migración posterior ya tocó lo mismo (una
migración vieja no se aplica tal cual; ver «Schema changes» en
`docs/development/AGENT_DATABASE_CONTRACT.md`).

## En el código y la base

- Lo vivo: `https://vinabike.cl/release.json`, el `sitemap.xml` y
  `scripts/db/query.sh production`; migraciones: `scripts/db/migration_status.sh`.
- Cada fila apunta a la página del tema, que tiene sus archivos y tablas.
