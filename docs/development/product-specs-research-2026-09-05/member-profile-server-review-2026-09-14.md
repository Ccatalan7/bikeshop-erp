# Revisión independiente del servidor de perfiles de componentes

14 de septiembre de 2026. Revisión de sólo lectura, sin SQL local ni productivo,
sin editar código. Las pruebas mínimas de abajo **no se ejecutaron**: son el
caso exacto para que Root las corra en local. F2 sigue abierto.

## Veredicto

- Contradicción 2: **cerrada para metadatos de plantilla**. Un cambio de
  plantilla, campo, definición u opción que deje inválido un perfil activo no
  llega a confirmarse. Queda una ruta fuera de esos triggers: la asignación de
  categoría del tenant (H1).
- Contradicción 1: la regla propuesta **basta**. El catálogo real no tiene una
  colección de componentes con otros nombres de marca y modelo.
- Hallazgos nuevos: H1 (medio, bloquea activar familias sobre productos ligados
  por categoría) y H2 (bajo, no bloquea publicar).
- No encontré otro bloqueo de diseño para publicar el framework sin activar
  familias ni llenar productos. Falta la verificación pgTAP pedida al final.

## H1 — Reasignar la categoría deja perfiles activos inválidos sin validar

**Ruta causal**

1. Un producto sin plantilla explícita resuelve su ficha padre por
   `category_tech_mappings` con `status='active'`
   (`20260906160000_product_spec_template_binding.sql:121`).
2. Cualquier usuario autenticado del tenant puede insertar, cambiar o borrar esa
   fila: las políticas sólo exigen `tenant_id = user_tenant_id()`
   (`20260318_spec_engine.sql:201-208`). No hay trigger ni función que la
   valide, ni en migraciones ni en el candidato.
3. La revalidación de perfiles sólo corre desde `spec_templates`,
   `spec_template_fields` y `spec_definitions` (`product_spec_member_profiles_core.sql:324-332`),
   y desde cambios de categoría o plantilla del propio producto
   (`product_spec_identity_constraint`, `20260906070000_product_spec_contract.sql:646`).
   Cambiar la asignación no toca ninguno de los dos, ni la época del grafo
   (`core.sql:70-77`).
4. La transacción confirma con perfiles activos cuya ficha padre ya no declara
   la colección. Desde entonces, toda validación del producto falla con 23514
   en `spec_member_binding_internal_v1` (`core.sql:151-153`): también un
   guardado v1 que sólo cambia el precio. Sólo sale archivando por v2.
5. El lector sigue entregando los perfiles activos (`core.sql:509-511` no mira
   la ficha padre), pero el contexto raíz v2 ya muestra otra plantilla o
   ninguna. El decoder entregado en la ronda 197 rechaza ese contexto (colección
   no declarada): el editor no abre para ofrecer el archivo.

Aunque se agregue la validación, la asignación también debe tocar la época de
la plantilla anterior y la nueva. Si no, un perfil que se guarda en paralelo
no queda serializado contra el cambio, igual que ya hace el guard
(`core.sql:239-242`).

**Prueba mínima** — en `supabase/tests/product_spec_member_profiles.sql`,
después de la línea 196 (perfiles r1/r3 activos, JWT del tenant A):

```sql
reset role;
savepoint member_mapping_route;
insert into public.product_categories(id,tenant_id,name,full_path) values
 ('99e10000-0000-4000-8000-000000000012','99e10000-0000-4000-8000-000000000001','Spec kits','Spec kits');
insert into public.category_tech_mappings(tenant_id,category_id,technical_family,template_id,status) values
 ('99e10000-0000-4000-8000-000000000001','99e10000-0000-4000-8000-000000000012','drivetrain_kit',
  '99e10000-0000-4000-8000-000000000050','active');
update public.products set category_id='99e10000-0000-4000-8000-000000000012',spec_template_id=null
 where id='99e10000-0000-4000-8000-000000000020';
select lives_ok($$set constraints all immediate$$,'the same parent through the category keeps the kit valid');
set local role authenticated;
select lives_ok($$update public.category_tech_mappings set status='inactive'
 where category_id='99e10000-0000-4000-8000-000000000012'$$,'a tenant user changes the category mapping');
reset role;
select throws_ok($$set constraints all immediate$$,'23514',null,
 'a mapping change cannot commit over active profiles');                     -- hoy falla: no hay nada que revalide
select is(jsonb_array_length(public.get_product_spec_member_profiles_v1(
 '99e10000-0000-4000-8000-000000000020')->'profiles'),2,'reader still offers both active profiles');
select throws_ok($$select public.spec_validate_product_internal_v1('99e10000-0000-4000-8000-000000000020')$$,
 '23514',null,'the committed graph no longer validates');                    -- hoy pasa: confirma la ruta
rollback to savepoint member_mapping_route;
```

