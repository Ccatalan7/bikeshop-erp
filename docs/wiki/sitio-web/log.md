# Registro del wiki del sitio web

Una línea por operación, la más nueva arriba: `fecha — operación — qué cambió`.
Operaciones: **ingesta**, **consulta archivada**, **revisión** (lint),
**corrección**.

- 2026-10-07 — corrección — [editor](paginas/editor-del-sitio.md) y
  [estado](paginas/estado-y-pendientes.md): la Vista HTML del editor (fases
  5b y 5c) y lo que le falta.
- 2026-10-07 — corrección — [rendimiento](paginas/rendimiento.md),
  [catálogo](paginas/catalogo-y-fichas.md) y
  [estado](paginas/estado-y-pendientes.md): el 503 del catálogo con muchas
  visitas juntas; lecturas que hacen menos (`20261007020000`), cuatro
  consultas a la vez desde el servidor, filtros opcionales y filtros activos
  que no desaparecen. Números antes y después.
- 2026-10-06 — corrección — [estado](paginas/estado-y-pendientes.md) y
  [editor](paginas/editor-del-sitio.md): la causa real del cuelgue de debug
  entre catálogo, categoría y ficha (una página tapada en el `Navigator` de la
  tienda, dentro del scroll, que el `Overlay` no vuelve a medir); el
  diagnóstico anterior era falso. Arreglado sin mantener páginas tapadas.
- 2026-10-06 — corrección — [catálogo](paginas/catalogo-y-fichas.md),
  [editor](paginas/editor-del-sitio.md) y [estado](paginas/estado-y-pendientes.md):
  etapa 3d, la ficha de producto como plantilla en el lienzo; despacho y retiro
  editables y la tarifa más barata también en Flutter; la propuesta del editor
  completa; la aserción de debug también entre categoría y ficha, y por qué
  cambiar el visor de la tienda no la arregla.
- 2026-10-06 — corrección — [catálogo](paginas/catalogo-y-fichas.md) y
  [editor](paginas/editor-del-sitio.md): etapa 3c, una plantilla para las 11
  categorías (`@catalog/categories`, «Diseño propio» por categoría, la misma
  regla en Flutter y en el servidor HTML).
- 2026-10-06 — corrección — [editor](paginas/editor-del-sitio.md) y
  [catálogo](paginas/catalogo-y-fichas.md): etapa 3b sin plantillas (Catálogo
  en tablas, todo lo de una categoría en su página, Ajustes del sitio con
  índice, versiones automáticas, copiar y pegar secciones); «Frenos» son tres
  categorías y el guardia de enlaces ahora sigue la regla de la ruta;
  [estado](paginas/estado-y-pendientes.md) con la aserción de debug anterior
  al lienzo.
- 2026-10-06 — corrección — [catálogo](paginas/catalogo-y-fichas.md) y
  [editor](paginas/editor-del-sitio.md): etapa 3a, `/productos` y las 11
  categorías se editan sobre su página; la trampa de la recarga en caliente
  con un campo nuevo; [estado](paginas/estado-y-pendientes.md) con el ERP
  1.0.12 publicado y la etapa 3b pendiente.
- 2026-10-06 — corrección — [editor](paginas/editor-del-sitio.md): etapa 2b,
  la lista «Secciones» (columna a la izquierda desde 1584 px o el panel sin
  selección) y la trampa del documento que sobrevive a su página;
  [estado](paginas/estado-y-pendientes.md) con el ERP 1.0.11 publicado.
- 2026-10-06 — corrección — [editor](paginas/editor-del-sitio.md): etapa 2a,
  la barra de arriba con los tres lugares, la página a la vista y «Guardar»
  siempre arriba; [estado](paginas/estado-y-pendientes.md) al día.
- 2026-10-06 — corrección — [editor](paginas/editor-del-sitio.md): etapa 1
  del rediseño aprobado, `/servicios` se edita sobre la página (secciones,
  textos en el lugar, panel de la selección, «Guardar» común) y la trampa del
  atajo de `Espacio` que se come los espacios;
  [catálogo](paginas/catalogo-y-fichas.md) dice dónde se edita;
  [estado](paginas/estado-y-pendientes.md) con las etapas 2 y 3 y el ERP
  1.0.10 publicado.
- 2026-10-06 — corrección — [catálogo](paginas/catalogo-y-fichas.md):
  `/servicios` como lista de precios (portada, planes, servicios por grupo,
  cierre), decidido en `Catálogo web > Presentación`; las 10 categorías de
  servicios; [editor](paginas/editor-del-sitio.md) y
  [estado](paginas/estado-y-pendientes.md) con el pendiente de rediseñar las
  páginas de configuración del editor.
- 2026-10-06 — corrección — [estado](paginas/estado-y-pendientes.md): los
  bloques del editor que ninguna página usa no se copian con el aspecto viejo
  de Flutter; el dueño pidió verlos rediseñados antes (propuesta en Claude
  Design) y la tercera tanda de la fase 5a espera su visto bueno.
