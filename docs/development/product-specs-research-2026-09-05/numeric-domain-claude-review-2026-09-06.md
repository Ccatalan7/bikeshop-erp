# Dominios numéricos: revisión de la corrección transversal — Claude, 2026-09-06

Objeto: `supabase/migrations/20260906150000_product_spec_numeric_domains.sql`,
`numeric-domain-changes-2026-09-06.json` (35 entradas) y
`all-fields-semantic-review-2026-09-06.json` (136 definiciones, snapshot
`52d08319…1e0dd7`). Sólo lectura de archivos del repositorio; no corrí SQL en
local ni en producción; no vi la fixture que Codex prepara.

## 0. Veredicto

**Semántica correcta; no hay bloqueo de semántica.** Los 35 cambios coinciden
uno a uno con el grupo de revisión del JSON semántico (26 `positive_measurement`,
9 `positive_integer_count` menos los 3 de cadena ya corregidos, 1
`nonnegative_stack`, 1 `nonnegative_count`, 1 `signed_offset`), y los
contraejemplos son reales: Sheldon lista BCD 58 y 145 en su crib sheet (leído
hoy) y Park Tool nombra 132 mm entre los anchos PF41. Quitar un tope permite
registrar una observación y no aprueba ningún montaje: el validador sigue
bloqueando sólo por `constraint_rules`, referencias y `range_order`, que la
migración no toca.

Quedan **tres asuntos antes de desplegar**, uno de contrato de despliegue y dos
de versionado; ninguno cambia la migración en sí:

1. **Read-back ejecutable.** `scripts/db/deploy_migration.sh` exige al menos un
   `--verify` (línea 46). No lo vi entre los archivos; si no existe, es
   bloqueo del contrato de despliegue. §4 dice qué debe afirmar.
2. **Tres definiciones no existen en ninguna migración confirmada:**
   `rim_erd_mm`, `rim_external_width_mm`, `rim_internal_width_mm` no aparecen
   en `supabase/migrations/*.sql` con ninguna forma de cita. Codex reporta 12
   ausentes en local; al menos esas tres nacieron fuera del historial. La
   migración aplicará en producción (su guardia lee la base viva), pero no es
   reproducible ni probable en local sin fixture, y el vocabulario productivo
   no se puede reconstruir desde el repositorio. Bloquea las pruebas, no el
   despliegue; pide una migración de reproducibilidad después (§3).
3. **Doble versionado y estampa dentro del contrato** (§3): funciona, pero
   deja `numeric_domain_review` en `form_contract`, que es el contrato y no un
   diario. No bloqueante; recomiendo retirarla antes de aplicar.

## 1. Semántica, campo por campo

| Grupo | Claves | Regla nueva | Juicio |
|---|---|---|---|
| Medidas | 26 (`*_mm`, `*_in`, `sealant_volume_ml`) | `positive` | correcto: una medida es > 0 y finita; los límites de montaje viven en referencia o receta. Positividad nueva en 7 claves que no tenían regla (`hose_length_mm`, `rim_*`, `rotor_thickness_mm`, `sealant_volume_ml`, `spoke_length_mm`); la guardia demuestra que ningún hecho existente la viola |
| Cantidades | `bb_ball_count_per_side`, `largest/smallest_cog_teeth`, `single_cog_teeth`, `pulley_teeth`, `rear_derailleur_min/max_teeth` | `positive`,`integer` | correcto |
| Capacidad y stack | `rear_derailleur_total_capacity_teeth` (`min 0`,`integer`), `bb_spacer_stack_mm` (`min 0`) | cero admitido | correcto para el stack (ninguna arandela). Para la capacidad, 0 no describe ningún cambio real; lo acepto como «declarado 0» sin bloqueo, pero conviene decirlo en el registro |
| Offset | `chainring_offset_mm` → `{}` | signo libre | correcto; `rim_asymmetric_offset_mm` ya estaba en `{}` y debe figurar en el registro como «sin cambio, con signo» para que la revisión sea completa |
| Pares ordenados | `smallest ≤ largest`, `tube_width_min ≤ max` (mm y in), `bearing_inner ≤ outer` | sin cambio | siguen en el validador (`range_order`, líneas 101–108 de `20260906103000`) |

Lo que la migración no promete y no debe leerse como promesa: pasar un dominio
no dice nada de compatibilidad (`mechanical_family_approved=false` en las 136
definiciones; 129 `pending`, 7 fuera de alcance de producto).

## 2. Alcance a otros consumidores y `subject_type`

