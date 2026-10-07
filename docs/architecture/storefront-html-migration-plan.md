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
- **Una ráfaga no tumba la página (2026-10-07).** Con ~12 visitas a la vez
  la base cortaba las lecturas del catálogo al pasar los 3 s de `anon` y la
  página entera respondía 503. Tres arreglos, ninguno con caché, así que
  sigue valiendo «≤5 s»:
  - **Las lecturas hacen menos y devuelven lo mismo**
    (`20261007020000`): los valores técnicos se calculan sólo para las
    categorías pedidas y el listado no normaliza texto si no hay búsqueda.
    Filtros de una categoría 399 → ~65 ms, listado ~130 → ~25 ms. Un índice
    mantenido por disparadores se intentó y se descartó: traía nueve defectos
    de concurrencia (`docs/development/AGENT_DATABASE_CONTRACT.md`).
  - **El servidor deja pasar cuatro consultas a la vez** por instancia
    (`DatabaseGate`); las demás esperan su turno en el servidor, hasta 10 s,
    y comparte las lecturas idénticas que ya van en camino.
  - **Los filtros son opcionales:** si su lectura falla, la página lista sus
    productos sin conteos ni filtros y conserva los filtros activos. Un
    filtro activo que la lectura ya no trae (los otros filtros lo dejan en
    cero) se dibuja marcado, con 0, para que se vea y se pueda quitar.

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

Hecho y verificado primero en la ruta oculta (`vinabike.cl/_html/...`); las
rutas públicas se abrieron el mismo día con el sí del dueño (ver «Rutas
abiertas»):

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
~400 px; el dueño eligió la opción gratis (ver «Pendiente»). Las fuentes no son el
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

El dueño lo aprobó el 2026-10-05 («has todo lo recomendado, pero pon una
alerta de 5 usd»). La alerta es el presupuesto «Sitio vinabike.cl - alerta 5
USD» del proyecto `project-vinabike`: **CLP 4.800** (≈ US$5), avisos al 50, 90 y 100 %
del gasto y al 100 % del pronóstico. La cuenta de facturación
(`01BD16-FAC1FF-F6EA02`, compartida con otros proyectos) está en pesos
chilenos y no acepta un monto en dólares (`INVALID_ARGUMENT`); el presupuesto
anterior de CLP 2 («Viñabike Firebase») quedó como estaba.

### Rutas abiertas (2026-10-05)

- `firebase.json`, target `store`: reescrituras `/productos`, `/productos/**` y
  `/producto/**` → `storefront-html` antes de `**`; se retiraron las reglas
  `headers` de `/productos` y `/productos/**` (el servidor manda las suyas).
- **Hosting sirve un archivo estático antes que una reescritura** (sus 301
  exactos van antes que ambos). El generador lee de `firebase.json` qué rutas
  son del servidor (`SeoServerRenderedRoutes` en
  `scripts/generate_product_seo_snapshots.dart`) y no escribe nada bajo ellas;
  su validación acepta esas entradas del sitemap y esos enlaces sin
  instantánea, y falla si queda un archivo ahí. Quitar una reescritura devuelve
  las instantáneas en el build siguiente: así se revierte la fase. Corrida con
  datos reales: 0 instantáneas de fichas, 1.295 fichas, 11 categorías y
  `/productos` al servidor; las 1.296 de `/tienda/producto/<uuid>` siguen como
  página `noindex` liviana que manda a la ficha; el sitemap mantiene sus 1.307
  URL de productos y los 301 exactos siguen saliendo del build.
- **La publicación revisa el servidor.** Cloud Run se publica aparte
  (`deploy_cloud_run.sh`) y `release.json` no dice nada de él. Cada respuesta
  trae `x-storefront-source` (lo que compila la imagen, según
  `services/storefront_html/tool/source_id.sh`, que el script de despliegue
  estampa y que se niega a publicar con cambios sin commit), y el flujo de la
  tienda (`scripts/releases/check_storefront_html_routes.mjs`) pide en los dos
  orígenes `/productos`, cada categoría y una muestra de fichas del sitemap
  recién armado, dos enlaces UUID viejos y una categoría inexistente. Falla si
  una página no es 200 con su canónica e indexable, si un enlace viejo no es
  301 a la ficha, si lo desconocido no es un 404 del servidor, o si Cloud Run
  corre otra fuente que la del commit: **cambiar el núcleo compartido obliga a
  republicar el servidor**, porque si no las dos tiendas dejan de decir lo
  mismo. Su primera corrida en vivo (run 37279240730) falló en las 36 páginas
  con «canonical (ninguna)» aunque estaban bien: buscaba `rel` antes que
  `href` y Jaspr escribe `href` primero, y su prueba usaba el orden que yo
  supuse. La prueba ahora usa el HTML como lo escribe el servidor; un
  verificador se prueba contra la salida real, no contra la que uno imagina
  (costó una corrida de 23 min marcada en rojo; el sitio estaba bien).
- **Revisión de Codex de la apertura** (2026-10-05, sólo lectura): sin P0;
  tres P2. (1) Dentro de una visita que ya cargó Flutter, tocar un producto
  sigue dibujando la ficha Flutter en el navegador: se deja así hasta la fase
  2, porque forzar una carga de página en cada clic obligaría a volver a
  arrancar Flutter (~4 MB) al volver a la portada, y la portada pasa a HTML en
  la fase 2. (2) La publicación no revisaba el servidor: corregido con lo de
  arriba. (3) Un producto publicado sin SKU tiene su ficha canónica en
  `/productos/<uuid>` y el servidor no la sabe dibujar (la lectura de la ficha
  va por SKU): hoy 0 de 1.682 productos no tienen SKU y el ERP lo genera al
  crear. Corregido con `get_public_product_page_v2` (por SKU o por id); la
  prueba del servidor encontró además que `Product.fromJson` se caía con un
  SKU nulo, lo que habría tumbado también cualquier catálogo que lo listara.

### Miniaturas de tarjeta (2026-10-05)

El dueño eligió la opción gratis: una copia de 400 y otra de 800 px de cada
foto de tarjeta, en vez de la transformación de imágenes de Supabase (~US$5–6
al mes). No se hacen al subir: el ERP sube fotos de producto desde una docena
de lugares y algunas están en AliExpress, así que un solo trabajo
(`scripts/generate_public_image_thumbnails.dart`) copia la foto que muestra cada
tarjeta, venga de donde venga, y la anota en `public_image_thumbnails`
(`20261005130000`, con la firma de la foto para rehacerla si cambia en la misma
URL). Corre en el job `card_thumbnails` de cada publicación de la tienda; una
foto todavía sin copia sale grande en su tarjeta. El servidor lee las copias en
la misma vuelta que completa las filas (`get_public_image_thumbnails_v1`) y las
ofrece en `srcset`, con la precarga de la primera tarjeta con los mismos
candidatos.

- **Resultado** (`measure.mjs`, celular lento, mediana de 3, rutas públicas,
  revisión `storefront-html-00010`, 2026-10-05):

  | Página | LCP antes | LCP con copias | Transferido |
  |---|---|---|---|
  | `/productos` | 4,4 s | **2,0 s** | 694 → 409 KB |
  | categoría `componentes` | 4,2 s | **2,1 s** | 647 → 413 KB |
  | categoría `camaras` | 1,6–1,9 s | **1,6 s** | 699 → 419 KB |
  | categoría `frenos` | — | **2,0 s** | 497 KB |
  | ficha `camara-maxxis-700x23…` | — | **2,2 s** | 319 KB |

  Todas bajo la vara de 2,5 s.
- Relleno inicial: 1.294 fotos sin fallas; 984 con copias, 310 ya de 400 px o
  menos (casi todas de AliExpress, de 220 px). En 40 fotos al azar: original
  **120 KB**, copia de 400 px **19,6 KB**, de 800 px **64 KB**. Una corrida
  sin fotos nuevas tarda ~2 min (sólo pregunta la firma de cada foto).
- Trampa: un `HEAD` a Supabase Storage responde `cache-control: no-cache`; el
  `GET` trae el `max-age` guardado al subir (un año) y el CDN la sirve en `HIT`.
- Un uso nuevo de `SUPABASE_SECRET_KEY` en el flujo de la tienda sube el conteo
  revisado de `test/scripts/supabase_cli_safety_test.sh` (ocho desde hoy).

### Paridad con Flutter (2026-10-05)

El dueño vio tarjetas rotas en `/productos` (fotos desbordadas, nombre y
precio cortados) y pidió forma, tamaños, espacio y animaciones perfectos. Se
midió cada página contra la tienda Flutter en vivo a 1440, 1280, 1100, 1000,
800, 700, 650, 412 y 360 px (posición de cada texto y línea con un muestreo de
píxeles, no a ojo) y quedó a 1 px en catálogo, ficha y pie (`3f12435c`). Lo
que conviene saber antes de tocarlo:

- **La grilla de Flutter lee la ventana, no la grilla**
  (`MediaQueryLayoutBuilder` en `_buildProductGrid`): a 1000 px pone cuatro
  columnas de 146 px junto al riel. La HTML aplica las mismas columnas,
  proporciones y separaciones de `websiteCatalogGridMetrics`, pero sobre el
  ancho de la grilla (consultas de contenedor) con umbrales que dejan un
  escritorio completo y un teléfono en los números exactos de Flutter; en los
  anchos intermedios no repite el defecto.
- **Flutter dibuja Oswald «bold» con el peso 400 engordado** (la fuente
  variable se dibuja en su instancia por defecto y Skia engrosa el contorno):
  los anchos de letra son los del 400. La HTML usa `400` con
  `-webkit-text-stroke:.032em`; con `700` los títulos cortaban otra línea.
- Cortes: cabecera 1080 px, catálogo de teléfono bajo 700 (barra «Filtro /
  Ordenar por» con hojas inferiores sin JavaScript), ficha bajo 1100 y 768,
  pie de teléfono bajo 800 (secciones plegables, sin medios de pago, como
  Flutter).
- Los íconos de marca del pie son los de Font Awesome, de la fuente que el
  build Flutter ya publica (`/assets/packages/font_awesome_flutter/...`); el
  subconjunto que deja Flutter trae los cinco. Cuando la fase 3 quite Flutter
  hay que copiar la fuente (y Barlow/Oswald) a la tienda HTML.
