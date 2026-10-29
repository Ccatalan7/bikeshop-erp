---
titulo: Catálogo, categorías y fichas de producto
resumen: qué producto sale en la tienda y por qué, cómo se arman categorías, facetas, búsqueda y la ficha pública, y qué pasa con los agotados
fuentes: [repositorio, google-search-central]
archivos: [lib/modules/website/catalog/website_catalog_workspace.dart, lib/modules/website/catalog/catalog_web_models.dart, packages/vinabike_public_core/lib/shared/models/public_product_visibility_policy.dart, packages/vinabike_public_core/lib/public_store/models/public_category_route.dart, packages/vinabike_public_core/lib/public_store/models/public_catalog_facets.dart, services/storefront_html/lib/src/catalog_page_model.dart, packages/vinabike_public_core/lib/public_store/seo/public_catalog_seo.dart, packages/vinabike_public_core/lib/public_store/models/public_commerce_product_projection.dart, packages/vinabike_public_core/lib/public_store/models/public_product_seo_copy.dart, lib/public_store/pages/product_catalog_page.dart, lib/public_store/pages/product_detail_page.dart, packages/vinabike_public_core/lib/public_store/utils/public_spec_display.dart, packages/vinabike_public_core/lib/modules/website/models/website_catalog_price_list.dart, services/storefront_html/lib/src/catalog_price_list_view.dart, lib/public_store/widgets/catalog_price_list_view.dart, packages/vinabike_public_core/lib/modules/website/models/website_catalog_guide.dart, lib/public_store/widgets/catalog_collection_guide.dart, packages/vinabike_public_core/lib/public_store/seo/storefront_seo_route.dart, services/storefront_html/lib/src/product_question_view.dart, packages/vinabike_public_core/lib/public_store/models/public_product_question.dart]
tablas: [products, product_categories, product_url_aliases, website_settings, featured_products, catalog_issue_dismissals, catalog_search_terms, catalog_search_misses, catalog_search_documents, catalog_search_words]
revisado: 2026-10-29
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
| `product_visibility_search_out_of_stock` | sin fijar (`offer`) | una búsqueda ofrece «Incluir agotados» (2026-10-24); `hide` la cierra |
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
- **La marca está en el nombre** (2026-10-11, `20261011010000`–`030000`):
  aviso nuevo de «Por resolver» con un toque y deshacer. Salta cuando un
  producto a la venta no tiene una marca real enlazada y el nombre que ve el
  cliente nombra exactamente una (palabra entera, no después de «para»,
  «compatible con», «tipo» o «réplica», y sin las marcas que son palabras
  comunes del catálogo: «Doble», «PRO», «Velo»); no pisa una marca escrita
  que diga otra. Aplicado con la pantalla: las 2 llantas Vision que tenían de
  marca al distribuidor «Andes Industrial» (Google las marcó sin
  identificador) y 39 productos con la marca escrita a mano pero sin enlazar
  (Shimano, ZTTO, Maxxis, Bucklos, SunRace…), que el filtro de marcas de la
  tienda no encontraba. «A la venta sin marca» bajó de 111 a 73 `[Prod
  2026-10-11]`. Una cámara («…(NO ES EXACTAMENTE LA MISMA: 1.50X2.2
  ORNATE)» en su nombre del ERP) mostró por qué la regla lee sólo el nombre
  que se ve: una nota de inventario no es la marca de la ficha. Después de la
  revisión de Codex (`20261011040000`, sin P0): deshacer sólo vuelve a una
  marca global o del tenant y si nadie cambió ni el enlace ni el texto; el
  comando pide lo mismo que la lista (un producto que hoy se vende); el «para
  …» se mira sobre el texto sin puntuación («compatible con: Shimano»); el
  texto pierde los acentos («Ohlins» = «Öhlins»), y sólo se sugiere una marca
  que algún producto de la tienda ya usa, para que una marca que es una
  palabra («One», «Race») no salte sola. Destacados toma los productos
  pedidos (`FOR SHARE`, antes que su candado: `20261011050000`) mientras
  comprueba y guarda. Aceptado en la segunda pasada, con su motivo: deshacer
  recibe el recibo de la pantalla, pero no permite nada que la ficha del
  producto no permita ya; la primera ficha de una marca nueva se enlaza a
  mano (después la regla la sugiere); una marca en uso que también es palabra
  puede sugerirse, y cada fila muestra «X → Y» antes del toque; si la política
  o la categoría cambian justo al guardar un destacado, la portada lo salta al
  leer.

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
- **Qué categorías se publican** (2026-10-25, corrige el criterio del
  2026-10-08 «≥7 en stock y búsqueda propia»): toda categoría del menú del
  encabezado con algo a la venta, también por sus subcategorías. Publicar
  decide el menú, no sólo Google ([rutas](rutas-y-navegacion.md)); con 1 o 2 a
  la venta la página se ve y dice `noindex,follow`, apunta a la categoría
  publicada de arriba y no entra al sitemap. La nota de `Catálogo web ›
  Categorías` nombra las del menú sin publicar y las publica todas con un
  botón; 85 de 147 publicadas ese día `[Prod 2026-10-25]`.
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
  foto del menú desplegable; desde el 2026-10-25 sólo la foto: el riel nuevo
  la muestra tal cual, y oscurecerla, su ancho y dónde va el texto quedaron
  guardados sin control ni lector), **Imagen al compartir** y **Restablecer**; los
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

## Guía, páginas por medida y cifras al día (2026-10-23)

