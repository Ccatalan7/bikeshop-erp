---
titulo: Mapa del sistema
resumen: de punta a punta, quién es dueño de qué — editor, base, funciones, build, hosting, borde y navegador — con los nombres exactos de archivos, tablas y funciones
fuentes: [repositorio]
archivos: [lib/main_store.dart, services/storefront_html/lib/src/storefront_handler.dart, packages/vinabike_public_core/pubspec.yaml, lib/public_store/routes/public_store_router.dart, lib/public_store/widgets/public_store_bootstrap.dart, lib/modules/website/services/website_service.dart, lib/modules/website/services/website_save_coordinator.dart, scripts/generate_product_seo_snapshots.dart, scripts/sync_seo_index.sh, scripts/check_storefront_bundle_budget.sh, scripts/write_storefront_release_evidence.sh, .github/workflows/firebase-hosting-store.yml, firebase.json, web/index.html, cloudflare-worker/src/index.js]
tablas: [website_settings, website_pages, website_blocks, website_navigation, website_content, website_banners, website_backups, featured_products, products, product_categories, online_orders, online_order_items, online_shipping_rate_tiers]
revisado: 2026-10-04
---

# Mapa del sistema

## La cadena completa

```text
ERP (editor del sitio, ficha de producto, catálogo web)
  │  guarda en Supabase (tablas website_*, products, product_categories…)
  ▼
Supabase (Postgres + RLS + funciones públicas + Edge Functions)
  │                                   │
  │ build de la tienda (GitHub Actions)│ datos en vivo para la app
  ▼                                   ▼
HTML por ruta + sitemap + redirecciones   Cloudflare Worker (caché 5 min de
  + main.dart.js (Flutter)                get_public_store_data)
  ▼                                   │
Firebase Hosting, target `store` ─────┴──► navegador del visitante:
  vinabike.cl y vinabike-store.web.app      1) HTML instantáneo  2) Flutter toma la página
```

`[Repo]` `[Prod 2026-10-03]`

## Dos apps, dos destinos de hosting

| | ERP (incluye el editor del sitio) | Tienda pública |
|---|---|---|
| Entrada Dart | `lib/main.dart` | `lib/main_store.dart` |
| Build | `build/web_erp` | `build/web_store` |
| Target de Firebase | `erp` (`project-vinabike.web.app`) | `store` (`vinabike.cl`, `vinabike-store.web.app`), con 1.668 redirecciones y 44 reglas de cabeceras en `firebase.json` (2026-10-03) |
| Workflow | `firebase-hosting-merge.yml` | `firebase-hosting-store.yml` |

El ERP también monta la tienda dentro de sí en `/tienda/*` para editarla en vivo
([rutas-y-navegacion](rutas-y-navegacion.md)) `[Repo]`.

**Tercera pieza, en migración (fase 0, 2026-10-04):** el servidor HTML
`services/storefront_html/` (Dart con Jaspr y `shelf`) arma la ficha en cada
visita desde `get_public_storefront_shell_v1` y `get_public_product_page_v1`,
con el mismo código Dart que la tienda Flutter: el paquete
`packages/vinabike_public_core` (proyección comercial, ficha técnica, texto SEO,
datos estructurados, rutas de categoría y menú, tema, horario). En la fase 0 no
reemplaza ninguna ruta pública: va a vivir en Cloud Run (`southamerica-east1`)
detrás de `/_html/**` en el target `store`, con `noindex`. Plan y fases en
`docs/architecture/storefront-html-migration-plan.md` `[Repo]`.

## Dueños de datos (Supabase, `public`)

| Tabla | Qué guarda | Quién la edita |
|---|---|---|
| `website_settings` | clave/valor por empresa: marca y tema (`theme_*`, `header_*`, logo), SEO del sitio (`seo_*`, `meta_*`, `store_url`), contacto y negocio, pagos (`payment_*`, `mercadopago_*`), integraciones Google y WhatsApp, política de catálogo (`product_visibility_*`); 231 claves (2026-10-03) | `Configuración`, `Tema`, `SEO`, `Integraciones` del editor; `website_setting_is_sensitive` decide qué no se publica |
| `website_pages` | páginas CMS: `inicio`, `productos`, `servicios`, `contacto`, `nosotros`, `terminos`, `privacidad`, `devoluciones`, `envios` (9, todas publicadas, 2026-10-03) | `Estructura > Páginas` |
| `website_blocks` | bloques de cada página (carruseles, Canvas, grillas…), 36 filas aprox. | lienzo e inspector del editor; reemplazo atómico con `replace_page_blocks` |
| `website_navigation` | menús de encabezado y pie | `Estructura > Navegación y menús` |
| `website_content`, `website_banners` | contenido y banners heredados | editor (historia) |
| `featured_products` | colección destacada | `Catálogo web > Portada` |
| `website_backups` | respaldos del sitio | `WebsiteBackupService` |
| `products`, `product_categories` | catálogo; `show_on_website`, textos y SEO por producto, presentación de categoría | ficha del producto en el ERP y `Catálogo web` |
| `online_shipping_rate_tiers` | tramos de despacho por total del pedido (4 activos, $6.990 a $14.990, 3–12 días hábiles; 2026-10-04): lo que cobra `quote_online_shipping_internal` | sólo personal y sin control en el editor (pendiente); lectura pública con `get_public_online_shipping_tiers`, que todavía nadie usa (la usará `/envios`) |
| `online_orders`, `online_order_items` y `online_order_*` | pedidos web, pagos, reservas de stock, documentos, correcciones, tokens de acceso | checkout público + `Sitio Web > Pedidos online` |

