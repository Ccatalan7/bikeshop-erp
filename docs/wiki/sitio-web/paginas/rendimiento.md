---
titulo: Rendimiento y carga
resumen: cuánto pesa y tarda la tienda, la página instantánea que muestra contenido antes de Flutter, el borde, las imágenes y cómo se mide contra las Core Web Vitals
fuentes: [web-dev, flutter-web, repositorio, consolas-google]
archivos: [services/storefront_html/lib/src/public_reads.dart, services/storefront_html/lib/src/search_overlay_view.dart, services/storefront_html/deploy_cloud_run.sh, scripts/fonts/subset_storefront_fonts.sh, services/storefront_html/lib/src/storefront_fonts.dart, scripts/generate_public_image_thumbnails.dart, docs/architecture/storefront-instant-page.md, docs/architecture/storefront-html-migration-plan.md, services/storefront_html/tool/measure.mjs, scripts/storefront_instant_page/instant_page.js, scripts/storefront_instant_page/instant_page.css, web/index.html, cloudflare-worker/src/index.js, scripts/check_storefront_bundle_budget.sh, supabase/functions/website-optimize-image/index.ts]
tablas: [website_settings, website_blocks, public_image_thumbnails, catalog_search_documents]
revisado: 2026-10-31
---

# Rendimiento y carga

## Lo esencial

La tienda Flutter baja ~1,3 MB de `main.dart.js` y ~1,6 MB de CanvasKit antes de
dibujar. En un móvil lento (1,6 Mbps, 150 ms, CPU ×4) eso es **~20 s hasta
«tienda lista»** (2026-09-24) `[Repo: storefront-instant-page.md]`. Sin más, el
visitante vería sólo el logo todo ese tiempo y Google mediría el logo como LCP.

## La vara (Core Web Vitals)

| Métrica | Bueno | Malo |
|---|---|---|
| LCP (carga) | ≤ 2,5 s | > 4 s |
| INP (respuesta) | ≤ 200 ms | > 500 ms |
| CLS (estabilidad) | ≤ 0,1 | > 0,25 |

Se juzga el percentil 75 de usuarios reales, móvil y escritorio por separado; el
laboratorio (Lighthouse) es una simulación y no mide INP `[WD]`.

## Página instantánea (2026-09-24)

El HTML que el build ya escribe para cada ruta se pinta **antes** de Flutter, con
los colores y la fuente del tema; Flutter lo retira cuando dibujó su versión. Es
un consumidor de los mismos dueños, nunca otro CMS `[Repo]`.

- Rutas: fichas `/productos/<slug>/<sku>`, categorías y la portada (cuando su
  primer bloque es un carrusel que dibuja igual). El catálogo raíz y el resto
  siguen sólo con Flutter.
- Medición local, móvil lento, mediana de 3 cargas: el primer contenido pasa de
  0,4 s (logo) a **0,27 s** (ficha) / 0,26 s (categoría) / 0,29 s (portada); la
  tienda queda lista igual (~20–22 s) `[Repo]`.
- El logo del encabezado pasó de un PNG de 104 KB a un WebP de 15 KB.

## Lo que se midió en vivo

- PageSpeed móvil de la portada: 26 (LCP 16,8 s) antes de todo; 62 con la
  instantánea de fichas; **38** con la portada instantánea, porque Lighthouse contó
  como previo al LCP lo que terminó de bajar antes (LCP simulado 18,2 s con la
  foto pintada a 1,3 s en la traza) `[Consola 2026-09-24]`.
- Ajuste (`data-ip-lcp`, sin precarga de `main.dart.js`, Flutter espera la foto
  hasta 3 s): foto 3,0 → 1,9 s; tienda lista 20,0 → 20,8 s. Clicable a 4,3 s en
  wifi y 7,8 s en 4G normal `[Prod 2026-09-24]`.
- PageSpeed final sin medir (la API respondió 429).