El dueño pidió que las categorías usen lo que usan las tiendas grandes, no
sólo el marcado («nosotros debemos estar a la altura de grandes empresas»)
`[Dueño 2026-10-23]`. Lo técnico ya estaba (HTML completo, canonical,
`CollectionPage`, `ItemList`, migas); faltaba contenido y estructura, y eso
llevaba pendiente desde el 2026-10-04 (brechas 4 y 6 de
[referentes](seo-de-referentes.md)). Desde este día una categoría tiene, en su
página del editor:

- **Guía y preguntas** (sección propia): título, texto (párrafos separados
  por una línea en blanco), preguntas con su respuesta y un enlace «Para leer
  más» (la guía del taller, un servicio, una página por medida). Se dibuja bajo
  los productos, con las preguntas que se abren de a una y su `FAQPage`
  (Google reserva sus resultados de preguntas para salud y gobierno; Bing y
  los asistentes las leen) `[Repo]` `[GSC]`. Una pregunta sin respuesta o un
  enlace sin texto o destino quedan en el borrador y no se muestran.
- **Páginas por medida o marca**: una página propia para lo que se busca
  («cámaras aro 26», «neumáticos Kenda»), con los productos de la categoría y
  un filtro fijo, en `/productos/categoria/<categoría>/<página>`. Tiene su
  nombre en el enlace, dirección, título, texto, título y descripción en
  Google, «Que Google la muestre» y su propia guía. La categoría las enlaza
  bajo su portada («Por aro: Aro 26 · Aro 29 / 700c»); en una de ellas, «Ver
  todo» vuelve a la categoría y el filtro fijo no se ofrece otra vez. Se
  agregan desde los valores reales de la lista (con cuántos productos tiene
  cada uno). **No se generan combinaciones**: cada página es una decisión del
  editor y el resto de las direcciones filtradas sigue `noindex` con la
  categoría como canonical. Con menos de 3 productos la página se ve pero dice
  `noindex` y apunta a su categoría, y no entra al sitemap; la categoría
  filtrada justo por el valor de una página va por 301 a ella, y una página
  borrada o renombrada va por 301 a su categoría `[Repo]`.
- **Cifras al día en los textos de Google**: `{cantidad}`, `{desde}`,
  `{hasta}` y `{marcas}` se llenan con la lista de la propia página cada vez
  que se dibuja, así un precio en el título nunca queda viejo (la lección de
  las guías, donde «Desde $24.990» se cotejó a mano). Si falta una cifra (las
  cuentas no respondieron), la página usa su fórmula en vez de una frase con
  un hueco. El editor muestra qué dice hoy y el centro SEO lee lo mismo
  `[Repo]`.
- **Paginación**: la página 2 en adelante de un catálogo, sin nada más en la
  dirección, es su propia página canónica (`?page=2`) e indexable, como pide
  la guía de paginación de Google; hasta este día decía `noindex` y apuntaba a
  la página 1, así que lo listado sólo ahí llegaba a Google únicamente por el
  sitemap `[GSC]` `[Repo]`.

**Cuidado con el 29 y el 700c.** Son el mismo aro (622 mm): una página «aro
29» lista también los 700c. El nombre la dice («Aro 29 / 700c») y su texto
explica el ancho, que es lo que los separa ([ruedas y
neumáticos](../../compatibilidad/paginas/ruedas-y-neumaticos.md)).

**En vivo desde el 2026-10-23** `[Prod 2026-10-23]`: guía con tres preguntas
en cámaras, neumáticos, llantas, pastillas y rayos, y 12 páginas: cámaras y
llantas aro 29 / 700c, 26 y 27.5; neumáticos aro 29 / 700c, 26, 27.5 y Kenda;
pastillas para freno de disco y zapatas para freno de llanta. Diez son
indexables; cámaras y neumáticos aro 27.5 tienen 2 productos y quedan
`noindex` hasta tener 3. Se escribió como un guardado del editor (registro
entero por `updated_at`, versión «Al guardar · /productos/categoria»), recién
con la 1.0.38 publicada en macOS, Android y web.

**21 categorías más desde el 2026-10-29** `[Prod 2026-10-29]`: guía con tres
preguntas y textos de Google propios en Componentes (lo que se busca como
«repuestos»), Ruedas, Mazas, Frenos, Cálipers, Transmisión, Cadenas, Piñones,
Motores, Volantes, Cambios, Dirección, Manubrios, Horquillas, Accesorios,
Luces, Bombines, Pedales, Asientos, Mantenimiento y Lubricantes. `/productos`
pasó a titularse «Repuestos y accesorios para bicicleta en Viña del Mar».
Se eligieron por las búsquedas que Google ya les mostraba y por tener al menos
3 productos a la venta. Los datos técnicos salen del [wiki de
compatibilidad](../../compatibilidad/index.md) y las palabras, del [taller
chileno](../../compatibilidad/paginas/palabras-del-taller.md). Se escribió con
el mismo modelo del editor (`prepareForSave`, `put`, `encode`, ida y vuelta
idéntica y las 10 entradas no tocadas byte a byte iguales), con compare-and-set
por `updated_at` y dos versiones «Al guardar · /productos/categoria». La razón
para seguir por ahí: las páginas por medida del 23-oct salieron mejor que su
categoría en su primera semana (neumáticos aro 26 en posición 20, llantas aro 26
en 14) contra 27–38 de las categorías generales `[GSC 2026-10-28]`.

