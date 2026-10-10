---
titulo: Catálogo, categorías y fichas de producto
resumen: qué producto sale en la tienda y por qué, cómo se arman categorías, facetas, búsqueda y la ficha pública, y qué pasa con los agotados
fuentes: [repositorio, google-search-central]
archivos: [lib/modules/website/catalog/website_catalog_workspace.dart, lib/modules/website/catalog/catalog_web_models.dart, packages/vinabike_public_core/lib/shared/models/public_product_visibility_policy.dart, packages/vinabike_public_core/lib/public_store/models/public_category_route.dart, packages/vinabike_public_core/lib/public_store/models/public_catalog_facets.dart, services/storefront_html/lib/src/catalog_page_model.dart, packages/vinabike_public_core/lib/public_store/seo/public_catalog_seo.dart, packages/vinabike_public_core/lib/public_store/models/public_commerce_product_projection.dart, packages/vinabike_public_core/lib/public_store/models/public_product_seo_copy.dart, lib/public_store/pages/product_catalog_page.dart, lib/public_store/pages/product_detail_page.dart, packages/vinabike_public_core/lib/public_store/utils/public_spec_display.dart, packages/vinabike_public_core/lib/modules/website/models/website_catalog_price_list.dart, services/storefront_html/lib/src/catalog_price_list_view.dart, lib/public_store/widgets/catalog_price_list_view.dart]
tablas: [products, product_categories, product_url_aliases, website_settings, featured_products, catalog_issue_dismissals]
revisado: 2026-10-10
---

# Catálogo, categorías y fichas de producto

## Lo esencial

La tienda muestra el inventario del ERP: no hay un catálogo aparte. Un producto
sale en la web si **el producto lo permite** y **la política del sitio lo deja
pasar**, y todo consumidor (tienda, snapshots, sitemap, feed de Merchant,
checkout) lo decide con la misma proyección pública `[Repo]`.

## Cuándo sale un producto

**Desde el 2026-10-10 lo decide una sola regla en la base**,
`catalog_product_web_block_v1(producto, política)` (migraciones `20261010010000`
y `20261010020000`). La aplican todas las lecturas públicas
(`get_public_products` y lo que la envuelve: catálogo con filtros, búsqueda,
destacados, feed de Merchant; además el alias de URL y la clasificación de IVA
pública) **y el checkout**, que rechaza un id que la regla no deja vender
aunque llegue directo `[Repo]` `[Prod 2026-10-10]`. El ERP no la vuelve a
calcular: lee su resultado con `catalog_web_items_v1` y muestra el primer
escalón que falla como motivo, en palabras.

La escalera, de arriba abajo; el primero que calza es el motivo:

| Paso | Código | Para quién |
|---|---|---|
| Consumible del taller | `workshop_consumable` | nunca sale; un disparador (`zz_guard_consumable_off_web`) rechaza encenderle la web y apaga web, Merchant y WhatsApp |
| Inactivo | `inactive` | todos |
| «Vender en la web» apagado | `web_off` | todos (un solo interruptor: `is_published` y `show_on_website` juntos) |
| Sin IVA clasificado | `missing_tax` | productos (0, 19 o el 0,19 histórico); un servicio no pasa por el carrito |
| Sin precio | `missing_price` | todos, salvo un servicio «A cotizar» |
| Bajo el costo con IVA | `below_cost` | productos con costo, salvo liquidación vigente (`web_clearance_until`) |
| Falta foto / nombre web / descripción / marca | `missing_image`, `missing_web_name`, `missing_description`, `missing_brand` | según los ajustes; foto, nombre y marca sólo productos (foto desde `20261010040000`: `/servicios` es una lista sin fotos) |
| Categoría que no se muestra | `category_hidden` | sólo si el ajuste lo pide |

Estados en el ERP: **En venta**, **Agotado** (se vende, sin stock: la ficha
queda con «Agotado»), **Falta algo**, **Oculto** (apagado o inactivo) y
**Taller** (consumibles). La política del sitio (`website_settings`) quedó así
el 2026-10-10 `[Prod]`:

