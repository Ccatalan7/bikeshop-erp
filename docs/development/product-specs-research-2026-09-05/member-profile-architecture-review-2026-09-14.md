# Perfil técnico por miembro de kit: revisión arquitectónica — 2026-09-14

Revisión independiente y acotada para el hallazgo **F2** de cadenas y kits: hoy
cada miembro de un kit tiene identidad, evidencia, interfaces y declaraciones,
pero **no una ficha técnica con las medidas de su familia**. Esta revisión
propone el camino mínimo para darle una, reutilizando lo que ya existe.

Sólo lectura de código, migraciones y artefactos. No edité motor, GUI,
compiladores, SQL ni otros documentos; no leí producción, no corrí runtime, no
publiqué ni llené. **F2 sigue abierto**: esto es una propuesta, no un cierre.

No reabrí Sheldon, Park ni fuentes OEM, porque la propuesta no introduce ninguna
afirmación mecánica nueva: todo lo que decide aquí es de persistencia, dueño y
alcance.

## 1. Tres cosas que no deben confundirse

El código ya las separa, y la propuesta depende de mantenerlas separadas:

| Qué es | Dónde vive hoy | Rasgo que no se puede perder |
|---|---|---|
| **Referencia OEM exacta** | `product_spec_references` (`20260906070000_product_spec_contract.sql:16-30`) | Global, sin `tenant_id`, sólo lectura para `authenticated`, con fuentes obligatorias. Una edición nueva del catálogo es un id nuevo (`product_spec_contract.dart:121-123`). Se **elige** y luego se valida por identidad (`matchesIdentity`, `:162-172`); no se deduce. |
| **Hecho observado de un producto** | `spec_facts` con `subject_type='product'` (`20260821180000_spec_facts_unified.sql:27-46`) | Del tenant, con `source`, `confirmed` y lecturas auditables. Su identidad es inmutable y debe apuntar a un producto del mismo tenant (`20260906070000…:561-587`). |
| **Pieza vendida por separado** | una fila real de `products`, opcionalmente componente en `product_set_components` (`20260721190000_canonicalize_product_set_inventory.sql:1-7`) | Tiene SKU, stock, categoría y su propia ficha. Un componente pertenece a **un solo** juego (`:20-21`, `uq_product_set_components_component`). |

Un **miembro de kit** no es ninguna de las tres. Es una pieza dentro de **un**
producto que no tiene fila propia en inventario. Su perfil es una observación
sobre ese producto, acotada a una parte suya. Puede apoyarse en una referencia
OEM elegida explícitamente, pero no es la referencia; y no se convierte en un
producto por tener medidas.

## 2. Qué hay hoy en el código

**El eje `subject_scope` ya existe y significa exactamente esto.** Se agregó a
`spec_facts` para decir «qué parte del sujeto» —`front_brake`, `rear_brake`,
`drivetrain`— sin duplicar campos por parte
(`20260821200000_diagnosis_joins_the_registry.sql:17-33`). La unicidad ya lo
incluye: `(tenant_id, subject_type, subject_id, spec_definition_id,
coalesce(subject_scope,''))` (`:37-42`). Hoy lo usa el diagnóstico para
`job_bike` (`20260821210000_backfill_diagnosis_facts.sql:91,116`).

**Toda la ruta de producto ignora a propósito los hechos con alcance**, que es
la propiedad que hace segura la propuesta:

- el escritor borra y reescribe sólo `subject_scope is null`
  (`20260906190000_product_spec_structured_rows.sql:434,468,484`);
- el validador de producto, la carga útil y los hechos sin asignar filtran igual
  (`20260906070000…:385`, `:149`; `20260906160000_product_spec_template_binding.sql`,
  `spec_unassigned_facts_internal_v1`);
- el espejo hacia `product_spec_values` **salta** los hechos con alcance
  (`20260906170000_product_spec_legacy_boundary.sql:560,576`), así que no llegan
  al espejo heredado ni a lo que se publica;
- la lectura por lotes del consumidor de compatibilidad,
  `get_product_spec_contexts_v1`, sólo arma el mapa del producto entero.

**El validador de fichas es puro y recibe la plantilla.**
`validateProductSpecDraft({template, values, reference, brand, model,
manufacturerSku})` (`product_spec_contract.dart:176-183`) no depende de
producto, categoría ni persistencia, y ya emite `reference_identity`
(`:199-206`) y `reference_conflict` (`:207-244`). Su gemelo de servidor,
`spec_validate_draft_internal_v1(template_id, facts, reference_id, brand,
model, sku)`, tiene la misma firma.

