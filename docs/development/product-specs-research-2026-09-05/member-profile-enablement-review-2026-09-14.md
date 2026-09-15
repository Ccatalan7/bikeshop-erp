# Revisión acotada · alcance de habilitación de `member_profiles` — 2026-09-14

Ronda 213. Sólo lectura: `member-profile-enablement-scope-2026-09-14.json`
`20580f49…` (17 objetivos, 5 excluidos), catálogo integrado
`all-family-contents-integrated-2026-09-07.json` (publicadas) y
`original-successors-integrated-catalog-2026-09-08.json` (sucesores), y las
decisiones de familia ya escritas (`row-gap-closure-review-2026-09-07.md`,
`chain-drive-independent-review-2026-09-08.md`,
`non-drivetrain-kit-owner-followup-2026-09-07.json`). Sin SQL, sin runtime,
sin investigación nueva de productos. No declaro compatibilidad ni autorizo
publicación ni fill.

## Pregunta y regla aplicada

¿Activar `member_profiles` sobre `kit_members` en esas 17 plantillas duplica
identidad o medidas que ya viven en otra tabla de contenido? Regla: una tabla
es **configuración intrínseca** del producto raíz cuando describe cómo está
armado (qué circuito, qué posición, qué incluye, qué enlaza con qué); es
**otra pieza** cuando sus columnas son marca/modelo/MPN/medidas de un
componente que además tiene familia con plantilla propia. Un perfil de miembro
guarda exactamente eso segundo, así que sólo el segundo caso duplica.

Base común: `kit_members` es una definición global única (6 columnas:
`member_role`, `family`, `quantity`, `position`, `identity_brand`,
`identity_model`; sin `unique_by`), y sus 105 valores de `family` incluyen las
familias de las piezas de freno, transmisión y luz — salvo donde el contrato
de la plantilla los restringe por `row_conditions` (sólo `light`, ver D3). Por tanto, donde el kit ya
tiene otra tabla con marca/modelo/medidas por miembro, el perfil crea un
**tercer dueño** (fila de `kit_members` + tabla propia + hechos del perfil).

## Resultado por plantilla

| Plantilla (fuente) | Otro contenido | Veredicto | Cambio mínimo antes de habilitar |
|---|---|---|---|
| bicycle, bmx_cable_detangler, brake_lever, fender, headset_small_part, rider_protection, training_wheel, wheel | ninguno | **Aprobado** | ninguno |
| handlebar_covering (`pack_quantity`, `end_plugs_included`), lock (`keys_included`, `mount_bracket_included`), tube_repair (`glue_volume_ml`, `patch_count`), tubeless_repair (`plug_count`, `tool_included`) | escalares de conteo/booleanos | **Aprobado** | ninguno: son cardinalidad intrínseca, no identidad ni medida; el solape conteo↔`quantity` ya existía sin perfiles y `patch`/`tool` no son familias con plantilla |
| drivetrain_kit (sucesor v3) | `drivetrain_kit_member_evidence` (rol `contents`) | **Corregir antes** | ver D1 |
| hydraulic_disc_brake (v3), mechanical_disc_brake (v2), rim_brake (v2) (sucesores) | `brake_assembly_configurations` | **Corregir antes** | ver D2 |
| light (publicada v17) | `light_member_configurations` (+ `light_mode_configurations` enlazada) | **Aprobado** (corregido en ronda 214) | ninguno: el contrato efectivo excluye `family = light` en `kit_members`; ver D3 |

**Alcance aprobado sin cambios: 13 de 17** (corregido en ronda 214; la
versión inicial decía 12/17 por leer sólo la lista global de familias). Los
otros 4 —`drivetrain_kit` y los tres frenos— son los de `review_needed[0]`
(«duplicate ownership…»).

## Hallazgos demostrables

### D1 — drivetrain_kit: la evidencia por miembro ya es del perfil

`drivetrain_kit_member_evidence` = `member_reference` (enlace de fila a
`kit_members`, `kit_owner_drivetrain_kit_member_evidence`), `manufacturer_sku`,
`edition`, `source_document` (req), `source_url`. Un perfil de miembro guarda
`manufacturer_sku` confirmado con fuente de la fila, `identity_sources` de la
fila y la edición/fuentes de la referencia elegida. Habilitar sin tocar la
tabla deja el MPN y la evidencia con dos dueños que nada concilia (el motor no
compara `manufacturer_sku` de la tabla con el del perfil).
*Mínimo:* en la misma publicación que añade `member_profiles`, pasar
`drivetrain_kit_member_evidence` a `legacy` (se conservan filas físicas, sin
nuevos datos) y retirar su enlace `kit_owner_…_evidence` de `row_coherence`.
Las tablas hermanas `…_member_interfaces` y `…_member_fitments` son rol
`declaration`, no `contents`: quedan fuera de esta pregunta, pero comparten el
mismo `member_reference` y conviene decidir su destino en el mismo paquete.