- 2026-10-06 — corrección — [editor](paginas/editor-del-sitio.md): el HTML
  dibuja también preguntas, llamado a la acción, características y «sobre
  nosotros», y dice qué tipos faltan; [estado](paginas/estado-y-pendientes.md)
  al día.
- 2026-10-06 — corrección — [rutas](paginas/rutas-y-navegacion.md): las
  páginas del editor (`/pagina/<slug>`) en el servidor HTML con texto, botón
  y separador (fase 5a); [editor](paginas/editor-del-sitio.md) dice qué
  bloques dibuja el HTML y que uno con superficie propia queda en Flutter;
  [estado](paginas/estado-y-pendientes.md) con el ERP 1.0.9.
- 2026-10-06 — corrección — [portal](paginas/portal-de-clientes.md): el
  login en el servidor HTML (fase 4c), con Auth desde el navegador y los
  enlaces del correo en Flutter; el teléfono de la cuenta nueva se guarda al
  entrar; [seguridad](paginas/seguridad.md) (la contraseña no llega al
  servidor; la regla de Hosting de `/cuenta/**` pisaba el `no-store`),
  [rutas](paginas/rutas-y-navegacion.md) y [estado](paginas/estado-y-pendientes.md)
  al día.
- 2026-10-06 — corrección — [portal](paginas/portal-de-clientes.md): perfil y
  direcciones en el servidor HTML (fase 4b), guardados con `POST
  /cuenta/accion` como el cliente; tres arreglos de las dos tiendas al
  mudarlo; [seguridad](paginas/seguridad.md), [rutas](paginas/rutas-y-navegacion.md)
  y [estado](paginas/estado-y-pendientes.md) al día.
- 2026-10-06 — corrección — [portal](paginas/portal-de-clientes.md): las
  páginas de lectura del portal en el servidor HTML (fase 4a), leídas con el
  token del cliente; reglas al núcleo; [rutas](paginas/rutas-y-navegacion.md)
  y [seguridad](paginas/seguridad.md) al día.
- 2026-10-06 — consulta archivada — [rendimiento](paginas/rendimiento.md):
  celular lento con todo lo público en HTML: 0,8–2,8 s por página contra
  20,5 s de la cuenta, que sigue en Flutter.
- 2026-10-06 — corrección — [rutas](paginas/rutas-y-navegacion.md): el menú
  ancho de escritorio en las páginas HTML, como Flutter (la función del menú
  trae `css_class` desde `20261006120000`); cerrada la diferencia abierta.
- 2026-10-06 — corrección — [rutas](paginas/rutas-y-navegacion.md): el
  encabezado HTML muestra la cuenta con sesión y el menú del teléfono usa la
  regla de Flutter; el menú ancho de escritorio queda como diferencia abierta.
- 2026-10-06 — corrección — [checkout](paginas/checkout-y-pedidos.md) y
  [rutas](paginas/rutas-y-navegacion.md): `/checkout` abierto al servidor; la
  página del pedido en HTML (fase 3c) con su PDF en el servidor; la clave
  publicable pasa la puerta de las funciones; el token del pedido nunca va en
  la dirección.
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

## 2026-10-07 — La vista HTML del editor dibuja cualquier página

- El borrador lleva la ruta pública en pantalla y el servidor la dibuja con el
  manejador de las visitas, a través de lecturas que llevan el borrador
  (`EditorDraftReads`): catálogo, categorías, ficha e información salen sin un
  dibujo aparte. Las marcas son una capa sobre la página.
- Trampas medidas: una categoría entrada desde el catálogo se empuja y sólo
  `GoRouter.state` la nombra; la vista nativa de macOS no recibe movimientos
  del puntero; la captura de una ventana en segundo plano es vieja (runbook
  de control de la app).
- Hallazgo: el lienzo Flutter lista 1.615 productos y la tienda 538; queda en
  [estado y pendientes](paginas/estado-y-pendientes.md).

## 2026-10-07 — Escribir los textos sobre la vista HTML (5d)

- Con el bloque elegido, un clic en un título o texto lo vuelve editable en
  la página; el editor lo arrienda por el mismo dueño que el lienzo
  (`WebsiteInlineFieldBinding`) y lo escribe como un paso del historial.
- Trampa medida en la app: un bloque dibujado una vez por banda tiene dos
  elementos con el mismo `data-block-id`, uno oculto; la página marcaba el
  primero. Se marca el que se ve.
- El carrusel no avanza solo en el borrador (como el lienzo), y sus flechas
  lo mueven.

## 2026-10-07 — La vista HTML en el ERP web

- Probada con la sesión del dueño en Chrome: el visor de la web carga la
  página como `data:` URL, de otro origen; el editor no podía ejecutar nada
  en ella (ni marco, ni barra, ni escritura). Ahora se hablan por mensajes en
  los dos sentidos, firmados con la ficha de la vista.

