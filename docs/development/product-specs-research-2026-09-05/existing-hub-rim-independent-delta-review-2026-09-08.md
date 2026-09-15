# Revisión independiente del delta de mazas y llantas (sólo lectura) — 2026-09-08

Revisión acotada al **delta** integrado por Root sobre la propuesta
independiente. Mi informe anterior
([`existing-hub-rim-readiness-2026-09-08.md`](existing-hub-rim-readiness-2026-09-08.md))
queda **histórico**: las decisiones vigentes son las de
[`existing-hub-rim-root-decisions-2026-09-08.md`](existing-hub-rim-root-decisions-2026-09-08.md),
y este documento evalúa lo implementado, no lo que yo había propuesto.

No edité ningún código ni JSON. Entradas obligatorias leídas:
`scripts/inventory/compile_existing_hub_rim_root.py` y el documento de
decisiones.

| archivo | sha256 verificado |
|---|---|
| `existing-hub-rim-catalog-2026-09-08.json` | `ce6c4807…db13d301` |
| `existing-hub-rim-cases-2026-09-08.json` | `a86d1d6b…9e00ae0e6` |

Corrí los 57 casos más las dos pruebas de metadatos (**59 verdes**), la
auditoría de adopción y nueve sondas mínimas con fixtures de scratchpad contra
el catálogo de Root sin modificarlo. **No verifiqué SQL**: los 57 avances,
repeticiones y rollbacks quedan fuera de mi dictamen.

## Dictamen

**Las cinco adjudicaciones que pediste comprobar están implementadas y son
observables.** Acepto además la corrección sobre el ejemplo Novatec: procede de
un listado de distribuidor, no de un plano OEM; sirve para mostrar que existen
dos datums distintos, y no autoriza convertir cotas ni rellenar una variante.

Quedan **dos hallazgos vigentes**, ninguno bloqueante: una **asimetría** entre
la compuerta escalar y la de fila para el receptor de transmisión, y una **cota
OEM publicada que sigue sin destino**, justamente en la fuente que el propio
documento de decisiones cita para distinguirla.

## 1. Lo comprobado, ejecutando el contrato

### 1.1 Cada maza del juego conserva lo suyo

La tabla de piezas lleva por fila identidad, ancho, perforación, sujeción de
eje, diámetro con su datum, eje pasante incluido y su referencia, receptor y su
referencia, presencia y tipo de anclaje de disco, anclaje de rayo, rodamiento,
los cuatro PCD y distancias al centro, distancia entre bridas y diámetro del
agujero de rayo. Diez casos verdes prohíben, uno por uno, el escalar equivalente
cuando el alcance es un juego, y las compuertas **por fila** reproducen las
mismas dependencias que las escalares: el receptor cuelga del booleano de la
propia pieza, el tipo de disco de su presencia, el eje pasante incluido de que
la sujeción sea eje pasante, y el datum se exige cuando hay diámetro.

### 1.2 Un juego incompleto queda pendiente, y un extremo repetido bloquea

La cardinalidad existente compara la cantidad declarada con sus filas: una sola
pieza deja `row_cardinality_pending` no bloqueante y repetir un extremo revienta
la unicidad como `row_shape` bloqueante. El total está acotado a exactamente dos.

**Precisión que conviene dejar escrita**, porque la auditoría puede leerse mal:
las 48 mazas muestran hoy `row_cardinality_pending` **sólo porque su alcance aún
no está declarado**. No es ruido sobre 41 mazas sueltas. En cuanto el alcance se
declara, el motor descarta esa pendiente —`product_spec_contract.dart:366-372`,
«una colección que no aplica no puede exigir más investigación»—. Medido: una
maza delantera con sus datos completos devuelve **cero observaciones**, y tanto
la tabla de piezas como su total le quedan **prohibidos**.

### 1.3 Sujeción y diámetro con datum representan 14 mm sin tocar el vocabulario compartido

`hub_axle_mount_kind` aporta las interfaces —incluidos eje con tuercas y eje
hembra con pernos— y el diámetro es un número con su datum, así que 14 mm se
escribe sin inventar un token. Las **27 definiciones publicadas se reutilizan
sin una sola diferencia** de `id`, rótulo, tipo, unidad, dominio ni reglas,
comparadas campo a campo contra la preimagen de publicación. El selector viejo
de eje y el de rosca de eje pasante quedan legacy.

### 1.4 La rosca de cuadro/horquilla queda fuera de la maza

El campo antiguo de rosca está retirado y el eje pasante sólo se identifica si
está realmente incluido: la referencia cuelga de la sujeción **y** del booleano
de suministro, con caso bloqueante propio.

### 1.5 Llanta: el perfil manda

El perfil de talón es obligatorio y precede a diámetro de asiento, ancho
interno, tubeless y rango de anchos: una llanta tubular tiene los cuatro
prohibidos, con tres casos bloqueantes. El agujero de válvula pasó a medida
propia, el ERD exige su datum, y altura de perfil y unión conservan su fuente.
La tensión máxima vive por configuración, con unidad y documento, y una lectura
de tensiómetro bloquea por no ser una unidad de fuerza.

### 1.6 Las fuentes nuevas dicen lo que el documento de decisiones afirma

Leídas de primera mano en esta ronda:

