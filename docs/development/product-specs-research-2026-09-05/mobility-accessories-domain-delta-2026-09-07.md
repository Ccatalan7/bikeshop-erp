# Delta de dominio: dos contraejemplos OEM, alcance de `volume_l` y presión de herramienta

2026-09-07. Para integrar, no para planificar. Catálogo congelado
`all-family-port-cardinality-integrated-2026-09-07.json` (`16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`).
Paquete: `mobility-accessories-domain-delta-2026-09-07.json` —
`2da618f89190bdade42e5d509a2eb93ba9e67aab6ef37b6ed6d48a7ac3efe62d`.

**Tus dos contraejemplos son reales y ambas propuestas son correctas en la forma. Cada una necesita
una corrección de alcance, y encontré un defecto nuevo en `pump`.**

## Correcciones tuyas que acepto

`kit_members`: mi lectura era de **uso** de plantilla. Extender el helper a `light`, `fender` y
`training_wheel` es un cambio de uso y no exige mutar la definición compartida ni tocar a los otros 20
usuarios. Retiro la frase «un forward que nombre a las 23».

Son **9** definiciones reutilizadas en la preimagen viva, no 8: mis 8 contaban sólo las del primer
packet y dejaban fuera `spec_evidence_source`.

MA-2: no generalizo que `json` = criterio inútil. Lo que medí es que el consumidor no filtra por rol
ni por `allowed_when`; qué hacer con las tablas de filas depende de sus consumidores.

## Fuentes

**S1 — Topeak HYBRIDROCKET HP, leída textual.** «Road mini pump, CO2 inflator, or both. The choice is
yours!»; «The mini-sized pump and integrated CO2 inflator lets you choose between pumping, inflating
with CO2 or a combination of both.»; «Capacity: 160 psi / 11 bar»; «Use only Topeak 16g CO2
cartridges»; «Included 1 threaded 16g CO2 cartridge».

**S2 — el manual PDF, ilegible.** Se descargó (425,8 KB) pero no se pudo extraer texto ni renderizar:
`pdftoppm` no está instalado. No sustituyo su contenido por una lectura plausible. La evidencia que
uso es S1, que ya es del fabricante y es textual.

**S3 — CamelBak M.U.L.E. 5, parcial.** Verifiqué textual el nombre «M.U.L.E.® 5 Waist Pack with Crux®
1.5L Lumbar Reservoir» y la categoría «waist pack»; las variantes británica e irlandesa lo titulan
«M.U.L.E.® **5L** Waist Pack…», con la L explícita. El depósito viene incluido: está en el nombre del
producto y en el SKU. **La tabla de especificaciones se renderiza por JavaScript y no llegó en ninguna
de las tres páginas: no pude leer si los 5 L incluyen el depósito o son sólo carga.** No lo deduzco —
y esa laguna es, ella misma, el argumento de DL-3.

## DL-1 · Bomba híbrida: el facet es suficiente, con una corrección de alcance

El defecto está confirmado. `pump_kind` es `single_select` y la tabla de CO2 está `allowed_when
pump_kind in ["Inflador CO2","Cartucho CO2 (recarga)"]`. Con «De mano / mini» se bloquea justo lo que
el fabricante declara —16 g, roscado, 1 incluido—; con «Inflador CO2» se le cambia el nombre a un
producto que el OEM llama *mini pump*. `valve_heads_supported` no discrimina: es requerido en ambos.

**Corregir — el alcance del facet.** Como disyunción («tipo dedicado O facet=true»), un `pump_kind =
"Inflador CO2"` con `co2_inflation_capable = false` queda almacenable y sin dueño: la tabla se permite
igual y la contradicción se guarda. Acótalo con `allowed_when pump_kind in ["De mano / mini","De
pie","Otro","Compresor / eléctrica"]`, donde el facet añade información. Es el mismo movimiento de un
solo dueño que ya aplicaste en `light`.

**Correcto — «no deducir ausencia = false».** Se sostiene solo por el motor: un `false` es un valor
*conocido* y cierra la tabla; ausente deja `allowed_when` en `unknown` y la tabla queda pendiente. No
hace falta regla extra.

