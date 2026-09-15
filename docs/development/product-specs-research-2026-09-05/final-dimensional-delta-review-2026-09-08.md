# Revisión final de los tres deltas dimensionales (sólo lectura) — 2026-09-08

Sin implementar, sin SQL ejecutado, sin runtime, git ni producción. No edité
ningún archivo revisado; sólo escribí este documento. Todo sigue sin activar y
sin rellenar productos.

## Qué verifiqué directamente

Corriendo Dart, no leyendo:

| suite | resultado |
|---|---|
| `test/unit/product_spec_strict_row_order_test.dart` | **23 verdes** |
| paquete de direcciones (catálogo + casos actuales) | **23 verdes** (1 metadatos + 22 casos) |
| paquete de mazas/llantas | **65 verdes** |
| paquete de rayos | **32 verdes** |
| sondas propias con fixtures de scratchpad, sobre los catálogos sin modificar | 6 + 3 + 4, todas concluyentes |

Leyendo y comparando artefactos: los SHA citados de mazas/llantas y rayos
coinciden con los archivos; los **ensayos de adopción frescos** llevan el SHA
del catálogo bajo revisión —`7585bdb1…` y `4a604b43…`— y reproducen
**89 y 48 evaluados, cero bloqueantes, 22 y 19 observaciones legacy, ninguna
activa sin proyectar y cero escrituras**. Los desgloses coinciden con lo
declarado.

**No verifiqué**: ninguna corrida SQL (63, 40 ni 31), el ensayo del paquete de
direcciones bajo extensión, ni el comportamiento del editor real. El SQL lo leí
como texto, nunca lo ejecuté. Tampoco certifico ningún montaje mecánico: todas
mis sondas son de representación con valores sintéticos.

## 1. Mazas y llantas: F1 y F2

**F1 está resuelta y de la forma que anunciaste**: la presencia explícita
gobierna las dos rutas. El nuevo `hub_drive_receiver_present` es **obligatorio
para toda maza suelta** —delantera, trasera o universal— y el tipo y la
referencia cuelgan de él, con la misma forma que ya usaba la fila
(`drive_interface_present`). La posición dejó de inferir el receptor sin dejar
de exigir la pregunta. Comprobado con sondas propias:

| sonda | resultado |
|---|---|
| maza **delantera** con presencia declarada `true` + tipo + referencia | pasa |
| la misma con presencia `false` + tipo | **bloquea** (`field_applicability`) |
| la misma sin declarar presencia + tipo | pendiente (`prerequisite`), no bloquea |

Que una maza delantera pueda nombrar un receptor cuando lo declara es la
consecuencia buscada, no un defecto: la aprobación mecánica sigue dependiendo
del modelo y nada aquí la concede.

**F2 está resuelta y algo más completa de lo pedido.** El agujero del asiento
del niple y el **agujero de acceso en el fondo del neumático** son campos
distintos, ambos con prerrequisito de procedencia, y el taladrado pasa a una
tabla por patrón con **datum obligatorio** y ángulo radial, ángulo axial y
zig-zag con sus unidades propias (° y mm) y su documento. Comprobado:

| sonda | resultado |
|---|---|
| las dos cotas de agujero con cifras distintas en la misma ficha | pasa |
| patrón de taladrado **sin** su datum | pendiente (`row_incomplete`) |
| el mismo patrón **con** su datum | pasa |

No encontré defectos vigentes en este delta.

## 2. Rayos: D1

Resuelta y conservando lo que pedía la observación. `spoke_thread_standard`
pasa a `required: never`, **mantiene** su aplicabilidad —sigue prohibida cuando
se declara que no hay rosca— y **mantiene** su prerrequisito de procedencia. La
regresión que impide que la exigencia vuelva usa `forbidden_issue_fields` sobre
ese campo en el caso que transcribe la fila OEM: es la forma correcta, porque
falla si alguien vuelve a exigir un nombre que la fuente citada no publica.

La adopción fresca lo confirma del otro lado: el desglose de pendientes ya no
contiene ninguna exigencia sobre esa designación, y conserva
`prerequisite:spoke_length_mm` en los 48. No reabro la propuesta histórica.

## 3. Orden estricto y dueño compartido

### 3.1 Lo que está bien, comprobado

- **Gramática y versiones.** El esquema acepta `version` 1 o 2 y rechaza 3;
  `strict_ordered_pairs` sólo existe en la versión 2 y se rechaza en la 1. El
  sobre de datos debe declarar la misma versión que su esquema.
- **Exactitud.** La comparación es decimal exacta: `4.1e1` frente a `41.00` se
  detectan como iguales y se rechazan, y una diferencia por debajo de la
  precisión de coma flotante (`…993.1` frente a `…993.2`) se conserva como
  orden válido. Un número JSON crudo se rechaza en vez de redondearse.
- **Incompletitud.** Una celda ausente deja la fila pendiente y **no** dispara
  el orden; falta el `required` como observación incompleta, no como negación.
- **Aislamiento entre filas.** El par se evalúa dentro de cada fila; el caso
  `separate_rows_never_supply_each_others_dimensions` fija que dos filas no se
  prestan cotas.
- **Rechazo antes de guardar.** El caso inválido no sólo emite `row_shape`
  bloqueante: también hace fallar `buildFactPayload`, que es la ruta de
  persistencia. Es más de lo que pedía la observación.
- **Convivencia.** `ordered_pairs` conserva `<=` —la igualdad inclusiva sigue
  siendo válida— y `strict_ordered_pairs` exige `<`.
