---
titulo: Catálogo, categorías y fichas de producto
resumen: qué producto sale en la tienda y por qué, cómo se arman categorías, facetas, búsqueda y la ficha pública, y qué pasa con los agotados
fuentes: [repositorio, google-search-central]
archivos: [packages/vinabike_public_core/lib/shared/models/public_product_visibility_policy.dart, packages/vinabike_public_core/lib/public_store/models/public_category_route.dart, packages/vinabike_public_core/lib/public_store/models/public_catalog_facets.dart, services/storefront_html/lib/src/catalog_page_model.dart, packages/vinabike_public_core/lib/public_store/models/public_commerce_product_projection.dart, packages/vinabike_public_core/lib/public_store/models/public_product_seo_copy.dart, lib/public_store/pages/product_catalog_page.dart, lib/public_store/pages/product_detail_page.dart, packages/vinabike_public_core/lib/public_store/utils/public_spec_display.dart, packages/vinabike_public_core/lib/modules/website/models/website_catalog_price_list.dart, services/storefront_html/lib/src/catalog_price_list_view.dart, lib/public_store/widgets/catalog_price_list_view.dart]
tablas: [products, product_categories, product_url_aliases, website_settings, featured_products]
revisado: 2026-10-06
---

# Catálogo, categorías y fichas de producto

## Lo esencial

La tienda muestra el inventario del ERP: no hay un catálogo aparte. Un producto
sale en la web si **el producto lo permite** y **la política del sitio lo deja
pasar**, y todo consumidor (tienda, snapshots, sitemap, feed de Merchant,
checkout) lo decide con la misma proyección pública `[Repo]`.

## Cuándo sale un producto

1. **El producto:** activo, `is_published`, `show_on_website` y del tipo pedido
   (`product` o `service`) `[Prod: resolve_public_product_url_alias,
   get_public_products]`.
2. **La política del sitio** (`website_settings`, `Catálogo web`), 2026-10-03
   `[Prod]`:

| Clave | Valor | Efecto |
|---|---|---|
| `product_visibility_stock_policy` | `available_only` | los listados muestran sólo lo que tiene stock |
| `product_visibility_require_image` | `true` | sin foto no se lista |
| `product_visibility_include_uncategorized` | `false` | sin categoría no se lista |
| `product_visibility_require_visible_category` | `false` | la categoría no tiene que estar publicada |

3. **El stock se cuenta por la proyección pública**, no por `stock_quantity`: un
   set puede tener stock cero en su fila y venderse por sus componentes `[Repo]`.

Cifras del 2026-10-03 `[Prod]`: 1.682 productos en el ERP, 1.601 marcados para la
web; la tienda **lista 539 productos con stock** y **59 servicios**; el sitemap
tiene 1.306 URL bajo `/productos/` (fichas, también de agotados, y 11 categorías).

## Agotados

Desde el 2026-09-23 una ficha agotada **sigue existiendo**: la página abre con
«Agotado», su JSON-LD dice `OutOfStock` y sigue en el sitemap; sólo los listados
la esconden (migración `20260923210000`; recuperó la ficha de 756 de 901
agotados) `[Repo]`. Antes, un producto que se agotaba desaparecía del build y su
URL moría; para Google eso es perder la página, no «sin stock». Google prefiere
la misma URL con la disponibilidad correcta `[GSC]`.

## Categorías

- 137 categorías activas, **11 visibles en la tienda** (2026-10-03) `[Prod]`. En el
  ERP la categoría agrupa las líneas del taller; en la tienda sólo navega. No
  publica productos.
- `Catálogo > Categorías > En el sitio` decide si se ve. Cómo se ve —el slug
  público estable, la portada heredada o propia, migas, subcategorías,
  facetas, densidad de la grilla, la foto del menú y la imagen al compartir—
  se edita **sobre su página** («Su página» la abre en el lienzo; desde el
  2026-10-06 ya no hay `Presentación`). «Restablecer» vuelve al diseño
  compartido; nunca despublica `[Repo: website-editor-contract.md]`.
