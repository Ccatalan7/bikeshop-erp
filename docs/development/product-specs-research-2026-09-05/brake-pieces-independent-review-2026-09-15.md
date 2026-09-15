# Revisión independiente · sucesores de `brake_caliper`, `brake_pad` y `rotor` (2026-09-15, ronda 225)

Revisión acotada del candidato de Root, sin producción, sin migraciones, sin
escritura de datos ni de archivos de Root, y sin tocar D2. Sondas propias en
`.tmp/product-spec-catalog/brake-pieces-review-20260915/` (Dart 12/12 con
`SPEC_CATALOG_CASES` propio; diagnóstico SQL en rollback con los mismos
constructores de Root). Fuentes externas: Park Tool «Brake Pad Replacement: Rim
Brakes» para la zapata; el resto sale de las plantillas y del motor.

| Artefacto | Hash |
|---|---|
| `.tmp/db/brake-pieces-2026-09-15-candidate.sql` | SHA-256 `f74307cf4d437d86e261df96e52cccb8415e26de0147dd2cbe29d1213328b8d5` |
| `brake-pieces-2026-09-15-catalog.json` / `-cases.json` / `-packet.json` | `a2ef73b6…` / `0e11a5d9…` / `0346fe79…` |
| `scripts/inventory/compile_brake_piece_successors.py` | `2fb7991b…` |
| Preimagen productiva (03:36:12Z; 11 + 53 + 18 productos por binding efectivo, 0 explícitos) | `c115d62e…` |
| Integrado congelado de origen | `e0cccea8…` (no modificado) |
| Mi sonda `probe_cases.py` / `review-cases-dart.json` | `4f35fd3a…` / `61aa1db8…` |

## 1. Dictamen

**No apruebo el SHA `f74307cf…` tal cual.** El empaquetado, la conservación
legacy, el rotor y la pastilla de disco están sólidos (§2). Tres defectos
reproducibles del cáliper y de la zapata exigen un cambio mínimo de metadata
dentro de este mismo paquete, todos sobre definiciones o contrato aún no
publicados, y por tanto un recompilado con nuevo SHA (§3: H1 contradicción
interna del cáliper híbrido, H2 el cáliper no es dueño de su propio montaje,
H3 el recambio de cartucho debe declarar un espárrago que no tiene). H4 es un
hueco de interfaz recomendado en el mismo recompilado. Lo demás son límites de
superficie y detalles (§4) que no bloquean.

## 2. Lo que ya es sólido (verificado)

- **Empaquetado.** Mismo publicador de plantillas existentes que aplicaron
  `20260915004000` y `20260915023000`: guardia del validador `ac0738d5…`
  (cuerpo vigente, ninguna migración posterior lo redefine), preimagen exacta
  por id de cada campo y plantilla, definiciones reutilizadas byte a byte con
  sus opciones, colisión de claves, huella md5 de hechos, productos,
  referencias y mapeos de categoría antes y después, replay exacto. Log de Root:
  `exact_metadata` 1/1 en forward y replay; 46 casos coinciden con el validador
  desplegado. Revisiones calculadas y confirmadas por el replay: cáliper
  2+1+13 actualizaciones+13 altas = 29; pastilla 2+1+9+11 = 23; rotor
  3+1+9+4 = 17.
- **Delta contra el integrado (diff programático).** Sólo: retiro del legacy
  nunca publicado `hose_system_code` y de sus entradas de contrato; ayuda de
  `compound_type` corregida (el nombre comercial puede preceder a la clase);
  campos legacy con sección, orden e ids vivos y `semantic_roles: legacy`; y
  dos etiquetas del integrado que no existían en vivo quedan fuera: la de
  `fluid_type` y «Espesor nominal nuevo del rotor (mm)» sobre
  `rotor_thickness_mm`, con lo que el espesor antiguo no se rotula como
  nominal. Ninguna definición difiere del integrado.
- **Legacy inerte para el validador.** Valores en `rotor_thickness_mm` y
  `tool_size_mm` no producen incidencia alguna (casos `bkr_rotor_keeps_…`), la
  mezcla `allowed_when always/never` entre legacy es cosmética.
- **Rotor.** Diámetro numérico (`160/140` bloquea con `field_constraint`: el
  par por posición vive en la receta del cáliper), montaje 6 pernos/Centerlock
  obligatorio, material obligatorio, flotante, espesor nominal y límite de
  desgaste como par ordenado (límite mayor bloquea, igual se admite, límite
  sin nominal se admite), restricción de compuesto con fuente y sin deducirla
  del metal, herramienta legacy sin convertirla en compatibilidad. Correcto.
