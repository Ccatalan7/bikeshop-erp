# Saneamiento de luz, electrónica y sensores — doble autoridad entre escalares y filas (2026-09-07)

Propuesta sobre el catálogo integrado `all-family-reviewed-fields-2026-09-07.json` (`cf8ebeb1e4e7dd32…`). Cada parche lleva su preimagen exacta tomada del catálogo por el generador, que aborta si no coincide. Nada aplicado; compuertas cerradas; llenado 0. El JSON es la fuente.

## 1. Reglas

- Un hecho, un dueño: si un escalar y una columna de filas dicen el mismo hecho físico de la luz, gana la fila y el escalar se retira de la plantilla (rol legacy + allowed never), nunca se borra. Un total declarado por el OEM (puertos, modos, lúmenes de portada) es otro hecho: no es count(filas) ni max(filas), y el detalle parcial no lo deriva ni lo niega.
- Juego y luz única son distintos por light_position; la cantidad de filas nunca decide si es juego.
- Un miembro se identifica por row.id; member_id y member_revision son texto para la persona y para el rótulo.
- Sin regla suma(max por puerto) ≤ total ni asignación ≤ máximo individual: tres hechos distintos con su fuente.
- Sensores: perfil + transporte + supported por fila; ningún booleano escalar nuevo.
- Fuentes que se contradicen se conservan como fichas alternativas con identidad y fecha sobre el mismo miembro físico; una fuente genérica («USB») no contradice a una precisa («Micro-USB»), la precisa gana.

## 2. Doble autoridad detectada