- Facetas: marca y, desde el 2026-09-16, filtros técnicos (válvula, aro,
  velocidades…) cuando la especificación describe al menos el 30 % de la
  colección (`get_public_product_facets_v2`) `[Repo]`. Desde el 2026-10-05 esa
  regla (`offeredPublicSpecFacets`) y la lectura de las filas
  (`PublicCatalogFacetSnapshot.fromRows`) viven en el núcleo y las usan Flutter
  y la tienda HTML. Desde el 2026-10-07, en la tienda HTML, una marca o un
  valor técnico activo que la lectura ya no trae (los otros filtros lo dejan
  sin productos) se dibuja marcado y con 0, para que se vea por qué no hay
  resultados y se pueda quitar; si la lectura de filtros falla, la página
  lista sus productos sin conteos ni filtros y conserva los activos
  `[Repo 2026-10-07]`.
- **Qué categoría abre una URL** (`resolvePublishedCategoryRouteValue`, núcleo,
  2026-10-05): un UUID sólo si está publicada; un slug o alias guardado en
  «Catálogo web» sólo su categoría (si no está publicada o lo reclaman dos, nada
  abre); si no, el nombre o la ruta completa entre las **publicadas**, y dos
  iguales no abren ninguna. Importa porque hay nombres repetidos: «Cambios»
  existe dos veces y «Frenos», «Dirección», «Ruedas» y «Transmisión» también
  como subcategorías de «Servicio» (2026-10-06; «Frenos» son tres) — una
  publicada y las demás no `[Prod 2026-10-06]`. Desde el 2026-10-06 el
  **guardia de enlaces** (`PublicCategoryPublication.allowsHref`, usado por el
  editor al navegar y por las tarjetas de categorías del HTML) aplica esta
  misma regla; antes miraba todas las categorías y rechazaba
  `/productos/categoria/frenos` aunque la página abría `[Repo]`.
- Los conteos de la lista de categorías y «Todas» salen de la misma lectura de
  facetas (filas `category` y `summary`), no de
  `get_public_product_category_counts`: respetan los demás filtros y la regla de
  stock del sitio; «Todas» cuenta también lo que no tiene categoría publicada
  (539 contra 533 sumando categorías, 2026-10-05) `[Repo]` `[Prod]`.
- Un filtro técnico en la URL (`spec.valve_standard=…`, o `s.`) es estado del
  visitante como una marca: `noindex,follow` con la canónica limpia. Hasta el
  2026-10-05 faltaba en la lista y una categoría filtrada así decía
  `index,follow` (`storefront_seo_route.dart`) `[Repo]`.

## Las categorías y `/productos` en el editor

Desde el 2026-10-06 (etapa 3a del rediseño) `/productos` y cada categoría
publicada (hoy 11: Accesorios y Componentes en la raíz, 9 subcategorías) se
editan **sobre su página**, como Servicios `[Repo]` `[Prod 2026-10-06]`:

- La lista «Secciones» muestra la **Portada** (sólo en una categoría), **Todos
  los productos** («del catálogo · N») y **En Google**.
- En la portada se escribe sobre la página. Sin título propio, la página
  muestra el **nombre de la categoría** tal como lo ve el cliente; escribir
  encima le da uno propio y vaciarlo vuelve al nombre. El panel cambia la
  etiqueta, el texto, la foto y su oscurecimiento, el alto, la alineación y si
  se ven las subcategorías.
- En los productos se eligen las tarjetas (editorial, equilibrada, compacta),
  los filtros y la ruta de categorías.
- El nombre, la descripción, la foto de la categoría y sus productos se
  cambian en Inventario («Abrir categorías en Inventario»). Desde la etapa 3b
  la sección de página trae también la **dirección** (slug, las anteriores que
  siguen llevando ahí, aviso si otra categoría ya la usa), **En el menú** (la
  foto del menú desplegable), **Imagen al compartir** y **Restablecer**; los
  filtros se ordenan con «Subir».
- Lo que no se guardó se ve en la página, pero los enlaces y la dirección
  leen lo guardado.

Las 11 presentaciones de categoría seguían en los valores por defecto el
2026-10-06 (sin título propio ni foto, cuadrícula equilibrada)
`[Prod 2026-10-06]`.

**Una plantilla para todas las categorías (etapa 3c, 2026-10-06)** `[Repo]`:
el aspecto de una página de categoría —alto, alineación y capa oscura de la
portada, tamaño de las tarjetas, los filtros y su orden, la ruta y las
subcategorías— es el de la **plantilla de categorías**, una entrada más del
mismo registro (`@catalog/categories`) que no tiene dirección ni es una
categoría. En el editor, en cualquier categoría, esos controles dicen arriba
«Plantilla · cambia las 11 categorías» y lo que se cambia ahí cambia en todas.
«Diseño propio para Frenos» deja a esa categoría con su aspecto (parte del de
la plantilla, nada salta) y apagarlo la devuelve a la plantilla. Los textos, la
foto, la dirección, el menú y Google siguen siendo de cada categoría. La misma
regla (`withCategoryTemplate`) la aplican la tienda en Flutter, el editor y el
servidor HTML (`drawnCategory`). Una categoría guardada antes conserva su
aspecto sólo si no era el de por defecto: las 11 de producción lo eran, así que
todas siguen la plantilla `[Prod 2026-10-06]`.