- Diferencias a propósito: la ficha HTML conserva la tarjeta «Despacho a
  domicilio» con la tarifa más barata real del checkout (Flutter sólo muestra
  promesas escritas en la configuración); la foto de un relacionado se
  centra (en Flutter queda pegada a la izquierda por un `Stack` sin
  alineación); el paginador del teléfono deja sólo las flechas (en Flutter
  «Siguiente» se sale de la pantalla).
- Se quitaron de la ficha la marca sobre el título, la línea «Código …» y la
  barra fija de compra del teléfono: Flutter no las tiene.

## Fase 2a: páginas de información (2026-10-05)

`/nosotros`, `/envios`, `/devoluciones`, `/terminos` y `/privacidad` las
dibuja el servidor en la ruta oculta (`/_html/<slug>`, `noindex`); las rutas
públicas siguen en Flutter hasta abrirlas. Lectura: `website_pages` con sus
`website_blocks` (las cinco a la vez, `tenant_id` en las dos tablas, como
`anon`, que sólo ve lo publicado y visible). Vista: `policy_page_model.dart`,
`policy_page_view.dart`, `website_blocks_view.dart` (héroe y contacto, para
la portada después), `block_composition.dart` y `website_page_css.dart`.

**Un dueño, no copias.** Pasaron al núcleo las definiciones base de los
bloques, la composición, la proyección por pantalla, la acción de un bloque,
el documento de lienzo, el limpiador de datos, la **normalización de bloques
al cargarlos** (era privada de `WebsiteService`, que ahora la llama), las
reglas de las páginas de información (`public_policy_content.dart`: secciones,
resumen, «tiene algo que leer», datos de contacto), los colores del tema
(`website_theme_roles.dart`, con prueba de paridad contra
`WebsiteThemeBuilder` a la décima) y el JSON-LD de la página.

**Medición.** Los rectángulos de Flutter se leen de su árbol de semántica
(`flt-semantics`, activado con el `flt-semantics-placeholder`), no de
píxeles: posición y alto exactos de cada texto. Resultado a 1440 y 412 px en
las cinco páginas: marco, héroe, secciones y contacto en los mismos píxeles;
lo que difiere es a propósito (abajo) o es un rectángulo que Flutter recorta
en el borde de la ventana.

Lo que costó una vuelta cada uno:

- **Flutter normaliza cada bloque al cargarlo**: los valores por defecto del
  tipo bajo lo guardado. El héroe de `/envios` no guarda botón y Flutter
  muestra «Ver catálogo» (del defecto); sin normalizar, el título quedaba
  40 px más abajo.
- **Espaciado de letras heredado de Material 3**: un texto cuyo estilo no
  dice `letterSpacing` hereda el de su rol (bodyMedium 0,25; bodyLarge y
  labelMedium 0,5; titleMedium 0,15; bodySmall 0,4; chips 0,1). Sin él un
  párrafo de teléfono cortaba una línea menos (26 px) y la dirección del pie
  de la fase 1 cortaba en otro lugar. Medir el ancho del texto en Chrome con
  y sin el espaciado lo decide (411,1 px exactos con 0,25).
- **Cada línea mide redondo**: alto = `round(tamaño × altura)` (21,28 → 21;
  24,65 → 25); la hoja usa esos píxeles enteros.
- **Densidad del tema −1** (`PublicStoreTheme`): el botón mediano del editor
  (mínimo 44, relleno 12/20) queda en 40 de alto y 20 de relleno; el borde
  va dentro (en CSS se resta 1 px al relleno).
- **`PageComposition` centra cada bloque al ancho de su contenido**: un
  párrafo largo llena la columna, las tarjetas de 500 quedan centradas. En
  CSS: `width:fit-content`; la `Wrap` nunca pone dos tarjetas porque la
  columna mide a lo más 720.
- **Los datos se leen al ancho de la columna y la visibilidad al de la
  ventana**: entre 816 y 991 px la columna mide menos de 640 y el bloque se
  lee como teléfono. Por eso la composición se calcula en seis bandas de
  ancho y un bloque sólo se repite si cambia en alguna.
- **La hoja compartida terminaba con una llave de más**, que se comía la
  primera regla de la hoja siguiente (el tema de la página nunca aplicaba).
  Prueba: `every stylesheet closes what it opens`.
- Jaspr parte el texto largo en líneas con sangría: `white-space:pre-line`
  dibujaba una línea en blanco; los saltos simples van como `<br>`.

**Arreglado en las dos tiendas.** El bloque de contacto mostraba al
visitante «Completa tus datos de contacto desde el editor» en `/nosotros`,
`/terminos` y `/privacidad`, con la dirección, el teléfono y el correo en
Configuración: ahora usa esos datos cuando el bloque no trae los suyos
(`resolveWebsiteContactBlockFacts`) y el aviso queda sólo en Edición. El
chip de la página actual dibujaba un disco oscuro con un visto sobre el
ícono (`showCheckmark: false`). El catálogo de bloques
`assets/block_marketplace/` (que la app nunca carga) traía para el contacto
un teléfono y una dirección inventados: quitados.

Un bloque que el HTML aún no dibuja (ni como sección ni con su renderer) se
omite y se nombra en `x-storefront-uncovered`; una página así no debe pasar
a HTML al abrir las rutas.

**Rutas abiertas.** Las cinco pasan al servidor con reescrituras exactas en
`firebase.json`. El generador ya no escribe sus instantáneas (Hosting serviría
el archivo antes que la reescritura) y su validación no las exige; el sitemap
las sigue nombrando cuando están publicadas. La revisión de la publicación
lee de `firebase.json` las rutas exactas del servidor y pide las que el
sitemap publica (`exactServerRoutes` en `check_storefront_html_routes.mjs`).
Ninguna de las cinco tiene hoy un bloque sin cubrir. Para revertir, se quitan
las cinco reescrituras.

## Fase 2b: la portada (2026-10-05)

`/_html/` dibuja la portada completa (`home_page_model.dart`,
`home_page_view.dart`): encabezado sobre el primer bloque, carrusel (fotos y
la diapositiva compuesta de «Cámaras»), productos elegidos a mano, grilla de
categorías, marcas, video de YouTube y reseñas de Google. Medida contra el
árbol de semántica de Flutter a 1440 y 412 px: todos los textos, botones,
tarjetas, flechas y puntos en las mismas coordenadas (dentro de 1 px); el
recorrido (encabezado al bajar, avance automático, flechas, deslizar, páginas
de marcas en el teléfono) probado en Chrome. `/` sigue en Flutter: falta
abrirla.

**Un dueño, no copias.** Pasaron al núcleo el botón de una diapositiva
(`resolveWebsiteCarouselSlideAction`), el id de un enlace de YouTube
(`websiteYouTubeVideoId`) y las reseñas (`WebsiteGoogleReviewsContent`:
las sincronizadas cuando el bloque no trae, filtro por estrellas y cantidad,
promedio sobre la lista completa). Flutter las llama desde ahí.
Antes de mover lógica de un widget al núcleo hay que buscar en `test/` los
contratos que leen el código del widget como texto (`sourceOf(...)`):
`website_collections_responsive_policies_test.dart` buscaba
`data['minRating']` en el carrusel de reseñas, fallaron tres en la
integridad de la publicación y la tienda de `ddf3cfba` no se desplegó (una
vuelta de CI, ~25 min). El contrato se apunta al dueño nuevo y además se
comprueba que el widget lo consume.

Lo que costó una vuelta, para el que siga:

- **El encabezado de la portada no reserva su alto** (`allowOverlayAtTop`):
  flota fijo sobre el carrusel, transparente con un velo negro 52→24 % y el
  logo y las palabras en blanco; pasados 50 px de scroll se vuelve sólido
  (el color en 300 ms, el resto de golpe), y también mientras un menú está
  abierto. Un script en línea dentro del encabezado pone el estado antes de
  pintar nada debajo; sin scripts queda sólido.
- **El ítem actual del menú usa el color del texto del encabezado**, no el
  de la marca (`_buildNavItemLink` recibe `textColor`): negro 87 % sobre
  blanco, blanco sobre la foto. Las páginas del servidor lo pintaban azul
  desde la fase 1; corregido en todas.
- **El lienzo (`CanvasBlock`) escala cajas, radios, bordes y la letra de
  los botones, pero no el texto**: escala = ancho/ancho de diseño, nunca
  mayor que 1, centrado si sobra. En CSS con unidades de contenedor
  (`--s:min(100cqw / var(--dw),1px)`), así el mismo HTML sirve a cualquier
  ancho; un juego de capas por pantalla que dibuje distinto (legado: teléfono
  bajo 600 y el resto; canónico: 600/900).
- **El cruce entre diapositivas usa la misma curva al entrar y al salir**:
  `AnimatedSwitcher` reproduce la saliente al revés con su curva de salida,
  y en el tiempo eso es `easeOutCubic` también.
- **Una altura mínima no es una altura**: con `minimumHeight` Flutter no da
  alto al bloque (las marcas ponen su relleno de 48/16 y además 16 de la
  fila) y lo centra dentro de los 510; con altura exacta, nada de eso.
- **Las listas en una fila sin alto toman la altura 1,5 de `bodyMedium`**
  (el `DefaultTextStyle` de la tienda), sin redondear: tarjetas de
  categoría, título de productos (33 px de 22), reseñas.
- **Un `Wrap` alinea arriba**: en el pie, el chip de transferencia quedaba
  centrado con el logo de 60 px; arreglado en todas las páginas.

**Red de seguridad para las rutas abiertas.** El editor publica al
instante, sin pasar por CI: si el dueño agrega a una página abierta un tipo
de bloque que el HTML aún no dibuja, el servidor no lo omite, responde la
página de Flutter (`app.html` de Hosting) con la cabeza de esa página (título, descripción, canónica,
robots, sociales, JSON-LD) y su texto en el `<noscript>`, y lo marca con
`x-storefront-fallback: flutter` (`flutter_shell.dart`). Sin eso Google
leería la portada en `/envios`. La copia oculta sigue mostrando lo que el
HTML dibuja.

Para capturar otra diapositiva de Flutter se hace clic en su punto por
coordenada y sin activar la semántica: con ella activa el clic no cambió la
diapositiva (observado, sin buscar la causa).

Lo que queda distinto, medido: los textos de capa con altura de línea 1,0
quedan 1–2 px más arriba que en Flutter (su reparto del interlineado no es
el de CSS) y la etiqueta «Iniciar sesión» de Flutter cae en la letra por
defecto del motor porque su estilo no nombra familia (4 px más ancha).

## Fase 2c: `/` en el servidor (2026-10-05)

