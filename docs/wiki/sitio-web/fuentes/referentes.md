---
titulo: Tiendas de referencia (medición en vivo)
resumen: cómo se midió la configuración SEO pública de tiendas de bicicletas chilenas e internacionales, y con qué cuidado leerla
tipo: externa
revisado: 2026-10-04
---

# Tiendas de referencia `[Ref]`

El dueño pidió (2026-10-04) aplicar «absolutamente toda la configuración de SEO
que ocupan sitios web de venta profesionales, u otros referentes de venta de
bicicletas». Para no suponerla, se midió en vivo.

## Qué tiendas

- **Chilenas que aparecen en Google** al buscar repuestos y bicicletas online
  (búsqueda del 2026-10-04): Oxford Store (`oxfordstore.cl`), Better Bike
  (`betterbike.cl`), Cycling Store (`cyclingstore.cl`), Express Bike
  (`expressbike.cl`), RudolfBike (`rudolfbike.cl`), ExtremeZone
  (`extremezone.cl`), Bike Center, Sparta, Belda Cycles.
- **Marcas internacionales:** Canyon, Specialized, Commencal (Trek no entregó
  ficha a la lectura).
- No respondieron a una lectura automática: Belda (403), Decathlon (403), Bike24
  (403), REI.

## Cómo

Un script de sólo lectura (navegador de escritorio como user agent) leyó
`robots.txt`, los sitemaps, la portada, una categoría y una ficha de cada una, y
contó: título y descripción, canonical, robots, hreflang, Open Graph y Twitter,
tipos y propiedades de JSON-LD y microdatos, `h1`, **palabras y enlaces que el
HTML trae sin ejecutar JavaScript**, alt de imágenes y paginación. Se probó
primero sobre vinabike.cl.

## Cómo leerla

- Es una foto de una ficha y una categoría por tienda, el 2026-10-04; otra ficha
  puede traer otras propiedades.
- «Sin JavaScript» es lo que ve un rastreador que no ejecuta JS (Bing en su
  primera pasada, previsualizaciones de redes y la mayoría de los rastreadores
  de asistentes de IA). Google sí ejecuta JS en una segunda fase, más lenta.
- Que un referente haga algo no lo vuelve correcto: se contrasta con
  [Google Search Central](google-search-central.md). Ejemplo: varios declaran
  `SearchAction`, pero Google retiró el cuadro de búsqueda de enlaces del sitio.