**Decisión del dueño (2026-09-24):** no rehacer las páginas como HTML todavía
`[Dueño]`. La tarea programada `vinabike-store-ready-review` (8-oct, 10:00 local)
lee `store_ready` en GA4 por tramo de carga y recomienda.

**Ficha en HTML (2026-10-04):** la misma ficha (`H911`) servida como HTML desde
un servidor Dart de prueba (retirado; hoy `services/storefront_html/`), medida con el
mismo método: usable a los **2,6 s** contra 23,9 s, **342 KB** contra 4.384 KB,
389 palabras y 67 enlaces sin JavaScript. Pierde en primer byte (0,78 s contra
0,12 s) porque corre en un Mac en Chile y lee la base en São Paulo en cada
visita, sin CDN. Plan y fases en `docs/architecture/storefront-html-migration-plan.md`
`[Repo 2026-10-04]`.

**Fase 0 (2026-10-04):** el servidor `services/storefront_html/` reemplaza a la
prueba y mide lo mismo en local (usable a los 2,6 s, 362 KB). Por dentro, en
producción y como `anon`: `get_public_product_page_v1` tarda **281 ms**, y
**~275 ms** de eso es `get_public_product_technical_specs`, que valida la ficha
técnica en cada lectura (`spec_validate_draft_internal_v1`); la tienda Flutter
paga lo mismo hoy en una llamada aparte. `get_public_storefront_shell_v1` tarda
5 ms (86 KB). Armar la página con Jaspr compilado (AOT) tarda 5–7 ms. La ficha
técnica precalculada es requisito de la fase 1 `[Prod 2026-10-04]`.

**En vivo por `vinabike.cl/_html/` (2026-10-04, Cloud Run en São Paulo):**
usable a los 2,6 s contra 24,1 s de la ficha Flutter, 338 KB contra 4.384 KB,
foto principal 2,64 s contra 1,58 s y primer byte 0,90 s contra 0,14 s. El
primer byte lo fija la lectura (~300 ms, la ficha técnica), no la distancia
`[Prod 2026-10-04]`.

**Despertar el servidor** (2026-10-05, `min-instances 0`, tras 20 min sin
visitas): la primera visita queda usable a los 3,0 s contra 2,5 s con el
servidor despierto (primer byte 1,29 s contra 0,83 s, celular lento). El
binario nativo arranca en ~0,15 s; el resto es la primera lectura
`[Prod 2026-10-05]`.

**Fase 1, catálogo y categorías en HTML** (2026-10-05, por `/_html/`, celular
lento, mediana de 3): ficha LCP **1,13 s** (primer byte 0,76 s; la lectura de la
ficha bajó a 108–145 ms con la ficha técnica en una pasada); categoría
`camaras` LCP **1,6–1,9 s**; `/productos` LCP **4,4 s** y `componentes` **4,2 s**,
contra la categoría Flutter usable a los **22,2 s** con 4.012 KB. Lo que frena
el catálogo son las fotos de tarjeta de 1.200 px (75–120 KB cada una, ~690 KB
por página): el teléfono baja ~16 a la vez porque Chrome carga lo `lazy` hasta
2.500 px por debajo con una conexión lenta `[Prod 2026-10-05]`. **Con las
copias de 400/800 px** (ver «Imágenes»), ya en las rutas públicas: `/productos`
LCP **2,0 s** (409 KB), `componentes` **2,1 s**, `camaras` **1,6 s**, `frenos`
**2,0 s** y una ficha **2,2 s**, todas bajo 2,5 s `[Prod 2026-10-05]`. Detalle en
`docs/architecture/storefront-html-migration-plan.md` («Miniaturas de
tarjeta»).

