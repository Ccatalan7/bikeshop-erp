# Registro del wiki del sitio web

Una línea por operación, la más nueva arriba: `fecha — operación — qué cambió`.
Operaciones: **ingesta**, **consulta archivada**, **revisión** (lint),
**corrección**.

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