- **Pastilla de disco.** `pad_shape_code` obligatorio, retención, modelo de
  retén, compuesto OEM literal separado de la clase, resorte y unidades como
  contenido, cáliperes declarados por fila con `unique_by`
  (marca, modelo, generación, variante) y fuente por fila: compartir marca no es
  una declaración. Un campo de disco bajo `Llanta` bloquea
  (`field_applicability`, mi caso).
- **Cáliper, lo correcto.** Tiro de cable exigido por el cáliper y sólo para
  mecánico/híbrido; receta de rotor por posición con espesor admitido en la
  receta y no trasladado al rotor; aprobaciones de fluido por modelo, con
  producto obligatorio para aceite mineral y `unique_by` que impide que otra
  URL cree otro sistema; puertos hidráulicos de ESTA pieza; híbrido con
  conversión interna sin manguera externa y aun así con aprobaciones de
  fluido (mi caso); freno de llanta con montajes documentados y rangos
  ordenados; sin frenos completos ni recursión.

## 3. Defectos que corregir antes de publicar (cambio mínimo)

**H1 · El cáliper contradice su propia ayuda con el convertidor externo.** La
ayuda de `brake_actuation` dice: «Si lo mueve un convertidor externo, el cáliper
sigue siendo hidráulico y el convertidor se nombra aparte». Pero
`brake_conversion_location` y `brake_external_converter_model` sólo se admiten
con `Híbrido`, y bajo `Hidráulico` nombrar el convertidor bloquea
(`field_applicability`; caso de Root
`bkx_a_hydraulic_caliper_has_no_external_converter` y mi
`hydraulic_caliper_moved_by_external_converter_cannot_name_it`). La rama
«conversión en un dispositivo externo» describe un sistema (convertidor +
cáliperes hidráulicos corrientes), no la pieza: en esa venta el cáliper es
hidráulico y el convertidor es otro producto. Es herencia del catálogo de
freno completo. **Cambio mínimo:** en `brake_caliper`,
`allowed_options.brake_conversion_location = ["En esta pieza"]`, retirar el
campo `brake_external_converter_model` del cáliper (la definición deja de
usarse y el compilador deja de publicarla), reescribir la ayuda de
`brake_actuation` («…el convertidor se documenta en la presentación que lo
incluye, no en esta pieza») y quitar los casos
`bkx_hybrid_caliper_names_its_converter` y
`bkx_a_conversion_in_a_device_names_it`, conservando
`bkx_a_conversion_inside_names_no_external_device`.

**H2 · El cáliper de disco no es dueño de su montaje.** En vivo
`mount_standard` es obligatorio; el sucesor lo retira a legacy con
`allowed_when never` y no crea ningún campo raíz para la interfaz propia
(International Standard / Post Mount / Flat Mount). El único sitio donde decirlo
es la columna **opcional** `caliper_mount` de `rotor_size_recipe`, cuyas filas
son `required_when Disco` y exigen `frame_mount`, `rotor_diameter_mm`,
`adapter_required` y `source_url`. Reproducido: dos filas con `caliper_mount`
Post Mount y Flat Mount para el mismo cáliper validan limpias (mi caso
`caliper_contradictory_mount_rows_accepted`, SQL y Dart); un cáliper Flat Mount
sin tabla OEM de adaptadores queda pendiente por `rotor_size_recipe` y no
puede declarar su interfaz (`flat_mount_caliper_without_fitment_rows_is_pending`).
El montaje del cáliper es un extremo físico de la pieza, como lo es
`rotor_mount_type` para el rotor. **Cambio mínimo:** una definición nueva
`caliper_mount_interface` (single_select: International Standard, Post Mount,
Flat Mount, Desconocido / sin confirmar) como campo raíz `primary/intrinsic`
del cáliper, `allowed_when` y `required_when` `braking_surface = Disco`,
evidencia `oem_or_package`; quitar la columna `caliper_mount` de la receta (la
receta conserva `frame_mount`, adaptador y diámetro por posición). Recomiendo
además `rotor_size_recipe` `required_when never`: la tabla de adaptadores es
documentación OEM, no un intrínseco, y hoy deja pendiente a todo cáliper de
disco hasta encontrarla. Un caso nuevo: `Disco` sin `caliper_mount_interface`
queda `required_missing`.

**H3 · El recambio de cartucho debe declarar un espárrago que no tiene.**
`rim_pad_stud_type` es `required_when braking_surface = Llanta` para toda
zapata, y `rim_pad_construction` admite «Recambio de cartucho». Park Tool:
«All three of these systems come in either a one-piece, where the pad is fixed
to the stud, or a cartridge style, where the pad slides in and out», retenido
por «retention screw or clip». El inserto no tiene espárrago: la fijación es
del porta-goma, y `rim_pad_interface_model` ya la nombra. Reproducido: mi
caso `cartridge_insert_must_declare_a_stud_it_lacks` queda `required_missing`
y sólo se cierra mintiendo con «Desconocido». **Cambio mínimo:**
`required_when rim_pad_stud_type` = `braking_surface = Llanta` **y**
`rim_pad_construction in ["Una pieza", "Cartucho (porta-goma)"]` (la ausencia
de construcción deja pendiente, como corresponde), con `allowed_when` igual
que hoy; un caso nuevo con «Recambio de cartucho» sin espárrago y sin
pendiente.

