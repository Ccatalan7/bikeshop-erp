---
titulo: Google Search Central
resumen: la documentación de Google para que un sitio se rastree, se indexe y se muestre bien; manda sobre cualquier blog de SEO
tipo: externa
revisado: 2026-10-03
---

# Google Search Central `[GSC]`

`developers.google.com/search/docs` y la ayuda de Search Console
(`support.google.com/webmasters`). Es la autoridad: describe lo que Googlebot
hace de verdad. Un blog de SEO que la contradice está equivocado o desactualizado.

## Consultado el 2026-10-03 (lectura completa, resumen propio)

| Página | URL | Qué se tomó |
|---|---|---|
| JavaScript SEO basics (actualizada 2026-03-04) | `/search/docs/crawling-indexing/javascript/javascript-seo-basics` | tres fases (rastreo, render en cola, índice); sólo `<a href>` se sigue con seguridad; rutas con `#` no; soft 404 en SPA; canonical inyectado debe calzar con el HTML; caché agresiva → huellas en los nombres de archivo |
| Consolidar URLs duplicadas | `/search/docs/crawling-indexing/consolidate-duplicate-urls` | redirección y `rel=canonical` son señales fuertes, el sitemap débil; canonical es señal, no orden; URL absolutas; no usar robots.txt ni `noindex` para canonicalizar |
| Crear un sitemap | `/search/docs/crawling-indexing/sitemaps/build-sitemap` | 50.000 URL o 50 MB por archivo; sólo URL canónicas absolutas; `lastmod` sólo si es exacto; `priority` y `changefreq` se ignoran |
| Robots meta y `X-Robots-Tag` | `/search/docs/crawling-indexing/robots-meta-tag` | la cabecera sirve para cualquier respuesta; **una URL bloqueada en robots.txt nunca deja leer su `noindex`** |
| Informe de indexación de páginas | `support.google.com/webmasters/answer/7440203` | qué significa cada motivo de «no indexada» y cuáles no son error; filtrar por sitemap |
| Datos estructurados de ficha de comercio (merchant listing) | `/search/docs/appearance/structured-data/merchant-listing` | `Product` + `Offer` (no `AggregateOffer`), precio > 0, moneda ISO; recomendados: disponibilidad, condición, envío, devolución, marca, GTIN/MPN, descripción; el marcado debe calzar con lo visible |
| Política de devoluciones (actualizada 2026-09-08) | `/search/docs/appearance/structured-data/return-policy` | se declara una vez en `Organization`/`OnlineStore` con `hasMerchantReturnPolicy`: país + `returnPolicyCategory` (+ `merchantReturnDays` si es plazo finito) o sólo `merchantReturnLink`; recomendados método, costo y tipo de reembolso; prioridad: Merchant Center > ficha > organización |
| Política de envío (actualizada 2026-09-08) | `/search/docs/appearance/structured-data/shipping-policy` | `hasShippingService` → `ShippingService` → `shippingConditions` con destino, tramo por `orderValue`, `shippingRate`, `transitTime`; retiro como `FulfillmentTypeCollectionPoint`; la de la ficha (`shippingDetails`) gana sobre la de la organización |
| Datos estructurados de negocio local | `/search/docs/appearance/structured-data/local-business` | `name` y `address` obligatorios; recomendado geo, teléfono, horario, imagen; usar el subtipo más específico |

## Cómo leerla

- Distingue **requisito** («required») de **recomendación**. Un aviso de Search
  Console sobre una propiedad recomendada no impide aparecer.
- Los informes de mejoras (fichas de comercio, fragmentos de producto) muestran
  **muestras** de elementos, no un censo de páginas.
- Fechas: la página dice «Last updated»; anotarla al ingerir.
