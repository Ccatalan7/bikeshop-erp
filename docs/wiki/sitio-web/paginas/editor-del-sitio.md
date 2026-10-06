---
titulo: El editor del sitio
resumen: cómo funciona el editor de vinabike.cl dentro del ERP — sus dos planos de control, los espacios de administración, los bloques, el guardado y el teléfono
fuentes: [repositorio]
archivos: [docs/architecture/website-editor-contract.md, lib/modules/website/models/website_catalog_canvas.dart, lib/modules/website/widgets/website_editor_selectable_surface.dart, lib/modules/website/widgets/editor_panel/catalog_section_controls.dart, services/storefront_html/lib/src/website_blocks_view.dart, packages/vinabike_public_core/lib/modules/website/models/website_block_surface_presence.dart, lib/modules/website/providers/website_edit_mode_provider.dart, lib/modules/website/services/website_save_coordinator.dart, lib/modules/website/models/website_block_type.dart, lib/modules/website/services/website_editor_draft_controller.dart]
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

## Páginas de catálogo en el lienzo (2026-10-06)

Primera etapa de la propuesta que el dueño aprobó el 2026-10-06 («dale,
construye la propuesta del editor»: un editor para todas las páginas, como
Shopify o Wix). `/servicios` ya no se edita en un formulario aparte: se abre en
el editor y **se edita encima** `[Repo]`.

- Cada sección (Portada, Planes, Todos los servicios, Cierre) se selecciona en
  la página o desde el panel. Los textos se escriben directo sobre la página;
  una etiqueta vacía se ofrece sólo con su sección seleccionada.
- Sin nada seleccionado, el panel muestra las secciones de la página y **lo que
  viene del catálogo** («del catálogo · 59»): precios, nombres y lo que incluye
  cada plan se cambian en el servicio, con un botón a Inventario.
- Con una sección seleccionada, el panel muestra sólo lo suyo en grupos que se
  abren: textos, botón, calificación de Google, foto, alineación; «Diseño y
  Google» cambia lista ↔ cuadrícula (avisa que la cuadrícula borra portada,
  planes y cierre al guardar) y lo que ve Google.
- Se guarda con el mismo «Guardar»: un borrador por página de catálogo que
  escribe sólo su entrada del registro, leído fresco. Probado en producción el
  2026-10-06 con una ida y vuelta: cambió un solo campo y las otras 11
  presentaciones quedaron iguales `[Prod 2026-10-06]`.
- En una ventana angosta, el dock nombra la sección y «Editar» abre la hoja.

**La barra de arriba (etapa 2a, 2026-10-06):** «Sitio web ▾» lleva a los tres
lugares — **Páginas** (este lienzo), **Catálogo** y los ajustes del sitio
(marca, menús, destinos, lista de páginas) —; «Página: Servicios ▾» queda
siempre a la vista; a la derecha, la vista, Deshacer y Rehacer, «Cambios sin
guardar», «Ver como cliente» y **«Guardar», siempre arriba**. El panel derecho
ya no tiene su propio Guardar: guarda «Versiones guardadas» y «Descartar». Lo
que no cabe a un ancho queda en «…» `[Repo]`.

**Las secciones a la izquierda (etapa 2b, 2026-10-06):** «Secciones» es una
sola lista de lo que tiene la página que está en pantalla, de arriba abajo,
entre el encabezado y el pie. Con el editor de 1584 px o más es una columna a
la izquierda del lienzo (264 px); más angosto, es lo que muestra el panel
derecho cuando no hay nada seleccionado. Cada fila dice el tipo y el título
propio del bloque («Banner · Sobre Viñabike»); se elige tocándola (y la página
baja hasta ella), se arrastra por su manija, se oculta con el ojo, y en «…» se
sube, baja, duplica o elimina (pregunta antes). «Agregar sección» abre el mismo
catálogo de bloques que el «+» de la página. En una página de catálogo lista sus
propias secciones; en el carrito o una ficha de producto dice que la página no
tiene secciones propias. «Capas» ya no está en «Agregar» `[Repo]`.

**Las categorías en el lienzo (etapa 3a, 2026-10-06):** `/productos` y cada
categoría se editan sobre su página igual que Servicios — portada escrita en la
página, tarjetas, filtros y Google al costado; detalle en
[catálogo y fichas](catalogo-y-fichas.md) `[Repo]`.

Pendiente ([estado-y-pendientes](estado-y-pendientes.md)): una plantilla que
cambie las 11 categorías a la vez, la ficha de producto en el lienzo, copiar
secciones entre páginas y el historial de versiones (etapa 3b).

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

- Un atajo de teclado `Espacio`/`Enter` (`FocusableActionDetector`) en una
  superficie que contiene un campo de texto **se come los espacios** que se
  escriben en el campo: el evento sube por la cadena de foco y el atajo lo
  consume antes que la entrada de texto. La superficie seleccionable sólo
  reacciona cuando el foco es suyo (`node.hasPrimaryFocus`) `[Repo 2026-10-06]`.
- Cambiar de página en el editor **apila** la ruta nueva: la anterior sigue
  montada debajo, con `TickerMode` apagado, y no se desecha. Lo que una página
  le cuenta al editor (la de servicios publica sus secciones) se publica sólo
  con `TickerMode.of(context)` encendido y se retira cuando se apaga; si no,
  Inicio mostraba el panel de «Servicios › Portada» `[Repo 2026-10-06]`.
- El documento abierto del editor **sobrevive a su página**: el carrito, una
  ficha de producto o el catálogo no abren documento, así que al ir de Inicio
  al carrito el editor sigue teniendo los bloques de Inicio. Una lista de «lo
  que tiene esta página» que lea sólo el documento muestra la página anterior.
  La página que está en pantalla y es dueña del documento se publica a sí misma
  (`publishBlockCanvas`, desde `WebsiteEditorDocumentBinding.bind`) y se retira
  fuera de pantalla y al desecharse; la lista lee eso `[Repo 2026-10-06]`.
- Recargar en caliente (`r`) no inicializa un campo nuevo en un objeto que ya
  existía: el contexto que la página de catálogo había publicado antes de la
  recarga traía `collection` en nulo y el panel mostró «type 'Null' is not a
  subtype of type 'bool'». No es un defecto: después de agregar un campo a un
  modelo vivo se reinicia (`R`) antes de juzgar la pantalla
  `[Repo 2026-10-06]`.
- El registro de presentaciones del catálogo es **una fila** con todas las
  categorías: leerlo y escribirlo entero deja que dos sesiones se pisen. Se
  escribe como «comparar y reemplazar» sobre su `updated_at`, releyendo ante un
  conflicto (`_updateCatalogPresentationRegistry`) `[Repo 2026-10-06]`.

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
