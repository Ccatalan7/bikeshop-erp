# Revisión independiente del alcance del consumidor — 2026-09-07

**Sin nuevas regresiones reproducidas en el cambio acotado.** Pasaron las 82
pruebas existentes del servicio en una ejecución independiente. Se acepta esta
corrección de límites con los pendientes de modelo, rueda y alcance del taller
explícitos; no se declara completitud mecánica ni se habilita el llenado.

La revisión fue de lectura. No se editaron implementación ni pruebas, no se
consultó ninguna base de datos y no se operó el runtime. El [JSON del dictamen](consumer-scope-boundary-review-2026-09-07.json)
contiene casos, fuentes, hashes y límites reproducibles.

## Estado revisado

Captura: `2026-09-07T14:40:15.875217+00:00`.

| Archivo | SHA-256 |
| --- | --- |
| `lib/modules/bikeshop/services/bike_product_compatibility_service.dart` | `1b92589665640c7b02dac9f915be956d328a432b08596d16aeca0bf6a507145d` |
| `test/unit/bike_product_compatibility_service_test.dart` | `f04717e2e278ad17a391617b0b50a1144a023af40625f83676f6318e912ffc4e` |

El diff contra HEAD incluye rondas anteriores. Este dictamen se limita a las
comparaciones de identidad, frenos, pedalier y mando solicitadas, no a cada
cambio acumulado ni a todas las familias.

## Límites comprobados

| Caso | Resultado comprobado |
| --- | --- |
| Maza delantera 110 mm ante cuadro/horquilla con 100 mm y `rotor_mount_type` presente | `incompatible` por ancho. La familia de freno se exige antes de entrar al evaluador de frenos; un atributo compartido no evita la comprobación de maza. |
| Pastilla de llanta ante tipo agregado disco; freno delantero ante contrapedal | `caution`. Sin rueda y sistema instalados no se extrapola el dato agregado a ambos extremos. El rotor conserva su comparación parcial de diámetro. |
| Bielas Hollowtech/cuadradas y cuadro BSA | `caution`; no se compara la interfaz de biela como si fuera caja del cuadro. Una coincidencia parcial mantiene montaje y línea de cadena pendientes. |
| Pedalier 73/68 roscado o 92/89,5 a presión | `caution` por configuración sin recomendar adaptador. Mid frente a BSA sigue rechazando **montaje directo**. |
| `spindle_interface_accepted` contiene GXP y Hollowtech | Se revisan alternativas individuales. Hollowtech puede aparecer como coincidencia parcial; GXP solamente queda fuera de cobertura registrada, sin aprobar una adaptación. |
| Shifter sin lado o `Universal` | `caution` antes de comparar un extremo no identificado. `Universal` no se trata como `Par`. Se cotejaron los cuatro rótulos reales del catálogo. |
| Mando izquierdo con familia de indexado trasero diferente | Se conserva pendiente el tiro/indexado delantero; no se aprueba ni rechaza por la familia trasera. |
| Par 3x10 ante bici 2x12 | Prevalece el conflicto trasero 10/12 sobre el pendiente de cambio delantero. |
| 3x ante 2x, o desviador/bielas 2x ante 1x | Se exige cobertura del modelo o conversión explícita; no se recomienda omitir una posición. `compatible_chainring_counts` se lee y un texto como `modelo 2026` no fabrica una cantidad. |

Anclas del servicio: dispatch `452`, `474` y `492`; desviador `1098`; mando `1139`;
pedalier `1255`; crankset `1326`; interfaces aceptadas `3078`;
canonicalización de caja `3089` y `3108`; frenos `2213` y `2250`.

## Contraste de las fuentes

[Park Tool: estándares de pedalier](https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-standards-and-terminology)
separa caja, rosca/ajuste y eje. [Park Tool: selección para presión](https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-tool-selection-press-fit)
distingue el diámetro de encaje en el cuadro de los ejes admitidos y describe
adaptadores propios. Esas fuentes respaldan separar interfaces; no autorizan un
adaptador por coincidencia nominal de 24 mm.

El manual [Shimano DM-MAFC002-11](https://si.shimano.com/en/pdfs/dm/MAFC002/DM-MAFC002-11-ENG.pdf),
páginas impresas 12 y 14, presenta 68/73 roscado y 89,5/92 a presión bajo
configuraciones distintas. Se confirma el rechazo de la propuesta D3 como regla
universal. Esto no hace roscado y pressfit intercambiables ni demuestra cobertura
de cualquier modelo o ancho.

[Sheldon Brown: contrapedal](https://www.sheldonbrown.com/coaster-brakes.html)
lo sitúa en la maza trasera y contempla freno delantero independiente. Por ello,
`brakeType=coaster_brake` no acredita ausencia o incompatibilidad de toda manilla
delantera.

[Shimano DM-SL0001-11](https://si.shimano.com/en/pdfs/dm/SL0001/DM-SL0001-11-ENG.pdf),
páginas 12–16, distingue mecanismos con y sin conversor; señala que SL-T780 y
SL-T670 no lo incorporan. [SI-5N20A-002](https://si.shimano.com/en/pdfs/si/5N20A/SI-5N20A-002-ENG.pdf)
describe una configuración concreta del selector. Ninguno sostiene que cualquier
mando triple funcione como doble dejando una posición sin usar.

## Evidencia y límites restantes

Comando ejecutado por este revisor:

```text
fvm flutter test test/unit/bike_product_compatibility_service_test.dart --reporter expanded
00:00 +82: All tests passed!
exit_code=0
```

Son fixtures sintéticas con caché estructurada. Comprueban comportamiento del
consumidor; no son evidencia OEM de un producto del stock ni prueban el transporte
RPC o la pantalla real. No se ejecutó un análisis estático nuevo en esta revisión.

También se leyeron las rutas reales del autocomplete. En
`lib/shared/widgets/product_autocomplete_field.dart:147`, el modo
`compatibleOnly` excluye sólo `incompatible`; `caution` sigue visible. La selección
en `1514` comunica el producto, y la entrada exacta por SKU/barcode en `1540`
también llama esa selección. El servicio, usado por el taller mediante
`tasks_tab_view.dart:206`, es un evaluador para ordenar/filtrar sugerencias, **no
un bloqueo de persistencia**. Esta frontera preexistente no se reporta como
regresión nueva ni como cierre de seguridad mecánica.

Siguen pendientes modelo/generación de las contrapartes, sistema por rueda,
objetivo de reemplazo o conversión, controles combinados y relaciones OEM
completas. AG01 continúa abierto: platos físicos incluidos, capacidad del
crankset y configuración instalada no son el mismo dato. La nueva cantidad del
catálogo no se asimila a la clave legacy para aparentar cobertura. El alcance de
esta aceptación termina en los nueve límites descritos.
