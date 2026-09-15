# Vínculo producto → plantilla: revisión de integridad del borrador — Claude, 2026-09-06

Objeto: `supabase/migrations/20260906160000_product_spec_template_binding.sql`,
leído en tres versiones mientras Codex lo editaba; las líneas citadas son de la
última, 3244 líneas, MD5 `593c763cabf96de9fec55e14fb018ffa`. Si el archivo vuelve a cambiar,
cada cita lleva además el texto ancla para localizarla. Compilado sólo en PostgreSQL local; producción no lo tiene. También
leí `supabase/tests/product_spec_template_binding.sql` (95 líneas, en curso) y
comprobé en local, sólo lectura, columna, FK, índice, propietario de la vista,
volatilidad y ACL reales. No edité código ni SQL; no ejecuté mutaciones.

## 0. Veredicto

El diseño hace lo acordado: la identidad del producto posee la plantilla, la
categoría queda como respaldo, un vínculo explícito inválido **no** cae a la
categoría, los hechos fuera de plantilla se conservan con procedencia,
`confirmed` y lecturas, y el comando deja recibo con motivo y actor. La
asignación es estructural: no toca `source`, `confirmed`, referencias ni
claims, y ningún lector la convierte en aprobación mecánica.

Hay **tres errores concretos** que corregir antes de producción y varios
huecos de integración que no bloquean la migración pero sí la adaptación de
consumidores.

| # | Error | Dónde | Evidencia |
|---|---|---|---|
| E1 | `spec_template_id` y `spec_reference_id` se pueden escribir directamente por PostgREST, rodeando el comando: sin recibo, motivo, actor ni guardia de revisión | `products`, política `products_update` para `public` | local: `has_column_privilege('authenticated','products','spec_template_id','update') = true`, igual para `spec_reference_id` y `spec_revision`; la migración no revoca nada sobre la tabla |
| E2 | El lector del editor lanza excepción cuando la plantilla explícita no está disponible, y el guardado atómico también: un producto cuya plantilla se desactivó queda bloqueado para cualquier guardado por comando, incluido el comercial, y el formulario no puede abrir la ficha justo cuando hay que corregirla | `get_product_spec_editor_context_v1` línea 72 («La ficha asignada no está disponible», 23514); `spec_validate_product_internal_v1` línea 213 («Plantilla no disponible», 42501) llamado desde `save_product_with_specs_v1` | la vista y el snapshot devuelven `binding_source='explicit_unavailable'` como estado; el editor no |
| E3 | El consumidor de taller en Dart sigue decidiendo la familia por la caché de categoría, así que un producto revinculado se evalúa con la familia de su categoría mientras sus hechos siguen la plantilla nueva. En el servidor, la versión actual ya emite `template_unavailable` para el vínculo no disponible (línea 188); la versión anterior lo marcaba `unmapped` | `bike_product_compatibility_service.dart` 177–180 (sólo `unmapped` se ignora) y 283–374 (`_ensureCategoryTechMappings`) | el contexto trae `__technical_family`, `__template_key` y `__binding_source`, y el consumidor no los lee todavía |

## 1. Lo verificado, propiedad por propiedad

