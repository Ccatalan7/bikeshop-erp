# Migración del sitio y su editor a HTML

**Estado:** aprobado por el dueño el 2026-10-04 («ok, aprobado, arranca con la
fase 0»); reemplaza su decisión del 2026-09-24 («no rehacer las páginas
públicas como HTML todavía»). Fase 0 en curso: hecha en local y en la base,
falta Cloud Run (ver «Fase 0: estado»). Cumple el contrato «HTML-first
storefront evolution is allowed» de `.github/copilot-instructions.md`: dueño →
control → operación → consumidores, rutas que siguen en Flutter, traspaso,
frescura, reversión y verificación.

## Por qué

La tienda es una app Flutter web: dibuja en un lienzo con JavaScript. Flutter
mismo dice que no sirve para contenido que necesita SEO
(`docs/wiki/sitio-web/fuentes/flutter-web.md`). Medido el 2026-10-04 en la ficha
de la horquilla Suntour Auron 35 (`H911`), en un celular lento (1,6 Mbps,
150 ms, CPU ×4, mediana de 3 cargas, método de
`docs/architecture/storefront-instant-page.md`):

| | Tienda actual | Ficha HTML de prueba |
|---|---|---|
| Página completa y usable | 23,9 s | **2,6 s** |
| Bytes transferidos | 4.384 KB | **342 KB** |
| Primer contenido | 0,37 s | 0,93 s |
| Foto principal (LCP) | 1,57 s | 2,56 s |
| Primer byte | 0,12 s (CDN) | 0,78 s (servidor en un Mac en Chile, sin CDN) |
| Palabras sin JavaScript | 16 visibles + 65 en `<noscript>` | **389** |
| Enlaces sin JavaScript | 3 + 2 en `<noscript>` | **67** |

La tienda actual llega antes al primer contenido porque la página instantánea
es un archivo estático en el CDN; la prueba lee la base en cada visita desde
Chile. En producción el servidor corre junto a la base (São Paulo, la región de
Supabase) y el primer byte baja a decenas de milisegundos; ver «Lo que la
prueba no resuelve todavía».

Los referentes chilenos sirven 700–2.500 palabras en el HTML
(`docs/wiki/sitio-web/paginas/seo-de-referentes.md`). Mantener la página
instantánea completa además de Flutter duplica cada página; migrar la elimina.

## Requisitos del dueño (2026-10-04)

1. **El editor sigue dentro del ERP**, desde el mismo menú y con la misma
   sesión: nada de una URL aparte. El lienzo pasa a ser el sitio HTML real en
   un visor web integrado; el ERP ya integra visores web (WhatsApp Web y
   portales de proveedores, `lib/shared/widgets/webview_module_page.dart`).
2. **Lo que se configura en el ERP se ve en segundos en la página.** No hay
   sincronización: el ERP y el sitio leen y escriben las mismas tablas. El
   precio y el stock nunca salen de una caché vieja. Frescura igual o mejor que
   hoy (hoy: la ficha abierta se relee cada ~30 s; portada y ajustes, hasta
   5 min por el Worker; lo que lee Google, hasta el próximo despliegue).
3. **Regla 1 del wiki:** todo lo que muestra el sitio se crea y se corrige en el
   editor o en el ERP; el HTML es consumidor, nunca un segundo dueño.

## Arquitectura

### Un núcleo Dart, dos consumidores

Lo que decide cómo se ve un producto ya es Dart puro y ya corre fuera de
Flutter (el generador de snapshots lo usa con `dart run`): la proyección
comercial (`PublicCommerceProductProjection`), la ficha técnica
(`PublicProductSpecSheet`, `public_spec_display.dart`: rodados, anchos,
unidades, números a la chilena), el texto SEO (`public_product_seo_copy.dart`),
los datos para Google (`lib/public_store/seo/`), las rutas de categoría
(`website_catalog_presentation.dart`), el tema (`website_theme_color_value.dart`),
el horario (`public_business_hours.dart`) y los modelos de los 24 bloques del
editor (`lib/modules/website/models/`). **La prueba los importa tal cual**: no
se copió ni una regla a otro lenguaje.

Por eso la recomendación es **renderizar en Dart en el servidor**:

- **Fase 0 extrae ese núcleo a un paquete Dart puro**
  (`packages/vinabike_public_core`), que importan el ERP y el sitio.
