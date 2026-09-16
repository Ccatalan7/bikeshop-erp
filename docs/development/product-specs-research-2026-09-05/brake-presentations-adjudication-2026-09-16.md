# Presentaciones completas de freno: D2 publicado como revisión 223 — 2026-09-16

Publicado en producción como `supabase/migrations/20260916130000_brake_presentations.sql`
(sha256 `59279faa5cd870e5cb03aa9d8dd4e246206cfe47aaa2f949bc03164302e9bae1`), verificado a las
08:01:26Z con `supabase/manual_checks/verification/20260916130000_brake_presentations.sql`
(sha256 `b8ad24a3889a9255099d2bd67b4287161ec104653908869d78ecdaaf02766540`). Las tres
presentaciones y el cáliper conservan id y observaciones: `hydraulic_disc_brake` (`22fdca94…`)
3→18 con 4 usos y 12→15 campos, `mechanical_disc_brake` (`b6df9356…`) 2→13 con 1 uso y 8→11
campos, `rim_brake` (`3a76d564…`) 2→10 con 28 usos y 5→8 campos, `brake_caliper` (`9d97103e…`)
30→32 con 11 usos y 27→28 campos. Ningún producto, hecho, referencia ni asignación cambió: los
44 vínculos, las 44 revisiones (md5 `ce18c1da…`) y los 5 hechos (md5 `4e173d8d…`) son los mismos
antes y después. Definiciones globales 899 → 901.

Este bloque cierra los dos errores de propiedad que dejó abiertos
[brake-member-ownership-adjudication-2026-09-15.md](brake-member-ownership-adjudication-2026-09-15.md)
sobre la propuesta 222, y con él quedan publicados los 37 reemplazos originales del plan
(105 de 105 entregas planificadas de arquitectura de plantillas). No certifica compatibilidad
mecánica ni autoriza llenado.

## Entradas fijadas

| Artefacto | SHA-256 |
|---|---|
| Preimagen fresca `.tmp/product-spec-catalog/brake-presentations-preimage-20260916/preimage.json` (07:54:29Z; 4 plantillas, 52 campos, 30 definiciones) | `26413eee70d317a4896721fc874a43429043633dbd08955dada1a64d70e4d29e` |
| Delta de IDs `…/brake-presentations-snapshots-20260916/product-ids.json` (44 productos: 28 de llanta, 4 hidráulicos, 1 mecánico, 11 cálipers) | `a347e1520d50e58f12abcce61c142b5d94952d4ebc28f4e115972afd7c18f4a9` |
| Manifiesto de fichas `…/brake-presentations-snapshots-20260916/manifest-20260916T075504563684.json` | `721ec61da9f2d8ed1e8cebd0cef63708ba30b23069af47778a3b24edbd55abe6` |
| `brake-presentations-2026-09-16-catalog.json` · `-cases.json` · `-packet.json` | `24be252a8cdb18c2…` · `3d0738110a79f661…` · `90b6a2ac34e40415…` |
| Ensayo local `.tmp/db/brake-presentations-2026-09-16-forward-candidate/forward-replay-and-cases.log` | `804a38fb56c64de3191ea2d368e509e20301fb67d7125dbfefaffffcc399f6e6` |
| Auditoría de adopción `.tmp/product-spec-catalog/brake-presentations-adoption-20260916.json` | `295478cde5afb72f594ce55153727f9feca9549ba6f92ad0173bb4a4895ab4ba` |
| Lectura antes / después `…/brake-presentations-readback-20260916/before.csv` · `after.csv` | `399b56a64c709f7b…` · `14a318baf257e0fe…` |

