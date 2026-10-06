# Registro del wiki del sitio web

Una línea por operación, la más nueva arriba: `fecha — operación — qué cambió`.
Operaciones: **ingesta**, **consulta archivada**, **revisión** (lint),
**corrección**.

- 2026-10-06 — corrección — [checkout](paginas/checkout-y-pedidos.md): checkout HTML
  en `/_html/checkout` (fase 3b), tienda de prueba local, y el pedido por
  transferencia de un cliente con sesión que la base deshacía desde el 11-jul.
- 2026-10-06 — corrección — [checkout](paginas/checkout-y-pedidos.md) y
  [rutas](paginas/rutas-y-navegacion.md): `/carrito` pasa al servidor HTML (fase 3a).
- 2026-10-06 — consulta archivada — [publicación](paginas/publicacion-y-despliegue.md):
  costo de Hosting (rastreadores de IA y versiones sin límite) y cómo medirlo.
- 2026-10-06 — corrección — [rendimiento](paginas/rendimiento.md): la foto de
  cámaras del carrusel, 2,1 MB en PNG, pasa a WebP de 118 KB por el editor.
- 2026-10-05 — consulta archivada — [rendimiento](paginas/rendimiento.md):
  portada en vivo, teléfono lento: foto principal 2,7 s, carga 2,8 s.
- 2026-10-05 — corrección — [rendimiento](paginas/rendimiento.md): «Productos
  destacados» baja la copia pequeña de la foto optimizada, no el original.
- 2026-10-05 — corrección — [rutas](paginas/rutas-y-navegacion.md): los
  enlaces `?category=<id>` de los bloques salen con la ruta limpia, sin 301.
- 2026-10-05 — corrección — [rutas](paginas/rutas-y-navegacion.md): desde el
  carrito o la cuenta, un clic de Flutter hacia una ruta del servidor recarga
  la página (fase 2f); ya no dibuja su copia de la portada o del catálogo.
- 2026-10-05 — corrección — [rutas](paginas/rutas-y-navegacion.md): `/contacto`
  pasa al servidor HTML (fase 2e); Instagram de Contacto ya no es un enlace roto.
- 2026-10-05 — corrección — [rutas](paginas/rutas-y-navegacion.md): `/servicios`
  y sus categorías pasan al servidor HTML (fase 2d).
- 2026-10-05 — corrección — [rendimiento](paginas/rendimiento.md): las fuentes
  sí pesaban; WOFF2 latino (21 KB) delante del TTF, foto principal de la
  portada 4,8 → 3,7 s en el teléfono lento.
- 2026-10-05 — corrección — `/` abierta al servidor HTML: Flutter entra por
  `app.html`, el `index.html` raíz se borra en el build; medidas de la portada
  en un teléfono lento (texto ~1 s, foto ~4,8 s, Flutter ~20 s) en el plan de
  migración; pendientes nuevos: fuentes WOFF2 y el PNG de 2 MB del carrusel.
- 2026-10-05 — corrección — la tienda HTML se ve como la Flutter: tarjetas,
  grilla, riel de filtros, hojas «Filtro / Ordenar por» del teléfono,
  paginador, pie de escritorio y de teléfono y ficha de producto medidos a
  1 px contra vinabike.cl; Flutter dibuja Oswald «bold» con el peso 400
  engordado ([marca y tema](paginas/marca-y-tema.md),
  [estado](paginas/estado-y-pendientes.md)).

- 2026-10-05 — corrección — miniaturas de tarjeta: un trabajo copia a 400 y
  800 px la foto de cada tarjeta (de cualquier origen) y la anota en
  `public_image_thumbnails`; las tarjetas HTML las ofrecen en `srcset`; un HEAD
  a Storage dice `no-cache` aunque el GET traiga un año
  ([rendimiento](paginas/rendimiento.md), [mapa](paginas/mapa-del-sistema.md)).

