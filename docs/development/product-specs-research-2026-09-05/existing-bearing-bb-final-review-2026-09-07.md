# Rodamiento/motor y consumidor: dictamen final independiente

2026-09-07. Revisión sólo lectura del diff del consumidor, del callback
`compile_existing_bearing_bb_root.py`, de su integración y de los dos
artefactos. No edité nada de root. Los dos hashes declarados coinciden y sus
79 pruebas pasan aquí.

**Veredicto: la adjudicación de root es correcta y yo estaba equivocado en tres
puntos de fondo.** Los verifiqué abriendo las fuentes yo mismo, no aceptándolas.
Queda **un defecto concreto**, con contraejemplo medido, y una pregunta que root
me pidió revisar y que contesto con una distinción, no con un sí.

## Me equivoqué, y así lo comprobé

**1. Los biseles sí son del rodamiento.** Yo los saqué de `bearing` alegando que
describían el asiento de otra pieza. Abrí la ficha de Enduro S7806: publica
**«36 degree inner chamfer»** y, por separado, **«Angular Contact»**. Son dos
hechos distintos del mismo objeto, y el segundo no absorbe al primero. Root
restauró los tres campos con sus dominios y sus pendientes originales, y tiene
razón.

**2. El par no se podía fusionar.** Cane Creek publica sus rodamientos de
dirección como **«36° x 45°»** y **«45° x 45°»**. Yo convertí ese par en un solo
ángulo de rodadura. La página no define qué significan los dos números —eso lo
comprobé también—, pero publica dos, y un esquema que sólo admite uno no puede
representar lo que el fabricante imprime.

**3. Un rodamiento radial tiene ángulo de contacto, y puede ser cero.** Mi
compuerta admitía el ángulo sólo con `race_type = Contacto angular`. NSK lo
contradice de frente: **«Radial bearings: 0° ≤ α ≤ 45°»**, con la definición del
ángulo y el caso α = 0° incluido. Mi regla habría rechazado un dato legítimo por
una etiqueta de clasificación. Root desacopla el ángulo de esa etiqueta y lo deja
opcional; verificado con dos sondas, un cartucho radial declara 0 y declara 40
sin incidencia.

**4. La fuente del thread-together existía.** Declaré «sin fuente para la copa
roscada contra su opuesta». Park, Bottom Bracket Identification, lo dice
literalmente: **«installs into a non-threaded shell»** y **«the two pieces thread
together inside the shell»**. Es la tercera vez en este proyecto que escribo «no
hay fuente» después de una búsqueda incompleta; el patrón es mío y ya está
anotado.

Un punto donde mi frase se sostiene, y lo digo una vez porque no cambia nada:
volví a abrir la sección **ISO vs J.I.S.** de Sheldon y todo lo que hay ahí está
atribuido —una cita de rec.bicycles.tech y un «yet another source claimed»—. Mi
afirmación estaba acotada a esa sección. El resultado es el mismo en los dos
diseños: la variante OEM se exige, no se deriva de Sheldon.

## El defecto: `bb_accepted_spindles` perdió la interfaz

`interface` dejó de ser obligatoria y **no está en ninguna de las dos claves**,
que son `[standard, configuration]` y `[oem_brand, oem_model, oem_edition,
configuration]`. Tres consecuencias, la primera medida:

- **Un motor que admite Cuadrado JIS y Cuadrado ISO del mismo modelo y edición,
  en una misma configuración, no se puede representar.** Las dos filas chocan:
  `row_shape: bb_accepted_spindles`. Sonda
  `rp_two_interfaces_one_configuration_same_model`.
- **La fixture de root rodea el choque en vez de exponerlo.**
  `bbx_jis_and_iso_are_two_declarations` reparte las dos interfaces en
  «Configuración sintética 1» y «2», y la traducción lo justifica diciendo que
  cada interfaz declara una configuración independiente. Eso **afirma algo que la
  fuente puede no decir**: convierte una limitación de la clave en una tesis
  sobre el producto. Es el caso que el propio documento de decisiones señala como
  importante —no aprobar dos interfaces por marca— resuelto moviendo el dato.
- **Una fila puede declarar un eje admitido sin decir qué interfaz es**, y no
  queda pendiente. Antes era obligatoria. Sonda
  `rp_accepted_row_without_any_interface`: pasa limpia.

El arreglo es pequeño y del mismo tipo que root ya aplicó al resto: exigir
`interface` condicionalmente cuando `target_kind = Modelo y edición` —como ya
hace con marca, modelo y edición— y meterla en esa clave. Con `Estándar
declarado` la interfaz la lleva el propio estándar y no hace falta.