**`{desde}` sólo en una categoría de una sola pieza.** Toma el producto más
barato de la lista. En Frenos era una pieza de $300 y el título decía «Frenos de
bicicleta… desde $ 300», y Mantenimiento decía «desde $ 200». En una categoría
que mezcla piezas (las madres, y las que tienen ejes, espaciadores o coronas
dentro) el título va sin precio. Con precio quedan las de un solo tipo:
cadenas, luces, bombines, pedales, cálipers, manubrios, horquillas y
lubricantes. `{marcas}` tampoco sirve cuando casi todo es sin marca: Luces
decía «8 luces… de Giyo» con una sola Giyo `[Prod 2026-10-29]`.

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
  reclamo, es un hecho del catálogo. Al lado del nombre, uno largo
  («Mantención Full (bici rígida, frenos hidráulicos)») la corta en el borde:
  el 2026-10-24 se pasó a una pestaña colgada de la tarjeta, pero se revirtió
  con el resto del rediseño y sigue pendiente de mostrarle al dueño.
  Títulos, nombres y botones van como se escriben (antes en mayúsculas, y
  «AGENDAR POR WHATSAPP» se partía en dos líneas en una tarjeta de 1/4)
  `[Repo]`.
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

- **Aspecto (dueño, 2026-10-24: «toma como referencia a Canyon y
  Specialized»).** La foto principal y las miniaturas van sobre un gris claro
  plano (el texto de la ficha al 6 % sobre blanco, ≈ `#F2F2F3`: `--stage` en HTML, `commerceStage` en Flutter), con esquinas rectas. La foto blanca del proveedor se
  multiplica en ese gris, y en el teléfono la foto va de borde a borde. El
  nombre se escribe como en el catálogo, sin mayúsculas forzadas. Así lo
  miden las dos marcas ([referentes](../fuentes/referentes.md)), en
  `storefront_css.dart` (`.stage`) y en `_buildProductImageStage` de Flutter
  `[Repo 2026-10-24]`.
  Desde tableta, el gris llega al borde de la ventana (62 % del ancho; 56 %
  bajo 1100 px). Una línea cierra la sección arriba y abajo, y otra la separa
  de la columna de compra. Las migas van en una fila propia sobre la foto:
  una línea, alineada con el logo, con chevrones y el producto al final (en
  el teléfono sin el producto, que es el título de abajo). El dueño no quiso
  las migas sobre el título: «el breadcrumb aún puede ir de forma elegante en
  una fila independiente arriba de la foto» `[Dueño 2026-10-24]`.
  Los datos clave son una tabla de líneas, no una caja. Mientras se recorre
  la columna de compra la foto sigue a la vista (`position: sticky`, bajo
  `--top-h`, la altura del encabezado que mide el script). El dueño lo pidió
  al ver la foto dentro del margen: «ours looks cheap not being edge to edge
  of the gray part on desktop». La ficha de Flutter (lienzo del editor) dibuja
  lo mismo, salvo que la foto no queda fija `[Repo 2026-10-24]`.
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
  ninguno `[Prod 2026-10-06]`. Sin ellos, el despacho dice las zonas del
  checkout (`get_public_online_shipping_tiers`, por `PublicShippingPromise` del
  núcleo): «Región de Valparaíso desde $ 6.490, 1 a 3 días hábiles. Resto de
  Chile continental desde $ 7.490, hasta 10 días», y el pago, «Chile
  continental, 1 a 10 días hábiles según tu región». Hasta el 2026-10-23 la
  ficha decía el plazo de la zona más cercana como si fuera el de todo Chile y
  el checkout tenía escrito a mano «3 a 12 días», un plazo que ninguna zona
  tiene `[Prod 2026-10-23]`.
- **Relacionados que calzan** (2026-10-23): hasta 48 de la categoría en stock,
  ordenados por cuántos valores filtrables de la ficha técnica comparten con el
  producto (`get_public_related_fit_v1`, migración `20261024010000`); si alguno
  comparte, los que no comparten nada no salen. Bajo el neumático de ruta
  Freedom Comet 700 x 23C salían neumáticos de 20″, 24″ y 26″; ahora, los 700c
  y aro 29 `[Prod 2026-10-23]`. La vista previa del editor ordena con la misma
  función (`rankRelatedByFit` del núcleo).
- **Lo que va con esto** (2026-10-23): en la ficha de un neumático, las
  cámaras en stock cuyo rango (`tube_fit_rows`: aro, ancho mínimo y máximo)
  incluye su aro y su ancho (`bead_seat_diameter_mm`, `tire_width_mm`); en la
  de una cámara, los neumáticos que calza. Del más barato al más caro, cada
  una con «Agregar» al carrito sin salir de la ficha
  (`get_public_product_fits_v1`, migración `20261024020000`). La válvula no se
  decide: depende del agujero de la llanta y la sección lo dice. Se muestra u
  oculta y se titula en el editor («Lo que va con esto», plantilla de ficha);
  qué calza lo decide la ficha técnica. Bajo el Freedom Comet 700 x 23C: las
  dos RBX 700 x 18-25C en stock; bajo un 29 x 2.10, cuatro cámaras aro 29
  `[Prod 2026-10-23]`.
- **Barra de compra en el teléfono** (2026-10-24): bajo 768 px, el nombre, el
  precio y «Agregar al carrito» quedan fijos abajo mientras el botón de la
  ficha no está a la vista (al abrir la ficha en un teléfono ese botón queda
  bajo el primer pantallazo, y al bajar por la ficha técnica se perdía). Su
  botón aprieta el de la ficha (misma cantidad, mismo `add_to_cart`) y dice
  «Agregado»; el chat sube sobre ella. Nunca para un producto agotado, sin
  precio o un servicio. Se apaga en «Botones» de la plantilla («Barra de
  compra fija en el teléfono», `show_sticky_buy_bar`, activa por defecto).
  HTML: `.buybar` (`product_page_view.dart`, `storefront_css.dart`,
  `storefront_script.dart`); Flutter: `_buildBuyBar` en un `OverlayPortal`,
  nunca bajo Editar ni Vista previa, y `CustomerChatWidget.bottomInset` sube
  el chat `[Repo]`.