**Todo lo público en HTML, en vivo** (2026-10-06, `66865dc3`, celular lento:
CPU ×4, 1,6 Mbps, 150 ms, sin caché; «se lee» = el mayor pintado): portada
**2,8 s** (474 KB), `/productos` **2,1 s** (366 KB), una ficha **2,4 s**
(395 KB), `componentes` **2,0 s**, `/carrito` **0,8 s** (125 KB), `/contacto`
**1,0 s**. `/cuenta/login`, que era lo último en Flutter, quedaba usable a los
**20,5 s** con 3.649 KB `[Prod 2026-10-06]`; en HTML (fase 4c) se lee a los
**0,8–0,9 s** con 215 KB `[Prod 2026-10-06, 32336525]`.

**El portal en HTML** (fase 4a, 2026-10-06, `3e4ae449`, el mismo celular lento):
el marco de `/cuenta` con su puerta se lee a los **1,6 s** en vivo, contra
**18,4 s** de Flutter; con sesión, la cuenta completa (resumen, pedidos, taller y
bicis, leídos como el cliente por `POST /cuenta/vista`) a los **1,8 s** en local
con datos reales anonimizados `[Prod 2026-10-06]` `[Repo 2026-10-06]`.

- La página HTML viajaba sin comprimir (64 KB): ni Cloud Run ni Firebase
  Hosting comprimen una respuesta reenviada. El servidor la manda en gzip
  (15 KB) `[Prod 2026-10-05]`.
- Las fuentes sí pesaban (corrige lo que decía esta línea): Hosting manda
  los TTF en brotli (Barlow 104 → 43 KB), pero la portada pide seis antes de
  su foto principal y comparten el ancho de banda con ella. Un WOFF2 con el
  rango latino pesa 21 KB (Oswald 28 contra 91): la foto principal de la
  portada HTML bajó de 4,8 a 3,7 s en el teléfono lento, con el mismo texto
  al píxel `[Repo 2026-10-05]`. El TTF completo queda detrás para cualquier
  otro carácter, y como segunda fuente si falta el WOFF2.
- El catálogo leía ~450–700 ms: `get_public_product_facets_v2` ~410 ms en la
  base, de eso ~270 ms en `spec_public_facet_values_internal_v1` (valores
  técnicos de todo el catálogo, en cada visita) y ~190 ms en el universo de
  `get_public_products` `[Prod 2026-10-05]`. Desde `20261007020000` los
  filtros calculan los valores técnicos sólo de las categorías pedidas y el
  listado no normaliza texto sin búsqueda. Medido en la base, sin cambiar
  ninguna respuesta (13 listados y 7 filtros comparados fila a fila con la
  versión anterior): filtros de `/productos` 391 → ~120 ms, de una categoría
  399 → ~65 ms, listado de una página ~130 → ~20–50 ms; una página de
  categoría completa son ~100–150 ms de base `[Prod 2026-10-07]`.
- **Muchas visitas a la vez** (2026-10-07): doce páginas de categoría
  simultáneas daban 503 en 8 de 12 (antes de `20261007020000`) y todavía en 5
  de 12 en una de tres ráfagas después: el servidor mandaba unas ochenta
  consultas juntas a la base, cada una tardaba ~10 veces más y las que
  pasaban los 3 s de `anon` se cortaban. El servidor ahora deja pasar cuatro
  a la vez por instancia (`DatabaseGate`) y las demás esperan su turno en el
  servidor `[Prod 2026-10-07]`.

**El buscador (2026-10-25):** una sugerencia tardaba 1,3–2,0 s. En la base,
«cadena» costaba 585 ms contra 78 ms sin término: el 90 % era rehacer en cada
tecla lo mismo para los 1.183 productos (normalizar textos 200 ms, la ficha
como texto 130 ms, partirlo en palabras contra el vocabulario 150 ms). Con los
documentos de búsqueda, ~130 ms; en vivo 0,67–1,0 s por tecla. Con la 1.0.41
(caja directa a Cloud Run) y la huella incrustada (`20261025060000`): el
servidor tarda 140–240 ms por sugerencia (2 ms sin base), la lista de
productos 101–107 ms y los filtros 119 ms en la base; desde el Mac del dueño
(Seattle) 0,35–0,49 s por tecla, de los que ~200 ms son el viaje
`[Prod 2026-10-25]`. Detalle en [catálogo](catalogo-y-fichas.md).