## 2026-10-07 — Segunda prueba de la vista HTML en el ERP web

- El editor no le contestaba a la página: guardar la ventana del marco con
  `event.source!` la lee, y una ventana de otro origen no se deja leer. Se
  guarda sin leerla y sólo se le escribe.
- El ERP web no arrancaba después del deploy: el service worker de Flutter
  mezclaba partes de dos builds. El ERP web va sin service worker y retira el
  viejo; una pestaña de antes de un deploy avisa «Hay una versión nueva».
- Verificado en el ERP web publicado (2450c55e): la página recibe la
  selección (barra, «Agregar aquí», alto) y se escribe un título con ⌘↵, que
  se deshace. El worker viejo se fue solo; la primera carga aún corrió el
  programa viejo, y `index.html` lo retira ahora antes de arrancar.

## 2026-10-07 — Las secciones del muestrario, en Flutter y en HTML

- Construidas desde el lienzo aprobado: cifras, carta del taller, planes,
  testimonios, galería, equipo, preguntas, franja de marcas y llamado, con
  tonos de la marca y anchos por el bloque decididos en el núcleo. El HTML
  ya cubre todos los tipos salvo `canvas` y `footer`.
- `text-wrap: balance` en el HTML y una `Row` por línea base dentro de
  `IntrinsicHeight` en Flutter rompían la paridad; el detalle está en la fase
  5a del plan de migración.
- Vistas en la app real antes de publicar: el bloque nuevo de cifras decía
  «4,8 en Google» con la nota real en 4,4. Ahora la nota y las reseñas salen
  de la sincronización, los precios de ejemplo son los del catálogo y nada
  inicial afirma plazos ni certificaciones. Dos bandas seguidas se tocan.

## 2026-10-07 — El bloque canvas en HTML

- `canvas` lo dibuja el HTML (escenario + capas del carrusel); siguen en
  Flutter los que tienen una capa de producto o un video de fondo.
- Al compararlo apareció que el lienzo Flutter cortaba el texto de una capa
  que no cabe y el HTML no: el carrusel en vivo ya tenía ese caso en la
  tableta. Ahora Flutter tampoco corta.

## 2026-10-07 — Código muerto del sitio fuera

- Borradas las páginas sin ruta del editor viejo (banners, contenido) y del
  portal viejo (cuenta, tablero «premium»), más la lista y el detalle viejos
  del chat. `/cuenta/mensajes` redirige al centro de chats en vez de dibujar
  una lista distinta. La clave `header_nav_links` se queda: nadie la lee y
  borrarla es una escritura que borra.

## 2026-10-07 — El catálogo del lienzo es el del cliente

- Causa de los 1.615 productos del lienzo: Editar no usaba la lectura de la
  tienda, cargaba todo lo editable (no publicado y agotado) y filtraba y
  paginaba en la app. «Ver como cliente» lo heredaba porque cambiar de modo
  no vuelve a cargar. Se quitó ese camino: los tres modos piden al servidor.

## 2026-10-07 — Los botones en la vista HTML

- Un botón del bloque elegido se edita en su lugar con la tarjeta del
  lienzo (texto, destino, estilo). Los campos de cada botón los nombra el
  núcleo (`WebsiteButtonFields`) y la página los pide por nombre.
- Comprobado antes con clics reales: un diálogo de Flutter sobre la vista web
  de macOS recibe los clics.
- Las capas de una campaña (diapositiva de cámaras, 33 capas) se eligen con
  un clic en la vista HTML; antes sólo se elegía el carrusel.
- Las fotos de sobre nosotros, servicios, galería y equipo se cambian con
  un clic en la vista HTML (selector de imágenes del lienzo).
- La capa elegida se mueve y cambia de tamaño arrastrando en la vista HTML,
  por la manipulación directa del lienzo.
- La capa arrastrada en la vista HTML cae como en el lienzo: se pega a bordes
  y centros (del canvas y de otras capas) con línea guía, o a la grilla del
  documento; Mayús y Escape como en el lienzo.
- Revisión de Codex: un botón o una foto pedida para otro tipo de bloque se
  rechaza (hero y CTA comparten la llave del texto).
- En macOS las flechas de la vista HTML no hacían nada: un clic no le da el
  teclado a la vista nativa. El editor lo toma y se lo pasa; Suprimir y ⌘D
  borran y duplican la capa como en el lienzo.
- La capa elegida se gira en la vista HTML con su manilla; su marco se
  dibuja girado y una capa girada cambia de tamaño en sus propios ejes.
- El HTML pinta la superficie propia de un bloque (pestaña Estilo) como
  Flutter: antes una página con un bloque con estilo volvía entera a Flutter.
- La vista HTML es el lienzo con que abre el editor en macOS y el ERP web;
  cada equipo recuerda si se apaga.