| Clave | Valor | Efecto |
|---|---|---|
| `product_visibility_stock_policy` | `available_only` | los listados muestran sólo lo que tiene stock; la ficha del agotado sigue |
| `product_visibility_require_image` | `true` | un producto sin foto no sale |
| `product_visibility_include_uncategorized` | `false` | |
| `product_visibility_require_visible_category` | `false` | la categoría del menú no decide qué se vende |
| `product_visibility_require_web_name` | sin fijar (no) | se dejó apagado: el único a la venta sin nombre web se lee bien con el del ERP |

Cifras del 2026-10-10, después de lo aplicado abajo `[Prod]`: 428 productos en
venta (y 3 kits), 755 agotados, 225 «falta algo», 50 ocultos, 157 del taller;
54 servicios publicados. El listado público sigue en ~70 ms.

**Cerrado 2026-10-10 — los consumibles del taller se vendían.** La excepción
del stock (`track_stock = false` pasa siempre) servía a los servicios, pero un
consumible tiene `track_stock` forzado a `false` y salía listado con carrito
(100 el 2026-10-09). Ahora la regla los para antes de mirar el stock, el
disparador impide volver a marcarlos y el checkout los rechaza. La excepción
sigue existiendo para productos sin control de stock que no son consumibles.

### Lo aplicado con el catálogo nuevo (2026-10-10)

Todo desde la pantalla, como lo haría una persona `[Prod 2026-10-10]`:

- **Servicios duplicados fuera de la web:** Sangrado (queda Purgado),
  Instalación de cámara (queda Cambio de cámara $1.990), Servicio de mazas
  (queda Mantención de maza), Inflado de rueda $0 (queda Presión), Tubeless
  Bettabikes y Mecánica básica/media/mayor. **Publicada** la Mantención Full
  hidráulicos $90.000. **«Desde $1.000»** en Instalación de piezas o partes.
  Arriendo de bicicleta quedó como estaba.
- **IVA 19 %** a los 19 productos marcados sin clasificar (repuestos comunes).
- **GTIN:** 175 SKU que son códigos de barras reales copiados al GTIN (se
  pueden deshacer); 2 descartados por ser el código de muestra «6901234…».
- **Archivadas** 7 fichas que no eran productos (nombres de proveedor y
  gastos), sin uso en compras, ventas ni taller.
- **Destacados por ventas**, uno por categoría antes de repetir (16 elegidos),
  y el bloque «Productos Destacados» de la portada pasó de «Manual» (4, dos
  agotados) a la fuente «Destacados»: muestra los 6 primeros a la venta y, si
  uno se agota, entra el siguiente solo.
- **Un destacado nuevo pasa por la regla** (`20261010060000`, revisión de
  Codex): si dejó de venderse entre abrir la pantalla y tocar «Agregar», la
  base no guarda nada y dice cuál y por qué. Los que ya estaban se conservan
  aunque hoy no pasen (la portada los salta y vuelven solos); un consumible
  sale siempre. Los 16 de producción estaban a la venta ese día `[Prod
  2026-10-10]`.

## Agotados

Desde el 2026-09-23 una ficha agotada **sigue existiendo**: la página abre con
«Agotado», su JSON-LD dice `OutOfStock` y sigue en el sitemap; sólo los listados
la esconden (migración `20260923210000`; recuperó la ficha de 756 de 901
agotados) `[Repo]`. Antes, un producto que se agotaba desaparecía del build y su
URL moría; para Google eso es perder la página, no «sin stock». Google prefiere
la misma URL con la disponibilidad correcta `[GSC]`.

## Categorías

- 137 categorías activas, **30 visibles en la tienda** desde el 2026-10-08 (11
  hasta ese día) `[Prod]`. En el ERP la categoría agrupa las líneas del taller;
  en la tienda sólo navega. No publica productos.
- **Cada categoría es una página que Google puede mostrar** para lo que la
  gente busca («neumáticos para bicicleta», «luces para bicicleta»). El
  2026-10-08 se publicaron 19 con al menos 7 productos en stock y búsqueda
  propia: Neumáticos, Llantas, Mazas, Rayos, Tubeless, Pastillas, V-Brake,
  Desviadores, Shifters, Postiza, Motores, Piñones, Tee, Fundas y piolas,
  Luces, Asientos, Pedales, Mantenimiento y Lubricantes. Quedaron fuera
  «Frenos Hidráulicos» (son olivas y mangueras: el título engañaría),
  «Herramientas» (dos categorías con ese nombre: el slug es ambiguo) y las de
  menos de 7 en stock. Publicar no agrega nada al menú (lo arma
  `website_navigation`); suma la página, el sitemap y las subcategorías de su
  madre `[Prod]`.
