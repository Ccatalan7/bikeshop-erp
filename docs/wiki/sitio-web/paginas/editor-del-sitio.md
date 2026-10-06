---
titulo: El editor del sitio
resumen: cómo funciona el editor de vinabike.cl dentro del ERP — sus dos planos de control, los espacios de administración, los bloques, el guardado y el teléfono
fuentes: [repositorio]
archivos: [docs/architecture/website-editor-contract.md, services/storefront_html/lib/src/website_blocks_view.dart, packages/vinabike_public_core/lib/modules/website/models/website_block_surface_presence.dart, lib/modules/website/providers/website_edit_mode_provider.dart, lib/modules/website/services/website_save_coordinator.dart, lib/modules/website/models/website_block_type.dart, lib/modules/website/services/website_editor_draft_controller.dart]
tablas: [website_pages, website_blocks, website_navigation, website_settings, featured_products]
revisado: 2026-10-06
---

# El editor del sitio

## Lo esencial

El editor no es una maqueta encima de otro sitio: **es el CMS del sitio real**.
Se edita sobre la tienda misma (montada dentro del ERP), y lo guardado es lo que
se publica. Un resultado está terminado sólo si lo guardado explica el lienzo, la
vista previa y la tienda publicada `[Repo: website-editor-contract.md]`.

## Dos planos de control conectados

| Plano | Es dueño de |
|---|---|
| **Lienzo + inspector derecho** | bloques, diapositivas, capas Canvas, textos, imágenes, botones (CTA), orden, visibilidad y diseño por tamaño de pantalla |
| **Barra superior de administración** | páginas reales, destinos, publicación de productos y categorías, destacados, menús, tema global (encabezado y pie), integraciones y estado de publicación |

Una campaña puede necesitar los dos: el banner se arma en el lienzo, pero la
categoría a la que lleva se configura en `Catálogo web > Categorías`. Para un
botón a una categoría **no** se crea una página CMS duplicada; el destino se elige
con `WebsiteLinkValueEditor` y se audita en `Estructura > Destinos y enlaces`
`[Repo]`.

## Espacios de administración (dueño de cada dato)

| Espacio | Dueño de |
|---|---|
| `Catálogo web` (Productos, Categorías, Portada) | qué productos y categorías salen en la web; la colección destacada; la presentación de cada categoría (slug, portada, migas, facetas) y el diseño de `/servicios`: grilla o lista de precios con portada, botón, calificación, planes y cierre (2026-10-06, [catálogo](catalogo-y-fichas.md)) |
| `Estructura > Páginas` | registros de `website_pages` |
| `Estructura > Navegación y menús` | `website_navigation` (encabezado y pie) |
| `Estructura > Destinos y enlaces` | auditoría de a dónde lleva cada botón y menú |
| `Tema` | tipografías, colores, fondo y botones globales |
| `SEO y visibilidad` | **sólo lectura**: diagnostica y manda al dueño de cada dato; no guarda nada |
| `Configuración` | `store_url` (origen HTTPS limpio, el canonical), título y descripción del sitio, plantillas de título de producto, GA |
| `Integraciones` | Google (Places, reseñas, Merchant), WhatsApp, Mercado Pago |

`[Repo: website-editor-contract.md «Management workspaces»]`

En el ERP, el panel `Sitio Web` (`/website`, `website_management_page.dart`)
abre las mismas páginas de administración con rutas propias:

| Ruta del ERP | Archivo |
|---|---|
| `/website` | `website_management_page.dart` |
| `/website/pages` | `page_management_page.dart` |
| `/website/navigation` | `navigation_management_page.dart` |
| `/website/destinations` (y `/website/content` redirige aquí) | `website_destination_management_page.dart` |
| `/website/featured` | `featured_products_page.dart` |
| `/website/product-visibility` | `product_website_visibility_page.dart` |
| `/website/orders` | `online_orders_page.dart` |
| `/website/settings` | `website_settings_page.dart` |
| `/website/integrations` | `integrations_page.dart` |
| `/website/seo` | `seo_settings_page.dart` |
| (sin ruta, código muerto) | `banners_management_page.dart`, `content_management_page.dart` |

`[Repo: app_router.dart, 2026-10-03]`

## Bloques

