---
titulo: Estado y pendientes
resumen: qué está en vivo hoy, qué falta y de quién depende — la lista de trabajo del sitio, con fecha
fuentes: [repositorio, consolas-google, google-search-central]
archivos: [supabase/migrations/20260728223000_harden_website_navigation_seed.sql, supabase/migrations/20260728230000_add_storefront_publication_contract.sql, docs/architecture/storefront-instant-page.md, docs/architecture/storefront-html-migration-plan.md]
tablas: [website_navigation, website_settings, products, online_shipping_rate_tiers]
revisado: 2026-10-06
---

# Estado y pendientes

Se actualiza cada vez que algo cambia de estado; cada línea con su fecha.

## En vivo (2026-10-06) `[Prod]`

- Servidor HTML `core-77a7eb3f1290.server-4e272c85a24b`
  (`storefront-html-00035-xcs`, 2026-10-06): las categorías y las fichas
  dibujan sus plantillas; sin ninguna guardada se ven como antes
  (`/productos/categoria/categorias` es 404).
  Todo lo que ve un cliente es del servidor: el carrito, el checkout, la
  página del pedido, el portal y el login (2026-10-06, `32336525`); Flutter
  sólo arranca en los chats del portal, la descarga de la app del personal,
  `/auth/callback` y al canjear un enlace del correo.
- ERP 1.0.16 (macOS `macos-v1.0.16-339`, Android APK 2091) desde `6225e668`
  (2026-10-06): la ficha de producto como plantilla en el editor (etapa 3d);
  web `71f7b476`. Antes, el mismo día: 1.0.15 (macOS `macos-v1.0.15-335`, APK
  2090, `4243884f`: la plantilla de las 11 categorías, etapa 3c); 1.0.14 (macOS `macos-v1.0.14-332`, APK 2089, `7952cfc0`: Catálogo en
  tablas, Ajustes del sitio, versiones al guardar) y 1.0.13 (macOS
  `macos-v1.0.13-328` y APK 2088, `53b55fac`): `/productos` y las categorías
  se editan sobre su página (etapa 3a). Antes, el mismo día: 1.0.12 (`b4b4d810`, la lista
  «Secciones») y 1.0.11 (`fea927df`, `/servicios` sobre la página y la barra
  con «Guardar» siempre arriba).
- Las páginas que crea el editor (`/pagina/<slug>`) las dibuja el servidor
  HTML con texto, botón, separador, preguntas, llamado a la acción,
  características, «sobre nosotros» y los bloques de la portada (fase 5a,
  2026-10-06), y desde el 2026-10-07 también cifras, carta del taller,
  planes, testimonios, galería, equipo y franja de marcas, rediseñadas desde
  el lienzo aprobado junto con preguntas y llamado; hoy no hay ninguna
  publicada. El fondo, borde, sombra y relleno propios de un bloque los
  pinta el HTML desde el 2026-10-07, y también todo bloque agregable con
  todo lo que guarda (el lienzo con su video y sus capas de producto). Sólo
  una capa de un tipo desconocido devolvería una página a Flutter.
- Sitemap: 1.315 URL. La tienda lista 539 productos con stock y 62 servicios
  (2026-10-06, con los 7 servicios que estaban guardados como producto).
- Checkout con Mercado Pago y transferencia funcionando (desde el 2026-09-23).
- Página instantánea en fichas, categorías y portada; semántica para rastreadores.
- Merchant: suspendido («Información engañosa»), en período de bloqueo.

## Depende del dueño