| Consumidor | Qué lee | Efecto de la migración |
|---|---|---|
| Validador de producto (`spec_validate_draft_internal_v1`) | `positive`, `integer`, `min`, `max` (líneas 64–71 de `20260906103000`) | aplica las reglas nuevas; `min` o `max` ausentes comparan con nulo y no bloquean |
| Hechos de bicicleta y visita (849, `subject_type` ≠ product) | mismas definiciones | la guardia de la migración los revisa (no filtra `subject_type`: correcto); en tiempo de ejecución nada los valida contra `validation_rules` (`spec_fact_value_shape_internal_v1` sólo comprueba forma), así que el taller no cambia de comportamiento |
| Registro de diagnóstico (`20260821200000`, línea 47) | expone `validation_rules` | ningún Dart del taller las lee (grep sin resultados fuera de inventario y compras): sin efecto |
| Lecturas con cita | digest y rechazo | el digest hashea rótulo, tipo, descripción y opciones, no reglas; el rechazo no usa `min`/`max`: las 14 lecturas quedan intactas |
| Formulario y contrato Dart | `min`, `max`, `positive`, `integer` (`product_form_page` 1675–1690; `product_spec_contract` 185–195) | paridad completa con el servidor |
| Editor de refinamiento de compras (`supply_need_refinement_editor` 1135–1150) | sólo `min`/`max`/`minimum`/`maximum` | al desaparecer los topes deja de acotar y **nunca supo** `positive`/`integer`: un predicado «dientes = -3» pasa el editor. No bloquea esta migración; es un seguimiento del vocabulario compartido |
| `option_rules` de pedalier (`20260820220000`, línea 237) | anchos pressfit `[86.5, 89.5, 92, 107, 121]` | son sugerencias, no bloqueos (prueba «legacy suggested options are not promoted»); pero la lista sigue sin 132 mm PF41: el formulario no lo ofrecerá aunque el validador lo acepte. Seguimiento con fuente Park |

## 3. Versionado

- **Guardia de línea base**: `validation_rules = old_rules` en jsonb es
  insensible al orden de claves y a `0.5`/`0.50`; un nulo produce
  desigualdad y cae en «baseline drifted». Correcto y a prueba de repetición:
  la migración no es idempotente por diseño, y el sello de versión del
  despliegue impide re-ejecutarla.
- **Doble bump**: el `update spec_definitions` dispara
  `product_spec_definition_revision` (`+1` por definición y plantilla), y el
  `update spec_templates` posterior dispara `product_spec_template_revision`,
  que respeta el `+1` manual porque `form_contract` cambia. Una plantilla con
  siete definiciones tocadas sube ocho versiones. Inofensivo para la guardia
  de editores abiertos, pero el `+1` manual es redundante.
- **Estampa `numeric_domain_review` en `form_contract`**: los lectores Dart
  sólo leen `prerequisites`, `roles`, `helpers` y `labels`; el SQL lee `roles`,
  `prerequisites` y `labels`; el read-back de la base afirma
  `form_contract->>'version'='1'`, que se conserva. Nada se rompe. Aun así, el
  contrato no es el lugar de un diario: la trazabilidad la dan el recibo de
  despliegue, el SHA del JSON de cambios y el comentario de la migración.
  Recomiendo quitarla y dejar el bump al trigger.
- **Reproducibilidad**: tres claves sin origen en migraciones (arriba) y doce
  ausentes en local según Codex. La fixture mínima debe crear esas
  definiciones con `old_rules` exactas y sus campos de plantilla, para que
  las pruebas ejerciten la guardia y el bump. Después hace falta una
  migración que siembre en local lo que producción ya tiene, o un registro
  explícito de la divergencia; si no, cada corrección transversal repetirá
  esta fixture.
- **Trazabilidad del registro**: `numeric-domain-changes-2026-09-06.json` no
  lleva evidencia por clave ni el SHA del JSON semántico del que sale. Basta
  añadir `evidence` a las dos claves con contraejemplo (`chainring_bcd_mm` con
  Sheldon 58/145/146; `bb_shell_width_mm` con Park PF41 132 mm) y «sin
  evidencia de tope universal» al resto, más `rim_asymmetric_offset_mm` y las tres de cadena como «sin cambio».

## 4. Read-back mínimo para `--verify`

Sin `begin`/`end` y con `select 1/(…)`, como los read-backs existentes:

1. Las 35 definiciones globales tienen exactamente `new_rules` (comparación
   jsonb contra la misma tabla temporal de la migración).
2. Ningún hecho, de cualquier `subject_type`, viola `positive`, `integer` ni
   `min` de las reglas nuevas (misma consulta que la guardia).
3. Ninguna de las 35 conserva `max`.
4. Las plantillas que usan esas definiciones subieron de versión respecto de
   la línea base `.tmp/db/spec-numeric-before.json` (si el read-back puede
   recibir la línea base) o, al menos, `contract_version` de `chain` y
   `chain_link` sigue en 6 y 24: no están afectadas.
5. `md5(prosrc)` del validador igual al que afirma
   `chain-connector-readback.sql`: esta migración no toca funciones.

## 5. Pruebas locales que cierran la revisión

pgTAP, con la fixture de las definiciones ausentes: la guardia falla ante
deriva; la guardia falla ante un hecho de bicicleta con `spoke_length_mm`
negativo (demuestra el alcance a todos los sujetos); tras aplicar, el
validador acepta BCD 58 y 145, ancho de caja 132, stack 0, offset −4, y
rechaza 0 en medidas, 14.5 dientes y −1 en capacidad. Dart: los mismos casos en
`product_spec_contract_test.dart` con una fixture exportada de producción como
la de cadenas, porque los tests actuales de esos campos
(`spec_cascade_bottom_bracket_test.dart`, `spec_option_rules_test.dart`)
prueban visibilidad y opciones, no dominios.