**Estado.** No bloquea publicar el framework, porque aún no hay perfiles.
Bloquea activar familias sobre productos ligados por categoría, y bloquea el
saneamiento de asignaciones pendiente mientras existan perfiles activos.

**Cierre sugerido.** Un constraint trigger diferido en `category_tech_mappings`
(insert, update, delete). Para los productos del tenant con
`spec_template_id is null`, categoría antigua o nueva y perfiles activos, debe
tocar la época de ambas plantillas y llamar a
`spec_validate_product_member_profiles_internal_v1`. No reabro el comportamiento
previo de los hechos raíz frente a una reasignación.

## H2 — El historial de perfiles no tiene guarda de inmutabilidad

**Ruta causal.** La cabecera no se borra ni se cambia archivada (`core.sql:228-265`).
Los hechos, opciones y lecturas archivadas tampoco (`core.sql:336-374`), aun para
una sesión privilegiada: la prueba pgTAP lo verifica tras `reset role`
(líneas 254-260). `product_spec_member_profile_events` sólo tiene `revoke`
más lectura por tenant (`core.sql:42-58`), y no tiene trigger. Ahí queda el único
registro de la fila, identidad, referencia y actor anteriores (`core.sql:283-284`),
y su hash entra en la huella del respaldo (`core.sql:477-479`). Una sesión
privilegiada, como un script de reparación o `service_role`, puede borrarlo o
reescribirlo. Se pierde la historia del cambio de fila y la huella cambia sin
aviso.

**Prueba mínima** — después de la línea 189:

```sql
reset role;
savepoint member_history_route;
select throws_ok($$delete from public.product_spec_member_profile_events
 where profile_id='99e10000-0000-4000-8000-000000000082'$$,'23514',null,'profile history is append-only');
select throws_ok($$update public.product_spec_member_profile_events set actor_id=null
 where profile_id='99e10000-0000-4000-8000-000000000082'$$,'23514',null,'profile history keeps its actor');
rollback to savepoint member_history_route;
```

Hoy ambas sentencias se ejecutan sin error.

**Estado.** No bloquea publicar. Hay que cerrarlo antes de declarar el historial
inmutable: basta un `before update or delete` que falle con 23514, como la rama
de borrado del guard.

## Adjudicación de la contradicción 2

La pregunta es si puede confirmarse una metadata que deja inválido un perfil
activo. Por la plantilla, **no**:

- **Todos los cambios de plantilla pasan por el trigger.**
  `spec_contract_revision_internal_v1` (`20260906070000_product_spec_contract.sql:889`)
  convierte los cambios de campo, definición y opción en un `update` de
  `spec_templates`. Así los cuatro caminos entran al trigger diferido de
  metadatos (`core.sql:302-332`).
- **El trigger revalida cada producto afectado.** Para cada producto con
  perfiles activos cuya plantilla de componente o ficha padre actual sea la
  cambiada (`core.sql:316-319`), revisa tres cosas y aborta con 23514:
  - vínculo e identidad (`core.sql:207-211`);
  - hechos fuera de la plantilla (`core.sql:212-216`);
  - completitud de la referencia y observaciones bloqueantes (`core.sql:217-220`, que llama a `180-186`).

  La ruta original de la contradicción, retirar un campo del que depende una
  referencia o un hecho sin cambiar el id, aborta al confirmar.