**Un vínculo de filas no cruza plantillas.** El contrato de `row_coherence`
exige que `field` y `target_field` sean tablas de la **misma** ficha
(`product_spec_coherence.dart:107-131`). Por eso ninguna tabla del kit puede
«apuntar» a una ficha de otra familia: lo que falta no es un vínculo más, es un
sujeto donde colgar la otra ficha.

**Una fila de tabla ya tiene identidad estable en el editor.** El editor asigna
`Uuid().v4()` a cada fila nueva y edita y borra **por id**
(`product_spec_rows_field.dart:102-105`, `:200-221`). El servidor exige formato
y unicidad (`20260906190000…:135-142`) pero **no** que un id sobreviva de un
guardado a otro. Una tabla de filas se guarda como un solo hecho, en
`value_json` (`:384`, `:482`).

**Qué usa `kit_members` y cómo.** Sus seis columnas publicadas son `member_role`,
`family`, `quantity`, `position`, `identity_brand` e `identity_model`; ninguna
es un dato técnico. En el último catálogo completo integrado,
`all-family-wss-residual-integrated-2026-09-07.json`, la usan **23 plantillas**; en las
37 integradas está activa como contenido en `brake_lever`,
`hydraulic_disc_brake`, `mechanical_disc_brake`, `rim_brake` y `drivetrain_kit`,
y es legacy en `crankset`, `shifter` y `tubeless_consumable`. `drivetrain_kit`
cuelga de sus filas tres tablas enlazadas: evidencia, interfaces y destinos por
miembro.

Tres mediciones sobre ese mismo catálogo completo que condicionan el diseño:

1. **El vocabulario de `family` es exactamente el conjunto de las 105 claves de
   plantilla.** Un miembro con familia declarada ya nombra una ficha resoluble.
2. **La clave de plantilla no siempre es su familia técnica.**
   `hydraulic_disc_brake` y `mechanical_disc_brake` pertenecen a
   `complete_brake`. Las referencias se buscan por `technical_family`
   (`20260907023000_product_spec_research_snapshot.sql:88-97`); la fila del kit
   nombra la **clave**. Quien resuelva un perfil tiene que pasar de una a otra.
3. **22 de las 23 plantillas con `kit_members` admiten su propia familia como
   miembro**; sólo `light` la excluye. Sin un límite explícito, un perfil podría
   anidar otro kit adentro, y ése adentro otro.

## 3. Propuesta

### 3.1 El sujeto: el producto kit, acotado a la fila del miembro

Los hechos del perfil se guardan en `spec_facts` **sin tabla nueva de hechos**:

| columna | valor |
|---|---|
| `subject_type` | `'product'` |
| `subject_id` | el producto kit |
| `subject_scope` | `'kit_members:<id de fila>'` |
| `spec_definition_id` | una definición **de la ficha de la familia del miembro** |

Con eso se heredan sin escribir nada: la unicidad por parte, la guarda de tenant
y de producto, la inmutabilidad de identidad —un hecho no puede mudarse de un
miembro a otro—, el revisionado del producto kit, y la **invisibilidad** para el
espejo, la tienda y la lectura de compatibilidad. Una medida de un miembro nunca
se vuelve medida del kit por accidente, porque ningún lector existente la ve.

La gramática del alcance es `<clave del campo dueño>:<id de fila>`, con **un
solo nivel**. El prefijo es la clave del campo y no la palabra «miembro», para
que una segunda tabla de contenido futura no colisione.

### 3.2 La plantilla: la de la familia, resuelta por clave

La ficha del perfil es la plantilla cuya `key` es la `family` de la fila. Se
valida con el **mismo** `validateProductSpecDraft` y su gemelo SQL, pasando esa
plantilla, los valores acotados, la referencia del miembro si la hay, y la
identidad declarada en la fila. No hay un motor nuevo ni una segunda copia de
reglas: los `row_conditions`, pares ordenados y cardinalidades de la familia
corren tal cual.

La referencia se busca por la `technical_family` **de esa plantilla**, no por la
clave de la fila, para cubrir el caso medido de los frenos de disco.

### 3.3 La cabecera: una fila por perfil

