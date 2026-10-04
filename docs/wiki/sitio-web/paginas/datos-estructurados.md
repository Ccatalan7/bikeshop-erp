---
titulo: Datos estructurados (JSON-LD)
resumen: qué declara cada tipo de página de vinabike.cl, qué pide Google para fichas de comercio y negocio local, y lo que falta
fuentes: [google-search-central, schema-org, repositorio]
archivos: [scripts/generate_product_seo_snapshots.dart, lib/public_store/utils/structured_data.dart]
tablas: [products, website_settings]
revisado: 2026-10-03
---

# Datos estructurados (JSON-LD)

## Lo esencial

El JSON-LD va en el **snapshot HTML** que escribe el build, no lo inventa
Flutter: así Google lo lee sin esperar el render y coincide con lo visible
`[Repo]`. Regla de Google: el marcado describe lo que la página muestra; si
dice otro precio o disponibilidad, es una discrepancia que Merchant castiga
`[GSC]` `[MC]`.

## Lo que declara cada página (vivo, 2026-10-03)

| Página | Tipos | `[Prod]` |
|---|---|---|
| Todas | un `LocalBusiness` (nombre, razón social, RUT, dirección completa, teléfono, correo, `areaServed`, `sameAs`, `contactPoint`) | la validación del build exige uno solo por página |
| Ficha `/productos/<slug>/<sku>` | `Product` (`name`, `image`, `sku`, `brand`, `category`, `url`) con `Offer` (`price`, `priceCurrency` CLP, `availability`, `itemCondition`, `seller`, `url`) + `BreadcrumbList` | agotado → `OutOfStock` |
| Categoría | `CollectionPage` + `ItemList` + `BreadcrumbList` | |
| `/servicios` | `ItemList` de 57 `Service`, cada uno con su `Offer` | |
| Portada | sólo el `LocalBusiness` | |

## Lo que pide Google para una ficha de comercio

**Obligatorio** (y lo cumplimos): `name`, `image`, `offers` como `Offer` (no
`AggregateOffer`) con `price` > 0 y `priceCurrency` ISO `[GSC]`.

**Recomendado** y estado nuestro:

| Propiedad | ¿La declaramos? |
|---|---|
| `availability`, `itemCondition`, `brand` | sí |
| `description` | **no** — la ficha la tiene en la página pero no en el JSON-LD |
| `shippingDetails` (envío) | **no** |
| `hasMerchantReturnPolicy` (devoluciones) | **no** — hay página `/devoluciones`, pero no está declarada |
| `priceValidUntil` | no (sólo importa si se declara una fecha) |
| `gtin` / `mpn` | casi imposible hoy: 5 de 1.635 productos con EAN y ninguno con MPN (2026-10-02) |

Las tres primeras faltas son las de más valor: Google las usa para mostrar envío
y devoluciones en los resultados de compra, y la política de Merchant mira
justamente que costos y devoluciones estén claros `[GSC]` `[MC]`.

## Negocio local

Google pide `name` y `address` (los tenemos) y recomienda `geo`, `telephone`,
`openingHoursSpecification`, `image` y usar **el subtipo más específico** `[GSC]`.
Hoy: sin `geo` ni horario, y el tipo es el genérico `LocalBusiness`, cuando
schema.org tiene **`BikeStore`** (LocalBusiness → Store → BikeStore) `[SO]`.

## Oportunidades (2026-10-03)

1. Agregar `description` al `Product` (desde el mismo resolvedor del texto de la
   ficha).
2. Declarar envío y devoluciones (`shippingDetails` con la cotización de envío
   real y `hasMerchantReturnPolicy` con la política de `/devoluciones`), desde
   los dueños que ya existen (`quote_public_online_shipping`, páginas CMS), nunca
   como texto fijo.
3. `LocalBusiness` → `BikeStore`, con `geo` y horario desde la configuración del
   negocio (`business_*` en `website_settings`).
4. Cargar EAN donde el producto lo tenga en la caja (aporta a Merchant).

## Trampas

- Dos `LocalBusiness` en una página (la validación del build lo rechaza).
- JSON-LD distinto entre el snapshot y lo que Flutter muestra (precio, stock).
- Declarar `AggregateOffer` en una ficha: deja de ser elegible como ficha de comercio.

## En el código y la base

- Generador: `scripts/generate_product_seo_snapshots.dart` (Product, Offer,
  BreadcrumbList, CollectionPage, ItemList, Service, WebSite, LocalBusiness).
- En la app: `lib/public_store/utils/structured_data.dart` (y su versión web).
- Datos: `products` (campos `website_*`), configuración del negocio en
  `website_settings`.