- **Las rutas que movían la resolución también están cerradas:**
  - retirar la ficha padre o cambiar su key, tenant o familia técnica: guardia de
    retiro mientras un producto o una asignación activa la usan
    (`20260906160000_product_spec_template_binding.sql:106`);
  - desactivar la plantilla de componente: FK compuesta (`core.sql:21-22`);
  - borrar una opción usada: FK restrict (`20260821180000_spec_facts_unified.sql:69`);
  - mudar un hecho de scope: `spec_product_fact_graph_internal_v1`
    (`20260906070000_product_spec_contract.sql:561`).
- **La escritura directa de hechos también se valida:**
  `product_spec_fact_constraint` (`20260906070000:649`) llama al validador de
  producto, que ya incluye los perfiles (candidato, línea 806).

Por eso el lector ya no puede caer en `core.sql:185` por esas rutas. La única
salida es la asignación de categoría (H1): no hace caer al lector, porque las
observaciones no usan la ficha padre, pero deja fallando todo guardado.

Una precisión: el trigger elige los productos por la ficha padre resuelta
**después** del cambio (`core.sql:318`). Si un cambio saca la resolución de esa
plantilla, el producto no se revisa. Para plantillas lo impide la guardia de
retiro; para asignaciones nada lo impide.

## Contradicción 1: evaluación de la regla canónica

Propuesta de Root: `identity_columns` debe incluir `identity_brand` e
`identity_model`, aunque sus valores falten hasta investigarlos. **Basta.**

- **Nombres.** En los catálogos integrados
  (`all-family-*-integrated-2026-09-07.json`), las 74 colecciones con columna
  `family` usan exactamente `member_role, family, quantity, position,
  identity_brand, identity_model`. Ninguna colección habilitable usa otros
  nombres.
- **Familias.** Los 105 tokens de familia son keys de plantilla; ninguno es sólo
  una familia técnica. Sólo `hydraulic_disc_brake` y `mechanical_disc_brake`
  difieren de su familia técnica (`complete_brake`). Eso ya lo resuelve el
  vínculo por key (`core.sql:160-163`) y la referencia por familia técnica.
- **Servidor y cliente leen las mismas dos claves** (`core.sql:189`, y el
  `validate` del decoder Dart).
- **Valores ausentes.** El vínculo proyecta sólo las claves presentes
  (`core.sql:165-166`), así que el validador recibe texto vacío y marca
  `reference_identity` hasta identificar con fuente (`core.sql:260-265`). Es el
  comportamiento correcto: la referencia espera a la identidad.

No es contraejemplo el caso de las filas que nombran varias piezas con otros
nombres (circuitos hidráulicos con `lever_brand`, `caliper_brand` y
`hose_model`). No tienen columna de familia tipada, y el contrato actual ya
impide habilitarlas (`core.sql:121-124`). Si algún día se quiere un perfil por
pieza ahí, hace falta una colección de una pieza por fila, no un mapa de
nombres.

Implementación: en `spec_member_collection_contract_internal_v1`
(`core.sql:125-136`), exigir `entry->'identity_columns' ?& array['identity_brand','identity_model']`.
Como el trigger de metadatos ejecuta el contrato en cada cambio de plantilla
(`core.sql:315`), ninguna plantilla se publica violándolo. Caso pgTAP: quitar
`identity_model` de `identity_columns` debe fallar con 23514.

## Áreas revisadas sin hallazgo

