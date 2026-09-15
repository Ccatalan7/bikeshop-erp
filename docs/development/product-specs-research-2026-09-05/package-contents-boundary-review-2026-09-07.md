# Contenido de conjuntos: revisión independiente — 2026-09-07

La cantidad nueva **separa correctamente contenido de configuración**. Admite
cero, mantiene desconocido como pendiente y no copia el conteo legacy. Hay una
corrección de representación antes del llenado: la tabla de platos incluidos
conserva la posición de montaje como clave única. Además, el cotejo entre cantidad
y filas sigue siendo un gap real del motor. **AG01 permanece abierto.**

El [JSON de revisión](package-contents-boundary-review-2026-09-07.json) contiene
cuatro parches de metadatos con preimágenes exactas y 19 casos del contrato
propuesto. Los parches no se aplicaron. El diseño de cardinalidad está marcado
como no ejecutable por el motor actual; no es un nuevo DSL listo para publicar.

## Evidencia del cambio actual

Se reprodujo `compile_package_contents()` en memoria, sin ejecutar su `__main__`
ni escribir los artefactos resultantes. Coinciden los cuatro archivos congelados:

| Artefacto | SHA-256 |
| --- | --- |
| Catálogo de contenido | `20a9c1eabdf84dd5e3e9cb5a4a922a695c6e91deff53bebdb2e0c584b5e8edee` |
| Casos de contenido | `f87a94087f0a325d637f58833d61c5568e95cc52bb5e27fd126a1306aa5eb1ae` |
| Propuesta de Root | `8428447ff39b385d29da28faa5d2997bffca34ee252308359b910dc13fcbaac8` |
| Decisiones de Root | `2a988ed6bc65fda4ad0d1c5b59d7313d0eca965b424520cfd9c1533e06950d65` |

La plantilla `bicycle` y la definición compartida `chainring_count` permanecen
idénticas a la base. `crankset` y `drivetrain_kit` conservan ID y familia. Sólo en
ellas el conteo antiguo queda legacy. El campo nuevo no exige que un kit incluya
bielas, no se limita a 1/2/3 posiciones y no deduce sus valores de nombres o datos
antiguos. El cambio de rótulo del conjunto de freno tampoco fabrica miembros.

Se ejecutó un probe Flutter independiente autorizado:

```text
fvm flutter test .tmp/product-spec-catalog/package-contents-boundary-probe.dart --no-pub --reporter expanded
00:00 +22: All tests passed!
exit_code=0
```

Incluye los 13 casos congelados de contenido y nueve límites adicionales. Parte
de las aserciones **reproduce gaps abiertos**; que pasen no significa que el motor
ya resuelva la cardinalidad. Los 381 Dart, 272 SQL y 180 Python del documento de
integración son evidencia atribuida a Root; no se repitieron en esta revisión.

## PCB01: posición de montaje no es identidad del contenido

`chainring_teeth_rows` ahora describe lo suministrado, pero su esquema conserva
`unique_by: [[position]]` y `position.required=true`. El parser de filas rechaza
dos posiciones iguales en `product_spec_rows.dart:123`; la validación del borrador
lo presenta como `row_shape` bloqueante.

Reproducción sintética: `included_chainring_count=2`; filas con IDs distintos,
dientes 30 y 32, ambas para posición 1. La tabla no puede representar ambos
platos suministrados sin inventar una segunda posición. Ese caso describe dos
alternativas/repuestos **incluidos**, no dos opciones de compra. No se localizó
un paquete OEM exacto con esas dos coronas ni se atribuye el caso al stock.

Corrección mínima de metadatos: quitar la unicidad por posición y hacer esa
posición descriptiva opcional. La identidad estable de la fila sigue siendo
única. En una copia en memoria, esos dos ajustes eliminan el falso bloqueo y
permiten conservar dientes conocidos sin inventar posición. Los parches
`PCB-P01` y `PCB-P04` incluyen el esquema completo anterior y los rótulos/helpers
exactos. No cambian claves, tipos ni unidades de columnas.

En **esta etapa inédita**, basta conservar `chainring_teeth_rows` como único dueño
del contenido y retirarle la autoridad de posición única de montaje. La definición
es nueva y sólo la usa `crankset`; añadir otra tabla idéntica produciría dos dueños
del mismo dato. Si aparecieran datos ya publicados con semántica de configuración,
habría que crear un dueño de contenido separado y conservar aquellos datos: esta
recomendación no autoriza reinterpretar facts existentes ni configuraciones OEM.

## Unidad de conteo y fuentes exactas

El total debe contar **platos o coronas dentadas suministrados**, no piezas
separables, unidades comerciales ni posiciones que se usan simultáneamente.