- **Pregunta por este producto** (2026-10-24, dueño: «hay clientes que nos
  han hablado preguntando por productos, pero tienen que describirlos»): bajo
  la compra, una caja «¿Tienes dudas con este producto?» (agotado: «¿Lo
  necesitas?», con más color) con WhatsApp y Chat. Cualquiera de los dos abre
  una hoja con el producto (foto, precio, SKU, stock), preguntas para tocar
  según el producto (`PublicProductQuestion.suggestions` del núcleo: en
  stock, «¿Lo tienen para retiro hoy?»; agotado, «¿Cuándo les llega?» y
  «¿Tienen algo parecido?»; con ficha técnica, «¿Le sirve a mi bicicleta?» y,
  en stock, «¿Me lo instalan en el taller?») y el texto del cliente. El
  mensaje lo arma un solo dueño (`PublicProductQuestion.message`): el nombre,
  SKU, precio y enlace del producto, y después la pregunta. «Enviar por
  WhatsApp» abre `wa.me` con eso; «Enviar por el chat» crea la consulta del
  portal como cliente (`/cuenta/accion`, `chat-new` con `product`, que llega a
  `create_customer_support_request` con el contexto `product`: en Mensajería
  la conversación dice «Producto» y «Abrir producto»). Sin sesión, la pregunta
  queda en la pestaña (`sessionStorage` `vb-question`, 30 min), el login
  vuelve a la ficha (`vb-after-login`, sólo una ruta de la tienda) y se envía
  sola una vez; si al volver no hay cliente, la hoja lo dice en vez de salir
  otra vez. La tarjeta de ayuda bajo la ficha técnica abre la misma hoja con
  «¿Le sirve a mi bicicleta?» marcada. Sin JavaScript, los enlaces de la caja
  van a WhatsApp con el producto y a `/cuenta/chats`. En el teléfono la hoja
  sube desde abajo y el campo no toma el foco (el teclado tapaba las
  preguntas). Se muestra u oculta y se titula en «Preguntas» de la plantilla
  (`show_ask`, `ask_title`; el título también se escribe sobre la ficha en el
  editor); los servicios siguen con su «Agendar por WhatsApp». HTML:
  `product_question_view.dart` (caja, hoja, CSS y script); Flutter:
  `_buildQuestionBox` en `product_detail_page.dart` (lleva directo a cada
  canal, sin hoja) `[Repo]`.

## Búsqueda

`search_public_products` (texto) y el catálogo con facetas
(`get_public_products_faceted_v2`). La búsqueda semántica (`search_products`,
`match_products_semantic`) no está abierta a visitantes desde el 2026-09-23 `[Repo]`.

**Entiende el taller desde el 2026-10-24** (`20261024030000`, en producción
`[Prod 2026-10-24]`). La búsqueda que comparten el catálogo, sus facetas, el
buscador del encabezado y la lista de Flutter
(`get_public_products_without_inventory_reservations`) dejó de exigir que cada
palabra esté escrita en el producto. El dueño, probando el buscador: «the
search should be WAY SMARTER in terms of tech specs intuition»; «camara fv» no
encontraba nada y «29x2.25» tampoco.

- **Vocabulario como datos** (`catalog_search_terms`, 94 conceptos): las
  palabras chilenas primero, medidas en los pedidos del taller
  ([palabras del taller](../../compatibilidad/paginas/palabras-del-taller.md)),
  y después las de otros países y del inglés. Un producto cuyo nombre,
  categoría o ficha dice una palabra de un concepto responde a todas. Una
  **parte** sólo la dicen el nombre y la categoría; un **atributo** (válvula,
  tubeless, uso, recargable) también la ficha técnica
  (`spec_public_facet_values_compute_internal_v1`, la misma de los filtros).
  Una frase («pata de cambio») trae el concepto y sus palabras, salvo la que
  nombra otra parte por sí sola o une: «sin cámara» hace tubeless una llanta,
  no la vuelve cámara (`20261024040000`; el dueño vio una llanta tubeless y un
  obús entre las cámaras de «camara fv»).
- **Lo que es primero**: el concepto con que empieza el nombre («Motor
  sellado») pesa más que el de su categoría, y éste más que una mención; una
  búsqueda que es exactamente el nombre de lo que el producto es («pata de
  cambio», «motor») lo pone arriba.
- **Lo que se escribe** (`catalog_search_normalize_v1`): «29x2.25» es «29
  2.25», «11 velocidades», «11s» y «1x11» son «11v» (un «1/2x11/128» de cadena
  no), «29er» es 29, «700c» es 700, «27.5» es también «650b».
- «de», «para» y parecidas no se exigen; «bicicleta», «aro», «rin» cuentan si
  están pero no se exigen. Una o dos letras empiezan una palabra («av» ya no
  se encuentra dentro de «llave»).
- Medido en producción: «camara fv» 4 → 48, «balatas» 0 → 43, «caramayola»
  0 → 15, «masa trasera» 0 → 33, «piñon 7v» 2 → 39, «pedalier» pone los
  motores antes que la llave; 0,47–0,54 s por búsqueda contra 0,36–0,86 s
  antes (todos los productos, sin el filtro de stock).
- **Trampa que costó una vuelta**: la primera versión calculaba el vocabulario
  por producto y por concepto en subconsultas; Postgres las repetía en cada
  referencia y tardó 9,4 s. El read-back del despliegue lo cortó a los 30 s, se
  restauró la función anterior en ~2 min y se rehízo como un join de palabras
  (`product_words` × `vocabulary_terms`, todo `materialized`). Antes de
  desplegar una búsqueda, medir su cuerpo con `explain analyze` contra los
  datos reales.

