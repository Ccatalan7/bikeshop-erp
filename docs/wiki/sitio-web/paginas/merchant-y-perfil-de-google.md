---
titulo: Google Merchant Center y perfil de Google
resumen: por qué la cuenta de Merchant está suspendida, qué mira Google para levantarla, cómo se arma el feed y el papel de la ficha de Google y las reseñas
fuentes: [merchant-center, consolas-google, repositorio]
archivos: [supabase/functions/google-merchant-feed/index.ts, supabase/functions/_shared/google_merchant_feed.ts, supabase/functions/google-business-reviews/index.ts, supabase/functions/google-public-data-refresh/index.ts, lib/modules/website/services/google_business_service.dart]
tablas: [products, website_settings]
revisado: 2026-10-08
---

# Google Merchant Center y perfil de Google

## Lo esencial

Merchant Center pone los productos en Google Shopping y en las fichas de compra
de la búsqueda. La cuenta de Viñabike (5635601285) está **suspendida por
«Información engañosa»**: la apelación del 27-dic-2025 se rechazó y la consola
está en período de bloqueo, sin fecha para pedir otra revisión (2026-09-23)
`[Consola]`.

## Qué mira Google en esa política

Que el sitio muestre quién es el negocio (identidad, dirección, contacto), el
**costo total** (envío, impuestos), las **condiciones de devolución**, y que lo
ofrecido se pueda cumplir (precio y stock reales). Se corrige arreglando el sitio,
sacando del feed lo que incumple y pidiendo revisión (típicamente ~7 días
hábiles) o apelando; los casos graves se suspenden sin aviso y casi no vuelven
`[MC]`. La reputación (ficha de Google, reseñas) también cuenta `[MC]`.

## Lo que ya está saneado (2026-09-23)

- Información de empresa en Merchant igual a la web: Viñabike, Álvarez 32 Local
  17, contacto@vinabike.cl, +56998357797; sitio verificado y reclamado; sin
  verificación de identidad pendiente `[Consola]`.
- Feed «PRODUCTS SOURCE 2»: 66 de 66 productos con precio y stock iguales a
  `get_public_products` `[Consola]`.
- Textos del sitio sin «Compra/Venta de bicicletas», páginas de envío,
  devoluciones, términos y privacidad publicadas, checkout funcionando
  ([checkout-y-pedidos](checkout-y-pedidos.md)).

## Lo que falta para pedir la revisión

1. **Llegar a soporte:** el formulario exige un ID de Google Ads de 10 dígitos y
   la cuenta de Viñabike no tiene. Basta crear una cuenta de Ads gratis, sin
   campaña (decisión y acción del dueño) `[Consola]`. Si no, esperar a que la
   consola vuelva a mostrar «Solicitar revisión».
2. ~~**Declarar envío y devoluciones** en los datos estructurados~~ — las
   devoluciones se declaran desde el 2026-10-04 (link a la página publicada). El
   envío **no**, a propósito: Google no puede acotar «Chile continental» y
   declarar todo Chile sería justamente información engañosa; en Merchant
   Center se configura en su propia consola ([datos-estructurados](datos-estructurados.md)).
3. **Ficha de Google y reseñas** al día (fotos, horario).
4. Fotos de 16 productos antiguos (pendiente del dueño, 2026-09-24).

## El feed

`google-merchant-feed` (Edge Function) arma el feed con la **misma proyección
pública** que la ficha y la misma regla de IVA del checkout: un producto sin
clasificación tributaria no entra. Campos propios de Merchant por producto:
`website_merchant_title`, `…_description`, `…_brand`, `…_gtin`, `…_mpn`,
`website_google_product_category`. Desde el 20-jul-2026 se usa la Merchant API
`[Repo: ONLINE_ORDER_OPERATIONS.md]`. Pocos productos tienen código de barras (5
de 1.635 con EAN), lo que limita la calidad del feed.

- **Sin código de barras no es motivo para quedar fuera** (2026-10-08). Google
  marca la falta de GTIN o MPN como «rendimiento limitado», no como rechazo
  `[MC]`; el feed omite el identificador (nunca usa el SKU de la tienda ni
  declara `identifier_exists=false`) y el diagnóstico de la ficha lo muestra
  como aviso. La regla escrita el 24-jul-2026 lo excluía, pero nunca se había
  desplegado: la función seguía en la versión del 21-jul. Al desplegarla el
  2026-10-08 el feed cayó de 65 productos a 1 y se corrigió en el acto
  (`isAdvisoryMerchantIssue`) `[Prod 2026-10-08]`.
- **Quién entra lo decide el interruptor `is_google_merchant`** de cada
  producto, no la regla: 65 marcados y 359 listos (en stock, foto, precio, IVA
  y marca real) el 2026-10-08 `[Prod]`. Marcar los demás vale la pena recién
  cuando se levante la suspensión.
- **La marca es la del fabricante.** El 2026-10-08 se asignó la marca escrita
  en el nombre a 139 productos que tenían el proveedor, el origen o nada
  (Shimano, KMC, Kenda, Mavic, Continental, Rockbros…; 39 marcas nuevas del
  tenant). No se asignó cuando la marca del nombre es compatibilidad («para
  Shimano», postizas «para Trek»), distribuidor (Bettabikes, Garozzo) o dudosa
  (Vision, Avid de AliExpress, Camelbak que el nombre web ya no dice) `[Prod]`.

## Ficha de Google (Business Profile) y reseñas

- `google-business-reviews` es el proxy de la API de Business Profile; las
  reseñas se guardan en `website_settings` (`google_reviews_*`) y las refresca
  `google-public-data-refresh` (pg_cron `google-public-data-refresh-daily`,
  08:17 UTC); el bloque `googleReviews` de la portada las muestra `[Repo]`
  `[Prod]`.
- Desde el 2026-10-07 ese mismo refresco (y la sincronización del editor con
  la ficha) guarda dónde está el local: `seo_geo_latitude`,
  `seo_geo_longitude` y `seo_address_country_code`, campos básicos de Places
  sin costo extra. El nodo `BikeStore` los publica como `geo` y
  `addressCountry: CL` ([datos-estructurados](datos-estructurados.md)).
- Places (`google_maps_place_id`) también alimenta el autocompletado del checkout
  vía `google-places-proxy`.

## Trampas

- Abrir una cuenta de Merchant nueva para escapar de la suspensión: va contra la
  política.
- Un precio o stock distinto entre el feed, el JSON-LD y la página: es justo lo
  que dispara la sanción.
- Creer que el feed y la tienda leen reglas distintas: es la misma proyección.

## En el código y la base

- Funciones: `google-merchant-feed` (`_shared/google_merchant_feed.ts`),
  `google-product-diagnostics`, `google-business-reviews`,
  `google-public-data-refresh`, `google-places-proxy`.
- ERP: `Integraciones` del editor; `google_business_service.dart`.
- Datos: campos `website_merchant_*` de `products`; `google_*` de `website_settings`.