| Propiedad | Cómo lo hace | Líneas | Juicio |
|---|---|---|---|
| Propiedad por identidad con respaldo de categoría | `spec_template_resolution_internal_v1(tenant, categoría, explícita)`: si hay explícita, sólo ella; si no, el mapeo activo; en ambos casos exige plantilla activa y global o del tenant | 9–17; vista 23–31 | correcto |
| Arbitraje de explícita inválida, inactiva o de otro tenant | el resolvedor devuelve nulo; la vista rotula `explicit_unavailable`; `assign` rechaza asignarla (42501); validar y guardar rechazan operar con ella | vista 27–29; `assign` 139–140; validación 213; guardado 338–343 | correcto como arbitraje; ver E2 por el efecto sobre guardados comerciales |
| ACL y SECURITY DEFINER | vista revocada a `public/anon/authenticated`, propietario `postgres`; resolvedor y funciones internas privadas; `assign`, `get_product_spec_bindings_v1` y el editor sólo `authenticated`; `get_public_product_technical_specs` sigue en `anon` y lee la vista con privilegios del definidor; `search_path` fijo en todas | `revoke`/`grant` inmediatamente después de cada función y de la vista | correcto; confirmado en local (`view_sel_authenticated=false`, `fn_resolution_authenticated=false`, `fn_assign_anon=false`) |
| Idempotencia entre comandos | `assign` comparte tabla de recibos y espacio de candado `:product_spec_save:` con el guardado; misma clave con otro hash → 23505; replay devuelve el resultado guardado | 126–131 | correcto; el hash omite revisión y timestamp esperados a propósito: un reintento con expectativas distintas es el mismo comando |
| Concurrencia | candado `:spec_fact:<producto>` y `for update` sobre el producto, iguales a los del guardado; revisión y `updated_at` esperados; el trigger BEFORE sube `spec_revision` al cambiar `spec_template_id` | 134–135; trigger `spec_product_revision_internal_v1` (537) | correcto; el trigger neutraliza además un `spec_revision` escrito a mano |
| Hechos, lecturas y `false` preservados al reasignar | `assign` no escribe hechos; la validación usa sólo los campos activos (`spec_active_product_values_internal_v1`); los demás salen en `unassigned_facts` con valor, `source`, `confirmed`, `updated_at` y lecturas; el escritor legado exige que las definiciones pertenezcan a la plantilla resuelta y por eso no puede borrar un huérfano | `spec_unassigned_facts_internal_v1`; `spec_active_product_values_internal_v1` (237); guardia del escritor legado (435) | correcto; `spec_write_payload_internal_v2` no cambia y sigue borrando sólo definiciones de la plantilla |
| Referencia incompatible | la validación del borrador añade `reference_identity` sin `blocking` → bloqueante → 23514 y la transacción del `assign` revierte | 237–243 y validador existente | correcto; falta prueba (§3) |
| Guardas de escritores | `save_product_with_specs_v1` resuelve con la explícita del producto y la categoría del payload o la almacenada, exige igualdad con `p_template_id` y versión; `spec_template_id` no está en la lista blanca del patch | 338–343; lista blanca en 287 | correcto: el vínculo sólo cambia por `assign` **o por escritura directa** (E1) |
| Lectores tienda, taller, snapshot, búsqueda | los cuatro usan la vista o el resolvedor; búsqueda v4–v7 toman la familia del producto de la vista y el alcance por categoría admite `category_id` en el alcance **o** familia en las familias del alcance | joins a la vista en 84, 171, 191, 253 y en las cuatro búsquedas; alcance por categoría en 1992–1998 | correcto; un producto revinculado no desaparece de una búsqueda por su categoría |
| Estructural vs mecánica | el recibo guarda `review_reason`, `actor_id`, antes y después; no se escribe `confirmed`, `source`, referencia ni claim; la tienda no publica `binding_source` | 146–150 | correcto |

## 2. Huecos de integración (no bloquean la migración)

- **G1 Compras.** `supply_need_eligible_products_internal_v1`
  (`20260817160000`, líneas 309–345) elige candidatos por categoría y lee los
  campos con la plantilla de la categoría de la necesidad. Un producto con
  vínculo explícito de otra familia entra por categoría y se juzga con campos
  ajenos. Decidir: candidatos y campos por la vista cuando el producto tiene
  vínculo. `supply_need_stock_candidates_v1` lee `spec_facts` directamente y no
  se ve afectado; `create_supply_need_batch_v2`, `replace_supply_need_v1`,
  `assistant_infer_technical_predicates_internal_v1` y
  `assistant_inspect_inventory_schema_v3` derivan por categoría sin producto:
  correcto.