**Una medida decide y una pieza es esa pieza** (2026-10-25,
`20261025010000`, en producción `[Prod 2026-10-25]`). El dueño, con «cassette
7v» en la caja: «dude, the search engine it's still garbage». Salían cassettes
de 8 y 9 y espaciadores. Una batería de 45 búsquedas del taller mostró que no
era un caso: «cassette 11v» traía 8 y 9, «camara 20» cámaras de 26 y un kit de
parches, «manubrio 31.8» tees, «rayos 26» llantas, «pastillas shimano» manillas
de cambio, «cadena 12v» el cortacadena y un cambio, y «desviador shimano 8v»
ponía primero un Sensah. Las causas y lo que quedó:

- **La medida decide** ([contrato de identidad](../../../architecture/product-identity-matching-contract.md),
  «Medida excluyente»): velocidades, aro (como asiento ISO), hoyos de maza,
  abrazadera y disco se leen de la ficha (`sprocket_count`,
  `drivetrain_speeds`, `chain_speeds`, `bead_seat_diameter_mm`,
  `spoke_hole_count`, `rotor_diameter_mm_value`, las de abrazadera) y del
  nombre («7/8/9 velocidades», «3x7», «aro 26», «29 x 2.25», «36 rayos»). Lo
  que dice otro valor sale; lo que no dice la medida no se juzga por ella.
  Una velocidad nunca sale de texto libre de la ficha o la descripción.
  Si la búsqueda pide aro, lo que no es la pieza pedida tiene que confirmarlo.
  El ancho de neumático junto al aro («27.5 2.1») ordena, no excluye.
- **Los decimales son una palabra** (`catalog_search_text_v2`,
  `catalog_search_query_v2`): «1.50-2.20» ya no es «1 50 2 20» (era el «20» de
  «camara 20») y «180mm» es «180 mm». `catalog_search_normalize_v1` no cambió:
  las palabras del vocabulario y la llave de las búsquedas sin resultados
  siguen igual (las palabras no aceptan punto).
- **La pieza pedida**: la primera parte que nombra la búsqueda manda. Otra
  pieza sale, salvo que pertenezca a ella (pastillas para «freno», el eslabón
  para «cadena») o sea herramienta, consumible o pieza menor *para* ella
  («Llave para motor», «Espaciador de cassette»). Una maza «para piñón» o una
  horquilla «para disco» siguen siendo maza y horquilla.
- **Una maza dice qué recibe** (`hub_drive_receiver_kind`): «maza cassette» no
  lista las de piñón con rosca, y «maza rosca» al revés.
- **La marca escrita va primero**; un mando o cambio delantero va después de
  los traseros si no se pide «delantero».
- Vocabulario: «disco» nombra el rotor; «cortacadena» y «extractor» son
  grupos propios con «herramienta» de palabra amplia.
- Medido en todo el catálogo (con y sin stock): «cassette 7v» 16 productos,
  todos de 7; «camara 20» 11 cámaras aro 20; «manubrio 31.8» 5 manubrios.
  0,57 s contra 0,50 s antes.
- **Trampa de datos**: la etiqueta de una opción es su identidad y puede
  traer códigos de investigación («Shimano HG spline M (… ROAD 11v y 7v sólo
  según filas C-731 …)»); lo que ve el cliente es `display_label`
  (`20261002100000`). Toda lectura pública de la ficha debe leer
  `display_label`; la búsqueda leía la etiqueta y por eso un cassette de 8
  «decía» 7v.
- **Cómo se probó sin escribir en producción**: una lectura de producción es
  `BEGIN READ ONLY` y no deja crear funciones. Se tomó el cuerpo de la función
  de la migración, se reemplazaron sus ayudantes por su expresión y sus
  parámetros por valores, y se corrió como `select` por cada búsqueda
  (`explain analyze` igual). Así se midieron 54 búsquedas reales antes de
  desplegar.

**«Incluir agotados»** (2026-10-24, `20261024050000` y `060000` en
producción `[Prod 2026-10-24]`). El dueño, al ver que «camara fv» daba 3 de las
41 cámaras francesas publicadas (38 en cero): «put an option on the search to
show the agotados as well». La regla de stock (`available_only`) saca lo agotado
de todo listado y un visitante sólo podía angostarla. Ahora una búsqueda la
puede ampliar si la tienda lo ofrece: «Reglas de la tienda» del ERP dice «En el
buscador, los agotados aparecen si el cliente marca «Incluir agotados»» (o «no
aparecen»), clave `product_visibility_search_out_of_stock`; sin fila vale
`offer`. `get_public_products` deja pasar lo agotado sólo con término de
búsqueda, `p_only_in_stock = false` y la tienda ofreciéndolo; las lecturas
`get_public_products_faceted_v2` y `get_public_product_facets_v2` llevan
`p_include_out_of_stock` (último, `false` por omisión: Flutter y quien no lo
mande leen igual). Con la opción, lo que se puede comprar va primero y lo
agotado después, cada uno por relevancia. La URL es `stock=all` con `q`: la caja
la manda al marcar el interruptor (este navegador lo recuerda) y «Ver los N
productos» la conserva; el catálogo muestra la casilla «Incluir agotados» arriba
de los filtros mientras haya búsqueda. Medido: «camara fv» 3 → 40.

