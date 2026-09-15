# Aptitud de representación: 14 familias de movilidad y accesorios

2026-09-07. Revisión independiente sobre el catálogo congelado
`all-family-port-cardinality-integrated-2026-09-07.json`
(`16459826fee4c589cce37243afe4e159317212ddf1d47d6d6f1d76f9b3fadf15`) y las revisiones ya cerradas.
Paquete: `mobility-accessories-readiness-2026-09-07.json` —
`04207518f86bb50b43e5e06c20b1b73227edb2ac357bb49f36bbd5f3e422e71f`.

Sólo lecturas de artefactos y código. Sin base de datos, sin runtime, sin git, sin subagentes. No
reabrí la investigación por familia.

## Resultado

**Ninguna de las cinco compuertas abiertas que tocaban este bloque sigue sin implementar, y ninguna
de las 14 familias tiene un impedimento estructural para publicar sus metadatos.** Lo que queda son
un defecto de representación que debe cerrarse antes de abrir el llenado (MA-1), un defecto del
consumidor de compras (MA-2) y dos pendientes con dueño (MA-3, MA-4).

160 campos, 22 tablas de filas, 11 campos legacy o inalcanzables, 8 definiciones globales ya
publicadas reutilizadas.

## 1. Las cinco compuertas previas, y cómo se cerraron

De `field-addendum-a-root-decisions-2026-09-07.json` quedaban ocho compuertas sin aceptar. Cinco
tocan este bloque, y las cinco están implementadas en el catálogo congelado. **AG01** (fastener) y
**AG07** (nutrition/caffeine, de `food_beverage`, ya publicada) quedan fuera; **AG08** es la compuerta
de llenado, global y todavía cerrada, que no es condición de publicación.

**AG02 — luz.** No se añadieron guardas de «luz única»: se retiró el segundo dueño. Los cinco
escalares —`power_source`, `charge_connector`, `light_mount_kind`, `mount_diameter_min_mm`,
`mount_diameter_max_mm`— quedaron `role: legacy` con `allowed_when: never` y `required_when: never`, y
`light_member_configurations` pasó a `required_when: always`. La entrada externa se separó del puerto
de carga dentro de la fila: `power_input_connector` es `required_when` `battery_kind` está en las dos
alimentaciones externas.

**AG03 — referencias por id y upstream falso.** Las dos referencias existen como links de
`row_coherence`: `light_member_link` y `consumer_electronics_member_link`, de modo que un modo o un
puerto fantasma da `row_reference_unresolved` bloqueante. La mitad de `cycle_computer` se cerró por el
otro lado: al **rechazar** `sensor_link_ant_plus`, `_bluetooth` y `_wired`, las filas quedaron como
único dueño de la pareja tipo/transporte/soportado, y ya no existe un upstream con el que
contradecirse. Verifiqué que esos tres campos no están en la plantilla.

**AG04 — accessory_mount.** `scalar_ordered_pairs` declara las dos parejas, así que 35→22 y 100→55
bloquean. Y la mitad discreta se cerró con `bar_fit_representation`: el rango continuo sólo se permite
con «Rango continuo declarado por OEM» y `bar_clamp_configurations` sólo con «Medidas discretas
(filas)». Son excluyentes por construcción, sin inventar una lista de diámetros — que es mejor de lo
que el caso negativo pedía.

**AG05 — perfiles eléctricos.** Tres tablas separan las tres afirmaciones:
`power_port_configurations` (límite individual, `unique_by port_id`), `power_budget_configurations`
(asignación simultánea, `unique_by configuration+port_id`) y `power_port_profile_configurations`
(perfil declarado, con `profile_kind` que exige tensión o etiqueta OEM). No se agregó ninguna regla
universal de sumas, que es exactamente lo que el caso negativo prohibía.

**AG06 — potencia.** `rated_power_w` quedó `allowed_when device_kind = «Cargador»`, y el cable
conserva `cable_power_capacity_w` como dueño único.

## 2. MA-1 · Defecto: el rango de tamaño de rueda no tiene orden, y hoy no puede tenerlo

Familias: **rack_basket, fender, kickstand, training_wheel**.