Hace falta un registro chico, que no es un motor sino persistencia con llaves:

```text
product_kit_member_profiles
  tenant_id            uuid  not null  → tenants
  product_id           uuid  not null  → products (mismo tenant)
  member_field_key     text  not null  -- 'kit_members'
  member_row_id        text  not null  -- formato de id de fila
  template_id          uuid  not null  → spec_templates (activa)
  reference_id         text  null      → product_spec_references
  created_at, updated_at
  unique (tenant_id, product_id, member_field_key, member_row_id)
```

Por qué no basta con los hechos solos:

- la **referencia** necesita llave foránea real; como texto dentro de una
  celda no tendría garantía;
- la **plantilla fijada** permite detectar que alguien cambió la familia de la
  fila conservando su id, y exigir que el perfil viejo se borre antes de
  reinterpretarse;
- **encontrar huérfanos** pasa a ser un join, no un análisis de cadenas.

`products.spec_reference_id` **no** se usa para miembros: es un solo valor, es
la identidad del kit, y apuntarlo a la referencia de una pieza dispararía
`reference_identity` contra la marca y modelo del kit.

### 3.4 Contrato de lectura

`get_product_kit_member_profiles_v1(p_product_id uuid) returns jsonb`,
`security definer`, del tenant autenticado, en la misma instantánea MVCC que la
lectura del kit. Para cada fila de `kit_members` devuelve:

- `member_row_id`, `family` y la cabecera si existe;
- `template` con **la misma forma** que `get_product_spec_editor_context_v2`,
  para que el cliente reutilice `decodeProductSpecEditorContext`;
- `values` con `read_schema_version: 2` y transporte decimal exacto;
- `reference` con la forma de `get_product_spec_references_v2`;
- `issues` del validador compartido, marcadas con el `member_row_id`.

Una fila sin familia, o con una familia sin plantilla activa, se devuelve **sin
perfil admisible** y con su motivo. No se inventa una ficha genérica.

### 3.5 Contrato de guardado

El guardado del perfil va **en la misma transacción que el guardado del kit**,
no en una llamada aparte, para que el `spec_revision` del producto proteja las
dos cosas a la vez. Se amplía el guardado actual con un argumento opcional
`p_member_profiles jsonb`, o se agrega un RPC que exija la revisión esperada y
reutilice `product_spec_save_receipts`. En ambos casos, en este orden:

1. Parsear las filas **ya guardadas** de `kit_members`.
2. Rechazar un perfil cuyo `member_row_id` no está entre esas filas.
3. Rechazar un perfil cuya plantilla no es la de la `family` actual de la fila.
4. **Barrer huérfanos por existencia de fila, no por ausencia en el payload**:
   borrar cabecera y hechos acotados de cada fila que ya no existe o cambió de
   familia. Un cliente viejo que no envía perfiles no borra nada.
5. Excluir de la proyección los campos de la plantilla del miembro con rol
   semántico `contents` o `legacy` —ver §4— y rechazar si llegan.
6. Escribir los hechos con el mismo camino por definición que usa el producto,
   pero con alcance; mezclar con los `fact_values` de la referencia elegida,
   como ya hace `spec_write_payload_internal_v2`.
7. Validar cada perfil con `spec_validate_draft_internal_v1`. Un bloqueo en
   cualquier perfil aborta el guardado entero.
8. Recibo idempotente: misma clave y mismo contenido devuelve el resultado;
   misma clave y contenido distinto es `23505`.

## 4. Límites de recursión y de alcance

- **Un nivel.** Un perfil nunca contiene perfiles. El alcance admite exactamente
  un `<campo>:<fila>`, y lo impone una restricción de tabla, no una convención.
- **Sin contenido dentro del perfil.** Del perfil se excluyen los campos con rol
  semántico `contents`: `kit_members`, platos incluidos, pedalier suministrado y
  equivalentes. Un volante que viene dentro de un kit declara su largo de biela
  y su unión con el eje; sus platos, si vienen, son **filas del kit**, no del
  volante. Así el contenido se declara una vez y en un solo nivel.
- **Si un miembro es a su vez un juego que se vende, es un producto.** Ese caso
  va por `product_set_components`, no por perfiles.
- **La cantidad no fabrica unidades.** Una fila con `quantity: 2` tiene un
  perfil que describe a las dos piezas iguales. Si difieren —izquierda y
  derecha— son dos filas, que es como `kit_members` ya lo exige con `position`.