- **Ryde Andra 29 R** publica el ERD rotulado con su datum —`ERD (MM) (ID −2MM)
  596`—, una **tensión máxima de rayo de 1400 N**, el diámetro del agujero de
  válvula, la unión («pin»), el rango de ancho de neumático y el tipo de gancho.
  Es el respaldo exacto de exigir datum al ERD y de tratar la tensión como
  límite del componente por configuración y unidad.
- **Park Tool, medición de tensión**, dice que la tensión la declaran las marcas
  en kgf o en newtons, remite al fabricante de la llanta, fija la condición de
  medición —sin presión en el neumático— y explica que la lectura del
  tensiómetro es una escala que hay que convertir con su tabla. Sostiene tanto
  la separación límite/medición como el caso que bloquea la escala cruda.

### 1.7 Adopción y pruebas

Reproducidas: **48 mazas y 41 llantas, cero bloqueantes, 22 observaciones legacy
(7 y 15), ninguna activa sin proyectar, 89 con datos pendientes**; la auditoría
cita el mismo SHA del catálogo. **59 pruebas Dart verdes.** No son productos
rellenados ni montajes certificados.

## 2. Hallazgos vigentes

### F-1. Una pieza delantera de un juego puede declarar receptor de transmisión; una maza delantera suelta no

Las dos rutas aplican reglas distintas al mismo hecho de dominio:

- escalar: `hub_drive_receiver_kind` se permite **sólo** si el alcance es
  `Trasera`;
- por fila: el receptor se permite si `drive_interface_present` es verdadero,
  **sin mirar `piece_position`**.

Reproducción mínima, contra el catálogo de Root sin modificarlo:

| sonda | resultado |
|---|---|
| juego con fila `Delantera`, `drive_interface_present: true` y receptor de cassette | **pasa sin observación** |
| maza suelta `Delantera` con `hub_drive_receiver_kind` | **bloquea** (`field_applicability`) |

No lo declaro defecto cerrado: el documento de decisiones dice explícitamente
que «sus booleanos controlan su propio receptor», así que la compuerta por
booleano es deliberada. Lo que señalo es que **la misma afirmación imposible se
bloquea por un camino y se acepta por el otro**. Si la regla de dominio es que
un extremo delantero no recibe transmisión, la compuerta de fila admite la misma
forma que ya usan las demás —conjunción con `piece_position`— sin motor nuevo.
Si la regla no es esa, conviene que quede escrito, porque hoy el contrato
sostiene las dos lecturas a la vez.

### F-2. La segunda cota de agujero que publica la fuente citada sigue sin destino

El documento de decisiones adopta una regla nueva y explícita: no se excluye una
cota OEM porque todavía no la use otro módulo. Aplicándola al propio ejemplo que
cita: **Ryde publica dos diámetros de agujero para el mismo modelo** — asiento
de niple 5,5 mm y fondo del neumático 9 mm — y el documento de decisiones nombra
esa distinción. La plantilla conserva un solo campo, definido en su ayuda como
el agujero **para el niple**; el del fondo del neumático no tiene dónde ir.

No es ambigüedad —el campo está bien definido— sino una cota publicada que se
queda fuera, que es exactamente lo que la regla nueva quería evitar. El arreglo
tiene la misma forma que el campo que ya existe y no toca vocabulario
compartido. En la misma ficha de ese fabricante quedan además sin destino los
ángulos de taladrado radial/axial y el zig-zag; los menciono para que la
decisión sea consciente, no para pedirlos.

## 3. Limitaciones conocidas, no defectos

1. **Una llanta tubular no tiene ninguna cota de diámetro ni de ancho tipada.**
   Prohibirle asiento de talón y ancho interno de clincher es correcto —no tiene
   asiento de talón—, pero le quedan sólo el ERD, el ancho exterior y el texto
   ISO. **En la población capturada no hay ninguna llanta tubular**, así que hoy
   no afecta a ningún producto.
2. **La presencia de eje pasante incluido nunca es obligatoria**, ni en el
   escalar ni en la fila, mientras que en la fila sí son obligatorios los
   booleanos de disco y de receptor. La asimetría va en la dirección segura
   —callar en vez de afirmar— y conviene que quede escrita.
3. **`Desconocido / sin confirmar`** aparece en los dominios nuevos de sujeción
   y receptor y el motor lo lee como celda vacía. Es conducta compartida, ya
   conocida; sólo pido no contarlo como capacidad de expresar «el fabricante no
   lo declara».

## 4. Integración pendiente, tal como la declara Root

Las conversiones entre configuraciones y los receptores con varios puertos, el
cruce mecánico por modelo, la comparación automática de la prosa ISO con las
cifras y la aritmética entre cotas de brida siguen **explícitamente abiertos**.
Los cinco casos pendientes del paquete los sostienen y ninguno se presenta como
prueba superada. Nada de lo que reviso aquí los cierra.

## 5. Fuentes abiertas de primera mano en esta ronda

- Ryde, *Andra 29 R* — `https://www.ryde.nl/andra-29-r/`
- Park Tool, *Spoke Tension Measurement and Adjustment* —
  `https://www.parktool.com/en-us/blog/repair-help/wheel-tension-measurement`
- Park Tool, *Standardized Headset Identification System* y Sheldon Brown,
  *Tire Sizing Systems* y *Wheelbuilding*, ya leídas en rondas anteriores de
  este mismo bloque.