| Id | Plantilla | Hecho | Dueños hoy | Por qué es doble | Dueño único |
|---|---|---|---|---|---|
| DA-L1 | light | alimentación / batería de una luz | power_source (escalar, sólo luz única); battery_capacity_mah (escalar); light_member_configurations.battery_kind / battery_capacity_mah / battery_voltage_v / power_input_connector (fila, allowed always) | Para una luz única aplican los escalares y además las filas están permitidas siempre: «Pilas AA/AAA» en el escalar y «Li-ion integrada» en la fila conviven sin que nada lo detecte (el motor no compara fila con escalar). | light_member_configurations, para toda luz (una fila para la luz única). |
| DA-L2 | light | conector de carga | charge_connector (escalar); light_member_configurations.charge_connector (fila) | Igual que DA-L1; además el escalar no distingue puerto del dispositivo de extremo del cable, la fila sí (power_input_connector aparte). Un «USB» genérico de la web no contradice el «Micro-USB» del manual: lo precisa; el token más preciso con fuente gana, el genérico no se registra como alternativa. | fila |
| DA-L3 | light | fijación y diámetros de montaje | light_mount_kind, mount_diameter_min_mm, mount_diameter_max_mm (escalares + scalar_ordered_pairs); light_member_configurations.mount_kind / mount_diameter_* / mount_circumference_max_mm / mount_zone (fila + ordered_pairs) | Dos rangos de diámetro para la misma pieza; el par escalar y el par de fila se validan por separado. | fila |
| DA-L4 | light | grado IP | ip_rating (escalar text); light_member_configurations.ip_rating (fila text) | Dos textos libres para el mismo hecho. | fila, como token IEC 60529 |
| DA-L5 | light | lúmenes declarados y cantidad de modos frente a filas de modos | lumens_claimed, modes_count (escalares); light_mode_configurations (una fila por modo conocido) | NO es doble autoridad. Las filas son el detalle conocido y pueden estar incompletas; modes_count es el total que el OEM declara; lumens_claimed es la cifra OEM de portada, que no equivale a max(filas) sin el mismo método y condiciones de medida. Ni el total ni la ausencia se derivan del detalle parcial. | tres hechos: total declarado (escalar, declaration con evidencia), detalle conocido (filas), completitud (desconocida salvo que la fuente lo diga) |
| DA-L6 | light | posición de una luz única | light_position (escalar: Delantera/Trasera/Casco); light_member_configurations.position (fila requerida) | Con una fila por luz única, la posición se escribe dos veces y el motor no puede exigir que coincidan. | No resoluble sin motor (G2) o sin migrar el vocabulario de light_position a «Luz individual / Juego»; ver decisión D-L6. |
| DA-L7 | light | composición del juego | kit_members (contents, allowed always); light_member_configurations (contents) | La luz delantera de un juego cabe como fila de kit_members (family=light) y como miembro. | light_member_configurations para las luces; kit_members sólo para lo que no es luz (cable, soporte, correa). El motor no puede prohibir family=light dentro de la plantilla light (G3): queda como regla de captura y fixture. |
| DA-C1 | cycle_computer | montaje del sensor incluido | sensor_mount (escalar text, measurement); computer_contents.mount_interface (fila por ítem) | El soporte del sensor es una propiedad del ítem incluido, no del ciclocomputador. | computer_contents.mount_interface |
| DA-C2 | cycle_computer | fuente de velocidad frente a sensores admitidos | speed_source (escalar); sensor_support_configurations (Velocidad × transporte) | No es duplicado: speed_source dice cómo mide velocidad el equipo; las filas dicen qué parejas admite. La consistencia (speed_source por sensor ⇒ existe fila Velocidad admitida) no es expresable hoy (G2). Se conservan ambos. | ambos, con significado distinto; consistencia pendiente de motor |
| DA-C3 | cycle_computer | pareja sensor admitida / excluida | sensor_support_configurations.supported (boolean por fila) | No hay escalar duplicado (root rechazó sensor_link_*). Lo que falta es unique_by: (Velocidad, ANT+, true) y (Velocidad, ANT+, false) pueden convivir. | la fila, con unique_by [sensor_type, transport] |
| DA-E1 | consumer_electronics | cantidad de puertos frente a filas de puertos | ports_count (escalar); power_port_configurations (una fila por puerto conocido) | NO es doble autoridad: ports_count es el total declarado por el OEM y las filas son el detalle conocido, que puede estar incompleto. count(filas) < ports_count es completitud pendiente, no contradicción; count(filas) > ports_count sí lo sería y hoy no se detecta (G2). | total declarado (escalar, declaration con evidencia) y detalle (filas) |
| DA-E2 | consumer_electronics | protocolos de carga | charging_protocol_claim (escalar, allowed always); power_port_configurations.protocols (por puerto) | Para un cargador el protocolo es por puerto; el escalar queda para cable y «Otro». | por puerto en cargadores; escalar sólo cable/otro |
| DA-E3 | consumer_electronics | capacidad de una tarjeta | storage_capacity_gb (number, unidad GB entera); storage_capacity_label (text literal) | NO se retira: el literal conserva la unidad y la convención impresas (GB, TB, GiB). «1TB» no se convierte a 1000 ni a 1024 GB por intuición; storage_capacity_gb sólo se escribe cuando la fuente fija la convención. Dos hechos: literal declarado y valor normalizado conocido. | literal → storage_capacity_label (declaration con evidencia); número → storage_capacity_gb sólo con convención conocida |
| DA-E4 | consumer_electronics | potencia total / máxima por puerto / reparto | rated_power_w (total del cargador); power_port_configurations.max_power_w (máximo individual); power_budget_configurations.power_w (asignación en una combinación) | No es duplicado: tres significados (AG05). En un cargador de un puerto coinciden numéricamente y siguen siendo dos afirmaciones OEM distintas. Sin regla suma(max) ≤ total ni power_w ≤ max. | tres dueños, tres hechos |

## 3. Parches (preimagen exacta en el JSON)