Hosting sirve un archivo que calza exacto antes que cualquier reescritura, y
`/` calzaba con el `index.html` de Flutter. El generador
(`generate_product_seo_snapshots.dart`) ahora copia la entrada de Flutter a
`app.html`, la usa como destino de `**` (carrito, checkout, portal, servicios)
y, cuando `/` es del servidor, borra el `index.html` raíz; el validador falla
si queda un archivo en una ruta del servidor. No hay service worker
(`--pwa-strategy=none`) ni script que busque `index.html` por nombre; el
`<base href="/">` es el mismo. `app.html` tiene su regla de caché
(`max-age=0, must-revalidate`), como tenía `index.html`. La red de seguridad
lee `app.html`: una portada con un bloque que el HTML no dibuja la responde
Flutter con la cabeza de la portada. Revertir = quitar la reescritura de `/`
(el generador vuelve a dejar el `index.html`).

Medido en un teléfono lento (4× CPU, 1,6 Mbps, 150 ms; caché fría), la
portada:

| | Flutter (`/` hasta hoy) | HTML |
|---|---|---|
| Primer cuadro con contenido | 19,9 s (`flutter-first-frame`) | 1,0–1,3 s (texto y encabezado) |
| Foto principal | después de eso | 4,8 s |
| LCP que reporta el navegador | 1,8 s (la pantalla de carga, no la tienda) | 4,8 s |

El LCP de Flutter que ve Google es el de su pantalla de carga: el número de
Core Web Vitals de la portada va a «empeorar» al abrirla aunque la tienda se
vea 15 s antes. No es una regresión.

Lo que costó una vuelta:

- **Una foto lazy apilada bajo otra igual se descarga**: está «a la vista»
  para el navegador aunque su diapositiva esté oculta. La tercera diapositiva
  es un PNG de 2,1 MB subido sin pasar por la optimización del editor; se
  bajaba junto a la primera (82 KB) y le quitaba el ancho de banda (carga
  completa 16 s). Ahora una diapositiva posterior nombra su foto en
  `data-src` y el script la pide antes de mostrarla, la segunda cuando la
  página terminó de cargar (6 s).
- **El `Wrap` de Flutter mide lo que su fila más ancha**: centrado en el
  pie, con cada fila empezando a la izquierda. Una línea flex que se parte no
  se encoge a su fila más ancha, así que el servidor calcula ese ancho con
  las columnas de la tienda y lo aplica con container queries
  (`SiteFooter.wrapCss`). Entre 800 y ~1000 px «Contacto» baja bajo el logo.
- **Las fuentes pesaban**: seis TTF (Barlow ~50 KB comprimido cada uno,
  Oswald 91) compartían el ancho de banda con la foto principal. Cada cara
  se declara ahora dos veces sin rangos que se crucen: su subconjunto latino
  en WOFF2 (`web/fonts/`, 21–28 KB, `scripts/fonts/subset_storefront_fonts.sh`)
  y el TTF completo para el resto de Unicode; el TTF va también como segunda
  fuente del WOFF2, porque el servidor se publica antes que Hosting y un
  archivo que aún no existe no puede dejar el texto en la letra del sistema.
  Foto principal 4,8 → 3,7 s; el texto mide igual al píxel.

## Fase 2d: `/servicios` (2026-10-05)

`/servicios` no es una página del editor: Flutter la dibuja con el mismo
catálogo que `/productos` y `product_type = service`
(`_defaultProductTypeForRoute`). El servidor hace lo mismo: las rutas
`/servicios` y `/servicios/categoria/<slug>` van al catálogo con
`CatalogRequest.services`, que pide `p_product_type = service` a la lista y
a las facetas; el modelo cambia la raíz de presentación
(`WebsiteCatalogRoot.services`), el título («SERVICIOS»), el sustantivo
(«Mostrando 1 - 20 de 59 servicios», «Buscar servicios»), las migas y la
canónica. El título y la descripción para Google son los que la instantánea
ya publicaba («Servicios y precios del taller de bicicletas | …»), ahora en el
núcleo (`publicServicesCatalogSeoTitle`/`Description`) para el generador y el
servidor; el JSON-LD lista cada servicio como `Service` con su precio. Con la
reescritura en `firebase.json`, el generador deja de escribir el archivo
`servicios` y el validador falla si queda uno.

Medido contra Flutter en píxeles (bandas de filas oscuras) a 1440, 800 y
412 px: título, conteo, barra «Filtro / Ordenar por» y tarjetas dentro de
1 px. De paso se corrigió el catálogo entero: **la columna de resultados
quedaba 2 px más abajo** que la de Flutter, que suma la línea 1,5 del título
(30 px), 8 px, la línea del conteo (19,5 que su texto redondea a 20) y 28 px
hasta la grilla; en el teléfono, 27, 6 y 12. El riel ya calzaba y conserva su
posición.

A 800 px Flutter pone tres tarjetas de 141 px y el HTML dos: es la decisión
de la fase 1 (Flutter mide la ventana, el HTML la columna de resultados), no
un descuido; se mantiene.

### `/servicios` como lista de precios (2026-10-06)

El dueño aprobó la propuesta de `/servicios` del lienzo de Design («dale,
arregla el catálogo y construye la página»). No es una página del editor ni un
bloque: es un **diseño de la raíz de servicios** en «Catálogo web»
(`layout: price_list` en `catalog_category_presentations_v1`), con portada,
planes, la lista por grupo y cierre (detalle en
`docs/wiki/sitio-web/paginas/catalogo-y-fichas.md` y en el registro de
superficies). Las reglas son del núcleo (`website_catalog_price_list.dart`) y
las dibujan el servidor y Flutter; no hay medición a píxel contra Flutter
porque Flutter no tenía esta página: el HTML es el diseño aprobado y el
widget Flutter lo sigue.

Dos decisiones con costo:

- **La lista lee todo, de a 100** (el techo de `get_public_products_faceted_v2`),
  hasta 1.000. Para no sumar una espera, `/servicios` pide la primera página
  de 100 **junto** con el shell, antes de saber si es lista de precios; si es
  grilla esa lectura se descarta y pide la suya (una lectura de más sólo en
  ese caso).
- **El HTML se mide con un Supabase falso local** que lee producción y pone
  la presentación en la respuesta del shell (`fake_page_sb.mjs` en el
  scratchpad): así se ve el diseño antes de guardarlo en el editor.

## Fase 2e: `/contacto` (2026-10-05)

Tampoco es una página de bloques: Flutter dibuja `ContactPage` con los datos
de Configuración (correo, teléfono, dirección, WhatsApp, redes, horario y el
enlace de Google Maps) y la publicación de la página `contacto` del editor
(sin publicar: «Contacto no disponible», aquí con 404). El servidor la dibuja
igual (`contact_page_model.dart`, `contact_page_view.dart`,
`contact_page_css.dart`); el horario agrupado («Lunes a Viernes», «Cerrado»)
pasó al núcleo (`publicBusinessHourRows`) y Flutter lo lee de ahí. El
formulario hace lo de Flutter: los mismos mensajes en el mismo orden, el
foco en el primer campo con error, un correo a la tienda con los cuatro
campos, «Abriendo cliente de correo...» y el formulario en blanco; el correo
se abre con un enlace para que el script lo cuente como `contact` (email).
Sin scripts, el navegador lo envía con `action="mailto:"`.

Medido contra Flutter a 1440 y 412 px: todas las cajas de texto, los bordes
de los campos y los botones en la misma fila de píxeles. Lo que costó:

- **Flutter redondea hacia arriba el alto de cada línea**: 15 px × 1,5 =
  22,5 se dibuja en 23 (y 13 × 1,5 en 20). Con 22,5 cada fila del horario
  quedaba medio píxel corta y el error crecía hacia abajo.
- **Sus botones y campos son compactos en toda pantalla**, también en el
  teléfono: `VisualDensity` resta 8 px a un botón (Maps e Instagram quedan en
  el mínimo de 40, WhatsApp en 42) y 4 a un campo (51 px; el mensaje, 143).
- **La etiqueta en reposo de un campo es el `bodyLarge` del tema**: el tamaño
  del cuerpo + 2 (18 px), no los 15 del texto que se escribe.
- **El divisor del tema mide 1 px** y no trae espacio propio.
- **Las etiquetas de sus botones caen en la Roboto del motor** (su estilo no
  nombra familia), como «Iniciar sesión»: aquí llevan la letra de la tienda.

De paso se arregló un enlace roto de Flutter: el ajuste `instagram` guarda
la dirección completa y la página le anteponía `https://instagram.com/`;
ahora las dos tiendas usan `normalizeSocialUrl`, como el pie.

Para publicar el servidor con trabajo a medias en el árbol: el hook bloquea
`git stash` en el checkout compartido y `deploy_cloud_run.sh` se niega con
cambios sin commit en el servicio o el núcleo. Se copian esos archivos al
scratchpad, se dejan los de `HEAD` (`git show HEAD:<ruta> > <ruta>`), se
publica y se devuelven con `cmp` de cada uno.

## Fase 2f: Flutter deja la página a las rutas HTML (2026-10-05)

Desde la fase 2c, Flutter sólo arranca en el carrito, el checkout, la cuenta
y el portal. Un clic suyo dentro de la tienda (el menú, el logo, un enlace
del pie) navegaba con `go_router` y dibujaba su propia copia de la portada,
del catálogo o de una página de información: la visita seguía en Flutter
y no veía la página que ve Google. Ahora `_navigateToHref`
(`public_store_layout.dart`) hace una carga completa cuando la ruta de
destino la responde el servidor (`storefrontHtmlServes`, en el núcleo), sólo
en la tienda pública en un navegador: nunca en el editor ni en su vista
previa, ni en la tienda que el ERP monta en `/tienda`.

La lista de rutas del servidor existe dos veces: las reescrituras de
`firebase.json` y `storefrontHtmlRouteSources`. Una prueba
(`product_seo_snapshot_server_routes_test.dart`) las compara: una ruta nueva
del servidor se agrega en los dos lados en el mismo commit.

Los enlaces de los bloques guardados como `/productos?category=<id>` (diez
en la portada) pasaban por un 301 antes de la categoría. Ahora el servidor
los escribe con la ruta limpia de la categoría publicada
(`StorefrontShell.categoryHref`, el mismo que ya usaban los menús): ni el
visitante ni Google siguen una redirección. Lo guardado en el editor no
cambia.

Dos trampas de la publicación, del mismo día:

