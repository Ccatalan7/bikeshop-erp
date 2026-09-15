# Revisión final · sucesor de `brake_lever` (2026-09-15, ronda 229)

Revisión acotada del candidato implementado por Root sobre la propuesta 228 y
su adjudicación (`brake-lever-adjudication-2026-09-15.md`, `fd134b7c…`). Sólo
lectura y reejecuciones locales en rollback sobre los archivos actuales; sin
producción, código, git ni publicación. No toca el trabajo paralelo de orden
escalar ni casquillo de tija.

| Artefacto | Hash |
|---|---|
| `.tmp/db/brake-lever-2026-09-15-candidate.sql` | SHA-256 `ded86efb78dbdbdf5a4b470af9f4adb18f6c809d4fbb455142ffb86bc6ea7ce1` |
| `brake-lever-2026-09-15-catalog.json` / `-cases.json` / `-packet.json` | `c2df108e…` / `17f14369…` / `f5482d0b…` |
| `compile_brake_lever_successor.py` / `test_brake_lever_profiles.py` | `76320804…` / `df1252e1…` |
| Preimagen v2 (04:54:31Z; 18 manetas por binding efectivo, 3 explícitas) | `4f3f19a2…` = la que declara el paquete |
| Mis sondas `.tmp/product-spec-catalog/brake-lever-review-20260915/{probe.py, review-cases-dart.json}` | `5acd757a…` / `231491ea…` |

## 1. Dictamen

**Aprobado el SHA exacto `ded86efb…`**, con una condición de evidencia (F1) y
los límites del §4. No encontré defecto de propiedad, requisitos ni cruces. El
delta corrige los seis puntos de mi 228 §3 y añade las cinco ramas de Codex
(topología hidráulica en línea, abrazadera frente a expansor, cabeza anclada
frente a cable pasante, posiciones del tiro ajustable, alojamiento frente a
cable sin cortar), todas coherentes con las fuentes que pude leer.

## 2. Delta verificado

- **Seis campos vivos conservados con sus ids.** `brake_type`,
  `caliper_hydraulic` y `brake_system` a legacy `allowed_when never`;
  `reach_adjust` intrínseco; `brake_position` pasa a declaración con
  `required_when never`; `spec_evidence_source`. `fluid_type` y
  `hose_system_code` no se crean; `kit_members`, `integrated_shifter`,
  `brake_external_hose_connection`, `brake_conversion_location` y
  `brake_external_converter_model` del prototipo desaparecen.
- **Doce definiciones reutilizadas byte a byte iguales a la preimagen v2**,
  incluidas las tres que la 227 publicó (`brake_model_fluid_approvals`,
  `brake_piece_hydraulic_ports`, `brake_bleed_ports`). Trece nuevas, 21
  opciones, 25 campos; revisión 2 → 28 = 2 + 1 (contrato) + 6 actualizaciones +
  19 altas, confirmada por el replay exacto. Escalares nuevos visibles y
  filtrables; las tablas de filas no. Mismo framing del publicador que el
  candidato de pinza, pastilla y rotor (diff vacío salvo el SHA de origen).
- **Propiedad e interfaces.** Accionamiento restringido a cable/hidráulico;
  tiro entregado sólo mecánico; interfaz de cable (anclada, pasante, ambos)
  sólo mecánico, con perfiles de cabeza sólo para anclada o ambos y posiciones
  sólo para «Ajustable»; fijación al manubrio con tres ramas excluyentes
  (diámetro exterior sólo con abrazadera, rango interior ordenado sólo con
  expansor, interfaz OEM sólo con montaje específico, espacio recto sólo con
  abrazadera); función hidráulica obligatoria cuando es hidráulica, salidas
  sólo para la principal, conexiones hacia mando y pinza sólo para la
  auxiliar, purga sólo «Maneta», fluidos admitidos por modelo (no cargados);
  anclaje para mando separado con código sólo para «Otro sistema OEM». Lado y
  rueda sin regla que los cruce.

## 3. Reejecutado sobre los archivos actuales

