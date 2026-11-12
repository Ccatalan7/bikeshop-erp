---
titulo: Consolas de Google (Search Console, GA4, Merchant)
resumen: lo que Google dice del sitio, medido con fecha; cómo entrar y cómo no leerlas mal
tipo: interna
revisado: 2026-11-11
---

# Consolas de Google `[Consola]`

Search Console (propiedad de dominio `vinabike.cl`), Google Analytics 4 (flujo
web con `G-FR5Q37BW43`) y Merchant Center (cuenta 5635601285). Las administra la
cuenta Google de Viñabike, que en el Chrome del dueño está en el índice `/u/2`
(la `/u/0` es otra cuenta sin propiedades). En GA4 se entra con
`?authuser=2`: con `authuser=1` abre «Welcome to Google Analytics», que parece
falta de acceso y es sólo la cuenta equivocada (2026-10-04). Se leen con la
extensión Claude in Chrome; el navegador integrado sirve para páginas públicas.

## Mediciones archivadas

| Fecha | Consola | Qué se midió |
|---|---|---|
| 2026-09-23 | Search Console | sitemap del 20-sep filtrado: 524 de 549 indexadas; todas las conocidas: 797 indexadas y 2.425 no (suma de motivos); 613 «página alternativa con canonical»: 606 `/productos/`; enlaces: 17 internos, 0 externos |
| 2026-09-23 | Search Console | `/productos/` en 3 meses: 175 clics, ~7 mil impresiones repartidas en > 1.000 URL, la mejor con 5 clics, en baja |
| 2026-09-23 | Prueba de resultados enriquecidos (render de Google, ficha) | Flutter monta; 4 elementos válidos; 2 `<a>` y ambos dentro de `<noscript>` (antes del arreglo) |
| 2026-09-24 | Prueba de resultados enriquecidos (ficha S56467) | 11 `<a href>` fuera de `noscript` tras la semántica para rastreadores |
| 2026-09-23 | Search Console | sitemap reenviado (lee 1.309 URL); indexación pedida para `/` y `/servicios` (éste «Rastreada: sin indexar», último rastreo 7-may) |
| 2026-09-23 | GA4 | llegan `view_item`, `add_to_cart`, `begin_checkout`, `contact`; `purchase` probado con un pedido de prueba (anulado) |
| 2026-09-24 | GA4 | dimensión personalizada «Tramo de carga» = `load_bucket` registrada |
| 2026-10-04 | GA4 (6-sep→3-oct) | 1.185 vistas: 279 fuera de vinabike.cl, 515 de vinabike.cl desde Estados Unidos (Seattle = el Mac del dueño y los agentes), 391 de clientes; ver [medicion](../paginas/medicion.md) |
| 2026-09-23 | Merchant | «Información engañosa»; apelación del 27-dic-2025 rechazada; consola en período de bloqueo sin fecha; información de empresa igual a la web; feed «PRODUCTS SOURCE 2» 66/66 con precio y stock iguales a `get_public_products` |
| 2026-09-24 | PageSpeed Insights (móvil, portada) | 62 → 38 tras la portada instantánea (LCP simulado 18,2 s con la foto pintada a 1,3 s en la traza); ver [rendimiento](../paginas/rendimiento.md) |
| 2026-10-14 | Search Console (API, `web_presence_search_daily`) | antes y después de los cambios SEO del 23-sep: 4→22 sep 2,2 clics y 69 vistas al día, posición 12,6; 23 sep→12 oct 3,3 clics y 104 vistas al día (+50 %), posición 9,9. En 16 meses: el máximo fue junio de 2026 (138 vistas/día), septiembre bajó a 79 y octubre va en 110 |
| 2026-10-14 | Search Console (API, consultas) | el taller sube: «taller de bicicletas» posición 27,3 → 11,6 con el doble de vistas, «taller bicicletas» 16,3 → 5,8, «arreglo de bicicletas» 19,1 → 4,8, «reparacion de bicicletas» 46,5 → 2,8, «taller de bicicletas cerca de mi» 47,2 → 2,4; la portada 16,0 → 7,0 (605 → 1.255 vistas, 22 → 43 clics); aparecen `/servicios` y `/guias/*` |
| 2026-10-14 | Search Console (interfaz) | 1.030 páginas indexadas en total (797 el 23-sep); filtrado al sitemap sólo 88 de ~1.400 (informe del 8-oct): el 8-oct cambiaron 1.264 direcciones de producto y las viejas responden 301, Google las recorre de a poco |
| 2026-10-14 | Search Console (inspección de URL, `web_presence_urls`) | de 807 direcciones del sitemap revisadas: 373 indexadas, 330 descubiertas sin rastrear, 86 que Google no conoce, 9 «noindex» y 7 «alternativa» con último rastreo de agosto–septiembre (la tienda Flutter; hoy responden `index,follow`) |
| 2026-10-14 | GA4 (interfaz) | desde el 23-sep: sesiones orgánicas +66 % por día, sesiones con interés 65 % → 80 %, aparece el canal «AI Assistant», 1 compra real (WEB-26-00021); «Directo» inflado por las visitas propias (Seattle) |
| 2026-10-29 | Search Console (API, `web_presence_search_daily`, al 28-oct) | octubre 1→28 es el mejor mes en 16: 139 clics y 4.621 vistas (165 al día; junio, el máximo anterior, 138), posición 11,8. Por semana: 60 vistas al día (14-sep) → 168 (12-oct) → 217 (19-oct) → 236 (26→28-oct); clics 7 → 45 → 38 → 23 en tres días |
| 2026-10-29 | Search Console (API, páginas, octubre contra septiembre) | portada 1.506 → 2.070 vistas y 52 → 101 clics, posición 12,0 → 6,4; `/servicios` 7 → 105 vistas en posición 5,9 y 0 clics; guías 469 vistas, 2 clics, posición 6; categorías 6 → 412 vistas en **posición 35** (5 clics); fichas 808 → 1.731 vistas, 30 clics, posición 12; unas 30 direcciones viejas `/productos/<uuid>` (301 a la nueva) suman 780 vistas en posición 26. Páginas distintas con vistas: 343 en septiembre, 712 en octubre (1.117 en junio, la tienda Flutter); búsquedas distintas 195 → 363, el máximo |
| 2026-10-29 | Search Console (API, consultas por familia y semana) | «taller», arreglo, reparación y mantención: 67–83 vistas por semana a inicios de septiembre en posición 13–27 → 125–154 desde el 21-sep en posición ~7, con 2–6 clics por semana; «tienda» y «bicicletas viña del mar»: 30–52 → 78–98 vistas, 4–9 clics; repuestos: 28–51 → 101–237 vistas (desde la tienda HTML del 8-oct) en posición ~40 y 0–2 clics; la marca «viñabike» 2–8. Sólo 1.318 de las 4.621 vistas de octubre traen la consulta (Google oculta las raras) |
| 2026-10-29 | Search Console (inspección de URL, `web_presence_index_daily`) | sitemap de 1.323 direcciones (1.238 fichas, 70 categorías, 6 guías, 8 páginas y la portada; leído por Google el 28-oct): indexadas 598 de 1.283 (47 %) el 14-oct → 812 de 1.323 (61 %) el 29-oct. Portada, páginas y guías 15/15; categorías 56/70; fichas 741/1.238 (365 descubiertas sin rastrear, 115 que Google no conoce). Las 14 «noindex» y 8 «alternativa» son lecturas de la tienda Flutter (último rastreo jul–sep): en vivo responden `index,follow` con su canonical |
| 2026-10-29 | GA4 (API, `web_presence_traffic_daily`, sólo Chile) | octubre 1→28: 263 sesiones (máximo; julio 155), 165 orgánicas (julio 132), 24 de «AI Assistant» (antes 0–4 al mes), 70 % con interés; eventos: 851 `view_item_list`, 234 `view_item`, 13 `contact`, 6 `begin_checkout`, 3 `add_to_cart`, 1 `purchase` |
| 2026-11-11 | Search Console (API, `web_presence_*`, 26-ago→22-sep contra 14-oct→10-nov) | clics 68 → 163, apariciones 2.222 → 5.884, posición 12,6 → 11,9, clics por aparición 3,1 % → 2,8 %. Noviembre 1→10: 6,3 clics y 217 apariciones al día, el máximo de 16 meses (octubre 4,9 y 169). Por tema: taller 336 → 581 apariciones, puesto 17 → 7, clics 4 → 10; tienda en Viña 101 → 290, 12,3 → 7, 3 → 20; repuestos genéricos 204 → 712, 33 → 39, 2 → 3. «taller de bicicletas viña del mar»: puesto 3, 116 apariciones, 3 clics. Sólo el 28 % de las apariciones trae la consulta. Clics por tipo: portada 96, fichas 48 (puesto 16), categorías 11 (puesto 34), servicios y guías 7 de 859 apariciones (puesto 6) |
| 2026-11-11 | Search Console (inspección de URL, `web_presence_index_daily`) | sitemap de 1.345: indexadas 598 de 1.283 (47 %) el 14-oct → 1.082 (80 %) el 11-nov; quedan 152 descubiertas sin indexar, 77 que Google no conoce, 14 rastreadas sin indexar y 15 «noindex» de la tienda Flutter |
| 2026-11-11 | Search Console (interfaz) | todas las conocidas: 1.455 indexadas y 3.107 no (797 y 2.425 el 23-sep); métricas web principales en celular: 94 buenas, 0 mejorables, 0 lentas (escritorio sin datos); fragmentos de productos y fichas de comerciante 55 válidas, 0 con error; migas 84/0; enlaces internos 21.976 (17 el 23-sep), externos 1 (bicicletaz.com, texto «sitio web»); acciones manuales: ninguna |
| 2026-11-11 | GA4 (interfaz, 14-oct→10-nov, todo el sitio) | 416 sesiones: google 210, directo 100, chatgpt.com 52, accounts.google.com 15, bing 14, gemini.google.com 5. Desde ChatGPT se llega a 31 páginas distintas, casi todas fichas y categorías de repuestos. Personas por evento: 300 en total, 267 `view_item_list`, 206 `view_item`, 6 `add_to_cart` (13 veces), 2 `view_cart` (3), 0 `begin_checkout`, 17 `contact` (20) |
| 2026-11-11 | GA4 (API, sólo Chile) y base | sesiones 103 → 337 (26-ago→22-sep contra 14-oct→10-nov), orgánicas 75 → 203, asistentes de IA 0 → 57, con interés 66 % → 61 %. Pedido web real WEB-26-00022 (11-nov, corona Deckas 38T AE0118): esa ficha tuvo 24 apariciones y 0 clics en Google y 3 visitas desde ChatGPT. Reseñas de la ficha: 36 (4,4) el 8-oct → 42 (4,5); 21 pedidos de reseña por WhatsApp desde el 5-nov y 3 reseñas de 5 estrellas en las 24 h siguientes al primer envío. Informe con gráficos: «Viñabike en Google» (artifact `5oabsvDAuafHyZGteuskyM`) |