- **Paridad Dart/SQL.** Leí el candidato SQL y las seis reglas coinciden con
  Dart una a una: versiones admitidas, `strict` sólo en la 2, igualdad de
  sobre, tipos decimal/entero, comparación `>` frente a `>=`, evaluación dentro
  del bucle de fila y rechazo de un número JSON. No encontré divergencia.
- **H1 cerrada en direcciones.** Los dos extremos declaran el par estricto y
  rechazan ID mayor **e igual** a OD. Verificado con un control propio: sobre el
  catálogo publicado, `30 / 41,8` pasa mientras `41,8 / 30` y `41 / 41`
  bloquean.
- **H2 adjudicada y escrita.** La readiness dice que el contenido es
  independiente del alcance: un juego superior puede incluir una pieza
  identificada sin declarar por ello un stack inferior. La ficha no cambió y no
  hacía falta que cambiara.

### 3.2 Defecto vigente G-1 · la regla de unidades cubre sólo una de las dos listas

El delta introduce una comprobación de unidades y la aplica **sólo** a
`strict_ordered_pairs`. En el mismo esquema versión 2, la lista inclusiva puede
ordenar dos columnas de unidades distintas sin ninguna queja.

Reproducción mínima, sobre el esquema de rodamientos publicado en el paquete de
direcciones, cambiando una sola clave:

| esquema | resultado |
|---|---|
| `ordered_pairs: [["inner_contact_angle_deg","bearing_outer_diameter_mm"]]` (° contra mm) | **aceptado** |
| `strict_ordered_pairs` con **esas mismas dos columnas** | rechazado |

La ruta escalar sí compara unidades para sus pares. El resultado es que un
esquema puede declarar hoy que un ángulo no supera un diámetro. Está igual en
Dart y en SQL, así que es una decisión de gramática y no un fallo de porte.

### 3.3 Defecto vigente G-2 · dos órdenes contradictorios sobre el mismo par se aceptan

Nada comprueba las dos listas entre sí, ni dentro de una lista. Un esquema
puede declarar el orden inclusivo en un sentido y el estricto en el contrario:

```json
"ordered_pairs":        [["bearing_inner_diameter_mm", "bearing_outer_diameter_mm"]],
"strict_ordered_pairs": [["bearing_outer_diameter_mm", "bearing_inner_diameter_mm"]]
```

Ese esquema **se acepta**. A partir de ahí, ninguna fila con las dos cotas
puede existir. Reproducido con tres filas bien formadas:

| fila | con el esquema publicado | con el esquema contradictorio |
|---|---|---|
| interior 30 · exterior 41,8 (anillo correcto) | pasa | **bloquea** |
| interior 41,8 · exterior 30 | bloquea | bloquea |
| interior 41 · exterior 41 | bloquea | bloquea |

La ruta escalar previene justamente esto con una detección de ciclos; la ruta
de filas no tiene ninguna. El fallo es ruidoso —falla cerrado y en todas las
filas— pero lo que se ve al final es un `row_shape` sobre datos correctos, y la
causa está en el metadato. Declarar el mismo par en las dos listas también se
acepta; ahí no hay daño porque el estricto absorbe al inclusivo.

Las dos correcciones caben donde ya está la validación del esquema y no piden
motor nuevo, pero el archivo es del dueño compartido: no propongo tocarlo aquí.

### 3.4 Precondición que conviene dejar escrita, no defecto

El sobre de datos debe declarar exactamente la versión de su esquema, y hay una
prueba que lo fija a propósito (`old_envelope_cannot_enter_new_schema`). La
consecuencia es de migración: **publicar un esquema versión 2 sobre un campo
que ya tiene filas guardadas con `schema_version` 1 convierte cada observación
guardada en un `row_shape` bloqueante** hasta que su sobre se reescriba. Hoy no
afecta a ningún producto —no hay esquema versión 2 publicado y las tablas de
direcciones no tienen filas guardadas—, pero es una precondición del momento en
que se publique, y no la vi escrita en ningún sitio.

### 3.5 Defecto de documentación en la readiness de direcciones

El archivo se contradice consigo mismo sobre la geometría anular. En un
párrafo declara H1 resuelta con sus dos regresiones; más abajo, la sección de
pendientes sigue diciendo que quedan «dos límites mecánicos explícitos»
incluida «exigir la geometría anular estricta», y que «el motor actual de pares
ordenados admite igualdad».

Eso ya no es cierto: la igualdad se rechaza —lo comprobé con el control de
§3.1— y el caso pendiente correspondiente **ya fue retirado** del archivo de
casos, que hoy conserva un solo pendiente. Es el JSON el que está al día y la
prosa la que quedó atrás. Importa porque la readiness es lo que lee quien
adjudica.

## 4. Resumen

Los tres deltas hacen lo que anuncian y lo comprobé ejecutando: F1 con la
presencia gobernando ambas rutas, F2 con las dos cotas de agujero separadas y
el taladrado por patrón con datum, D1 con la designación opcional sin perder
fuente ni aplicabilidad, y H1 cerrada con el orden estricto, incluida la
igualdad. La paridad Dart/SQL del orden estricto no muestra divergencias.

Quedan dos defectos vigentes, ambos en la gramática del esquema de filas y
ambos presentes en los dos motores —**G-1**, la regla de unidades cubre sólo la
lista estricta; **G-2**, dos órdenes contradictorios sobre el mismo par se
aceptan y bloquean toda fila correcta—, una precondición de migración sin
escribir y una readiness que se contradice sobre lo que ya se corrigió.