- **El texto que presenta la categoría** es `product_categories.description`
  («Descripción» de la categoría en el ERP), salvo que el editor ponga uno en su
  portada: se ve bajo el título y es la meta descripción. Las 30 publicadas lo
  tienen desde el 2026-10-08 (antes ninguna; Google leía «157 productos
  publicados en Ruedas de Viñabike.»). Se escribió con lo que hay en stock
  (marcas y medidas reales) y con los servicios del taller que existen.
- **El título por defecto** es «{Categoría} para bicicleta | {tienda}
  {ciudad}» («… de bicicleta» en una categoría de servicios; sin agregado si
  el nombre ya dice bici), desde el 2026-10-08; antes «Ruedas | Viñabike».
  El título SEO de su portada en el editor manda sobre la fórmula
  (`public_catalog_seo.dart`).
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
publicada (30 desde el 2026-10-08; 11 antes) se
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
  catálogo y del más barato al más caro. El precio dice lo que el ERP marcó en
  el servicio (`products.website_price_mode`, 2026-10-10): exacto, **«Desde
  $X»** (precio de partida) o **«A cotizar»** (sin precio; el checkout igual
  rechaza $0). La ficha del servicio dice lo mismo, y su JSON-LD ofrece
  `AggregateOffer` con `lowPrice` para «Desde» y ninguna oferta para «A
  cotizar». Anónimo lee la columna con la identidad web
  (`publicProductIdentityColumns`, `20261010030000`). Se
  filtra al escribir (sin acentos) y, sin script, con `?q=`.
- **Cierre:** título, texto y botón, opcional.

Las categorías de servicios agrupan igual las líneas del taller (G1): las 10
subcategorías de «Servicio» (Mantenciones, Frenos, Transmisión, Cables y fundas,
Ruedas, Dirección, Suspensión, Limpieza, Revisión general, Armado y arriendo)
se crearon el 2026-10-06 con 66 servicios; 62 públicos. Ninguna se publica en
la navegación: la lista las usa como grupos, no como páginas `[Prod 2026-10-06]`.

La lectura pública corta en 100 filas: el servidor lee de a 100 hasta tener
todo (`_wholeListing`); la primera página va junto con la del menú para no
sumar una espera. Desde el 2026-10-10 un servicio no necesita foto para
salir (la lista no las muestra); los que tienen, la llevan en su ficha.

## La ficha pública

- Una sola proyección (`PublicCommerceProductProjection`) alimenta la ficha
  Flutter, la página instantánea, el snapshot HTML y el feed de Merchant.
- Campos web propios del producto: `website_name`, `website_description`,
  `website_price`, `website_image_url(s)` y la versión optimizada, y los de
  Merchant (`website_merchant_title`, `…_description`, `…_brand`, `…_gtin`,
  `…_mpn`, `website_google_product_category`) `[Repo]`.
- **Nombre y descripción para el cliente (llenado del 2026-10-08)** `[Prod 2026-10-08]`:
  las 1.295 fichas visibles y 59 de los 62 servicios tienen `website_description`
  propia, y ~1.200 un `website_name` limpio (antes: 52 descripciones, 429
  nombres en MAYÚSCULAS con códigos de proveedor como «AE», «C/U»,
  «COMPATIBLE / GENERICO ALTERNATIVO 2022 ECONOM.»). Se editan en el ERP
  («Nombre web» y «Descripción web» del producto). Las reglas con que se
  escribieron, para el producto que entre después:
  - nombre: tipo de pieza en palabras de taller chileno («Cámara»,
    «Caramagiola», «Desviador delantero», «Tubo de asiento»), marca, modelo
    que la gente busca (RD-M310, CS-HG31), la medida clave con punto
    («29 x 2.25», «31.8 mm») y la variante; sin «Genérico», sin códigos de
    proveedor, y sin una marca de lujo en un producto de AliExpress que la
    copia (ODI, FOX), que es una imitación;
  - descripción: qué es, para qué bici o uso, la compatibilidad que dan sus
    datos y qué medir antes de comprar; sólo hechos de su nombre, su ficha o
    el modelo conocido; nunca el stock (cambia);
  - un servicio dice qué incluye y cuándo hace falta. Los tres planes de
    mantención («Mantención Básica», «Semi», «Full») **no** llevan
    `website_description`: sus tarjetas en `/servicios` leen la lista numerada
    de `description` (`catalogPlanIncludes`) y un texto web la reemplazaría.