- **Un commit que sólo toca el servidor no dispara la publicación de la
  tienda** (el filtro de rutas no incluye `services/storefront_html/lib`):
  se publica con `deploy_cloud_run.sh` y nada lo revisa hasta la próxima
  publicación. Tampoco la disparaba un cambio sólo del núcleo, con el que se
  compila la tienda Flutter; ahora `packages/vinabike_public_core/**` está
  en el filtro, como en los flujos de macOS, Windows y la compuerta.
- **Publicar el servidor con una publicación de la tienda pendiente la hace
  fallar**: la revisión de rutas compara Cloud Run con la fuente de *su*
  commit, y corre después de publicar Hosting. Si ya se publicó, se cancela
  esa corrida (mientras siga en las compuertas no publicó nada) y se empuja
  un commit que la dispare sobre el `HEAD` que corre Cloud Run.
- **Un `publication_context` «cancelado» sin pasos, 15 a 19 minutos después
  de crearse, no es una prueba**: GitHub no consiguió máquina («The job was
  not acquired by Runner of type hosted even after multiple attempts», en
  las anotaciones del trabajo). Le pasó a dos corridas seguidas durante el
  incidente de Actions del 2026-10-05; se repite con `gh run rerun <id>`.

### Costo medido (2026-10-06)

Facturación del 1 al 5 de octubre: Cloud Run CLP 40, cubierto entero por la
cuota gratis (CLP 0); Artifact Registry 72 MB (CLP 0), ahora con regla de
limpieza (se quedan las 5 imágenes más nuevas y se borran las de más de 7
días). Lo que sí cobró fue **Firebase Hosting, CLP 2.911**: rastreadores de IA
bajando la tienda Flutter (~7 GB/día) y versiones viejas guardadas sin
límite. El HTML terminó con lo primero y las versiones quedaron en 50 por
sitio; el detalle está en el wiki, `publicacion-y-despliegue.md`.

## Fase 3a: el carrito (2026-10-06)

`/carrito` lo responde el servidor (`cart_page_model.dart`,
`cart_page_view.dart`, `cart_page_css.dart`). El carrito vive en el
navegador, y Hosting borra las cookies, así que la primera respuesta no puede
saber qué tiene: el servidor manda el marco, igual para todos, y el script de
la página pide `/carrito/lineas?l=<id>:<q>,…`. Esa respuesta vuelve a leer
los productos como Flutter al restaurar (`get_public_products` sin filtro de
stock y `get_public_product_tax_classifications`; sin tasa no se paga),
ajusta las cantidades al stock, cuenta las líneas ajustadas y dibuja líneas y
resumen. El navegador guarda lo ajustado, como hace Flutter. La regla de IVA
por línea (`StorefrontTaxSummary`) pasó al núcleo: carrito HTML, checkout y
confirmación calculan igual.

+, − y eliminar escriben el mismo documento que «Agregar», bajo el mismo
candado (`window.vinabikeCart` del script global; el del carrito corre
después, por `pageScripts` de `sitePage`). Otra pestaña abierta se actualiza
sola con el evento `storage`. Antes del primer pintado un script en línea
decide entre «vacío» y «cargando», para que un carrito vacío no parpadee.

Medido contra Flutter a 1440 y 412 px, vacío y con líneas: todo texto y
botón en el mismo píxel, los mismos totales (neto, IVA, total) y el mismo
documento guardado. En un teléfono lento las líneas están en pantalla a los
**1,2–1,5 s** con 203 KB, contra **18,4 s** y 3.640 KB de Flutter
`[Prod 2026-10-06]`. El checkout sigue en Flutter: «Proceder al pago» empieza
a bajar `main.dart.js` cuando el visitante apunta al botón.

Lo que costó:

- **Una clase genérica chocó otra vez** (como `.sheet` en la fase 1): `.cart`
  ya era el formulario de «Agregar» de la ficha, un `grid`, y dejó el carrito
  de 104 px de ancho. La raíz se llama `cart-page`.
- **`flex: 7` / `flex: 4` no es el `Expanded` de Flutter**: CSS descuenta el
  relleno del resumen antes de repartir y lo corrió 30 px; una grilla
  `7fr 4fr` reparte como Flutter.
- **Un botón con el relleno por defecto de Material** pierde 4 px por lado con
  la densidad compacta (24 → 20) y su etiqueta cae en otra letra: se mide.
  *Corregido el 2026-10-06:* la causa no es la densidad, que nunca quita
  relleno horizontal (`ButtonStyleButton`: `dx = max(0, …)`); los 20 son el
  relleno de botón del tema del sitio (`button_size: medium`). Un botón con
  relleno propio de 24 conserva sus 24.
- La revisión de rutas de la publicación sólo miraba lo que está en el
  sitemap; ahora exige que `/carrito` venga del servidor con `noindex`
  (`privateServerRoutes`).

## Fase 3b: el checkout (2026-10-06)

`/checkout` en el servidor (`checkout_page_view.dart`, `checkout_page_css.dart`,
`checkout_page_script.dart`, `checkout_records_script.dart`), por ahora sólo en
la copia oculta `/_html/checkout`. Como el carrito, el formulario es el mismo
para todos (con los medios de pago que la tienda acepta en ese momento y el
punto de retiro) y las líneas llegan de `/checkout/lineas`, con lo que el
pedido dice de cada una (`orderItems` de Flutter) y el neto, IVA y bruto.

El navegador llama a Supabase **directo**, con la clave publicable, igual que
Flutter: capacidades, cotización, `google-places-proxy`,
`create_public_online_order_with_access` y `mercadopago-create-preference`.
No pasa por Cloud Run: no suma costo y la confianza es la misma de hoy.

Lo que hace posible convivir con Flutter es escribir **los mismos registros**
que `CheckoutSessionStore` (`checkout_records_script.dart`): el intento con su
carga exacta antes de la primera llamada, el recibo, el acceso al pedido y el
resultado del carrito. La página del pedido (`/pedido/<id>`) y el regreso de
Mercado Pago siguen siendo Flutter y no cambian.
`test/unit/storefront_html_checkout_contract_test.dart` corre ese script en
Node y lee lo escrito con los lectores de Flutter, en ambos sentidos.

- **Sesión del cliente:** la de Flutter (`sb-<ref>-auth-token` en
  localStorage). Si venció, se renueva y se escribe de vuelta en el formato que
  lee gotrue-dart. «Crear una cuenta» usa PKCE como `supabase_flutter`: deja el
  verificador en `flutter.supabase.auth.token-code-verifier`, así el enlace del
  correo inicia sesión.
- **Transferencia:** antes de abrir la página del pedido, el carrito pierde una
  sola vez lo pedido (`consumeCartOnce`, contra la revisión del carrito con
  que se armó el pedido). A diferencia de Flutter, no vuelve a proyectar las
  líneas que quedan contra el catálogo; las ajusta el carrito al abrirse.
- **Medido contra Flutter** con su árbol de semántica: 43 cajas a 1440 px y
  43 a 412 px a menos de 0,6 px. Lo no obvio:
  - La densidad del tema (−1) quita 4 px a campos, radios y casillas. Un campo
    mide 18 + 27 + 18 − 4 = 59 px, un radio 36.
  - El texto del campo es el `bodyLarge` del tema (18 px) y la etiqueta su
    `bodyMedium` (16 px).
  - Flutter redondea **cada línea** de un párrafo (13 × 1,45 da líneas de
    19 px). La altura de línea se escribe ya redondeada.
  - Las columnas de la dirección siguen al `LayoutBuilder` de la sección (dos
    columnas desde 640 px de contenido): en CSS es una consulta de contenedor,
    no de la ventana. Con la ventana, entre 980 y 1157 px salía al revés.
  - Un `span` con margen vertical no lo aplica: el subtítulo de cada opción
    sumaba 4 px menos.
- **Íconos:** salen de la misma fuente que dibuja Flutter
  (`MaterialIcons-Regular.otf`) con `tool/material_icon_paths.py`, sin
  descargar nada.
- **Probar pedidos, siempre en local:** `tool/run_local_checkout.sh` siembra
  una tienda de prueba (`tool/local_checkout_seed.sql`) y sirve el HTML contra
  la base local. Las funciones Edge las responde la prueba del navegador.

  Escenarios probados: transferencia, Mercado Pago (redirige a su
  `init_point`), retiro, cliente con sesión vencida, respuesta perdida
  (reintenta y recupera el **mismo** pedido) y página recargada a medio
  intento.

  Trampas del sembrado:
  - Insertar una tienda deja su id como sujeto de la petición
    (`request.jwt.claim.sub`), y la clasificación de IVA de un producto exige
    un usuario real como autor: el sujeto se fija después de la tienda.
  - Una tienda nueva nace con ajustes por defecto, así que se usa `on
    conflict`.
  - Un pedido deja reservas y eventos que no se dejan borrar; el reinicio
    local apaga disparadores y llaves sólo para las filas de la tienda de
    prueba.

Lo que costó: probando con la sesión del cliente apareció un **error de
producción** que no venía de la migración. Desde `20260711123000`, un cliente
con sesión no podía pagar por transferencia ni en Flutter: la base deshacía el
pedido al procesarlo. Se arregló en `20261006090000`
([checkout](../wiki/sitio-web/paginas/checkout-y-pedidos.md)).

`/checkout` quedó abierto al servidor el 2026-10-06 (d487113c, publicación
37433245945): lo responde Cloud Run con `noindex` y Flutter le deja la página.

## Fase 3c: la página del pedido (2026-10-06)

`/pedido/<id>` en el servidor (`order_page_view.dart`, `order_page_css.dart`,
`order_page_script.dart`). El acceso al pedido vive en la pestaña
(`CheckoutSessionStore`), así que el servidor manda el marco —el mismo para
todos, con los datos de transferencia de los ajustes del editor— y el script
hace lo que hace `OrderConfirmationPage`:

- toma el acceso de la pestaña (el recibo del intento manda sobre uno
  guardado), cierra el carrito una sola vez y, en una transferencia, retira el
  intento;
- con un regreso de Mercado Pago (`?status=…&payment_id=…`) **verifica** el
  pago con `mercadopago-get-payment` antes de creerle a la dirección, y sólo
  entonces cierra el carrito y el recibo;
- lee el pedido con `get_public_online_order_by_access_token` y lo dibuja con
  las mismas palabras de `OrderConfirmationPolicy` para cada estado (pagado,
  en revisión, fallido, por transferencia, cancelado, recibido);
