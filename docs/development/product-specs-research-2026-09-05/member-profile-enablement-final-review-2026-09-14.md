# Revisión final acotada · paquete de habilitación `member_profiles` (9 familias) — 2026-09-14

Ronda 215. Sólo lectura; sin SQL ejecutado, sin runtime, sin código. Leídos:
`scripts/inventory/compile_member_profile_enablement.py` `e2b6e7d0…`, las dos
líneas `helper_text`/`default_value_json` de `metadata_records` en
`compile_non_drivetrain_publication.py` `68fddcde…` (:158-159, con la tupla
:41), el paquete `member-profile-enablement-2026-09-14-packet.json`
`a91972be…` (9 parches), el candidato y verificador generados en `.tmp/db/`,
la evidencia local `.tmp/db/member-enablement-local-20260914/forward-replay-and-cases.log`
y `.tmp/product-spec-catalog/member-enablement-dart-20260914.log`. No revisé D2
ni el catálogo completo.

## Veredicto: **aprobado para este delta de metadata**, sin bloqueantes.

No afirmo compatibilidad, fill ni distribución; el paquete tampoco
(`product_writes`, `fill_allowed`, `mechanical_approval` = false).

## Evidencia

- **Sólo `member_profiles`.** Diff propio de los 9 parches (`before`→`after`):
  cambian únicamente `form_contract.member_profiles` (versión 1, colección
  `kit_members`, `family_column = family`, identidad `[member_role, position,
  identity_brand, identity_model]`), `contract_version` +1 exacto por
  plantilla (fender 9→10, handlebar_covering 11→12, headset_small_part 11→12,
  light 17→18, lock 16→17, rider_protection 10→11, training_wheel 6→7,
  tube_repair 9→10, tubeless_repair 8→9) y `updated_at` (nulo en `after`, sin
  uso en el SQL). Ningún parche previo tenía `member_profiles`.
- **Campos, definiciones y reglas preservados.** `records.spec_definitions` y
  `spec_definition_values` vacíos; `records.spec_template_fields` (88) idéntico
  a `before` en todas las columnas que el forward compara (sólo falta
  `updated_at`, excluida por diseño de `TABLES`); `records.spec_templates`
  difiere de `before` sólo en `member_profiles`. Las restricciones de
  `row_conditions` de `light` viajan intactas. El compilador falla cerrado si
  aparece cualquier registro de definición/opción o un parche que no sea de
  `spec_templates` (:101-104), si `kit_members` no es `contents` (:42-43), si
  ya existe otro contrato (:44-45) o si el preimage no es exactamente las nueve
  (:34-35, :48-49).
- **Las dos líneas del compilador compartido** hacen que los registros de
  campo lleven `helper_text` y `default_value_json` del preimage; por eso el
  paquete no genera parches de campo (0 `UPDATE`/`INSERT` sobre
  `spec_template_fields` en el candidato, verificado por el bucle de nuevos
  ids que no encuentra ninguno).
- **Una subida por revisión.** El candidato sólo hace `update spec_templates
  set form_contract = after` por parche; la versión la sube el trigger
  `spec_contract_revision_internal_v1` (20260906070000:889-895) **sólo** cuando
  `(form_contract, is_active, technical_family)` cambia. Por eso el replay del
  log local (dos bloques de forward, ambos `exact_metadata = 1`) no puede
  subirla dos veces.
- **Cadena de hashes.** `preimage_sha256`, `catalog_sha256` y `cases_sha256`
  del paquete coinciden con los archivos (`7495d389…`, `074e2f2e…`,
  `e3216c00…`); el documento embebido en el candidato es igual al paquete.
- **Guardas del forward.** Validador productivo fijado por md5
  (`spec_validate_draft_internal_v1` `ac0738d5…`), colisión de claves,
  deriva de definiciones compartidas (64 reutilizadas, opciones incluidas),
  deriva de preimage, `lock table`, `repeatable read`, `set constraints all
  immediate` (dispara `spec_member_template_metadata_constraint`, que valida
  el contrato de colecciones: pasó en local), huella de hechos/productos/
  referencias/mapeos antes y después = 1.
- **Casos.** 18 (9 familias × `accessory_mount`/`light`): `light/light`
  bloquea por `row_option`, el resto sin bloqueo; `deployed_behavior_matches =
  1`. Dart 29 PASS.
- **Verificador RED en producción antes de aplicar** es lo esperado: compara
  el post-estado (`member_profiles` presente).

## Observaciones no bloqueantes

- El forward no afirma `contract_version = before + 1`; la garantía es del
  trigger. Un chequeo de una línea en el verificador (comparar contra
  `patches[].after.contract_version`) lo dejaría explícito. No bloquea.
- Con `helper_text`/`default_value_json` siempre presentes en los registros,
  un catálogo futuro que no traiga esas claves las compararía como `null`
  contra un campo vivo con texto y generaría un parche de campo. Para este
  paquete no aplica (vienen del preimage); vale para las publicaciones de
  sucesores que usen el mismo compilador.
- En `light`, la colección sigue anunciando `light` entre sus
  `familyOptions` (definición global) aunque el contrato lo bloquee por fila:
  el editor dejaría crear la ficha de una fila `family = light` y el guardado
  la rechazaría con `row_option`. Sin riesgo de datos; es un callejón de UI
  que sólo aparece si el operador ignora el bloqueo de la fila.
- `updated_at: null` en `patches[].after` es cosmético.

## Qué no toqué

Ningún archivo congelado, SQL, test ni catálogo. Sólo este documento.