| Id | Plantilla / clave | Op | Alcance | Necesita |
|---|---|---|---|---|
| LPS-L-retire-power_source | light / power_source | replace_field_contract | Sólo la plantilla light. power_source deja de editarse ahí; sus hechos existentes quedan inmutables como legacy (mecanismo 170). Otras plantillas que usen la definición no cambian. | schema_only; gate: consulta de sólo lectura de hechos existentes por definición antes de aplicar |
| LPS-L-retire-charge_connector | light / charge_connector | replace_field_contract | Sólo la plantilla light. charge_connector deja de editarse ahí; sus hechos existentes quedan inmutables como legacy (mecanismo 170). Otras plantillas que usen la definición no cambian. | schema_only; gate: consulta de sólo lectura de hechos existentes por definición antes de aplicar |
| LPS-L-retire-battery_capacity_mah | light / battery_capacity_mah | replace_field_contract | Sólo la plantilla light. battery_capacity_mah deja de editarse ahí; sus hechos existentes quedan inmutables como legacy (mecanismo 170). Otras plantillas que usen la definición no cambian. | schema_only; gate: consulta de sólo lectura de hechos existentes por definición antes de aplicar |
| LPS-L-retire-light_mount_kind | light / light_mount_kind | replace_field_contract | Sólo la plantilla light. light_mount_kind deja de editarse ahí; sus hechos existentes quedan inmutables como legacy (mecanismo 170). Otras plantillas que usen la definición no cambian. | schema_only; gate: consulta de sólo lectura de hechos existentes por definición antes de aplicar |
| LPS-L-retire-mount_diameter_min_mm | light / mount_diameter_min_mm | replace_field_contract | Sólo la plantilla light. mount_diameter_min_mm deja de editarse ahí; sus hechos existentes quedan inmutables como legacy (mecanismo 170). Otras plantillas que usen la definición no cambian. | schema_only; gate: consulta de sólo lectura de hechos existentes por definición antes de aplicar |
| LPS-L-retire-mount_diameter_max_mm | light / mount_diameter_max_mm | replace_field_contract | Sólo la plantilla light. mount_diameter_max_mm deja de editarse ahí; sus hechos existentes quedan inmutables como legacy (mecanismo 170). Otras plantillas que usen la definición no cambian. | schema_only; gate: consulta de sólo lectura de hechos existentes por definición antes de aplicar |
| LPS-L-retire-ip_rating | light / ip_rating | replace_field_contract | Sólo la plantilla light. ip_rating deja de editarse ahí; sus hechos existentes quedan inmutables como legacy (mecanismo 170). Otras plantillas que usen la definición no cambian. | schema_only; gate: consulta de sólo lectura de hechos existentes por definición antes de aplicar |
| LPS-L-declared-total-modes_count | light / modes_count | replace_field_contract | Total declarado por el OEM, distinto del detalle conocido en filas; exige evidencia. No se deriva de count(filas) ni la ausencia de filas lo niega. | schema_only |
| LPS-L-label-modes_count | light / modes_count | replace_definition_label | Rótulo que dice de quién es el número. | schema_only |
| LPS-C-declared-total-ports_count | consumer_electronics / ports_count | replace_field_contract | Total declarado por el OEM, distinto del detalle conocido en filas; exige evidencia. No se deriva de count(filas) ni la ausencia de filas lo niega. | schema_only |
| LPS-C-label-ports_count | consumer_electronics / ports_count | replace_definition_label | Rótulo que dice de quién es el número. | schema_only |
| LPS-E-storage-label-owner | consumer_electronics / storage_capacity_label | replace_field_contract | El literal impreso es el dueño de unidad y convención (GB/TB/GiB); storage_capacity_gb sólo se escribe cuando la fuente fija la convención. Sin conversión 1000/1024 por intuición. | schema_only |
| LPS-E-storage-label-text | consumer_electronics / storage_capacity_label | replace_definition_label | Rótulo que conserva la convención. | schema_only |
| LPS-L-drop-mount-pair | light / — | replace_scalar_ordered_pairs | Obligatorio junto a LPS-L-retire-mount_diameter_*: spec_coherence_metadata_internal_v1 rechaza un par cuyo extremo no sea number activo. | schema_only |
| LPS-L-members-required | light / light_member_configurations | replace_field_contract | Una luz única tiene exactamente una fila; un juego, una por luz. El juego se declara con light_position = «Juego delantera + trasera», nunca se deduce de la cantidad de filas. | schema_only |
| LPS-L-modes-required | light / light_mode_configurations | replace_field_contract | Con lumens_claimed y modes_count retirados, los modos son el único dueño de lúmenes y autonomía; la exigencia es no bloqueante (required_missing). | schema_only |
| LPS-L-members-schema | light / light_member_configurations | replace_rows_schema_parts | Un miembro físico = una fila; su identidad es row.id. member_revision sigue opcional: no se inventa una revisión que el fabricante no publica. IP pasa a token IEC 60529 para filtrar. | schema_only; la definición no tiene hechos (origin new); si los tuviera exige migración explícita (spec_rows_definition_guard) |
| LPS-L-modes-schema | light / light_mode_configurations | replace_rows_schema_parts | Group Ride 100 lm/8 h (web anterior, manual v1 coincide en 8 h) y 15 lm/10 h (web vigente, Spec change) son dos fichas del mismo modo del mismo miembro: dos filas de modo con member_revision distinta, sobre UNA fila de miembro. member_revision sigue opcional. lumens_secondary y runtime_max_h quedan sólo para modos realmente dobles/rangos declarados. | schema_only |
| LPS-L-link-labels | light / — | replace_link_label_columns | Presentación: el selector muestra miembro y revisión; no cambia identidad ni exige migración (guard corregido R3). | schema_only |
| LPS-L-kit-roles | — / kit_members | append_row_column_values | Lo que un juego de luces incluye y no es luz: el cable Micro-USB del AMPP800, el soporte SP-15. family: consumer_electronics para el cable, accessory_mount para soporte/correa/espaciador. Las luces nunca van en kit_members (regla de captura, G3). | schema_only; kit_members se usa en 23 plantillas: gate de hechos existentes antes de tocar el esquema |
| LPS-C-sensor-schema | cycle_computer / sensor_support_configurations | replace_rows_schema_parts | Perfil + transporte por fila, sin booleanos nuevos: supported ya es la exclusión explícita. «Desconocido / sin confirmar» permite registrar que Garmin admite Radar sin decir por qué transporte, en vez de inventar dos filas ANT+/Bluetooth. unique_by impide admitida y excluida a la vez. | schema_only |
| LPS-C-retire-sensor_mount | cycle_computer / sensor_mount | replace_field_contract | El soporte del sensor pertenece al ítem incluido: computer_contents.mount_interface. La definición puede tener hechos de la plantilla anterior: legacy los conserva inmutables. | schema_only; gate: hechos existentes |
| LPS-E-protocol-scope | consumer_electronics / charging_protocol_claim | replace_field_contract | En un cargador el protocolo se declara por puerto (power_port_configurations.protocols); el escalar queda para cable y otros. | schema_only |
| LPS-E-link-labels | consumer_electronics / — | replace_link_label_columns | Presentación: «USB-C 1 · USB-C · Salida» en el selector del reparto. | schema_only |
| LPS-E-port-profiles | consumer_electronics / power_port_profile_configurations | add_field | AG05/FA14: perfiles V/A/protocolo por puerto como filas vinculadas al puerto por row.id. Capacidad representable hoy; datos: ninguno, la ficha Anker no publica perfiles V/A (fixture unknown). Sin regla de sumas ni de tope. | schema_only; llenado 0 |

