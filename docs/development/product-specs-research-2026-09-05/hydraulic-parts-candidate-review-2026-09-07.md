# Hidráulica — dictamen independiente sobre el sucesor de root (2026-09-07)

Lectura y veredicto. No edité candidatos, motor, migración ni base; no corrí el
publicador SQL ni consulté producción. Las sondas corrieron contra el catálogo
**sin modificar**, con archivos de casos propios en el scratchpad.

**Veredicto: publicable.** Los diez puntos de la adjudicación se sostienen,
medidos uno por uno. **Un hallazgo de representación** (HY-A) y **una medida
precisa del alcance de un límite ya declarado** (HY-B).

## Integridad

Los ocho SHA-256 recomputados coinciden exactamente con los declarados, incluidos
compilador base `a666cd2a…aa85`, adjudicador `e355283e…9c6a`, migración
`b268af0a…dd83` y verificador `5314b821…22cd1`.

**La invocación del adjudicador es obligatoria en los dos sentidos que importan:**
`from compile_hydraulic_parts_root import review_hydraulics` es import de nivel
superior —sin él el compilador no arranca— y `review_hydraulics(...)` se llama en
la línea 245 sobre las tres estructuras. No hay ruta que produzca artefactos sin
pasar por él.

**40 pruebas Dart: las corrí yo, pasan** (3 de metadatos y 37 casos). Aritmética
del paquete: 16 definiciones nuevas, 7 opciones, 3 plantillas, 31 usos, 8
compartidas preservadas. Superficie de escritura sólo sobre las cuatro tablas de
metadatos y pin del motor `ac0738d5c2039412b603dc71adc41721`. Y comprobé lo que
la ronda anterior había roto: **ninguna fixture contiene ya una celda `null`**.

### `fluid_type` merece una frase, porque un diff ingenuo engaña

Comparado con el **congelado**, `fluid_type` aparece como definición compartida
modificada, y la comparten cuatro familias. No es una mutación: el congelado
proponía cinco opciones y el candidato las **reduce a las tres vivas**
(`Aceite Mineral`, `DOT 4`, `DOT 5.1`), que es exactamente lo que trae
`reused_definitions`. Verifiqué lo decisivo: **`fluid_type` no está en
`records.spec_definitions`**, así que la migración no la escribe, y su rol en
`brake_fluid` es `legacy`. El candidato se alinea con producción; el congelado
era el que estaba equivocado.

## Los diez puntos, medidos con veintiocho sondas

| Sonda | Resultado |
|---|---|
| 2.000 mm declarados **y** `cut_to_install` | limpio — largo y corte son independientes |
| dos acoples de cáliper en extremos A y B | limpio |
| mismo extremo físico dos veces | **bloquea** `row_shape` |
| extremo apuntando a un tramo inexistente | **bloquea** `row_reference_unresolved` |
| rosca 8 mm con paso 26 tpi | limpio — unidades independientes |
| designación literal cargando un paso | **bloquea** `row_field_applicability` |
| extremo sin rosca cargando un diámetro | **bloquea** |
| oliva con largo de inserto | **bloquea** |
| aplicación apuntando a una pieza inexistente | **bloquea** |
| misma aplicación con **edición de manguera distinta** | limpio — se conserva |
| mismo envase declarado dos veces | **bloquea** `row_shape` |
| dos envases con formulaciones distintas | limpio |
| envase DOT sin designación | `row_incomplete` **no bloqueante** |
| mineral declarando grado DOT | **bloquea** `row_field_applicability` |
| DOT 5 con base no silicona | **bloquea** `row_value_conflict` |
| DOT 5.1 con base silicona | **bloquea** |
| mineral con base silicona | **bloquea** |
| mineral citando ISO 7308 con edición y alcance | limpio |
| norma o modelo apuntando a un envase inexistente | **bloquea** |

Tres de mis sondas fallaron por culpa mía y conviene decirlo, porque una de ellas
es informativa: pasé `dot_grade: null` para dejar una celda pendiente y el parser
la rechazó como celda tipada inválida — es **exactamente** el fallo que ya
detectaste y corregiste en el primer pase, y confirma que el arnés endurecido
funciona. Las otras dos arrastraban `dot_grade` en una fila mineral y por eso
sumaban una incidencia que yo no había previsto.

