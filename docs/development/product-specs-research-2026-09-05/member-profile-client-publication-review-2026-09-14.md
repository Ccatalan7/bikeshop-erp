# Revisión independiente: integración cliente y compuerta de publicación de perfiles de componentes

14 de septiembre de 2026. Sólo lectura de código y pruebas Dart focales; sin SQL
local ni productivo, sin runtime ni UI. El formulario sigue en v1/v2 y no se
considera integrado. F2 sigue abierto.

## Veredicto

- **C1 (medio).** Cambiar la categoría de un producto con perfiles activos deja
  la ficha ilegible en el cliente: la lectura v3 del borrador no se decodifica
  y no hay camino para archivar. Bloquea la edición normal en cuanto se activen
  familias con perfiles. Abajo va el contrato que necesita el borrador.
- **C2 (medio).** Tras un guardado exitoso, los borradores de componentes
  siguen creyéndose no persistidos: la siguiente identificación pierde su
  `binding_action` y un archivo posterior se descarta en silencio. Bloquea la
  edición normal dentro de una misma sesión del formulario.
- **C3 (bajo).** Una referencia de la misma familia técnica con un hecho fuera
  de la plantilla del componente pasa la validación del cliente y la rechaza el
  servidor. No bloquea publicar.
- Compuerta de publicación: sin hallazgo bloqueante; una fragilidad menor.
- Sin hallazgo en: versión/revisión, comando completo, rebind/identify/archive
  frente al servidor, procedencia al reabrir y al quitar referencia, atomicidad
  del guardado, compatibilidad del cliente v1.

## Verificación ejecutada

- `flutter test` sobre `test/unit/product_spec_member_profile_test.dart` y
  `test/unit/product_spec_member_draft_test.dart`: **49 PASS**. Analyzer sin
  avisos en los dos modelos y los dos tests. Corridos contra los hashes finales
  de abajo.
- Sondas propias en `.tmp/product-spec-catalog/member_client_review_probe_test.dart`
  y `…probe2_test.dart` (7 casos, PASS): P1, P1b, P2, P3, P4, P5. Usan sólo la
  fixture sintética. No están en el repo.
- Todo lo del servidor y del formulario es por lectura.

## C1 — Cambio de categoría con perfiles activos: la lectura falla cerrada y no hay salida

**Flujo reconstruido con el código.**

1. `_showCategorySearchDialog` cambia `_selectedCategoryId` y llama
   `_loadSpecTemplate(categoryNueva, productId)`
   ([product_form_page.dart:748-752](../../../lib/modules/inventory/pages/product_form_page.dart:748)).
2. `_loadSpecTemplate` guarda el borrador raíz actual bajo la llave
   `producto:plantillaVieja` (:1268-1283) y pide el contexto con la categoría
   nueva. El servidor resuelve la ficha raíz por la **categoría del borrador**
   salvo que el producto tenga `spec_template_id` explícito
   (`get_product_spec_editor_context_v1`, `20260906160000_product_spec_template_binding.sql:234`);
   `values` trae sólo los hechos que caben en la plantilla nueva y el resto va a
   `unassigned_facts`. La revisión es la persistida.
3. Con v3 (`getProductMemberEditorContext`,
   [spec_engine_service.dart:363-382](../../../lib/modules/inventory/services/spec_engine_service.dart:363))
   el bloque `member_profiles` trae los perfiles **persistidos**, atados a la
   colección de la plantilla vieja. `decodeProductSpecMemberProfiles` toma las
   colecciones de la raíz del **borrador** (:240-242) y las filas de sus
   `values` (:276). Si la plantilla nueva no declara esa colección, lanza
   `la colección no está declarada en la ficha raíz` (:317).
4. `_loadSpecTemplate` atrapa la excepción como `_specLoadError` (:1379-1383):
   la pestaña de ficha muestra «No se pudo cargar la ficha» y sólo ofrece
   reintentar (:7622-7632). No hay forma de archivar los perfiles.