El buscador del encabezado (2026-10-24, sin publicar en el servidor HTML aún)
lee `/buscar?q=` (`search_suggestions.dart`): seis productos y tres servicios
de esa misma búsqueda, las categorías donde están (la que su nombre dice
primero) y el total para «Ver los N productos». La caja es
`search_overlay_view.dart`: se abre con la lupa, «/» o Ctrl/⌘ K, desenfoca la
página, sugiere mientras se escribe, muestra las búsquedas recientes de ese
navegador y las categorías del menú, y sin resultados ofrece preguntar por
WhatsApp con la búsqueda escrita en el mensaje. Sin JavaScript la lupa sigue
siendo el enlace a `/productos#buscar`.

**Rápido mientras se escribe** (2026-10-25). Dueño: «it's really slow man,
that's really important to capture a client, it has to be fast». Cada
sugerencia tardaba 1,3–2,0 s `[Prod 2026-10-25]`. Tres arreglos:

- **Documentos de búsqueda** (`20261025040000` y `050000`, en producción):
  `catalog_search_documents` guarda por producto lo que la búsqueda compara
  (textos normalizados, la ficha como texto, lo que es según el vocabulario y
  sus medidas), armado por `catalog_search_documents_compute_internal_v1`
  con las mismas CTE que la búsqueda corría en línea. La búsqueda usa el
  documento sólo si su huella (`catalog_search_source_md5_v1`, los campos del
  producto que lee) y su versión coinciden; si no, lo calcula ahí, como antes:
  un documento viejo es más lento, nunca distinto. Un cambio en la ficha de un
  producto borra su documento; uno en lo que todos leen (definiciones,
  opciones, plantillas, `category_tech_mappings`, el vocabulario) los borra
  todos. `catalog_search_documents_refresh_v1` los rearma cada minuto
  (pg_cron) y rehace los de más de un día. Un cambio en cómo se arma un
  documento sube la versión en las dos funciones. «cadena» en la base: 585 →
  ~130 ms; 1.469 documentos.
- **La caja le pregunta directo a Cloud Run** (`data-api`, de
  `STOREFRONT_SEARCH_ORIGIN`, que `deploy_cloud_run.sh` lee del servicio):
  se salta el relevo de Hosting (~200 ms). `/buscar` responde
  `access-control-allow-origin` sólo a la tienda y a su `www`
  (`StorefrontConfig.allowsSearchFrom`). Al abrir la caja (o al pasar sobre la
  lupa) abre la conexión (`preconnect`). Sin el relevo tampoco hay caché
  compartida. Desde el 2026-10-29 el servidor guarda cada respuesta 5 min
  (`_keptSearchAnswer`), salvo las incompletas o fallidas.
- **La caja no espera** (`search_overlay_view.dart`): 90 ms tras la última
  tecla; mientras llega la respuesta muestra la del prefijo más largo ya
  respondido, sin la animación de entrada (`.srch.calm`); una pregunta a la
  vez y siempre por lo que está escrito ahora. El servidor reusa el «shell»
  de las sugerencias 30 s (`_searchShell`).
- **La caja avisa** (2026-10-29). Sin nada que mostrar, dice «Buscando «…»».
  Una respuesta fallida, como un 503 con la base ocupada, se pide otra vez a
  los 0,7 s. Si vuelve a fallar, la caja muestra «No pudimos buscar» con
  «Reintentar». Antes quedaba «Explora la tienda» y se leía como «no hay».

Medido en vivo tras los documentos y antes de publicar lo demás: 0,67–1,0 s
por tecla. Publicado en la 1.0.41 y con la huella incrustada
(`20261025060000`): el servidor responde en 140–240 ms y, desde el Mac del
dueño en Seattle, 0,35–0,49 s por tecla `[Prod 2026-10-25]`. Lo que queda: tres
lecturas en paralelo (listado ~105 ms, filtros ~119 ms —sólo para contar
categorías—, servicios ~26 ms) y después los completados (nombres, marcas,
miniaturas) en un segundo viaje.

**Como escribe el cliente** (2026-10-28). Dueño, probando en el teléfono:
«si busco neumático 27, no me aparece nada», y después «tenéis que probarla
tú directamente… como que tú fueras un cliente». Una batería de ~220
búsquedas de cliente contra vinabike.cl (palabras de taller, tipeo, plurales,
medidas a medio escribir, marcas, servicios) encontró, y se arregló en la base
(`20261028010000`–`040000`, en producción) `[Prod 2026-10-28]`:

- **La última palabra es un comienzo** (como el `prefixLast` de los
  buscadores instantáneos): «27» encuentra 27.5, «2.2» 2.25, «11-3» 11-34;
  el borde izquierdo se mantiene («20» nunca dentro de «2.20»). «27» solo
  pide aro 584 o 630 (no se vende ningún 630) y todo 27.5 dice «27» entre sus
  nombres; un número seguido de «mm» no es aro; «27 5» es 27.5.
- **Lo mal escrito se corrige antes de buscar** contra las palabras de la
  tienda (`catalog_search_words`, rehecha con los documentos): primero lo que
  suena igual en Chile (ll/y, k/c, v/b, z/s, ce/ci, h muda, n/m ante b o p,
  letras dobles: `catalog_search_phonetic_v1`), si no a una letra (dos desde
  ocho), la más listada; sólo hacia palabras de cuatro letras o más (`cono`
  se volvía `con`). Nunca un número ni una palabra de servicio.
  `get_public_search_correction_v1` le dice a la tienda qué buscó. Se quitó
  el respaldo por trigramas, que traía roldanas para «lentes».
- **Un plural encuentra su singular y un adjetivo su otro género**
  (`catalog_search_alt_v1`: «guantes largos» → «Guante … Largo», «eje
  cuadrado» → «punta cuadrada», «pedales» → «Pedal»).
