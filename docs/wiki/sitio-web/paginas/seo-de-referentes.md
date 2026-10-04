---
titulo: SEO de los referentes y lo que nos falta
resumen: qué configuración SEO tienen las tiendas de bicicletas que ya aparecen en Google (medido en vivo), comparada con vinabike.cl, y la lista de brechas en orden de impacto
fuentes: [referentes, google-search-central, schema-org, repositorio]
archivos: [scripts/generate_product_seo_snapshots.dart, docs/architecture/storefront-instant-page.md]
tablas: [products, product_categories, website_pages, website_settings]
revisado: 2026-10-04
---

# SEO de los referentes y lo que nos falta

## Lo esencial

El dueño quiere aplicar «absolutamente toda la configuración de SEO» de los sitios
de venta profesionales y de los referentes de bicicletas `[Dueño 2026-10-04]`. Se
midió en vivo a las tiendas chilenas que hoy aparecen en Google por repuestos y
bicicletas, y a marcas internacionales ([cómo se midió](../fuentes/referentes.md)).
La diferencia más grande **no es una etiqueta: es cuánto contenido real trae el
HTML**.

## La comparación (ficha de producto, 2026-10-04) `[Ref]`

| | Oxford Store | Better Bike | Cycling Store | Express Bike | RudolfBike | ExtremeZone | Canyon | **vinabike.cl** |
|---|---|---|---|---|---|---|---|---|
| Palabras en el HTML sin JavaScript | 1.318 | 751 | 940 | 694 | 10.448 | 19 | 2.238 | **13 visibles + 57–87 en `<noscript>`** |
| Enlaces `<a href>` sin JavaScript | 403 | 54 | 91 | 74 | 1.057 | 0 | 95 | **3 (+2 en `<noscript>`)** |
| Palabras en una categoría | 1.118 | 912 | 721 | 391 | 2.930 | 19 | 2.758 | **1 + 149 en `<noscript>` (25 enlaces de 67 productos)** |
| `description` en el JSON-LD del producto | sí | no | sí | sí | (microdatos) | sí | no | **sólo si el producto la tiene: 29 de 1.541** |
| Código de barras (`gtin`/`mpn`) | sí | sí | no | sí | — | `mpn` | no | **5 de 1.541 tienen uno real** |
| Política de devolución declarada | no | **sí** | no | no | no | no | no | **sí (link), desde 2026-10-04** |
| Variantes (`ProductGroup`) | no | sí | no | no | no | no | sí | no |
| Especificaciones (`additionalProperty`) | no | no | no | no | no | no | **sí** | **sí, 1.232 fichas, desde 2026-10-04** |
| Valoraciones (`AggregateRating`) | no | no | no | no | sí | no | sí | no |
| Negocio declarado como | Organization | Organization | Organization | — | Organization | Organization | Organization | **BikeStore** con horario y devoluciones (2026-10-04) |
| Sitemaps (archivos) | 6 | 8 | 5 | 5 | 1 | 8 | 12 | 1 |
| Blog o guías | sí | sí | no | no | sí | sí | — | **no** |

Lo que hacemos igual o mejor: título y descripción de ficha con buen largo (69 y
148 caracteres), canonical propio, Open Graph y Twitter, alt en todas las
imágenes, imágenes dentro del sitemap (2.592), `BreadcrumbList`, disponibilidad y
condición en la oferta `[Prod]`.

Dos lecturas importantes:
- **Seis de siete referentes chilenos sirven la página completa en HTML** (entre
  390 y 10.000 palabras). ExtremeZone es una SPA como nosotros (19 palabras) y
  aun así aparece: Google ejecuta JavaScript, pero en una segunda fase más lenta.
  Bing en su primera pasada, las previsualizaciones de redes y la mayoría de los
  rastreadores de asistentes de IA **no** lo ejecutan.