- **G2 Editor y formulario Dart.** `SpecEngineService.getTemplateForCategory`
  (239–247) y `_loadSpecTemplate(categoryId)` (`product_form_page.dart`
  1259–1330) indexan el borrador por categoría; deben pasar a
  `get_product_spec_editor_context_v1(product, categoría del borrador)` y
  mostrar `unassigned_facts` y `binding_source`. La referencia se sigue
  eligiendo por `template.technicalFamily` (1289, 1391, 7421): con el vínculo
  eso ya es la familia correcta.
- **G3 Recomendación de trabajos.** `get_product_ids_for_spec_family_v1`
  reemplaza la búsqueda de categorías `chain` (`smart_job_recommendation_service.dart`
  310–325); filtra `product_type='product'`: verificar que los juegos con
  `is_set` no queden fuera si alguna vez se recomiendan.
- **G4 Read-backs históricos.** `readback.sql` (líneas 2–3) fija md5 de
  `get_product_spec_snapshot_v1`, `get_product_spec_contexts_v1` y
  `spec_product_revision_internal_v1`, que esta migración reescribe; el
  `--verify` nuevo debe traer los md5 nuevos y los documentos marcar los
  anteriores como reemplazados. No vi un `--verify` de esta migración; sólo
  `numeric-domain-verify.sql`.
- **G5 `unassigned_facts` con plantilla nula** devuelve todos los hechos:
  aceptable para `none`, pero el cliente debe distinguir `none` de
  `explicit_unavailable` y no tratar ese caso como «sin ficha».
- **G6 Rendimiento.** `spec_unassigned_facts_internal_v1` recalcula el payload
  completo del producto por cada hecho huérfano (línea 95) y el contexto de
  taller lo llama por producto: con decenas de candidatos es hechos ×
  productos. Calcular el payload una vez.
- **G7 Servicios y juegos.** `assign` no excluye `product_type='service'` ni
  `is_set`; el manifiesto sí excluyó servicios. Decidir explícitamente.
- **G8 Desactivar plantillas.** No existe guardia contra desactivar una
  plantilla con vínculos explícitos o mapeos activos (grep en `2026090*`):
  es la causa raíz de E2.

## 3. Pruebas: lo que cubre el pgTAP en curso y lo que falta

Cubre: ACL de vista, resolvedor y editor; respaldo por categoría; reasignación
a otra familia sin referencia; snapshot, contexto y tienda siguen el vínculo;
huérfano `false` con lectura intacta; hechos y lecturas byte a byte; fila del
producto intacta salvo tres columnas; replay; misma clave con otro hash;
revisión y timestamp obsoletos; el escritor legado no borra un huérfano;
cambio de categoría no altera la explícita; lector por familia; limpiar el
vínculo y volver a la categoría; producto sin categoría; borrador nuevo;
categoría ajena; cruce de tenant en lecturas y en `assign`; guardas diferidas.

Falta, en orden de riesgo:

1. Explícita inactiva y explícita de otro tenant: `assign` → 42501; tras
   desactivar la plantilla, `binding_source='explicit_unavailable'`, la
   tienda no publica, y el comportamiento decidido para E2.
2. Referencia vinculada y reasignación a otra familia: 23514, y producto,
   hechos, lecturas y referencia idénticos después (la transacción revierte).
3. `save_product_with_specs_v1` con `p_template_id` de la categoría mientras
   existe vínculo → 40001; con la explícita → guarda hechos bajo ella y el
   escritor sólo borra campos de esa plantilla.
4. Escritura directa `update products set spec_template_id = <ajena o
   inactiva>` → 42501 por el trigger diferido; después de E1, 42501 de
   permiso antes de llegar al trigger.
5. `spec_revision` sube exactamente 1 por asignación y no sube al replay.
6. Caso positivo de tienda: tras vincular y guardar hechos de la nueva
   plantilla, `get_public_product_technical_specs` devuelve campos.