## Servicios: la lista de precios

Desde el 2026-10-06 `/servicios` es una **lista de precios**, no la grilla de
tarjetas con el logo repetido `[Repo]` `[Prod 2026-10-06]`. Lo decide el editor
(`layout: price_list` en `catalog_category_presentations_v1`; los productos
siempre son grilla). **Se edita sobre la página**, como Inicio: en el editor se
elige «Servicios», se toca una sección (Portada, Planes, Todos los servicios,
Cierre) o un texto y se escribe ahí; el panel derecho muestra sólo esa
sección, y «Diseño y Google» guarda la lista o la cuadrícula y lo que ve
Google. Se guarda con el mismo «Guardar» de todo el sitio (ver
`editor-del-sitio.md`) `[Repo]`. Muestra todo en una página:

- **Portada:** título, texto, imagen opcional (sin ella, el color principal
  oscurecido), un botón del editor y la calificación de Google sincronizada.
- **Planes:** los servicios de la categoría elegida (`plans_category_id`, hoy
  «Servicio / Mantenciones») como tarjetas. Lo que incluye cada una sale de su
  **descripción numerada** (`1) …`, `2) …`; las líneas debajo de un número son
  su detalle). Se marca «La más completa» la que incluye más; no es un
  reclamo, es un hecho del catálogo.
- **La lista:** el resto, agrupado por **su propia categoría** en el orden del
  catálogo y del más barato al más caro; sin precio dice «Consultar». Se
  filtra al escribir (sin acentos) y, sin script, con `?q=`.
- **Cierre:** título, texto y botón, opcional.

Las categorías de servicios agrupan igual las líneas del taller (G1): las 10
subcategorías de «Servicio» (Mantenciones, Frenos, Transmisión, Cables y fundas,
Ruedas, Dirección, Suspensión, Limpieza, Revisión general, Armado y arriendo)
se crearon el 2026-10-06 con 66 servicios; 62 públicos. Ninguna se publica en
la navegación: la lista las usa como grupos, no como páginas `[Prod 2026-10-06]`.

La lectura pública corta en 100 filas: el servidor lee de a 100 hasta tener
todo (`_wholeListing`); la primera página va junto con la del menú para no
sumar una espera. Un servicio público necesita foto como un producto: los
servicios llevan el logo de Viñabike como imagen.

## La ficha pública

- Una sola proyección (`PublicCommerceProductProjection`) alimenta la ficha
  Flutter, la página instantánea, el snapshot HTML y el feed de Merchant.
- Campos web propios del producto: `website_name`, `website_description`,
  `website_price`, `website_image_url(s)` y la versión optimizada, y los de
  Merchant (`website_merchant_title`, `…_description`, `…_brand`, `…_gtin`,
  `…_mpn`, `website_google_product_category`) `[Repo]`.
- Título y descripción SEO: un solo resolvedor (`public_product_seo_copy.dart`)
  para la app, la vista previa del ERP y los snapshots. La primera frase de
  búsqueda puede enriquecer el texto generado; nunca pisa uno escrito a mano ni
  se vuelve una lista de palabras clave oculta `[Repo]`.
- Ficha técnica pública: `public_spec_display.dart` y
  `get_public_product_technical_specs`, con las etiquetas para cliente que define
  el contrato de fichas (ver el [wiki de compatibilidad](../../compatibilidad/index.md)).
- URL canónica: `/productos/<slug>/<sku>`; el slug sale de `product_url_slug` y un
  cambio deja alias en `product_url_aliases` ([rutas](rutas-y-navegacion.md)).
