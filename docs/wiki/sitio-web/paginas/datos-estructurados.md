---
titulo: Datos estructurados (JSON-LD)
resumen: qué declara cada tipo de página de vinabike.cl, de qué dueño sale cada dato, qué pide Google para fichas de comercio y negocio local, y lo que falta
fuentes: [google-search-central, schema-org, repositorio]
archivos: [scripts/generate_product_seo_snapshots.dart, scripts/sync_seo_index.sh, packages/vinabike_public_core/lib/public_store/seo/public_product_structured_data.dart, packages/vinabike_public_core/lib/public_store/seo/public_business_structured_data.dart, packages/vinabike_public_core/lib/public_store/models/public_business_hours.dart, lib/public_store/utils/structured_data.dart]
tablas: [products, website_settings, spec_facts]
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
| `hasMerchantReturnPolicy` | **sólo** `merchantReturnLink` a `/devoluciones`, y sólo si esa página está publicada con contenido |

**El envío no se declara, a propósito (2026-10-04).** La tienda despacha a
«Chile continental» y **Google Search no soporta esa delimitación para Chile**:
su `DefinedRegion` lee regiones sólo en EE. UU., Australia y Japón y códigos
postales sólo en Australia, Canadá y EE. UU. `[GSC]`. schema.org sí permitiría
rangos postales, pero Google no los leería, e Isla de Pascua y Juan Fernández
son de la región de Valparaíso. `addressCountry: CL` prometería despacho a las
islas, contra lo que dice `/envios`, en una cuenta de Merchant suspendida por
«información engañosa». El retiro gratis (`FulfillmentTypeCollectionPoint`, que
Google distingue del despacho) salió con él: aporta poco solo y volverá cuando
se declare el envío. `google_merchant_identity_contract_test.dart` prohíbe
`hasShippingService` y `shippingDetails` hasta que exista una forma exacta. Se
implementó y se retiró el mismo día, después de la revisión de Codex; la función
`get_public_online_shipping_tiers` (20261004120000, aplicada) quedó para que
`/envios` lea los tramos de su dueño ([estado-y-pendientes](estado-y-pendientes.md)).
El comentario de esa migración, congelada byte a byte, todavía dice que el build
declara los tramos: es historia.

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

Envío y devoluciones se pueden declarar **una vez** en la organización desde el
2026-09-08: `hasShippingService` → `ShippingService` → `shippingConditions`;
`hasMerchantReturnPolicy` con país + categoría (+ días) **o sólo**
`merchantReturnLink`. Prioridad: Merchant Center > ficha > organización `[GSC]`.

## Lo que falta

1. **Descripciones de producto** (29 de 1.541): es contenido, no marcado.
2. ~~`geo` del local~~ y 3. ~~`addressCountry` como código~~ (2026-10-07):
   la ficha del local en Google es su dueño. El refresco diario
   (`google-public-data-refresh`) y la sincronización del editor guardan
   `seo_geo_latitude`, `seo_geo_longitude` y `seo_address_country_code`;
   `public_business_identity.dart` y `sync_seo_index.sh` publican `geo` y
   `addressCountry: CL` cuando existen (si no, el nombre del país y nada de
   `geo`). Esto es la dirección del local, no una promesa de envío: el envío
   sigue sin declararse (arriba). El refresco es el dueño: si el lugar deja de
   traerlos, los vacía en vez de dejar los de otro lugar; la sincronización
   del editor sólo escribe, porque Business Profile entrega `latlng` sólo
   cuando alguien lo fijó a mano. Ambos generadores recortan los espacios de
   cada ajuste igual. `[Prod 2026-10-08]` `-33.025195, -71.562306` y `CL`,
   publicados en el nodo de vinabike.cl.
4. Términos de devolución como campos del editor (ver arriba).
5. Envío: sólo si Google llega a aceptar una región que excluya las islas, o
   si Merchant Center lo configura por su lado (ahí sí hay más control).

## Trampas

- Dos nodos de negocio en una página (la validación del build lo rechaza).
- Un mapa propio de JSON-LD en la página o en el generador: vuelve a separar lo
  que ve Google en el snapshot de lo que ve al renderizar.
- Declarar `AggregateOffer` en una ficha: deja de ser elegible como ficha de
  comercio.
- JSON dentro de `<script>` sin escapar `<`: un nombre con `</script>` cierra el
  elemento. `encodeStructuredDataForHtml` lo escapa.
- Una regla nueva del nodo de negocio tiene **tres lectores**: el servidor HTML
  (`public_business_identity.dart`), el `index.html` de Flutter
  (`sync_seo_index.sh`, en jq) y el validador de la publicación
  (`buildExpectedLocalBusinessIdentity`, que compara el nodo de `app.html`).
  El 2026-10-07 `addressCountry: CL` entró en los dos primeros y no en el
  tercero: la publicación de la tienda falló apenas el lugar entregó el
  código, ~45 min de compuerta perdidos. El país sale ahora de una sola
  función (`publicAddressCountry`); lo que se agregue al nodo se prueba con
  los ajustes reales contra el validador antes de subirlo.

## En el código y la base

- Ficha de producto: `packages/vinabike_public_core/lib/public_store/seo/public_product_structured_data.dart`;
  la página la llama en `_updateStructuredData` (al cargar el producto, la ficha
  técnica y el recorrido de categorías).
- Negocio: identidad en `scripts/sync_seo_index.sh`; lo demás en
  `packages/vinabike_public_core/lib/public_store/seo/public_business_structured_data.dart`, aplicado por
  `completeSeoBusinessJsonLd` en `scripts/generate_product_seo_snapshots.dart`.
- Horario: `packages/vinabike_public_core/lib/public_store/models/public_business_hours.dart`.
- En la app: `lib/public_store/utils/structured_data.dart` (y su versión web).
- Base: `products`, `spec_facts` (vía `get_public_product_technical_specs`),
  `website_settings`.
- Pruebas: `test/unit/public_structured_data_test.dart`.
