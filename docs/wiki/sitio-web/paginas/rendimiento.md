---
titulo: Rendimiento y carga
resumen: cuánto pesa y tarda la tienda, la página instantánea que muestra contenido antes de Flutter, el borde, las imágenes y cómo se mide contra las Core Web Vitals
fuentes: [web-dev, flutter-web, repositorio, consolas-google]
archivos: [scripts/fonts/subset_storefront_fonts.sh, services/storefront_html/lib/src/storefront_fonts.dart, scripts/generate_public_image_thumbnails.dart, docs/architecture/storefront-instant-page.md, docs/architecture/storefront-html-migration-plan.md, services/storefront_html/tool/measure.mjs, scripts/storefront_instant_page/instant_page.js, scripts/storefront_instant_page/instant_page.css, web/index.html, cloudflare-worker/src/index.js, scripts/check_storefront_bundle_budget.sh, supabase/functions/website-optimize-image/index.ts]
tablas: [website_settings, website_blocks, public_image_thumbnails]
revisado: 2026-10-05
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
- El catálogo lee ~450–700 ms: `get_public_product_facets_v2` ~410 ms en la
  base, de eso ~270 ms en `spec_public_facet_values_internal_v1` (valores
  técnicos de todo el catálogo, en cada visita) y ~190 ms en el universo de
  `get_public_products`. Lo paga igual la tienda Flutter `[Prod 2026-10-05]`.

## Borde y datos

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
  de JPEG 168 KB a WebP 82 KB. Siguen pesados: la campaña de cámaras en PNG
  (2.085 KB) y una WebP de 312 KB en la grilla de categorías (2026-09-24).
- La biblioteca no lista `.avif` (`listAssets`).

## Presupuesto del bundle

El build falla si `main.dart.js` y compañía pasan 7,3 MB crudos o 1,95 MB gzip
(`check_storefront_bundle_budget.sh`). Es el freno para que el peso no crezca
sin que nadie lo decida.

## Trampas

- Juzgar con un solo número de PageSpeed: varía entre corridas y es laboratorio.
- `pagespeed.web.dev` no termina en una pestaña de fondo ni en el navegador
  integrado con el panel oculto.
- Un `<canvas>` no cuenta como LCP: el LCP de una página Flutter pura es el logo
  o la imagen HTML que haya.
- Precargar `main.dart.js` compite con la foto del LCP.
- Creer que `fetchpriority="low"` en las fotos de abajo deja pasar a la del LCP:
  con fotos de 100 KB igual se reparten el ancho de banda (medido 2026-10-05,
  sin cambio apreciable). El arreglo es el tamaño, no la prioridad.

## En el código y la base

- Instantánea: `scripts/storefront_instant_page/` (la inyecta el generador),
  contrato en `docs/architecture/storefront-instant-page.md`.
- Medición en el sitio: evento GA4 `store_ready` con `load_ms` y `load_bucket`
  ([medicion](medicion.md)).
- Borde: `cloudflare-worker/`. Presupuesto: `scripts/check_storefront_bundle_budget.sh`.
- Fuentes de la tienda HTML: `scripts/fonts/subset_storefront_fonts.sh` corta
  `web/fonts/*.latin.woff2` (Hosting los sirve en `/fonts/`);
  `services/storefront_html/lib/src/storefront_fonts.dart` los declara con el
  mismo rango y precarga la del título.