| Prueba | Resultado |
|---|---|
| 38 casos de Root por `prepare` + verificador real (forward y replay) | `exact_metadata` 1/1 ×3, huella de hechos/productos 1/1 ×2, `38 · 1`, rollback |
| Arnés Dart, catálogo + 38 casos | 39/39 |
| Mis 8 fronteras (SQL diagnóstico y Dart 9/9) | mecánica con función hidráulica → `field_applicability`; hidráulica con interfaz de cable → `field_applicability`; montaje específico sin interfaz → pendiente; montaje específico con diámetro de abrazadera → `field_applicability`; expansor con espacio recto → `field_applicability`; auxiliar en línea completa (dos conexiones, purga Maneta, fluidos) → sin incidencia; dos conexiones con el mismo `port_id` → `field_constraint`; accionamiento «Desconocido» con tiro → pendiente por accionamiento y aplicabilidad no bloqueante |
| `test_brake_lever_profiles.py` (Root, rol autenticado, rollback, 22:02:40 tras regenerar) | 13 ok |
| Adopción final (22:03:28) | 18 evaluados, 0 bloqueos, 0 observaciones, 3 pendientes por producto (`brake_actuation`, `lever_side`, `lever_mount_method`) |

Fuentes verificadas por mí: Park Tool «In-line brake levers» («The in-line
lever pushes on the housing, effectively making it longer»; secciones de
manillar de ruta ≈ 23,4 mm frente a 25,4 / 26,0 / 26,4 / 31,8 mm), que sostiene
`lever_cable_interface = Cable pasante` y un `handlebar_clamp_mm` sin
restringir; Paul Cross Lever (uso pasante o «on its own» con la cabeza de cable
en el rebaje; pivote interior para tiro corto y exterior para tiro largo;
abrazaderas 26,0 y 31,8), que sostiene «Ambos usos» y
`lever_cable_pull_positions`; Shimano C-421 distingue «I-SPEC EV type» e
«I-SPEC II type». El PDF de Paul Reverse Levers y DM-GADBR01-06 no son
legibles por mi herramienta: acepto las citas de Codex sin verificarlas.

## 4. Hallazgos y límites

**F1 · Evidencia SQL desfasada (condición antes de publicar).** Los tres
ensayos guardados (`sql-tests`, `-v2`, `-v3`) embeben catálogos anteriores
(`420816a6…`, `c0f06d7f…`, `40d2c43a…`), ninguno el actual `c2df108e…`, y sus
`forward-replay-and-cases.log` terminan en `division by zero`; `dart-v3.log`
(21:59:37) es anterior a la regeneración de las 22:02:32. La adjudicación
afirma 38 casos SQL con publicación y repetición exacta, pero ese log no
existe en la carpeta. Mi corrida sobre el paquete actual lo pasa; Root debe
dejar un `sql-tests-v4` y un `dart-v4` sobre el SHA que publica.

**F2 · «Desconocido / sin confirmar» es desconocido para el motor.** Con ese
token en `brake_actuation` el validador emite `required_missing
brake_actuation` y deja como no bloqueante la aplicabilidad de `lever_cable_pull`.
Es la convención del motor (ausencia = unknown), no un defecto; la interfaz
debe mostrarlo como pendiente, no como respondido.

**F3 · Detalles no bloqueantes.** `brake_position` lleva rol `declaration` y
semántica `compatibility`; `lever_mount_oem_interface` y
`lever_control_mount_oem_code` son texto libre marcados filtrables (un filtro
de texto no es criterio útil); `lever_cable_head_profiles` exige `oem_spec`
incluso para «Barril» o «Pera»; `shifter_mount_interface` no lista I-SPEC B ni
A (cabe en «Otro sistema OEM» con código). Ninguno exige recompilar.

**Límites.** `lever_cable_pull` y `handlebar_clamp_mm` siguen invisibles y no
filtrables por ser definiciones ya publicadas (decisión pendiente, como dice
la adjudicación). La cohorte trae pares y juegos: la plantilla heredada no
prueba pieza única y el saneamiento de presentaciones sigue abierto antes de
cualquier llenado. Todo es representación y conservación; no certifica
circuito, montaje ni compatibilidad OEM; llenado en cero.

## 5. Cierre

Aprobado `ded86efb…` con F1 como condición de evidencia. Propiedad de vuelta a
Root para reconciliar, publicar y hacer los recorridos reales de manetas.