## Cómo leerlas sin equivocarse

- **Search Console, indexación:** la vista por defecto suma todas las URL que
  Google conoce (redirecciones, alternativas, viejas). Para juzgar la
  publicación, filtrar **al sitemap enviado** y anotar la fecha del informe junto
  a la del build (`/release.json`). Sumar las filas de motivos en vez de leer la
  tarjeta redondeada.
- **GA4, de dónde vienen:** «Seattle, Estados Unidos» es el Mac del dueño y
  todo lo que corre en él, no clientes. Un aviso automático de GA4 de «alza de
  tráfico de Estados Unidos» casi seguro es una ronda de trabajo en el sitio.
  Agregar «Nombre de host» o «Ciudad» como dimensión secundaria antes de
  concluir.
- **GA4, personas y veces (2026-11-11):** el informe Eventos trae «Recuento de
  eventos» y «Usuarios totales»; el embudo de Presencia en internet suma lo
  primero. «11 agregaron al carro» eran 13 veces de 6 personas, y sólo 2
  abrieron el carro. Para hablar de personas se lee la columna de usuarios.
- **GA4, «Referral» de accounts.google.com:** es la vuelta del inicio de sesión
  con Google del portal `/cuenta`, no otro sitio que enlace (15 sesiones del
  14-oct al 10-nov). Se saca con la lista de referencias no deseadas del flujo
  web, un ajuste de la cuenta de Analytics que decide el dueño.