**El buscador con la base ocupada (2026-10-29).** El dueño: «la búsqueda a
veces sigue bastante bumpy». En vivo:
- una búsqueda de cada seis respondía 503, y el 10 % más lento pasaba de 15 s;
- buscando de a una, 40 búsquedas tomaron 230 s, 5,7 s cada una;
- de esas 40, 4 fallaron y 6 llegaron sin categorías o sin el conteo de
  agotados. «casco» decía «No encontramos» en vez de ofrecer los 11 agotados.

Cada consulta sola tarda ~100 ms en la base. Pero la base es Micro (1 GB, CPU
compartida, 60 conexiones), y con poca carga junta se satura: una persona
escribiendo, unos robots, el ERP y Realtime. Las consultas de `anon` pasan los
3 s y se cortan: 88 cortes entre las 21:16 y las 22:33 UTC. pg_cron ni siquiera
arranca sus tareas: 15 «job startup timeout» en el día.

Tres cosas del buscador lo empeoraban:
1. Desde la 1.0.41 la caja pregunta directo a Cloud Run, así que nada
   guardaba las respuestas entre visitas, aunque la respuesta lo permite
   (`s-maxage=300`). Cada tecla de cada visita leía la base 4 o 5 veces.
2. El conteo de agotados volvía a pedir los filtros de categoría, la lectura
   más pesada, sin usarlos.
3. Una respuesta fallida dejaba la caja como estaba, sin reintentar ni avisar.

El arreglo va en el registro `website-search-understands-customers` (1.0.42):
- el servidor guarda cada respuesta 5 min (`_keptSearchAnswer`); una
  incompleta o fallida no se guarda;
- el conteo de agotados no pide filtros;
- la caja dice «Buscando «…»», reintenta una vez a los 0,7 s y, si no puede,
  muestra «No pudimos buscar» con «Reintentar».

Contra la misma base, las mismas 40 búsquedas dieron 1 error y 0 incompletas,
con los mismos productos y totales. Una búsqueda repetida responde en 1–3 ms
`[Prod 2026-10-29]`. Lo de fondo sigue pendiente: el tamaño de la base
([pendientes](estado-y-pendientes.md)).

**Lo que pedía cada letra (2026-10-29, segundo paso).** Ya publicado lo
anterior, en vivo «camara» seguía tardando 5–8 s, y 5 búsquedas seguidas
dieron 503. Cada letra hacía 9–14 llamadas a la base:
- el listado, más 3 para completarlo (identidad, marcas, fotos);
- los filtros completos del catálogo, sólo para contar categorías: ~14.400
  bloques para «camara». Es la consulta registrada que más se desborda a
  disco: ~10 GB de archivos temporales desde el 30 de agosto en
  `pg_stat_statements`;
- los servicios, la corrección y el conteo de agotados, que también
  completaba su única fila con 3 llamadas.

Ahora las categorías salen de `get_public_search_category_counts_v1`
(~5.600 bloques, el mismo universo que el filtro: 96 filas iguales en 8
búsquedas), y el conteo de agotados no completa filas
(`CatalogRequest.complete`). Las mismas 40 búsquedas dan respuestas idénticas
línea por línea `[Prod 2026-10-29]`.

## Borde y datos