## 4. Vínculos ya implementados y condiciones que faltan dentro de filas

- `light_member_link` (modos → miembros) y `consumer_electronics_member_link` (reparto → puertos) están en el catálogo y son correctos: identidad por row.id, rótulo derivado. Esta propuesta sólo cambia sus `label_columns` (presentación) y agrega un tercer vínculo, perfiles → puertos.
- Lo que ningún vínculo cubre son condiciones **dentro** de las filas. Se registran como carencias, no como parches:

| Id | Carencia | Casos | Hoy |
|---|---|---|---|
| G1 | Condiciones dentro de filas: aplicabilidad/obligatoriedad de una celda según un escalar o según otra celda de la misma fila. | light_mode_configurations.lumens_secondary sólo cuando pattern = «Constante + intermitente»; light_mode_configurations.runtime_max_h sólo cuando la fuente declara rango; light_member_configurations.position obligatoria sólo cuando light_position = Juego | Las celdas quedan opcionales; la fixture registra el exceso como no detectable. |
| G2 | Consistencia fila ↔ escalar (exists_row / igualdad). | speed_source por sensor ⇒ existe fila (Velocidad, *, supported=true); luz única: fila.position = light_position; juego: al menos una fila Delantera y una Trasera | No expresable; ver D-L6. |
| G3 | Restricción de opciones de una columna de filas por plantilla (allowed_options existe sólo para escalares). | kit_members.family ≠ light dentro de la plantilla light | Regla de captura; fixture no detectable. |
| G4 | Comparación numérica entre filas vinculadas. | power_budget.power_w frente a power_port.max_power_w; suma de asignaciones frente a rated_power_w | A propósito no se propone: son tres significados (AG05); un OEM puede publicar cifras que una regla llamaría contradictorias. |
| G5 | Completitud de un grupo o de un detalle frente a un total declarado. | power_budget «C1+C2+A» con sólo dos filas; count(filas de puertos) > ports_count; count(filas de modos) > modes_count | Menor que el total = pendiente por convención; mayor = contradicción no detectable. |
| G6 | unique_by omite las filas a las que les falta una clave del grupo; con una clave opcional (member_revision) dos filas sin revisión no se deduplican. | dos filas Group Ride sin member_revision | Se acepta antes que obligar a inventar una revisión; alternativa de motor: tratar la clave ausente como valor vacío al comparar. |
| G7 | Consumidores (filtro técnico del asistente, facetas) aún no leen columnas de filas. | buscar luces por conector de carga o por grado IP tras retirar los escalares | Compuerta técnica previa al despliegue de estos parches; no es tarea manual del dueño. |

