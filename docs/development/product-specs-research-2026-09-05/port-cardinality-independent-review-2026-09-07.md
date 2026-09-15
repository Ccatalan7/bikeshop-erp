# Recuento de puertos y corrección de luces: revisión independiente

Claude, revisor independiente · 2026-09-07

Reviso tu integración y tu corrección. No toco tus archivos, no leo base de datos y no escribo hechos. La revisión anterior queda congelada en `row-gap-closure-review-2026-09-07.json`, SHA `aeef526190b16d7a9acd7b0c46de6aa81e82a4a9b2a9a733505cc63ada9e4862`.

**Aviso de huella.** El catálogo coincide con el que nombraste, `16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`. El archivo de casos ya no: lo nombraste como `682e10011a5259bd9f603e0864f18c3c001080f6d3a98f18dd755e61c8835e9f` y cuando terminé de leerlo daba `329ad3e5543048121775fd7fc3d5c5b4acd90d7446cd3deacc999b4dce3716d7`, con los mismos 323 casos y el mismo `catalogue_sha256` declarado. Comprobé los cuatro casos `PORT-` uno por uno y su contenido es idéntico en la versión que tengo, así que la revisión de abajo se sostiene; el cambio está en otra parte del archivo, presumiblemente tu corrida de paridad.

## Tu corrección de luces es correcta, y mi propuesta estaba mal

La verifiqué por tres caminos independientes y los tres la sostienen.

**1. El grano dentro de un mismo miembro.** `light_mode_configurations` declara `unique_by: []` explícitamente vacío y lleva `operating_conditions`, `measurement_method`, `member_revision` y `source_url`. Eso es un esquema diseñado para admitir varias filas del mismo modo del mismo miembro. No es una hipótesis: en tus propios casos congelados, `light_kit_same_revision_twice` y `light_kit_group_ride_twice_without_revision_undetectable` tienen dos filas de «Group Ride» para el miembro `m-rear`.

**2. El grano entre miembros.** La columna `member_id` es requerida, así que una ficha de conjunto tiene filas de varios miembros. Leí la fuente que citas: el combo declara **cuatro modos por cada luz** —«Four light modes (High / Low / Daytime HyperConstant / Flashing)» para el AMPP500 y «4 modes» para el ViZ150— y no publica un total del conjunto. Un escalar por ficha no puede totalizar filas de dos miembros.

**3. El daño concreto.** Con la cardinalidad activada y `modes_count` en 4, una luz cuyo modo se documenta dos veces bajo dos métodos de medición produce cinco filas y dispara `row_cardinality_conflict`, que **bloquea**. La ficha sería correcta y el motor la rechazaría. Es justo el patrón de observaciones en competencia que la integración de luces conservó a propósito.

Mi propuesta trataba `modes_count` y las filas como el mismo objeto. No lo son: el total cuenta modos declarados por luz y las filas cuentan observaciones. El error fue mío y no lo vi porque me apoyé en que el nombre del total y el de la tabla coincidían.

## El recuento de puertos sí tiene el grano correcto

La diferencia es verificable en el esquema, no en el nombre.

| | `power_port_configurations` | `light_mode_configurations` |
|---|---|---|
| Rótulo | Puertos (uno por fila) | Modos por luz (lúmenes y autonomía juntos) |
| `unique_by` | `[[port_id]]` | `[]` |
| Dimensión de miembro | no existe | `member_id` requerido |
| Columnas de observación | ninguna | condiciones, método, revisión |
| Total declarado | `ports_count`, por dispositivo | `modes_count`, por luz |

Comprobé además que `consumer_electronics` **no tiene tabla de miembros**: no hay ninguna dimensión de conjunto que pueda inflar las filas por encima de un total por dispositivo. El riesgo que invalida las luces no existe aquí.

La cardinalidad tampoco aprieta nada nuevo: `unique_by: [[port_id]]` ya impedía dos filas del mismo puerto antes de esta integración. Y `ports_count` quedó con `min: "1"`, que conserva el significado sin abrir el dominio al cero.

### Los cuatro casos, revisados

| Caso | Filas | `ports_count` | Esperado | Mi lectura |
|---|---|---|---|---|
| `PORT-fewer_ports_pending` | 2 | 3 | `row_cardinality_pending` no bloqueante | correcto: faltan puertos por documentar, no hay contradicción |
| `PORT-extra_port_conflict` | 2 | 1 | `row_cardinality_conflict` | correcto: más ocurrencias que el total declarado sí es contradicción |
| `PORT-unknown_total_pending` | 2 | ausente | `row_cardinality_pending` no bloqueante | correcto: el total no se deduce de las filas |
| `PORT-unknown_label_still_counts_occurrence` | 2 | 1 | `row_cardinality_conflict` | correcto, y es el que más me importa: un puerto de etiqueta desconocida sigue ocupando una ocurrencia, igual que un diente desconocido no elimina la corona |

### Un riesgo residual, acotado

Si una ficha documentara un puerto que el fabricante no cuenta —un puerto de servicio, o uno de un accesorio incluido— el conflicto bloquearía una ficha correcta. Es el mismo mecanismo que invalida las luces, en una escala mucho menor porque no hay miembros. Si aparece, la salida no es inflar el total: es decidir si eso es un puerto. Lo dejo anotado como riesgo, no como defecto.

## Qué corrijo de mi entrega anterior

En `row-gap-closure-review-2026-09-07.json` propuse cerrar G09 en `light_mode_configurations` y en `power_port_configurations` con la misma corrección mínima. La mitad de puertos era correcta y la integraste. La mitad de luces es incorrecta: no basta con subir `row_coherence` a version 2 y darle dominio al total, porque el problema no es el dominio sino el grano. `light_mode_configurations` queda sin cardinalidad y su G09 vuelve a ser carencia de dato, no cerrable.

Corregido el recuento de aquella entrega: de las 50 instancias, **1 cerrada** en vez de 2, y 32 requisitos de dato en vez de 31.
