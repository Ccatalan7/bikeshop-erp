# Tienda en HTML

La tienda pública armada como HTML en el servidor, una página por visita, con el
mismo código Dart que el ERP (`packages/vinabike_public_core`). Fases 0 y 1 de
`docs/architecture/storefront-html-migration-plan.md`: fichas de producto,
`/productos` (con búsqueda y filtros) y las páginas de categoría. Desde el
2026-10-05 responde las rutas públicas que `firebase.json` le reescribe
(`/productos`, `/productos/**`, `/producto/**` y, desde la fase 2a, las cinco
páginas de información) y una copia con `noindex` en `/_html/...`. La
portada se dibuja en `/_html/`, pero `/` sigue en Flutter hasta abrirla; las
demás páginas del editor, carrito, checkout y portal siguen en Flutter.

- **Rutas** (`storefront_handler.dart`): `/productos`,
  `/productos/categoria/<slug>`, `/productos/<slug>/<sku>`; las viejas
  `/productos/<uuid>`, `/producto/<uuid>` y las de `product_url_aliases`
  redirigen con 301 a la ficha canónica, igual que otro nombre para el mismo
  SKU (la consulta se conserva). Una categoría desconocida o no publicada, y
  un producto que no se ve, responden 404 con su página. `/nosotros`,
  `/envios`, `/devoluciones`, `/terminos` y `/privacidad`: la página del
  editor con sus bloques; sin nada que leer, 404 con el mensaje de Flutter.
  `/`: la portada del editor (`is_home`) con su encabezado sobre el primer
  bloque, y los productos que sus bloques eligen (`get_public_products` con
  `p_product_ids` y sólo con stock); sin portada publicada, 404. Un bloque que
  aún no se dibuja se nombra en `x-storefront-uncovered`.
- **Datos:** lecturas públicas con la llave publicable, al mismo tiempo cuando
  no dependen una de otra: `get_public_storefront_shell_v1` (ajustes, menús,
  páginas, categorías con descripción, imagen y orden) y
  `get_public_checkout_capabilities`; la ficha con
  `get_public_product_page_v2` (por SKU, o por id para un producto sin SKU,
  que vive en `/productos/<uuid>`); el catálogo con
  `get_public_products_faceted_v2`, `get_public_product_facets_v2` (también los
  conteos por categoría y «Todas», como Flutter) y
  `get_public_spec_option_labels_v1`, y las copias de 400 y 800 px de las fotos
  de sus tarjetas con `get_public_image_thumbnails_v1`, en la misma vuelta que
  completa las filas; las páginas de información leen `website_pages` con sus
  `website_blocks` (filtro `tenant_id` en las dos). No guarda nada entre
  visitas.
- **Fotos de tarjeta:** cada tarjeta ofrece en `srcset` las copias que hizo
  `scripts/generate_public_image_thumbnails.dart` (corre en cada publicación
  de la tienda y a mano para rellenar) y la foto original; una foto que el
  trabajo todavía no copió se muestra grande. La precarga de la primera
  tarjeta lleva los mismos candidatos, para que se baje una sola vez.
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
  y lo lee con `PersistedCart`; vive en la raíz, no en este paquete, así que
  `dart test` de aquí no la corre: tras tocar el guion se corre a mano. Su DOM
  es mínimo —`document.querySelector`/`querySelectorAll` y un formulario que
  sólo tiene `addEventListener`—, así que el guion busca siempre desde
  `document`; un `form.querySelectorAll` tumbó las cuatro compuertas de la
  publicación 48f43cfc el 2026-10-05), aplica un filtro al marcarlo, cambia la foto y
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

**Se publica desde un commit, y cada cambio del núcleo lo vuelve a pedir.**
El script se niega si hay cambios sin commit en lo que compila la imagen
(`tool/source_id.sh`: `lib` y `pubspec.yaml` del núcleo; `bin`, `lib`,
`pubspec.*` y `Dockerfile` de este servicio) y estampa ese nombre en
`STOREFRONT_SOURCE`; cada respuesta lo trae en `x-storefront-source`. La
publicación de la tienda (`scripts/releases/check_storefront_html_routes.mjs`)
falla si Cloud Run corre otra fuente que la del commit que publica: el núcleo
lo comparten la tienda Flutter, que se publica sola con cada push, y este
servidor, que no; sin republicarlo, las dos tiendas dejan de decir lo mismo.
Orden: commit, `deploy_cloud_run.sh`, push. Y nunca mientras una
publicación anterior de la tienda no haya pasado su revisión del servidor:
esa revisión compara Cloud Run con *su* commit, y fallaría con el servidor
nuevo (2026-10-05).

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
