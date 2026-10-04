---
titulo: Publicación y despliegue de la tienda
resumen: cuándo lo guardado en el editor llega al HTML que ve Google, cómo se construye y publica la tienda, y cómo saber qué versión está en vivo
fuentes: [repositorio, flutter-web]
archivos: [.github/workflows/firebase-hosting-store.yml, scripts/sync_seo_index.sh, scripts/generate_product_seo_snapshots.dart, scripts/check_storefront_bundle_budget.sh, scripts/write_storefront_release_evidence.sh, supabase/functions/dispatch-storefront-publication/index.ts, lib/modules/website/services/storefront_publication_service.dart, supabase/migrations/20260728230000_add_storefront_publication_contract.sql]
tablas: [website_settings, website_pages, website_blocks, products]
revisado: 2026-10-03
---

# Publicación y despliegue de la tienda

## Lo esencial

Hay **dos velocidades** `[Repo]`:

| Qué cambia | Cuándo lo ve el visitante | Cuándo lo ve Google |
|---|---|---|
| Precio, stock, textos, bloques, tema (guardado en el ERP/editor) | al recargar: Flutter lee la base (con hasta 5 min de caché del Worker en los datos de portada) | cuando corre el **build de la tienda** y Google vuelve a rastrear |
| Código de la tienda | tras el build de la tienda | igual |

El build de la tienda corre con un push a `main` que toque la tienda, con el
**build diario** o a mano. Guardar en el editor **no** lo dispara
`[Repo: website-editor-contract.md «Known release-freshness residual»]`.

## El build diario

Cron `0 8 * * *` en `firebase-hosting-store.yml`. **Es la hora pedida, no la de
ejecución:** GitHub atrasa `schedule` con carga y puede saltarse una corrida; la
primera (24-sep) partió a las 13:10 UTC, y el otro cron del repo llegó entre
35 min y 6 h tarde. 08:00 UTC son las 05:00 de Chile en verano y las 04:00 en
invierno. Se describe como «una vez al día, pedido a las 08:00 UTC», nunca con una
hora o plazo máximo `[Repo]`.

## Los pasos del build

1. `scripts/sync_seo_index.sh` escribe los datos SEO del sitio en `web/index.html`.
2. `flutter build web --release -t lib/main_store.dart -o build/web_store`.
3. Presupuesto del bundle (`scripts/check_storefront_bundle_budget.sh`): 7,3 MB
   crudos, 1,95 MB gzip, 3,6 MB diferidos (1,6 MB por pedazo). Si se pasa, no
   publica.
4. `sync_seo_index.sh --check`: si alguien guardó durante el build, aborta.
5. `scripts/generate_product_seo_snapshots.dart` lee configuración, productos,
   disponibilidad, marcas, categorías, alias, páginas y bloques **como una sola
   revisión**: la lee dos veces idéntica y la revalida antes de aplicar las
   redirecciones; si algo cambió, aborta en vez de publicar HTML, sitemap y
   redirecciones mezclados `[Repo: website-editor-contract.md]`.
6. Verifica los activos, sella la revisión, escribe `release.json`, despliega el
   target `store` y comprueba la evidencia en `vinabike.cl` y
   `vinabike-store.web.app`.

## ¿Qué está en vivo?

`https://vinabike.cl/release.json` dice el commit, el run de Actions, la hora del
build (`built_at`), el target y la publicación. El 2026-10-03: commit `c4ed2fde`,
build `2026-10-04T05:20:54Z`, `publication: null` (build por push) `[Prod]`.
Antes de afirmar algo sobre el sitio desplegado, se lee este archivo.

## Publicar desde el editor (no activo)

Existe un contrato para que «Publicar» en el editor dispare el build: un registro
de publicaciones en Postgres (revisiones, coalescencia, reclamos con candado) y
la función `dispatch-storefront-publication`, que llama al workflow por la API de
GitHub. **No está activo** (2026-10-03): la migración
`20260728230000_add_storefront_publication_contract` no está aplicada
(`migration_status.sh` → `NOT_APPLIED`) y falta una **GitHub App** (APP_ID,
INSTALLATION_ID y llave privada) que tiene que crear el dueño. Mientras tanto, el
build diario cubre `[Prod]` `[Repo]`.

## Caché

- `index.html` y las rutas: `Cache-Control: public, max-age=0, must-revalidate`
  (cada visita revalida); Flutter advierte que el `max-age=3600` por defecto de
  Firebase sirve versiones viejas `[FL]` `[Prod]`.
- Los JS y CanvasKit: CanvasKit se sirve desde gstatic con caché inmutable; uno
  propio se descartó (mismo peso y Firebase lo serviría sin caché) `[Repo]`.
- Datos de portada: Worker de Cloudflare, 5 minutos.

## Trampas

- `web/index.html` copiado a `build/web_store` **no arranca Flutter**: el build
  reemplaza `$FLUTTER_BASE_HREF` y pega `flutter_bootstrap.js` en
  `{{flutter_bootstrap_js}}`. Para probar sin recompilar hay que hacer las dos
  cosas (`docs/architecture/storefront-instant-page.md`).
- El generador reescribe `firebase.json` y `scripts/generated_product_redirects.json`
  al correrlo en local: restaurarlos después (CI los regenera).
- `--build-dir` distinto de `build/web_store` aborta; la validación exige un solo
  `LocalBusiness`, un `h1` y un `main` por página.
- Un push a `main` publica la web (también el ERP web); macOS, Windows y Android
  van por despacho aparte.

## En el código y la base

- Workflow: `.github/workflows/firebase-hosting-store.yml` (y
  `scripts/releases/storefront_publication_workflow.mjs`).
- Evidencia: `scripts/write_storefront_release_evidence.sh` → `release.json`.
- Publicación desde el editor: `storefront_publication_service.dart`,
  `supabase/functions/dispatch-storefront-publication/`, migración sin aplicar.
- Para ver la tienda en un navegador real antes de publicar:
  `scripts/dev/web_preview.sh` (`docs/development/WEB_PREVIEW.md`).
