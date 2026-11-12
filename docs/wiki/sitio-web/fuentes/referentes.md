---
titulo: Tiendas de referencia (medición en vivo)
resumen: cómo se midió la configuración SEO pública de tiendas de bicicletas chilenas e internacionales, y con qué cuidado leerla
tipo: externa
revisado: 2026-11-12
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

## Ficha: foto y nombre (2026-10-24)

El dueño pidió decidir el aspecto de la ficha «basándote en referentes». Un
script de Chrome de sólo lectura abrió 16 fichas reales (tres no se dejaron
leer: Jenson y REI bloquean, y Chain Reaction y Wiggle redirigen a Evans), y
midió el fondo de la foto principal y el `text-transform` y la fuente del `h1`:

| Tienda | Fondo de la foto | Nombre |
|---|---|---|
| Specialized | gris claro plano (`#F1F1F1`), esquinas rectas | como se escribe |
| Canyon | gris claro plano (`#F2F2F2`), esquinas rectas | como se escribe |
| Tredz | gris claro plano (`#F3F3F3`), esquinas rectas | como se escribe |
| Trek | blanco, tarjeta con radio 16 y sombra | como se escribe |
| Oxford Store, Cycling Store, Bike24, Bike-Discount, Alltricks, Competitive Cyclist | blanco, sin recuadro | como se escribe |
| RudolfBike | blanco sobre una página gris, radio 3 | como se escribe |
| bike-components, Commencal | blanco | mayúsculas por CSS |
| ExtremeZone | blanco | Bebas Neue (fuente sólo de mayúsculas) |

Lectura: 11 de 14 escriben el nombre como en el catálogo. La foto va sobre
blanco o sobre un gris claro plano con esquinas rectas. Ninguna usa un
recuadro redondeado teñido con el color de la marca, que es lo que el diseño
del 2026-10-24 puso en la ficha y que se revirtió el mismo día.

## Portadas que rotan (2026-11-01)

El dueño pidió «darle vida» al sitio mirando referentes con buen gusto, de
deporte y aventura (GoPro, DJI, Canyon, Fox, Cannondale, Commencal, RockShox,
SRAM) y talleres en esa línea. Se leyeron las portadas con `curl` y un script
de sólo lectura (títulos, banners, llamados y promesas); DJI, Padro Bikes,
Better Bike, Tienda Ride, Fanatik y Jenson no se dejaron leer (404, 429 o 403).

- **Marcas:** arriba va una sola historia o un lanzamiento que cambia con la
  temporada. Canyon tiene «La bicicleta de la semana» y «Ayúdame a decidir».
  Santa Cruz pone «Lo que nos encanta», elegido por su equipo. Fox lleva
  servicio y FOX Academy en la portada. GoPro vende por actividad y muestra
  fotos de su gente.
- **Talleres:** TF Tuned y Vorsprung (suspensiones) ponen «agenda tu servicio»
  y herramientas que resuelven. Bicycle Habitat cambia el titular con la
  temporada y tiene «Bike Repair» a la vista. Brick Lane Bikes abre con «Latest
  Arrivals».
- **Chile:** Oxford Store cambia el set completo de banners. En el Internet
  Archive del 2026-03-02 tenía 6, con «marzo» en el nombre; el 2026-11-01
  tenía 8 distintos, con versión de escritorio y de teléfono. RudolfBike tiene
  vitrinas automáticas (nuevos, más vendidos, tendencia). Las guías de Cycling
  Store usan imágenes de ChatGPT (el nombre del archivo lo dice) con tildes mal
  escritas dentro de la imagen.
- **Evidencia sobre carruseles:** en Notre Dame (2013) tocó el carrusel entre
  1 % y 9 % de las visitas, y de esos clics entre 55 % y 89 % fue a la primera
  diapositiva. Nielsen Norman Group y Baymard recomiendan pocas diapositivas,
  sin giro automático en el teléfono, y repetir abajo lo importante.

Lo que se tomó de cada una, y el plan, está en el documento
[«Darle vida a vinabike.cl»](https://claude.ai/artifact/3fn5NfDnTQSx4gkHgyZSkr).

## Tienda Ride: vender sin stock (2026-11-12)

El dueño la dio como referencia por dos cosas: cómo vende lo que no tiene en la
tienda y cómo presenta el producto (varias fotos, video, tabla de componentes,
guía de tallas). Es de Viña del Mar y corre sobre Shopify.

- **Catálogo.** 1.556 productos; 185 sobre $500.000 (nosotros, 1 ese día), 144
  sobre $1.000.000 y 105 sobre $3.000.000.
- **«Preventa» es el botón de compra** cuando el stock es cero. De 121 productos
  caros que se pudieron leer, 60 se vendían así y 61 tenían stock. Se paga
  directo, también una bicicleta de $5.699.990, con cuotas sin interés.
- **Sus reglas de preventa están en `/pages/terminos-y-condiciones`,** la página
  que enlaza la casilla del carro, no en `/policies/terms-of-service`. Dicen que
  la fecha estimada va en la descripción de cada producto (la ficha que se miró
  no la traía), que puede moverse por fábrica, transporte o aduana, y que la
  preventa no se anula pasados 10 días de la compra. Es importación por lotes.
- **Cómo se lee su stock.** `/products.json?limit=250&page=N` entrega el
  catálogo y `/products/<handle>/?section_id=js_ppr` la cantidad por variante.

**Trampa.** Los términos de una tienda se leen en la página que su checkout
enlaza. Se leyó primero la ruta de políticas por defecto de Shopify y se
concluyó, mal, que no nombraban la preventa.