24 tipos en `WebsiteBlockType` (`hero`, `carousel`, `canvas`, `text`, `products`,
`categoryGrid`, `brandLogos`, `googleReviews`, `faq`, `contact`…). En
producción se usan 11 tipos en 25 bloques: `hero` 5, `faq` 4, `about` 4,
`features` 3, `contact` 3 y uno de `videoBanner`, `products`, `googleReviews`,
`categoryGrid`, `brandLogos` y `carousel` `[Prod 2026-10-03]`. La altura de cada
tipo (exacta, mínima o intrínseca) la decide `WebsiteBlockCapabilityRegistry`, la
misma regla para el inspector, Edit y público `[Repo]`.

El sitio público lo dibuja el **servidor HTML**, que hoy cubre `hero`,
`contact`, `carousel`, `products`, `categoryGrid`, `brandLogos`,
`videoBanner`, `googleReviews`, `text`, `button`, `divider`, `faq`, `cta`,
`features` y `about` (`pageCoveredBlockTypes`, 2026-10-06); las páginas de
información leen `about`, `faq` y `features` como secciones de texto, como
Flutter. Faltan `canvas`, `services`, `testimonials`, `gallery`, `pricing`,
`team`, `stats`, `footer` y `partnersBanner`. Una página con
otro tipo, o con un bloque que tiene fondo, borde, sombra o relleno propio
(`websiteBlockHasAuthoredSurface`: el HTML todavía no pinta superficies), la
responde Flutter entera: el visitante nunca pierde lo que el editor guardó.
El lienzo del editor sigue siendo Flutter; el plan para que sea el HTML real
está en la fase 5 de `storefront-html-migration-plan.md` `[Repo]`.

Lo que arma un agente (campañas, banners, diapositivas, secciones) son
operaciones reales del editor: mismos valores por defecto, validaciones, esquema
y guardado que una persona, y el resultado se reabre y se edita en sus controles
sin agentes. Si falta un control, primero se agrega al editor. Es la regla 1 de
[principios](principios.md), con su prueba de ida y vuelta
`[Repo: website-builder-agent-handoff.md]`.

## Guardar

- Un solo **«Guardar»** global (`WebsiteSaveCoordinator`) persiste todo; ningún
  panel tiene un segundo botón de guardar. Los bloques de una página se
  reemplazan de forma atómica (`replace_page_blocks`) `[Repo]`.
- Borrador local durable: `WebsiteEditorDraftController` y `WebsiteEditorDraftStore`
  recuperan lo no guardado si se cierra la pestaña.
- `Configuración` guarda con **una** llamada (`saveSettings`); un bucle de una
  escritura por campo deja el sitio a medias si falla al medio
  `[Repo: canonical-ui-surfaces.md]`.
- Guardar **no publica** el HTML que ve Google ([publicacion-y-despliegue](publicacion-y-despliegue.md)).

## En el teléfono

El lienzo sigue montado; el bloque elegido recibe un dock contextual medido y
los controles profundos abren una hoja (máximo 60 % del alto con teclado). Edit →
Vista previa → Edit conserva la selección y el scroll. Cualquier cambio de esa
geometría pasa la prueba real de iOS
`integration_test/website_phone_authoring_ios_smoke_test.dart` `[Repo]`.

## Trampas

- Una página CMS duplicada para que un botón funcione (la categoría ya tiene su
  destino).
- Volver a crear publicadores redundantes de productos o categorías: los atajos
  abren el mismo dueño `[Repo]`.
- Valores por defecto que ganan sobre un valor guardado: el valor guardado
  siempre manda en los tres modos.
- El editor sigue llamando `ensure_default_footer_navigation`, que no existe en
  producción (migración `20260728223000` sin aplicar, 2026-09-29) — ver
  [estado-y-pendientes](estado-y-pendientes.md).

## En el código y la base

- Proveedor de modo y documento: `WebsiteEditModeProvider`
  (`lib/modules/website/providers/website_edit_mode_provider.dart`); inspector:
  `PersistentEditorShell`, `WebsiteEditorPanel`; composición: `PageComposition`,
  `WebsitePageComposition`; render público: `WebsiteBlockRenderer`.
- Tablas: `website_pages`, `website_blocks`, `website_navigation`,
  `website_settings`, `featured_products`.
- Superficies registradas: filas «Website …» de
  `docs/architecture/canonical-ui-surfaces.md`.