- 2026-10-05 — corrección — rutas públicas abiertas a la tienda HTML:
  `/productos`, categorías, fichas y `/producto/<uuid>` en Cloud Run; Hosting
  sirve un archivo estático antes que una reescritura, así que el build ya no
  escribe instantáneas ahí y la publicación revisa el servidor y su fuente
  ([rutas](paginas/rutas-y-navegacion.md),
  [mapa](paginas/mapa-del-sistema.md),
  [estado](paginas/estado-y-pendientes.md)).

- 2026-10-05 — corrección — fase 1 de la tienda HTML en la ruta oculta:
  catálogo, categorías y fichas; reglas movidas al núcleo; dos defectos de
  Flutter corregidos al compartirlas (filtros técnicos indexables, categorías
  de nombre repetido); la cookie `vb_sin_medir` no llega a Cloud Run; la página
  reenviada viajaba sin comprimir; LCP del catálogo frenado por fotos de
  1.200 px ([rutas](paginas/rutas-y-navegacion.md),
  [catalogo](paginas/catalogo-y-fichas.md), [medicion](paginas/medicion.md),
  [rendimiento](paginas/rendimiento.md)).

- 2026-10-05 — corrección — marca por navegador: `?sin_medir` deja de contar
  un navegador propio en GA4 y el píxel, `?medir` la saca; cookie del dominio
  más `localStorage` ([medicion](paginas/medicion.md)).

- 2026-10-05 — consulta archivada — arranque en frío del servidor HTML con
  `min-instances 0`: usable a los 3,0 s contra 2,5 s despierto; despertar suma
  ~0,3–0,5 s ([rendimiento](paginas/rendimiento.md)).

- 2026-10-04 — consulta archivada — GA4 por nombre de host y ciudad (6-sep→3-oct):
  de 1.185 vistas, 279 no eran de vinabike.cl y 515 eran de vinabike.cl desde
  Seattle, que es el Mac del dueño y los agentes; quedan 391 de clientes. El
  «alza de Estados Unidos» del 24-sep fue nuestra ([medicion](paginas/medicion.md),
  [consolas](fuentes/consolas-google.md)).

- 2026-10-04 — corrección — GA4 contaba como usuarios de la tienda las
  sesiones del ERP web, las vistas previas y `localhost`, que comparten la
  página de la tienda; y las mediciones de los agentes, que abren un perfil
  nuevo en cada carga. Ahora mide sólo el dominio de la tienda y las
  herramientas bloquean la analítica ([medicion](paginas/medicion.md)).

- 2026-10-04 — corrección — medido en vivo por `vinabike.cl/_html/`: usable a
  los 2,6 s contra 24,1 s, pero el primer byte (0,90 s) no bajó como prometía
  el plan; lo fija la ficha técnica (~300 ms por lectura). Corregido en el plan
  y en [rendimiento](paginas/rendimiento.md).

- 2026-10-04 — corrección — el servidor HTML corre en Cloud Run y
  `vinabike.cl/_html/**` lo alcanza. Dos trampas del primer despliegue en
  `services/storefront_html/README.md`: la cuenta de compilación necesita
  `roles/run.builder` aunque tenga Editor, y `dart compile exe` no crea su
  carpeta de salida.

- 2026-10-04 — corrección — el dueño aprobó la migración y empezó la fase 0:
  núcleo Dart compartido en un paquete (los archivos se movieron y las rutas
  viejas los reexportan), dos lecturas públicas `SECURITY INVOKER` en
  producción, servidor Jaspr que reemplaza a la prueba. Medido en producción:
  la ficha técnica cuesta ~275 ms por lectura, también en la tienda Flutter
  ([rendimiento](paginas/rendimiento.md)). Falta Cloud Run, que espera el
  inicio de sesión del dueño en Google Cloud ([estado](paginas/estado-y-pendientes.md)). La revisión de Codex
  (sin P0/P1) encontró marcas sin filtro de empresa y relacionados sin los
  campos del sitio en la lectura (corregido en `20261004190000`), y menús y pie
  que no seguían la regla de Flutter.

