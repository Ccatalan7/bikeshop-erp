# Revisión final del delta · sucesores de cáliper, pastilla y rotor (2026-09-15, ronda 227)

Delta contra la versión revisada en 225 (`reviewed-v1/`), sin repetir la
investigación. Sólo lectura, más reejecuciones locales en rollback sobre los
archivos actuales; sin producción, sin código, sin archivos de Root.

| Artefacto actual | Hash |
|---|---|
| `.tmp/db/brake-pieces-2026-09-15-candidate.sql` | SHA-256 `440d1cbbe0c0418d54fde6493d7e189a9db422a30ddac1c3ae975c5e04e37f3a` |
| `brake-pieces-2026-09-15-catalog.json` / `-cases.json` / `-packet.json` | `b7522376…` / `96e125c6…` / `c7236df4…` |
| `scripts/inventory/compile_brake_piece_successors.py` / `test_brake_piece_profiles.py` | `f40cc80e…` / `4905e51f…` |
| Preimagen v2 (04:09:04Z; 11 + 53 + 18 por binding efectivo) | `83fff344…` = la que el paquete declara |

## 1. Dictamen

**Aprobado el SHA exacto `440d1cbb…`** con el alcance del §4. El delta es
exactamente H1–H4 de la ronda 225 más los flags de superficie de la 226; no
encontré defecto bloqueante. Todo lo demás de 225 sigue válido sin cambios.

## 2. Delta verificado (diff programático v1 → actual)

- **Cáliper (26 → 27 campos, revisión 2 → 30):** sale
  `brake_external_converter_model` (campo, contrato y definición, que deja de
  publicarse); entran `caliper_mount_interface` (definición nueva,
  single_select IS/PM/FM/Desconocido, `primary/intrinsic`, obligatoria en
  Disco) y `rim_pad_stud_type` reutilizada como «Fijación de zapata admitida
  por esta pinza» (`measurement/compatibility`, obligatoria en Llanta).
  `rotor_size_recipe` pasa a `required_when never` y sus columnas
  `caliper_mount` y `caliper_model` quedan vetadas sólo en este dueño
  (`row_conditions.allowed_when never`); la definición compartida no cambia.
  `allowed_options`: `braking_surface = [Disco, Llanta]`,
  `brake_conversion_location = ["En esta pieza"]`. Puertos:
  `brake_piece_hydraulic_ports.end_role = [Entrada]`, purgadores sólo en
  `brake_bleed_ports`. Ayudas reescritas coherentes con la pieza; el
  prerrequisito inerte `bleed_port → spec_evidence_source` retirado.
- **Pastilla (20 campos, revisión 23):** `rim_pad_construction` obligatoria
  en Llanta; `rim_pad_stud_type` permitida y obligatoria sólo con construcción
  «Una pieza» o «Cartucho (porta-goma)»; ayudas nuevas.
- **Rotor:** sin cambios (13 campos, revisión 17).
- **Definiciones:** 25 reutilizadas byte a byte iguales a la preimagen v2; 23
  nuevas; 31 opciones (27 + 4 de `caliper_mount_interface`). Once escalares
  nuevos con `is_customer_visible` e `is_filterable` verdaderos (lista
  `SURFACE_FIELDS`); ninguna definición ya publicada cambia, así que
  `brake_actuation` sigue invisible y no filtrable (decisión aparte, no
  bloquea).
- **Publicador:** mismo framing que v1 salvo el SHA de origen; guardia del
  validador y colisión de claves iguales.
- **Casos:** 46 → 58. Retirados los seis que dependían del convertidor
  externo o del puerto duplicado; añadidos los de montaje raíz, veto de
  columnas, superficie, ubicación de conversión, puertos y zapata. El caso de
  dos puertos pasa ahora con entrada en `brake_piece_hydraulic_ports` y purga
  en `brake_bleed_ports`.

## 3. Reejecutado sobre los archivos actuales

Los logs de Root (`dart-v2-final` 21:10, `sql-tests-v2-verified` 21:12,
`adoption-v2` 21:11) son anteriores a la regeneración de los artefactos
(21:18:34), pero el contenido es el mismo: el SQL verificado embebe el catálogo
`b7522376…` y sus 58 expectativas coinciden con `cases.json` actual. Aun así
volví a correr sobre los archivos actuales:

| Prueba | Resultado |
|---|---|
| Arnés Dart, catálogo + 58 casos de Root | 61/61 |
| Casos de Root por `prepare` + verificador real (forward, replay exacto) | `exact_metadata` 1/1 ×3, huella de hechos/productos 1/1 ×2, 58 · 1 |
| `supplier_need_portal_search_test` + `bike_product_compatibility_service_test` | 106/106 (incluye `180/160`, `180 mm`, `180.5` y `180.5` numérico → sin diámetro; sólo `rotor_diameter_mm_value` entero) |
| Mi sonda v2 (9 casos Dart, 12 SQL) | 12/12 Dart; SQL: recetas con `caliper_mount` → `row_field_applicability` por fila; pinza Flat Mount sin receta → pendiente sólo `caliper_mount_interface`; recambio de cartucho sin espárrago → sin incidencia; `Maza` y «En un dispositivo externo» → `field_constraint`; puerto `Salida` → `row_option`; clave del convertidor retirado → ignorada como ajena; pinza de llanta con fijación admitida → sin incidencia |
| `test_brake_piece_profiles.py` (Root, rol `authenticated`, rollback) | 20 ok, 0 fallos: tres perfiles reales separados, montaje en la pinza, diámetro en el rotor, inserto sin espárrago, rechazo de cruce de plantilla, del convertidor retirado y de medida raíz; búsqueda por predicado y salida pública |

Adopción v2: 82 evaluados, 0 bloqueos, 17 legacy conservados (10
`rotor_diameter_mm` y 3 `rotor_thickness_mm` de `import`, 4 `brake_system` de
`name_reading`, todos sin confirmar), 0 activos sin proyectar. Criterios
guardados: 49 revisiones, 0 con claves retiradas de freno.

## 4. Alcance y límites

- Pruebas de representación y conservación; no aprobación mecánica ni
  llenado (sigue en cero). El guardado de perfiles probado es local y en
  rollback, no un guardado productivo.
- Retirar de la web no borra historia: los 17 hechos siguen en `spec_facts` y
  en el editor; la web y el matcher dejan de mostrarlos (ronda 226).
- `brake_actuation` invisible y no filtrable hasta una decisión propia.
- `brake_conversion_location` sigue obligatoria en híbrido con una sola
  opción: pregunta redundante, no defecto.
- Lecturas anónimas reales y comprobación de interfaz antes/después quedan a
  Root, como anunció.
- La preimagen v2 es posterior a las aplicaciones de la madrugada; el
  publicador vuelve a exigirla exacta al aplicar y falla cerrado si algo
  cambió.

## 5. Cierre

Propiedad de vuelta a Root. Nada pendiente de mi lado para este paquete.
