# Propuesta acotada D2 · dueño por pieza en los sucesores de freno — 2026-09-14

Ronda 214. Sólo lectura del catálogo de sucesores
(`original-successors-integrated-catalog-2026-09-08.json`) y sus casos
(`original-successors-integrated-cases-2026-09-08.json`,
`brake-family-representation-cases-2026-09-07.json`). Propuesta para Root
(metadata/publisher); no autoriza activación ni fill, no toca código ni datos.

## 1. Qué depende hoy de `brake_assembly_configurations`

Plantillas: `hydraulic_disc_brake` (v3), `mechanical_disc_brake` (v2),
`rim_brake` (v2). Rol del campo: `contents` en las tres.

**Esquema (definición global, v1).** `unique_by [[circuit_id, position]]`.
Columnas intrínsecas del circuito (8): `circuit_id` (req), `position`
(req, Delantero/Trasero), `lever_included`, `caliper_included`,
`hose_included`, `rotor_included`, `adapter_included` (req, booleanos),
`source_url` (req). Columnas de pieza (16): `lever_brand`, `lever_model`,
`lever_generation`, `lever_reach_adjust`, `caliper_brand`, `caliper_model`,
`caliper_generation`, `caliper_rotor_nominal_thickness_mm`,
`caliper_piston_count`, `caliper_pad_shape_code`, `caliper_pad_retainer_model`,
`hose_model`, `hose_length_mm`, `rotor_model`, `rotor_diameter_mm`,
`adapter_model`.

**Enlace de fila.** `brake_circuit_owner`: `brake_circuit_connections.configuration_row_id`
→ `brake_assembly_configurations`, `label_columns [position, circuit_id]`. Existe
en `hydraulic_disc_brake` y `rim_brake`; `mechanical_disc_brake` no tiene
tabla de conexiones ni enlace.

**Condiciones de fila (idénticas en las tres).** `allowed_when` de cada una de
las 16 columnas de pieza condicionado a su `<pieza>_included = true`;
`required_when` sólo para `lever_model`, `caliper_model`, `hose_model`,
`rotor_model`, `adapter_model` cuando su `*_included = true`; el resto
`never`. Ninguna otra sección del contrato nombra la tabla: sin
`prerequisites`, `cardinality`, `evidence_scopes` ni condiciones de otros
campos que la referencien.

**Casos ejecutables (15 en el paquete de sucesores; 3 de ellos también en el
de frenos), todos sobre `hydraulic_disc_brake`:**

- Dependen sólo de circuito, posición, `unique_by` y enlace (8):
  `brake_link_exact_circuit_row_id`, `brake_link_label_is_not_id`,
  `bkx_a_connection_names_a_configuration_that_exists`,
  `bkx_a_connection_cannot_name_an_absent_configuration`,
  `bkx_the_same_end_of_one_circuit_twice_blocks`,
  `bkx_the_same_configuration_twice_blocks`,
  `bkx_front_and_rear_are_two_configurations`,
  `bkr_another_source_cannot_duplicate_a_physical_circuit`.
- Dependen de columnas de pieza (7): `brake_front_rear_keep_own_dimensions`,
  `bkr_magura_trail_sport_preserves_four_front_two_rear` (pistones por
  posición), `bkr_no_lever_cannot_claim_lever_reach`,
  `bkr_no_rotor_cannot_claim_an_included_diameter`,
  `bkr_inclusion_of_front_rotor_does_not_enable_rear`,
  `bkr_included_rotor_without_model_remains_pending`,
  `bkr_legacy_pad_shape_is_not_assigned_to_both_calipers`.

## 2. Dónde puede vivir cada dato de pieza (ya existe el campo)