- mide `purchase` (GA4) y `Purchase` (Meta, `eventID` `purchase_<id>`) igual
  que Flutter: cada carga, salvo un pedido cancelado o un pago fallido; los dos
  descartan un id repetido.

Los registros nuevos (acceso con migración de la llave antigua, resultado del
carrito al presentarlo, aviso confirmado, retiro del recibo) están en
`checkout_records_script.dart`, que ahora comparten el checkout y el pedido;
`test/unit/storefront_html_checkout_contract_test.dart` los cruza con Flutter
en ambos sentidos (8 casos).

**El resumen en PDF** («DESCARGAR RESUMEN DEL PEDIDO») tiene un solo dueño:
`buildOrderSummaryPdf` en el núcleo compartido
(`packages/vinabike_public_core/lib/public_store/documents/`). La app lo llama
con su `OnlineOrder`; el servidor lo arma en `POST /pedido/resumen.pdf`, con el
acceso en el cuerpo (nunca en la dirección), y las fuentes Barlow las lee una
vez de Hosting, que sirve los mismos archivos que empaqueta Flutter.
`test/unit/order_summary_pdf_contract_test.dart` exige que las dos lecturas
del pedido digan lo mismo. Las palabras de los estados del pedido pasaron al
núcleo (`online_order_labels.dart`) y los getters de `OnlineOrder` las llaman.

- **Medido contra Flutter** con el pedido de prueba respondido por el
  navegador (nada llega a la base): los seis estados, el regreso aprobado con
  aviso del carrito y la página sin acceso, a 1440 y 412 px. Todas las
  posiciones coinciden al píxel. Esa página **no usa los roles del tema**:
  pinta con sus propios literales (azul del logo, líneas y superficies
  cálidas, un acento por estado), así que el CSS usa los mismos.
- **De punta a punta en local:** transferencia desde el checkout HTML hasta el
  pedido, carrito vaciado, PDF descargado y la página que sigue abriendo al
  recargar.
- Con la página del pedido en HTML, el checkout ya no precarga `main.dart.js`
  al apuntar a «Realizar pedido» (eran 3,6 MB para nada).

`/pedido/**` quedó abierto el 2026-10-06 (ea3e52a3, publicación
37437697313). En un teléfono lento el pedido aparece en 0,9–1,0 s con 168 KB;
Flutter lo dibujaba a los 22 s con 3,85 MB.

### El encabezado con sesión y el menú del teléfono (2026-10-06)

Dos diferencias con Flutter que estaban en vivo desde las primeras fases:

- **Con sesión**, Flutter muestra la cuenta (inicial, nombre, «Mi cuenta» y el
  menú del portal) y el HTML seguía diciendo «Iniciar sesión». Ahora la sesión
  del cliente vive en el script común (`window.vinabikeSession`: lee
  `sb-<ref>-auth-token`, la renueva bajo el candado de `supabase_flutter`, la
  cierra con `logout?scope=local`) y el checkout la usa en vez de la suya. El
  encabezado lee la fila de `customers` de la tienda, como
  `CustomerAccountService.isAuthenticated`; la pestaña recuerda lo último que
  mostró para que la página siguiente ya salga con la cuenta, sin parpadeo.
- **El menú del teléfono** no usaba la regla de Flutter
  (`PublicCategoryNavigationProjection.forMobile` sobre el árbol con
  `PublicPagePublication.forAllAudiences`): «Accesorios», con sus hijas sin
  publicar, salía como grupo vacío. Ahora la usa (`StorefrontShell.menuFor`), y
  cada fila tiene la letra (18 px), los colores del tema y el subtítulo «Solo
  esta categoría» de Flutter. Un enlace a una página necesita su página
  adjunta antes de la regla: sin ella la toma por un enlace sin resolver.

Medido con una sesión inventada que la prueba responde (ninguna lectura llega
a la base con ese token): encabezado y menú de cuenta a ±2 px a 1440, el menú
del teléfono con sesión y sin ella al píxel en alto.

### El menú ancho de escritorio (2026-10-06)

En escritorio «Componentes» abría en el HTML una lista simple; Flutter abre un
panel a todo el ancho. Ahora el HTML dibuja ese panel
(`services/storefront_html/lib/src/mega_menu_view.dart`), sobre la misma
proyección de escritorio que Flutter (`menuFor(..., mobile: false)`):

- **Cuál se abre:** un ítem con hijas y `megamenu` en su «Clase CSS» abre el
  panel (`MegaMenuButton`); sin ella, la lista compacta
  (`NavigationDropdownButton`). La función pública del menú no traía
  `css_class`: la agrega `20261006120000` (aplicada y verificada). Los dos
  disparadores son botones, como en Flutter; la página de la rama es «VER
  TODO», dentro del panel, y todos sus enlaces vienen en el HTML.
- **Un dueño:** la foto, los velos, el ancho y la alineación de cada sección
  salen de `megaMenuPresentationOf` y el blanco o negro de las letras de
  `PublicHeaderContrastMode`, los dos en el núcleo; Flutter los usa también.
- **Medido contra Flutter a 1440 y 1100 px:** pestañas, foto de sección,
  tarjetas, «Volver a…» y «VER TODO EN…» a ±0,1 px; la foto sin
  desplazamiento (difiere sólo el suavizado). Tiempos de Flutter: abre 110 ms
  después de posar el puntero, cierra 180 ms después de salir, aparece en
  190 ms, cambia de sección en 150 ms y la revela en 1250 ms; a los 450 ms las
  dos capturas coinciden.

Tres reglas de Flutter que no se ven en el código del widget y que valen para
cualquier página:

- **El interlineado.** Un `TextStyle` suelto reparte el espacio extra de una
  línea en proporción al ascenso y descenso de la fuente
  (`TextLeadingDistribution.proportional`); CSS lo reparte a medias. Con
  Barlow (1,0 y 0,2) el texto de Flutter cae `(alto − 1,2 × tamaño) / 3` px
  más abajo: en el encabezado, 1 px. Se corrige moviendo el texto, no la caja.
  *Precisado el 2026-10-06:* un estilo que sale del tema (`titleLarge`,
  `bodyMedium`… de `Typography.englishLike2021`) lleva
  `TextLeadingDistribution.even`, igual que CSS: no se mueve. El portal,
  todo derivado del tema, cuadró sin corrimiento; con él quedaba 13 px
  arriba en el título de 72 px.
- **Un botón sin familia es Roboto.** Un `TextStyle` de botón sin
  `fontFamily` («INICIAR SESIÓN», «Volver a…») no hereda Barlow: Flutter lo
  dibuja en Roboto 400, que su motor baja de Google, con negrita fingida. El
  HTML carga esa misma Roboto (`vb-roboto`) sólo donde se ve, y como Chrome no
  la engruesa, la negrita es un trazo del ancho de Skia (1/24 del tamaño a
  9 px, 1/32 a 36 px).
- **El borde no suma.** El borde de un botón de Flutter (`side`) se dibuja
  dentro del tamaño: en CSS se resta del relleno.

Sigue: el portal y la cuenta (`/cuenta/**`), lo último que dibuja Flutter en
la web.

## Fase 4: el portal y la cuenta — plan (2026-10-06)

Lo que queda en Flutter es todo de un cliente con sesión: ~5.800 líneas de
páginas (`lib/public_store/pages/customer_*.dart`) y ~9.500 de piezas
(`customer_portal_layout.dart`, `customer_portal_style.dart`, filas de pedido
y de trabajo, tarjeta de bici, chats) más `customer_portal_presentation.dart`
(663, las reglas de estado). Nada de eso lo indexa Google; la ganancia es la
velocidad para quien entra a ver su pedido o su bici.

**Cómo se dibuja sin dos dueños.** La sesión vive en el navegador
(`sb-<ref>-auth-token`; Hosting borra las cookies), así que el servidor no ve
al cliente al servir la página. Pintar el portal con JavaScript duplicaría
las reglas de `customer_portal_presentation.dart`. Se hace como el PDF del
pedido: la página llega con su marco y el script pide al servidor las
secciones con el token del cliente en la cabecera; el servidor lee Supabase
**con ese token** (RLS, sin clave de servicio, sin guardarlo) y devuelve el
HTML armado con las reglas movidas al núcleo. Sin sesión, la página muestra
la puerta de Flutter («Entra a tu cuenta» e «Iniciar sesión»), no redirige.

Lecturas a portar, todas de `CustomerAccountService`: `customers` (por
`auth_user_id` y `tenant_id`), `customer_addresses`, `online_orders` con sus
líneas y las fotos de `products`, `bikes` y `mechanic_jobs`. Antes de leer, el
alta idempotente `provision_current_public_store_customer(p_tenant_id)`.

Orden:

- **4a, leer:** `/cuenta` (resumen), `/cuenta/pedidos`, `/cuenta/bicicletas`,
  `/cuenta/servicios`, con sus fichas (detalle de bici y de trabajo).
- **4b, escribir:** `/cuenta/perfil` y `/cuenta/direcciones` (formularios con
  las mismas validaciones del núcleo; el autocompletado de direcciones es el
  del checkout HTML).
- **4c, entrar:** `/cuenta/login` en su modo simple (correo y contraseña,
  registro, «¿Olvidaste tu contraseña?», Google). Los enlaces que vuelven del
  correo (`code`, `token_hash`, `type`, invitación, recuperación) siguen
  abriendo Flutter, que los canjea: para eso el HTML guarda el verificador
  PKCE donde lo busca `supabase_flutter` en la web —
  `localStorage["flutter.supabase.auth.token-code-verifier"]`, el texto
  `"<verificador>/<evento>"` codificado en JSON por `shared_preferences`— y la
  sesión en `sb-<ref>-auth-token`, que ya lee `window.vinabikeSession`.
- **4d, chats:** tiempo real; al final, o se quedan en Flutter si no hay
  ganancia que medir.

## Fase 4a: el portal, leer (2026-10-06)

`/cuenta`, `/cuenta/pedidos`, `/cuenta/servicios` (con `?bike_id=`) y
`/cuenta/bicicletas` en el servidor (`portal_page_view.dart`,
`portal_page_css.dart`, `portal_page_script.dart`, `portal_page_route.dart`),
con sus fichas de trabajo y de bici.