- **El lado es del producto, no del grupo**: todo cambio decía «delantero»
  por las frases de su grupo y «cambio delantero» listaba traseros.
- **Una búsqueda de servicio** no lista productos que sólo la nombran en la
  descripción, todo servicio dice «taller», «servicio», «arreglo» y
  «reparacion», y «sangrado» es «purgado».
- Vocabulario nuevo con evidencia chilena: «porta celular», «dedo largo» /
  «dedo completo» / «medio dedo», «valvula fina» (frase de presta).
- La regla de velocidades no convierte un modelo («B01S») en «b01v».

En la caja (`search_overlay_view.dart`, sin publicar al 2026-10-28): «Resultados
para «casco»» cuando corrigió; con «Incluir agotados» apagado y menos de seis
con stock, el servidor cuenta los agotados (`agotados` en `/buscar`; sólo el
total: hasta el 2026-10-29 también pedía los filtros de categoría) y la caja
ofrece «Ver también N agotados» o, si no hay nada con stock, «No hay «casco» con
stock hoy · Ver los 11 agotados» en vez de «No encontramos»; una respuesta sólo
de servicios lleva a `/servicios`; un decimal se marca entero y la coma es su
punto. Antes y después de tocar la búsqueda se corre
`services/storefront_html/tool/customer_search_battery.py --compare` y se lee
cada diferencia: más resultados no es mejor si son ruido.

**Lo que se busca y no se encuentra** (2026-10-24, `20261024070000` y
`080000` en producción `[Prod 2026-10-24]`; el envío desde la tienda, sin
publicar). Dueño: «has la 2 nomás». Una búsqueda que no muestra nada (la caja
del encabezado tras 1,5 s sin escribir, al cerrarla o al preguntar por
WhatsApp; `/productos?q=` vacío sin filtros) manda `POST /buscar/sin-resultados`
una vez por visita (`sessionStorage` `vb-search-misses`); el servidor la pasa a
`catalog_search_miss_record_v1`, que **busca de nuevo** y la guarda sólo si la
tienda entera no lista nada: una por forma de decirla
(`catalog_search_normalize_v1`), con las veces, cuándo y cuántos agotados
encuentra (0: no la entiende o no se vende; más: lo que falta es stock). No
guarda nada que parezca dato de alguien (correo, enlace, siete dígitos o más,
más de ocho palabras), ni más de 300 nuevas al día por tienda, ni más de 180
días. No es medición: no espera el consentimiento porque no lleva identidad.
En el ERP, **«Búsquedas»** del catálogo de la tienda (`?tab=searches`):
«Sin resultados» (Por revisar / Resueltas / Ignoradas) con «Es una palabra
de…» (elige el grupo, o uno nuevo, y dice cuántos productos encuentra ahora) e
«Ignorar» con deshacer; «Palabras del buscador» muestra los 94 grupos con su
nombre con tildes (`label`, `080000`), sus palabras compartidas y las propias
de la tienda, que son las únicas que se quitan. Funciones:
`catalog_search_misses_v1`, `catalog_search_vocabulary_v1`,
`catalog_search_add_words_v1` (un grupo se encuentra por su clave exacta,
`cinta_llanta`, antes de leer el texto como un grupo nuevo),
`catalog_search_remove_word_v1`, `catalog_search_miss_close_v1`, con las
guardias del catálogo. El vocabulario ya no se edita sólo con migraciones. Al
abrirlo el 2026-10-24 la lista estaba vacía: se llena cuando se publique el
servidor HTML. Una búsqueda vacía del catálogo ahora dice «No encontramos
«…»», ofrece «Buscar en los agotados» si la tienda lo permite y «Preguntar por
WhatsApp» con «Hola, busqué «…» en la tienda y no lo encontré. ¿Lo tienen?».

## Trampas

- **Una categoría con el nombre de otra no publicada no se podía guardar en el
  editor** (hasta el 2026-10-29, en el código; sale con la próxima
  publicación). Al guardar, el editor agregaba a la validación la dirección
  por defecto de *todas* las categorías activas, y «Frenos», «Ruedas»,
  «Dirección», «Transmisión» y «Cambios» existen también dentro de «Servicio»
  sin publicar. Las de Componentes, publicadas, chocaban con esas: «La ruta
  “frenos” ya pertenece a otra categoría». Una categoría sin publicar no abre
  ninguna dirección, así que ahora sólo cuentan las publicadas
  (`withPublishedFallbacks`) `[Repo 2026-10-29]`.
- Preguntar «¿qué lista la tienda para esta búsqueda?» con
  `get_public_products(p_only_in_stock := false)`. Desde `20261024050000` ese
  `false` con un término de búsqueda **amplía** a lo agotado cuando la tienda
  ofrece «Incluir agotados»; lo que el visitante ve por omisión es
  `p_only_in_stock := true` (lee la regla de stock de la tienda). Así se
  escribió primero `catalog_search_miss_record_v1` y el pgTAP lo pilló: una
  búsqueda que sólo encontraba agotados no quedaba (2026-10-24).
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
- El distribuidor como marca: 41 productos tenían «Andes Industrial» de marca
  (y 32 «Taiwan», 43 «Aliexpress»), cargados a mano entre 2022 y marzo de
  2026; ningún camino actual copia el proveedor a la marca `[Prod 2026-10-11]`.
  La tienda no los publica como marca (`isPublicProductBrand`); la base usa la
  misma lista (`catalog_is_public_brand_v1`, comparada por
  `catalog_brand_in_name_contract_test.dart`).