5. Si la lectura no fallara, `ProductSpecMemberDrafts(source)` se construye de
   nuevo desde la lectura y no existe stash de borradores de componentes: los
   cambios no guardados de los miembros se pierden al cambiar la categoría,
   mientras el borrador raíz sí se conserva por llave.
6. Al guardar, el servidor exige que los perfiles activos sigan vinculados con
   la plantilla nueva: sin colección declarada, `La ficha no admite perfiles en
   esta colección` ([core.sql:180](../../../scripts/inventory/sql/product_spec_member_profiles_core.sql:180));
   con colección pero sin fila, `Falta la fila del componente` (:185); ambos
   desde `spec_validate_product_member_profiles_internal_v1` (:223-237). La
   única salida es `archive_ids` en el mismo comando v2. Es la regla correcta:
   nada se archiva solo.

**Repro (P1, ejecutado).** Fixture `active`; a la raíz se le quita
`form_contract.member_profiles` y se cambia `template_id`/`template_key`
(simula la lectura v3 con categoría de borrador): `decodeProductSpecMemberProfiles`
lanza `no está declarada`. **P1b:** con la lectura persistida y una plantilla
padre sin la declaración, `buildCommand` lanza «La ficha del producto cambió:
archiva las fichas incluidas anteriores.»
([product_spec_member_draft.dart:313](../../../lib/modules/inventory/models/product_spec_member_draft.dart:313));
tras `archive` explícito de los dos perfiles produce
`{upserts: [], archive_ids: [081, 082]}`. Es decir, el borrador ya sabe exigir
el archivo; lo que falta es poder llegar a él.

**Cuando sí funciona hoy.** Si la plantilla nueva declara la **misma
definición** de colección con la misma `family_column`, la lectura decodifica
(las filas viajan en `values` porque la definición es la misma) y el guardado
pasa. Con `spec_template_id` explícito la categoría no cambia la raíz y los
miembros no se ven afectados.

**Contrato que necesita el borrador.** Propuesta, no decisión:

1. El bloque `member_profiles` debe poder decodificarse **sin la raíz del
   borrador**: cada perfil trae su contrato de colección persistido
   (`field`, `family_column`, `identity_columns`) y la fila persistida
   (`member_row` con `values` y `sources`), que el servidor ya lee en
   `spec_member_binding_internal_v1`. El decoder verifica identidad contra esa
   fila y calcula aparte `boundInDraft`: si la raíz del borrador declara la
   colección con la misma `family_column` e `identity_columns` y contiene la
   fila. Se mantiene estricto con el servidor y tolerante con el borrador.
2. `ProductSpecMemberDrafts` se crea una vez por carga de producto y sobrevive
   a `_loadSpecTemplate`; no se guarda por llave de plantilla. El reset por
   cambio de autoridad (:1371) debe limpiarlo también.
3. `buildCommand(parentTemplate: borrador, parentValues: borrador)` ya rechaza
   los activos no vinculados. La UI los muestra como bloqueo con acción
   «Archivar» por perfil y deshacer hasta guardar (`undoArchive`); nunca
   archivo automático. Si se revierte la categoría antes de guardar, las marcas
   siguen visibles y reversibles.
4. El guardado es v2 con `archive_ids`, la categoría nueva y `p_template_id`
   nuevo en la misma RPC, como ya lo exige el servidor.
5. `_row` compara `field` y `family_column` pero no `identity_columns`
   (:305-315). Entre dos plantillas que comparten la definición pero declaran
   columnas de identidad distintas, el cliente pasa y el servidor rechaza con
   «El componente cambió» (:237). Comparar también `identity_columns`.

El disparador nuevo sobre `category_tech_mappings` (core :364-389) sube
`spec_revision` del producto al cambiar la asignación: un editor abierto recibe
40001 al guardar. Coherente con `p_expected_revision`.

## C2 — Tras guardar, los borradores no saben que ya existen

**Ruta causal.**