No lo toco: son sus archivos.

## Clasificación de carga y construcción: distinguidas donde importa, no en el token

Root preguntó, y la respuesta tiene dos mitades.

**En las compuertas, sí, y ése era el defecto grave.** El ángulo ya no depende de
`bearing_race_type`, así que ninguna clasificación puede invalidar una medida.
Eso está resuelto.

**En el vocabulario, todavía no.** `bearing_race_type` ofrece «Radial» y
«Contacto angular» en una sola celda, y esos dos no son valores del mismo eje:
según NSK la clasificación radial/axial se define **por el rango del ángulo**
—radial 0°–45°, axial 45°–90°—, mientras que «contacto angular» es una
construcción. Con el ángulo ya registrado, la clase de carga se deduce de él y la
celda es redundante; y en el sentido contrario, una ficha no puede decir que un
rodamiento de contacto angular es de carga radial, porque sólo hay una casilla
para las dos preguntas. Sonda
`rp_angular_contact_cannot_also_record_its_load_class`: pasa, porque nada
bloquea, y ése es justamente el punto — no hay contradicción, hay un dato que no
cabe.

No es bloqueante y no pido rehacerlo. Sí pido que se decida a conciencia, porque
es la misma familia de problema que el resto del bloque cerró: un hecho, un
dueño.

## Lo que probé y funciona

Once sondas más, todas verdes contra el candidato exacto:

| Sonda | Resultado |
|---|---|
| cartucho radial declara 0° y 40° | pasa, como manda NSK |
| «Sólo bisel interior» con ángulo exterior | rechaza el exterior |
| el par 36/45 con ambos biseles | pasa |
| cubeta **con** rodamiento incluido declara su asiento | pasa |
| forma de suministro sin declarar | pendiente, no completa |
| mismo puerto con otro `source_scope` | bloquea |
| dos puertos, dos lados | pasa |
| dos miembros con códigos distintos | pasa |
| el mismo miembro dos veces | bloquea |
| dos estándares en una configuración | pasa |
| la fila sin interfaz | pasa — y ése es el defecto de arriba |

Confirmo también lo que root declara y yo puedo comprobar sin base: los dos
hashes, las 79 pruebas, la retirada del `bb_bearing_arrangement` que yo había
introducido y nunca se publicó, la conservación de los campos vivos como legacy,
y que los miembros de rodamiento llevan construcción, código y medidas **en la
misma fila**, con el par `bore ≤ outer` ordenado. La auditoría de los 57
productos, la corrida SQL y los snapshots autenticados no los puedo verificar
desde aquí y no los presento como míos.

## El consumidor: el arreglo cierra la clase, no el caso

Root eligió la siembra perezosa. `_draftFor` hace `putIfAbsent` y siembra desde
`widget.criteria` en el momento de la primera lectura, y los tres puntos que
usaban `!` —dibujo, valores actuales y recolección— pasan por él. **Corrí mi
sonda original sin cambiarla**: las seis pasan, incluida la que reventaba con la
misma plantilla y un campo más. Las dos suites nombradas: 28 verdes.

Es el arreglo que deja de depender de cuándo corrió la siembra, que era la
propiedad que hacía frágil al anterior. Coincido con root en que **no habilita
activar las originales**: el cliente corregido no está distribuido, y una
plantilla que gana campos delante de un binario viejo es exactamente el escenario
que reproduje.

## Gates que sigo viendo abiertos

- La interfaz de los ejes admitidos, arriba.
- El eje del vocabulario de `bearing_race_type`, arriba.
- Distribución del cliente antes de activar, que root ya declara.
- Adopción, referencias de identidad y cobertura mecánica siguen abiertas, como
  dice el documento de decisiones. Ninguna sonda sintética las toca.

## Hashes verificados

| Artefacto | SHA-256 | |
|---|---|---|
| `existing-bearing-bb-catalog-2026-09-07.json` | `13ca4446ef21517bc880f0cbf0b69517d704c6830b9876130727b6ba01429027` | coincide |
| `existing-bearing-bb-cases-2026-09-07.json` | `6b5d2a07e55f7f35dce1e4fed0fe944dcc715cbcf0f3c81f9530c021168b88f8` | coincide |
| `compile_existing_bearing_bb_root.py` | `0f1a3bbc3636075271acd75783bba30ae5578055e1e333f53214f98cc4a7e989` | leído |

Fuentes que abrí yo para este dictamen: Enduro S7806, Cane Creek headset
bearings, NSK Differentiating Rolling Bearings, Park Bottom Bracket
Identification y Sheldon bbsize. Ninguna cita aquí es de segunda mano.