- **Componentes con Jaspr** (SSR en Dart; con él están hechos dart.dev y
  docs.flutter.dev), validado en la fase 0 portando la ficha de prueba. Plan B
  si Jaspr no rinde: el mismo servidor Dart de la prueba con plantillas propias.
- Alternativa descartada por ahora: Astro/Next.js en TypeScript. Tiene más
  ecosistema, pero obliga a reescribir el núcleo en TypeScript o a mover cada
  regla de presentación a SQL, y deja dos implementaciones que divergen.

### Datos y frescura

- **Un viaje por página.** Hoy la ficha Flutter hace 6+ llamadas
  (`get_public_products`, tres enriquecimientos, ficha técnica, recorrido,
  datos de la tienda). Desde el 2026-10-04 existen dos lecturas que el
  servidor hace al mismo tiempo: `get_public_product_page_v1(tenant, sku)`
  (producto con sus campos del sitio, filas de marca, ficha técnica y
  relacionados) y `get_public_storefront_shell_v1(tenant)` (ajustes públicos,
  menús, páginas, categorías, tramos de envío). Son `SECURITY INVOKER` y sólo
  componen las lecturas públicas que ya existen, así que no pueden devolver
  nada que la llave pública no lea hoy
  (`20261004180000_public_storefront_page_reads.sql`).
- **Servidor junto a la base:** Cloud Run en `southamerica-east1`, la misma
  región que Supabase (`sa-east-1`). Firebase Hosting le reenvía sólo las rutas
  migradas; el resto sigue en Flutter.
- **Sin caché vieja:** el HTML se arma en cada visita (`Cache-Control:
  private, no-cache` desde el 2026-10-05: el borde no la guarda y el navegador
  pregunta cada vez, pero el botón «atrás» puede usar su copia; con `no-store`
  no podía), y en la fase 0 también lo compartido: leerlo cuesta
  5 ms en la base, así que menús, tema y categorías están frescos en cada
  visita sin invalidar nada. Una caché en memoria invalidada por Supabase
  Realtime queda para cuando el tráfico lo pida. Precio y stock se leen en cada
  visita.
- **Prueba obligatoria por fase:** cambiar un dato en el ERP y ver el HTML
  público actualizado en ≤5 s (con un producto de prueba no publicado, nunca
  con uno real).

### El editor

- **El panel lateral se queda en Flutter, en el ERP**: pestañas, campos de cada
  bloque, guardado (`WebsiteSaveCoordinator`, `replace_page_blocks`). Es la
  mayor parte del editor y no se reescribe.
- **El lienzo pasa a ser el sitio HTML real** en un visor web del ERP
  (WKWebView en macOS, WebView en Android, WebView2 en Windows, iframe en el ERP
  web). En modo edición, sólo para personal autenticado, el sitio marca cada
  bloque y avisa al panel cuál se tocó; el panel guarda y el lienzo vuelve a
  dibujar ese bloque. Se gana fidelidad: lo que se ve al editar es literalmente
  la página pública.
- Se reescriben los renderizadores de los 24 bloques (hoy widgets Flutter en
  `lib/modules/website/widgets/`) como componentes HTML.
- La sesión pasa del ERP al visor sin volver a entrar.

### Lo que Google y los demás reciben

Todo en HTML visible: título, precio, disponibilidad, ficha técnica, descripción,
migas y relacionados como enlaces; JSON-LD del mismo armado compartido
(`buildPublicProductStructuredData`, `completePublicBusinessStructuredData`);
`sitemap.xml` y redirecciones siguen saliendo del build mientras convivan las
dos tiendas.

## Fases (cada una se revierte quitando sus reescrituras de Firebase)

| Fase | Qué | Rutas | Sigue en Flutter |
|---|---|---|---|
| 0 | Núcleo Dart en paquete; Jaspr validado con esta ficha; `get_public_product_page_v1`; servicio en Cloud Run detrás de una ruta oculta; medición | ninguna pública | todo |
| 1 | **Fichas y categorías** (casi todo el valor SEO; su contenido viene de la ficha del producto y de «Catálogo web», no de bloques) | `/productos/<slug>/<sku>`, `/productos/categoria/<slug>`, `/productos` | portada, páginas del editor, carrito, checkout, portal |
| 2 | **Editor con lienzo HTML** + portada, páginas del editor, `/servicios`, `/contacto`, páginas legales | todas las de contenido | carrito, checkout, portal |
| 3 | **Carrito, checkout, pedido y portal** en HTML con islas interactivas; pagos con los mismos RPC y Edge Functions; pagos de prueba antes de abrir | todas | nada: se retira `lib/main_store.dart` |