| Área | Evidencia |
|---|---|
| RPC, auth y tenant | Lectores exigen `auth.uid()` y tenant del producto (`core.sql:490-492`, `540-543`; snapshot v2 vía v1 y eventos filtrados por tenant, `475-476`). Guardado v2 (candidato 854, 863-865, 892-896). Apply filtra tenant y producto (`core.sql:407-409`, `432-434`). El guard rechaza plantilla o definición ajenas (`core.sql:231-238`). |
| RLS y ACL | Cabecera y eventos: sólo lectura por tenant (`core.sql:32-38`, `52-57`). Época revocada (`core.sql:69`). Funciones nuevas revocadas; sólo cinco RPC concedidas (candidato 966-993). DML de hechos de producto bloqueado para authenticated/anon por políticas restrictivas (`20260906170000_product_spec_legacy_boundary.sql:631-641`). |
| Recibo y hash | v1 conserva su hash; v2 envuelve protocolo, hash raíz y comando completo antes de leer el recibo (candidato 875-888). Una misma clave v1/v2 choca con 23505 (pgTAP 126-127). |
| Rollback comercial | Todo en una transacción; validación en línea después del apply (candidato 944-947) y constraints diferidos (pgTAP 133-135, 143-145). |
| Escritor único y transporte exacto | Cabeceras sólo por apply. Hechos por el escritor con scope, con `::numeric` desde texto (candidato 131). Lector en texto (`core.sql:499-500`, `507`). Los escritores viejos se limitan a `subject_scope is null`: `save_product_spec_facts_v1`, `record_product_spec_reading_v1`, el espejo legacy y el candidato de aplicación (línea 169). |
| Archivo e inmutabilidad | Guard de cabecera (`core.sql:249-265`); hechos, opciones y lecturas archivadas (`core.sql:355-357`); identidad y scope del hecho inmutables (`20260906070000:561`). Salvo H2. |
| Candados y época | Guard, guard de hechos y trigger de metadatos tocan la época (`core.sql:239-242`, `358-362`, `313-315`). El guardado toma FOR SHARE sobre la ficha padre (candidato 901-903) y la de componente (`core.sql:425`), y todo cambio de metadatos escribe la fila de plantilla (`20260906070000:889`): espera o falla por serialización. Salvo H1. |
| Lecturas activas y archivadas | Payload por scope (`core.sql:501`, `507`); `catalog_keys` por scope (`503-506`); observaciones `[]` si está archivado (`175`); plantilla sólo en activos (`509-511`). Las funciones que leen `spec_facts` sin filtro de scope son guardias de población (fallan cerradas) o el snapshot de investigación v1, que ya lleva `subject_scope` en cada hecho. |
| Compatibilidad v1 | El wrapper v1 conserva firma y hash con protocolo 1 (candidato 958-961). Los predecesores reemplazados son wrappers con scope nulo (759-770). Un cliente viejo no puede dejar huérfano un perfil (pgTAP 133-135). |

## Descartados al verificar

- **Mover evidencia archivada con `update spec_facts set subject_scope=…`.** El
  guard nuevo sólo mira `NEW` (`core.sql:341`), pero
  `spec_product_fact_graph_internal_v1` ya prohíbe cambiar tenant, tipo, sujeto,
  scope o definición de un hecho de producto.
- **Leer por la plantilla de componente después de quitarle un campo.** El
  trigger de metadatos lo aborta (arriba).
- **Tokens de familia escritos como familia técnica.** 0 de 105.

## Verificación pedida (no afirmada como hallazgo)

La prueba difiere todos los constraints en la línea 62 y los ejecuta en la 269.
La línea 222 inserta una lectura sobre el hecho de 082, escrito por el escritor
con scope con fuente `mechanic` (candidato 135). El trigger
`spec_fact_readings_only_on_readings` exige fuente `name_reading`
(`20260831290000_the_label_and_the_button_agree.sql:167-189`). Leyendo el
código, la ejecución de la línea 269 debería fallar con 23514.

El insert además omite `definition_id` y `vocabulary_digest`, declarados NOT
NULL (`20260831290000:145-146`). Cuatro pruebas existentes usan el mismo insert,
así que esa parte no la afirmo.

Si el archivo pasa en local, lo resuelven dos consultas:
`select tgenabled from pg_trigger where tgname='spec_fact_readings_only_on_readings'`
y la definición local de `spec_fact_readings`.

Hay una consecuencia que no depende de la corrida: ningún escritor actual crea
un hecho de componente que admita lectura. Los casos 222-231 y 251-255 prueban
guardas sobre un estado que el producto no produce. La inmutabilidad archivada
se prueba mejor sobre hechos y opciones que el escritor sí crea.

## Estado de bloqueos

| Bloqueo | Estado |
|---|---|
| Publicar el framework sin activar familias ni llenar | Sin bloqueo de diseño encontrado; pendiente la verificación pgTAP de la línea 269 |
| Activar familias sobre productos ligados por categoría, o sanear asignaciones con perfiles activos | Bloqueado por H1 |
| Declarar inmutable el historial de perfiles | H2 abierto; no bloquea publicar |
| Contradicción 1 | La regla basta; falta implementarla con su caso pgTAP |
| Contradicción 2 | Cerrada para metadatos de plantilla; residual en H1 |
| Contradicción 3 | Corregida (`core.sql:526-529`; pgTAP 102-104) |