- Una regla que arma una expresión regular por marca y por producto es lenta:
  con 186 marcas y ~230 candidatos sumó 1,6 s a `catalog_web_items_v1`, porque
  Postgres guarda pocas expresiones compiladas y recompilaba todas. Buscar la
  marca como palabra con `position` en el texto normalizado, normalizando las
  marcas una vez por lista, dejó la lista en ~2 s (`20261011020000`).

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
- Guía, páginas por medida y textos de Google de cada categoría: el registro
  `catalog_category_presentations_v1` de `website_settings`
  (`website_catalog_presentation.dart` y `website_catalog_guide.dart` del
  núcleo). El editor lo guarda con `saveCatalogPresentationForTenant`
  (`website_service.dart`), que valida contra
  `WebsiteCatalogPresentationRegistry.withPublishedFallbacks` y deja la
  versión con `record_website_version`.
- Catálogo del ERP (editor «Catálogo» y ruta `/website/product-visibility?tab=`,
  2026-10-10): `lib/modules/website/catalog/` — `website_catalog_workspace.dart`
  (pestañas Productos, Por resolver, Servicios, Categorías, Destacados,
  Búsquedas —`catalog_search_view.dart`, `catalog_search_controller.dart`,
  2026-10-24— y Reglas), `catalog_web_controller.dart` (una proyección para todas las
  pestañas), `catalog_web_service.dart` (sólo comandos `catalog_*`) y cada
  vista con su vista previa de la página real. Base: `catalog_web_items_v1`,
  `catalog_set_web_sale_v1`, `catalog_copy_sku_to_gtin_v1` (y deshacer),
  `catalog_set_clearance_v1`, `catalog_set_price_mode_v1`,
  `catalog_classify_tax_v1`, `catalog_convert_item_v1`,
  `catalog_dismiss_issue_v1` (tabla `catalog_issue_dismissals`),
  `catalog_archive_empty_records_v1`, `catalog_category_counts_v1`,
  `catalog_featured_suggestions_v1`, `catalog_replace_featured_v1`,
  `catalog_apply_brand_from_name_v1` y `catalog_restore_brands_v1` (con
  `catalog_brand_words_v1`, `catalog_brand_from_words_v1`,
  `catalog_brand_from_name_v1`, `catalog_brand_agrees_v1` y
  `catalog_is_public_brand_v1`). Las páginas
  viejas (`product_website_visibility_page.dart`, `featured_products_page.dart`)
  se retiraron; `/website/featured` redirige a la pestaña Destacados.
- Lista de precios: reglas en el núcleo (`website_catalog_price_list.dart`:
  grupos, planes, «qué incluye», el plan marcado, la calificación); la dibujan
  `catalog_price_list_view.dart` del servidor HTML y el widget Flutter
  `CatalogPriceListView` (tienda del ERP, Editar/Vista previa y la vista previa
  del espacio «Catálogo web»).
- Tienda HTML (fase 1, ruta oculta): `services/storefront_html/lib/src/`
  `catalog_page_model.dart` y `catalog_page_view.dart` (catálogo, categoría,
  búsqueda), `product_page_model.dart` y `product_page_view.dart` (ficha),
  `product_question_view.dart` («Pregunta por este producto»; sus palabras y
  el mensaje en `public_product_question.dart` del núcleo). Los
  filtros son formularios GET: el servidor junta los valores repetidos de una
  casilla (`brand=a&brand=b`) y descarta los campos vacíos antes de
  `WebsiteCatalogQuery.tryParse`.
- Guía y páginas por medida o marca (2026-10-23): el modelo es
  `website_catalog_guide.dart` del núcleo (`WebsiteCatalogGuide`,
  `WebsiteCatalogLanding`, `websiteCatalogLandingMinimumItems`), guardado en
  `guide` y `landings` de la presentación de la categoría
  (`catalog_category_presentations_v1`); la ruta es
  `['productos', 'categoria', slug, landing]` de `storefront_handler.dart`
  (301 desde la categoría filtrada y desde una página que ya no existe); el
  pedido de la lista suma el filtro fijo en `catalogRequestFor(landing:)`; la
  vista dibuja `_LandingLinks` y `_Guide` (`catalog_page_view.dart`) y Flutter
  `CatalogLandingLinks` y `CatalogCollectionGuideView`
  (`lib/public_store/widgets/catalog_collection_guide.dart`). En el editor,
  `_guide` y `_landings` de `editor_panel/catalog_section_controls.dart`, con
  los valores que publica la página en `WebsiteCatalogCanvasContext.filters`.
  El sitemap suma las páginas con al menos 3 productos
  (`_fetchListedCategoryLandings` de `scripts/generate_product_seo_snapshots.dart`,
  con la misma lectura que la tienda **y su misma llave pública**:
  `get_public_products_faceted_v2` no se le concede a `service_role`, y con
  esa llave la primera compilación con páginas escritas murió en 403 el
  2026-10-23; el camino no había corrido porque el registro aún no tenía
  páginas). Las cifras al día son
  `resolvePublicCatalogText` / `publicCatalogEditorText` de
  `public_catalog_seo.dart`; la paginación, `storefrontCatalogListedPage` de
  `storefront_seo_route.dart`.
- Plantillas: la de categorías es el dueño `@catalog/categories` de
  `website_catalog_presentation.dart` (`withCategoryTemplate`,
  `drawnCategory`); la de fichas, `website_product_page_template.dart`
  (ajuste `product_page_template_v1`), ambas en el núcleo. En el editor:
  `editor_panel/catalog_section_controls.dart` (`_CategoryLookScope`) y
  `editor_panel/product_page_controls.dart`, con las secciones de la ficha en
  `website_product_canvas.dart`.
