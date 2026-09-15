# Revisión final acotada · cierre R1/R5 del editor de piezas — 2026-09-14

Ronda 212. Sólo lectura del delta; sin SQL ejecutado, sin runtime. Leídos:
migración `20260914225500_product_spec_member_issue_details.sql` `93b9f3c3…`
(coincide con el SHA congelado), verify `1f4dfa7e…`, candidato
`product_spec_member_issue_details_candidate.sql` `08b66737…`, predecesor JSON
`a6ff1b52…`, pgTAP `supabase/tests/product_spec_member_issue_details.sql`,
`models/product_spec_contract.dart` `39f40fab…`, `pages/product_form_page.dart`
`7c7e9671…` (ambos iguales a los declarados).

**Ejecutado:** `test/unit/product_spec_member_issue_message_test.dart` +
`test/unit/product_spec_reference_scope_test.dart` → **12 PASS**.

## Veredicto: sin bloqueo. R1 cerrado; R5 cerrado por código, pendiente sólo la prueba de runtime que Root está haciendo.

## R1 — detalle estructurado de issues de miembros

- Delta SQL exacto: una sola línea. `raise exception 'Ficha de componente
  contradictoria: %', issues` → `raise exception 'Revisa la ficha de la pieza
  incluida' using errcode='23514', detail=issues::text`. md5 del predecesor
  recalculado aquí `e20342ed…` = registrado; md5 del candidato empaquetado
  `51736f72…` = postimagen y verify. El candidato va embebido byte a byte en
  la migración; guard y postimagen exigen `postgres`, **no** definer, `STABLE`,
  `search_path` fijo y ACL `postgres`/`service_role`; el reintento es
  idempotente (guard acepta ambas imágenes). Sin lock ni huella de datos: no
  toca tablas, correcto para un cambio de cuerpo.
- `issues` ya trae `profile_id`, `collection_definition_id`, `member_row_id`
  junto al `code/field/message/blocking` del validador
  (`20260914213000:479-481`), así que el `detail` identifica pieza y campo. La
  pgTAP reproduce primero el texto crudo del predecesor, luego afirma mensaje
  humano, `profile_id`+`field` exactos y que la observación original queda
  intacta tras fallar.
- Cliente: `productSpecServerIssues` lee `profile_id` → `memberProfileId`;
  `productSpecIssueMessage` resuelve plantilla y valores de **esa** pieza vía
  `memberContext`, prefija su rótulo, cae a «Pieza incluida: …» si la pieza no
  se conoce (nunca a etiquetas raíz) y no duplica la etiqueta cuando el
  servidor ya la trae (contract :121-147). El formulario conecta el UUID del
  borrador activo (`_specIssueMemberContext`, form :5449-5462) al snackbar de
  guardado (:5429). Un issue sin `field` string se descarta y queda el
  mensaje humano del servidor: aceptable.
- Nota menor de palabras, no bloqueante: el snackbar numera «Pieza N» por
  orden de la lista de borradores activos, mientras el editor ubica la misma
  pieza como «configuración N» dentro de su colección. Dos numeraciones para el
  mismo objeto; bastaría reutilizar la ubicación del editor en el rótulo.

## R5 — cambio a Servicio y vuelta

- `_cacheCurrentSpecDraft` (form :1277-1292) guarda valores, claves manuales,
  autoderivados y referencia bajo `productId:templateId` sólo si no hay error
  ni carga en curso. `_handleProductTypeChanged` lo llama **antes** de vaciar
  (:3916), luego `_specLoadEpoch++` cancela cualquier carga en vuelo y apaga
  `_isLoadingSpecs` (:3920-3921), y anula `_loadedSpecDraftKey` (:3924).
- Vuelta: `wasService && value != service` relanza `_loadSpecTemplate`
  (:3965-3966). Su primera acción es `_cacheCurrentSpecDraft` (:1296), que con
  `_loadedSpecDraftKey` y `_specTemplate` nulos no hace nada → el borrador
  cacheado no se pisa con `{}`; luego `draft = _specDrafts[draftKey]` (:1339)
  lo restaura como valores base. Causal y correcto.
- Stale/guardado: con borrador restaurado, `_specRevision` no se refresca
  (:1382) — es la regla existente: si hay borradores de miembros y la revisión
  del servidor difiere, la carga lanza «El producto cambió en otra edición» y
  bloquea; si no los hay, la revisión vieja viaja en `p_expected_revision` y el
  servidor rechaza. Ningún camino sobrescribe en silencio. Los borradores de
  miembros se conservan a través del cambio (no se anulan en la rama servicio)
  y quedan inertes mientras el formulario es de servicio (esa ruta no envía
  `_specSaveCommand`); al volver, `??=` los mantiene y la comprobación de
  revisión los protege.
- Cambio a Servicio con carga en vuelo: no se cachea el estado intermedio
  (guard `!_isLoadingSpecs`); el estado anterior ya había sido cacheado por la
  propia carga al arrancar, y la carga cancelada no escribe (epoch). Correcto.
- Sin prueba Dart del cambio/vuelta; queda la prueba de runtime de Root, que
  no sustituyo. No es bloqueo.

## Qué no toqué

Ningún archivo congelado, SQL, test ni fixture. Sólo este documento.