| Desde | Qué | Por qué |
|---|---|---|
| 2026-09-23 | Crear una cuenta de Google Ads (gratis, sin campaña) y pasar su ID | el formulario de soporte de Merchant no avanza sin él ([merchant](merchant-y-perfil-de-google.md)) |
| 2026-09-23 | Ficha de Google: fotos, horario, pedir reseñas | reputación entra en la revisión de Merchant |
| 2026-09-24 | Fotos de 16 productos antiguos | sin foto no se listan |
| 2026-09-24 | Tarjeta «MOUNTAIN BIKE» de la portada enlaza a Cadenas | contenido del editor |
| 2026-09-24 | Crear la GitHub App (APP_ID, INSTALLATION_ID, llave privada) | sin ella «Publicar» del editor no puede disparar el build ([publicacion](publicacion-y-despliegue.md)) |
| 2026-09-24 | Marcar `contact` como evento clave en GA4 | es una configuración de la cuenta |
| 2026-09-23 | Reconectar la cuenta Google del ERP con el permiso de Search Console | el centro SEO no ve Google hasta entonces |

## Lo puede hacer un agente

El plan de SEO completo, medido contra los referentes y ordenado por impacto, está
en [seo-de-referentes](seo-de-referentes.md); lo que sigue es la lista de trabajo.

| Desde | Qué | Página |
|---|---|---|
| 2026-10-07 | Vista HTML del editor: medir el zoom de ventana en Windows (en el ERP web quedó verificada con 2450c55e: barra, «Agregar aquí», alto y escritura) | [editor](editor-del-sitio.md) |
| 2026-10-04 | **Descripciones de producto**: 29 de 1.541 publicados tienen texto; el JSON-LD y la página no tienen qué mostrar en el resto (contenido, no marcado) | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | Términos de devolución (días, quién paga, reembolso) como campos del editor, para declararlos además del link (regla 1: primero el control) | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | Los tramos de envío no tienen control en el editor y la página `/envios` los repite como texto: un cambio de tarifa hay que hacerlo en dos lados. Llevarlos al editor y que la página los lea de `get_public_online_shipping_tiers` | [checkout](checkout-y-pedidos.md) |
| 2026-10-04 | `geo` del local y `addressCountry` como `CL` (hoy «Chile»; `seo_address_country_code` sin dueño) | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | Textos de presentación de las 11 categorías visibles | [seo-de-referentes](seo-de-referentes.md) |
| 2026-10-04 | Artículos/guías en el editor (capacidad nueva) y páginas de aterrizaje de filtros | [seo-de-referentes](seo-de-referentes.md) |
| 2026-10-04 | Ver en vivo los correos de pago, preparación, retiro, envío y entrega: ningún pedido real los ha disparado (la última venta web pagada es del 3-may) | [checkout](checkout-y-pedidos.md) |
| 2026-10-04 | Avisar al taller por correo o WhatsApp cuando entra un pedido web (hoy sólo el aviso dentro del ERP) | [checkout](checkout-y-pedidos.md) |
| 2026-10-03 | Eventos GA4 que faltan: `view_item_list`, `select_item`, `remove_from_cart`, `view_cart`, `add_shipping_info`, `add_payment_info` | [medicion](medicion.md) |
| 2026-10-03 | Comparar Search Console contra la línea base del 23-sep (filtrada al sitemap) y mirar `/servicios` | [seo-tecnico](seo-tecnico.md) |
| 2026-09-24 | La tienda llama `get_public_store_data` directo además de usar la precarga (sin investigar) | [rendimiento](rendimiento.md) |
| 2026-09-24 | Imágenes pesadas: campaña de cámaras en PNG de 2 MB, WebP de 312 KB en la grilla de categorías | [rendimiento](rendimiento.md) |
| 2026-09-26 | Login `/cuenta/login` sin la dirección «Sendero» | [portal](portal-de-clientes.md) |
| 2026-10-07 | Precio de un servicio o de un plan sacado del catálogo (un campo que elija el producto), para que la carta del taller no quede vieja cuando cambia un precio | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-06 | **Lienzo del editor en HTML:** el sitio real en un visor web dentro del ERP (requisito 1 del dueño); los chats se quedan en Flutter (7 conversaciones del portal en total, 0 en 90 días) | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-06 | Pasar al HTML el canje de los enlaces de Auth (vuelta de Google en `/auth/callback`, confirmar con `code`), hoy en Flutter: el verificador PKCE ya está donde ambos lo leen | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-03 | Clave `header_nav_links` en `website_settings`: nadie la lee (los menús son de `website_navigation`); borrarla es una escritura que borra, así que se deja hasta decidirlo | [marca](marca-y-tema.md) |
| 2026-10-08 | Leer el resultado de la tarea `vinabike-store-ready-review` | [rendimiento](rendimiento.md) |
| 2026-10-04 | **Fase 0 de la migración a HTML:** anotar el costo mensual real de Cloud Run (`storefront-html`) después de unos días; lo demás está hecho y medido ([rendimiento](rendimiento.md)) | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-04 | Paridad latente de la ficha técnica: el generador de snapshots arma la identidad con `color`, `size`, `material` y `weight` leídos de `products`, y la página pública no los recibe; un producto que los tenga mostraría en el snapshot filas que la página no. 0 productos afectados hoy | [datos-estructurados](datos-estructurados.md) |