## Límites

- Sin SQL: todo sale de leer el código; las pruebas mínimas no se corrieron.
- No revisé el candidato de orden estricto de filas que incluyen las pruebas,
  ni comparé los md5 de predecesores contra producción; eso es de la compuerta
  de publicación.
- No revisé el servicio ni el editor Dart que Root está conectando.
- La concurrencia la analicé por orden de candados. No busqué interbloqueos de
  forma exhaustiva: un bloqueo mutuo aborta con 40P01 y no corrompe datos.

## Hashes leídos

| Archivo | SHA-256 |
|---|---|
| `scripts/inventory/sql/product_spec_member_profiles_core.sql` | `7a51e51dc29b7c32df70245d40a68d2ce2c570d700feaa546dd36e7169c4743d` |
| `scripts/inventory/sql/product_spec_member_profiles_candidate.sql` (regenerado byte a byte desde el compilador; core embebido idéntico) | `8acf4db26c7a9ea1e8f730b05031917cbcae318803c1ecd8672781a0ede703fb` |
| `scripts/inventory/compile_product_spec_member_profiles.py` | `c12f2525c1aa74546ac178af2f18b99f9dde5cc9f91d0701f12d24abe586f9bf` |
| `scripts/inventory/sql/product_spec_member_profile_predecessors.json` | `951f6c250adea4fc471562f719edad7cdc366b0a02f638c23f601d0445a3077d` |
| `supabase/tests/product_spec_member_profiles.sql` (antes `98db0fb3…`; +3 líneas del sobre vacío) | `b225274ea48950da3f04db3a59cbf185a94d29e9111e0fc2f1a544ba6fe0ef98` |
| `scripts/inventory/test_product_spec_member_concurrency.py` (antes `eb14761e…`) | `c108f45e8b5710396979ee6fc71235ec03e57a9f28b3bc0d6309fd9c0ccf7143` |
| `scripts/inventory/sql/product_spec_application_candidate.sql` (sólo filtros de scope) | `71db507e742e04c5450acdeb592fb4b236cf44fa07545f3071237223db6457b7` |

## Adjudicación de H1, H2 y claves canónicas (ronda 203, sólo lectura)

Releí las piezas nuevas del core (`a1dae85b…`), el pgTAP corregido
(`fb1dd1ca…`) y la evidencia en `.tmp`. No corrí SQL.

### H1 — cerrado

`spec_member_category_constraint` ([core.sql:364-389](../../../scripts/inventory/sql/product_spec_member_profiles_core.sql:364)),
diferido, sobre insert/update/delete de `category_tech_mappings`:

- no hace nada si no cambian tenant, categoría, plantilla o estado (:369-370);
- toca la época de la plantilla saliente y de la entrante (:371-376);
- para cada producto sin plantilla explícita, de la categoría vieja o de la
  nueva, con perfiles activos, revalida los perfiles y sube `spec_revision`
  (:377-386). Elegir los productos por categoría y no por plantilla resuelta
  cubre el caso que señalé: el producto que sale de la plantilla.

Evidencia: pgTAP ok 41-43 (`status='pending'`, borrado y reasignación del
mapping fallan con 23514, ejecutados como `authenticated`, que es la ruta RLS
real) y las cuatro cédulas nuevas de concurrencia:
`category_before_new_profile` 55P03, `profile_before_category_reassignment`
55P03, `repeatable_read_category_profile_phantom` 40001 y
`fresh_category_revalidation` 23514.

Residual, no bloqueante: el disparador revalida sólo los perfiles, no la raíz;
la raíz nunca dependió de la asignación. Un producto con `spec_template_id`
explícito no se ve afectado por la asignación, y es correcto que no lo esté.

### H2 — cerrado