1. Un perfil nuevo nace con `persisted: false`
   ([product_spec_member_draft.dart:52-79](../../../lib/modules/inventory/models/product_spec_member_draft.dart:52)).
   `buildUpsert` sólo envía `binding_action` si `persisted` (:212) y
   `buildCommand` sólo archiva persistidos (:292).
2. `saveProductWithSpecs` devuelve sólo `Product`
   ([inventory_service.dart:739-747](../../../lib/modules/inventory/services/inventory_service.dart:739));
   descarta `member_profiles` y `revision` del read-back v2. El formulario
   actualiza `_specRevision` y `_existingProduct` (:5254) y nada más.
3. No existe API para marcar los borradores como guardados ni para
   reconstruirlos desde el read-back. El decoder tampoco acepta el bloque solo:
   necesita el contexto v3 completo.

**Consecuencias, con el mismo objeto de borradores tras un guardado
exitoso:**

- **Identificar el componente recién creado** (fila sin modelo → se confirma el
  modelo con su fuente): el segundo upsert va sin `binding_action`. El servidor
  ve identidad distinta a la guardada y exige la acción:
  `Confirma la identificación con su fuente o archiva la ficha anterior`
  (core :500). El guardado falla hasta recargar.
- **Archivar el componente recién creado:** `archive_ids` lo omite; el servidor
  lo deja activo. El cliente lo muestra archivado, el siguiente guardado lo
  omite del comando (los omitidos no se tocan) y, si además se retiró su fila,
  el servidor rechaza con `Falta la fila del componente` (:185). Al recargar,
  reaparece activo.

**Repro (P2, ejecutado).** Fixture `active`: `archive(082)`,
`add(forRow(083, r2))`, `buildCommand` → `upserts=[081,083]`,
`archive_ids=[082]` (guardado 1). Sin reconstruir: se agrega `identity_model`
a r2 y `identify()` → el upsert de 083 en el guardado 2 trae las claves
`[id, collection_definition_id, member_row_id, template_id, contract_version,
manufacturer_sku, reference_id, values]`, sin `binding_action`. Variante:
`archive(083)` tras el guardado 1 → `archive_ids=[081]` en la primera sonda.

**Propuesta.** Después de cada guardado v2 confirmado, releer v3 con la
categoría guardada, exigir `revision == savedProduct.specRevision` y
reconstruir `ProductSpecMemberDrafts` desde esa lectura, bloqueando ediciones
entre el acuse y la reconstrucción. Si se prefiere usar el read-back del
guardado, el decoder necesita una entrada que acepte bloque + raíz ya
decodificada. Un `markSaved()` que sólo cambie `persisted` no basta: también
debe limpiar `_bindingAction`, y quedaría desalineado de identidad, fuentes y
`saved_contract_version` que el servidor pudo cambiar.

## C3 — Referencia con un hecho fuera de la plantilla del componente (bajo)

**Ruta causal.** `selectReference` copia **todos** los hechos de la referencia
al borrador (:133-138). `validate()` no reclama: el valor es conocido y no hay
definición que lo contradiga. `buildFactPayload` recorre sólo los campos de la
plantilla y omite la clave ajena; el servidor vuelve a derivar todos los hechos
de la referencia (`v_reference || p_values`, candidato :63-64) y rechaza
`La respuesta no pertenece a esta plantilla` (:69). Aplica cuando dos claves de
plantilla comparten familia técnica: `hydraulic_disc_brake` y
`mechanical_disc_brake` bajo `complete_brake`, que es justo el caso de los
miembros. La raíz tiene el mismo comportamiento latente.

**Repro (P4, ejecutado).** Referencia de la fixture con un hecho
`member_test_other_key` agregado: `values` del borrador incluye la clave,
`validate()` devuelve `[]`, el upsert lleva sólo 052 y 053 con
`reference_id` puesto. El rechazo del servidor es por lectura del candidato.

**Propuesta.** `validate()` emite un bloqueo (`reference_identity` o un código
propio) cuando `reference.facts` tiene claves fuera de los campos activos de la
plantilla, o el selector ofrece sólo referencias cuyos hechos caben. No
verifiqué si existen referencias así en producción.

