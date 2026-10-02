---
titulo: Bike Matrix (bikematrix.io) — investigación
resumen: servicio B2B de compatibilidad para tiendas en línea; cómo identifica bicis y piezas, sus estados y sus límites
tipo: producto
revisado: 2026-10-02
---

# Bike Matrix (bikematrix.io) — investigación

Investigación pedida por el dueño el 2026-10-02. Conclusión y comparación en
[paginas/bike-matrix-vs-vinabike.md](../paginas/bike-matrix-vs-vinabike.md).

## Hechos

**Qué venden.** Software B2B: una tienda en línea muestra al cliente sólo las
piezas que calzan con su bici. Se integra por app de Shopify, por API o por un SDK
de componentes web (`@bikematrix/web-components`); también ofrecen integración
con Magento, WooCommerce, ERP, POS y herramientas de taller por API.

**Historia.** Empezó en noviembre de 2023 como buscador de pastillas de freno; en
2024 sumó ruedas, neumáticos y cámaras (según ETRTO), rotores, cadenas,
cassettes y piñones; finalista del premio Eurobike 2024 en soluciones digitales;
levantó capital en 2024 (USD 1,2 M) y 2025-2026 (USD 2 M). Caso de BIKE24: +69 %
de conversión en la prueba.

**Datos.** Base propia de bicis desde 2018 (98.411 en una página, 106.357 en
otra: crece). Unas 160.000 piezas de más de 150 marcas (SRAM, Shimano,
Campagnolo…). Los datos se **enriquecen a mano** por especialistas; no usan IA
para decidir. Los fabricantes de bicis entregan por modelo y año: eje, montaje de
freno, pedalier, patilla y rueda. Los de piezas entregan código del fabricante y
EAN más los atributos que afectan la compatibilidad; aceptan listas de precios y
documentación técnica, no catálogos PDF. Para el fabricante es gratis.

**Categorías con lógica (SDK, 17):** pastillas, rotor, manilla, cáliper, sistema
de freno; rueda delantera, rueda trasera, juego de ruedas, neumático, cámara;
cadena, cassette, biela, plato; dirección, pedalier, eje delantero, eje trasero.
Dicen 18 activas y 30 como meta.

**Identidad de la bici.** El selector recorre marca → familia de modelo → versión
→ año → talla. El evento `BikeAdded` entrega `key` (id de Bike Matrix), nombre,
marca, modelo, serie de cuadro, talla, año, variante, imagen y si es una bici
personalizada (`isCustomBike`). El «Bike Lounge» guarda varias bicis del cliente;
el «Virtual Workshop» deja cambiar componentes para que la compatibilidad siga a
la bici modificada.

**Identidad de la pieza.** EAN/UPC, código del fabricante (MPN) o SKU. En
Shopify, la tienda asigna colecciones a categorías de Bike Matrix y un conteo de
SKU reconoce los productos; lo no reconocido lo procesa su equipo.

**Resultado.** La etiqueta de compatibilidad tiene cuatro estados:
`compatible`, `warning`, `incompatible` y `unavailable`; el repositorio de
ejemplos los describe como verde, ámbar (compatible con condiciones) y rojo. Hay
resultado por producto, por colección, lista de compatibles y selector de
variante. Un SKU marcado con `*` no muestra estado.

**Criterio.** «Lógica de mecánico», considerando las piezas que rodean a la que
se cambia, no sólo el reemplazo igual. No recomiendan combinaciones que no
respaldarían nueve de cada diez mecánicos (ejemplos: cadena SRAM de 12 en
transmisión Shimano de 12; cassette de 52 dientes de otra marca con cambio
Shimano de 12). La lógica es cerrada («salsa secreta»).

**Límites que se ven.** Bicis desde 2018; respuesta sí/no por par sin explicación
pública; lo que no está en su base queda invisible en la vista filtrada (lo
advierte un análisis de terceros); depende de que la tienda tenga EAN/MPN.

## Páginas consultadas (2026-10-02)

| Página | URL | Lectura |
|---|---|---|
| Inicio | https://www.bikematrix.io/ | completa |
| How it works | https://www.bikematrix.io/how-it-works | completa |
| FAQ | https://www.bikematrix.io/frequently-asked-questions | completa |
| Parts manufacturers | https://www.bikematrix.io/parts-manufacturers | completa |
| Riders | https://www.bikematrix.io/riders | completa |
| Blog (índice) | https://www.bikematrix.io/blog | completa |
| Comparing Apples to Oranges | https://www.bikematrix.io/post/comparing-apples-to-oranges | completa (extracto) |
| Anything is compatible if you use a hammer… not! | https://www.bikematrix.io/post/anything-is-compatible-if-you-use-a-hammer-not | completa |
| Data in, data out! | https://www.bikematrix.io/post/data-in-data-out | completa |
| "Secret Sauce" Conundrum | https://www.bikematrix.io/post/secret-sauce-conundrum | extracto |
| Docs: overview, SDK, configuración, componentes, eventos | https://docs.bikematrix.io/docs/overview | completa |
| Docs: compatibility label | https://docs.bikematrix.io/docs/sdk-integration/web-components/compatibility-indicators/compatibility-label | completa |
| Docs: Shopify | https://docs.bikematrix.io/docs/shopify-integration/introduction | completa |
| GitHub web-components | https://github.com/bikematrix/web-components | completa |
| Cycling Industry News (Eurobike 2024) | https://cyclingindustry.news/eurobike-award-finalist-bike-matrix-expands-compatibility-product-finder/ | completa |
| NOCA Mobility, «What is Bike Matrix» | https://www.noca-mobility.com/what-is-bike-matrix-and-how-does-it-work/ | completa |

## Pendiente

- La API real (`api-staging.bikematrix.io/bike/v2/`) pide cuenta; no se probó.
- Si el dueño quisiera integrarlo en la tienda, la pregunta es comercial
  (precio por SKU y visitas) y de datos: de 1.635 productos activos, sólo 5
  tienen un EAN válido y ninguno tiene código del fabricante (MPN) (lectura
  2026-10-02). Bike Matrix no reconocería casi nada del inventario.