- **El marco y el contenido.** La página llega con la puerta («Entra a tu
  cuenta»); con una sesión en el navegador, un script antes de pintar la
  cambia por «Preparando tu cuenta», como Flutter mientras lee al cliente. El
  script pide `POST /cuenta/vista` con el token en `authorization`; el
  servidor lee Supabase **como ese cliente** (RLS, más el filtro de tienda en
  cada lectura, `SupabasePublicReads.customerPortal`) y responde la página
  armada. Un token rechazado responde `expired` y el navegador lo renueva una
  vez (`vinabikeSession.renew`); una sesión que no es cliente de la tienda,
  «No pudimos abrir esta cuenta». El token no se guarda ni se escribe en un
  registro; la respuesta es `no-store`.
- **Un dueño.** Lo que cada página muestra y en qué orden salió de las
  páginas de Flutter al núcleo (`customer_portal_plans.dart`: resumen,
  pedidos, taller, franja de servicio, garantía), igual que el armado de las
  filas (`customer_portal_snapshot.dart`), el dibujo de la bici
  (`customer_bike_drawing_geometry.dart`, que Flutter pinta y el HTML escribe
  en SVG) y las reglas de estado (`customer_portal_presentation.dart`,
  `order_confirmation_policy.dart`, `online_order.dart`, `bike_type.dart`).
  Flutter usa los mismos.
- **Las fechas** en la hora de la tienda: el servidor corre en UTC, así que
  `usePortalTimeZone()` hace que `portalLocalTime` lea un instante en
  America/Santiago; una fecha sin zona (`2026-09-24`) queda como está.
- **Filtros sin ida y vuelta.** «Pedidos» y «Taller» llegan con cada pestaña
  o bici ya dibujada (`data-view`); un filtro muestra la suya al instante,
  como el estado de la página en Flutter, y la grilla de fichas queda como la
  arma Flutter para esa cantidad.
- **Archivos del trabajo** (6 de 532 trabajos los tienen): la miniatura con un
  enlace firmado por 5 minutos y, al tocarla, uno nuevo (`POST
  /cuenta/archivo`) en otra pestaña, en vez del visor de Flutter.
- **Sin pie de la tienda:** Flutter monta el portal con
  `_buildPageNoScroll`, que no dibuja el pie; el HTML tampoco
  (`sitePage(showFooter: false)`).
- **Medido contra Flutter** con datos reales anonimizados, a 1440 y 412 px,
  sin sesión, vacío y con fichas abiertas: los bordes de cada bloque en la
  misma fila de píxeles y el texto a ±1 px.

Lo que costó, y vale para las páginas que siguen:

- **El borde de un `DecoratedBox` o de un `Material` va dentro de la caja**,
  sobre el relleno; un `Container` lo suma. La franja de datos de las fichas
  medía 2 px de más y corría todo lo de abajo.
- **SkParagraph pone la mitad del espaciado entre letras antes de cada letra**
  y la mitad después; CSS todo después. Un rótulo con 2,6 px de espaciado
  empieza 1,3 px más a la derecha en Flutter.
- **Una clase genérica chocó por tercera vez:** `.foot` (el pie de la tienda)
  pintó de azul la columna del portal. Las clases del portal llevan `pt-`.
- **Un reinicio `.pt button{…}` le gana a `.pt-chip{…}`** por especificidad:
  los reinicios van en `:where(.pt)`.

### Pendiente

- Las copias de una foto reemplazada quedan en Storage (pocos KB cada una);
  una limpieza de las que ninguna fila nombra, si algún día pesan.
- 4d (chats) sigue en Flutter; 4c (entrar) se hizo el mismo día (abajo).

## Fase 4b: el portal, escribir (2026-10-06)

`/cuenta/perfil` y `/cuenta/direcciones` en el servidor
(`portal_forms_view.dart`, parte de `portal_page_view.dart`), con el diálogo
de la contraseña en sus tres pasos, el formulario de una dirección con la
búsqueda de Google Maps, la confirmación de borrar y el menú de cada fila.

- **Lo que se guarda va al servidor, no a Supabase desde el navegador.** El
  formulario manda `POST /cuenta/accion` `{path, query, action, values}` con
  la sesión en `authorization`; el servidor revisa con las reglas del núcleo,
  escribe **como el cliente** (RLS) con la tienda en cada filtro
  (`customerWrite` sólo acepta `customers` y `customer_addresses` y exige el
  `tenant_id`) y responde la página dibujada de nuevo, el mensaje de un campo
  o lo que hay que decir. Así una regla vive en un solo lugar y un teléfono
  lento hace un viaje, no dos (escribir y volver a leer). El cliente y la
  tienda los pone el servidor, nunca el navegador.
- **La contraseña** también pasa por el servidor hacia Supabase Auth con la
  misma sesión (`PUT /auth/v1/user`, `GET /auth/v1/reauthenticate`, `POST
  /auth/v1/logout?scope=others`), sin guardarla ni anotarla. Una vez cambiada,
  lo que falle después sólo pide cerrar las demás sesiones, nunca la
  contraseña de nuevo; el aviso «Quedó pendiente…» queda en
  `sessionStorage` por usuario (Flutter lo tenía en memoria).
- **Un dueño:** `customer_portal_forms.dart` (qué pide cada campo, las
  palabras, qué escribe un guardado), `self_password_rules.dart` (cómo se lee
  un rechazo de Auth) y `customer_address.dart`, `auth_input_validation.dart`
  movidos al núcleo; Flutter usa los mismos. La lectura de un lugar de Google
  (`resolvePlace`) es una sola para el checkout y el portal
  (`places_script.dart`).
- **Arreglado en las dos tiendas:** borrar el RUT o el teléfono ahora los
  borra (antes volvían, porque un campo vacío no se mandaba); un campo
  obligatorio con sólo espacios ya no pasa; las fechas de una dirección se
  escriben en UTC (Flutter las mandaba en hora local sin zona, 3 a 4 h
  corridas); las escrituras de direcciones y del perfil filtran la tienda.
- **Medido contra Flutter** a 1440 y 412 px: perfil, edición, errores, los
  tres pasos de la contraseña, la fila, el menú, el formulario nuevo, editado
  y con errores, borrar y el aviso de abajo, con los bordes en la misma fila
  de píxeles y el texto a ±1 px. 52 comportamientos verificados en los dos
  anchos contra un Supabase falso (guardar y cancelar, cada respuesta de Auth,
  agregar, editar, principal, borrar, Esc, la búsqueda de Maps contestada en
  la prueba, sin llamar a Google, y las carreras de la revisión).
- **Revisión de Codex** (sólo lectura, 5 hallazgos, ninguno de tienda ni de
  sesión, todos corregidos con prueba): una respuesta perdida después de que
  Auth cambió la contraseña dejaba abiertas las demás sesiones (ahora el
  intento siguiente avisa `uncertain` y un «misma contraseña» de Auth cuenta
  como cambiada: sólo se cierran las sesiones); un resultado tardío de Maps
  podía llenar otra dirección (se descarta por número de apertura); un Enter
  durante el cierre del diálogo podía agregar la dirección dos veces (nada se
  manda de un diálogo que se cierra); guardar el perfil borraba el aviso
  pendiente (la acción manda `pending`); un 405 o una lectura fallida antes
  de escribir salían sin `no-store` (ahora con las palabras de Flutter).

Lo que costó, y vale para los formularios que siguen:

- **Una escritura que cruza dos tramos (navegador → servidor → Auth) puede
  haber ocurrido aunque la respuesta se pierda:** el navegador marca el
  resultado como desconocido y el servidor lee el siguiente rechazo con eso
  en mente; nunca se repite una mutación a ciegas.
- **El texto de un campo es el `bodyLarge` del tema (18 px), no 16:** los
  rótulos de la ficha y el texto escrito tienen tamaños distintos. Un campo de
  una línea mide 48 (el mínimo), uno de dos 74, el código de 22 px 53; el
  rótulo descansa a 18 px del borde, y al subir no se corre hacia el lado.
- **El diálogo de Material se ensancha por sus botones** (`IntrinsicWidth`):
  «Verifica que eres tú» mide 514, no 420 + 48, y el contenido se estira con
  él. En CSS: `width: fit-content` con el texto en `contain: inline-size`.
- **El tema del formulario reemplaza los botones de texto del sitio:** en un
  diálogo un `TextButton` lleva el 12 de Material; en la página, el 20 del
  sitio.
- **El texto de ayuda y el de error van en una línea con «…»** (`maxLines`
  nulo con `ellipsis` es una línea en Flutter).
- **El contenido de un diálogo** es 16 px en líneas de 24 y espaciado 0,25;
  el aviso de abajo (`SnackBar`), 16/24 con 24 a los lados y 52 de alto.
- **Un `<dialog>` enfoca su primer campo al abrir** y el rótulo sube; el de
  Flutter abre sin foco. `autofocus` en el `<dialog>` no le basta a Chrome:
  se enfoca el diálogo después de `showModal()`.
- **Skia pinta las letras más finas que Chrome** (la misma fuente y color,
  ~30 % menos tinta): no es el peso; se compara la posición, no el grosor.

### Pendiente

- La búsqueda de Maps en el formulario de una dirección sólo se probó con
  respuestas falsas (para no gastar consultas); en vivo la usa el mismo proxy
  que el checkout.

## Fase 4c: entrar (2026-10-06)

`/cuenta/login` en el servidor (`login_page_view.dart`, `login_page_css.dart`,
`login_page_script.dart`): entrar, crear la cuenta, el aviso «Confirma tu
correo» con «Reenviar correo», Google y el diálogo «Recuperar contraseña»,
con las barras de Flutter. Las palabras y las reglas de cada campo pasaron al
núcleo (`customer_auth_forms.dart`); `CustomerAuthPage` usa las mismas.

- **Supabase Auth se llama desde el navegador, no desde el servidor.** Auth
  cuenta los intentos de entrar y de crear cuenta por dirección IP: pasando
  por Cloud Run, todos los clientes compartirían una y el límite de uno
  bloquearía a todos. Lo que el navegador manda a Auth es lo mismo que manda
  gotrue-dart (mismo cuerpo, mismo `redirect_to`), y lo que recibe queda donde
  lo deja `supabase_flutter`: la sesión en `sb-<ref>-auth-token` como
  `Session.toJson`, y el verificador PKCE en
  `flutter.supabase.auth.token-code-verifier` (JSON, con `/passwordRecovery`
  para una recuperación). Así el enlace del correo y la vuelta de Google, que
  canjea Flutter, lo encuentran.