- **El armazón viaja sólo cuando cambió (2026-10-31).** Cada página leía el
  armazón entero (`get_public_storefront_shell_v1`: menús, categorías, ajustes
  públicos, tramos de despacho; ~200 kB, ~37 kB comprimido) y los rastreadores
  piden ~4.400 páginas al día: ~0,16 GB diarios, la mayor parte del tráfico de
  Supabase de la tienda `[Prod 2026-10-31]`. Ahora el servidor guarda el último
  armazón con su huella (md5) y, como mucho cada 15 s, pregunta a
  `get_public_storefront_shell_if_changed_v1(p_tenant_id, p_known_stamp)`:
  con la huella vigente la respuesta es sólo `{stamp}` (unas decenas de bytes).
  Un cambio en el editor llega a las páginas en ≤ 15 s. Los medios de pago del
  pie (`get_public_checkout_capabilities`) quedan un minuto. Cada página
  decodifica su propia copia del texto: ninguna comparte filas con otra
  `[Repo 2026-10-31]`.
- `web/index.html` precarga `get_public_store_data` desde el Worker de Cloudflare
  `vinabike-edge-cache` (caché 5 min por región): ~50 ms en caché frente a
  ~700 ms a Supabase `[Repo: cloudflare-worker/README.md]`.
- La tienda además llama la función directo aunque acepte la precarga (no
  investigado, 2026-09-24).

## Imágenes

- **Fotos de tarjeta en su tamaño (2026-10-05).** Cada foto de tarjeta pública
  tiene copias de 400 y 800 px (`public_image_thumbnails`, las hace
  `scripts/generate_public_image_thumbnails.dart` en cada publicación de la
  tienda) y las tarjetas HTML las ofrecen en `srcset` con `sizes` según la
  grilla; la precarga de la primera tarjeta lleva los mismos candidatos. En 40
  fotos al azar: 120 KB la original, 19,6 KB la de 400 px, 64 KB la de 800 px
  `[Prod 2026-10-05]`. La tienda Flutter todavía baja la de 1.200 px.
- **«Productos destacados» mostraba la foto original** (`product.imageUrl`),
  no la optimizada de la que salen las copias: en la portada, una captura de
  pantalla en PNG de 267 KB compitiendo con la foto principal en el teléfono
  lento. Desde el 2026-10-05 el bloque usa `publicProductPrimaryImageUrl`
  (la misma primera foto que el catálogo) en el servidor y en el editor: las
  dos primeras tarjetas bajaron de 308 a 47 KB en un teléfono `[Prod 2026-10-05]`.
- **Medido en vivo tras publicar las dos cosas** (teléfono lento: CPU ×4,
  1,6 Mbps, 150 ms; caché fría; 2026-10-05, release `8399d0fd`): portada
  texto 0,9 s, foto principal 2,7 s (antes 4,0), carga completa 2,8 s (antes
  5,2); `/contacto` 0,7 s; `/servicios` 1,4 s `[Prod 2026-10-05]`. La portada
  Flutter tardaba ~20 s en su primer cuadro.
- El editor guarda una versión web optimizada (`website-optimize-image`) y, al
  elegir una imagen vieja de la biblioteca, la optimiza (`<nombre>-src<hash>-<uuid>-web.webp`,
  reutilizada si ya existe; WebP > 300 KB también) `[Repo]`.
- Carrusel: la diapositiva 1 pasó de PNG 1 MB a WebP 59 KB; la foto de la portada
  de JPEG 168 KB a WebP 82 KB. La campaña de cámaras (diapositiva 3) pasó de
  PNG 2.085 KB a WebP 118 KB, elegida otra vez en la biblioteca del editor,
  que la optimiza al usarla (2026-10-06). Ninguna imagen que baja la portada
  pasa de ~120 KB `[Prod 2026-10-06]`.
- La biblioteca no lista `.avif` (`listAssets`).

## Presupuesto del bundle

El build falla si `main.dart.js` y compañía pasan 7,3 MB crudos o 1,95 MB gzip
(`check_storefront_bundle_budget.sh`). Es el freno para que el peso no crezca
sin que nadie lo decida.