- [SRAM CR-RED-KIT-E1](https://www.sram.com/en/sram/models/cr-red-kit-e1) declara
  construcción de una pieza y combinaciones 2x. Un monobloque comercial puede
  contener dos coronas. Por tanto, `kit_members.quantity=1` no puede refutar por
  sí solo `included_chainring_count=2`. El probe confirma que el cambio actual no
  introduce ese rechazo. Los parches `PCB-P02/P03` aclaran la unidad; no implican
  que el helper anterior ya obligara a contar unidades comerciales.
- [Profile No Boss](https://www.profileracing.com/product/no-boss-3-piece-chromoly-race-crankset/)
  documenta bielas, eje y accesorios, y requiere plato o spider adecuado aparte.
  Sustenta permitir cero; no identifica J253.
- [SRAM GS-GX-1E-A1](https://www.sram.com/en/sram/models/gs-gx-1e-a1) presenta un
  kit de actualización con bielas y plato como no aplicables. Un kit de transmisión
  no exige esas piezas. El probe permite cero con un miembro de cambio trasero.
- [Extralite QRC3S-B](https://www.extralite.com/products/927/qrc3s-b) distingue
  Base Kit y Full Kit; el Full incluye 52T **o** 54T. Dos alternativas publicadas
  no son dos platos suministrados. Hace falta fijar la variante antes de llenar.
- [Race Face Turbine](https://www.raceface.com/products/turbine-crankset) declara
  platos vendidos aparte, aunque las condiciones de pesaje usan uno de 32T.
  Ese dato de medición no puede crear una fila de contenido.

Estas son fuentes sobre los modelos indicados, no identificación de productos
del ERP ni reglas de compatibilidad para otras marcas. Para este límite se
necesita contenido OEM concreto; las generalidades mecánicas de Sheldon/Park no
determinan qué vende cada variante.

## PCB-G01: contrato mínimo de cantidad frente a filas

Primera aplicación: sólo `crankset`, entre `included_chainring_count` y
`chainring_teeth_rows`. El kit de transmisión no tiene esa tabla y no debe recibir
una dependencia sobre un campo ausente.

Cada fila válida debe representar una **ocurrencia de corona suministrada**,
independiente de su posición. Un par integrado tiene dos coronas; dos copias del
mismo dentado siguen siendo dos ocurrencias. Dos lecturas de la misma corona se
conservan bajo una sola identidad de contenido, con sus fuentes. No se cuentan
filas de opciones, posiciones únicas, modelos distintos ni URLs.

Sean `N` el total entero exacto declarado y `R` las ocurrencias documentadas bajo
esos IDs. Primero se validan tipos/esquemas; un documento inválido no se cuenta.

| Estado | Resultado |
| --- | --- |
| N ausente | Pendiente de total declarado; no deducir N desde R. |
| N=0 y tabla ausente | Coherente respecto del conteo, sin aprobación mecánica. |
| N=0 y tabla no vacía | Conflicto; reutilizar el actual `field_applicability`, sin duplicar el diagnóstico. |
| N>0, R>N | Conflicto bloqueante del total frente a las filas conocidas. |
| N>0, R<N, incluso tabla ausente | Completitud pendiente, no incompatibilidad ni fila inventada. |
| R=N | Conteo equilibrado solamente; conservar pendientes de dientes, evidencia y montaje. |
| N o tabla inválidos | Mantener el diagnóstico de tipo/rango/integer/row_shape; no redondear ni generar otro resultado engañoso. |

Se reprodujo que hoy `N=2/R=3` y `N=2/R=1` no generan respectivamente conflicto
ni pendiente de cardinalidad. La condición `N>0` sólo administra aplicabilidad y
requisito. `ProductSpecCoherence` admite vínculos y parejas escalares; no tiene un
operador para cantidad de filas. Una coincidencia `R=N` tampoco acredita que cada
fila tenga todos sus datos: desconocer dientes no elimina una corona ya
documentada del conteo.

La implementación futura debe comparar enteros exactos, leer ambos extremos en
la misma revisión y evaluar el resultado después de preservar/mezclar filas y
fuentes existentes. Cambiar un ID visualizado, el orden o una fuente no altera el
total. Debe rechazar el contrato en clientes antiguos que no sepan interpretarlo;
añadir una clave que aquellos ignoren dejaría una falsa validación. Dart, SQL,
referencias y guardas de publicación necesitan el mismo contrato y pruebas de
concurrencia antes de activarlo.

No se suma `kit_members.quantity` en este mínimo. Primero harían falta tipo,
unidad de cantidad, inclusión, variante y alcance padre/hijo confirmados, además
de vínculos que impidan contar dos veces una biela/conjunto y sus coronas. Ni
`family=chainring` ni el texto «plato» resuelven por sí solos un monobloque o una
fila incompleta. Sin esa información, la reconciliación con miembros queda
pendiente; ausencia de miembros conocidos no demuestra cero.

No se accedió a DB ni runtime, no se editaron archivos de Root y no se publicaron
metadatos ni productos. Los parches locales propuestos y el contrato mínimo no
cierran AG01, identidad/SKU, compatibilidad OEM ni el llenado global.
