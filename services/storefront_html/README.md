# Tienda en HTML

La tienda pública armada como HTML en el servidor, una página por visita, con el
mismo código Dart que el ERP (`packages/vinabike_public_core`). Es la fase 0 de
`docs/architecture/storefront-html-migration-plan.md`: sólo fichas de producto,
en una ruta oculta (`/_html/productos/<nombre>/<sku>`) junto a la ficha Flutter
que copian, con `noindex`.

- **Datos:** dos lecturas públicas al mismo tiempo, con la llave publicable
  (`get_public_storefront_shell_v1`, `get_public_product_page_v1`). No guarda
  nada: cada visita lee precio, stock, menús y tema; cada respuesta es
  `no-store`.
- **Páginas:** componentes Jaspr que sólo corren en el servidor. Sin
  JavaScript la página está completa; dos scripts chicos cambian la foto y
  avisan que el carrito llega en la fase 1. Jaspr avisa una vez al arrancar que
  no hay archivo `.client.dart`: es a propósito.
- **Cabeceras:** `server-timing` (`data` = las lecturas, `render` = armar el
  HTML), `x-robots-tag: noindex`.

## Correrlo en el Mac

```bash
bash services/storefront_html/run_local.sh
```

Abre `http://localhost:4325/_html/productos/x/H911` (el nombre en la ruta no
importa; manda el SKU). Lee producción, sólo lectura, con la llave publicable
del Llavero de macOS (`Vinabike ERP Supabase publishable key`) o de
`SUPABASE_PUBLISHABLE_KEY`, y sirve las fuentes y el logo desde `assets/` como
lo hace Firebase. Con `.claude/launch.json` se abre con `preview_start`
(`storefront-html`); no recarga solo: se reinicia tras cada cambio.

## Pruebas y medición

```bash
cd services/storefront_html && ../../.fvm/flutter_sdk/bin/dart test
node services/storefront_html/tool/measure.mjs "<url>" <etiqueta> 3
```

`measure.mjs` simula un celular lento (1,6 Mbps, 150 ms, CPU ×4, 412×823,
perfil nuevo por carga) y da la mediana. Con una URL de vinabike.cl mide la
tienda Flutter: «lista» es cuando retira la página instantánea. Una captura de
página completa deja vacías las fotos con `loading="lazy"`: hay que recorrer la
página antes.

## Desplegarlo

```bash
bash services/storefront_html/deploy_cloud_run.sh
```

**Costo: tiene que ser gratis** (requisito del dueño, 2026-10-04). Por eso
`min-instances 0`: Cloud Run cobra sólo mientras responde, dentro de su cuota
gratis mensual, que a este tráfico no se acerca. Una instancia siempre
despierta costaría ~US$10–15 al mes; sólo con una decisión explícita del dueño.

Cloud Run en `southamerica-east1`, junto a Supabase. Necesita `gcloud` con la
sesión de un dueño del proyecto y facturación activa. Desplegado por primera vez
el 2026-10-04 (`storefront-html-00001`).

Dos trampas que costaron un intento cada una (2026-10-04):

- La compilación corre con la cuenta de servicio por defecto
  (`452996097799-compute@developer.gserviceaccount.com`), y aunque tiene
  Editor, Cloud Build la rechaza («the default service account is missing
  required IAM permissions») hasta que tiene `roles/run.builder`. Ese permiso
  lo dio el dueño; un agente no cambia permisos del proyecto.
- `dart compile exe` no crea la carpeta de salida: el `Dockerfile` hace
  `mkdir -p /out` antes.

Cloud Run reserva las rutas que terminan en `z` (`/healthz` responde 404 desde
el borde de Google, sin llegar al servidor).

Cloud Build compila la
imagen (`Dockerfile`, Dart 3.10.4 → binario nativo sobre una imagen vacía)
desde un contexto con sólo este servicio y el núcleo. Después del primer
despliegue, y nunca antes, se agrega en `firebase.json` (target `store`) la
reescritura `{"source": "/_html/**", "run": {"serviceId": "storefront-html",
"region": "southamerica-east1"}}` antes de `**`: si el servicio no existe,
falla el despliegue de Hosting.