**No agregues nada para «cartucho incluido vs capacidad».** Ya está representado:
`configuration_kind` separa «Cartucho de esta presentación» —con `included_quantity` requerido— de
«Cartucho compatible declarado» —con `counterpart_model` requerido—. El HYBRIDROCKET HP usa las dos
filas: la presentación con `included_quantity` 1, y la compatibilidad «Use only Topeak 16g CO2
cartridges».

**Y el facet basta**, sin `pump_kind` múltiple: `pump_pressure_specifications` es `allowed_when
always` y su `quantity_kind` incluye «Presión orientativa CO2 para la configuración indicada» con
`configuration` requerido, así que el segundo modo de operación ya tiene dónde vivir.

| caso | valores | esperado |
|---|---|---|
| positivo | mini + facet true + fila 16 g roscado incluido 1 | sin incidencia — es el HYBRIDROCKET HP |
| negativo | mini + facet false + una fila | `field_applicability` bloqueante |
| negativo | «Inflador CO2» + facet false | con la corrección: inexpresable. Hoy: contradicción guardada |
| desconocido | mini + facet ausente + una fila | pendiente: la fila se conserva sin bloquear ni certificar |

`pump_kind` y `co2_cartridge_configurations` sólo las usa `pump`, y ninguna es global publicada: la
corrección es autocontenida.

## DL-2 · Riñonera con depósito: correcta, con una advertencia sobre el segundo volumen

Confirmado: `bag_kind` sólo admite Mochila, Mochila de hidratación, Cubre-mochila y Otro, y
`reservoir_l` está `allowed_when bag_kind = "Mochila de hidratación"`. Con «Otro» el volumen es
expresable pero el depósito no, así que la M.U.L.E. 5 no se puede representar sin mentir en el tipo.

**Correcto — el append es seguro.** `bag_kind` sólo lo usa `rider_bag` y no es global publicada.

**Correcto — encadenar la capacidad al hecho y no al tipo.** Ése es el arreglo real. `false` cierra
`reservoir_l` de forma definitiva; ausente lo deja pendiente, que es lo que pediste.

**Corregir — la capacidad de alojamiento no puede compartir campo.** «Capacidad de alojamiento para
un depósito comprado aparte» es **otra medida**: la del compartimento, no la del depósito entregado.
Ponerlas en `reservoir_l` bajo un booleano repone el defecto que ya cerraste en `light` (AG02) y en
`consumer_electronics` (AG06): dos medidas en un campo. Deja `reservoir_l` como la capacidad del
depósito **incluido**, y no agregues el segundo campo ahora — no tengo ninguna fuente en la mano que
lo exija. Cuando aparezca, va con clave propia.

**Advertencia.** No extiendas `fits_volume_min_l`/`fits_volume_max_l` a la riñonera: están acotados a
«Cubre-mochila», donde son un rango real de mochilas cubiertas y tienen `scalar_ordered_pairs`. En una
riñonera «lo que le cabe» sería la capacidad de alojamiento del punto anterior, no un rango.

| caso | valores | esperado |
|---|---|---|
| positivo | Riñonera + `reservoir_included` true + `reservoir_l` 1.5 + `volume_l` 5 | sin incidencia — es la M.U.L.E. 5 |
| negativo | `reservoir_included` false + `reservoir_l` 1.5 | `field_applicability` bloqueante |
| desconocido | Riñonera + `reservoir_included` ausente + `reservoir_l` 1.5 | pendiente: la cifra se conserva sin certificar que venga incluida |

## DL-3 · Decisión sobre el alcance de `volume_l`: token, no helper y no regla de suma

En MA-4 dije «helper». **La M.U.L.E. 5 me hace cambiar de opinión.** El producto declara dos volúmenes
—5 L el bolso, 1,5 L el depósito— y no pude leer si los 5 L incluyen el depósito. Esa ambigüedad, que
me dejó sin respuesta con la fuente delante, es exactamente la que va a tener el operador. Un helper
no se filtra, no se compara y no se audita; un token sí.

- `volume_l` guarda la capacidad que el fabricante imprime para el producto tal como se vende, en sus
  propias palabras, con el alcance **declarado y nunca deducido**.
- Se agrega `volume_basis`, con la forma de `quantity_kind` que ya aprobaste en
  `pump_pressure_specifications`: «Total declarado por el fabricante», «Sólo carga», «Por unidad del
  conjunto», «Desconocido / sin confirmar».
