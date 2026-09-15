# Revisión del delta de orden de filas y de la adjudicación de piezas de servicio — 2026-09-08

Sólo lectura. Sin SQL ejecutado, sin runtime, git ni publicación. No edité
ningún archivo revisado; escribí sólo este documento. Todo sigue sin activar,
sin asignar y sin llenar.

## Qué verifiqué directamente

| comprobación | resultado |
|---|---|
| `test/unit/product_spec_strict_row_order_test.dart` | **30 verdes** (16 casos + 14 esquemas inválidos) |
| candidato adjudicado de las tres familias | **52 verdes** (3 metadatos + 49 casos) |
| paquete de direcciones, para confirmar que no se movió | 23 verdes |
| SHA de catálogo y casos de las tres familias | coinciden con los citados |
| mi compilador original | **byte-idéntico** (`afc381d2…fc3df8e7`) |
| ensayo de adopción | lleva el SHA del catálogo bajo revisión y da **33 productos (23/3/7), 0 bloqueantes, 0 legacy, 0 activas sin proyectar, 0 escrituras y 33 con pendientes** |
| barrido propio de unidades en pares | 33 archivos candidatos, **808 esquemas de filas, 226 pares declarados, cero entre unidades distintas** |
| una sola sonda de duda | ver §3 |

**No verifiqué**: las 49 corridas SQL de avance/replay —en curso, y no las
atribuyo a producción—, las 22 SQL bajo extensión del paquete de direcciones,
ni el editor real. El SQL lo leí como texto.

## 1. G1 y G2

**G1 corregida y algo más amplia de lo que reporté.** La comprobación de
unidades cubre ahora las dos listas de pares, con un mensaje común. Un detalle
que conviene registrar: el fixture incluye
`inclusive_pair_rejects_different_units_v1`, es decir que la regla **también
aplica a esquemas versión 1**. Es un endurecimiento retroactivo de la gramática
ya existente, no sólo de la nueva. Tu lectura de producción da cero pares entre
unidades distintas; comprobé lo mismo del lado del repositorio, sobre todos los
candidatos: 226 pares declarados y ninguno cruza unidades. El endurecimiento no
rompe nada en ninguno de los dos sitios.

**G2 corregida de forma mínima y correcta.** El grafo se arma con la unión de
las dos listas y la búsqueda se hace **por cada par estricto**, desde su segundo
extremo buscando el primero. Recorrí los casos:

- oposición directa, escrita en cualquiera de los dos sentidos: rechazada;
- dos pares estrictos opuestos: rechazado;
- ciclo largo con un solo enlace estricto: rechazado;
- par consigo mismo: ya lo rechazaba la comprobación de columnas repetidas;
- el mismo par declarado en las dos listas: aceptado, y es correcto porque el
  estricto absorbe al inclusivo;
- ciclo sólo inclusivo: aceptado, que es la regla que declaraste — `a ≤ b` con
  `b ≤ a` es satisfacible únicamente en la igualdad.

La terminación está garantizada por el conjunto de visitados en Dart y por el
`UNION` del recursivo en SQL.

**Paridad de texto SQL.** Leí el candidato y refleja las dos reglas: la
comprobación de unidades sobre ambas listas con `is distinct from` —de modo que
dos columnas sin unidad se consideran iguales, igual que en Dart— y una
reachability recursiva sembrada en el segundo extremo del par estricto que
busca el primero. No encontré divergencia con Dart. El generador es un parcheo
textual con una guarda de conteo que aborta si el texto de origen deja de tener
exactamente las dos ocurrencias esperadas; es una defensa razonable para un
parche por texto.

**Cobertura del fixture.** Cinco esquemas negativos nuevos cubren exactamente
lo reportado —unidades distintas en la lista inclusiva en v2 y en v1, oposición
inclusiva/estricta, dos estrictos opuestos y el ciclo largo— y dos casos
positivos nuevos fijan lo que **no** debe rechazarse: el ciclo sólo inclusivo
expresando igualdad y el par declarado en las dos listas. Es la forma correcta:
los negativos solos habrían dejado sitio para una corrección demasiado ancha.

No encontré defectos vigentes en este delta.

## 2. Adjudicación de las tres familias

Acepto las cuatro correcciones. Las contrasté contra la fuente que yo mismo
había leído, y en tres de ellas el error era mío.