Costuras que la fase 1 tiene que cumplir:

- **Carrito:** «Agregar» en la ficha HTML escribe el mismo sobre versionado que
  lee el carrito Flutter (`lib/public_store/services/cart_store.dart`:
  `public_store_cart_v2.<tenant>`, `schemaVersion` 1, vigencia 7 días, candado de
  almacenamiento). Un test de contrato compara los dos formatos.
- **Tema, encabezado y pie** se dibujan en dos renderizadores hasta la fase 2:
  el único período con doble dibujo. Por eso la fase 2 va inmediatamente
  después.
- **GA4 y el píxel:** los mismos eventos (`view_item`, `add_to_cart`…) desde un
  script pequeño; nunca duplicados con Flutter en la misma ruta.
- **`noindex`, canonical y redirecciones** iguales a las de hoy por ruta
  (`docs/wiki/sitio-web/paginas/rutas-y-navegacion.md`).

## Verificación por fase

- Para el 100 % de las fichas publicadas, comparación automática entre la
  versión Flutter y la HTML de título, precio, disponibilidad, fotos, ficha
  técnica y migas: cero diferencias.
- Celular lento: LCP ≤ 2,5 s y página usable ≤ 3 s en ficha y categoría;
  PageSpeed móvil antes y después.
- Sin JavaScript: el texto y los enlaces de la página completa.
- Frescura ≤ 5 s (prueba de arriba) y Prueba de resultados enriquecidos sin
  errores.
- Capturas reales en teléfono y escritorio; en la fase 2, el editor dentro del
  ERP en macOS, Android y web.

## Lo que la prueba no resolvía (2026-10-04)

- **Primer byte:** 0,78 s desde un Mac en Chile hasta Supabase en São Paulo,
  sin CDN. La lectura única y el servidor en la misma región no alcanzaron
  (0,90 s medido en vinabike.cl): manda la ficha técnica, ver «Fase 0: estado».
- **Foto principal:** el JPG de 1.200 px de Supabase Storage es el mismo que usa
  la tienda actual. Falta servirla en el tamaño justo (`srcset` con
  transformación de imágenes) y subconjuntar las fuentes.
- **Menú en el teléfono:** los submenús salen desplegados; se pliegan como en
  la tienda actual.
- **Carrito:** el botón todavía no escribe el carrito (lo hace la fase 1).
- **Nodo `BikeStore`:** la prueba declara sólo la ficha y las migas.

## Riesgos y costo

- **Tamaño:** la tienda son ~65.600 líneas Dart (22 páginas, 60 rutas) y los
  renderizadores del editor ~67.000. Se reescribe la capa que dibuja; se quedan
  la base, sus reglas (pedidos, pagos, reservas, envío, correos), el modelo del
  editor, el núcleo Dart, el feed de Merchant y el panel del editor.
- **Pagos:** el checkout se rehace al final, con pagos de prueba.
- **Dos tiendas por ruta durante la migración:** sólo encabezado, pie y tema se
  dibujan dos veces, y sólo entre la fase 1 y la 2.
- **Infraestructura nueva:** un servicio en Cloud Run. **El sitio tiene que
  ser gratis** (dueño, 2026-10-04): corre con `min-instances 0`, que cobra sólo
  mientras responde y cabe en la cuota gratis mensual de Cloud Run al tráfico
  de Viñabike. Una instancia siempre despierta (~US$10–15 al mes) estuvo
  encendida unas horas el 2026-10-04 y se apagó al saberse el requisito. El
  costo de esa decisión es un arranque en frío para la primera visita después
  de un rato sin tráfico; se mide antes de abrir rutas en la fase 1.
- **Jaspr** es más chico que el ecosistema de TypeScript: se valida en la fase 0
  antes de comprometer el resto.

## Fase 0: estado (2026-10-04)

Hecho y verificado:

- **Núcleo Dart** en `packages/vinabike_public_core`, Dart sin Flutter: 18
  archivos movidos con `git mv` (proyección comercial, ficha técnica, texto
  SEO, datos estructurados, URL de producto, presentación de categorías,
  menús y destinos, origen canónico (`store_url`), tema, horario, `Product`, utilidades chilenas) y la regla
  de marca de la tienda (`canonicalPublicProductBrandNames`). En cada ruta
  vieja de `lib/` queda una línea que lo reexporta, para no tocar los 162
  archivos que lo importan mientras otro agente puede estar editándolos; el
  código nuevo importa el paquete. CI lo analiza y prueba con Dart puro.