- **Ninguna regla calcula carga = total − depósito.** Con la fuente sin leer, esa resta sería inventar
  la lectura.
- El eje **unidad vs conjunto** es de `bike_bag`, no de `rider_bag`: `bag_member_configurations` ya
  lleva `volume_l` por miembro con `configuration` y `measurement_reference`, así que en filas está
  resuelto; al escalar sólo le falta decir cuál de las dos lecturas trae.
- **Sigue sin regla de suma:** 40 con dos miembros de 20 no se bloquea. Lo cerraste tú en el caso
  negativo de AG05.

Positivo: `volume_l` 5 con base «Total declarado por el fabricante» → sin incidencia. Negativo:
`volume_l` 5 sin base → **pendiente no bloqueante, no un error**; bloquearlo tiraría los volúmenes que
ya se registren bien. Desconocido: base «Desconocido / sin confirmar» se comporta igual que ausente,
porque `hasKnownSpecValue` trata ese token como ausencia — conviene saberlo antes de esperar que el
token cierre algo.

`volume_l` la usan `bike_bag` y `rider_bag`, las dos en este bloque, y no es global publicada.

## DL-4 · MA-3: el helper no basta, falta representación

**Lo demuestra tu propia fuente.** El HYBRIDROCKET HP declara «Capacity: **160 psi / 11 bar**»: dos
unidades para una magnitud, y no son el mismo número —11 bar son 159,5 psi, o sea que el fabricante
redondeó—. Un helper sobre `max_pressure_psi` no puede guardar dos valores, ni decir cuál imprimió el
fabricante, ni registrar que el par es una sola declaración.

`pump` ya lo resolvió: `pump_pressure_specifications` tiene `quantity_kind`, `value`, `unit` en
{psi, bar} y `configuration` requerido. `workshop_tool` no tiene nada de eso.

**Límite honesto:** verifiqué el fenómeno de doble unidad en una fuente primaria de este bloque, pero
es una bomba, no una herramienta de taller. No tengo en la mano un producto `workshop_tool` que
declare ambas unidades. La conclusión se sostiene igual porque `max_pressure_psi` es la **misma
definición** en las dos familias.

*Cambio mínimo:* `workshop_tool.max_pressure_psi` a `legacy` con `allowed_when never`, y una tabla de
filas propia con `quantity_kind` / `value` / `unit`. **No reutilices
`pump_pressure_specifications`:** su `quantity_kind` es de bomba —«Fondo de escala del manómetro»,
«Presión orientativa CO2 para la configuración indicada»— y no describe una llave dinamométrica ni una
prensa.

Positivo: presión sólo en psi → una fila. Positivo: «160 psi / 11 bar» → dos filas, las dos leídas.
Negativo: una sola cifra con la unidad obtenida por conversión → no se registra, convertir no es leer.
Desconocido: sin presión → pendiente.

## DL-5 · Hallazgo nuevo: la retirada de `max_pressure_psi` en `pump` quedó a medias

`pump.max_pressure_psi` es `role: legacy` pero **`allowed_when: always`**. En `light`, los cinco
escalares retirados llevan `allowed_when: never`. Y `role: legacy` sólo lo saca de ser extremo de
coherencia: no impide que se guarde un valor.

Así que hoy una bomba puede llevar `max_pressure_psi = 160` **y** una fila de
`pump_pressure_specifications` que diga 11 bar: dos dueños de una magnitud, que es justo lo que
cerraste en AG06 para `rated_power_w`.

*Cambio mínimo:* `pump.max_pressure_psi.allowed_when = never`, igual que `light`.

Positivo: sólo filas → sin incidencia. Negativo: `max_pressure_psi` 160 más una fila de 11 bar → hoy
**aceptado**; con el cambio, `field_applicability` bloqueante. Desconocido: ninguno de los dos →
pendiente.

---

2 fuentes verificadas, 1 ilegible declarada como tal, 2 propuestas aceptadas con corrección, 2
decisiones tomadas, 1 hallazgo nuevo, 17 casos ejecutables. Compuertas sin cambio: `fill_allowed`,
`compatibility_rules_integrated`, `all_product_assignment_review_complete`,
`all_family_domain_review_complete` — todas `false`.
