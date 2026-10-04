---
titulo: Estado y pendientes
resumen: qué está en vivo hoy, qué falta y de quién depende — la lista de trabajo del sitio, con fecha
fuentes: [repositorio, consolas-google, google-search-central]
archivos: [supabase/migrations/20260728223000_harden_website_navigation_seed.sql, supabase/migrations/20260728230000_add_storefront_publication_contract.sql, docs/architecture/storefront-instant-page.md]
tablas: [website_navigation, website_settings]
revisado: 2026-10-03
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

| Desde | Qué | Página |
|---|---|---|
| 2026-10-03 | JSON-LD de ficha: `description`, `shippingDetails`, `hasMerchantReturnPolicy` | [datos-estructurados](datos-estructurados.md) |
| 2026-10-03 | `LocalBusiness` → `BikeStore`, con `geo` y horario | [datos-estructurados](datos-estructurados.md) |
| 2026-10-03 | `robots.txt`: quitar `Disallow` de `/cuenta/` y `/pedido/` (la cabecera `noindex` ya los saca) | [rutas](rutas-y-navegacion.md) |
| 2026-10-03 | Eventos GA4 que faltan: `view_item_list`, `select_item`, `remove_from_cart`, `view_cart`, `add_shipping_info`, `add_payment_info` | [medicion](medicion.md) |
| 2026-10-03 | Comparar Search Console contra la línea base del 23-sep (filtrada al sitemap) y mirar `/servicios` | [seo-tecnico](seo-tecnico.md) |
| 2026-09-24 | Carrusel en teléfono: las flechas tapan el texto (antes esperaba Design; desde el 27-sep el aspecto lo decide el agente) | `storefront-instant-page.md` |
| 2026-09-24 | La tienda llama `get_public_store_data` directo además de usar la precarga (sin investigar) | [rendimiento](rendimiento.md) |
| 2026-09-24 | Imágenes pesadas: campaña de cámaras en PNG de 2 MB, WebP de 312 KB en la grilla de categorías | [rendimiento](rendimiento.md) |
| 2026-09-26 | Login `/cuenta/login` sin la dirección «Sendero» | [portal](portal-de-clientes.md) |
| 2026-10-03 | Código muerto: `banners_management_page.dart`, `content_management_page.dart`, `customer_account_page.dart`, `premium_dashboard_widgets.dart`, ruta `/cuenta/mensajes`; clave `header_nav_links` | [editor](editor-del-sitio.md) |
| 2026-10-08 | Leer el resultado de la tarea `vinabike-store-ready-review` | [rendimiento](rendimiento.md) |

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