- Cambiar el nombre web cambia la URL; la anterior queda en
  `product_url_aliases` y responde 301 por el SKU `[Prod 2026-10-08]`.
- **La ficha de un servicio** (`product_type = 'service'`) se agenda, no se
  compra `[Repo 2026-10-08]`: miga Inicio › Servicios › su grupo, el botón de
  la portada de `/servicios` (su texto) con un WhatsApp que nombra el servicio
  y su precio, «Se hace en el taller» con la dirección de retiro, «Detalles del
  servicio» y «Otros servicios del taller»; sin stock, SKU, carrito ni
  despacho. Antes decía «En stock», «Agregar al carrito» y «Despacho a
  domicilio desde $6.990». Las fichas de servicio entran al sitemap.
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
- Un producto nuevo sin foto no aparece en la tienda aunque esté marcado para
  la web: el catálogo del ERP lo pone en «Falta algo › Falta foto» y en «Por
  resolver». Sin categoría cae además en «General» en el taller.
- «Sin control de stock» no significa servicio. Un consumible del taller tampoco
  lleva stock, y toda regla que trate `track_stock = false` como «siempre
  disponible» lo publica (pasó hasta el 2026-10-09, arriba). La pregunta es el
  tipo de ítem (`product_type`, `purchase_treatment`), no el stock.
- El código de barras suele estar guardado como SKU: 178 SKU numéricos de 8, 12,
  13 o 14 dígitos con dígito verificador correcto, sin GTIN, y que no empiezan
  con 2 (los que empiezan con 2 son códigos internos) `[Prod 2026-10-09]`. Un
  dígito verificador correcto no prueba que el código sea real: «6901234…» es
  el número de muestra que traen productos genéricos chinos. Antes de copiar
  en bloque, mirar los prefijos (2026-10-10: 175 copiados, 2 descartados).
  **Corrige** «5 de 1.635 con EAN» (2026-10-02), que sólo miraba la columna
  `gtin`. Merchant: 79 de los 82 marcados van sin GTIN
  ([datos-estructurados](datos-estructurados.md)).
- Un precio cargado igual al costo: 35 de los 59 productos marcados que quedan
  bajo el costo con IVA tienen `price = cost` exacto `[Prod 2026-10-09]`.

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
- Páginas: `product_catalog_page.dart`, `product_detail_page.dart`.
- Catálogo del ERP (editor «Catálogo» y ruta `/website/product-visibility?tab=`,
  2026-10-10): `lib/modules/website/catalog/` — `website_catalog_workspace.dart`
  (pestañas Productos, Por resolver, Servicios, Categorías, Destacados y
  Reglas), `catalog_web_controller.dart` (una proyección para todas las
  pestañas), `catalog_web_service.dart` (sólo comandos `catalog_*`) y cada
  vista con su vista previa de la página real. Base: `catalog_web_items_v1`,
  `catalog_set_web_sale_v1`, `catalog_copy_sku_to_gtin_v1` (y deshacer),
  `catalog_set_clearance_v1`, `catalog_set_price_mode_v1`,
  `catalog_classify_tax_v1`, `catalog_convert_item_v1`,
  `catalog_dismiss_issue_v1` (tabla `catalog_issue_dismissals`),
  `catalog_archive_empty_records_v1`, `catalog_category_counts_v1`,
  `catalog_featured_suggestions_v1`, `catalog_replace_featured_v1`. Las páginas
  viejas (`product_website_visibility_page.dart`, `featured_products_page.dart`)
  se retiraron; `/website/featured` redirige a la pestaña Destacados.
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