## 5. Decisiones que quedan en root

- **D-L6 — Posición de la luz única: ¿escalar o fila?** Mantener light_position con su vocabulario actual y exigir una fila por luz; la igualdad posición-fila queda como G2 y la fixture la marca como no detectable. Alternativa completa: migrar light_position a «Luz individual / Juego delantera + trasera» y dejar la posición sólo en la fila; exige migración de hechos existentes del escalar (gate) y no la propongo como parche en este bloque.
- **D-FA07 — Root aceptó «escalares sólo para luz única»; esta propuesta retira los siete escalares físicos y conserva los totales declarados.** Retirar alimentación, conector, batería, fijación, diámetros e IP: con escalares para luz única, los modos (que necesitan member_id) no tendrían dueño y la alimentación seguiría con dos dueños según el tipo de producto. modes_count y lumens_claimed se quedan como declaraciones OEM con evidencia. Costo real: G7.

## 6. Fixtures

| Id | Plantilla | Tipo | Fuentes | Issues esperados | Nota |
|---|---|---|---|---|---|
| light_single_ampp800_web_revision | light | valid | S-CATEYE-WEB | — | Luz única = una fila de miembro; el cable incluido va en kit_members con rol nuevo «cable». Ningún escalar físico retirado aparece; lumens_claimed 800 y modes_count 5 son totales OEM con evidencia y conviven con tres filas de modos conocidas (detalle incompleto: faltan Middle y Low, y eso no es contradicción). El vínculo de modos usa row.id. |
| light_kit_cateye_group_ride_two_revisions | light | valid | S-CATEYE-WEB, S-CATEYE-MANUAL-LD810 | — | Un solo ViZ300 físico (una fila de miembro; Micro-USB y 800 mAh del manual precisan el «USB» y «Li-ion» de la web). Group Ride conserva sus dos fichas OEM como dos filas de modo con revisión distinta sobre el mismo miembro: alternativas documentales, no dos luces. El SKU en stock no se atribuye a una hasta ver su envase. |
| light_kit_same_revision_twice | light | contradictory | S-CATEYE-WEB | row_shape@light_mode_configurations, row_reference_pending@light_mode_configurations | Mismo miembro, misma revisión, mismo modo dos veces: unique_by [member_id, mode, member_revision] lo rechaza. El pendiente es porque no hay filas de miembros en esta fixture. |
| light_kit_group_ride_twice_without_revision_undetectable | light | contradictory_undetectable | S-ENGINE | row_reference_pending@light_mode_configurations | G6: sin member_revision en ninguna, unique_by omite ambas filas y el duplicado no se detecta. Se acepta antes que obligar a inventar una revisión. |
| light_single_position_mismatch_undetectable | light | contradictory_undetectable | S-ENGINE | — | G2: la fila dice Trasera y el escalar Delantera; hoy nada lo detecta. Se registra para que la carencia tenga caso, no para aceptarlo. |
| light_kit_member_inside_kit_members_undetectable | light | contradictory_undetectable | S-ENGINE | — | G3: la luz delantera aparece como componente del kit y como miembro. Regla de captura hasta que exista restricción de opciones por plantilla en columnas. |
| light_inventory_ae_kit_pending | light | unknown | S-INVENTARIO | required_missing@light_member_configurations, required_missing@light_mode_configurations | Sin OEM: pendiente, nunca se inventa desde el título. |
| computer_garmin_540_sensors_transport_unknown | cycle_computer | valid | S-GARMIN-540 | — | La fuente admite el tipo sin decir el transporte: se registra tal cual, sin desdoblar en ANT+ y Bluetooth. IPX7 y 26 h del equipo no tienen campo en cycle_computer; no se agregan en este bloque. |
| computer_sensor_pair_admitted_and_excluded | cycle_computer | contradictory | S-ENGINE | row_shape@sensor_support_configurations | Admitida y excluida a la vez: contradicción por unique_by [sensor_type, transport] (hoy indetectable: unique_by es null). |
| computer_wired_inventory_speed_source_without_rows_undetectable | cycle_computer | contradictory_undetectable | S-INVENTARIO, S-ENGINE | — | G2: mide velocidad por cable pero la única fila excluye Velocidad por cable. No detectable hoy. |
| charger_anker_a2667_ports_budget_profiles_unknown | consumer_electronics | valid | S-ANKER-A2667 | — | ports_count 3 es el total declarado y las tres filas el detalle conocido; charging_protocol_claim ya no aplica al cargador. power_port_profile_configurations queda ausente: la ficha no publica V/A (unknown), y ausente es desconocido. C2+A = 12+12 con máximos individuales de 65 y 22,5: ninguna regla lo juzga. |
| charger_budget_names_ghost_port | consumer_electronics | contradictory | S-ENGINE | row_reference_unresolved@power_budget_configurations | Ya implementado (vínculo por row.id). |
| charger_baseus_65w_model_unknown | consumer_electronics | unknown | S-INVENTARIO | required_missing@power_port_configurations, prerequisite_missing@rated_power_w | 65 W del título es declaración sin evidencia; los puertos faltan. Nada se copia de Anker. |
| card_literal_without_number | consumer_electronics | unknown | S-ENGINE | — | El literal «1TB» conserva unidad y convención impresas; storage_capacity_gb queda desconocido porque nadie sabe si son 1000 o 1024 GB sin que la fuente lo diga. Nada se convierte por intuición. |