También limita lo que se carga aparte (los fragmentos `deferred`: 3,6 MB en
total, 1,6 MB el más grande). **El 2026-10-10 la tienda dejó de publicarse**
con la 1.0.20: el fragmento del ERP que el editor carga pasó de 1,41 a 2,09 MB
porque el catálogo nuevo envolvía su página en `WebsiteAdminShell`, y ese
marco trae el `MainLayout` del ERP entero (mensajería, avisos, correo), aunque
el editor sólo usaba la versión sin marco. Se separó: el editor usa
`WebsiteCatalogWorkspace` y sólo la ruta del ERP usa `WebsiteCatalogPage` con
el marco; quedó en 1,43 MB y el principal bajó 200 KB. Lo que el editor de la
tienda importa no puede tocar `website_admin_ui.dart` ni `main_layout.dart`;
se mide con `flutter build web --release -t lib/main_store.dart` y el script,
igual que CI, antes de subir.

## Trampas

- Saltarse el relevo de Hosting para ganar el viaje también se salta su caché
  compartida. Desde el 2026-10-25 nada guardaba las sugerencias entre visitas,
  aunque decían `s-maxage=300`, y cada tecla de cada visita fue a la base.
  Se vio el 2026-10-29, con una búsqueda de cada seis en 503. Lo que guardaba
  el borde, ahora lo guarda el servidor.
- En la consola del navegador, un 503 del buscador aparecía como error de
  CORS («No 'Access-Control-Allow-Origin' header»). La caja lee `/buscar`
  desde otro origen, y la respuesta de error salía sin el permiso, así que el
  navegador escondía el código. Desde el 2026-10-29 el 503 de `/buscar` lleva
  el permiso. Ante un error de CORS en la caja, se buscan los 503 en los
  registros de Cloud Run antes de revisar la configuración del permiso.
- Medir una consulta sola no dice cómo se porta en la tienda. En la base Micro
  una búsqueda tarda ~100 ms a solas y pasa de 3 s con poca carga junta. Se
  mide con la batería de cliente (`customer_search_battery.py --workers 1`) y
  se leen los `postgres_logs` («canceling statement due to statement timeout»).
- Juzgar con un solo número de PageSpeed: varía entre corridas y es laboratorio.
- `pagespeed.web.dev` no termina en una pestaña de fondo ni en el navegador
  integrado con el panel oculto.
- Un `<canvas>` no cuenta como LCP: el LCP de una página Flutter pura es el logo
  o la imagen HTML que haya.
- Precargar `main.dart.js` compite con la foto del LCP.
- Creer que `fetchpriority="low"` en las fotos de abajo deja pasar a la del LCP:
  con fotos de 100 KB igual se reparten el ancho de banda (medido 2026-10-05,
  sin cambio apreciable). El arreglo es el tamaño, no la prioridad.
- Una regla SQL que se aplica a cada fila tiene que poder **incrustarse**: una
  función `language sql` sin `security definer`, sin `set` y **sin
  subconsultas** (`exists`, `in (select …)`) el planificador la pega dentro de
  la consulta; con una sola subconsulta se llama fila por fila. La regla de
  venta (2026-10-10) llevaba un `exists` para la categoría y **duplicó el
  listado público** (~50 → ~110 ms). Se movió esa pregunta a su propia
  función y volvió a ~51 ms (`20261010020000`). Medir con `EXPLAIN (ANALYZE)`
  antes y después de tocar una función que usan las lecturas públicas.
  **Tampoco se incrusta** una función `immutable` cuyo cuerpo llama algo
  `stable` (`concat_ws` lo es): la huella de los documentos de búsqueda
  (`catalog_search_source_md5_v1`, `20261025040000`) era `immutable` y con
  `set search_path`, y costaba 44 ms por lectura contra 6,7 ms escrita en
  línea, en **toda** lectura del catálogo, con término o sin él: el catálogo
  sin término subió de ~78 a ~110 ms ese mismo día y nadie lo midió hasta
  la tarde. `20261025060000` la deja `stable` y sin `set` (60–78 ms). Se
  comprueba en `pg_proc` (`provolatile = 's'`, `proconfig is null`) y con la
  prueba pgTAP del dueño de la función `[Prod 2026-10-25]`.