- **Lecturas de la página** desplegadas y verificadas en producción
  (`20261004180000`), con pgTAP (`public_storefront_page_reads.sql`: borrador,
  SKU desconocido, otra empresa, costo ausente, menús y páginas ocultos). La
  revisión de Codex encontró que las marcas no se filtraban por empresa y que
  los relacionados llegaban sin los campos del sitio que Flutter agrega a
  cada tarjeta; `20261004190000` corrige las dos cosas, con pruebas que
  fallaban antes.
- **Revisión cruzada** (Codex, 2026-10-04): sin P0 ni P1; cinco P2 y tres P3,
  corregidos. Además de lo anterior: menús con su visibilidad de teléfono y
  escritorio, pie con la regla de Flutter (grupos con enlaces o una lista
  «Enlaces»), canónica desde `store_url`, logo de la empresa que se pide (o su
  nombre), el paso de CI se dispara también con cambios del servidor, y la
  cobertura de los registros de versión incluye el núcleo y el servidor
  (`requiresReviewedChange`): un cambio en el núcleo no tocaba el hash de su
  reexportación.
- **Servidor** `services/storefront_html/`: Jaspr 0.23.5 renderizando en el
  servidor con `renderComponent` sobre `shelf`, sin componentes cliente. Los
  menús se resuelven con los modelos de la tienda (`WebsiteNavigation.href`,
  `WebsitePage.fullPath`, `WebsiteDestination.parse`); el texto SEO con
  `PublicProductSeoCopyInput.fromSettings`, nuevo en el núcleo. Pruebas del
  manejador (página completa, escape, 404, 502, 405, menús). La prueba de
  `tool/` se retiró.
- **Medido** (en local, celular lento): usable a los 2,6 s, 362 KB, igual que
  la prueba. Armar la página compilada (AOT) tarda 5–7 ms. En la base:
  `get_public_product_page_v1` 281 ms, `get_public_storefront_shell_v1` 5 ms.

Cloud Run (2026-10-04): el dueño instaló `gcloud`, inició sesión y dio a la
cuenta de compilación el rol `roles/run.builder`; el proyecto ya tenía
facturación. Se habilitaron Cloud Run, Cloud Build y Artifact Registry y el
servicio `storefront-html` corre en `southamerica-east1` (512 MiB; primero con
`min-instances 1`, en 0 desde que el dueño recordó que el sitio debe ser gratis). Medido directo contra Cloud Run desde Chile: primer byte ~0,7 s, de
eso 310–460 ms de lectura en São Paulo (la ficha técnica) y 6–16 ms de armado.
La reescritura `/_html/**` → `storefront-html` del target `store` va en el
mismo commit que este texto.

Medido a través de `vinabike.cl/_html/...` (2026-10-04, celular lento, mediana
de 3): usable a los **2,6 s** contra 24,1 s de la ficha Flutter, **338 KB**
contra 4.384 KB; foto principal 2,64 s contra 1,58 s; primer byte **0,90 s**
contra 0,14 s. El borde no guarda la página (`x-cache: MISS`, `no-store`).

**El primer byte no bajó a «decenas de milisegundos» como decía este plan.**
Poner el servidor junto a la base quitó el viaje Chile–São Paulo de las
lecturas, pero la lectura misma tarda ~300 ms, y casi todo es la ficha técnica
validándose en cada visita. Precalcularla es lo primero de la fase 1; sin eso,
el primer byte del HTML queda por sobre el de la página instantánea, aunque la
página completa llegue nueve veces antes.

Costo: el sitio tiene que ser gratis (requisito del dueño, 2026-10-04). El
servicio quedó con `min-instances 0`, la imagen guardada pesa 5,5 MB (la cuota
gratis es de 500 MB) y cada compilación tarda unos minutos dentro de la cuota
gratis de Cloud Build. Falta confirmar en la facturación, después de unos días,
que el costo es US$0.