- **Activación por plantilla, no por lista en código.** La capacidad se enciende
  con una marca en el contrato de la plantilla dueña. Recomiendo empezar sólo en
  `drivetrain_kit`, y dejar explícitamente fuera por ahora:
  - `light`, que ya tiene dueño tipado de sus miembros,
    `light_member_configurations`; encenderla crearía dos dueños;
  - `bicycle` y `wheel`, que son conjuntos completos con sus propias tablas de
    ocurrencias; un perfil por miembro ahí convertiría la ficha de la bici en
    una suma de fichas;
  - los frenos completos, hasta revisar su relación con
    `brake_assembly_configurations`.
- **Tenant.** Hechos y cabeceras son del tenant; referencias y plantillas siguen
  la resolución existente, global o del tenant.

## 5. Alternativas descartadas

| Alternativa | Por qué no |
|---|---|
| Devolver medidas escalares al kit | Es el defecto que F2 ya evitó: un kit con dos piezas de la misma familia no guarda dos valores, y el espejo, la tienda y la compatibilidad lo leerían como dato del kit. |
| Tablas anchas por kit con columnas copiadas de cada familia, al estilo de `light_member_configurations` | Copia definiciones sin sus reglas: una celda no ejecuta `row_conditions`, pares ordenados ni cardinalidades de la familia. Multiplica 23 plantillas por las familias posibles y se desincroniza en la primera edición de una familia. Sirve para una familia con miembros acotados, no como mecanismo general. |
| Crear productos de inventario para cada miembro y enlazarlos con `product_set_components` | `save_product_set_aggregate` identifica cada componente por SKU, lo deja con `track_stock = true` y `purchase_treatment = 'inventory'`, y en el alta copia categoría, marca y proveedor del padre (`20260721190000…`, alta y actualización de componentes). Fabrica inventario ficticio, y como un componente pertenece a un solo juego, una pieza igual en dos kits no cabe. Es correcto sólo cuando la pieza se vende de verdad por separado. |
| Un `subject_type = 'kit_member'` nuevo | `subject_id` tendría que apuntar a una tabla que no existe; la guarda de tenant, la guarda de producto y el revisionado están atados a `product`. Se pierde la protección de revisión del kit y hay que duplicar las tres guardas. |
| Guardar la ficha del miembro dentro de la celda de `kit_members` | El esquema publicado está congelado por la guarda del publicador, y un JSON anidado se salta la llave foránea de opciones de `spec_fact_values`. |
| Apuntar `products.spec_reference_id` del kit a la referencia de un miembro | Un solo valor, identidad equivocada, `reference_identity` inmediato. |
| Resolver la referencia del miembro por coincidencia de marca y modelo | Los nombres no son joins. La referencia se **elige** y después se valida con `matchesIdentity`. |
| Un motor de reglas anidado nuevo | El validador existente ya es puro y recibe la plantilla. Duplicarlo abriría la divergencia entre Dart y SQL que costó varias rondas cerrar. |

## 6. Prerrequisitos, en orden

1. **Comprobar en producción, en sólo lectura, que no hay hechos de producto con
   `subject_scope` no nulo.** No lo leí. Si los hay, deciden la migración antes
   de agregar la restricción.
2. **Restringir la gramática** para sujetos de producto:
   `subject_type <> 'product' or subject_scope is null or subject_scope ~
   '^[a-z][a-z0-9_]*:[A-Za-z0-9_-]{1,80}$'`. El diagnóstico sobre `job_bike`
   queda intacto.
3. **Contrato de estabilidad de id de fila.** El editor ya conserva ids; falta
   que el servidor trate la desaparición de un id como borrado del perfil y el
   cambio de familia con el mismo id como invalidación. **No verifiqué** si la
   edición masiva o la importación regeneran ids: hay que comprobarlo antes de
   activar, porque un id regenerado borraría perfiles válidos.
4. **Resolución clave → familia técnica** en un único ayudante SQL y su gemelo
   Dart.
5. **Lector de plantilla sin producto ni categoría.**
   `get_product_spec_editor_context_v2` exige uno de los dos; el perfil necesita
   cargar la ficha de una familia por clave.
