---
titulo: Catálogo, categorías y fichas de producto
resumen: qué producto sale en la tienda y por qué, cómo se arman categorías, facetas, búsqueda y la ficha pública, y qué pasa con los agotados
fuentes: [repositorio, google-search-central]
archivos: [lib/shared/models/public_product_visibility_policy.dart, packages/vinabike_public_core/lib/public_store/models/public_commerce_product_projection.dart, packages/vinabike_public_core/lib/public_store/models/public_product_seo_copy.dart, lib/public_store/pages/product_catalog_page.dart, lib/public_store/pages/product_detail_page.dart, packages/vinabike_public_core/lib/public_store/utils/public_spec_display.dart]
tablas: [products, product_categories, product_url_aliases, website_settings, featured_products]
revisado: 2026-10-03
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
- `Catálogo web > Categorías > Publicación` decide si se ve; `Presentación`
  guarda el slug público estable, la portada heredada o propia, migas,
  subcategorías, facetas y densidad de la grilla. Quitar la presentación vuelve
  al diseño compartido; nunca despublica `[Repo: website-editor-contract.md]`.
- Facetas: marca y, desde el 2026-09-16, filtros técnicos (válvula, aro,
  velocidades…) cuando la especificación describe al menos el 30 % de la
  colección (`get_public_product_facets_v2`) `[Repo]`.

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

- Política: `lib/shared/models/public_product_visibility_policy.dart`
  (compartida por tienda y editor) y las claves `product_visibility_*`.
- Funciones: `get_public_products`, `get_public_products_faceted_v2`,
  `get_public_product_facets_v2`, `get_public_product_category_counts`,
  `search_public_products`, `get_public_featured_products`.
- Páginas: `product_catalog_page.dart`, `product_detail_page.dart`; editor:
  `product_website_visibility_page.dart`, `featured_products_page.dart`.