- **GA4, compras de hoy:** el informe «Hoy» no muestra una compra hasta horas
  después: el pedido de las 16:46 del 11-nov no aparecía a las 20:56. La fuente
  de una venta se mira al día siguiente.
- **GA4, de qué asistente de IA:** el canal «AI Assistant» no dice cuál; con
  «Origen de la sesión» como dimensión secundaria en Adquisición de tráfico,
  y en «Página de destino» con el mismo origen y la búsqueda de la tabla
  (`chatgpt`), sale a qué páginas llegan (2026-11-11).
- **GA4, vistas por título de página (2026-11-11):** no sirven para comparar
  octubre con septiembre. Del 4 al 6 de octubre la tienda pasó de Flutter, cuyo
  título de app era «Tienda» (`lib/main_store.dart`), al servidor HTML, que pone
  un título por página. Por eso la tarjeta «Vistas por título de página» de
  octubre dio «Productos para bicicletas» +5.566 % y «Tienda» −93 %: son las
  mismas páginas con otro nombre. A través de ese cambio se compara por «Ruta de
  la página» o por el total de vistas.
- **Render:** la Prueba de resultados enriquecidos (pestaña HTML, lupa) muestra
  lo que Google pintó; Chrome con user agent de Googlebot no es lo mismo.
- **Inspección de URL y «Solicitar indexación»:** un enlace directo a
  `/search-console/inspect?...&id=<url>` responde 404 (con `/u/2/` o con
  `authuser=2`); se entra por el cuadro «Inspeccionar cualquier URL» de
  arriba (clic, escribir, Enter). La prueba en vivo tras «Solicitar
  indexación» tarda 30–45 s; la cuota es de unas 10 URL por día, así que se
  gastan primero en las que Google tiene fuera del índice (2026-10-08).