## Lo que un visitante sin cuenta puede llamar

Funciones `SECURITY DEFINER` de lectura pública (todas filtran por empresa y
devuelven sólo lo publicable) `[Prod 2026-10-03]`:
`get_public_store_data` (configuración pública y bloques de la portada en un solo viaje; es lo que cachea el Worker),
`get_public_products`, `get_public_products_faceted_v2`,
`get_public_product_facets_v2`, `get_public_product_category_counts`,
`get_public_featured_products`, `get_public_product_technical_specs`,
`get_public_spec_option_labels_v1`, `get_public_product_tax_classifications`,
`search_public_products`, `resolve_public_product_url_alias`,
`get_public_checkout_capabilities`, `quote_public_online_shipping`,
`get_public_online_shipping_tiers` (2026-10-04),
`get_public_storefront_shell_v1` y `get_public_product_page_v1` (2026-10-04:
`SECURITY INVOKER`, componen las de arriba en una lectura por página para el
servidor HTML),
`create_public_online_order_with_access`,
`get_public_online_order_by_access_token`. Las versiones `_v1` de facetas y
productos siguen por compatibilidad. Detalle en [seguridad](seguridad.md).

## Edge Functions del sitio (`supabase/functions/`)

| Función | Para qué |
|---|---|
| `google-merchant-feed` | feed de productos para Merchant Center (misma proyección pública y regla de impuestos del checkout) |
| `google-product-diagnostics` | revisa cómo se ve una ficha pública desde fuera (con borde anti-SSRF) |
| `google-places-proxy` | autocompletado de direcciones del checkout para visitantes sin cuenta |
| `google-business-reviews` | proxy de la API de Google Business Profile (reseñas) |
| `google-public-data-refresh` | refresca datos públicos de Google (reseñas, Places) que muestra el sitio |
| `google-oauth-callback` | conexión Google del ERP (centro SEO, Merchant) |
| `dispatch-storefront-publication` | publicar la tienda desde el editor vía GitHub; **no activa**: falta la GitHub App y su migración no está aplicada ([publicacion-y-despliegue](publicacion-y-despliegue.md)) |
| `mercadopago-create-preference`, `mercadopago-webhook`, `mercadopago-get-payment`, `mercadopago-refund-payment`, `mercadopago-expire-preferences` | pago con Mercado Pago de punta a punta ([checkout-y-pedidos](checkout-y-pedidos.md)) |
| `send-transactional-order-email`, `resend-transactional-webhook` | correos del pedido (Resend) y sus eventos |
| `website-optimize-image`, `website-remove-background` | imágenes del editor: versión web optimizada y quitar fondo |

## El build de la tienda (`firebase-hosting-store.yml`)

1. `scripts/sync_seo_index.sh` escribe en `web/index.html` los datos SEO del
   sitio (título, descripción, OG, GA) leídos de la base.
2. `flutter build web --release -t lib/main_store.dart -o build/web_store`.
3. `scripts/check_storefront_bundle_budget.sh` (techo: 7,3 MB crudos, 1,95 MB
   gzip, diferidos 3,6 MB) — falla el build si se pasa.
4. `sync_seo_index.sh --check`: si alguien guardó en el editor durante el build,
   se aborta en vez de publicar mezclado.
5. `scripts/generate_product_seo_snapshots.dart`: HTML por ficha, categoría y
   página, `sitemap.xml`, `robots.txt` y redirecciones de URL viejas
   ([seo-tecnico](seo-tecnico.md)); completa el nodo `BikeStore` (logo, horario,
   devoluciones) y declara la ficha técnica de cada producto ([datos-estructurados](datos-estructurados.md)).
6. Verifica los activos generados, sella la revisión, escribe `release.json`
   (`scripts/write_storefront_release_evidence.sh`), despliega el target `store`
   y comprueba la evidencia en los dos orígenes.

Disparadores: push a `main` que toque `lib/**`, `web/**`, el generador o
`firebase.json`; el cron diario `0 8 * * *` (hora pedida, llega tarde); y
`workflow_dispatch` `[Repo]`.

## En el navegador

1. `web/index.html` (con lo que inyectó el build) pinta la **página
   instantánea** de esa ruta y precarga los datos desde el Worker
   (`window.flutter_injected_preloaded_data`) ([rendimiento](rendimiento.md)).
2. `flutter_bootstrap.js` baja `main.dart.js` y CanvasKit; `lib/main_store.dart`
   arranca, `WebsiteService` toma la precarga (`lib/shared/utils/web_data_bridge.dart`)
   y `public_store_router.dart` resuelve la ruta.
3. Flutter dibuja su versión y retira la instantánea; GA4 recibe `store_ready`
   ([medicion](medicion.md)).

## En el código y la base

- Tienda: `lib/public_store/` (páginas, servicios, rutas, tema). Editor:
  `lib/modules/website/` (páginas de administración, servicios, modelos de
  bloques). Las dos comparten `lib/shared/models/public_product_visibility_policy.dart`.
- Núcleo compartido (2026-10-04): `packages/vinabike_public_core/lib/`, Dart sin
  Flutter. Las rutas viejas en `lib/` son una línea que lo reexporta; el código
  nuevo importa el paquete. Servidor HTML: `services/storefront_html/`.
- Guardado del editor: `WebsiteSaveCoordinator` (un solo «Guardar») →
  `WebsiteService`.
- Borde: `cloudflare-worker/src/index.js` (`vinabike-edge-cache`), caché de 5
  minutos de los datos públicos.
- Cada superficie tiene su fila en `docs/architecture/canonical-ui-surfaces.md`.