### D2 — frenos: la tabla de conjunto lleva identidad y medidas de las piezas

`brake_assembly_configurations` mezcla dos cosas. Intrínseco del kit:
`circuit_id`, `position`, `*_included` (5 booleanos), `source_url`, y es el
destino del enlace `brake_circuit_owner` desde `brake_circuit_connections`.
Pieza: `lever_brand/model/generation`, `caliper_brand/model/generation`,
`hose_model`, `rotor_model`, `adapter_model`, `rotor_diameter_mm`,
`hose_length_mm`, `caliper_rotor_nominal_thickness_mm`, `caliper_piston_count`,
`caliper_pad_shape_code`, `caliper_pad_retainer_model`, `lever_reach_adjust`.
`kit_members` de estas plantillas ya declara los mismos miembros (`maneta`,
`cáliper`, `manguera`, `rotor`, `adaptador`) con marca/modelo, y sus familias
(`brake_lever`, `hydraulic_hose`, `rotor`, …) tienen plantilla: un perfil de
rotor guardaría diámetro y espesor; uno de cáliper, pistones y pastilla. Tres
dueños para la misma identidad y medida, sin enlace entre la tabla de conjunto
y `kit_members`.
*Mínimo:* no habilitar estas tres hasta partir la tabla. Como el rol
`legacy` es por campo y no por columna, la partición es: el campo actual pasa
a `legacy` (filas físicas conservadas), un campo nuevo de circuito conserva
sólo `circuit_id`, `position`, `*_included`, `source_url` con el mismo
`unique_by`, y el enlace `brake_circuit_owner` se re-apunta a él; identidad y
medidas de pieza pasan a `kit_members` + perfil. Reglas, enlaces y los 15 casos
afectados, con su destino uno por uno, en
`member-brake-owner-delta-proposal-2026-09-14.md` (ronda 214). Sucesores con 0
perfiles y 0 fill: revisión de contrato, no migración de datos.

### D3 — light: corregido; no hay duplicación porque `family = light` está excluida

Mi lectura de la ronda 213 fue incompleta: juzgué con las 105 opciones
globales de la columna `family` de `kit_members`, pero el contrato efectivo de
`light` restringe esa columna en `row_conditions.fields.kit_members.allowed_options.family`
a **104** familias, sin `light` (catálogo publicado, plantilla `light`). Root
lo confirmó con una sonda de sólo lectura contra el validador productivo
(`.tmp/db/light-member-family-live-probe-20260914.{sql,json}`, sin
escrituras): un borrador sintético con `kit_members.family = light` devuelve
`row_option` **bloqueante** («Familia técnica: La opción no pertenece a esta
ficha»), y `family = accessory_mount` no devuelve ningún bloqueo. Por tanto un
perfil de miembro en `light` sólo puede describir accesorios (soportes,
cables…), nunca otra luz; `light_member_configurations` sigue siendo el único
dueño de las especificaciones por luz y `light_member_link` no se toca.
*Veredicto:* aprobado sin cambios. *Residual, no bloqueante:* la exclusión vive
en una condición de fila, no en la definición; si una publicación futura
retirara esa restricción, la duplicación de la ronda 213 reaparecería. Lección
para quien revise: el contrato efectivo es definición ∩ `row_conditions`, y
leer sólo la lista global de opciones no basta.

## Notas fuera del alcance de la pregunta

- `review_needed[1]` (hechos de miembro separados de aprobaciones raíz y de
  consumidores) no lo revisé; sólo señalo que `bicycle` y `wheel` tienen
  campos raíz que describen componentes (talla de rueda, horquilla…) y que ese
  solape raíz↔perfil es otra pregunta, no de tablas de contenido.
- Los 5 excluidos (`kit_members` legacy) están bien fuera: un perfil exige
  colección activa.
- Ninguna de las otras 16 plantillas restringe `family` por `row_conditions`
  (verificado en ambos catálogos): en ellas aplica la lista global.
- `kit_members` sin `unique_by` permite dos filas idénticas; el perfil las
  distingue por `row_id` y el editor ya muestra su posición (E4). No bloquea.

## Qué no toqué

Ningún código, SQL, JSON de alcance ni catálogo. Sólo este documento y, en
ronda 214, `member-brake-owner-delta-proposal-2026-09-14.md` (propuesta D2).
