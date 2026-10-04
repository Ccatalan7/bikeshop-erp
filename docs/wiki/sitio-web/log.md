# Registro del wiki del sitio web

Una línea por operación, la más nueva arriba: `fecha — operación — qué cambió`.
Operaciones: **ingesta**, **consulta archivada**, **revisión** (lint),
**corrección**.

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