## 7. Fuentes conservadas con identidad y fecha

| Id | Título | Grado | Lectura |
|---|---|---|---|
| S-CATEYE-WEB | Cateye — AMPP800 (HL-EL088RC) + ViZ300 (TL-LD810), página de producto | oem_page | lectura web 2026-09-07 (registrada en el addendum A como E-CATEYE) |
| S-CATEYE-MANUAL-LD810 | Cateye — manual TL-LD810/820 (TL-LD810_820_HP_ENG_v1.pdf) | oem_manual | PDF descargado y leído localmente (PDFKit) 2026-09-07 |
| S-GARMIN-540 | Garmin — Edge 540 Owner’s Manual (Wireless Sensors; Specifications) y página de producto | oem_page | lectura web 2026-09-07 (E-GARMIN-540) |
| S-ANKER-A2667 | Anker — 735 Charger (Nano II 65W) A2667, ficha de soporte | oem_page | lectura web 2026-09-07 (E-ANKER-A2667) |
| S-INVENTARIO | Inventario Viñabike: títulos de productos reales sin OEM identificado | inventory | catálogo interno (addendum A, 2026-09-07) |
| S-ENGINE | Motor real: product_spec_rows.dart, product_spec_template_rules.dart, product_spec_coherence.dart, 20260907020000 | structural | lectura de código 2026-09-07 |

Conflicto conservado: «USB» de la web y «Micro-USB» del manual no se contradicen: el manual precisa el puerto. La contradicción documental real es Group Ride: manual v1 ≈8 h (sin lúmenes) y web anterior 100 lm / 8 h frente a web vigente 15 lm / 10 h con nota «Spec change». Son dos fichas del mismo producto físico, no dos miembros.

## 8. Compuertas antes de aplicar

- Lectura de sólo lectura en hosted: hechos por definición para power_source, charge_connector, battery_capacity_mah, light_mount_kind, mount_diameter_min_mm, mount_diameter_max_mm, ip_rating, modes_count, lumens_claimed (sólo productos de la plantilla light), sensor_mount, ports_count, storage_capacity_label y kit_members; un conteo > 0 en un campo de filas exige migración explícita (spec_rows_definition_guard), y en un escalar sólo confirma que legacy conserva datos.
- LPS-L-drop-mount-pair se aplica en la misma migración que los retiros de mount_diameter_*.
- Manual TL-LD810_820 v1 leído: Micro-USB confirmado, 800 mAh, Group Ride ≈8 h en esa revisión.
- Las trece definiciones que se retiran o cambian son origin: new en el catálogo integrado (sin metadatos ni hechos en producción según all-family-existing-metadata): la lectura de hosted es confirmación, no migración.
- Los consumidores que filtran por escalares (asistente, facetas) deben leer columnas de filas antes de retirar los escalares de luz: compuerta técnica, no trabajo manual del dueño (G7).
- Ningún parche autoriza fill.

## 9. No cubierto

- Autonomía y grado IP del ciclocomputador (Garmin 26 h, IPX7): sin campo; fuera de este bloque.
- Facetas del asistente sobre columnas de filas: carencia aparte.
- Migración del vocabulario de light_position (D-L6).

| light-power-sensor-sanitation-2026-09-07.json | `0f3685983e76efc3aa605ad63ecba70051e5c3b4ef8ccc0dd03047391b7cae47` |