6. **Decisión sobre las tablas por miembro de `drivetrain_kit`.** Cuando exista
   el perfil, `drivetrain_kit_member_interfaces` y
   `drivetrain_kit_member_fitments` pasan a ser un segundo dueño de lo que la
   ficha de la familia ya tipa. Recomiendo retirarlas a legacy al activar, y
   conservar `drivetrain_kit_member_evidence` como identidad y fuente de la
   fila, o absorberla en la cabecera. Es decisión de Root.
7. **Auditoría de adopción y instantánea de investigación** deben contar hechos
   acotados y cabeceras. La instantánea ya revisa tenant sin filtrar alcance
   (`20260907023000…:117-126`); la auditoría de adopción no los ve hoy, y un
   huérfano quedaría invisible.
8. **Distribución del cliente.** El barrido por existencia de fila hace inocuo a
   un cliente viejo, pero el editor de perfiles no debe mostrarse hasta que el
   RPC exista en producción.

## 7. Consumidores afectados

| Consumidor | Qué pasa | Qué hay que garantizar |
|---|---|---|
| `get_product_spec_contexts_v1` → `bike_product_compatibility_service.dart:261-263` | Sin cambio: sólo ve el producto entero | Que siga sin ver miembros. Si algún día los consume, por una lectura aparte y un mapa por miembro, nunca fusionado. |
| `ProductSpecRelation.evaluate` | Evalúa una configuración por vez (`product_spec_relation.dart:81-82`) | Evaluar **cada** perfil por separado; nunca un mapa con dos miembros mezclados. |
| Espejo `product_spec_values` y ficha pública | Sin cambio: el disparador salta los hechos acotados | Regresión explícita. No leí el cuerpo de `get_public_product_technical_specs`; hay que confirmar que no lee `spec_facts` directo sin filtro. |
| `get_product_ids_for_spec_family_v1` → `smart_job_recommendation_service.dart:315` | Sin cambio: resuelve por la ficha del producto | Un kit con una cadena adentro **no** es un producto de familia `chain`. |
| Matcher de duplicados e identidad | Sin cambio | La identidad declarada del miembro nunca se une al catálogo. |
| `product_set_components` y `save_product_set_aggregate` | Sin cambio | Siguen siendo el camino de una pieza vendida por separado. |
| Editor de producto | Gana una sección de perfiles por fila | Reutilizar `decodeProductSpecEditorContext` y el editor de campos; no un editor paralelo. |
| Compiladores y publicador | Una marca por plantilla y la exclusión de `contents` | Los casos de §8 dentro del arnés parametrizado. |

## 8. Casos adversariales mínimos

| # | Situación | Resultado exigido |
|---|---|---|
| A1 | Dos miembros de la misma familia con medidas distintas | Dos perfiles independientes; el contexto de compatibilidad del kit no cambia |
| A2 | Perfil con un `member_row_id` que no está en `kit_members` | Bloqueo `member_profile_row_missing` |
| A3 | Se borra una fila del kit | Cabecera y hechos acotados desaparecen en el mismo guardado; la auditoría no encuentra huérfanos |
| A4 | Se cambia la familia de una fila conservando su id | El perfil anterior se invalida y no se reinterpreta con la plantilla nueva |
| A5 | Un cliente viejo guarda el kit sin enviar perfiles | Los perfiles se conservan mientras sus filas existan |
| A6 | Fila sin familia o con familia sin plantilla activa | Sin perfil admisible; pendiente, no bloqueo del kit |
| A7 | La plantilla del miembro tiene campos de contenido | Excluidos de la proyección; rechazados si llegan |
| A8 | Alcance anidado, `kit_members:r1/kit_members:r2` | Rechazado por la restricción de gramática |
| A9 | Miembro `hydraulic_disc_brake` con referencia de `complete_brake` | Aceptado; con referencia de otra familia técnica, `reference_identity` bloqueante |
| A10 | Referencia elegida y valor del miembro distinto | `reference_conflict` sólo en ese perfil |
| A11 | Hecho de miembro frente a espejo, tienda y contexto de compatibilidad | Ausente en los tres |
| A12 | `get_product_ids_for_spec_family_v1('chain')` sobre un kit con cadena | No devuelve el kit |
| A13 | Hecho acotado apuntando a un producto de otro tenant | Rechazado por la guarda existente |
| A14 | La misma pieza se vende sola y además viene en un kit | El kit no se enlaza por texto; los hechos del producto no se copian al perfil |
| A15 | Perfil pedido para un miembro de `light` | Rechazado mientras `light_member_configurations` sea dueño |
| A16 | Evaluación de relación con dos perfiles | Dos evaluaciones; un mapa mezclado es error |
| A17 | `quantity: 2` de piezas idénticas | Un perfil para la fila; no se inventan unidades |
| A18 | Reenvío con la misma clave de operación | Mismo resultado; con otro contenido, `23505` |