Compilador: `scripts/inventory/compile_brake_presentations.py <preimagen-fresca>`. Este bloque no
tiene preimagen congelada propia porque el diseño es de la revisión 223, no del catálogo de las 37:
la preimagen fresca es la única referencia y la migración aborta si alguna plantilla, campo o
definición difiere de ella. Los siete prototipos del sucesor antiguo
(`brake_assembly_configurations`, `brake_circuit_connections`, `rotor_size_recipe`,
`rotor_included_diameter_mm`, `levers_included`, `rim_brake_style`, `lever_pull_required`) se
comprueban ausentes antes y después, por clave y por id.

## Qué cambió en las plantillas

- **Selector `brake_presentation`** (`daa3972f-3565-598f-9c5b-00d92f61b0de`, opción única, visible y
  filtrable). Obligatorio siempre. Opciones por plantilla: hidráulico «Un freno completo (maneta,
  manguera, cáliper)», «Par delantero y trasero», «Cáliper con manguera, sin maneta»; mecánico «Un
  freno completo (maneta, cable y funda, cáliper)», «Par delantero y trasero», «Cáliper sin
  maneta»; llanta «Un mecanismo (un extremo)», «Par de mecanismos», «Set con manetas y cables».
- **`kit_members`** (definición compartida ya existente) con la colección estándar de perfiles.
  Obligatorio siempre; depende del selector y de la fuente de evidencia. Familias admitidas:
  hidráulico maneta, cáliper, manguera, rotor, adaptador, pastilla y líquido; mecánico maneta,
  cáliper, cable, funda, rotor, adaptador y pastilla; llanta cáliper, maneta, pastilla, cable y
  funda. Ninguna presentación admite otra presentación ni el mando combinado.
- **`brake_circuits`** (`d9fe443a-3d63-5af9-9daa-4ad340baa0bb`, filas). Sólo aplica cuando la
  presentación tiene circuitos (freno completo o par; set de llanta con manetas). Cada fila dice
  qué rueda frena, cómo se acciona y a qué filas de maneta, cáliper y línea apunta; el líquido
  entregado sólo existe en circuitos hidráulicos. Hidráulico admite sólo «Hidráulico», mecánico y
  llanta sólo «Cable».
- **Legacy exacto.** Los 25 campos vivos de las tres presentaciones pasan a sección `legacy`,
  nunca obligatorios, con sus mismos ids, definiciones y reglas; se leen y no se editan.
- **`brake_caliper` gana `tool_size_mm`**: medida intrínseca, permitida siempre, nunca exigida,
  con evidencia OEM o de envase.

## Compuertas, con su evidencia

| Compuerta | Resultado |
|---|---|
| Ensayo SQL local (replay exacto, 22 casos, rollback) | `local_forward true · exact_replay true · cases 22 · rollback true` |
| Arnés Dart del formulario | 26 pruebas, todas verdes |
| Adopción sobre 44 fichas frescas por RPC | 44 evaluadas · 0 bloqueantes · 44 pendientes · 5 observaciones legacy conservadas (hidráulicos) · 0 activas sin proyectar · `no_population_conflict_detected` en las 44 |
| Verificador antes / después | `division by zero` antes; `APPLIED and verified` después; recibo `.tmp/db/migration-receipts/20260916130000.receipt` |
| Guardia de coherencia | no tocada: los campos con `row_conditions` y `row_coherence` nacen sin hechos; `spec_coherence_publication_guard` sigue `O` antes y después |
| Lectura posterior | `hydraulic_disc_brake=18/15 · mechanical_disc_brake=13/11 · rim_brake=10/8 · brake_caliper=32/28` · 2 definiciones nuevas, 1 visible y filtrable · prototipos ausentes · `tool_size_mm` en el cáliper · 44 vínculos · revisiones y hechos con el mismo md5 |

## Adjudicaciones

1. **Los dos errores de Root quedan cerrados.** El tamaño de herramienta pertenece al cáliper
   (`a_caliper_declares_the_tool_size_of_its_bolts`) y el dato raíz de las presentaciones queda
   como legacy sin editar (`the_retired_root_tool_size_no_longer_answers`). Los dos mecanismos de
   un par de llanta son dos filas de `brake_caliper` con superficie «Llanta» y perfil propio, con
   marca, posición y medidas independientes
   (`a_pair_of_rim_mechanisms_is_two_rows_with_their_own_profiles`); la raíz de `rim_brake` no
   conserva ningún campo activo de mecanismo.
