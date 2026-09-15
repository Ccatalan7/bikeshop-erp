# Propuesta independiente · sucesor de `brake_lever` como pieza física (2026-09-15, ronda 228)

Propuesta, no entrega. Insumos leídos: candidata congelada
`original-successors-integrated-catalog-2026-09-08.json` (`e0cccea8…`, plantilla
`dee33c12…`), estado vivo por la preimagen guardada
`.tmp/product-spec-catalog/brake-ownership-20260915/preimage.json` (02:30:40Z:
`brake_lever` v2, 18 productos por binding efectivo, 3 explícitos) y la adopción
guardada del 09-08 (15 manetas, cero observaciones), las familias vecinas ya
publicadas el 09-07 (`brake_shift_combined_control`, `brake_small_part`,
`control_cable`, `hydraulic_hose`) y las definiciones que la ronda 227 dejó
publicadas para la pinza. Sin código, catálogos, migraciones ni producción.

## 1. Alcance de la pieza

`brake_lever` describe **una maneta completa**: cuerpo, hoja y abrazadera, con
bomba y depósito si es hidráulica. Quedan fuera y tienen otro dueño:

| Producto | Familia dueña | Por qué |
|---|---|---|
| Hoja o palanca de recambio (sin cuerpo ni abrazadera) | `brake_small_part` | es una parte de la maneta; hoy `brake_part_kind` sólo tiene pin, resorte, perno y «Otro»: falta la opción «Palanca / hoja de recambio» (delta aparte sobre una definición publicada) |
| Maneta con mando de cambio integrado | `brake_shift_combined_control` (publicada, v16) | no es una maneta de freno con un extra; es otro control |
| Par de manetas, maneta con manguera y pinza, «juego» | presentación (D2) | contenido, no pieza; la asignación heredada no prueba pieza individual (misma advertencia que NNV55 y 1062 en pinzas) |

## 2. Propiedad: qué es de la maneta y qué no

| Dato | Dueño | Cómo se declara |
|---|---|---|
| Accionamiento (cable o hidráulico) | maneta | `brake_actuation` |
| Tiro de cable **entregado** | maneta | `lever_cable_pull`; el tiro **exigido** es de la pinza (`cable_pull_required`, ya publicado) y ninguno implica el otro |
| Cabeza de cable que admite | maneta | reutilizar `cable_head` (publicada en `control_cable`) con etiqueta propia, si sus opciones cubren cabeza MTB y de ruta; si no, definición nueva |
| Diámetro de abrazadera al manubrio | maneta | `handlebar_clamp_mm` (22,2 plano; 23,8 ruta) |
| Interfaz para mando separado | maneta | `shifter_mount_interface` (nueva): I-SPEC EV, I-SPEC II, I-SPEC B, MatchMaker X, «Abrazadera independiente», «Desconocido / sin confirmar» |
| Mano / lado | maneta | `lever_side` (nueva): Izquierda, Derecha, Ambidiestra, Desconocido. No se deduce del país ni de `brake_position` |
| Rueda a la que se destina | declaración del envase | `brake_position` se conserva como declaración, no como intrínseco |
| Regulación de alcance | maneta | `reach_adjust` (vivo, se conserva) |
| Fluidos **admitidos** por modelo y edición | maneta | `brake_model_fluid_approvals` (publicada el 09-15); clase mineral exige producto OEM |
| Fluido **cargado** al vender | presentación (D2) | no va en la pieza |
| Salida hidráulica y su racor | maneta | `brake_piece_hydraulic_ports` con `end_role` sólo «Salida» |
| Puerto de purga de la maneta | maneta | `brake_bleed_ports` con `component_role` sólo «Maneta» |
| Manguera, pinza o mando incluidos | presentación | ningún `kit_members` en la pieza |
| Convertidor cable→hidráulico | pinza híbrida o presentación | nada en la maneta: una maneta de cable que mueve un convertidor sigue siendo mecánica |

## 3. Errores de la candidata congelada que no deben pasar