- 2026-10-04 — consulta archivada — el dueño preguntó si el sitio y el editor
  podían migrar a HTML sin perder el editor dentro del ERP ni la frescura de los
  datos. Ninguno de los dos requisitos necesitaba Flutter. Se escribió el plan
  (`docs/architecture/storefront-html-migration-plan.md`: núcleo Dart
  compartido, servidor junto a la base, lienzo del editor como visor web en el
  ERP, cuatro fases reversibles) y una ficha de prueba que importa el núcleo
  Dart sin copiarlo, medida en [rendimiento](paginas/rendimiento.md). Espera la
  decisión del dueño ([estado](paginas/estado-y-pendientes.md)).

- 2026-10-04 — corrección — datos estructurados hechos y medidos con un build
  local sobre datos reales: ficha técnica como `additionalProperty` en 1.232 de
  1.295 fichas, migas completas y un solo armado para snapshot y página (la
  página borraba las migas del snapshot al cargar); `BikeStore` con horario,
  logo, mapa y link a `/devoluciones`
  ([datos-estructurados](paginas/datos-estructurados.md)). El envío por tramos
  se implementó (con la función nueva `get_public_online_shipping_tiers`) y se
  retiró tras la revisión: Google no puede acotar «Chile continental» y
  declarar `CL` promete despacho a las islas, con Merchant suspendido por
  información engañosa. Codex encontró además un horario mal tipado que tumbaba
  `/contacto` y el build, un calendario lunes–viernes sin dueño y lecturas sin
  plazo; corregidos, y en la segunda pasada horas imposibles (`24:30`,
  `99:99`) que todavía pasaban.
  Tres afirmaciones anteriores eran falsas: «la ficha no declara
  `description`» (sí la declara; sólo 29 de 1.541 productos tienen texto), «quitar
  el bloqueo de `/pedido/` en robots» (protege el token del pedido; descartado en
  [rutas](paginas/rutas-y-navegacion.md)) y que `web/index.html` fuera fuente: lo
  regenera el build, y el script de doble navegación nunca llegó a producción
  ([publicación](paginas/publicacion-y-despliegue.md)).

- 2026-10-04 — ingesta — el dueño pidió aplicar «absolutamente toda la
  configuración de SEO» de los referentes. Se midió en vivo (portada, categoría,
  ficha, robots, sitemaps) a Oxford Store, Better Bike, Cycling Store, Express
  Bike, RudolfBike, ExtremeZone, Bike Center, Sparta, Canyon, Specialized y
  Commencal. Nace [seo-de-referentes](paginas/seo-de-referentes.md) con la
  comparación y diez brechas en orden de impacto, la ficha
  [referentes](fuentes/referentes.md) y la etiqueta `[Ref]`. Corrección en el
  camino: nuestro HTML sí trae la descripción del producto, pero en
  `<noscript>`, que Google descarta; no son 13 palabras para un rastreador sin
  JavaScript sino ~100. Ingesta de la guía de reseñas de Google (2026-09-08).

- 2026-10-04 — consulta archivada — el dueño fijó el objetivo (tienda premium,
  moderna, segura y bien conectada; venta, correos y creación de cuenta
  impecables) y se revisó el flujo de venta en producción: correos del pedido
  activos y sin errores, pero sólo `order_received` y `cancelled` se han enviado
  en vivo; la última venta web pagada es del 3-may; los 13 correos de cuenta
  coinciden con el repo y hay servidor de correo propio (30/h); el taller no
  recibe correo de pedido nuevo; la tienda sí despacha por tramos y
  `shipping_enabled` es una clave vieja. Ingesta de Google: políticas de
  devolución y de envío a nivel de organización (2026-09-08). Anotado en
  checkout, datos estructurados y pendientes.

