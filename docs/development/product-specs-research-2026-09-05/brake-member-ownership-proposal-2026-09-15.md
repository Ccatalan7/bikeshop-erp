# Propuesta D2 · propiedad por pieza en las cinco fichas de freno — 2026-09-15 (corregida en ronda 222)

**Propuesta, no entrega activa.** Sin SQL, migraciones, código, UI, productos,
runtime, activación ni fill. Base: preimagen viva
`.tmp/product-spec-catalog/brake-ownership-20260915/preimage.json` `bffd72b6…`
(`captured_at 2026-09-15T02:30:40Z`; claves `templates`, `fields`,
`existing_definitions`, `explicit_bindings`, `effective_bindings`). El
catálogo congelado de sucesores es objetivo histórico; ninguna interfaz suya se
da por publicada.

## 0. Correcciones sobre la versión 221 (rechazada)

1. `mechanical_disc_brake` tiene `technical_family = complete_brake` y
   descripción viva «Freno de disco mecánico completo»: es un freno completo,
   no un cáliper suelto. Retiro la reinterpretación de `rotor_diameter_mm`
   como «admitido»: un hecho vivo no cambia de significado por lectura; se
   conserva como legacy con su significado histórico y el dato nuevo se captura
   en su dueño.
2. `caliper_hydraulic` tiene rótulo «Hidráulico» (booleano, relevante para
   compatibilidad): es el accionamiento de la pieza, no «incluye cáliper».
   Retiro la inferencia y cualquier idea de reasignar productos por su valor.
