---
titulo: SEO técnico
resumen: cómo lee Google una tienda hecha en Flutter, qué hace Viñabike para que la entienda (snapshots, semántica, canonical, sitemap, robots) y cómo se mide sin engañarse
fuentes: [google-search-central, flutter-web, repositorio, consolas-google]
archivos: [scripts/generate_product_seo_snapshots.dart, scripts/sync_seo_index.sh, lib/public_store/services/crawler_semantics.dart, lib/public_store/widgets/public_link_semantics.dart, lib/modules/website/services/website_seo_center_service.dart, lib/modules/website/pages/seo_settings_page.dart, packages/vinabike_public_core/lib/public_store/models/public_product_seo_copy.dart]
tablas: [website_settings, website_pages, products, product_categories]
revisado: 2026-10-04
---

# SEO técnico

## Lo esencial

Google procesa un sitio en tres fases: **rastrea** el HTML (sólo sigue `<a
href>`), lo pone en una **cola de render** con un Chromium sin pantalla, y
**indexa** lo renderizado `[GSC]`. Flutter web pinta en un `<canvas>` y su propia
documentación dice que no sirve para contenido crítico de SEO `[FL]`. Por eso
Viñabike le da a Google tres cosas que no dependen de Flutter `[Repo]`:

1. **Un snapshot HTML por ruta indexable** (ficha, categoría, páginas, portada),
   escrito en el build por `generate_product_seo_snapshots.dart`, con título,
   descripción, canonical, Open Graph, JSON-LD, un `h1`, un `main` y enlaces
   reales.
2. **Semántica para rastreadores:** cuando la tienda detecta un rastreador,
   activa el árbol de accesibilidad y cada destino marcado con
   `PublicLinkSemantics` sale como `<a href>` real. El contenido es el mismo que
   ve un cliente. Tras activarla (2026-09-24), el render de Google de una ficha
   pasó de 0 a 11 enlaces fuera de `noscript` `[Consola]`.
3. **Cabeceras** `X-Robots-Tag` en lo que no se indexa ([rutas](rutas-y-navegacion.md)).

## Canonical

- Cada página declara su URL absoluta propia como canonical; las URL viejas
  redirigen con 301 (la señal más fuerte) y el sitemap sólo lista canónicas
  (señal débil, pero coherente) `[GSC]`.
- El origen canónico es `store_url` (`https://vinabike.cl`), un origen HTTPS
  limpio validado por `WebsiteSeoSettingsAliases.normalizeHttpsOrigin`;
  `seo_canonical_url` es sólo un espejo de compatibilidad `[Repo]`.
- Un canonical inyectado por JavaScript tiene que coincidir con el del HTML; nunca
  dos distintos `[GSC]`.
- Las 613 «páginas alternativas con canonical» de Search Console (2026-09-23; 606
  bajo `/productos/`) eran URL viejas apuntando bien a la nueva: no es error `[GSC]` `[Consola]`.

## Sitemap

1.315 URL el 2026-10-03, todas con `lastmod`: la portada, 8 páginas (`/productos`,
`/servicios` y las seis fijas: contacto, nosotros, términos, privacidad,
devoluciones, envíos) y 1.306 bajo `/productos/`
(fichas, incluidos agotados, y 11 categorías) `[Prod]`. Lejos
del límite de 50.000 por archivo. Google ignora `priority` y `changefreq` y sólo
usa `lastmod` si es exacto: tiene que cambiar sólo cuando cambia el contenido
`[GSC]`. Se envía en Search Console y se declara en `robots.txt`.

## Títulos y descripciones

- Sitio: `seo_*` y `meta_*` en `website_settings`, escritos en `index.html` por
  `sync_seo_index.sh`; desde el 2026-09-23 sin «Compra/Venta de bicicletas» y
  con una descripción real de la tienda. La portada tiene cinco fuentes de
  título que se igualaron ese día (página `inicio`, `seo_meta_*`, `meta_*`
  heredadas, `web/index.html`) `[Repo]`.
- Producto: un solo resolvedor para app, vista previa y snapshot
  ([catalogo-y-fichas](catalogo-y-fichas.md)).

## El centro SEO del ERP (`/website/seo`)

Sólo lectura: lista el sitio, las páginas, **todos** los productos internos y
**todas** las categorías activas (publicadas o no) y manda a cada dueño. Separa
tres planos que no se mezclan `[Repo: website-editor-contract.md]`:

1. **Lo que la app permite hoy** (derivado de los dueños).
2. **Lo que el build desplegado tiene** (`release.json`, `sitemap.xml`,
   `robots.txt`, con fecha).
3. **Lo que Google dice** (Search Console, con fecha). Un sitemap enviado no
   prueba que una URL esté rastreada ni indexada.

No ve Search Console hasta reconectar la cuenta Google con el permiso
`webmasters` ([fuente](../fuentes/consolas-google.md)).

## Cómo leer Search Console

- Indexación: filtrar **al sitemap enviado** y anotar la fecha del informe y la
  del build. «Rastreada: sin indexar» y «Descubierta: sin indexar» no son
  errores; «Página alternativa con canonical» funciona como debe; «Soft 404» y
  «Excluida por noindex» sí se revisan si no eran a propósito `[GSC]`.
- Los informes de fichas de comercio muestran muestras, no un censo.
- Línea base del 2026-09-23: 524 de 549 URL del sitemap indexadas; `/productos/`
  175 clics en 3 meses, ~7 mil impresiones, en baja `[Consola]`. Se compara
  contra esto, con fecha.

## Oportunidades (2026-10-03)

- ~~Quitar de `robots.txt` el bloqueo de `/cuenta/` y `/pedido/`~~ — descartado
  el 2026-10-04: `/pedido/<id>` lleva el token del pedido y el bloqueo evita que
  el rastreador lo abra ([rutas](rutas-y-navegacion.md)).
- Enlaces externos: 0 en Search Console (2026-09-23). Fuera del código: ficha de
  Google, marcas, proveedores y comunidades que enlacen a fichas y categorías.
- `/servicios` estaba «Rastreada: sin indexar» (último rastreo 7-may) al pedir su
  indexación el 2026-09-23: volver a mirarlo.

## Trampas

- Medir con la vista por defecto (todas las URL conocidas, 2.425 no indexadas el
  23-sep) en vez de la del sitemap.
- Concluir lo que ve Google con Chrome y user agent de Googlebot: usar la Prueba
  de resultados enriquecidos o la inspección de URL.
- Un contenido o enlace que sólo existe dentro de Flutter (sin snapshot ni
  semántica) no existe para Google.
- El contador de `noindex` del sitemap no mide nada sobre agotados: los agotados
  no estaban en el sitemap antes del arreglo.

## En el código y la base

- Generador: `scripts/generate_product_seo_snapshots.dart`; índice:
  `scripts/sync_seo_index.sh`; semántica: `crawler_semantics*.dart`,
  `public_link_semantics.dart`; centro SEO: `website_seo_center_service.dart`,
  `seo_settings_page.dart`.
- Claves: `store_url`, `seo_*`, `meta_*` en `website_settings`.