- **El servidor revisa los campos antes** (`POST /cuenta/accion`, `check`, sin
  sesión) con las reglas del núcleo, y **la contraseña no le llega**: el
  navegador manda su forma (cada mayúscula, minúscula, dígito, espacio o signo
  cambiado por uno de su tipo), que es todo lo que leen las reglas. Con la
  sesión de Auth, `enter` hace lo de `_loadCustomerData`: el alta idempotente
  y el cliente de la tienda; si no puede serlo, la sesión se cierra en Auth
  (`logout?scope=local`) y dice lo de Flutter.
- **Los enlaces que vuelven de Auth son de Flutter.** `code`, `token_hash`,
  `type`, `error`, `access_token` o `enlace` en la dirección: el servidor
  responde la página de Flutter con la cabeza del login
  (`loginIsAuthReturn`). Un enlace que trae el token en el fragmento (el
  puente `auth-action.html` de recuperación e invitación) no llega al
  servidor: un script al principio de la página lo devuelve con `?enlace=1`
  antes de pintar. Al terminar, Flutter vuelve a `/cuenta/login?clave=…` y el
  login HTML dice lo que Flutter decía.
- **Arreglado en las dos tiendas:** el teléfono escrito al crear la cuenta se
  perdía cuando había que confirmar el correo (Flutter sólo lo guardaba si
  Auth daba sesión al registrarse, y en producción nunca la da): 1 de 7
  cuentas. Ahora `enter` y `signIn` lo guardan del `user_metadata` si el
  cliente no tiene teléfono (`customerSignupPhone`). El gris del panel de la
  izquierda llega al fondo de la tarjeta (`IntrinsicHeight`); antes se cortaba
  a la altura de su contenido. `updateProfile` filtra la tienda y escribe UTC.
- **Hosting pisaba el `no-store`.** La regla de cabeceras de `/cuenta/**`
  (`public, max-age=0, must-revalidate`, de cuando todo eso era Flutter)
  reemplaza la del servidor en toda respuesta 200: las páginas del portal y
  las respuestas de `/cuenta/vista` y `/cuenta/accion` salían con ella (un POST
  no se guarda en caché, así que no hubo fuga). Ahora `/cuenta/**` es
  `private, no-cache` y las tres rutas de datos `no-store`.
- **Medido contra Flutter** a 1440, 900 y 412 px: entrar, crear cuenta,
  errores, el aviso de confirmado, «Confirma tu correo» con su barra y el
  diálogo, con los bordes en la misma fila y el texto a ±1 px. 60
  comportamientos en los dos anchos contra un Supabase falso que nunca
  reenvía nada de Auth a producción.
- **Revisión de Codex** (sólo lectura, 4 hallazgos P2, ninguno de
  credenciales, tienda ni redirección): cambiar de modo mientras el servidor
  revisaba podía mandar a Auth un registro sin revisar (ahora se manda lo que
  se revisó y el cambio de modo espera); dos clics en Google podían dejar un
  verificador que no era el de su desafío (uno a la vez); una sesión que no
  puede ser cliente quedaba guardada mientras Auth no contestaba el cierre
  (se olvida al tiro y el cierre va después, con 5 s de tope). El cuarto
  queda como límite conocido de las dos tiendas: gotrue-dart guarda **un**
  verificador, así que empezar otro flujo (Google, recuperar) antes de abrir
  el correo de confirmación hace que ese enlace no se pueda canjear con
  `code`; la cuenta queda confirmada igual y basta entrar con la clave.

Lo que costó, y vale para lo que sigue:

- **El script de la tienda deja fuera los campos vacíos de todo formulario
  GET al enviarse** (para que el catálogo no ponga `?min_price=` en la
  dirección): un formulario del login sin `method` es GET y sus campos vacíos
  quedaban deshabilitados. Un formulario que maneja un script lleva
  `method="post"`. Los del portal no lo sufrían porque llegan después.
- **Una consulta de contenedor no le da estilo al propio contenedor, y mide
  su caja de contenido:** `@container lg (min-width:900px){.lg{…}}` nunca
  aplica (se mueve a un hijo), y con 24 px de relleno a cada lado el ancho de
  Flutter (`LayoutBuilder`, la página entera) es el de la consulta más 48:
  900 de Flutter es `min-width: 852px`.
- **Un ícono en un `flex` se encoge** cuando el texto de al lado es largo
  (`flex-shrink: 1`): la caja de 40 px de los beneficios medía menos y el texto
  partía distinto en el teléfono. `flex: none` en el ícono.
- **Un `TextStyle` suelto en el login hereda `bodyMedium`** del tema de la
  tienda: el cuerpo a 16, alto 1,5 y espaciado 0,25. El tema de la tienda pone
  sus propios tamaños (`headlineSmall` 20 con el alto 1,333 de Material: 27).