7. Contexto de taller con `explicit_unavailable`: `template_unavailable` ya
   está en el servidor; falta la prueba pgTAP que lo afirme y, en Dart, que
   el consumidor ponga cautela con ese código y lea `__technical_family` del
   contexto en vez de la caché por categoría (E3).
8. `assign` sobre servicio o juego según la decisión G7.

## 4. Decisiones implementables

1. Revocar `update (spec_template_id, spec_reference_id, spec_revision)` sobre
   `public.products` a `authenticated` y `anon` en esta misma migración. El
   cliente no escribe esas columnas directamente (grep en `lib`: sólo
   `website_service.dart` 3738 y un script de imágenes actualizan `products`,
   con otras claves) y todos los escritores son SECURITY DEFINER.
2. El editor devuelve el estado (`explicit_unavailable`, snapshot y
   huérfanos) en vez de lanzar; el guardado comercial no debe morir por una
   plantilla desactivada. Añadir el trigger que impide desactivar una
   plantilla con vínculos explícitos o mapeos activos.
3. `template_unavailable` ya existe en `__spec_issues`; falta la cautela en
   el consumidor y la familia del contexto en Dart (E3).
4. Extender la vista a compras para candidatos con vínculo (G1).
5. `--verify` propio con md5 nuevos, conteo cero de vínculos explícitos tras
   aplicar (la migración no asigna) y ACL de las funciones nuevas; marcar
   `readback.sql` como reemplazado.
6. Comentario de columna y registro en `docs/architecture`; nada de esto
   habilita llenado: sigue bloqueado hasta cerrar la auditoría y el
   saneamiento global, y los productos de cafetería, electrónica y scooter
   entran en él con atributos propios.

---

## Addendum — segunda revisión de la versión corregida (2026-09-06, noche)

Revisión independiente, sólo lectura. No se editó SQL, Dart ni datos; no se
tocó producción ni el runtime. La migración 20260906180000 y
`product_spec_relation.dart` quedan fuera de este dictamen por instrucción.

### A.0 Qué versión se revisó

| Archivo | Estado | SHA-256 |
|---|---|---|
| `supabase/migrations/20260906160000_product_spec_template_binding.sql` | base revisada línea a línea: **4 007 líneas**, congelada al iniciar la ronda | `26c908d9bd29c54c194c87d8805ec2dbff9746da8c7e723f56cca5dee59efb8c` |
| el mismo archivo | **cambió a las 18:43 a 4 021 líneas** mientras corría la revisión; el delta se revisó por diff (ver A.3.1) | `680dd9d3b5b8c34cc27ba0e5cc9608d32f428c2775997edfade7213d2ff0c987` |
| `product-template-binding-verify.sql` (17:59) | leído completo | `178a9ca0dd31e9a77f987a9df080e33317824371023b20f05a0cf17ab3f2ee09` |
| `product-template-binding-smoke.sql` (18:08) | leído completo | `b03697ad810e60b67cbbe8abfa87de6f21d76436dfb6e2fe1ffd570a9805d758` |
| `supabase/tests/product_spec_template_binding.sql` (18:42, 166 líneas, 73 aserciones) | leído completo y **corrido en local** | `0cf13a76116c5ceffc8c14e3b6d4df7e8e8cc9c9d7fd7cc68aa7a60716e655ba` |

Los números de línea de abajo son de la versión de 4 007 líneas; hasta la
línea 2 428 coinciden con la de 4 021.

Delta 4 007 → 4 021 (nueve hunks, cuatro funciones): exclusión del rol
`legacy` en `assistant_infer_technical_predicates_internal_v1`,
`assistant_inspect_inventory_schema_v1`, `assistant_inspect_inventory_schema_v3`
y en los `availableFields` de `supply_need_eligible_products_internal_v1`. El
bloque de guardia de hashes (líneas 4–46) es **idéntico** en ambas versiones.

### A.1 Resueltos respecto de la revisión anterior