3. Puerto de purga y fitting existen **por extremo**: la maneta tiene su
   puerto y su oliva/insert; el cáliper tiene el suyo y su espaciador de purga
   (Shimano BL-M8100/BR-M8120, [DM-MBDBR01-01](https://si.shimano.com/en/pdfs/dm/MBDBR01/DM-MBDBR01-01-ENG.pdf)).
   El líquido **especificado** por cada pieza es de la pieza; el líquido **con
   que se entrega** un circuito es del circuito, y un par puede traer dos
   circuitos distintos. Ninguno de los tres queda en la raíz «por evitar
   definiciones».
4. Ausencia de filas no es conocimiento. La presentación se elige de forma
   explícita con un selector obligatorio y todo lo demás pende de él. En un
   par, los campos intrínsecos de la raíz no conviven con dos perfiles: la raíz
   de una presentación no lleva campos de pieza activos.
5. Un perfil de maneta usa la plantilla `brake_lever` vigente, con los cambios
   de este paquete; por eso `brake_lever` gana campos de extremo y **no** gana
   contenidos ni presentación (evitaría recursión). La familia autorizada por
   colección se restringe en el contrato.
6. Fuentes: las cifras de espesor son de manuales y rotores concretos, no
   universales; la mano de cada maneta no se deduce del país; clasificación
   comercial, propiedad y veredicto mecánico se tratan por separado.

## 1. Lo que hay hoy (leído del snapshot)

| Plantilla | v | Familia | Nombre / descripción vivos | Campos vivos (rol) | Productos efectivos |
|---|---|---|---|---|---|
| `hydraulic_disc_brake` `22fdca94…` | 3 | complete_brake | «Freno Disco Hidráulico» / «Kit o freno completo hidráulico» | brake_system, brake_position, mount_standard, rotor_diameter_mm (opciones incluyen «203/180», «180/160», «160/140»), pad_shape_code, piston_count, fluid_type, hose_length_mm, hose_fitting_type, bleed_port, reach_adjust, spec_evidence_source | 4 |
| `mechanical_disc_brake` `b6df9356…` | 2 | complete_brake | «Freno Disco Mecánico» / «Freno de disco mecánico completo» | brake_system, brake_position, mount_standard, rotor_diameter_mm (**requerido**), pad_shape_code, tool_size_mm, reach_adjust, spec_evidence_source | 1 |
| `rim_brake` `3a76d564…` | 2 | rim_brake | «Freno de Llanta / V-Brake» / «Frenos tipo V-Brake o cantilever» | brake_system, brake_position, tool_size_mm, reach_adjust, spec_evidence_source | 28 |
| `brake_lever` `dee33c12…` | 2 | brake_lever | «Manilla de Freno» / «Manillas o palancas de freno independientes del sistema» | brake_type, brake_system, brake_position, reach_adjust, caliper_hydraulic («Hidráulico»), spec_evidence_source | 18 |
| `brake_shift_combined_control` `a530a9f5…` | 16 | propia | — | contrato `rules_version 2` con `combined_control_units` (member, unit Izquierdo/Derecho/Único, control_model, edition, clamp_mm, source_url; `unique_by member`), configuraciones enlazadas por `unit_row_id`, cardinalidad `declared_units`, 10 legacy | 1 |

Los cuatro primeros: contrato `version 1`, sin `member_profiles`, sin
`row_coherence`, `prerequisites {}`, `helpers {}`. `kit_members`
(`d0cfc800…`) existe. Plantillas de pieza activas hoy (originales, no sus
sucesores): `brake_lever` (arriba); `brake_caliper` v2 («Calipers completos
hidráulicos o mecánicos»: bleed_port, fluid_type, piston_count, mount_standard,
pad_shape_code, hose_fitting_type, rotor_diameter_mm, reach_adjust,
brake_position, caliper_hydraulic, brake_type, brake_system); `rotor` v3
(rotor_diameter_mm, rotor_thickness_mm, rotor_mount_type, rotor_floating,
rotor_material, tool_size_mm, brake_position); `brake_pad` v2 («Pastillas para
frenos de disco o de llanta»: brake_type, pad_shape_code, compound_type,
pad_finned, pad_spring_included, pad_compatibility_note). Publicadas el 07-09
y vivas: `hydraulic_hose` (hose_length_mm, hose_system_code, diámetros,
fittings_included, brake_hydraulic_connections), `brake_mount_adapter`
(bolts_included, brake_adapter_fitments), `brake_fluid`, `control_cable`,
`control_housing`. No hay hechos en el snapshot; lo que exista se conserva.

**Zapata vs pastilla.** `brake_pad` cubre ambas sólo por el token
`brake_type` (V-Brake / Cantilever / Disco); no tiene tipo de espárrago ni
largo de zapata. Park Tool distingue espárrago liso (cantilever, con tuerca) y
espárrago roscado con separadores cóncavos/convexos, y pastilla fija o de
cartucho ([Brake Pad Replacement: Rim Brakes](https://www.parktool.com/en-us/blog/repair-help/brake-pad-replacement-rim-brakes)).
La zapata de llanta como miembro de un `rim_brake` cabe hoy sólo con
`brake_type` (y `member_role` «pastilla» u «otro»: la lista global no tiene
«zapata»); su interfaz queda pendiente del sucesor de `brake_pad`. No asumo
cobertura.

## 2. Fuentes y sus límites

- Sistema hidráulico: maneta con oliva preinstalada; purga con embudo
  SM-DISC en la maneta y espaciador amarillo en el cáliper; manguera insertada
  hasta la marca (Shimano BL-M8100/BR-M8120, [DM-MBDBR01-01](https://si.shimano.com/en/pdfs/dm/MBDBR01/DM-MBDBR01-01-ENG.pdf);
  aceite mineral Shimano para BR-M8100/M8120 según [DM-BROIL-02](https://si.shimano.com/en/pdfs/dm/BROIL/DM-BROIL-02-ENG.pdf)).
  Lección: cada extremo tiene su puerto y su unión; el líquido especificado es
  de cada pieza, el contenido es del circuito armado.
- Espesor de rotor: Shimano recomienda reemplazar bajo 1,5 mm en rotores que
  nacen de 1,8 mm, según [Park Tool, rotor](https://www.parktool.com/en-us/blog/repair-help/disc-brake-rotor-removal-installation);
  SRAM: «bajo el mínimo grabado en el rotor: 1,55 mm en rotores de 1,85 mm y
  1,7 mm en rotores de 2 mm» ([SRAM, guía de servicio](https://www.sram.com/en/learn/brake-welcome-guide/brake-service-guide)).
  Cifras **por manual y rotor concreto**; no son constantes de familia. Espesor
  real → dueño `rotor`; espesor admitido → dueño `brake_caliper`; nadie los
  compara automáticamente.
- Montaje: IS, Post Mount y Flat Mount con agujeros en cáliper, cuadro o
  adaptador ([Park Tool, alineación de disco mecánico](https://www.parktool.com/en-us/blog/repair-help/mechanical-disc-brake-alignment);
  [SRAM, especificaciones de montaje](https://www.sram.com/globalassets/document-hierarchy/frame-fit-specifications/aftermarket/disc-brake-caliper-mounting-specifications-for-road-and-mtb.pdf)).
- Pastillas de disco: forma específica del modelo de cáliper; retención por
  pasador, resorte, imán o clip; compuestos orgánico/semimetálico/metálico
  ([Park Tool, pastillas de disco](https://www.parktool.com/en-us/blog/repair-help/disc-brake-pad-removal-installation)).
- Frenos de llanta: doble pivote, side pull, center pull, linear pull/V,
  cantilever, U-brake ([Park Tool, identificación](https://www.parktool.com/en-us/blog/repair-help/rim-brake-identification));
  las direct-pull piden manetas de tiro largo y «no es seguro mezclar manetas
  y cables entre direct-pull y otros tipos» ([Sheldon Brown, canti-direct](https://www.sheldonbrown.com/canti-direct.html)).
  El tiro es propiedad de cada pieza; su calce es una declaración con fuente.
- Mano de la maneta: la práctica varía por país y por ciclista y no es una
  regla ([Sheldon Brown, brakturn](https://www.sheldonbrown.com/brakturn.html));
  por eso lado y rueda son datos declarados, nunca deducidos.

## 3. Principios del modelo

- **Presentación ≠ pieza ≠ veredicto.** Las plantillas `complete_brake` y
  `rim_brake` son presentaciones (qué se vende armado); `brake_lever`,
  `brake_caliper`, `rotor`, `hydraulic_hose`, `brake_pad`, `brake_mount_adapter`
  son piezas. Ninguna fila ni perfil emite compatibilidad.
- **Selector explícito.** Cada presentación empieza por `brake_presentation`
  (nuevo `single_select`, requerido siempre). Todo lo demás pende de él vía
  `prerequisites`; nada se deduce de que falten filas.
- **Identidad de pieza = fila de `kit_members` + perfil.** Dos filas del mismo
  modelo son dos piezas (D1 lo prueba). El lado y la posición son columnas de
  la fila (`position` Izquierdo/Derecho/Delantero/Trasero), no identidad.
- **Circuito = relación entre filas**, declarada en la raíz y validada por
  existencia con `row_coherence.links` (como `combined_control` con
  `unit_row_id`). Un circuito lleva el líquido con que se entrega; nunca un
  veredicto.
- **Extremo = dueño.** Puerto, unión y líquido especificado van en la pieza
  que tiene ese extremo (maneta o cáliper), en su perfil.
- **Sin contenidos en plantillas de pieza** que puedan ser miembros:
  evita la recursión hasta que exista E1 (§6).

## 4. Matriz live → cambio

### Definiciones y campos nuevos (compartidos)

| Nuevo | Tipo | Uso |
|---|---|---|
| `brake_presentation` | single_select | opciones por plantilla (abajo); requerido siempre |
| `brake_circuits` | json filas | `circuit_id` (text, req), `position` (token Delantero/Trasero/Único, req), `actuation` (token Hidráulico/Cable, req), `lever_row_id`, `caliper_row_id`, `line_row_id` (text; ids de filas de `kit_members`), `fluid_as_shipped` (token DOT 4/DOT 5.1/Aceite Mineral, `allowed_when actuation = Hidráulico`), `source_url` (url, req); `unique_by [[circuit_id]]`; enlaces `row_coherence` de las tres columnas `*_row_id` → `kit_members` con `label_columns [member_role, position, identity_model]` |
| `brake_lever`: campos añadidos con definiciones **existentes** | `bleed_port`, `hose_fitting_type`, `fluid_type` | extremo de la maneta; `allowed_when caliper_hydraulic = true`; `fluid_type` aquí es el líquido **especificado** para la maneta |

### `hydraulic_disc_brake` (presentación hidráulica)

`brake_presentation`: «Un freno completo (maneta, manguera, cáliper)», «Par
delantero y trasero», «Cáliper con manguera, sin maneta».

| Campo vivo | Después | Dueño |
|---|---|---|
| brake_system | legacy | identidad por piezas (marca/modelo de cada fila) |
| brake_position | legacy | posición por circuito y por fila |
| fluid_type | legacy | especificado → perfil maneta/cáliper; entregado → `brake_circuits.fluid_as_shipped` |
| bleed_port, hose_fitting_type | legacy | extremo → perfil `brake_lever` (campos añadidos) y `brake_caliper` (vivos) |
| hose_length_mm | legacy | perfil `hydraulic_hose` |
| piston_count, pad_shape_code, mount_standard | legacy | perfil `brake_caliper` |
| rotor_diameter_mm | legacy (significado histórico conservado) | rotor incluido → perfil `rotor`; admitido → perfil `brake_caliper.rotor_diameter_mm` y `brake_mount_adapter` |
| reach_adjust | legacy | perfil `brake_lever` |
| spec_evidence_source | activo | evidencia del envase |
| — | `brake_presentation`, `kit_members` + `member_profiles`, `brake_circuits` | familias autorizadas: brake_lever, brake_caliper, hydraulic_hose, rotor, brake_mount_adapter, brake_pad, brake_fluid |

Prerrequisitos: `kit_members`, `brake_circuits` → `[brake_presentation,
spec_evidence_source]`. `required_when`: `kit_members` y `brake_circuits`
siempre (una presentación sin piezas queda pendiente, no «única»).

### `mechanical_disc_brake` (presentación mecánica completa)

`brake_presentation`: «Un freno completo (maneta, cable/funda, cáliper)», «Par
delantero y trasero», «Cáliper sin maneta».

| Campo vivo | Después | Dueño |
|---|---|---|
| brake_system, brake_position | legacy | como arriba |
| mount_standard, pad_shape_code | legacy | perfil `brake_caliper` |
| rotor_diameter_mm (requerido) | legacy, **`is_required → false`** (un legacy no se exige) | rotor incluido → `rotor`; admitido → `brake_caliper` / adaptador |
| tool_size_mm | **activo** (excepción documentada) | sería del cáliper, pero `brake_caliper` vivo no tiene `tool_size_mm`; se conserva en la raíz hasta que la pieza lo tenga |
| reach_adjust | legacy | perfil `brake_lever` |
| — | `brake_presentation`, `kit_members`, `brake_circuits` (actuation Cable; `line_row_id` = cable) | familias: brake_lever, brake_caliper, control_cable, control_housing, rotor, brake_mount_adapter, brake_pad |

### `rim_brake` (presentación de freno de llanta; 28 productos)

`brake_presentation`: «Un freno (un extremo)», «Par», «Set con manetas y
cables». La raíz sigue siendo el mecanismo (brazos): `brake_system`,
`brake_position`, `tool_size_mm` **activos** (intrínsecos del mecanismo, no de
una pieza con plantilla). `reach_adjust` → legacy (maneta). Añadir
`kit_members` + `member_profiles` (familias: brake_lever, brake_pad,
control_cable, control_housing) y `brake_circuits` (actuation Cable;
`caliper_row_id` vacío permitido cuando el mecanismo es la propia raíz:
`allowed_when` por presentación). Estilo (V/cantilever/doble pivote) y tiro
requerido siguen pendientes del sucesor; no se inventan.

### `brake_lever` (pieza)

Sin `kit_members`, sin presentación. Cambios: añadir `bleed_port`,
`hose_fitting_type`, `fluid_type` (definiciones existentes) con `allowed_when
caliper_hydraulic = true`; ayuda de `caliper_hydraulic` = «Accionamiento
hidráulico de esta maneta»; `brake_position` y `brake_type` sin cambio.
**Pares de manetas vendidos solos:** no se representan en `brake_lever`
(recursión); van a una presentación. Hasta que exista una presentación de
manetas (D2-b) o E1, un par sigue como está hoy. No se reasigna ningún
producto.

### `brake_shift_combined_control`

Sin cambio. Ya tiene unidades físicas, lado, edición, cardinalidad y
configuraciones enlazadas. Su migración a `kit_members` es posterior y, como
puede ser miembro de una bicicleta, también depende de E1.

## 5. Familia autorizada y no recursión

`kit_members.family` global admite 105 familias; cada presentación restringe
con `row_conditions.fields.kit_members.allowed_options.family` a las listadas
arriba (mismo mecanismo que `light`, que hoy bloquea `light` con `row_option`).
Ninguna presentación autoriza `complete_brake`, `rim_brake` ni
`brake_shift_combined_control` como miembro. `get_product_spec_member_template_v1`
exige además familia en `allowed_values` y plantilla activa (:876-884); el
perfil de maneta se crea con la plantilla `brake_lever` vigente, es decir,
con los campos de extremo de este paquete.

## 6. Qué se implementa con el motor actual y qué necesita motor

Con el motor actual: selector + `prerequisites` + `allowed_when`/`required_when`
por campo (365 reglas `when` viven hoy en el catálogo publicado; servidor
`spec_condition_internal_v1`), `kit_members` + `member_profiles` (D1),
`row_coherence.links` y `unique_by` para `brake_circuits`, restricción de
familia por `allowed_options`, legacy conservado con roundtrip tipado.

Necesita motor:
- **E1 · alcance de campos en scope de miembro:** que un campo de rol
  `contents`/presentación de la plantilla de una pieza no se ofrezca ni valide
  cuando esa plantilla se usa como perfil. Sin E1, ninguna plantilla que sea
  miembro puede tener contenidos (por eso `brake_lever` no los recibe y los
  pares de manetas esperan).
- **E2 · comparación entre scopes:** rotor incluido vs admitido, tiro de
  maneta vs accionamiento, líquido especificado vs entregado, circuito
  completo. Hoy no existe; se documenta como declaración y se prueba que **no**
  valida (caso 13).
- Cambiar opciones vivas (`brake_position` mano/rueda, `rotor_diameter_mm`
  con pares «203/180») es cambio de definición con datos: fuera de D2.

## 7. Paquete mínimo coherente (D2-a)

1. Definiciones nuevas: `brake_presentation`, `brake_circuits`.
2. `brake_lever`: tres campos añadidos con definiciones existentes y su
   `allowed_when`; ayuda de `caliper_hydraulic`.
3. `hydraulic_disc_brake`, `mechanical_disc_brake`, `rim_brake`: selector,
   `kit_members` + `member_profiles` (colección estándar), `brake_circuits`
   con enlaces, `allowed_options.family`, prerrequisitos, legacy exacto de la
   matriz (mismos ids, ayudas, defaults y reglas; `section_key = legacy`;
   `is_required = false` en `rotor_diameter_mm` de mecánico), ayudas que
   nieguen compatibilidad por convivencia.
4. Sin prototipos del sucesor (`brake_assembly_configurations`,
   `brake_circuit_connections`, `rotor_size_recipe`, `rotor_included_diameter_mm`,
   `levers_included`, `rim_brake_style`, `lever_pull_required`): guard por clave
   e id, como D1.
5. Revisiones calculadas desde la preimagen (contrato + una por fila de campo
   tocada), nunca «+1». `brake_shift_combined_control` fuera.

D2-b (después): presentación de manetas (par) o E1; sucesores de
`rim_brake`/`brake_pad`/`brake_caliper`; migración de `combined_control_units`.

## 8. Casos que necesita la implementación

Preimagen y delta: (1) los cuatro contratos y campos vivos exactos por id y
clave; `kit_members` existente; (2) delta exacto por plantilla (campos nuevos,
`section_key` de los legacy, `is_required` sólo en el rotor del mecánico);
(3) revisiones calculadas; (4) prototipos ausentes antes y después; (5) huella
de hechos/productos/referencias/mapeos igual; legacy legible con
`p_include_legacy`; roundtrip idéntico aceptado (`hose_length_mm` decimal en
texto; `rotor_diameter_mm` «160/140» como opción) y cambio rechazado.

Selector y presentación: (6) sin `brake_presentation` → `required_missing`
pendiente y `kit_members`/`brake_circuits` pendientes por prerrequisito, sin
bloqueo; (7) cambiar la presentación de «Un freno completo» a «Par» conserva
filas, perfiles y circuitos ya cargados y sólo cambia lo exigido (segundo
circuito pendiente); cambiar a «Cáliper sin maneta» no borra la fila de maneta:
queda como contradicción declarada por el operador (pendiente), nunca
borrado automático; (8) `brake_circuits.fluid_as_shipped` con `actuation =
Cable` → bloqueante por `allowed_when`.

Piezas y circuitos: (9) filas de las familias autorizadas se guardan; una
fila `family = hydraulic_disc_brake` dentro de un freno → `row_option`
bloqueante; (10) dos manetas del mismo modelo (Izquierdo/Derecho) son dos filas
y dos perfiles con `reach_adjust` propio; (11) un perfil de maneta con
`caliper_hydraulic = false` rechaza `bleed_port`/`fluid_type` (allowed_when);
uno de maneta rechaza `piston_count` (23514); (12) `brake_circuits.lever_row_id`
apuntando a una fila inexistente o a una fila de cáliper → rechazo por enlace;
dos circuitos con el mismo `circuit_id` → rechazo; (13) rotor incluido 180
con cáliper que declara admitido 160 **se guarda sin incidencia** (E2 no
existe; el caso lo documenta); (14) el contexto raíz no expone hechos ni
reclamaciones de perfiles; (15) un producto `brake_lever` no ofrece
`kit_members` ni selector (no recursión).

## 9. Qué no afirmo

No certifico compatibilidad ni completitud de sets; no propongo reglas por
marca, velocidades o posición; no doy por activos sucesores ni sus
interfaces; no reasigno productos; no toco `combined_control`. Ningún archivo
de Root, catálogo congelado, código, SQL ni dato fue editado; sólo este
documento.