1. **`kit_members` en la maneta.** Contenidos en una pieza abren la recursión
   que `component_set` prohíbe y que D2 necesita evitar (E1). Retirar.
2. **`integrated_shifter` (booleano nuevo).** Un `true` describe un producto de
   otra familia ya publicada. Retirar; en su lugar la interfaz para mando
   separado (§2).
3. **Ramas híbridas muertas.** `allowed_options.brake_actuation` excluye
   «Híbrido», pero `brake_conversion_location`, `brake_external_converter_model`
   y las condiciones «Híbrido» de puertos y fluidos siguen en la plantilla.
   Retirar las tres definiciones de la maneta; la 227 ya sacó el convertidor
   de la pinza.
4. **`brake_external_hose_connection`.** Toda maneta hidráulica tiene salida a
   manguera; la pregunta sólo discriminaba híbridos. Retirar; los puertos se
   permiten directamente con «Hidráulico».
5. **Legacy inexistente.** `fluid_type` y `hose_system_code` no son campos
   vivos de `brake_lever` (los seis vivos son `spec_evidence_source`,
   `brake_position`, `brake_type`, `reach_adjust`, `caliper_hydraulic`,
   `brake_system`). No se crean como legacy: misma regla que
   `absent_legacy_not_created` en la pinza.
6. **`brake_position` como intrínseco.** Para una maneta la propiedad física es
   la mano; la rueda es destino. Hoy es obligatorio; pasa a declaración con
   `required_when never` y se agrega `lever_side`.

## 4. Plantilla propuesta

| Campo | Origen | Rol / semántica | `allowed_when` | `required_when` |
|---|---|---|---|---|
| `brake_actuation` | publicada | primary / intrinsic; `allowed_options` [Mecánico (cable), Hidráulico, Desconocido / sin confirmar] | always | always |
| `lever_cable_pull` | publicada | measurement / compatibility | actuation = Mecánico | actuation = Mecánico |
| `cable_head` (etiqueta «Cabeza de cable admitida») | publicada, a verificar | measurement / compatibility | actuation = Mecánico | never |
| `handlebar_clamp_mm` | publicada | measurement / compatibility | always | never |
| `shifter_mount_interface` | **nueva** | measurement / compatibility | always | never |
| `lever_side` | **nueva** | primary / intrinsic | always | always |
| `reach_adjust` | viva | primary / intrinsic | always | never |
| `brake_model_fluid_approvals` | publicada 09-15 | measurement / compatibility; `row_conditions` mineral → producto | actuation = Hidráulico | actuation = Hidráulico |
| `brake_piece_hydraulic_ports` | publicada 09-15 | declaration / compatibility; `row_conditions.allowed_options.end_role = [Salida]` | actuation = Hidráulico | never |
| `brake_bleed_ports` | publicada 09-15 | declaration; `component_role = [Maneta]` | actuation = Hidráulico | never |
| `brake_position` | viva | declaration | always | never |
| `spec_evidence_source` | viva | declaration / evidence | always | never |
| `brake_type` | viva | **legacy** (`allowed_when never`) | — | — |
| `caliper_hydraulic` | viva | **legacy**; sucesor `brake_actuation` | — | — |
| `brake_system` | viva | **legacy**; la marca vive en la identidad del producto | — | — |

Nada de `kit_members`, `integrated_shifter`, `brake_conversion_location`,
`brake_external_converter_model`, `brake_external_hose_connection`,
`fluid_type` ni `hose_system_code`. Flags de superficie (decisión del dueño,
misma lógica que 226): `brake_actuation` sigue siendo la definición global
invisible; `lever_cable_pull`, `handlebar_clamp_mm`, `lever_side` y
`shifter_mount_interface` merecen visibles y filtrables.

Opcionales que dejo fuera para mantener el paquete pequeño: número de dedos de
la hoja, tipo de abrazadera (partida o cerrada), depósito abierto o cerrado,
ajuste de carrera libre. Ninguno es una interfaz.

## 5. Casos de aceptación

1. Mecánica sin tiro → pendiente `required_missing lever_cable_pull`; con
   «Tiro largo» → sin incidencia.