- Declarar el TTF completo para «todo lo que no es latino»: el navegador lo
  baja para cualquier carácter de ese rango aunque el archivo no lo tenga. Un
  emoji en una reseña de Google (👌, ✨) hacía bajar `Barlow-Regular.ttf`
  (102 KB) en cada portada para nada; desde el 2026-10-24 cada familia
  declara sólo lo que su `cmap` trae (`storefrontFullFontRanges`) y
  `storefront_fonts_test.dart` lee los TTF y falla si algo queda fuera.
  Se encuentra listando los caracteres visibles fuera del rango latino de la
  página (`TreeWalker` sobre el texto) `[Prod 2026-10-24]`.
- Llamar una función SQL grande «por si acaso»: Postgres la **planifica en
  cada llamada**, aunque reciba un arreglo vacío. La que arma los documentos
  (~300 líneas) costaba ~150 ms sin hacer nada; se llama con
  `cross join lateral … where cardinality(ids) > 0` y no corre si no hay qué
  armar (`20261025050000`) `[Prod 2026-10-25]`.
- Un `not exists` entre dos CTE materializadas no tiene índice: se corre como
  bucle anidado (1.183 × 600 ≈ 700.000 comparaciones, 148 ms). Un `left join`
  a la tabla por su llave y `where … is null` lo resuelve con el índice
  `[Prod 2026-10-25]`.
- Medir desde el Mac del dueño: **sale a internet por Seattle** (el CDN
  responde desde `cache-bfi`, GA4 lo ubica ahí). Cada viaje a Cloud Run en
  São Paulo cuesta ~200 ms ida y vuelta desde ahí, en cualquier región
  (gcping: São Paulo, Santiago y us-east1 dan 160–270 ms), contra ~22 ms de un
  archivo del CDN. Lo que el dueño ve en la caja no es lo que ve un cliente en
  Chile; el tiempo del servidor está en los registros de Cloud Run
  (`httpRequest.latency`) `[Prod 2026-10-25]`.
- Medir la velocidad de una búsqueda desde el servidor local: lee la base en
  São Paulo desde Chile, así que el tiempo no dice nada; sólo sirve para ver
  que la caja pinta y que el CORS responde. Se mide en producción con
  `explain (analyze, timing off, summary on)` por llamada y en vivo con
  `curl -w` contra los dos orígenes.

## En el código y la base

- Instantánea: `scripts/storefront_instant_page/` (la inyecta el generador),
  contrato en `docs/architecture/storefront-instant-page.md`.
- Medición en el sitio: evento GA4 `store_ready` con `load_ms` y `load_bucket`
  ([medicion](medicion.md)).
- Borde: `cloudflare-worker/`. Presupuesto: `scripts/check_storefront_bundle_budget.sh`.
- Armazón con huella: `SupabasePublicReads._shell` en
  `services/storefront_html/lib/src/public_reads.dart` y la función
  `get_public_storefront_shell_if_changed_v1` (`20261031010000`).
- Buscador: `catalog_search_documents` y `catalog_search_documents_refresh_v1`
  (cron `catalog_search_documents_refresh`); la caja
  `services/storefront_html/lib/src/search_overlay_view.dart` pregunta a
  `STOREFRONT_SEARCH_ORIGIN` (lo pone `services/storefront_html/deploy_cloud_run.sh`).
- Fuentes de la tienda HTML: `scripts/fonts/subset_storefront_fonts.sh` corta
  `web/fonts/*.latin.woff2` (Hosting los sirve en `/fonts/`);
  `services/storefront_html/lib/src/storefront_fonts.dart` los declara con el
  mismo rango y precarga la del título.