Arranque en frío medido (2026-10-05, después de 20 minutos sin visitas; el
registro de Cloud Run confirma «Starting new instance» en cada caso): el
binario nativo sobre una imagen vacía queda listo en ~0,15 s y despertar le
suma ~0,3–0,5 s a la primera visita. Con curl, primer byte 1,16 s en frío contra
0,84–0,89 s despierto. En el celular lento, usable a los **3,0 s** en frío
contra 2,5 s despierto (primer byte 1,29 s contra 0,83 s). Incluso la peor
visita queda ocho veces por delante de los 24,1 s de la ficha Flutter: con
`min-instances 0` el sitio sigue siendo gratis sin un costo visible.

Lo que encontró la fase 0, y la fase 1 resuelve antes de abrir rutas:

- **La ficha técnica cuesta ~275 ms por lectura**:
  `get_public_product_technical_specs` valida los datos en cada visita
  (`spec_validate_draft_internal_v1`). La tienda Flutter paga lo mismo hoy, en
  una llamada aparte. Se precalcula cuando cambian los datos, en su dueño.
- La ficha Flutter y el generador pasan a `PublicProductSeoCopyInput.fromSettings`,
  para que el título y la descripción salgan de un solo lugar.
- Los enlaces de categoría de los menús usan la misma normalización que
  `normalizePublicCatalogRouteForRuntime` (hoy en código Flutter).
- La disponibilidad de los productos que son set (`preview_product_stock_impact`)
  entra a la lectura de la página.
- El nodo `BikeStore`, las fotos al tamaño justo (`srcset`) y los submenús
  plegados en el teléfono.
- `firebase.json` declara `Cache-Control: public, max-age=0, must-revalidate`
  para `/productos/**` (pensado para el `index.html` de Flutter). Cuando esas
  rutas pasen a Cloud Run, la regla se retira y manda la del servidor
  (`private, no-cache`), para que el borde nunca guarde una ficha. `/_html/**` no coincide
  con ninguna regla.
- La medición sigue las dos reglas de `scripts/sync_seo_index.sh`: GA4 y el
  píxel sólo en el dominio de la tienda y nunca en un navegador con la marca
  `vb_sin_medir` (cookie del dominio, puesta con `?sin_medir`). **Corrección
  2026-10-05:** el servidor no puede leerla: Firebase Hosting borra toda cookie
  salvo `__session` antes de reenviar a Cloud Run. La revisa el script de la
  página antes de cargar nada, como en `index.html`.
- `products.sku` es único en toda la base, no por empresa
  (`products_sku_key`): dos tiendas no pueden repetir un SKU. No afecta a
  Viñabike hoy; se anota para el día que haya otra.

Cómo correrlo, medirlo y desplegarlo: `services/storefront_html/README.md`.

## Fase 1: estado (2026-10-05)

Hecho y verificado, todavía en la ruta oculta (`vinabike.cl/_html/...`); las rutas públicas siguen en Flutter hasta que el
dueño apruebe el cambio de `firebase.json` (ver «Costo de abrir las rutas»):

- **Páginas:** `/productos` (con búsqueda), `/productos/categoria/<slug>` y la
  ficha, con encabezado, pie, menús y tema de la tienda. Rutas, 301 y 404 en
  `services/storefront_html/README.md` y en el wiki
  (`docs/wiki/sitio-web/paginas/rutas-y-navegacion.md`).
- **Una regla, un dueño:** se movieron al núcleo la lectura de facetas
  (`public_catalog_facets.dart`), qué filtros técnicos se ofrecen, qué
  categoría abre una URL (`public_category_route.dart`; Flutter delega en ella),
  títulos y descripciones de colección (`public_catalog_seo.dart`, también los
  usa el generador), `noindex`/canónica (`storefront_seo_route.dart`), el nodo
  `BikeStore` (`public_business_identity.dart`, el mismo armado que
  `sync_seo_index.sh`), los medios de pago del pie y la publicación de
  categorías y páginas. El servidor no tiene reglas propias.
- **Dos defectos de Flutter que aparecieron al compartir las reglas**, ya
  corregidos en el núcleo: un filtro técnico en la URL (`spec.<clave>`) no
  contaba como estado del visitante y la categoría filtrada decía
  `index,follow`; y el servidor resolvía las categorías con el resolvedor de
  menús, que mira también las no publicadas, así que «Cambios» y «Frenos»
  (nombres repetidos) daban 404 en HTML mientras Flutter las abría.
- **Carrito:** «Agregar» escribe el documento que lee Flutter, bajo el mismo
  candado; `test/unit/storefront_html_cart_contract_test.dart` corre el script
  de la página en Node y lo decodifica con `PersistedCart` en los dos
  sentidos (carrito nuevo, carrito Flutter existente con su límite de stock,
  carrito vencido).