## Compuerta de publicación (`prepare_product_spec_member_publication.py`)

Sin hallazgo bloqueante. Lo que revisé:

- Preimagen exacta: los seis predecesores se comparan contra
  `predecessors.json` en identidad, md5, dueño, ACL, definer, volatilidad y
  `search_path`; el compilador ya exige esos mismos md5 por cuerpo (verifiqué
  que `md5(body)` coincide en los seis). Objetos nuevos ausentes; sin hechos
  con scope ni plantillas con `member_profiles`; prerrequisito de orden
  estricto por md5. Todo falla cerrado.
- Ruta de recuperación: si la tabla ya existe, exige que funciones, tablas y
  disparadores coincidan exactamente con el manifiesto; nunca sobreescribe
  deriva.
- Post-imagen y read-back: funciones, tablas (columnas, constraints, índices,
  políticas) y disparadores comparados contra el manifiesto local; huella de
  datos de diez tablas igual antes y después.
- El candidato se regenera byte a byte desde el compilador (verificado con
  `cmp` sobre los hashes finales). La clave única `(id, is_active)` de
  `spec_templates` que usa la FK compuesta existe en producción
  (`20260906160000:57`).

Fragilidad menor: para las seis funciones reemplazadas, `create or replace`
conserva dueño y ACL, así que su post-imagen esperada debería salir de
`predecessors.json` (verdad de producción) y no del manifiesto local. Si local
y producción difieren en ACL, la migración falla cerrada por un falso
negativo. Bajo; no lo reproduje. Supone además que el despliegue corre como
`postgres`, igual que la captura local.

## Áreas revisadas sin hallazgo

| Área | Evidencia |
|---|---|
| Versión y revisión | El upsert envía `contract_version` de la plantilla **cargada** (:205), no la guardada; el servidor responde 40001 si cambió (core :486) y actualiza `saved_contract_version`. `isStale` es informativo. La revisión esperada de los miembros sale de la misma lectura v3 que la raíz (`spec_engine_service.dart:380`). |
| Comando completo | `buildCommand` incluye todos los activos como upserts y sólo los persistidos como archivo (:269-295); los omitidos no se tocan en el servidor, pero la lectura es de todo el producto y va guardada por revisión. Dos activos en una fila se rechazan (:277-282) igual que el índice parcial (core :24). |
| identify / rebind / archive | Identificar exige fuente y conservar lo confirmado (:151-158) = enriquecimiento del servidor (core :105-110, :288). Rebind exige identidad idéntica y elección explícita (:167-179) = core :506. Ambas en un mismo guardado se excluyen en los dos lados. Archivar y crear sobre la misma fila en un comando pasa el índice parcial porque el servidor archiva antes de insertar (core :462-471, :515). Archivo de un borrador no persistido nunca llega al servidor (test del draft). |
| Procedencia | Automáticos = `catalog_keys` ∩ hechos de la referencia (:28-31); se omiten del upsert y el servidor los vuelve a derivar como `catalog`. Al quitar la referencia se retiran los automáticos y se conservan los manuales (test «catalog round trip»); el escritor borra los `catalog` no enviados y conserva los `mechanic` iguales con sus lecturas (candidato :83-87, :119-127). Un manual igual al catálogo queda `catalog` en el servidor: mismo comportamiento que la raíz, ya revisado. |
| Referencia con MPN | Referencia con `manufacturer_sku` y miembro sin MPN → `reference_identity` bloqueante en cliente y servidor (P5); adoptar el MPN exige `identify` con fuente. Explícito, no silencioso. |
| Atomicidad del cliente | Una sola RPC con producto, raíz y comando de miembros (`inventory_service.dart:718-748`); la clave de operación rota sólo tras el acuse (:5246). El embedding sigue fuera de la transacción, como antes. |
| Cliente v1 | `_specSaveCommand` sin `p_member_profiles` → `save_product_with_specs_v1` (:752-755), protocolo 1: los perfiles no se tocan y se validan igual. |
| Plantilla de borrador | `decodeProductMemberTemplate` exige padre, colección, clave de familia, revisión 0 y valores vacíos (:404-421); `forRow` exige que la fila nombre la clave de la plantilla (:66-69). |