**H4 · El cáliper de llanta no declara la fijación de zapata que admite
(recomendado en el mismo recompilado).** El cáliper de disco debe declarar
`pad_shape_code`; el de llanta no tiene campo para el espárrago roscado, poste
liso o perno que acepta. Una clave ajena en el borrador se ignora en silencio
(mi caso SQL `rim_caliper_pad_interface_key_is_foreign` valida sin incidencia)
y el escritor la rechazaría. **Cambio mínimo:** adjuntar la definición nueva
`rim_pad_stud_type`, ya en este paquete, al cáliper como campo
`measurement/compatibility` `allowed_when`/`required_when`
`braking_surface = Llanta` (mismo patrón que `pad_shape_code` en disco).

## 4. Límites y detalles que no bloquean

- **Superficies (decisión de Root, no del candidato).** Las 23 definiciones
  nuevas nacen `is_customer_visible = false`; los legacy retirados
  (`rotor_diameter_mm`, `mount_standard`, `piston_count`, `fluid_type`,
  `caliper_hydraulic`, `brake_type`, `rotor_thickness_mm`, `tool_size_mm`) son
  visibles al cliente y varios `is_compatibility_relevant`/filtrables. Al
  aplicar, la ficha pública de los 18 rotores pierde diámetro y espesor, y la
  de los 11 cáliperes pierde montaje, pistones, fluido y tipo; la adopción
  fresca no lo devuelve mientras los sucesores sigan invisibles. Consumidor
  concreto: `supplier_need_portal_search.dart` mapea `rotor_diameter_mm` y
  `rotor_mount_type` como criterios de búsqueda; el primero pasa a legacy en
  el rotor. Son pruebas de representación y búsqueda, no de montaje.
- `braking_surface` del cáliper no está restringida: «Maza (banda / tambor /
  rodillo)» se acepta sin que nada más aplique (mi caso). Conviene
  `allowed_options = [Disco, Llanta]` como en la pastilla.
- `brake_piece_hydraulic_ports.end_role = Salida` se acepta en un cáliper (mi
  caso); y el puerto de purga puede vivir a la vez en esa tabla («Purgador»)
  y en `brake_bleed_ports` sin unicidad cruzada. Elegir un solo hogar o
  restringir opciones por `row_conditions`.
- Prerrequisito `bleed_port → spec_evidence_source` sobre un legacy nunca
  admitido: inerte.
- `brake_external_hose_connection` obligatorio bajo `Hidráulico`: un cáliper
  puramente hidráulico siempre la tiene; la pregunta sólo discrimina al
  híbrido. Inofensivo.
- Nombre de caso desfasado:
  `bkx_a_rotor_without_its_material_leaves_the_restriction_pending` ya no
  pende (la restricción sólo exige fuente).
- No afirmo compatibilidad por marca ni por pruebas verdes; no juzgo montaje;
  la adopción fresca de los 82 productos y el guardado en perfiles y
  consumidores siguen siendo de Root; el llenado sigue en cero.

## 5. Fronteras propias (Dart 9 casos asertados = 12/12 con plantillas; SQL 11 en diagnóstico)

| Caso | Resultado |
|---|---|
| dos recetas con `caliper_mount` contradictorio | sin incidencia (H2) |
| cáliper Flat Mount sin receta | `required_missing rotor_size_recipe` (H2) |
| recambio de cartucho sin espárrago | `required_missing rim_pad_stud_type` (H3) |
| cáliper hidráulico nombrando convertidor externo | `field_applicability` (H1) |
| cáliper de llanta con `rim_pad_stud_type` | clave ignorada, sin incidencia (H4) |
| `braking_surface` Maza en cáliper | sin incidencia |
| puerto `Salida` en cáliper | sin incidencia |
| zapata con `pad_shape_code` | `field_applicability` bloqueante |
| híbrido interno sin manguera | pendiente sólo por aprobaciones de fluido |
| rotor límite sin nominal | sin incidencia |
| rotor diámetro `160/140` | `field_constraint` bloqueante |

## 6. Cierre

Propiedad de vuelta a Root. Recompilar con H1–H3 (y H4 si se acepta), nueva
preimagen y nuevo SHA; el resto del paquete no necesita cambios.