`nominal_wheel_size_min` y `nominal_wheel_size_max` son `single_select`, no `number`. Y
`scalar_ordered_pairs` **rechaza** cualquier clave cuyo tipo no sea `number`:
`lib/modules/inventory/models/product_spec_coherence.dart:216` exige `activeTypes[k] != 'number'` →
`FormatException`. La pareja no está sin declarar: **no se puede declarar**. Hoy `min = 29"` con
`max = 20"` se acepta en las cuatro familias.

Agrava que en `training_wheel` los dos extremos son `required_when: always`: la única pareja
obligatoria del bloque es justo la que no tiene guarda.

El vocabulario trae además `700c` y `29"` para el mismo asiento de talón de 622 mm (Sheldon Brown,
medidas de neumático / ETRTO), y «Otra», que no tiene posición. Aun con un ordinal, la pareja seguiría
siendo ambigua.

**No propongo ninguna regla de compatibilidad ni ninguna conversión de pulgadas a milímetros.** Sólo
señalo que la representación admite un rango invertido y que el orden no es verificable.

*Alcance:* la definición no está entre las 93 globales publicadas y sus cuatro usuarios están en este
bloque, así que la corrección es autocontenida.

*Cambio mínimo:* reutilizar el patrón que ya aprobaste en este mismo bloque — un selector de
representación al estilo de `bar_fit_representation`, con la lista discreta viviendo en filas. Si se
conserva la lectura de rango, decirlo en el helper: el orden no se verifica.

| caso | valores | hoy | después |
|---|---|---|---|
| positivo | min 20" / max 26" | sin incidencia | sin incidencia |
| negativo | min 29" / max 20" | **aceptado — el defecto** | rechazado, o inexpresable bajo el selector |
| desconocido | sólo max 26" | `required_missing` no bloqueante | igual: la ausencia sigue pendiente |

**No impide publicar.** Publicar la plantilla no crea el dato malo; llenarla sí, y el llenado está
cerrado. Esto se cierra antes de abrir el llenado de estas cuatro familias, no antes de la publicación.

## 3. MA-2 · Defecto de proyección: todo campo se vuelve vocabulario de compra

Éste es el lector que no aparece buscando un nombre literal. **La tienda no proyecta nada**:
`lib/public_store/services/public_inventory_service.dart` no contiene ninguna lectura de ficha, así
que publicar estas 14 no muestra nada al cliente — y no es una cuestión de `is_customer_visible`. El
consumidor vivo es **la ruta de compras**.

`supplyNeedSearchFieldsOf`, en
`lib/modules/purchases/services/supply_need_effective_criteria.dart:115-133`, recorre **todos** los
`template.fields` con definición y no filtra por rol, `allowed_when`, `is_filterable` ni visibilidad.
Traslada `dataType`, `unit`, `allowedValues` y `validationRules`.

Medido en este bloque: de 160 campos, **11 son legacy o `allowed_when: never`** —light 8,
cycle_computer 2, pump 1— y **22 son tablas de filas** (`data_type: json`). Publicar estas 14 agrega
hasta 33 campos al vocabulario del buscador de proveedores que o nunca podrán tener valor o no son
criterios escalares.

*Cambio mínimo, del lado del consumidor:* en `supplyNeedSearchFieldsOf`, omitir el campo cuyo
`allowed_when` sea `never` y omitir `data_type == 'json'`. No cambia catálogo, definiciones ni
plantillas.

| caso | campo | esperado |
|---|---|---|
| positivo | `fender.max_tire_width_mm` | sigue siendo criterio de compra |
| negativo | `light.power_source` (legacy + never) | no debe ofrecerse como criterio de una luz |
| desconocido | un campo cuyo `allowed_when` depende de un valor no puesto | se sigue ofreciendo: desconocido no es no, y no se descarta en silencio |

**No impide publicar**: se manifiesta sólo cuando un producto queda ligado y se crea una necesidad de
suministro. Pero se multiplica con cada bloque.

## 4. Dos pendientes con dueño