- **Reenviar el sitemap:** el campo «Ingresar URL del sitemap» no toma el
  texto si se lo enfoca por referencia; sí con clic en el campo (2026-10-08).
  La propiedad es de dominio, así que va la dirección completa
  (`https://vinabike.cl/sitemap.xml`): `sitemap.xml` solo responde «Invalid
  sitemap address», y tras cerrar ese aviso el campo guarda el texto viejo:
  borrarlo antes de escribir (2026-10-09).
- **La cuota de «Solicitar indexación» no vuelve a medianoche de Chile:**
  la gastada el 8-oct seguía agotada el 9-oct a las 04:50 (Chile)
  («Quota Exceeded»). Reenviar el sitemap no la gasta.
  Tampoco vuelve a medianoche del Pacífico (04:00 de Chile): seguía agotada
  a las 07:22. El 9-oct a las 18:16 (Chile) ya había vuelto: seis URL
  pedidas seguidas sin aviso. Calza con «24 h después de cada pedido» (se
  gastó el 8-oct entre 17:40 y 17:50), pero no se probó entre 07:22 y 18:16,
  así que la hora exacta sigue sin confirmar (2026-10-09).
  El 2026-10-24 a las 02:16 (Chile) la sexta pedida seguida dio «Quota
  Exceeded»: la cuota puede ser menor que 10, o contar pedidos de las 24 h
  anteriores que el wiki no registra. Anotar aquí cada tanda con su hora.
- **El cuadro «Inspeccionar cualquier URL» tras cerrar un aviso:** el primer
  clic en el cuadro justo después de «Descartar» no lo enfoca y el texto se
  pierde sin error (el encabezado sigue con la URL anterior). Funciona
  enfocarlo por referencia en un paso aparte, después de cerrar el aviso
  (2026-10-09).
- **Filas por página** en Search Console: el selector no toma clics en la
  opción; sí clic en el selector + tecla End + Return (500 filas).
- **PageSpeed:** la API sin clave responde 429; `pagespeed.web.dev` en Chrome
  funciona si la pestaña está al frente; en el navegador integrado con el panel
  oculto no termina nunca.
- **GA4:** un evento nuevo tarda ~24 h en aparecer y recién ahí se puede marcar
  como evento clave.
- **Merchant:** el formulario de soporte exige un ID de Google Ads; la cuenta de
  Viñabike no tenía (2026-09-23). Desde el 2026-10-09 tiene una, sin campañas,
  y con ella se mandó el pedido de revisión.
- La conexión Google guardada en el ERP sólo tiene scope de identidad: el
  centro SEO del ERP no ve Search Console hasta reconectarla con `webmasters`.