## 9. Qué no verifiqué

- Si producción tiene hoy hechos de producto con alcance no nulo.
- Si la edición masiva y la importación conservan los ids de fila.
- El cuerpo de `get_public_product_technical_specs`: me apoyo en el comentario
  y en el disparador de espejo, no en su lectura.
- La relación entre perfiles y las tablas de configuración de los frenos
  completos.

Nada de esto cierra F2. Queda listo para que Root decida la cabecera, el orden
de activación y el destino de las tablas por miembro de `drivetrain_kit`, y
para que los casos de §8 se ejecuten antes de dar la ficha de kits por
terminada.

---

# Adjudicación de tres discrepancias — 2026-09-14

Root verificó en producción, a las 19:37 UTC, que hay **cero** hechos de
producto con alcance, y adoptó la base `spec_facts` + `subject_scope` con el
mismo validador por familia. Planteó tres discrepancias. Sólo lectura de código
y catálogo, más una sonda Dart fuera de la suite en
`.tmp/product-spec-catalog/member-profile-compat-gate-probe.dart`. No toqué
código, producción ni runtime. **F2 sigue abierto.**

## D1 · Borrar al quitar o cambiar una fila: acepto la corrección

**Mi paso 4 de §3.5 era destructivo y lo retiro.** Barría cabecera y hechos
cuando la fila desaparecía o cambiaba de familia. Eso borra observaciones reales,
y como `spec_fact_readings.fact_id` referencia al hecho con `on delete cascade`
(`20260831260000_the_name_is_evidence_the_server_checks.sql:46-48`), también
borra las lecturas que lo respaldan. Además ataba el perfil al id de fila: una
importación que regenere ids habría borrado todos los perfiles de golpe. El
editor conserva ids (`product_spec_rows_field.dart:102-105`, `:200-221`); el
riesgo estaba en importaciones y ediciones masivas, que no verifiqué.

**Acepto la decisión preliminar de Root** —cabecera con UUID propio, identidad
congelada, alcance `member:<profile_uuid>`, archivo explícito que conserva
hechos y lecturas, guardado viejo que conserva y bloquea si deja un perfil
huérfano, y cambio de familia, marca o modelo sólo archivando antes—, con seis
precisiones que la vuelven completa:

1. **Identificar no es cambiar.** `identity_brand` e `identity_model` son
   opcionales en la columna publicada. Congelar un vacío obligaría a archivar
   el perfil cuando después se lea el envase y aparezca la marca: la misma pieza
   física quedaría partida en dos perfiles, con sus observaciones repartidas.
   Regla: **vacío → valor** es identificación, admitida y con su fuente;
   **valor → otro valor** es cambio, y archiva. La familia no tiene estado
   vacío, porque sin familia no hay ficha.
2. **Hace falta re-vincular, no sólo bloquear.** Si la cabecera sigue apuntando
   a una fila del kit, una importación que regenere ids deja **todos** los
   guardados bloqueados para siempre: falla cerrado, pero sin salida. Se
   necesita una operación explícita que re-vincule un perfil a una fila nueva,
   exigiendo igualdad de identidad. Nunca automática.
3. **Igual identidad no identifica la fila.** Un kit con cáliper delantero y
   trasero del mismo modelo, o dos platos iguales, tiene dos filas con la misma
   identidad. Re-vincular exige elegir la fila; la igualdad de identidad es
   necesaria pero no suficiente, y una coincidencia ambigua bloquea.
4. **Cambiar de referencia no es cambiar de identidad.** Elegir otra edición de
   catálogo para el mismo miembro —otro id de referencia— revalida, y puede dar
   `reference_conflict`; no obliga a archivar.
5. **Lo archivado queda fuera de toda lectura activa.** Los lectores de producto
   ya ignoran todo hecho con alcance; los lectores de perfiles tienen que unir
   por cabecera y excluir lo archivado. La unicidad no choca, porque el alcance
   lleva el UUID del perfil. La auditoría de adopción cuenta archivados aparte.