| Hallazgo | Estado | Evidencia |
|---|---|---|
| E1 escritura directa de `spec_template_id` / `spec_reference_id` / `spec_revision` | **Resuelto** | Bloque DO líneas 83–100: revoca INSERT/UPDATE de tabla a `anon`/`authenticated`, reotorga por columna excluyendo las tres protegidas y el guard generado. Local: `has_table_privilege(authenticated, products, update) = false`, columnas ordinarias sin permiso = 0, columnas protegidas = false. pgTAP con `set local role authenticated` (tests 131–135). Ningún cliente Dart envía esas columnas: `grep` en `lib/` sólo las lee (`inventory_models.dart:344`), y `Product.toJson` no las incluye. |
| E2 el editor lanzaba 23514 y el guardado 42501 | **Resuelto como estado** | `get_product_spec_editor_context_v1` (177–199) devuelve `binding_source = explicit_unavailable` + `unassigned_facts`; el formulario lo muestra (`product_form_page.dart:7635`) y lista los hechos conservados (7643). Un guardado en ese estado sigue bloqueado por `spec_validate_product_internal_v1` (42501): no silencia el vínculo. Con las FK compuestas el estado es inalcanzable salvo con el trigger deshabilitado y la FK diferida, que es exactamente cómo lo simula el pgTAP (121–127). |
| E3 el cliente resolvía familia por categoría | **Resuelto** | `get_product_spec_contexts_v1` (302–320) emite `__technical_family`, `__template_key`, `__template_id`, `__binding_source`, `__unassigned_facts`; `bike_product_compatibility_service.dart` eliminó la caché de categorías y lee `__technical_family` (248–260); cualquier `__spec_issues` distinto de `unmapped` baja a caution. Test «an unavailable assigned template cannot regain category authority». |
| G1 compras elegía por categoría | **Resuelto, con consecuencias** (A.2) | `supply_need_eligible_products_internal_v1` y `supply_need_stock_candidates_v1` filtran con `spec_product_field_is_active_internal_v1` (154–164). |
| G2 formulario/editor | **Resuelto** | `spec_engine_service.dart` `getProductEditorContext` (252–266) y `_loadTemplate` sin caché de proceso, con recheck de `contract_version`/`is_active`; el formulario carga por RPC (1290–1350) y guarda `p_template_id`/`p_contract_version` (4794–4795). |
| G3 recomendaciones por `product_type`/categoría | **Resuelto** | `smart_job_recommendation_service.dart:315` usa `get_product_ids_for_spec_family_v1('chain')`. `bike_chain` no es familia en producción (familias con «chain»: chain, chain_guide, chain_link, chainring), así que dejar de pedirla no pierde nada. |
| G4 read-backs históricos | **Resuelto en diseño, desfasado en contenido** | `verify.sql` fija md5 de 28 funciones, 2 vistas, 3 constraints, permisos y un baseline de datos. Ver A.3.1. |
| G5 huérfanos con plantilla nula | **Resuelto** | `spec_unassigned_facts_internal_v1(p, null)` lista todos los hechos; el panel «Sin ficha» los muestra. Aislamiento de tenant añadido (línea 224 y lecturas 220). |
| G6 payload recalculado por huérfano | **Resuelto** | CTE materializada (213–215). Costo medido en producción: `spec_payload_display(spec_product_payload)` para los 1 664 productos = 1,71 s (≈1 ms/producto). |
| G7 servicios/sets | **Resuelto** | El lector de familia exige `is_active` y `product_type = 'product'` (203–206); compras ya excluía servicios. |
| G8 sin guardia al retirar | **Resuelto** | Trigger 102–115 (también sobre `tenant_id`/`key`/`technical_family`) **y** FK compuestas 51–73 con `unique(id, is_active)`; en local existen, validadas, con los guards generados `stored`. |