2. Hidráulica con `lever_cable_pull` → `field_applicability`.
3. Hidráulica sin aprobaciones → pendiente; una fila «Aceite Mineral» sin
   `fluid_product` → `row_required_missing` pendiente; dos filas iguales →
   `row_shape`.
4. Fila de puerto con `end_role` «Entrada» o «Purgador» → `row_option`;
   «Salida» → sin incidencia. Fila de purga con `component_role` «Cáliper» →
   `row_option`; «Maneta» → sin incidencia. Dos puertos con el mismo
   `port_id` → `row_shape`.
5. Mecánica con filas de puertos o purga → `field_applicability`.
6. `brake_actuation` «Híbrido» o «Contrapedal» → `field_constraint`.
7. Claves `integrated_shifter` o `kit_members` en el borrador → ajenas: el
   validador las ignora y el escritor las rechaza («La respuesta no pertenece
   a esta plantilla»).
8. Valores en `brake_type`, `caliper_hydraulic` y `brake_system` → ninguna
   incidencia en esos campos (`forbidden_issue_fields`); roundtrip idéntico
   aceptado y cambio rechazado.
9. `lever_side` Izquierda con `brake_position` Delantero, y Derecha con
   Delantero → ambos sin incidencia: no hay regla que derive uno del otro.
10. Sin `lever_side` → pendiente `required_missing`; «Ambidiestra» → sin
    incidencia.
11. `handlebar_clamp_mm` 23,8 con «Tiro corto» y 22,2 con «Tiro largo» → sin
    incidencia; 22,2 con «Tiro corto» también: el motor no cruza abrazadera
    con tiro, y así debe quedar.
12. Producto con hoja de recambio asignado a `brake_lever` → no lo detecta
    ningún guard; es una regla de adopción, no del motor.

## 6. Fuentes y sus límites

- Sheldon Brown, «Direct-pull (V-brake) and cantilever brakes»
  (sheldonbrown.com/canti-direct.html): «Direct-pull brake levers pull the
  cable twice as far, half as hard» y «It is not generally safe to mix and
  match levers/cables between direct-pull and other types»; nombra manetas de
  ruta compatibles con V-brake (Dia-Compe 287V, Tektro RL520) y el «Travel
  Agent». Sostiene `lever_cable_pull` como dato de la maneta y la opción
  «Ajustable».
- Shimano Deore BL-M6100, ficha transcrita por bike-components.de (la página
  oficial de Shimano devolvió 403 a la lectura automática): «clamp (split),
  I-Spec EV», «mineral oil», «reach adjust (with tools)», «2-finger», manguera
  «SM-BH90-SS (not included)», conexión «straight», pinzas recomendadas
  «BR-M6100» y «BR-M6200», venta «right (side-specific), left
  (side-specific)». Sostiene `shifter_mount_interface`, `lever_side`, la
  manguera como pieza aparte y la salida como puerto de la maneta. Diámetro
  22,2 mm no aparece en esa transcripción: no lo afirmo por esa fuente.
- SRAM Level TLM, sólo resúmenes de buscador: DOT 5.1, MatchMaker X, Bleeding
  Edge. Bastan para las opciones «DOT 5.1» y «MatchMaker X»; el puerto de purga
  de la maneta SRAM y su herramienta se documentan por fila con el manual del
  modelo, no por marca.
- Park Tool «Rim Brake Identification» y «Linear Pull Brake Service» no dicen
  nada sobre manetas; no se usan.

## 7. Limitaciones y cierre

Sin lecturas por producto de las 18 manetas vivas (la adopción del 09-08 tenía
15 con cero observaciones): la conservación legacy es de metadata, no de
valores. `cable_head` se reutiliza sólo si sus opciones calzan; la opción de
hoja de recambio en `brake_small_part` es otro delta. No se diseña D2 aquí: el
par de manetas y la maneta con manguera siguen siendo presentación. Ninguna
compatibilidad se deduce por marca ni por pruebas. Propiedad de vuelta a
Root para implementar.
