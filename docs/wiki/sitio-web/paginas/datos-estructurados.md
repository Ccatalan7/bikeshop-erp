---
titulo: Datos estructurados (JSON-LD)
resumen: qué declara cada tipo de página de vinabike.cl, de qué dueño sale cada dato, qué pide Google para fichas de comercio y negocio local, y lo que falta
fuentes: [google-search-central, schema-org, repositorio]
archivos: [scripts/generate_product_seo_snapshots.dart, scripts/sync_seo_index.sh, lib/public_store/seo/public_product_structured_data.dart, lib/public_store/seo/public_business_structured_data.dart, lib/public_store/models/public_business_hours.dart, lib/public_store/utils/structured_data.dart]
tablas: [products, website_settings, online_shipping_rate_tiers, spec_facts]
revisado: 2026-10-04
---

# Datos estructurados (JSON-LD)

## Lo esencial

El JSON-LD va en el **snapshot HTML** que escribe el build, así Google lo lee
sin esperar el render y coincide con lo visible `[Repo]`. Regla de Google: el
marcado describe lo que la página muestra; si dice otro precio o disponibilidad,
es una discrepancia que Merchant castiga `[GSC]` `[MC]`.

**Un armado por cosa declarada (2026-10-04).** La ficha de producto la arma
`buildPublicProductStructuredData` (`lib/public_store/seo/`) y la usan los dos
que la escriben: el snapshot del build y la página en Flutter, que al cargar
**reemplaza el script del snapshot por su id** (`seo-product-jsonld`). Antes
cada uno tenía su mapa y la página, al tomar el control, borraba las migas que
el snapshot había declarado: lo que Google renderiza es la versión de Flutter.

## Lo que declara cada página (build local con datos reales, 2026-10-04)

| Página | Tipos | De dónde sale |
|---|---|---|
| Todas | un **`BikeStore`** (`@id` `https://vinabike.cl/#negocio`) | ver «El negocio» abajo |
| Ficha `/productos/<slug>/<sku>` | `Product` + `Offer` + `BreadcrumbList` en un `@graph` | proyección pública + ficha técnica publicada |
| Categoría | `CollectionPage` + `ItemList` + `BreadcrumbList` | |
| `/servicios` | `ItemList` de 59 `Service`, cada uno con su `Offer` | |
| Páginas legales | `WebPage` | |

## La ficha de producto

| Propiedad | Dueño | Estado `[Prod 2026-10-04]` |
|---|---|---|
| `name`, `image`, `sku`, `brand`, `category`, `offers` | `PublicCommerceProductProjection` (la misma que Merchant y la página) | todas las fichas |
| `description` | descripción del producto (`website_merchant_description` → `website_description` → `description`) | **sólo 29 de 1.541** publicados tienen texto; nunca se rellena con el texto generado de la meta descripción, que no se ve en la página |
| `gtin` | `firstValidGtin` (rechaza los códigos internos que parten en 2) | 5 de 1.541 con un código de barras real |
| `model` | `products.model` | 174 |
| `additionalProperty` | la ficha técnica que ve el cliente: filas de `get_public_product_technical_specs` armadas con `PublicProductSpecSheet.build`, sin el grupo «Marca y modelo» (va como `brand`/`model`/`gtin`) | **1.232 de 1.295** fichas del build; 3 a 6 datos lo más común, hasta más de 10 (un casete: velocidades, dientes de cada piñón, tecnología, núcleo…) |
| `BreadcrumbList` | el mismo recorrido que la miga visible: Inicio › Productos › cada categoría pública › producto | |

Lectura de la ficha técnica en el build: una llamada por producto, 8 a la vez,
3 intentos; si una no se puede leer, el build se cae en vez de publicar un
snapshot que dice menos que la página. Ese paso y todo el generador tardan
~120 s con 1.295 fichas `[Repo 2026-10-04]`.

## El negocio

El nodo tiene **dos escritores, cada propiedad uno** `[Repo]`:

- `scripts/sync_seo_index.sh` escribe en `web/index.html` la identidad desde
  `website_settings`: tipo, `@id`, nombre, razón social, RUT, dirección,
  teléfono, correo, `contactPoint`, `sameAs`. Su `--check` la compara.
- El generador (`completeSeoBusinessJsonLd`) le **agrega** lo que sólo el build
  puede leer, sin reescribir nada de lo anterior:

