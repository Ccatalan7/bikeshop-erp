---
titulo: Bike Matrix y lo que Vinabike quiere más allá
resumen: cómo funciona Bike Matrix, en qué es más simple que lo que necesita el taller y qué ideas sí conviene tomar
fuentes: [bike-matrix]
k: [K07, K31]
claves_bici: [bikeType, wheelSize, freehubType, drivetrainSpeeds]
claves_producto: []
revisado: 2026-10-02
---

# Bike Matrix y lo que Vinabike quiere más allá

El dueño lo pidió así (2026-10-02): «investigarás mucho acerca de bike matrix
… aunque creo que bike matrix es más simple de lo que queremos aplicar en
nuestro caso». La investigación completa, con fechas y enlaces, está en
[fuentes/bike-matrix.md](../fuentes/bike-matrix.md). Aquí va la conclusión.

## Qué es Bike Matrix

Un servicio B2B (Shopify, API o SDK de componentes web) que le dice a una
**tienda en línea** qué repuestos calzan con la bici del cliente [BM]:

1. El cliente elige su bici: marca → familia de modelo → versión → año → talla.
   Bike Matrix le da un identificador (`key`) y la guarda en el navegador o en su
   «Bike Lounge» [BM].
2. La tienda le manda a Bike Matrix sus productos identificados por **EAN/UPC,
   código del fabricante (MPN) o SKU**; Bike Matrix los reconoce en su catálogo
   (lo que no reconoce lo procesa su equipo a mano) [BM].
3. Por cada par bici–producto devuelve un estado: `compatible`, `warning`
   (compatible con condiciones), `incompatible` o `unavailable` (sin datos), y la
   tienda filtra o muestra una etiqueta verde, ámbar o roja [BM].

Datos: sobre 106.000 bicis desde 2018 y unas 160.000 piezas de más de 150
marcas, **enriquecidos a mano** por mecánicos; los fabricantes de bicis entregan
por modelo y año el eje, el montaje de freno, el pedalier, la patilla y la rueda;
los de piezas entregan códigos y atributos [BM]. Cubre 17-18 categorías con
lógica (pastillas, rotores, cálipers, manillas, sistemas de freno; rueda
delantera, trasera, juego, neumático, cámara; cadena, cassette, biela, plato;
dirección, pedalier, ejes delantero y trasero) y apunta a 30 [BM].

Su línea de criterio: no recomendar una combinación salvo que nueve de cada diez
mecánicos la respalden, y considerar las piezas que rodean a la que se cambia,
no sólo el reemplazo igual [BM].

## En qué es más simple que lo que necesita Vinabike

| Bike Matrix | Vinabike |
|---|---|
| La bici es **un modelo de catálogo desde 2018**; los cambios del dueño se anotan en un «Virtual Workshop» | La bici es **la bici real del cliente**, de cualquier año, con lo que el taller confirmó y cambió; un trabajo terminado cambia la ficha (dueño, 2026-09-27) |
| Responde **sí/no por par bici–pieza**; no expone por qué | El mecánico necesita **el porqué y la condición**: qué separador, qué adaptador, qué falta saber |
| Productos identificados por **EAN/MPN** de catálogos de fabricante | De 1.635 productos activos, 5 tienen EAN válido y ninguno MPN (2026-10-02); la identidad se resuelve con el contrato de identidad de producto y la ficha técnica |
| Sólo **venta en línea** | Taller + venta: diagnóstico, servicios, presupuesto, memoria de la bici, tienda y portal |
| Datos y reglas **cerrados** (su «salsa secreta») | Reglas y evidencia propias y auditables (registro K, contrato de fichas, este wiki) |
| 18 categorías | 26 familias juzgadas hoy por el motor, más reglas de ficha en la base |

## Lo que sí conviene tomar

1. **El estado ámbar con condición.** Bike Matrix separa «compatible» de
   «compatible con condiciones». Vinabike lo tiene en el contrato (§8) pero el
   motor lo junta con «sin confirmar» bajo *Revisar*. Separarlos y nombrar la
   condición es la mejora más directa ([principios.md](principios.md)).
2. **«Sin datos» explícito.** Su `unavailable` no se confunde con incompatible.
   Igual que nuestro *sin confirmar*: mostrarlo distinto en la tienda y en el
   taller.
3. **La bici del cliente en la tienda.** Bike Matrix necesita que el cliente
   elija su bici en un catálogo; **Vinabike ya la conoce** si pasó por el taller.
   Un «calza con tu bici» en la tienda y el portal usando la ficha real de la bici
   del cliente es algo que Bike Matrix no puede hacer. Es la oportunidad más
   grande.
4. **Ficha de bici de catálogo por modelo-año-talla.** El `bike_catalog` del
   Master Schema cumple ese papel; llenarlo con el eje, montaje de freno, pedalier,
   patilla y rueda por modelo y año (lo mismo que Bike Matrix pide a los
   fabricantes) acelera el alta de bicis nuevas.
5. **Identificar por código del fabricante y EAN** cuando el producto los tiene,
   como un camino más del contrato de identidad (no el único). Hoy casi ningún
   producto los tiene; capturarlos al recibir mercadería es lo que haría posible
   cruzar con catálogos de fabricante.
6. **Lista de categorías como lista de control**: sus 18 categorías son un buen
   piso para verificar que el motor cubre lo que más se vende.

## Lo que no conviene copiar

- El sí/no sin explicación: en el taller el porqué es parte del servicio.
- Que lo que no está en la base «desaparezca»: Bike Matrix advierte que un
  producto sin datos queda invisible en la vista filtrada [BM]. En Vinabike, *sin
  confirmar* se muestra y se pregunta.
- Depender de un catálogo cerrado de bicis desde 2018: de las 480 bicis del
  taller, 473 no tienen año registrado (lectura 2026-10-02); un catálogo por
  modelo y año no las identificaría. La ficha confirmada por el mecánico sí.

## En Vinabike

- Conceptos equivalentes: su `key` de bici ≈ `bikes` + `bike_profiles`; su
  «Virtual Workshop» ≈ la ficha de la bici que cambia con los trabajos; sus
  categorías ≈ las familias del motor (`_assess*FamilyCompatibility`); sus
  estados ≈ nuestros veredictos.
- El modelo completo está en [modelo-vinabike.md](modelo-vinabike.md).

## Fuentes

- [fuentes/bike-matrix.md](../fuentes/bike-matrix.md).
