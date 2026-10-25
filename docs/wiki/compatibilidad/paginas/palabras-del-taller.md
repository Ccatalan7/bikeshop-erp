---
titulo: Palabras del taller chileno
resumen: cómo se llama cada parte en Chile (motor, cambio, pata de cambio, piola, patines, maza, piñón, tee, volante), medido en lo que piden los clientes del taller, y dónde lo usa el sistema
fuentes: []
k: []
claves_bici: []
claves_producto: []
revisado: 2026-10-24
---

# Palabras del taller chileno

Un cliente de Viñabike no dice «pedalier» ni «desviador»: dice **motor** y
**cambio**. Esta página es el vocabulario del taller en Chile, con la palabra
chilena primero y las de otros países y del inglés después, para que el
sistema entienda lo que alguien escribe la primera vez que se le ocurre.

## Cómo se midió (2026-10-24)

Se contó cada palabra en los textos propios de Viñabike, sin leer ni copiar
ninguna conversación: lo que pidió el cliente al dejar la bici
(`mechanic_jobs.client_request`), el diagnóstico y el trabajo hecho, y los
nombres del ERP de los productos [Taller]. Los WhatsApp entrantes eran 296 y
casi no nombraban partes: la evidencia está en el taller.

| Parte | Se dice en Chile | Pedido por clientes | Otras palabras (pedidos) |
|---|---|---|---|
| Pedalier | **motor** («motor sellado») | 21 | pedalier 1, eje de centro 0 |
| Cambio trasero | **cambio** | 48 (de 160 «cambio»: 112 son «cambio de…», reemplazar) | desviador 14, descarrilador 0 |
| Patilla del cambio | **pata de cambio**, postiza | 13 | postiza 6 |
| Cable | **piola** | 14 | cable 0 |
| Funda | **funda** | 2 | forro 0 |
| Maza | **maza** | 42 | masa 1, buje 0 |
| Cassette / rueda libre | **piñón** | 13 | cassette 4 |
| Bielas con platos | **volante**, biela | 8 / 10 | plato 3 |
| Zapata de freno de llanta | **patines** | 5 | zapatas 0, balatas 0 (México) |
| Pastillas de disco | **pastillas** | 25 | |
| Rotor | **disco** | 15 | rotor 0 |
| Potencia | **tee** | 4 | potencia 1 |
| Manubrio | **manubrio** | 7 | manillar 0 |
| Puños | **puños** | 11 | |
| Tija | **tija**, tubo de asiento | 4 / 1 | |
| Sillín | **asiento** | 10 | sillín 2 |
| Juego de dirección | **dirección** | 8 | cazoletas 0 |
| Horquilla | **horquilla** | 7 | suspensión 1 |
| Pata lateral | **pata** | 2 (sin «pata de cambio») | parador 0 |
| Neumático | **neumático** | 20 | cubierta 1 (Argentina) |
| Cámara | **cámara** | 66 | tubo 1 |
| Llanta (el aro de metal) | **llanta**, aro | 8 / 3 | |
| Rayos | **rayos** | 10 | radios 0 |
| Tapabarro | **tapabarro** | 2 | guardabarro 0 |
| Caramayola | caramagiola en el catálogo (9), caramayola (1) | 0 | botella, bidón |
| Bombín | **bombín** (13 productos) | 0 | inflador, bomba |

Los servicios se piden así: **mantención** 34, **centrar** 20, **enrayar** 18,
**purgar** 7, **parchar** 2.

## Trampas de palabra

- **«Pata»** es tres cosas: la pata lateral, la «pata de cambio» (patilla) y el
  largo de la jaula del cambio («pata larga»). Sola no dice cuál.
- **«Llanta»** es el aro de metal, no el neumático.
- **«Cambio»** solo es el cambio trasero; «manilla de cambio» es el mando, y
  «cambio de cámara» es reemplazarla: 112 de los 160 pedidos con «cambio».
- **«Motor»** en un producto eléctrico es un motor; en el taller, el pedalier.
- **«Corona»** (20 nombres del catálogo) puede ser un plato o un piñón del
  cassette; el buscador la trata como plato, igual que «catalina» (3).
- **«Disco»** solo es el disco de freno (rotor): «disco de 180», «cambiar los
  discos». El buscador lo trata así desde el 2026-10-25; «freno de disco»
  sigue siendo un freno, porque manda la primera pieza que se nombra.
- **«Cassette 7v»** lo escribe también quien tiene piñón con rosca: la mayoría
  de las bicis de 7 velocidades lo usan. El buscador muestra los piñones de 7
  aunque no haya cassettes de 7; una maza sí distingue núcleo de cassette y
  rosca.

## En Vinabike

- La búsqueda del catálogo usa este vocabulario como datos
  (`catalog_search_terms`, migración `20261024030000`): cada concepto tiene
  sus palabras equivalentes, las amplias a las que pertenece y frases de
  varias palabras («pata de cambio», «disco de freno», «tubo de asiento»). Una
  **parte** la dicen sólo el nombre y la categoría del producto (una cadena
  cuya ficha dice «derailleur» no es un cambio); un **atributo** (válvula,
  tubeless, uso) también lo dice la ficha técnica. El detalle del buscador
  está en [el catálogo del sitio](../../sitio-web/paginas/catalogo-y-fichas.md).
- Una palabra nueva se agrega como fila de esa tabla, no en el código. Desde
  el 2026-10-24 la tienda la agrega en el ERP, «Búsquedas» del catálogo de la
  tienda: ahí llega cada búsqueda que no encontró nada en vinabike.cl, y «Es
  una palabra de…» la suma a un grupo (fila propia de la tienda; las
  compartidas no se quitan). Cada grupo tiene su nombre con tildes (`label`):
  las palabras van sin ellas porque así compara la búsqueda.