| Propiedad | Dueño |
|---|---|
| `logo` | el logo que pinta la tienda (`storefrontFirstLogoSource`: `logo_url` del sitio → logo del tenant → el empaquetado de Viñabike) |
| `image` | `seo_og_image` |
| `hasMap` | `seo_google_maps_url` (o sus alias) |
| `openingHoursSpecification` | `business_hours_json` (ERP › «Horario del local»), leído por `parsePublicBusinessHours`, el mismo que usa `/contacto`; días con igual horario van juntos |
| `hasShippingService` | despacho: un `ShippingConditions` por tramo activo de `online_shipping_rate_tiers` (lo que cobra el checkout), `maxValue` = tope − 1 porque Google lee ambos extremos como incluidos; retiro en tienda gratis (`FulfillmentTypeCollectionPoint`) |
| `hasMerchantReturnPolicy` | **sólo** `merchantReturnLink` a `/devoluciones`, y sólo si esa página está publicada con contenido |

Los tramos son de personal; el build los lee por
`get_public_online_shipping_tiers` (20261004120000), lectura pública de las
filas activas, igual que puede leerlos la página de envíos.

**Devoluciones con link y nada más, a propósito.** Los términos (10 días, quién
paga el envío, reembolso) viven como texto en la página del editor. Declararlos
como campos (`merchantReturnDays`, `returnFees`…) sería un segundo dueño sin
control en el editor; un test lo prohíbe. Para declararlos hay que agregar
primero esos campos al editor (regla 1) — está en
[estado-y-pendientes](estado-y-pendientes.md).

La validación del build exige en cada página **un** nodo de negocio
(`BikeStore` o `LocalBusiness`), que una política de devolución sólo exista
dentro de él y que su link sea la `/devoluciones` publicada.

## Lo que pide Google

Ficha de comercio — **obligatorio** (cumplido): `name`, `image`, `offers` como
`Offer` (no `AggregateOffer`) con `price` > 0 y `priceCurrency` ISO. Recomendado:
disponibilidad, condición, marca, GTIN/MPN, descripción, envío y devolución
`[GSC]`.

Negocio local: `name` y `address`; recomendado `geo`, `telephone`, horario,
`image` y **el subtipo más específico** (`BikeStore`: LocalBusiness → Store →
BikeStore) `[GSC]` `[SO]`.

Envío y devoluciones se declaran **una vez** en la organización desde el
2026-09-08: `hasShippingService` → `ShippingService` → `shippingConditions`;
`hasMerchantReturnPolicy` con país + categoría (+ días) **o sólo**
`merchantReturnLink`. Prioridad: Merchant Center > ficha > organización `[GSC]`.

## Lo que falta

1. **Descripciones de producto** (29 de 1.541): es contenido, no marcado.
2. `geo` del local (no hay latitud/longitud en ningún dueño).
3. `addressCountry` va como «Chile»; Google prefiere el código `CL`, y
   `seo_address_country_code` no tiene quien la escriba.
4. Términos de devolución como campos del editor (ver arriba).

## Trampas

- Dos nodos de negocio en una página (la validación del build lo rechaza).
- Un mapa propio de JSON-LD en la página o en el generador: vuelve a separar lo
  que ve Google en el snapshot de lo que ve al renderizar.
- Declarar `AggregateOffer` en una ficha: deja de ser elegible como ficha de
  comercio.
- JSON dentro de `<script>` sin escapar `<`: un nombre con `</script>` cierra el
  elemento. `encodeStructuredDataForHtml` lo escapa.

## En el código y la base

- Ficha de producto: `lib/public_store/seo/public_product_structured_data.dart`;
  la página la llama en `_updateStructuredData` (al cargar el producto, la ficha
  técnica y el recorrido de categorías).
- Negocio: identidad en `scripts/sync_seo_index.sh`; lo demás en
  `lib/public_store/seo/public_business_structured_data.dart`, aplicado por
  `completeSeoBusinessJsonLd` en `scripts/generate_product_seo_snapshots.dart`.
- Horario: `lib/public_store/models/public_business_hours.dart`.
- En la app: `lib/public_store/utils/structured_data.dart` (y su versión web).
- Base: `products`, `spec_facts` (vía `get_public_product_technical_specs`),
  `online_shipping_rate_tiers` (vía `get_public_online_shipping_tiers`),
  `website_settings`.
- Pruebas: `test/unit/public_structured_data_test.dart`.