- Nuestro texto para rastreadores vive en `<noscript>`: la descripción del
  producto cuando existe (87 palabras en el aceite Shimano S56467; 57 genéricas
  en un producto sin descripción), y en la categoría los primeros 25 de 67
  productos. Un rastreador sin JavaScript lo lee; **Google, que sí ejecuta
  JavaScript, lo descarta** y lee lo que Flutter expone en su árbol semántico.
  Contra 700–2.500 palabras visibles de los referentes, sigue siendo poco y está
  en el lugar menos confiable.

## Brechas, en orden de impacto

Todas se resuelven **como consumidores de los dueños que ya existen** o agregando
primero la capacidad al editor (regla 1, [principios](principios.md)).

1. **Contenido real y visible en el HTML de cada página**, no en `<noscript>`.
   El snapshot de la ficha debe traer, visibles, la descripción, la ficha
   técnica, las migas como enlaces, productos relacionados y la categoría; el de
   la categoría, su texto de presentación y **todos** sus productos con enlaces y
   paginación; la portada, sus bloques en texto. No es rehacer la tienda: es enriquecer el HTML que el build ya
   escribe (la página instantánea ya lo pinta antes de Flutter). Es la brecha que
   más pesa y la que pone a vinabike.cl a la par de Oxford Store o Cycling Store.
2. ~~**Ficha de producto completa en JSON-LD**~~ — hecho el 2026-10-04 para lo
   que tiene dueño: ficha técnica como `additionalProperty` (1.232 fichas),
   `model` y migas completas ([datos-estructurados](datos-estructurados.md)).
   La `description` y el `gtin` ya se declaraban cuando existen: lo que falta
   es **contenido** (29 descripciones y 5 códigos de barras de 1.541).
3. **Envío y devoluciones declarados una vez para todo el negocio** — las
   devoluciones, hechas el 2026-10-04 (link a `/devoluciones`). El envío **no**:
   «Chile continental» no se puede acotar para Google en Chile y declarar `CL` promete
   despacho a las islas ([datos-estructurados](datos-estructurados.md)).
4. **Textos de categoría:** cada categoría visible con su presentación (título,
   texto, imagen) escrita y servida en HTML; hoy la descripción de categoría tiene
   50 caracteres. Se escriben en `Catálogo web > Categorías > Presentación`.
5. **Guías y artículos** (4 de 6 referentes chilenos tienen blog). Nuestra ventaja
   es el conocimiento de taller del [wiki de compatibilidad](../../compatibilidad/index.md):
   «qué cassette calza con mi bici», «cómo elegir neumático 29». Requiere agregar
   artículos al editor primero (regla 1).
6. **Páginas de aterrizaje para búsquedas de filtro** («cadenas 11 velocidades»,
   «neumáticos 29»): hoy los filtros no tienen URL. Se crean desde el editor como
   destinos con URL, título y texto propios, no como combinaciones automáticas.
7. ~~**El negocio**~~ — `BikeStore` con logo, horario, mapa e imagen, hecho el
   2026-10-04. Falta `geo` (sin dueño). El `SearchAction` que tienen varios
   referentes ya no lo usa Google `[GSC]`.
8. ~~`robots.txt`~~ — descartado: el bloqueo de `/pedido/` protege el token del
   pedido ([rutas](rutas-y-navegacion.md)).
9. **Reseñas:** `AggregateRating` sólo con reseñas reales de productos,
   visibles en la misma página. Google no da estrellas a un negocio que controla
   sus propias reseñas ni acepta reseñas traídas de otro sitio (las de Google
   Maps no se declaran como propias) `[GSC]`.
10. **Fuera del sitio:** perfil de Google con fotos y reseñas, Merchant (listados
    gratuitos), enlaces desde marcas, importadores (MKR) y comunidades.

## En el código y la base

- HTML y JSON-LD: `scripts/generate_product_seo_snapshots.dart` (y la página
  instantánea, `docs/architecture/storefront-instant-page.md`).
- Dueños de los textos: `products` (descripción y campos `website_*`),
  `product_categories` + presentación de categoría, `website_pages`,
  `website_settings` (negocio, horario).
- Para repetir la medición: el script descrito en
  [la ficha de referentes](../fuentes/referentes.md).
