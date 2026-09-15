# Hidráulica — adenda final sobre HY-A/HY-B (2026-09-07)

Revisión acotada de la adjudicación de las 19:35. No edité candidatos, motor,
migración ni base; no corrí el publicador. Sondas propias en el scratchpad
contra el catálogo sin modificar. No repetí la suite completa: las sondas del
cambio bastan y así lo pediste.

**Veredicto: publicable. Sin hallazgos nuevos.** Y el hallazgo anterior era mío
en su mitad más importante.

## Los ocho hashes finales coinciden

Recomputados uno por uno: compilador base `a666cd2a…aa85` (sin cambios),
adjudicador `1f6f90d1…fa3b`, catálogo `db035cb3…a6d6`, casos `1e49f0a8…a9e1`,
preimagen `1670b9ef…0a3f` (sin cambios), paquete `9c6303e9…0092`, migración
`6047e3f6…e3f1`, verificador `08eea544…b86e`. **42 casos**, 24 definiciones,
31 usos.

Superficie de escritura sin cambios —sólo las cuatro tablas de metadatos— y pin
`ac0738d5c2039412b603dc71adc41721`. El paquete sigue en 16 definiciones, 7
opciones, 3 plantillas, 31 usos y 8 compartidas. Y lo que verifiqué en el
dictamen anterior sigue en pie: la única definición que difiere del congelado es
`fluid_type`, estrechada al dominio vivo, y **la migración no la escribe**.

## Mi ejemplo estaba mal, y la corrección es la parte que importa

Presenté como contradicción representable un envase que designa DOT 5.1 y
declara cumplir DOT 4. No lo es. La ficha técnica de Motul edición 01/22 publica
para su DOT 5.1 el cumplimiento conjunto de FMVSS 116 DOT 3, DOT 4 y DOT 5.1, y
las clases 3, 4 y 5.1 de ISO 4925. Un líquido real cumple varias
especificaciones a la vez, así que mi «contradicción» habría rechazado un
producto legítimo — el error exacto que llevo tres bloques señalando en otros.

Lo que HY-A sí encontró, y sigue siendo válido, es la **ambigüedad**: una celda
de texto libre que podía cargar un grado DOT junto a la celda tipada que lo
posee. La adjudicación separa las dos cosas correctamente: la designación
comercial por un lado, cuatro cumplimientos tipados por otro, y el vocabulario
de la norma secundaria sin ningún grado DOT dentro.

## Nueve sondas sobre el cambio

| Sonda | Resultado |
|---|---|
| designación DOT 5.1 con cumplimiento DOT 3, 4 y 5.1 a la vez | limpio — la forma de Motul se registra |
| designación combinada «DOT 3 / DOT 4» | limpio |
| cumplimiento DOT 5 sobre base no silicona | **bloquea** `row_value_conflict` |
| designación DOT 5, base silicona y su cumplimiento | limpio |
| mineral declarando cualquier cumplimiento DOT | **bloquea** `row_field_applicability` |
| escribir «DOT 4» en la celda de norma secundaria | **bloquea** |
| referencia sin clasificar conservando su texto | limpio |
| referencia sin clasificar sin texto | `row_required_missing` no bloqueante |
| declaración por modelo sin edición | `row_incomplete` no bloqueante |

Una precisión sobre la sexta: yo esperaba `row_option` y el motor entrega
`row_shape`. La diferencia es a favor del candidato — al ser `standard` un token
con vocabulario, el valor se rechaza en el parseo del esquema, **antes** de que
la capa de condiciones de fila llegue a mirarlo. La puerta se cierra una etapa
más temprano de lo que yo había previsto.

La coherencia entre base y cumplimiento está expresada en positivo, con
`expected: false` sobre cada booleano según la base — sin negación y sin ampliar
la gramática. Es la misma técnica que cerró V-1 en cables y SH-1 en suspensión, y
aquí evita además el bloqueo que mi propuesta habría impuesto a un producto real.

## HY-B: el alcance quedó donde debía

`target_edition` y `hose_edition` son ahora **requeridas** en las dos tablas de
declaración, así que la clave compuesta ya no queda sin resolver por su columna
más probable de faltar. Comprobado: una declaración por modelo sin edición
muestra `row_incomplete` **no bloqueante**, sin año inventado ni sustituido por
cero. Es el comportamiento correcto: pendiente visible, guardado permitido.

Queda en pie lo que el documento ya declara y yo confirmo: la unicidad sigue
exigiendo la clave resuelta y no compara alias, de modo que dos textos distintos
para la misma edición siguen sin reconocerse. No es un defecto de este candidato
sino del mecanismo, y está escrito donde corresponde.

## Riesgos reales que quedan, y no son bloqueo

- **Los cuatro cumplimientos son booleanos sin valor por defecto**, lo cual es
  correcto —ausencia es desconocido, no «no cumple»—, pero significa que una
  botella sin ningún cumplimiento marcado y una botella que no cumple nada se
  ven igual salvo por la ausencia. La distinción vive en que nadie los completa
  automáticamente, y el helper lo dice; no hay forma de expresarla mejor sin un
  tercer estado por celda.
- **`edition` sigue opcional en las normas secundarias**, a diferencia de las dos
  tablas de declaración. Es defendible —una norma citada sin edición sigue
  identificando la norma— pero es una asimetría deliberada que conviene tener
  presente si alguien la lee como olvido.
- **Ninguna cifra de las fichas de Motul entró**, y así debe quedar: el documento
  sólo toma de allí el hecho del cumplimiento conjunto, no las propiedades de su
  tabla.

## Lo que no verifiqué

No corrí los 42 casos SQL, las cinco pruebas del publicador, ni la suite Dart
completa de 45; no consulté preimagen viva, respaldo ni estado de aplicación. No
abrí las fichas de Motul: tomo su contenido de tu lectura declarada, y lo digo
para que no se lea como verificación mía.

Sigue sin ser aprobación mecánica. El esquema representa estas declaraciones y se
niega a contradecirse dentro de una fila; que una botella concreta sirva a un
freno concreto es una afirmación del fabricante, y la puerta global del
consumidor permanece abierta con el fill en cero.