`spec_member_event_immutable` ([core.sql:60-67](../../../scripts/inventory/sql/product_spec_member_profiles_core.sql:60)):
`before update or delete` sobre `product_spec_member_profile_events`, siempre
23514. pgTAP ok 37-38 (borrado y cambio de actor) corren tras `reset role`, así
que cubren una sesión privilegiada. Residual: `truncate` no pasa por
disparadores de fila; queda fuera de este alcance y la huella del respaldo lo
delataría.

### Claves canónicas — cerrado

[core.sql:151](../../../scripts/inventory/sql/product_spec_member_profiles_core.sql:151)
exige `identity_columns ?& ['identity_brand','identity_model']` en cada
colección; pgTAP ok 59 lo prueba sin perfiles activos, es decir, en el borde de
metadatos. Coincide con las dos claves que leen el servidor y el cliente.

### ACL heredada de producción

El preflight real muestra que las tablas nuevas de `public` heredarían
`codex_test_runner=r` por privilegios por defecto. El core (:78-94) revoca en
las tres tablas nuevas a cualquier grantee que no sea el dueño, `service_role`
o `authenticated`, y `spec_member_graph_revisions` queda además con RLS sin
políticas. Con eso el manifiesto de tablas (que compara el texto de la ACL)
puede coincidir en local y en producción. Las funciones no lo necesitan: el
privilegio por defecto real es `{postgres=X,service_role=X}`.

### Verificación pedida — confirmada

Las lecturas `.tmp/db/member-profile-reading-category-{production,local}-20260914.json`
muestran producción con `definition_id` y `vocabulary_digest` NOT NULL, la FK
compuesta y el disparador `spec_fact_readings_only_on_readings` activo; local
sin ninguno de los tres. El pgTAP anterior habría fallado en producción. La
corrección: `supabase/tests/fixtures/product_spec_reading_receipt_contract.sql`
aplica ese contrato dentro del rollback de la prueba, y la prueba fija
`source='name_reading'` antes de insertar la lectura con `definition_id` y
`vocabulary_digest` (pgTAP :261-267). La fixture es una copia declarada, no
una prueba de paridad; la compuerta sigue siendo el preflight real.

### Evidencia leída

| Evidencia | Contenido | SHA-256 (16) |
|---|---|---|
| `.tmp/db/member-profiles-member-latest-20260914.log` | `1..67`, 67 ok, 0 not ok (el mensaje decía 65; el log trae 67) | `9c4dc4500e0e4425` |
| `.tmp/product-spec-member-concurrency/schedules.log` | 11 cédulas con el SQLSTATE esperado; `all_member_concurrency_schedules_pass=1`; `final_observation_preserved=1` | `277b5a7a86b5c10c` |
| `.tmp/product-spec-member-concurrency/state-after.log` | fixture y extensión ausentes tras restaurar | `50e2a9765af9a233` |
| `.tmp/product-spec-member-publication/live-preflight.json` | seis predecesores iguales en md5, dueño, ACL, definer, volatilidad y config a `predecessors.json` y al compilador; orden estricto igual; 0 hechos con scope; 0 plantillas con perfiles; cabeza `20260910133000`; tabla ausente | `f19f2c2f82116336` |
| lecturas de `spec_fact_readings` producción / local | arriba | `62cadd0964af91d9` / `57794f2601de979a` |
| `supabase/tests/fixtures/product_spec_reading_receipt_contract.sql` | contrato de recibos dentro del rollback | `8beec17ee3475626` |

### Migración preparada

`supabase/migrations/20260914213000_product_spec_member_profiles.sql`
(`f5708c27…`, 1.147 líneas, no aplicada) ya lleva la inmutabilidad del
historial, el disparador de asignación, el barrido de ACL y la regla canónica,
pero **no** `member_parent_context` ni el `editor_context` del acuse: es
anterior al candidato actual (`7c4f8e3a…`). Hay que regenerarla antes de
desplegar, como Root anunció.

### Estado

| Bloqueo | Estado |
|---|---|
| H1 | Cerrado; residual documentado |
| H2 | Cerrado; residual `truncate` |
| Claves canónicas | Cerrado |
| Verificación pgTAP de la línea 269 | Confirmada y corregida |
| Publicar el framework | Sin bloqueo del lado servidor; falta regenerar la migración y el read-back real |