**MA-3 · La unidad pegada al nombre se corrigió en uno de los dos usuarios.** En `pump`,
`max_pressure_psi` quedó `legacy` y el dueño pasó a `pump_pressure_specifications`, con
`quantity_kind`, `value` y `unit` como token requerido. En `workshop_tool` sigue vivo como
`declaration`, con la unidad soldada al nombre. Los dos usuarios están en este bloque y la definición
no está entre las 93. El campo es opcional y no bloqueante: es pendiente, no defecto. Positivo: una
presión declarada en psi entra sin incidencia. Negativo: una declarada en bar sólo se puede guardar
convertida o no guardarse, y ninguna de las dos es una lectura. Desconocido: sin presión, pendiente.

**MA-4 · `volume_l` no declara su alcance, donde `modes_count` sí lo hace.**
`bag_member_configurations` lleva `volume_l` por miembro más `configuration` y
`measurement_reference`, así que el alcance es expresable en la fila y no en el escalar. El precedente
está en este mismo bloque: `light.modes_count` tiene el helper «Total declarado para la luz individual
y su alcance; no se calcula contando filas». El cambio mínimo es el mismo helper en `bike_bag` y
`rider_bag`. **No una regla de suma:** no propongo que 20 L con dos miembros de 20 L se bloquee,
porque nada distingue una declaración por unidad de una por conjunto, y ya rechazaste las reglas
universales de suma en el caso negativo de AG05. Este hallazgo no tiene caso negativo mecánico, y
decirlo es parte del hallazgo.

## 5. Las definiciones globales que este bloque reutiliza

Ocho de las 93 ya publicadas. Cualquier propuesta sobre ellas es un forward que afecta a **todas** sus
familias, no una definición inédita:

| definición | familias | nota |
|---|---|---|
| `power_source` | light, audible_signal, cycle_computer | `never` en light; vivo en cycle_computer y en **audible_signal, ya publicada** |
| `mount_diameter_min_mm` / `_max_mm` | light, audible_signal | `never` en light: su dueño real hoy es **audible_signal, ya publicada** |
| `kit_members` | 23 familias; aquí light, fender, training_wheel | el helper de alcance de contenido sólo existe en lock y rider_protection |
| `color` | 37 familias; 11 aquí | |
| `material` | 27 familias; 5 aquí | |
| `volume_ml` | 4 familias; workshop_tool aquí | |
| `width_mm` | bike_protection, reflector | **reflector ya está publicada** |

El caso accionable es `kit_members`: extender a `light`, `fender` y `training_wheel` el mismo helper
que ya llevan `lock` y `rider_protection`, en un forward que nombre a las 23.

## 6. Límite de proyección al taller

El editor de fichas renderiza **todas** las columnas de una tabla de filas
(`lib/modules/inventory/widgets/product_spec_rows_field.dart:153`), sin visibilidad por columna. En
este bloque eso son tablas de hasta 17 columnas —`tool_capabilities` y `light_member_configurations`—,
13 en `rack_mount_configurations` y 11 en `power_port_profile_configurations`. Es un límite de
usabilidad real, no un defecto de contrato, y conviene saberlo antes de que un mecánico abra la
primera ficha de herramienta.

## 7. Veredicto por familia

Las 14 son **aptas para publicar metadatos**. Ninguna tiene un impedimento estructural.

| familia | veredicto | pendientes antes del llenado |
|---|---|---|
| workshop_tool | apta | MA-3, MA-2 |
| light | apta | MA-2 |
| cycle_computer | apta | MA-2 |
| consumer_electronics | apta | MA-2 |
| accessory_mount | apta | MA-2 |
| rack_basket | apta | **MA-1**, MA-2 |
| fender | apta | **MA-1**, MA-2 |
| kickstand | apta | **MA-1**, MA-2 |
| bike_bag | apta | MA-4, MA-2 |
| rider_bag | apta | MA-4, MA-2 |
| training_wheel | apta | **MA-1**, MA-2 |
| bike_protection | apta | MA-2 |
| eyewear | apta | MA-2 |
| pump | apta | MA-3, MA-2 |

`eyewear` merece una nota: su único campo obligatorio es una tabla de filas
(`eyewear_lens_configurations`), así que toda ficha de gafa quedará pendiente hasta que se investiguen
las lentes. Eso es un dato por investigar, no un defecto.

Compuertas sin cambio: `fill_allowed`, `compatibility_rules_integrated`,
`all_product_assignment_review_complete`, `all_family_domain_review_complete` — todas `false`.