6. **El bloqueo del cliente viejo tiene que decir qué hacer.** Un guardado que
   dejaría huérfano un perfil activo bloquea nombrando el perfil y la acción
   —archivar o re-vincular—, no con un error de forma.

Casos que reemplazan A3, A4 y A5:

| # | Situación | Resultado exigido |
|---|---|---|
| D1-a | Se quita la fila de un perfil activo | Bloqueo que nombra archivar o re-vincular; hechos y lecturas intactos |
| D1-b | Importación con ids regenerados | Bloqueo sin pérdida; re-vincular explícito lo resuelve |
| D1-c | Marca vacía que después se identifica | Mismo perfil, identificación con su fuente; sin archivo |
| D1-d | Marca KMC cambiada a SRAM | Exige archivar antes de crear el perfil nuevo |
| D1-e | Dos filas de igual identidad y re-vinculación | Exige elegir la fila; coincidencia ambigua bloquea |
| D1-f | Nueva edición de referencia para el mismo miembro | Revalida sin archivar |
| D1-g | Perfil archivado frente a los lectores | Invisible para lectores activos; visible para auditoría |

## D2 · Excluir `contents`: retiro la regla, rompe las propias fichas

**Tenías razón.** Lo medí sobre el catálogo integrado de las 37
(`original-successors-integrated-catalog-2026-09-08.json`): tomé cada plantilla
y marqué como legacy todos sus campos activos con rol semántico `contents`, que
es literalmente lo que yo proponía, y pasé el contrato por el mismo
`validate_contract` del compilador. **Las nueve plantillas probadas quedan
rechazadas:**

| Plantilla | Motivo del rechazo |
|---|---|
| `crankset` | `chainline_mm` pierde su prerrequisito `spindle_included` |
| `bottom_bracket` | `spindle_interface` pierde su prerrequisito `includes_spindle` |
| `crank_arm` | extremo de vínculo retirado: la interfaz por brazo del cierre H5 |
| `chainring` | extremo de vínculo retirado: desplazamiento, emparejado y declaraciones por plato |
| `chain_guide` | extremo de vínculo retirado: pesos del conjunto armado |
| `hydraulic_disc_brake` | condiciones de fila sin tabla activa |
| `shifter` | condiciones de fila sin tabla activa |
| `derailleur_pulley` | condiciones de fila sin tabla activa |
| `hub` | condiciones de fila sin tabla activa |

La otra forma de «excluir» —dejar los campos activos y no enviar sus valores—
tampoco sirve: los campos que dependen de ellos quedan pendientes para siempre y
los vínculos por miembro nunca resuelven. **Ninguna proyección parcial conserva
el mismo validador.**

**Por qué la regla estaba mal.** El rol `contents` mezcla tres cosas:
ocurrencias del envase —`kit_members`, `shifter_units`, `crank_arm_units`—,
datos de suministro de los que dependen campos intrínsecos —`spindle_included`,
`includes_spindle`, `included_chainring_count` y, en el catálogo completo,
`grip.sold_as`— y cantidades por paquete. Yo lo leí como si fuera sólo lo
primero.

**Límite propuesto, con el mismo validador:**

1. **La ficha completa, sin proyección.** El perfil se valida contra la
   plantilla publicada de su familia tal cual, con todos sus campos activos.
2. **Un nivel por cabecera, no por campos.** El `member_field_key` de una
   cabecera tiene que ser un campo activo de la ficha **del producto kit**, y
   una cabecera nunca tiene un perfil como padre. El guardado rechaza la
   cabecera que nombre un campo de otra ficha. El `kit_members` o las tablas de
   unidades de la ficha del miembro son datos declarativos de ese perfil y
   nunca generan perfiles.
3. **Lo intrínseco sigue siendo intrínseco.** Un volante dentro de un kit
   conserva `included_chainring_count`, `chainring_teeth_rows` y su
   cardinalidad. Esos platos no son filas del kit ni productos, y no necesitan
   perfil propio; la relación de H5 por brazo o por plato queda viva.
4. **La cantidad cuenta lo que el perfil describe.** Si el perfil declara un
   envase de par o de juego —`crank_side: Par`, `shifter_position: Par`,
   `chainring_package_kind: Juego`—, la `quantity` de la fila del kit cuenta
   envases, no piezas. Una discrepancia es revisión pendiente, no un valor
   deducido.