**Carrera asignar ↔ retirar: cerrada.** La FK `products_spec_template_active_fk`
toma `FOR KEY SHARE` sobre la fila `(id, is_active)` de la plantilla al asignar;
como `is_active` integra una clave única, el `update ... set is_active = false`
necesita `FOR UPDATE` y espera; la verificación `NO ACTION` del lado referido
se reevalúa con snapshot fresco, así que el orden inverso también falla. Vale en
READ COMMITTED y REPEATABLE READ; el pgTAP lo prueba con el trigger deshabilitado
(«foreign key protects active assignment even without advisory trigger»). El
trigger queda como mensaje amable, no como cierre.

**Guardia de 28 definiciones antes/después:** las 19 funciones preexistentes
coinciden hoy con producción (19/19 `matches_before = true`, leído en producción
esta noche); las 9 nuevas no existen allí. El baseline de datos del verify
(`products = 1665` y siete md5) coincidía con producción al momento de la
lectura.

**Replay idempotente:** `create or replace`, `add column if not exists`,
constraints e índice con `if not exists`, `drop trigger if exists`, y el bloque
de permisos recaptura los grants vigentes; en local las 28 definiciones dan
exactamente el md5 fijado por el verify.

### A.2 Regresión de compras (G1): qué cambia y cuánto

Semántica nueva: un campo es «activo» para un producto sólo si el producto tiene
plantilla resuelta, la plantilla contiene el campo y su rol no es `legacy`. En
`assistant_inventory_technical_predicate_source_internal_v1` y
`..._filter_source_internal_v1` el chequeo es la **primera** línea y devuelve
`unresolved` antes de mirar hechos **y antes del fallback por nombre e
identidad** que la versión productiva sí ejecuta (líneas 28, 165–194 de la
definición en producción: `name_reading`, `identity_fallback`).

Consecuencias medidas en producción (tenant Viñabike, 1 605 productos físicos):

| Población | Hoy | Efecto tras el despliegue |
|---|---:|---|
| Productos sin plantilla | 742 (545 con categoría, 197 sin) | Ningún predicado técnico se resuelve para ellos, ni por nombre. Siguen en el universo de `eligible` como `unresolved`; desaparecen de `por_ficha` en stock. |
| …de ellos con hechos | 1 (Cámara Chaoyang 700x33/37c F/v 60mm, sin categoría, 7 hechos `supplier_text`/`inferred`) | Sus hechos no satisfacen criterios. |
| Con plantilla y hecho fuera de ella | 1 (Cubetas Motor BMX americana sellada eje 19 mm: `spindle_diameter_mm` bajo `bottom_bracket_cup`) | Ese campo no cuenta. Es el caso que motivó el cambio. |
| Con plantilla y hecho de rol `legacy` | 1 (Cadena KMC HV408: `drivetrain_primary_ecosystem`, `import`) | No cuenta en compras ni asistente, y la tienda deja de mostrarlo (`get_public_product_technical_specs` ahora usa `spec_active_product_values_internal_v1`). |
| Necesidades abiertas | 27: 17 en categorías con plantilla, 10 sin categoría, 0 en categorías sin plantilla | Ninguna necesidad abierta hoy cae en categoría sin plantilla. |

Lectura: el cambio hace lo que Codex describe —un hecho conservado fuera de la
ficha no satisface criterios— y hoy toca tres productos. El efecto grande no
son los hechos sino el **fallback por nombre**: para 545 productos con categoría
y sin plantilla, el carril técnico del asistente y de compras queda apagado
hasta que el saneamiento les asigne ficha. Es coherente con «primero sanear»,
pero es una pérdida funcional respecto de producción que hay que decidir a
sabiendas. Alternativa sin romper la regla: distinguir «sin ficha» (binding
`none`, conservar el fallback por nombre/identidad) de «ficha que excluye el
campo» (`unresolved`); la regla de Codex sólo necesita el segundo caso.

Dos efectos menores: `eligible` saca del universo (y del conteo) a los
productos con plantilla que no contiene algún criterio, pero conserva a los sin
plantilla como `unresolved`, mientras stock los omite —dos lectores, dos
respuestas para el mismo producto—; y `availableFields` ahora une las familias
de la categoría (vista `category_spec_template_scope_internal_v1`, 144–152),
de modo que en una categoría mixta puede ofrecer un campo que deja en cero a
la otra familia. Ambos son aceptables si se documentan.

