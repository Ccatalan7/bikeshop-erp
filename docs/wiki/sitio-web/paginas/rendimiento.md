---
titulo: Rendimiento y carga
resumen: cuánto pesa y tarda la tienda, la página instantánea que muestra contenido antes de Flutter, el borde, las imágenes y cómo se mide contra las Core Web Vitals
fuentes: [web-dev, flutter-web, repositorio, consolas-google]
archivos: [docs/architecture/storefront-instant-page.md, docs/architecture/storefront-html-migration-plan.md, tool/storefront_html_prototype/measure.mjs, scripts/storefront_instant_page/instant_page.js, scripts/storefront_instant_page/instant_page.css, web/index.html, cloudflare-worker/src/index.js, scripts/check_storefront_bundle_budget.sh, supabase/functions/website-optimize-image/index.ts]
tablas: [website_settings, website_blocks]
revisado: 2026-10-04
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
un servidor Dart de prueba (`tool/storefront_html_prototype/`), medida con el
mismo método: usable a los **2,6 s** contra 23,9 s, **342 KB** contra 4.384 KB,
389 palabras y 67 enlaces sin JavaScript. Pierde en primer byte (0,78 s contra
0,12 s) porque corre en un Mac en Chile y lee la base en São Paulo en cada
visita, sin CDN. Plan y fases en `docs/architecture/storefront-html-migration-plan.md`
`[Repo 2026-10-04]`.

## Borde y datos

- `web/index.html` precarga `get_public_store_data` desde el Worker de Cloudflare
  `vinabike-edge-cache` (caché 5 min por región): ~50 ms en caché frente a
  ~700 ms a Supabase `[Repo: cloudflare-worker/README.md]`.
- La tienda además llama la función directo aunque acepte la precarga (no
  investigado, 2026-09-24).

## Imágenes

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

## En el código y la base

- Instantánea: `scripts/storefront_instant_page/` (la inyecta el generador),
  contrato en `docs/architecture/storefront-instant-page.md`.
- Medición en el sitio: evento GA4 `store_ready` con `load_ms` y `load_bucket`
  ([medicion](medicion.md)).
- Borde: `cloudflare-worker/`. Presupuesto: `scripts/check_storefront_bundle_budget.sh`.