- **Paridad automática** (`tool/parity.py`, 2026-10-05, después de la
  revisión de Codex): de las 1.307 páginas del sitemap, las **1.290 fichas
  comparables son idénticas** a la instantánea Flutter en título, descripción,
  robots, canónica, h1, `Product` (nombre, SKU, fotos, marca, categoría,
  precio, disponibilidad, ficha técnica, GTIN, modelo), migas y `BikeStore`.
  Las otras 5 fichas tienen un espacio en el SKU y su instantánea Flutter sirve
  la portada (defecto de la instantánea; el HTML sirve la ficha). Las 12
  colecciones coinciden en todo salvo el orden de su `ItemList`: la
  instantánea toma los primeros productos de su propia consulta y el HTML los
  que el visitante ve en esa página (orden por nombre), con el mismo nombre
  comercial; y el h1 de `/productos` («PRODUCTOS», como lo dibuja Flutter,
  contra el título SEO de la instantánea). Con `--skus`, los 1.541 SKU
  publicados: las 1.295 fichas con foto abren en su ruta canónica; las 246 sin
  foto dan 404 en las dos tiendas (la regla del sitio exige foto).
- **Revisión cruzada de Codex** (2026-10-05, sólo lectura): sin P0; 1 P1, 4 P2
  y 1 P3, todos corregidos con prueba. P1: un carrito que todavía estaba en la
  clave vieja compartida (`public_store_cart_v1`) quedaba oculto para Flutter
  tras agregar desde HTML; ahora la página lo migra como Flutter. P2: los ids de
  escrituras ya aplicadas en el primer formato de Flutter se perdían; las
  tarjetas mostraban el nombre web y no el comercial (las filas del listado se
  completan con `publicProductIdentityColumns`, la misma lista que usa Flutter);
  un `?category=` sin resolver abría todo el catálogo en vez de buscarlo, y la
  precedencia de `category`/`category_id`/`cat` no era la de Flutter; una
  página fuera de rango contaba mal. P3: gzip ignoraba `q=0`. La segunda
  pasada confirmó las seis correcciones y encontró dos P2 en ellas, también
  corregidos con prueba: si el navegador no dejaba borrar la clave vieja, el
  «Agregar» ya aplicado se informaba como fallido (y un reintento sumaba dos
  veces); y una falla al leer las marcas descartaba también los títulos
  comerciales. Ahora el retiro es de mejor esfuerzo (Flutter lee primero la
  clave de la tienda) y cada capa cae por separado, como en Flutter.
- **Sin JavaScript:** filtros y orden son formularios GET; menú y filtros del
  teléfono se abren con una casilla; «Agregar» lleva al carrito.
- **Frescura:** con la base local, el precio cambiado aparece en la ficha y en
  la categoría **0,07 s** después del commit: no hay caché entre la base y la
  página.
- **Compresión:** ni Cloud Run ni Firebase Hosting comprimían la página
  reenviada (64 KB viajaban así); el servidor la manda en gzip (15 KB).
- **Datos estructurados:** los nodos salen de los mismos armadores que la
  tienda Flutter y la comparación los dio idénticos en las 1.294 fichas con
  instantánea; la Prueba de resultados enriquecidos sobre una URL `/_html` no se
  corrió (es un formulario de Google: queda para el dueño o para cuando se
  abran las rutas).

Medido en el celular lento (`measure.mjs`, 2026-10-05, mediana de 3, Cloud
Run despierto):

| Página | Primer byte | LCP | Carga completa | Transferido |
|---|---|---|---|---|
| Ficha HTML | 0,76 s | **1,13 s** | 2,3 s | 285 KB |
| Categoría sin foto de portada pesada (`camaras`) HTML | 0,97–1,16 s | **1,64–1,88 s** | 4,8 s | 699 KB |
| `/productos` HTML | 1,0–1,1 s | **4,4–4,5 s** | 4,6 s | 694 KB |
| Categoría `componentes` HTML | 1,0 s | **4,2 s** | 4,3 s | 647 KB |
| Categoría `camaras` Flutter | 0,15 s | 0,41 s (instantánea) | 22,2 s | 4.012 KB |