2. **Ausencia es pendiente, nunca pieza única.** Sin presentación, el motor pide la presentación
   y las piezas; con presentación y sin filas, pide piezas y circuitos
   (`a_presentation_without_pieces_is_pending_never_single`). Un cáliper suelto no debe ni puede
   declarar circuito (`a_bare_caliper_with_hose_owes_no_circuit`,
   `a_bare_caliper_cannot_declare_a_circuit`); un solo mecanismo de llanta tampoco.
3. **Circuito separado de sus piezas.** Un circuito que apunta a una fila inexistente bloquea
   (`row_reference_unresolved`), dos circuitos con el mismo identificador bloquean (`row_shape`),
   un circuito de cable no lleva líquido entregado (`row_field_applicability`) y un circuito de
   cable no cabe en un hidráulico ni una manguera en un mecánico (`row_option`). El motor no
   compara medidas entre perfiles: rotor incluido contra admitido, tiro de maneta contra
   accionamiento o líquido admitido contra entregado (E2) siguen sin existir y se documentan
   como declaración, no como validación.
4. **Sin recursión.** Un freno completo dentro de un freno, o una presentación de llanta dentro
   de otra, bloquea por familia (`a_complete_brake_cannot_contain_a_complete_brake`,
   `a_rim_presentation_cannot_contain_a_rim_presentation`).
5. **Dos unidades del mismo modelo son dos filas.** Dos manetas del mismo modelo, izquierda y
   derecha, conviven con sus propios perfiles (`a_pair_keeps_two_levers_of_the_same_model_apart`).
6. **Desvío respecto de la propuesta 222 §8(6).** La propuesta esperaba que, sin selector, las
   piezas y los circuitos quedaran pendientes «por prerrequisito». Los dos motores reportan un
   campo obligatorio ausente como `required_missing` aunque su prerrequisito también falte, y
   callan sobre un campo cuya compuerta de aplicabilidad no se puede resolver. El caso
   `without_a_presentation_everything_is_pending` fija ese comportamiento real; el resultado
   práctico es el mismo: nada bloquea y nada se da por pieza única.
7. **Lo que no prueba este bloque.** Cambiar de presentación conservando filas (§8(7)) es
   conducta del cliente y de la RPC de guardado, no de la plantilla; no hay caso de plantilla.
   Un «Par» con un solo circuito no queda marcado: la cardinalidad de filas se cuenta contra un
   campo numérico, no contra una opción del selector. Las compuertas por perfil de maneta (§8(11))
   viven en la plantilla de `brake_lever`, publicada el 2026-09-15, y no se repiten aquí.
   Los pares de manetas vendidos solos siguen como están (D2-b), a la espera de una
   presentación de manetas o del alcance de campos por miembro (E1).
8. **Un asignado sospechoso, fuera de este bloque.** El producto 8092 «RESORTE (PAR) HERR/FRE
   MTB CORTO N» está vinculado a `rim_brake` y es un par de resortes, una pieza menor, no una
   presentación. Sigue en su plantilla con el selector pendiente como los otros 27; corregirlo es
   trabajo de la cola de asignación, no de una publicación de plantilla.

## Qué sigue abierto en frenos

Rutas de teléfono y editores embebidos, la superficie de consumidores de frenos
([brake-piece-consumers-review-2026-09-15.md](brake-piece-consumers-review-2026-09-15.md)),
E1 y E2 en el motor, la presentación de pares de manetas y la migración de
`brake_shift_combined_control`. Las 44 fichas quedan pendientes de declarar su presentación y
sus piezas; ninguna bloqueada.

Llenado técnico persistido: 0.