## Cambios durante la revisión

Root editó en paralelo el decoder, su test, el script de publicación, el core,
el candidato, el compilador y el pgTAP. Releí completo el script de
publicación; del decoder verifiqué por grep que la derivación de colecciones
desde la raíz del borrador (:240-242, :317) y la regla canónica de identidad
(:495) son las citadas, y volví a correr tests y sondas contra los hashes
finales. Del core leí sólo las piezas nuevas que tocan estos flujos
(:141-156, :364-389); no reaudité el servidor. El core cambió tres veces
durante la revisión; las líneas citadas corresponden al hash final.

## Límites

- Sin SQL: las reglas del servidor son por lectura del core y del candidato.
- Sin UI ni runtime: el flujo del formulario está reconstruido desde el código;
  no lo ejecuté.
- No revisé el candidato de orden estricto ni comparé predecesores contra
  producción; no verifiqué el rol con que corre `deploy_migration.sh`.
- Las sondas viven fuera del repo y no son pruebas de regresión.

## Hashes finales leídos

| Archivo | SHA-256 |
|---|---|
| `lib/modules/inventory/models/product_spec_member_draft.dart` | `0f2e31567f16ba1fc5c2cbe55a3dffb1ea0a8086a4587f417b3a59e58d7cfeba` |
| `lib/modules/inventory/models/product_spec_member_profile.dart` | `601df79ffb45a8ce98201570b10ea23e73229bb2b7b4d626e802301b8d70497f` |
| `test/unit/product_spec_member_draft_test.dart` | `ffab523f8a435852eb6153e9c12ed1cefcf18ceb9268f38e4400a9dfac0e5558` |
| `test/unit/product_spec_member_profile_test.dart` | `8ce08440d5228ab264885452811e5140b85995860c1d9e7723d9e9925f1b2cf5` |
| `lib/modules/inventory/services/spec_engine_service.dart` | `a75d57812daf63d6418b4feace9878e68fc5a2ba582beacbfb3eafce190f43cc` |
| `lib/modules/inventory/services/inventory_service.dart` | `5a2e29b8c212a87b9f69c898ed77899750fd537abac11616db3080dc1845bbe4` |
| `lib/modules/inventory/pages/product_form_page.dart` | `a0ec974c6b624ce409eae53e7ff144a475ec27202ac5d3b39e83f0d4bf4cc4fd` |
| `scripts/inventory/prepare_product_spec_member_publication.py` | `32c2a9e2ff3884ab9033bbf39909829771e6bc1cd06029792257b3d83a9395b7` |
| `scripts/inventory/compile_product_spec_member_profiles.py` | `4fa9bdeaa644d26bd4ccf6208c94734f35a7a5ad6cb1ad9af4642416b407e139` |
| `scripts/inventory/sql/product_spec_member_profiles_core.sql` | `15aa994dc09053668f7d8f5256f7b4000f5767034e38cea48524fcaf07ebf0c4` |
| `scripts/inventory/sql/product_spec_member_profiles_candidate.sql` (regenerado idéntico) | `a4ca8a14d29a034c721a244bab03a0822ae5fc9334c008334667d17c7141e84d` |
| `scripts/inventory/sql/product_spec_member_profile_predecessors.json` | `951f6c250adea4fc471562f719edad7cdc366b0a02f638c23f601d0445a3077d` |
| `test/fixtures/product_spec_member_profiles.json` | `0e0b42b945bfebecd22e159f7439e6a7ad15646773363f31210043b955b34845` |
| `supabase/tests/product_spec_member_profiles.sql` (no reauditado) | `87370a685244bc45e3ad2f3b69202da54f7d327f917b9ccaad6fee3fce1a9b16` |