**No se cumple todavía «LCP ≤ 2,5 s» en `/productos` ni en las categorías
cuyas primeras tarjetas tienen fotos pesadas.** La causa son las fotos de
tarjeta: son la versión de 1.200 px (75–120 KB cada una) que también usa
Flutter, y el teléfono baja ~16 a la vez (Chrome carga lo `lazy` hasta 2.500 px
por debajo con una conexión lenta). Ya se probó, sin efecto apreciable, quitar
la precarga de la fuente de títulos en el catálogo, cargar de inmediato sólo la
primera fila y bajar la prioridad del resto. Lo que falta es una miniatura de
~400 px; decisión del dueño (ver «Pendiente del dueño»). Las fuentes no son el
problema: Hosting ya las manda en brotli (104 → 43 KB).

Lecturas (en la base, 2026-10-05): la ficha bajó de ~300 a **108–145 ms**
(ficha técnica en una pasada, `20261005090000`). El catálogo tarda ~450–700 ms:
`get_public_product_facets_v2` ~410 ms, de eso ~270 ms en
`spec_public_facet_values_internal_v1` (valores técnicos de todo el catálogo en
cada visita) y ~190 ms en el universo de `get_public_products`. Es la misma
lectura que paga Flutter; precalcular los valores técnicos es la mejora
siguiente si el primer byte del catálogo importa.

**Al mover código al núcleo, buscar quién lee su texto** (2026-10-05, costó una
vuelta de CI con el despliegue de la tienda bloqueado). Muchos contratos del
repo leen el código fuente como texto (`File('lib/...').readAsStringSync()`) y
buscan identificadores; al mover algo al núcleo, el reexport de `lib/` compila
igual pero el texto ya no está ahí. Antes de publicar:
`grep -rl '<archivo movido o tocado>' test/` y correr esos archivos, no sólo los
del módulo. Así falló `google_merchant_identity_contract_test.dart` cuando las
columnas de las tarjetas pasaron a `public_product_identity_columns.dart`.

### Costo de abrir las rutas (2026-10-05)

Tráfico real: Search Console contó **8.090 peticiones de Googlebot en 90 días**
(43 % HTML, ~1.200 páginas al mes) y GA4 **1.185 vistas en 28 días** en todo el
sitio. Con 10.000 páginas al mes (holgado) y 100.000 (diez veces más):

- **Cloud Run:** cuota gratis mensual de 2 millones de peticiones, 180.000
  vCPU-s y 360.000 GiB-s. Una página ocupa ~0,6 s → 6.000 vCPU-s con 10.000
  páginas, 60.000 con 100.000: dentro de la cuota (US$0).
- **Salida de datos de Cloud Run:** ~15 KB por página en gzip → 0,15 GB al mes
  (1,5 GB con 100.000). La cuota gratis de 1 GiB es sólo para Norteamérica; desde
  São Paulo se cobra por GB (del orden de US$0,1–0,2), o sea **centavos al mes**.
  Es el único costo que no es claramente cero.
- **Firebase Hosting:** baja. Cada visita nueva a una página Flutter baja ~4 MB;
  la HTML ~0,3 MB. Googlebot bajó 2,4 GB en 90 días, en buena parte JavaScript
  de Flutter.
- **Compilaciones:** cada despliegue usa unos minutos de Cloud Build (cuota
  gratis) y guarda una imagen de 5,5 MB (cuota gratis de 0,5 GB en Artifact
  Registry; conviene una regla que borre las viejas).
- `min-instances 0` se mantiene: primera visita tras un rato sin tráfico,
  +0,3–0,5 s.

Para abrir las rutas faltan, en un mismo commit: reescrituras `/productos`,
`/productos/categoria/**` y `/productos/**` → `storefront-html` en
`firebase.json` (target `store`), retirar ahí la regla `Cache-Control` de
`/productos/**`, y que el generador deje de escribir instantáneas de fichas y
categorías (en Hosting un archivo estático tapa a la reescritura); el sitemap y
las redirecciones siguen saliendo del build.

### Pendiente del dueño

- Aprobar el costo de arriba (centavos al mes de salida de datos) para abrir
  las rutas.
- Miniaturas de las fotos de tarjeta, para cumplir el LCP del catálogo:
  (a) transformación de imágenes de Supabase: ~1.300 fotos de origen al mes,
  ~US$5–6 al mes sobre la cuota del plan; (b) gratis: guardar una miniatura
  de ~400 px junto a la versión de 1.200 px al subir cada foto (todas las
  rutas que suben fotos de producto) y generar una vez las ~1.300 que existen.