- **La barra de Flutter con el color de texto del editor** (negro al 87 %) se
  ve más oscura que ese color sobre blanco (#191919, no #222): su sombra queda
  debajo y se ve a través. En CSS, el color sobre una capa negra al 29 %.
- **El campo del diálogo de Flutter casi no tiene borde** (dos niveles de gris
  sobre el fondo del diálogo, sin explicación en el código del decorador): se
  copia lo medido, el borde mezclado al 25 % con el fondo.

## Fase 4d: los chats se quedan en Flutter (2026-10-06)

Medido en producción el 2026-10-06: el portal tiene 7 conversaciones en toda
su vida y ninguna con mensajes en los últimos 90 días (la última, 22-abr); en
el mismo período WhatsApp tuvo 14 activas de 22. Pasar los chats a HTML
(tiempo real, adjuntos, leídos) no tiene ganancia que medir: quedan en
Flutter, como decía el plan para ese caso. También se quedan
`/cuenta/descargas/android` (la descarga de la app para el personal, con su
propio ingreso) y `/auth/callback`, que además de canjear la vuelta de Google
devuelve al editor su intento de OAuth (`WebsiteEditorOAuthIntentGate`).

Con eso, lo que ve un cliente en vinabike.cl es HTML de punta a punta; Flutter
arranca sólo en esas tres rutas y al canjear un enlace del correo. Lo que
sigue del plan es el lienzo del editor (la sección «El editor» de arriba).

## Fase 5: el lienzo del editor — plan (2026-10-06)

El editor hoy es la tienda Flutter en modo edición (`PublicStoreLayout`,
`WebsiteEditModeProvider`): borradores sin guardar, selección, manillas,
vistas de teléfono y tableta, recuperación de borradores. El requisito 1 del
dueño pide que el lienzo sea el sitio HTML real dentro del ERP. Se hace por
pasos, con el lienzo Flutter como predeterminado hasta que el HTML lo iguale:

- **5a, los bloques que faltan.** El servidor dibuja 8 de los 25 tipos de
  bloque (`homeCoveredBlockTypes`: portada, contacto, carrusel, productos,
  categorías, marcas, video, reseñas). Faltan `canvas` (las campañas con
  capas, el más grande), `text`, `button`, `divider`, `services`, `about`,
  `testimonials`, `features`, `cta`, `gallery`, `faq`, `pricing`, `team`,
  `stats`, `footer` y `partnersBanner`. Hoy una página con uno de ellos la
  responde Flutter entera (`_flutterFallback`), así que el sitio nunca pierde
  un bloque; cada tipo nuevo se mide contra Flutter con una página de prueba
  servida por un Supabase falso (nada se escribe en producción para medir).
  **Corrección del dueño, 2026-10-06:** la paridad a píxel vale para lo que
  ya se ve en línea; un tipo que ninguna página publicada usa no se copia
  con el aspecto viejo de Flutter: se rediseña primero en un lienzo de Claude
  Design con datos reales, se le presenta al dueño y, aprobado, se construye
  en los dos dueños (widget de Flutter y HTML) para que el editor y el sitio
  sigan iguales.
- **5b, dibujar un borrador.** Una ruta del servidor sólo para el personal
  recibe el documento en edición (bloques y ajustes del tema, sin guardar) con
  la sesión del ERP, comprueba que es personal de la tienda leyendo como ella
  (RLS) y lo dibuja con los mismos componentes que la página pública;
  `no-store`, `noindex` y sin dejarse enmarcar fuera del ERP.
- **5c, «Vista HTML» en el editor.** Un visor web en la barra del editor
  (WKWebView en macOS, WebView en Android, WebView2 en Windows, un iframe en
  el ERP web; el ERP ya los usa en `webview_module_page.dart`) que muestra esa
  página y se redibuja con cada cambio del panel. El lienzo Flutter sigue
  siendo el de editar.
- **5d, editar sobre el HTML.** Cada bloque lleva su id; un clic en el visor
  avisa al panel, que lo selecciona; después las manillas y lo demás. Cuando
  el HTML iguala al lienzo Flutter en todos los bloques, pasa a ser el
  predeterminado y se retiran los renderizadores Flutter que nadie usa.

### 5a, primera tanda: `/pagina/<slug>`, texto, botón y separador (2026-10-06)

- **La ruta.** `/pagina/<slug>` (`DynamicWebsitePage`) la responde el
  servidor: la misma lectura que la portada con `slug=eq.<slug>`, sus bloques
  compuestos al ancho de la ventana (las bandas de la portada) y bajo el
  encabezado fijo (sólo el de la portada flota). Título, descripción, imagen,
  canónica y `robots` como `_scheduleSeoUpdate` (indexable sólo con algo que
  leer). Una que no existe es el 404 del servidor; con mayúsculas, 301 a la
  de minúsculas (Flutter lee el slug en minúsculas); sin bloques, «Esta
  página está en construcción» con `noindex`. Hoy no hay ninguna publicada:
  la ruta es también el banco de medición de los bloques.
- **Cómo se mide sin escribir en producción.** Flutter: `vinabike.cl/pagina/
  prueba-bloques` (Hosting sirve Flutter en `/pagina/**` hasta este cambio)
  con Playwright respondiendo `website_pages?…slug=eq.prueba-bloques` desde un
  archivo (objeto si el `Accept` pide `vnd.pgrst.object`, lista si no). HTML:
  el servidor local contra un Supabase falso que responde lo mismo y pasa lo
  demás a producción como visitante. Las mismas cajas de texto y botón a 1440,
  800 y 412 (todas exactas), las capturas lado a lado y el color bajo el
  puntero.
- **Texto, botón y separador.** Los tres miden igual que Flutter en los tres
  anchos. El botón con borde bajo el puntero, igual en color y escala.
- **Un bloque con superficie propia queda en Flutter.** El HTML no pinta
  todavía fondo, borde, sombra ni relleno de bloque
  (`WebsiteBlockSurface`); antes de esta tanda los ignoraba en silencio en
  cualquier bloque de la portada. Ahora `websiteBlockHasAuthoredSurface`
  (núcleo, con prueba de que sus claves son las de
  `WebsiteBlockSurfaceFields`) hace que esa página la responda Flutter
  entera. En producción ningún bloque tiene superficie (2026-10-06).

Lo que costó, y vale para lo que sigue:

- **`WebsiteBlockSurface` envuelve cada bloque en un `Container` de ancho
  infinito:** el hijo recibe el ancho entero como restricción fija. Por eso
  el botón suelto ocupa todo el ancho del bloque (no se centra a su medida) y
  un texto sin `maxWidth` es una caja de todo el ancho alineada a la
  izquierda; con `maxWidth` es una columna centrada de ese ancho. Todo bloque
  del renderizador se dibuja `fill`.
- **El texto del editor lleva `maxWidth: 800` por defecto** (la
  normalización pone los valores del tipo debajo de lo guardado); sólo un
  `null` guardado lo quita.
- **Jaspr sangra cada línea de un `RawText`:** un texto con saltos dentro de
  `white-space: pre-wrap` mostraba la sangría del HTML. El texto se escribe
  entero con sus saltos como `&#10;`.
- **Los estilos de Flutter heredan lo que el tema no dice:** el párrafo es
  `bodyLarge` con el tamaño del tema, alto 1,5 y espaciado 0,5 de Material 3;
  el subtítulo `titleLarge` a 18 con el alto 28/22; el título
  `headlineMedium` con el tamaño de títulos del tema y el alto 36/28; la
  etiqueta del botón, el cuerpo a su tamaño con el alto 20/14 y el espaciado
  0,1 de `labelLarge`.
- **Un color de separador `#AARRGGBB` lleva el alfa primero** (como lo lee
  Flutter), al revés que el `#RRGGBBAA` de CSS.
- **La sombra de `ElevatedButton`** (elevación 1, y 3 bajo el puntero) se
  ajustó midiendo filas de píxeles: `0 .7px 1px` al 18 % más un halo de 1 px,
  y `0 2px 3px` al 18 % con `0 1px 5px` al 8 %.
- **La tinta del texto es más oscura en Chrome que en CanvasKit** (≈1,5×,
  mismo tamaño y posición): es el rasterizador, igual en todas las páginas ya
  migradas; no se compensa con CSS.
- **Un texto vacío y un salto final son líneas en Flutter** (24 px cada una
  en el párrafo); en CSS un `<p>` vacío mide 0 y un salto final no agrega
  línea. Un espacio de ancho cero (`:empty::before`, `[data-break]::after`)
  los iguala; medido con una segunda página de prueba.
- **El trazo que imita la negrita es de Oswald, no de «los títulos»:**
  Flutter dibuja Oswald (un archivo variable) en su instancia regular y lo
  engrosa desde 600; Barlow tiene un archivo por peso y dibuja el pedido.
  El peso se decide por la familia que se dibuja
  (`storefrontFontDrawsRegularOnly`), también cuando el editor cambia la
  fuente de un texto (revisión de Codex).
- **Un enlace del editor se escribe como lo navega Flutter**
  (`navigateToHref`): una URL `http(s)` absoluta sale de la tienda, un
  `mailto:` o `tel:` abre la app del visitante, y cualquier otro valor, con
  o sin esquema, es una ruta dentro de ella (`WebsiteDestination.parse`). El
  HTML escribía el valor guardado tal cual; desde la revisión de Codex
  escribe el destino normalizado en todos los bloques. Flutter convertía
  también `mailto:` y `tel:` en una ruta; ahora los abre, en las dos copias
  de `navigateToHref`. Los enlaces de la portada y las páginas en vivo
  quedaron iguales (comparados uno a uno).

### 5a, segunda tanda: preguntas, llamado a la acción, características y «sobre nosotros» (2026-10-06)

Los cuatro bloques de contenido más usados (`faq`, `cta`, `features`,
`about`) los dibuja el servidor en la portada y en `/pagina/<slug>`, medidos
con una tercera página de prueba (dos de cada uno, con y sin foto, rejilla y
lista, pregunta larga): las mismas cajas que Flutter a 1440, 800 y 412, la
pregunta abierta con su respuesta en la misma fila y el tono bajo el
puntero. Las páginas de información siguen leyéndolos como secciones de
texto, como `StaticPolicyPage`. Lo que costó:

- **Cada bloque decide sus tamaños por un ancho distinto:** las preguntas y
  las características por su columna útil (el bloque menos su relleno, hasta
  900 y 1100), «sobre nosotros» por el ancho del bloque entero (900 y 600).
  Con `container-type` en la columna correspondiente las consultas leen lo
  mismo que cada `LayoutBuilder`.
- **Un `TextStyle` suelto hereda el espaciado 0,25 de `bodyMedium`** también
  en los títulos de Oswald de estos bloques: sin él los anchos no calzan.
- **El degradado del llamado a la acción va de esquina a esquina en
  Flutter** (`Alignment.topLeft` a `bottomRight`, líneas de igual color
  perpendiculares a la diagonal); el `to bottom right` de CSS sólo coincide
  en un cuadrado y en una franja ancha se ve casi vertical. Un script de la
  página da a cada bloque el ángulo de su diagonal (`180° − atan2(ancho,
  alto)`), y lo actualiza al cambiar de tamaño; sin script queda el de CSS.
- **El tono de una fila bajo el puntero es el `hoverColor` del tema** (negro
  al 4 %), no el 8 % de `onSurface` de Material 3: medido sobre la tarjeta.
- **La tarjeta de Material 3 (elevación 1, sombra del tema al 14 %)** se
  ajustó por filas de píxeles: `0 2px 3.5px -1px` al 5 % más un halo de 1 px.
- **La fila de una pregunta mide al menos 54** y deja 9 arriba y abajo de una
  pregunta de varias líneas (medido: una de tres líneas mide 90). Abre con
  `<details>`: funciona sin script y con teclado, y anima su alto donde el
  navegador lo permite (`::details-content`).

### 5a, tercera tanda: en pausa hasta aprobar el diseño (2026-10-06)

Cifras, testimonios, equipo, planes, galería, servicios, banner de partners
y el espacio del bloque de pie quedaron dibujados en HTML a píxel de Flutter
(cajas idénticas a 1440, 800 y 412; diferencia media bajo 1/255) y **no se
publicaron**: al ver las capturas el dueño rechazó el aspecto («HORRIBLE
designs… why aren't you using design sync to create them and present that
to me?»). Ninguna página publicada usa esos tipos (las cinco con bloques
usan portada, «sobre nosotros», características, preguntas y contacto), así
que no había nada en línea que conservar. Costó unas dos horas de medición
que no se van a usar tal cual. La propuesta nueva, con los precios, reseñas
y cifras reales, está en el lienzo «Bloques del sitio Viñabike»
(https://claude.ai/artifact/Eg75Q9vj2oZYWKiyGFDCHU) y espera su visto bueno.

Lo que la medición enseñó y sirve para cualquier paridad que quede:

- **Chrome dibuja un borde de 1,5 px como 1 px** (redondea el ancho a
  píxeles del dispositivo) y cada tarjeta perdía un píxel de alto; una sombra
  interior `inset 0 0 0 1.5px` sí se dibuja fraccionaria y no ocupa espacio,
  igual que el borde de Flutter dentro del relleno.
- **`theme.dividerColor` es negro** en la tienda, venga lo que venga del
  editor: sale del tema base de `PublicStoreTheme` (su `ColorScheme.light`
  sin `outlineVariant`) y `WebsiteThemeBuilder` no lo cambia.
- **Las `Card` sin margen propio llevan 8** (el tema base) dentro del ancho
  que Flutter les da; la sombra al 14 % medida por elevación: 1 = `0 1px 2px
  -1px` al 8 %, 2 = `0 2px 3.5px -1px` al 4,5 %, 4 = `0 4px 9px -3px` al
  5,5 %, cada una con un halo de 1–2 px.
- **Una tarjeta translúcida deja ver la sombra que Flutter pinta bajo ella**
  (`drawShadow` con oclusor transparente): el plan destacado se ve 3,6 % más
  oscuro adentro, menos junto al borde de arriba.
- **El banner de partners sólo tiene altura mínima** (su perfil no es
  `exact`): la rama de alto fijo de `_buildPartnersBanner` no se alcanza en
  una página pública.
- **Un plan sin botón muestra «Seleccionar» a `/productos`**: lo agrega la
  normalización (`syncNestedActions`), no el widget.

### 5b y 5c: la vista HTML del borrador (2026-10-07)

- **5b, el servidor dibuja el borrador.** `POST /_html/editor/borrador`
  (`editor_draft_route.dart`) recibe la portada o una página del editor con
  sus bloques y los ajustes sin guardar, y la dibuja con los mismos
  componentes de la página pública (`HomePageModel`/`EditorPageModel` con
  `draft: true`). Sólo para quien puede guardar el sitio: el servidor pregunta
  `can_edit_tenant_settings` con la sesión del ERP (Supabase rechaza una firma
  falsa: «expired»). Sin caché, sin índice y sin medición (la página es
  `hidden`). Cada bloque lleva `data-block-id`; uno que el HTML aún no dibuja
  aparece como aviso en su lugar («La vista HTML todavía no dibuja este
  bloque»), en vez de mandar la página entera a Flutter como hace la ruta
  pública. CORS sólo para el ERP web (`project-vinabike.web.app` y
  `.firebaseapp.com`); el ERP nativo no manda origen.
- **5c, «Vista HTML» en el editor.** `WebsiteHtmlDraftView` se monta sobre el
  lienzo (que queda montado debajo), pide el borrador 350 ms después de cada
  cambio del panel, conserva el desplazamiento al redibujar, marca la sección
  elegida y un clic en la página la elige en el panel
  (`window.flutter_inappwebview.callHandler('vbDraftPick')` →
  `selectBlock`). Enlaces y formularios no hacen nada, como en el lienzo. El
  interruptor está en la barra desde 1540 px (medido) y siempre en «Más
  acciones › Vista». Probado en macOS contra producción: portada, sección
  elegida por clic, título cambiado en el panel y visto en HTML en ~2 s,
  Tablet y Móvil.
- **Lo que falta del 5c:** las plantillas del catálogo y de la ficha de
  producto (hoy dicen que la vista HTML no las dibuja todavía); medir el zoom
  en Windows; en el ERP web el clic llega por `postMessage` y falta
  escucharlo.