## Hecho

| Fecha | Qué | Página |
|---|---|---|
| 2026-10-07 | **Formato, fondo y video iguales en el lienzo y la tienda**: el HTML dibuja el formato del hero, la nota de testimonios, el cargo del equipo y el título de reseñas, y el color propio de las reseñas; el banner de video dibuja su formato en los dos (antes en ninguno); «Formato» se quitó donde nadie lo usaba; el título de reseñas lee el fondo real (era blanco sobre blanco en el lienzo); las diapositivas con video y el video de fondo del lienzo se dibujan en HTML. Reseñas, banner, carrusel con video, productos (destacados, lo nuevo, una categoría, carrusel), categorías, marcas con superficie, lienzo con video o con capas de producto y llamado de alto fijo con relleno ya no mandan la página a Flutter (el lienzo Flutter lee ahora el catálogo como la tienda: en stock, enlaces por SKU). Una prueba de contrato exige que todo «Formato» del esquema se dibuje | [editor](editor-del-sitio.md) |
| 2026-10-07 | **Contenido real y visible en el HTML** (brecha 1 de SEO, del 2026-10-04): con la tienda en HTML, la ficha medida trae 390 palabras y 90 enlaces sin JavaScript (antes 13 y 3), la categoría Componentes 575 y 133, sin `<noscript>` | [seo-de-referentes](seo-de-referentes.md) |
| 2026-10-07 | **El lienzo muestra el catálogo del cliente**: Editar cargaba también lo no publicado y lo agotado (1.615 en `/productos` contra 538) y lo filtraba en la app; ahora pide al servidor como la tienda. 537 y 425 en Componentes, igual que vinabike.cl | [editor](editor-del-sitio.md) |
| 2026-10-07 | **Código muerto fuera**: `banners_management_page.dart`, `content_management_page.dart`, `customer_account_page.dart`, `premium_dashboard_widgets.dart` y las páginas viejas del chat (`customer_chat_list_page.dart`, `customer_chat_detail_page.dart`); `/cuenta/mensajes` y `/cuenta/mensajes/:id` redirigen ahora al centro de chats (`/cuenta/chats`) | [portal](portal-de-clientes.md) |
| 2026-10-07 | **Carrusel en teléfono: las flechas ya no tapan el texto** (pendiente del 2026-09-24): en la portada HTML van abajo, a los lados de los puntos; comprobado en vivo a 390 px | `storefront-instant-page.md` |
| 2026-10-07 | **Secciones del lienzo aprobado y bloque canvas** (`6e1eed56`, `1631d5aa`): cifras, carta, planes, testimonios, galería, equipo, preguntas, franja y llamado en Flutter y HTML; `canvas` en HTML salvo capas de producto o video; ningún valor inicial inventa cifras, plazos ni certificaciones; el texto de una capa ya no se corta en el lienzo. Y el **índice de las listas**: las secciones y `features` escriben en la posición guardada, y un carrusel deja fuera las entradas que no son diapositivas al normalizarse | [editor](editor-del-sitio.md) |
| 2026-10-07 | **Vista HTML: los textos se escriben ahí mismo** (servidor `8ef44635`→`d24c5da2`, Cloud Run `00046`→`00048`): con el bloque elegido, otro clic en un título o texto lo vuelve editable en la página; al salir se escribe por el mismo arriendo que el lienzo (un paso del historial; rechazado si el borrador cambió entretanto), Esc lo cancela. El carrusel no avanza solo en el borrador. Probado en macOS contra producción: título del carrusel escrito en el HTML, visto en el panel y redibujado, deshecho en un paso; Esc en el subtítulo; marco de tableta. Defecto anterior corregido: un bloque dibujado por banda se marcaba en su copia oculta | [editor](editor-del-sitio.md) |
| 2026-10-07 | **Vista HTML: pie sin guardar, barra del bloque y revisión de Codex** (`b3f4a4e7`→`3f6eba7b`): el pie según el borrador llega al HTML; el bloque elegido trae su barra (subir, bajar, ocultar, duplicar, copiar, eliminar); mover una sección del pie ya no deja el pie sin dibujar (defecto publicado desde `8e01c879`); la sesión del editor sólo va al servidor fijado en la compilación; los clics llegan en todo el ancho bajo el zoom; el inicio muestra su borrador | [editor](editor-del-sitio.md) |
| 2026-10-07 | **La vista HTML dibuja cualquier página de la tienda** (`7e269eb9`→`5b1d5577`, Cloud Run `00038`→`00040`): catálogo, servicios, categorías, ficha de producto e información, con los borradores de portadas, plantilla de categoría y plantilla de ficha, por el mismo manejador que atiende las visitas. Un clic elige el bloque, el encabezado, el pie o la sección del catálogo o de la ficha; el puntero la marca con su nombre. Probado en macOS contra producción: portada de «Componentes» cambiada en el panel y vista en HTML en ~3 s, botón de la ficha cambiado igual, selección por clic en las tres clases de página | [editor](editor-del-sitio.md) |
| 2026-10-07 | **Vista HTML en el editor** (fases 5b y 5c de la migración): el servidor dibuja la portada o una página del editor desde el borrador sin guardar (`POST /_html/editor/borrador`, sólo para quien puede guardar el sitio) y el ERP la muestra sobre el lienzo con el botón `<>`; un clic elige la sección en el panel. Probado en macOS contra producción (Cloud Run `00037`) | [editor](editor-del-sitio.md) |
| 2026-10-07 | **El catálogo ya no se cae con varias visitas juntas.** Con ~12 visitas a la vez la base cortaba las lecturas del catálogo al pasar los 3 s de `anon` (500) y el servidor HTML respondía «La tienda no pudo leer esta página» (503) a la página entera: 22 veces a PerplexityBot el 2026-10-06 y 8 de 12 en una ráfaga de prueba el 2026-10-07. Tres arreglos de raíz, sin caché: las **lecturas hacen menos y devuelven lo mismo** (`20261007020000`; filtros de una categoría 399 → ~65 ms, comparado fila a fila contra la versión anterior en producción); el **servidor deja pasar cuatro consultas a la vez** y las demás esperan su turno (`DatabaseGate`), además de compartir las lecturas idénticas en camino; y si los filtros fallan igual, la página **lista sus productos** y conserva los filtros activos, que se dibujan marcados aunque queden en 0. Un índice mantenido por disparadores se intentó y se descartó tras dos revisiones de Codex (nueve defectos de concurrencia) | [rendimiento](rendimiento.md) |
| 2026-10-06 | **El cuelgue de debug al pasar del catálogo a una categoría o a una ficha** (la vista previa de la tienda dentro del ERP): el `Navigator` de la tienda (`StatefulShellRoute` de `/tienda/*`) vive dentro del único scroll de `PublicStoreLayout`, así que su `Overlay` recibe alto infinito y se mide por la página de arriba; una página tapada en la misma rama (el catálogo bajo la categoría, la categoría bajo la ficha) seguía montada pero el `Overlay` no la vuelve a medir. La segunda vez que esa página tapada cambiaba (llegan sus datos o una foto) Flutter 3.38.5 lanzaba `_debugRelayoutBoundaryAlreadyMarkedNeedsLayout` en plena medición, el frame quedaba a medias y el proceso de debug creció a **35 GB en ~12 minutos** hasta agotar la memoria del Mac. El diagnóstico anterior de esta lista (la raíz de `ProductCatalogPage`, el visor `storefront_content_viewport`) **era falso**: la prueba mínima lo reproduce sin la tienda. Arreglo: las páginas del shell no se mantienen tapadas (`buildPublicStoreShellPage`, `maintainState: false`) y se rearman al volver; prueba `public_store_shell_covered_page_test` (falla sin el arreglo) y recorrido en la app catálogo → Accesorios → ficha, ida y vuelta, en 0,74 GB. En Release no había aserción; ahí sólo cambia que la página tapada deja de cargar en segundo plano | [editor](editor-del-sitio.md) |
| 2026-10-06 | **Rediseño del editor completo** (propuesta aprobada, «dale, construye la propuesta del editor», https://claude.ai/artifact/Eg75Q9vj2oZYWKiyGFDCHU): etapa 1 (`/servicios` sobre la página), 2a (barra con Páginas, Catálogo y Ajustes del sitio y «Guardar» siempre visible), 2b (lista «Secciones»), 3a (`/productos` y las categorías sobre su página), 3b (Catálogo en tablas, todo lo de una categoría en su página, Ajustes del sitio con índice, versiones al guardar, copiar y pegar secciones; ERP 1.0.14), 3c (una plantilla para las 11 categorías; ERP 1.0.15, Cloud Run `00034`) y 3d (la ficha de producto como plantilla en el lienzo, con despacho y retiro editables; ERP 1.0.16, Cloud Run `00035`). Codex revisó cada etapa | [editor](editor-del-sitio.md) |
| 2026-10-06 | **`/servicios` como lista de precios**, en vivo (`91360c26`, Cloud Run `storefront-html-00032-fxr`, fuente `core-bfcba35e141d.server-fc5aa6abc72c`): portada con WhatsApp y la calificación de Google, las 3 mantenciones como planes con lo que incluye cada una, los otros 59 servicios en 9 grupos con buscador y la banda de cierre; configurado desde el editor (`Catálogo web > Presentación > Todos los servicios`) y leído de vuelta en la base. Antes del deploy, Codex revisó en dos pasadas (8 hallazgos y 3 de los arreglos, corregidos con pruebas) | [catálogo](catalogo-y-fichas.md) |
| 2026-10-06 | **El login en HTML** (fase 4c): entrar, crear la cuenta, Google y «¿Olvidaste tu contraseña?», con Supabase Auth desde el navegador y la sesión y el verificador donde los lee Flutter; los enlaces del correo siguen en Flutter; al píxel de Flutter a 1440, 900 y 412 px y 60 comportamientos en los dos anchos contra un Supabase falso; revisión de Codex con 3 arreglos; el teléfono de la cuenta nueva ya no se pierde | [portal](portal-de-clientes.md) |
| 2026-10-06 | **Perfil y direcciones en HTML** (fase 4b): datos, contraseña (con código y cierre de las demás sesiones), agregar, editar, principal y borrar una dirección con la búsqueda de Maps; se guardan por `POST /cuenta/accion` como el cliente; al píxel de Flutter a 1440 y 412 px y 52 comportamientos verificados. En las dos tiendas: borrar el RUT o el teléfono ya los borra, un obligatorio con espacios no pasa y las fechas de una dirección van en UTC | [portal](portal-de-clientes.md) |
| 2026-10-06 | **Las páginas de lectura del portal en HTML** (fase 4a): `/cuenta`, pedidos, taller (con `?bike_id=`) y bicicletas los dibuja el servidor leyendo Supabase como el cliente, sin guardar su sesión; fichas de trabajo y de bici, filtros y archivos del trabajo; al píxel de Flutter a 1440 y 412 px. El marco se lee a los 1,6 s en un teléfono lento contra 18,4 s de Flutter | [portal](portal-de-clientes.md) |
| 2026-10-06 | **Menú ancho de escritorio como Flutter en las páginas HTML:** «Componentes» abría una lista simple; ahora el panel con pestañas por rama, foto de la sección, tarjetas, subniveles y «VER TODO», a ±0,1 px de Flutter a 1440 y 1100 px y con sus tiempos | [rutas](rutas-y-navegacion.md) |
| 2026-10-06 | **Encabezado con sesión y menú del teléfono como Flutter:** con sesión, las páginas HTML seguían diciendo «Iniciar sesión»; y el menú del teléfono mostraba «Accesorios» como grupo vacío, con letra más chica que Flutter | [rutas](rutas-y-navegacion.md) |
| 2026-10-06 | **La página del pedido en HTML** (fase 3c): al píxel de Flutter en los seis estados, el regreso de Mercado Pago (verificado antes de creerle a la dirección) y sin acceso, a 1440 y 412 px; el resumen en PDF lo arma el servidor con el mismo código que la app; de punta a punta en la base local desde el checkout HTML | [checkout-y-pedidos](checkout-y-pedidos.md) |
| 2026-10-06 | **`/checkout` abierto al servidor HTML** (d487113c): `noindex`, líneas y paso desde Flutter verificados en vivo | [checkout-y-pedidos](checkout-y-pedidos.md) |
| 2026-10-06 | **Clientes con sesión vuelven a pagar por transferencia:** desde el 11-jul la base deshacía su pedido al procesarlo (sólo pasaban invitados y personal); arreglado en `20261006090000`, probado en local y verificado en producción | [checkout-y-pedidos](checkout-y-pedidos.md) |
| 2026-10-06 | **El checkout en HTML** (fase 3b) en la ruta oculta `/_html/checkout`: al píxel de Flutter a 1440 y 412 px; en la base local crea pedidos por transferencia, Mercado Pago y retiro, con sesión del cliente, y recupera el mismo pedido si se pierde la respuesta; sus registros los lee la página del pedido de Flutter (prueba de contrato) | [checkout-y-pedidos](checkout-y-pedidos.md) |
| 2026-10-06 | **El carrito en el servidor HTML** (fase 3a): líneas en pantalla a los 1,2–1,5 s en un teléfono lento contra 18,4 s de Flutter, al píxel de Flutter a 1440 y 412 px, con los mismos totales; +, − y eliminar escriben el mismo carrito que lee el checkout Flutter | [checkout-y-pedidos](checkout-y-pedidos.md) |
| 2026-10-06 | **El sitio vuelve a costar CLP 0**: Hosting había cobrado CLP 2.911 (2–5 oct) por rastreadores de IA bajando la tienda Flutter y versiones guardadas sin límite; con el HTML los rastreadores bajan ~73 MB cada 12 h, cada sitio guarda 50 versiones y Artifact Registry borra imágenes viejas. La foto de cámaras del carrusel pasó de 2,1 MB a 118 KB por el editor | [publicacion-y-despliegue](publicacion-y-despliegue.md) |
| 2026-10-05 | **Flutter deja la página a las rutas HTML** (fase 2f): desde el carrito o la cuenta, «Inicio», «Productos» o el pie cargan la página del servidor; los enlaces `?category=<id>` de los bloques salen con la ruta limpia (sin 301); «Productos destacados» baja la copia pequeña de la foto optimizada. Portada en un teléfono lento: foto principal 2,7 s, carga 2,8 s | [rendimiento](rendimiento.md) |
| 2026-10-05 | **`/contacto` en el servidor HTML** (fase 2e): datos, horario, WhatsApp, redes y el formulario con los mensajes de Flutter, medidos al píxel a 1440 y 412 px. Arreglado en las dos tiendas: el botón de Instagram de Contacto llevaba a `instagram.com/https://…` porque el ajuste guarda la dirección completa | [rutas](rutas-y-navegacion.md) |
| 2026-10-05 | **`/servicios` en el servidor HTML** (fase 2d): el catálogo de servicios del taller con el mismo título para Google que la instantánea y cada servicio con su precio en el JSON-LD; el generador deja de escribir su archivo. En todo el catálogo, la columna de resultados sube 2 px a la posición de Flutter | [rutas](rutas-y-navegacion.md) |
| 2026-10-05 | **Portada `/` abierta al servidor HTML** (fase 2c): la entrada de Flutter pasa a `app.html` (destino de `**`) y el generador borra el `index.html` raíz, que Hosting servía antes que la reescritura. En un teléfono lento la portada muestra su texto en ~1 s y la foto principal en ~4,8 s; Flutter dibujaba su primer cuadro a los ~20 s. Las fotos de las diapositivas siguientes esperan su turno y el pie en tableta sigue el `Wrap` de Flutter | [rutas](rutas-y-navegacion.md) |
| 2026-10-05 | **Portada en HTML** (fase 2b, ruta oculta `/_html/`): encabezado sobre el carrusel, carrusel con la diapositiva compuesta, productos, categorías, marcas, video y reseñas en las mismas coordenadas que Flutter a 1440 y 412 px. En todas las páginas HTML: el ítem actual del menú en el color del encabezado (no azul), «Iniciar sesión» de 40 px y los medios de pago alineados arriba. `/` sigue en Flutter hasta abrirla | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-05 | **Páginas de información abiertas al servidor HTML**: `/nosotros`, `/envios`, `/devoluciones`, `/terminos` y `/privacidad` con reescrituras exactas; el generador deja de escribir sus instantáneas y la publicación las revisa en los dos orígenes | [rutas](rutas-y-navegacion.md) |
| 2026-10-05 | **Páginas de información en HTML** (fase 2a, ruta oculta `/_html/<slug>`): marco, héroe, secciones y contacto en los mismos píxeles que Flutter a 1440 y 412 px, medidos con el árbol de semántica de Flutter. La normalización de bloques, la composición y los colores del tema son del núcleo, no copias. En las dos tiendas: el bloque de contacto ya no muestra al visitante «Completa tus datos de contacto desde el editor» (usa Configuración → Contacto) y el chip de la página actual va sin el disco del visto | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-05 | **La tienda HTML se ve como la Flutter** (el dueño vio tarjetas rotas): tarjeta y grilla de `websiteCatalogGridMetrics`, riel con el árbol de radios, hojas «Filtro / Ordenar por» en el teléfono, paginador, pie de escritorio y de teléfono, ficha con cantidad − +, «Agregado al carrito» y «Comprar ahora»; medido a 1 px a nueve anchos (`3f12435c`) | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-05 | **Miniaturas de tarjeta** (opción gratis que eligió el dueño): copias de 400 y 800 px de las 1.294 fotos de tarjeta en `public_image_thumbnails`, hechas por `generate_public_image_thumbnails.dart` en cada publicación; las tarjetas HTML las ofrecen en `srcset` (120 KB → 20 KB por foto en un teléfono). Un producto sin SKU se dibuja en `/productos/<uuid>` (`get_public_product_page_v2`) | [rendimiento](rendimiento.md) |
| 2026-10-05 | **Rutas públicas abiertas a la tienda HTML** con el sí del dueño al costo (alerta de presupuesto de CLP 4.800 ≈ US$5): `/productos`, categorías, fichas y `/producto/<uuid>` las responde Cloud Run; el build deja de escribir sus instantáneas (`SeoServerRenderedRoutes`) y la publicación de la tienda revisa el servidor en los dos orígenes, incluida su fuente (`check_storefront_html_routes.mjs`). Las 5 fichas con espacio en el SKU, que la instantánea servía con la portada, quedan bien | [rutas](rutas-y-navegacion.md) |
| 2026-10-05 | **Fase 1 de la migración a HTML** en la ruta oculta: `/productos`, categorías y fichas con encabezado, pie, carrito compatible con Flutter, GA4/píxel, `noindex`/canónica/301/404; las 1.290 fichas comparables idénticas a la instantánea Flutter (las otras 5 son un defecto de la instantánea) y las 12 colecciones salvo el orden de su lista; revisión de Codex (1 P1, 4 P2, 1 P3) corregida con pruebas. Requisitos de la fase 0 resueltos: ficha técnica en una pasada (`20261005090000`), `BikeStore`, menús, submenús, set availability en la lectura | `docs/architecture/storefront-html-migration-plan.md` |
| 2026-10-05 | Filtros técnicos `spec.<clave>` en la URL ahora son `noindex` también en Flutter; categorías con nombre repetido abren igual en Flutter y HTML (regla en el núcleo) | [catalogo](catalogo-y-fichas.md) |
| 2026-10-04 | Servidor HTML en Cloud Run (`storefront-html`, `southamerica-east1`) detrás de la reescritura `/_html/**` del target `store`. El dueño instaló `gcloud`, inició sesión y dio `roles/run.builder` a la cuenta de compilación | [mapa](mapa-del-sistema.md) |
| 2026-10-04 | El dueño aprobó la migración del sitio y su editor a HTML. Fase 0 en local y en la base: núcleo Dart en `packages/vinabike_public_core` (18 archivos movidos, sin copiar), `get_public_storefront_shell_v1` + `get_public_product_page_v1` desplegadas y verificadas (`20261004180000`, `20261004190000` tras la revisión de Codex), servidor Jaspr con pruebas | [mapa](mapa-del-sistema.md) |
| 2026-10-04 | Ficha técnica (`additionalProperty`), `model` y migas completas en el JSON-LD de cada producto, con un solo armado para el snapshot y la página | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | `BikeStore` con logo, imagen, mapa, horario y link a la política de devoluciones. El envío se dejó fuera: Google no puede acotar «Chile continental» | [datos-estructurados](datos-estructurados.md) |
| 2026-10-04 | El script que evita la doble navegación de un enlace de Flutter llega por fin a producción (estaba sólo en `web/index.html`, que el build regenera) | [publicacion](publicacion-y-despliegue.md) |
| 2026-10-04 | Descartado: quitar `Disallow` de `/pedido/` en `robots.txt`. Esas URL llevan el token privado del pedido; con el bloqueo Google nunca las abre, y la cabecera `noindex` cubre el caso de que alguna se filtre | [rutas](rutas-y-navegacion.md) |

## Migraciones en git, no en producción

| Migración | Estado | Efecto |
|---|---|---|
| `20260728223000_harden_website_navigation_seed` | `NOT_APPLIED` (2026-10-03) | el editor llama `ensure_default_footer_navigation` (`website_service.dart:4350`) y esa función no existe en producción |
| `20260728230000_add_storefront_publication_contract` | `NOT_APPLIED` (2026-10-03) | registro de publicaciones del editor; espera la GitHub App |

Antes de aplicarlas: revisar si otra migración posterior ya tocó lo mismo (una
migración vieja no se aplica tal cual; ver «Schema changes» en
`docs/development/AGENT_DATABASE_CONTRACT.md`).

## En el código y la base

- Lo vivo: `https://vinabike.cl/release.json`, el `sitemap.xml` y
  `scripts/db/query.sh production`; migraciones: `scripts/db/migration_status.sh`.
- Cada fila apunta a la página del tema, que tiene sus archivos y tablas.