## HY-A — la celda dueña del grado DOT tiene una puerta trasera de texto libre

La decisión 8 dice que el grado DOT tiene una única celda dueña. Medido, esa
unicidad es una convención, no una compuerta: `brake_fluid_standard_claims.standard`
es texto libre sin vocabulario, así que un envase puede declarar
`dot_grade = 'DOT 5.1'` en la fila de formulación y, enlazado a ese mismo envase,
una fila de norma cuyo `standard` dice **`DOT 4`**. La sonda no produce ninguna
incidencia.

Es la misma clase que DT-1 en transmisión: un texto libre que carga un valor cuya
celda dueña está tipada al lado. La severidad es menor que allí, porque cualquier
consumidor que lea el grado leerá `dot_grade`; el daño es para quien lea la tabla
de normas, que verá dos grados y ninguna señal. Y no hay ambigüedad de intención:
la propia decisión declara que la celda dueña es única.

Arreglo acotado disponible sin tocar el motor: dar vocabulario a `standard`
excluyendo los grados DOT, o añadir un `standard_family` que gobierne qué puede
escribirse allí. Las columnas de fila admiten `allowed_values`; esta misma tabla
usa tokens en otras columnas.

## HY-B — dónde deja de alcanzar la clave compuesta

El documento ya lo declara: «las claves compuestas sólo detectan conflicto cuando
su identidad está resuelta». Lo medí para fijar su alcance exacto, porque la
consecuencia práctica no es obvia:

- dos aplicaciones idénticas con **`target_edition` puesta en ambas** y estados
  opuestos → **bloquea** `row_shape`;
- las mismas dos con **`target_edition` sin poner** → **pasan en silencio**;
- con ediciones **realmente distintas** → se conservan las dos, como debe ser.

O sea: la guardia es más débil justo donde las ediciones están sin resolver, que
es donde más probable es que un catálogo real llegue. No lo llamo defecto —está
declarado y es consecuencia del mecanismo, no de un olvido— pero conviene que
quede escrito con esta precisión, porque «clave compuesta» suena a garantía y
aquí es una garantía condicionada a que alguien haya respondido la edición.

## La corrección que me hiciste, y es mía

Yo afirmé que **el aceite mineral no tiene norma publicada** y construí sobre eso
una compuerta: prohibir `specification` para mineral y exigirle la designación
del fabricante. No tenía fuente para ese universal; lo deduje de que no encontré
ninguna norma mineral. El resumen oficial de ISO 9128:1987 citando fluidos de
base petróleo bajo ISO 7308 lo refuta. La sonda confirma que ahora un envase
mineral **sí** puede citar una norma con su edición y su alcance.

Es la tercera vez en esta serie que convierto una ausencia de evidencia en una
regla. Las dos anteriores fueron de ámbito —declarar inexpresable lo que sólo
estaba en el ámbito equivocado—; ésta es de fuente, y es peor, porque una regla
mal fundada no falla ruidosamente: prohíbe en silencio. Lo dejo escrito.

Añado una segunda, menor: mis fixtures ponían URLs de Park como `source_url` de
filas de líquido. Park separa ámbitos mineral y DOT y no incluye líquido, así que
sus listas no son aprobaciones de fluidos; usarlas como fuente de una declaración
de envase era un paso de más. El sucesor no lo hace.

## Lo que no verifiqué

No corrí el publicador SQL ni los 37 casos SQL —siguen a tu cargo—, no consulté
la preimagen viva ni el respaldo, y no comprobé
`.tmp/product-spec-catalog/hydraulic-parts-dart.log` ni
`.tmp/db/hydraulic-parts-publication-tests.log`. No abrí ninguna de las fuentes
esta ronda: los límites que declaras —PDF de Jagwire y fichas actuales con error,
Shimano con texto abierto pero captura sin imagen y descarga 403— coinciden con
lo que yo mismo encontré en mi ronda, donde `si.shimano.com` me devolvió 403 en
las dos rutas que probé.

Nada de esto es aprobación mecánica. Los enlaces dan ámbito y las claves detectan
contradicción cuando la identidad está resuelta; que una botella concreta sirva a
un freno concreto sigue siendo una declaración del fabricante, y el consumidor
global que debe resolver envase/pieza y modelo/edición antes de usarla continúa
pendiente, con el fill en cero.