- 2026-10-04 — corrección — el dueño precisó la regla 1: si pide algo que el
  editor no puede representar, el agente es libre de crear primero la función o
  el componente en el editor y después aplicar el cambio, sin pedir permiso
  aparte. Escrito como libertad explícita (no sólo como obligación) en
  [principios](paginas/principios.md), la skill, `AGENTS.md`, el aviso de sesión
  y `website-editor-contract.md`.

- 2026-10-04 — corrección — el dueño preguntó si el wiki tenía «esa idea que si
  los agentes aplican cambios, esos no pueden ser implementaciones paralelas a lo
  que se podría hacer en el editor». Estaba en los contratos como invariante no
  negociable, pero en el wiki sólo como una línea del editor y no salió en el
  resumen. Pasa a ser la **regla 1** de [principios](paginas/principios.md), con
  lo permitido y lo prohibido, la prueba de ida y vuelta y un precedente propio
  (23-sep, textos SEO y bloque «MARCAS» por SQL directo); también en el README,
  el índice, la página del editor, la skill, `AGENTS.md` y el aviso de inicio de
  sesión.

- 2026-10-03 — creación — el dueño pidió «una nueva carpeta de second brain…
  como una especie de master schema experto en nuestro sitio web y editor del
  sitio». Se escribieron 17 páginas y 8 fichas de fuente con lo que había
  repartido en el contrato del editor, el handoff, la página instantánea, el
  runbook de pedidos, 11 notas de memoria y el diagnóstico del 23-sep; cada
  número se contrastó con producción y con vinabike.cl ese día. Ingesta de
  Google Search Central (JS SEO, canonical, sitemaps, robots, indexación, fichas
  de comercio, negocio local), Merchant (tergiversación), web.dev (Core Web
  Vitals), Flutter (web FAQ), GA4 (comercio) y schema.org (`BikeStore`). Nacen la
  skill `.claude/skills/sitio-web/`, el lint `scripts/knowledge/lint_site_wiki.py`,
  el hook `.claude/hooks/site_wiki_router.py` y la prueba
  `test/unit/site_wiki_contract_test.dart`.
- 2026-10-03 — consulta archivada — al contrastar con lo vivo salieron cosas que
  ningún documento decía: `robots.txt` bloquea `/cuenta/` y `/pedido/` y eso
  impide que Google lea su `noindex`; el JSON-LD de ficha no declara
  `description`, envío ni devoluciones; el negocio se declara `LocalBusiness`
  genérico (existe `BikeStore`); el píxel de Meta está apagado (sin ID);
  `get_public_store_data` devuelve configuración y bloques de portada (no
  navegación); la precarga la toma `WebsiteService`; la tabla de alias es
  `product_url_aliases`; `banners_management_page.dart`,
  `content_management_page.dart` y la clave `header_nav_links` ya no se usan.
  Anotado en sus páginas y en [estado y pendientes](paginas/estado-y-pendientes.md).

## 2026-10-05 — Páginas de información en HTML (fase 2a)

- Las cinco páginas de información las dibuja el servidor en `/_html/`; las
  trampas medidas (normalización al cargar, espaciado heredado de Material 3,
  líneas redondeadas, densidad −1, bandas de ancho, la llave sobrante de la
  hoja) quedaron en el plan de migración.
- El bloque de contacto mostraba al visitante el aviso del editor en tres
  páginas públicas; ahora usa los datos de Configuración → Contacto. Anotado
  en [estado y pendientes](paginas/estado-y-pendientes.md).

## 2026-10-05 — Portada en HTML (fase 2b)

- La portada completa la dibuja el servidor en `/_html/`, medida contra
  Flutter; las trampas (encabezado que no reserva alto, lienzo que no escala
  el texto, altura mínima, `Wrap` arriba, color del ítem actual) quedaron en
  el plan de migración. Abrir `/` queda en
  [estado y pendientes](paginas/estado-y-pendientes.md).