| Columna de conjunto | Fila `kit_members` (identidad) | Plantilla de la pieza (medida) |
|---|---|---|
| `lever_brand`, `lever_model` | `member_role = maneta`, `family = brake_lever`, `identity_brand/model` | — |
| `lever_reach_adjust` | — | `brake_lever.reach_adjust` |
| `caliper_brand`, `caliper_model` | `member_role = cáliper`, `family = brake_caliper` | — |
| `caliper_piston_count` | — | `brake_caliper.piston_count_value` |
| `caliper_pad_shape_code` | — | `brake_caliper.pad_shape_code` |
| `caliper_pad_retainer_model` | — | `brake_caliper.brake_pad_retainer_model` |
| `caliper_rotor_nominal_thickness_mm` | — | `rotor.rotor_nominal_thickness_mm` (es del rotor, no del cáliper) |
| `hose_model` | `member_role = manguera`, `family = hydraulic_hose` | — |
| `hose_length_mm` | — | `hydraulic_hose.hose_length_mm` |
| `rotor_model` | `member_role = rotor`, `family = rotor` | — |
| `rotor_diameter_mm` | — | `rotor.rotor_diameter_mm_value` |
| `adapter_model` | `member_role = adaptador`, `family = brake_mount_adapter` | — (sin medida propia) |
| `lever_generation`, `caliper_generation` | sin columna; hoy el catálogo ya las usa como parte del modelo en rótulos | decisión de Root: texto dentro de `identity_model` o columna nueva |

La `position` de la fila `kit_members` (Delantero/Trasero) es la misma
palabra que la del circuito: ese es el único puente necesario para la
separación mínima; no hace falta un enlace nuevo.

## 3. Separación mínima que conserva los contratos

1. **No cambiar el esquema de `brake_assembly_configurations`.** Pasarla a
   rol `legacy` en las tres plantillas (filas físicas conservadas, sin datos
   nuevos), igual que D1 para la tabla de evidencia de transmisión.
2. **Nuevo campo de contenido `brake_circuit_configurations`** con sólo las 8
   columnas intrínsecas y el mismo `unique_by [[circuit_id, position]]`; rol
   `contents`; sin `allowed_when`/`required_when` (no quedan columnas
   condicionadas).
3. **Re-apuntar el enlace** `brake_circuit_owner` a
   `brake_circuit_configurations` con los mismos `label_columns [position,
   circuit_id]` en `hydraulic_disc_brake` y `rim_brake`. `brake_circuit_connections`
   no cambia en este delta.
4. **Habilitar `member_profiles`** sobre `kit_members` en las tres plantillas
   (contrato `version 1`, `family_column = family`, `identity_columns
   [member_role, position, identity_brand, identity_model]`, como en el JSON
   de alcance). Identidad y medidas de cada pieza pasan a la fila y a su
   perfil según la tabla del §2.
5. **Casos.** Los 8 de circuito/enlace se conservan tal cual cambiando sólo el
   campo destino al nuevo. Los 7 de pieza se reescriben: cuatro como casos de
   perfil sobre la plantilla de la pieza (`rotor`: diámetro y espesor por
   posición; `brake_caliper`: pistones y pastilla por posición; `brake_lever`:
   `reach_adjust`; `hydraulic_hose`: largo), y tres como casos de kit sobre el
   nuevo campo (`rotor_included` delantero no habilita el trasero; incluido sin
   fila `kit_members` de ese rol y posición queda **pendiente**, no error; una
   fila `kit_members` de un rol cuyo `*_included = false` es contradicción).
   Esos dos últimos son la forma mínima del `allowed_when` que desaparece: hoy
   el motor no cruza tablas en `row_conditions`, así que se afirman con la
   guardia de perfiles (grafo de miembros), no con una regla nueva de filas.

Costo: una revisión de contrato por plantilla y un campo nuevo de la
definición global; 0 perfiles y 0 fill, sin migración de datos.

## 4. Fuera de este delta (pero conviene decidirlo en el mismo paquete)

- `brake_circuit_connections` (rol `declaration`) repite `component_brand`
  y `component_model` por extremo de circuito; con perfiles esa identidad ya
  vive en `kit_members`. Cuando se decida el dueño por pieza de las tablas de
  declaración (igual que `drivetrain_kit_member_interfaces`/`_fitments`),
  ese campo debería enlazar por `member_row_id` en vez de repetir marca/modelo.
- `mechanical_disc_brake` y `rim_brake` comparten la definición de conjunto
  con columnas de manguera hidráulica; el nuevo campo de circuito las deja
  fuera sin necesidad de excepción.

## 5. Qué no afirmo

No verifico compatibilidad ni publicación; no propongo activar el fill; no he
leído filas reales de estas tablas (0 fill declarado). Si existieran filas
físicas de `brake_assembly_configurations`, el paso 1 las conserva.
