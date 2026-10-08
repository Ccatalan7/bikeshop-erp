---
titulo: Consolas de Google (Search Console, GA4, Merchant)
resumen: lo que Google dice del sitio, medido con fecha; cómo entrar y cómo no leerlas mal
tipo: interna
revisado: 2026-10-04
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
- **Filas por página** en Search Console: el selector no toma clics en la
  opción; sí clic en el selector + tecla End + Return (500 filas).
- **PageSpeed:** la API sin clave responde 429; `pagespeed.web.dev` en Chrome
  funciona si la pestaña está al frente; en el navegador integrado con el panel
  oculto no termina nunca.
- **GA4:** un evento nuevo tarda ~24 h en aparecer y recién ahí se puede marcar
  como evento clave.
- **Merchant:** el formulario de soporte exige un ID de Google Ads; la cuenta de
  Viñabike no tiene uno (2026-09-23).
- La conexión Google guardada en el ERP sólo tiene scope de identidad: el
  centro SEO del ERP no ve Search Console hasta reconectarla con `webmasters`.