5. **Doble declaración, como pendiente documentado.** Que el kit liste una
   pieza en su fila y además la ficha del miembro la liste en su propio
   contenido se revisa; el motor no la deduplica.

Casos que reemplazan A7:

| # | Situación | Resultado exigido |
|---|---|---|
| D2-a | Volante miembro con platos y línea de cadena | Validado con su ficha completa; sin bloqueo por prerrequisito |
| D2-b | Brazos en par como miembro, con interfaz por brazo | El vínculo resuelve dentro del perfil |
| D2-c | Cabecera cuyo campo pertenece a la ficha del miembro | Rechazada: un solo nivel |
| D2-d | Fila del kit `quantity: 2` y perfil `crank_side: Par` | Revisión pendiente de cantidad; nada deducido |

## D3 · Consumidor de compatibilidad: una regresión concreta, reproducida

Revisé los archivos vigentes
`bike_product_compatibility_service.dart` (`e7bae053…`) y
`bike_product_compatibility_service_test.dart` (`be58db51…`).

**El cambio del kit en sí está bien.** Tanto el despacho por familia
(`:401-402`) como el detallado (`:574-575`) mandan `drivetrain_kit` a
`_assessDrivetrainKitCompatibility()`, que ya no hereda datos de biela. Cadena y
`bike_chain` siguen llegando a sus propios evaluadores (`:374-376`, `:518-520`).

### R1 · Un pendiente no bloqueante apaga todos los veredictos (alta)

La compuerta nueva en `:187-196` devuelve precaución para **cualquier** producto
con **cualquier** issue salvo `unmapped`, **antes** de toda evaluación por
familia, y sin mirar `blocking`.

El servidor sí emite issues no bloqueantes —`required_missing`,
`row_incomplete`, `row_reference_pending` con `'blocking',false`
(`20260906170000_product_spec_legacy_boundary.sql:74,80`;
`20260907020000_product_spec_row_coherence.sql:151,423,440,468`)— y
`get_product_spec_contexts_v1`, definida sólo en
`20260906070000_product_spec_contract.sql`, entrega el arreglo completo sin
filtrar. Con la adopción de hoy —863 de 868 productos con datos pendientes—
prácticamente todo producto cae en la misma precaución genérica, y **los
veredictos incompatibles dejan de ser alcanzables**.

Sonda, con el pendiente exacto que emite el servidor:

| caso | entrada | esperado | obtenido |
|---|---|---|---|
| P3 control | maza delantera 110 mm frente a bici de 100 mm, sin issues | `incompatible` | **`incompatible`** ✓ |
| P1 | lo mismo + un `required_missing` con `blocking: false` | `incompatible` | **`caution`** ✗ |
| P2 | `drivetrain_kit` + el mismo pendiente | detalle con «cada componente» | **«Ficha con datos pendientes de revisión»** ✗ |

`00:02 +1 -2: Some tests failed.`

**Por qué la suite queda verde:** sólo dos pruebas pasan `__spec_issues`, ambas
con códigos de tipo bloqueante —`template_unavailable` y `reference_conflict`—,
y las dos pruebas del kit no pasan issues. Ninguna combina un veredicto decisivo
con un pendiente no bloqueante.

**Dirección de la corrección** (el código es tuyo): que la compuerta global
actúe sólo sobre issues con `blocking` distinto de `false`, más
`template_unavailable`; que los pendientes no bloqueantes anoten el detalle sin
reemplazar el veredicto; y dos regresiones, un incompatible con un pendiente
no bloqueante y un kit con un pendiente.

### R2 · La compuerta de cadena queda sombreada (baja)

`:609` sólo se alcanza cuando el único issue es `unmapped`, porque cualquier otro
ya salió en `:187`. En ese caso responde «revisa los conflictos o datos
pendientes de su ficha» a un producto que no tiene ficha. Al corregir R1 conviene
alinearla con el mismo criterio de `blocking`.

**Qué no verifiqué:** el analyzer ni la corrida de las 83 pruebas —ésa es tu
evidencia—. Corrí sólo la sonda, que queda fuera de la suite.

## Estado

D1 y D2 quedan adjudicados a favor de Root con las precisiones de arriba. D3
tiene una regresión alta reproducida y una baja. **F2 sigue abierto**: falta
implementar la cabecera y el guardado, correr los casos de §8 con los
reemplazos D1 y D2, y corregir R1 antes de que el consumidor dependa de
perfiles.