### A.3 Errores concretos pendientes

1. **Los hashes fijados no corresponden al archivo actual — bloquea el
   despliegue.** La migración cambió a las 18:43 (4 021 líneas) después de
   generarse `verify.sql` (17:59) y sin regenerar el bloque de guardia (4–46,
   idéntico). Cuatro funciones cambiaron de cuerpo (A.0). Secuencia si se
   despliega así: la guardia pasa (coincide con `before_md5`) y crea los cuerpos
   nuevos; `function_contract_assertion` del verify falla en cuatro md5;
   `deploy_migration.sh` sale sin estampar («The migration SQL reached
   production but verification/stamping did not complete», líneas 95–135); al
   reintentar, la guardia lanza «Affected function changed since review» porque
   el cuerpo vivo no coincide ni con `before` ni con el `after` viejo. Queda
   atascado hasta regenerar ambas listas. Evidencia adicional: local tiene los
   cuerpos de 4 007 (28/28 md5 = verify) y el pgTAP de las 18:42 espera 4 021:
   corrido en local, **73 aserciones, fallan 53–54** («current discovery
   excludes retired chain criteria», «legacy discovery cannot resurrect retired
   chain criteria»). Arreglo: replay local de 4 021, regenerar `after_md5` en la
   guardia y en `verify.sql` desde ese mismo estado, y volver a correr pgTAP. Las
   224 de Codex no se reprodujeron aquí.
2. **Baseline y pins con fecha de vencimiento.** El baseline del verify
   (`products = 1665`, md5 de hechos, lecturas, plantillas, mapeos, recibos) y
   los del smoke (1 605 físicos, 1 664 contextos) coinciden hoy; cualquier
   guardado de ficha antes del despliegue los invalida y el verify fallará tras
   aplicar. Se recalculan inmediatamente antes de `deploy_migration.sh`, no
   antes.
3. **Costo del helper por producto × criterio en `eligible`.** Medido en
   producción con el equivalente inline (los cuerpos nuevos no existen allí):

   | Patrón | Antes | Después |
   |---|---:|---:|
   | Conteo del universo, categoría Cámaras (133 productos, 2 criterios) | 14 ms | 334 ms |
   | `por_ficha` en stock, 2 criterios | 20 ms | 56 ms |
   | Join producto→plantilla en búsqueda v4–v7 (1 664 productos) | 20 ms | 60 ms |

   `eligible` corre ese filtro dos veces (conteo y `scoped`) y luego evalúa:
   ≈0,7 s añadidos para 133 productos, lineal con universo × criterios (≈2 s
   con 400 productos), contra los 289 ms totales que el propio comentario de la
   función documenta tras el arreglo del 2026-08-31. No es error de corrección;
   es el camino caliente de compras. Propuesta: resolver el vínculo una vez por
   producto (lateral sobre la vista, o CTE materializada por producto) y probar
   pertenencia del campo con un anti-join sobre `spec_template_fields` para las
   claves del predicado; contar el universo desde la misma CTE. Medir después
   del despliegue: el smoke no cronometra.
4. **Fallback por nombre apagado para productos sin ficha** (A.2). Decisión de
   producto antes de desplegar; hoy no afecta ninguna necesidad abierta.
5. **`explicit_unavailable` no se repara desde el cliente.** Ningún llamador de
   `assign_product_spec_template_v1` ni de `get_product_spec_bindings_v1` en
   `lib/`. Con las FK es inalcanzable; pero el saneamiento que viene necesita
   correr `assign` para cientos de productos con `auth.uid()` real: el wrapper
   `query.sh` no lleva JWT. Es la misma laguna de «actor autenticado» del plan
   de llenado; conviene resolverla antes de empezar el saneamiento.