- **Una plantilla para todas las fichas (etapa 3d, 2026-10-06)** `[Repo]`: el
  ajuste `product_page_template_v1` (`WebsiteProductPageTemplate`, en el núcleo)
  decide lo que rodea a los datos del producto: de qué lado van las fotos en
  escritorio, la nota bajo el precio (vacía no sale), los datos clave junto al
  precio, el texto del botón de agregar, si sale «Comprar ahora» y con qué
  texto, si salen despacho y retiro, el título de la ficha técnica (vacío:
  «Ficha técnica» o «Detalles del producto» según el producto), la nota de
  origen, la tarjeta de ayuda (si sale, su pregunta y su texto) y los
  relacionados (si salen y su título). La leen la ficha Flutter y el servidor
  HTML; sin plantilla guardada todo queda como antes (así estaba en producción
  el 2026-10-06 `[Prod 2026-10-06]`). Se edita en el editor, sobre la ficha:
  «Foto y compra», «Ficha técnica» y «Relacionados» en «Secciones»; los títulos
  y la nota se escriben en la página, y el carrito, «Comprar ahora», WhatsApp y
  los relacionados no responden mientras se edita.
- **Despacho y retiro:** sus textos son del sitio (`shipping_promise_title`,
  `shipping_promise_detail`, `pickup_promise_detail`) y desde la etapa 3d se
  editan en «Foto y compra»; antes no tenían control y en producción no hay
  ninguno `[Prod 2026-10-06]`. Sin ellos, el despacho dice la tarifa más barata
  del checkout («desde $ 6.990, 3 a 12 días hábiles») y el retiro, la dirección
  de la tienda. Hasta el 2026-10-06 la ficha Flutter no mostraba despacho sin
  esos textos y la HTML sí: ahora ambas leen `get_public_online_shipping_tiers`.

## Búsqueda

`search_public_products` (texto) y el catálogo con facetas
(`get_public_products_faceted_v2`). La búsqueda semántica (`search_products`,
`match_products_semantic`) no está abierta a visitantes desde el 2026-09-23 `[Repo]`.

## Trampas

- Contar disponibilidad con `stock_quantity` crudo (los sets mienten).
- Creer que publicar la categoría publica sus productos, o al revés.
- Un producto nuevo sin categoría o sin foto no aparece en la tienda aunque esté
  marcado para la web; sin categoría cae además en «General» en el taller.
- Pocos productos tienen código de barras: 5 de 1.635 con EAN y ninguno con MPN
  (2026-10-02). Eso limita Merchant y los datos estructurados
  ([datos-estructurados](datos-estructurados.md)).

## En el código y la base

- Política: `packages/vinabike_public_core/lib/shared/models/public_product_visibility_policy.dart`
  (compartida por tienda y editor) y las claves `product_visibility_*`.
- Funciones: `get_public_products`, `get_public_products_faceted_v2`,
  `get_public_product_facets_v2`, `get_public_product_category_counts`,
  `search_public_products`, `get_public_featured_products`. Los valores
  técnicos de los filtros salen de
  `spec_public_facet_values_compute_internal_v1(tienda, productos)` (interna;
  `20261007020000`), que los filtros piden sólo para los productos de las
  categorías elegidas.
- Páginas: `product_catalog_page.dart`, `product_detail_page.dart`; editor:
  `product_website_visibility_page.dart`, `featured_products_page.dart`.
- Lista de precios: reglas en el núcleo (`website_catalog_price_list.dart`:
  grupos, planes, «qué incluye», el plan marcado, la calificación); la dibujan
  `catalog_price_list_view.dart` del servidor HTML y el widget Flutter
  `CatalogPriceListView` (tienda del ERP, Editar/Vista previa y la vista previa
  del espacio «Catálogo web»).
- Tienda HTML (fase 1, ruta oculta): `services/storefront_html/lib/src/`
  `catalog_page_model.dart` y `catalog_page_view.dart` (catálogo, categoría,
  búsqueda), `product_page_model.dart` y `product_page_view.dart` (ficha). Los
  filtros son formularios GET: el servidor junta los valores repetidos de una
  casilla (`brand=a&brand=b`) y descarta los campos vacíos antes de
  `WebsiteCatalogQuery.tryParse`.
- Plantillas: la de categorías es el dueño `@catalog/categories` de
  `website_catalog_presentation.dart` (`withCategoryTemplate`,
  `drawnCategory`); la de fichas, `website_product_page_template.dart`
  (ajuste `product_page_template_v1`), ambas en el núcleo. En el editor:
  `editor_panel/catalog_section_controls.dart` (`_CategoryLookScope`) y
  `editor_panel/product_page_controls.dart`, con las secciones de la ficha en
  `website_product_canvas.dart`.