**2.1 El peso es del conjunto, no de la placa. Me equivoqué.** La ficha pública
de OneUp da los 90 / 105 / 110 g en su fila de especificación junto a los tres
rangos de plato, pero su propio párrafo dice que **la Bash Guide** pesa 105 g
con 34T. El sujeto es el producto montado, no la placa suelta. Yo até esas
cifras a las piezas incluidas, que es atribuir a una pieza el peso de un
conjunto. La corrección es correcta y además está bien anclada: la nueva tabla
de pesos del conjunto exige una **referencia a la pieza montada**, que es
justamente lo que da sentido a «105 g (34T)», y el peso de pieza suelta queda
acotado por su ayuda a ese alcance documental.

**2.2 La capacidad no se calcula uniendo piezas. Me equivoqué.** El fabricante
publica «Capacity: 28-36T» como línea propia; es un dato declarado, no una
unión derivada de los rangos de las tres placas. Mi ayuda lo describía como
unión, que es exactamente convertir un cálculo en un hecho. La ayuda nueva lo
dice al revés y es lo que corresponde.

**2.3 Igual número de dientes no prueba identidad. Me equivoqué en el nombre
del caso.** Mi caso se llamaba «dos unidades idénticas»; el dato de partida
—tres referencias de par que declaran un solo número de dientes— sólo prueba
que la fuente da un número, no que las dos piezas sean iguales ni cuál es guía
y cuál tensión. El renombrado a «dientes iguales no resuelven identidad ni
posición» dice lo que el dato sostiene y nada más.

**2.4 Las declaraciones del par pertenecen a cada unidad. Es un hueco real de
mi entrega.** Yo dejé velocidades, jaula y modelos de cambio como escalares
permitidos siempre, de modo que un envase de dos piezas podía colgar una sola
declaración sobre dos unidades distintas —el mismo error que yo había señalado
en mazas y que no vi en mi propia ficha—. Ahora los escalares están acotados al
envase individual, con casos que bloquean su uso en un par, y el par tiene su
tabla de declaraciones con velocidad y jaula **por unidad**, unida a la pieza
por el vínculo de filas y con su caso negativo cuando la referencia no existe.

## 3. La única duda que sondeé

El vínculo del peso ensamblado exige una referencia a la pieza montada. Quise
saber qué ocurre cuando la tabla de piezas incluidas **no está documentada**.

| sonda | resultado |
|---|---|
| peso del conjunto con su pieza documentada | pasa |
| el mismo peso con la tabla de piezas **ausente** | pendiente no bloqueante (`row_reference_pending`) |

No es un defecto: el motor trata un destino ausente como información
incompleta, no como contradicción, y esa es la misma regla que usa el resto del
paquete. Pero significa que el ancla que hace verificable a «105 g con la placa
32-34T» puede quedar colgando mientras las piezas no se documenten. Conviene
una línea en la readiness diciendo que el peso del conjunto sólo queda anclado
cuando su pieza existe en la ficha; el caso negativo actual cubre la referencia
**equivocada**, no la **ausente**.

## 4. Verificación que parecía una inconsistencia y no lo es

Las dos plantillas del paquete declaran versiones distintas de coherencia de
filas: la guía usa 1 y la roldana usa 2. No es un descuido. La versión 1 admite
sólo vínculos y la 2 añade los conteos planos, y un bloque de versión 1 tiene
prohibido llevar la clave de cardinalidades. La guía declara vínculos y ningún
conteo; la roldana declara ambos. Cada una usa la versión que le corresponde.

## 5. Resumen

G1 y G2 están corregidas, con la regla de unidades extendida también a los
esquemas versión 1 y con un rechazo de ciclos que deja pasar el único ciclo
satisfacible. La paridad de texto entre Dart y SQL se sostiene y el fixture fija
tanto lo que debe rechazarse como lo que no. **No encontré defectos vigentes en
ninguno de los dos deltas.**

De la adjudicación de las tres familias acepto las cuatro correcciones: tres
eran errores míos —el peso del conjunto atribuido a la placa, la capacidad
descrita como unión y el caso que llamaba idénticas a dos roldanas por
compartir dientes— y la cuarta cerró un hueco que yo había señalado en otra
familia y no vi en la propia. Queda una sola observación menor: el ancla del
peso ensamblado admite quedar pendiente mientras la tabla de piezas esté
ausente.