6. **`assign` no mapea el 23503.** Si pierde la carrera, el operador recibe el
   mensaje crudo de la FK en lugar de «Plantilla no disponible» (240–290 sin
   bloque `exception`). Cosmético.
7. **v7 `scoped_families` sigue leyendo `category_tech_mappings`** (2 013–2 020,
   consumido en 2 121): la rama «producto de la familia fuera de la categoría»
   ignora las familias de vínculos explícitos, a diferencia de inferencia e
   inspección que ya usan la vista unión. Pequeño, pendiente.
8. **`getTemplateForCategory` sin llamadores** (`spec_engine_service.dart`
   239–247): camino muerto que resuelve por categoría; quitarlo evita que
   reaparezca la resolución categoría-primero.
9. **Smoke y el tope de 30 s del runner.** `every_editor_context_assertion`
   llama snapshot + contexto de editor para 1 605 productos (payload ×3 y
   validación cada uno). El lector de contextos actual tarda 5,3 s para 1 664
   productos en producción y 0,36 s para 60; con `__unassigned_facts` suma ≈1
   ms/producto. Probablemente cabe, no está demostrado: cronometrar o partir.
10. **Dart — velocidades declaradas de cadena.** Nueve aprobaciones parciales
    pasaron de `compatible` a `caution` (cadena, conector, shifter, maza,
    llanta, cámara, cubre cámara, válvula tubeless, pastilla no disco, rotor):
    verificado en el diff; los únicos `compatible` que quedan son sub-chequeos
    del shifter (1 145–1 168) que se funden en una caution. Pero el desajuste
    de velocidades **declaradas** de la cadena también bajó de `incompatible` a
    `caution` en ambos sentidos (test líneas 36–37 lo fija). Una cadena más
    ancha que la transmisión (máximo declarado < velocidades de la bici) no
    entra entre los piñones; ese sentido debería seguir `incompatible`. La
    cadena más estrecha sí admite caution. Dominio de Codex; se deja como
    observación con evidencia (Park Tool, Sheldon Brown: ancho de cadena vs
    separación de piñones).

### A.4 Pruebas corridas y resultado real

- Dart, 10 archivos (`bike_product_compatibility_service`, `product_spec_contract`,
  `chain_connector_spec_contract`, `product_spec_numeric_domains`,
  `drivetrain_product_spec_field_behavior`, `drivetrain_product_spec_inference`,
  `product_spec_inference_utils`, `product_spec_persistence_utils`,
  `spec_option_rules`, `product_spec_boolean_field`): **164 pasan**.
- Por un glob mal escrito corrí además la suite completa: 6 651 pasan, 3 fallan,
  1 omitida, en `payroll_redesign_surface_test` /
  `website_collections_responsive_inspector_test`; no identifiqué cuáles ni
  son de este alcance. Se informa porque ocurrió.
- pgTAP local (`scripts/db/test.sh product_spec_template_binding`): 73
  aserciones, **fallan 53–54** por el desfase local ↔ archivo (A.3.1).
- Producción, sólo lectura: 19/19 `before_md5` coinciden; baseline del verify
  coincide; mediciones de A.3.3 y G6.
- Local: FK compuestas validadas, `unique(id, is_active)`, guards generados,
  triggers `spec_template_retirement_guard` y `product_spec_template_revision`,
  permisos de tabla revocados y columnas ordinarias intactas.

### A.5 Dictamen

La arquitectura del vínculo, el cierre de permisos y la carrera de retiro están
correctos y probados. **No se despliega la versión de 4 021 líneas tal como
está**: hay que regenerar la guardia y el verify desde un replay local de ese
archivo (A.3.1), recalcular baseline y pins justo antes (A.3.2), decidir el
fallback por nombre para productos sin ficha (A.3.4) y, antes o inmediatamente
después, corregir y medir el costo del helper en `eligible` (A.3.3). El resto
son pendientes menores. El llenado sigue bloqueado hasta el saneamiento global,
y el saneamiento necesita el canal autenticado de A.3.5.
