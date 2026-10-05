# Tienda en HTML

La tienda pública armada como HTML en el servidor, una página por visita, con el
mismo código Dart que el ERP (`packages/vinabike_public_core`). Fases 0 y 1 de
`docs/architecture/storefront-html-migration-plan.md`: fichas de producto,
`/productos` (con búsqueda y filtros) y las páginas de categoría, hoy en una
ruta oculta (`/_html/...`) junto a las páginas Flutter que copian, con
`noindex`. Las mismas páginas responden sin el prefijo el día que
`firebase.json` les mande las rutas públicas.

- **Rutas** (`storefront_handler.dart`): `/productos`,
  `/productos/categoria/<slug>`, `/productos/<slug>/<sku>`; las viejas
  `/productos/<uuid>`, `/producto/<uuid>` y las de `product_url_aliases`
  redirigen con 301 a la ficha canónica, igual que otro nombre para el mismo
  SKU (la consulta se conserva). Una categoría desconocida o no publicada, y
  un producto que no se ve, responden 404 con su página.
- **Datos:** lecturas públicas con la llave publicable, al mismo tiempo cuando
  no dependen una de otra: `get_public_storefront_shell_v1` (ajustes, menús,
  páginas, categorías con descripción, imagen y orden) y
  `get_public_checkout_capabilities`; la ficha con
  `get_public_product_page_v1`; el catálogo con
  `get_public_products_faceted_v2`, `get_public_product_facets_v2` (también los
  conteos por categoría y «Todas», como Flutter) y
  `get_public_spec_option_labels_v1`. No guarda nada entre visitas.
- **Reglas:** ninguna propia. Lo que decide qué categoría abre una URL, qué
  filtros técnicos se ofrecen, títulos y descripciones, `noindex` y canónica,
  el nodo `BikeStore`, los medios de pago del pie y el texto SEO de la ficha
  vienen del núcleo, el mismo código que usa Flutter.
- **Páginas:** componentes Jaspr que sólo corren en el servidor. Sin
  JavaScript la página está completa: los filtros y el orden son formularios
  GET, el menú y los filtros del teléfono se abren con una casilla, y
  «Agregar al carrito» lleva al carrito. Con JavaScript, `storefront_script.dart`
  escribe el carrito que lee la tienda Flutter (la prueba
  `test/unit/storefront_html_cart_contract_test.dart` corre ese script en Node
  y lo lee con `PersistedCart`), aplica un filtro al marcarlo, cambia la foto y
  manda a GA4 y al píxel los eventos de Flutter (`view_item`, `add_to_cart`,
  `contact`, `store_ready`). Jaspr avisa al arrancar que no hay
  `.client.dart`: es a propósito.
- **Cabeceras:** `cache-control: private, no-cache` (el borde no guarda la
  página y el botón «atrás» puede usar la copia del navegador),
  `x-robots-tag: noindex` en la ruta oculta, en un filtro o búsqueda y en un
  404; `server-timing` (`data` = lecturas, `render` = armar el HTML); gzip
  cuando el navegador lo acepta, porque ni Cloud Run ni Firebase Hosting
  comprimen una página reenviada (2026-10-05: 64 KB viajaban sin comprimir).
- **Medición:** GA4 y el píxel sólo en el dominio de la tienda y nunca en la
  ruta oculta. La marca `?sin_medir` la revisa el navegador: Firebase Hosting
  borra toda cookie salvo `__session` antes de llegar a Cloud Run, así que el
  servidor no la ve.

## Correrlo en el Mac

```bash
bash services/storefront_html/run_local.sh
```

Abre `http://localhost:4325/productos` o
`http://localhost:4325/productos/x/H911` (redirige a la ficha canónica). Lee producción, sólo lectura, con la llave publicable
del Llavero de macOS (`Vinabike ERP Supabase publishable key`) o de
`SUPABASE_PUBLISHABLE_KEY`, y sirve las fuentes y el logo desde `assets/` como
lo hace Firebase. Con `.claude/launch.json` se abre con `preview_start`
(`storefront-html`); no recarga solo: se reinicia tras cada cambio.

## Pruebas y medición

```bash
cd services/storefront_html && ../../.fvm/flutter_sdk/bin/dart test
node services/storefront_html/tool/measure.mjs "<url>" <etiqueta> 3
python3 services/storefront_html/tool/parity.py --html http://localhost:4325
python3 services/storefront_html/tool/parity.py --skus <archivo-de-skus>
```

`parity.py` compara, para cada ficha y categoría del sitemap, la página que
publica la tienda Flutter (la instantánea del build) con la del servidor HTML:
título, descripción, robots, canónica, h1, el nodo `Product` (nombre, SKU,
fotos, marca, categoría, precio, disponibilidad, ficha técnica, GTIN, modelo),
migas, los nodos de colección y `BikeStore`. Con `--skus` revisa que cada SKU
publicado abra en su ruta canónica (los sin foto dan 404 en las dos tiendas:
la regla del sitio exige foto).

`measure.mjs` bloquea Google Analytics y el píxel de Meta (2026-10-04): cada
carga abre un perfil nuevo y contaría como un usuario más de la tienda. Las
mediciones anteriores a esa fecha incluían bajar `gtag.js`.

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
