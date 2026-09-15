# Revisión independiente · inferencias pendientes fuera de la ficha pública (2026-09-15, ronda 223)

Revisión del candidato de Root en
`.tmp/product-spec-catalog/public-inference-guard-20260915/` y de su prueba
pgTAP. Sólo lectura de archivos y pruebas locales en transacción con rollback;
sin SQL productivo, sin migraciones aplicadas, sin escritura de datos, código ni
archivos de Root. El lector local quedó en la preimagen antes y después
(`89e21f13…`, cero tenants sintéticos residuales).

| Artefacto revisado | Hash |
|---|---|
| `candidate.sql` (begin/commit + wrapper) | SHA-256 `8a6b8938a01c05e99e7047a571e6c89f7927938807c5c72e42d54eff74a3d1ef` |
| `migration-body.sql` (mismo cuerpo sin begin/commit) | SHA-256 `d7e1f2e0…` |
| `before-function.sql` / `after-function.sql` | SHA-256 `a45e9f43…` / `37f61d63…` |
| Preimagen → postimagen del lector (`md5(pg_get_functiondef)`) | `89e21f13bb41bdac92b17e62b059df06` → `4d42285fdfc0bc9c33fce0fe6d9d40a3` |
| `supabase/tests/fixtures/product_spec_public_inference.sql` | SHA-256 `ae64b303…` |
| `…/product_spec_public_inference_assertions.sql` | SHA-256 `514d1e86…` |
| `supabase/tests/product_spec_public_inference.sql` | SHA-256 `f3d7dc3e…` |
| Informe de Root `public-pending-inference-guard-2026-09-15.md` | SHA-256 `cc53ab3a…` |
| Mi sonda `.tmp/product-spec-catalog/public-inference-review-20260915/boundary-probe.sql` | SHA-256 `a9715f03…` (23 aserciones, rollback) |

## 1. Dictamen

**Aprobado el SHA exacto `8a6b8938…`** (par md5 `89e21f13…` → `4d42285f…`),
con los límites y condiciones del §6. No encontré bloqueantes ni un problema
reproducible. Omitir las inferencias pendientes de la salida pública antes de
asignar la cámara es correcto y es el cambio mínimo.

## 2. Delta verificado

- **Un solo bloque nuevo.** `diff before after` muestra únicamente el
  `not exists` de nueve líneas sobre `public.spec_facts`. Firma
  (`p_tenant_id uuid, p_product_id uuid` → mismas 8 columnas), `LANGUAGE sql`,
  `STABLE`, `SECURITY DEFINER`, `search_path`, dueño `postgres` y ACL
  (`postgres, authenticated, service_role, anon = X`) idénticos antes y después
  (mi aserción 4 compara la fila de `pg_proc` completa; la fixture 12 compara
  `proacl`). El cuerpo embebido en el wrapper es byte a byte
  `after-function.sql`; `candidate.sql` y `migration-body.sql` difieren sólo en
  `begin;`/`commit;`, como las migraciones del repo.
- **La preimagen es real, y lo corroboran tres fuentes independientes de la
  captura de Root:** (a) la migración `20260907020000` registra
  `89e21f13…` como postimagen de esta misma firma (`:8` y `:782`) y ninguna
  migración posterior del repo toca el lector; (b) `before-function.sql` sólo
  difiere del cuerpo de esa migración (`:519-552`) en el `;` final que
  `pg_get_functiondef` no imprime; (c) la base local está en `89e21f13…`.
- **El wrapper falla cerrado en los dos sentidos.** Sobre la postimagen
  retorna sin tocar nada (aserciones 19-20: replay es no-op y el md5 no
  cambia). Sobre un lector que no es preimagen ni postimagen lanza
  «Public specification reader changed after review» (21-22: derivé el lector
  con `alter function … set work_mem` y el guard lo rechazó; `reset` devolvió
  la postimagen, 23). Tras el `execute` vuelve a exigir el md5 de la
  postimagen (3). Es el mismo mecanismo de guardia por md5 que usan las
  migraciones de fichas del repo.

## 3. La decisión de lectura

**Qué hay detrás de `inferred`.** El único escritor de `source = 'inferred'`
en todo el repo es la migración `20260824560000` que llenó las cámaras desde su
nombre: material «butilo» cuando el nombre no lo dice y «sin sellante» cuando el
nombre no lo menciona, ambos con `confirmed = false` y con el razonamiento
«el silencio es evidencia» documentado allí. No hay escritor en runtime
(`lib/` y `supabase/functions/` no contienen `'inferred'`), y el comentario de
`spec_facts.source` del 08-21 fija que nunca se infiere en runtime. Por eso el
alcance del guard es exactamente el que Root midió: `tube_material` (103) y
`tube_has_sealant` (124), 227 campos potenciales en 132 cámaras visibles, todas
de la plantilla global `tube` `e1adfef6…`.

**Hoy la ficha pública publica todo lo conocido sin mirar procedencia.** Mi
aserción 2 lo demuestra con la preimagen: 12 de 12 valores salen, incluidas
inferencias pendientes de `single_select`, `multi_select`, booleano `false` y
número `0`. `sample-before.json` muestra la forma exacta del problema en una
cámara vecina: «Trae líquido sellante: No» y «Material de la cámara: Butilo»
como afirmaciones sin marca alguna.

**Esconder es correcto y mínimo; rotular no lo era.** Un rótulo de procedencia
exige columna nueva en la firma y cambio del modelo del storefront
(`_PublicProductTechnicalSpec.fromJson` en `product_detail_page.dart`); no es
el cambio mínimo. Esconder es reversible dato por dato sin tocar la función:
confirmar la inferencia la vuelve a publicar (aserción 12) y cambiar su origen
también (13), porque el filtro es específico de `inferred` y no un filtro
global de `confirmed` (fixture 6; mis 7-8 con `catalog` e `import` sin
confirmar siguen publicándose). Los hechos, el producto, la proyección interna
y los permisos no cambian (fixture 9-12; mis 10-11 conservan el cero y la
selección pendientes en `spec_active_product_values_internal_v1`).

**No contradice al 08-24.** Aquella migración juzgó la deducción suficiente
para la ficha interna; este candidato juzga que el storefront no la afirme
como hecho. Si el dueño considera que «sin sellante» merece publicarse, el
camino es confirmar esos hechos (decisión de datos, con la pieza o el
proveedor delante), no debilitar el lector.

**Omitir antes de asignar es lo correcto.** Asignar la plantilla activa las
siete observaciones raíz de `6927116185398`; con el guard se publican las
cinco `supplier_text` y las dos `inferred` quedan en el editor. Sin él, la
asignación convertiría dos deducciones en afirmaciones públicas.

**Radio de efecto.** Al aplicar, hasta 227 campos de 132 cámaras ya visibles
desaparecen de la web. Es el efecto buscado y Root no renderizó las 227 (dos
agregados del renderizador agotaron el timeout en
`spec_payload_display_internal_v1` y `spec_coherence_fields_internal_v1`, no en
nada que toque el candidato). Condición de lectura real en §6.

## 4. Aislamiento raíz / perfil / tenant y no promoción

El predicado nuevo mira exactamente la fila cuyo valor se imprimiría:

| Predicado del guard | Cómo obtiene el valor el lector hoy |
|---|---|
| `observed.tenant_id = p_tenant_id` | `visible` exige `p.tenant_id = p_tenant_id`; `spec_product_scope_payload_internal_v1` filtra `f.tenant_id = tenant del producto` |
| `subject_type = 'product'`, `subject_id = p.id` | mismo sujeto en el payload |
| `subject_scope is null` | el payload raíz pasa `p_scope = null` y filtra `subject_scope is not distinct from null` |
| `spec_definition_id = d.id` | el payload agrupa por `spec_definition_id` y lo mapea a `d.key` sólo por los campos de la plantilla, con excepción 23514 si dos definiciones comparten clave |

Con el índice único `(tenant_id, subject_type, subject_id, spec_definition_id,
coalesce(subject_scope,''))` hay a lo sumo una fila raíz por definición:
confirmar o corregir ocurre en el mismo registro, no hay «observación
superada» que pueda esconder un valor confirmado.

- **Tenant.** Una observación de otro tenant sobre el mismo `product_id` no
  puede existir: `product_spec_fact_graph` la rechaza con 42501 (aserción 16).
  Otro tenant lee cero filas (fixture 13). El filtro es coherente con la CTE
  `visible`, no una defensa nueva.
- **Perfil.** Una inferencia pendiente en un scope de componente sobre la misma
  definición no esconde la observación raíz (17-18). Advertencia de entorno:
  la base local **no tiene** el framework de perfiles (`spec_member_fact_guard`
  ausente, sin `product_spec_member_profiles`, 5 triggers en `spec_facts`), así
  que la fila con scope pudo insertarse sin perfil dueño. En producción esa
  fila exige perfil; el predicado la ignora en ambos casos.
- **Sin promoción accidental.** El candidato no escribe; `confirmed` es
  `NOT NULL` (23502, aserción 15), de modo que la rama «null» del texto de Root
  y el `coalesce(confirmed,false)` describen el código, no un estado
  alcanzable. `supplier_text` `false` (fixture 6), `catalog` e `import` sin
  confirmar (7-8) e `inferred` confirmado (fixture 5) conservan su política.
  `name_reading` sin confirmar no se ejercitó (requiere recibos de lectura);
  por código queda intacto.
- **Único camino anónimo.** De las seis funciones con `grant … to anon`
  (`create_public_online_order`, `get_public_online_order`,
  `get_public_product_technical_specs`, `normalize_worker_username`,
  `resolve_worker_login`, `search_products`) sólo este lector toca
  `spec_facts` o los payloads; `search_products` no lee hechos.
- **Seguridad.** Definer con `search_path` fijo y subconsulta calificada
  `public.spec_facts`; sólo quita filas del producto ya autorizado por
  `visible`. ACL de producción (`potential-impact.json.function_access`) igual a
  la local. Costo: búsqueda puntual por el prefijo del índice único, por
  campo; despreciable frente al validador que ya corre.

## 5. Cobertura de prueba

- **Reproducción de Root.** `candidate-test.sql`: 15 ok. `negative-test.sql`:
  12 ok y exactamente `not ok 2, 3, 4` (las tres de salida). Coincide con su
  informe.
- **Mi sonda (23 ok, rollback)** añade lo que la fixture no cubre: preimagen
  publica 12/12; postimagen esconde `single_select`, `multi_select`, booleano
  `false` y `0` inferidos por igual (5-6); `catalog`/`import` sin confirmar
  siguen (7-8); un `single_select` confirmado sigue rotulando (9); proyección
  interna intacta (10-11); confirmar republica (12); cambiar origen republica
  (13); `confirmed` nulo imposible (15); otro tenant imposible (16); scope no
  esconde raíz (17-18); replay no-op (19-20); deriva rechazada (21-22); `reset`
  restaura (23); fila de `pg_proc` completa sin cambio (4).
- **No ejercitado por nadie:** `name_reading` sin confirmar; inferencia
  pendiente de tipo `json` con `rows_schema` (el predicado no mira columnas de
  valor, así que aplica igual; ningún escritor produce filas `inferred`);
  plantilla global vs de tenant (la fixture usa una de tenant, las cámaras
  usan la global `e1adfef6…`; el predicado no depende del tenant de la
  plantilla).
- **La suite existente no se rompe por diseño:** ocho pruebas llaman al lector
  público y ninguna inserta `'inferred'`.
- **Secuencia.** `supabase/tests/product_spec_public_inference.sql` afirma la
  postimagen: sobre una base sin la migración falla exactamente en 3 (es el
  ensayo negativo). Debe entrar en el mismo cambio que la migración, y
  `just db-test product_spec_public_inference` antes de aplicarla es rojo por
  construcción.
- **Entorno local desfasado.** Sin `20260914213000` en local, los ensayos de
  Root y el mío corrieron sin perfiles de componente. Vale para este delta (el
  lector es idéntico a producción por md5 y el candidato no referencia objetos
  del framework), pero la suite completa de fichas exige reconstruir la base
  local antes.

## 6. Límites y condiciones de aplicación

1. **No es el contrato epistemológico (§4.2).** Otros orígenes sin confirmar
   siguen publicándose; la salida no muestra procedencia; y el editor no avisa
   al operador que una inferencia pendiente está oculta en la web. Límite de
   interfaz, fuera de este delta.
2. **Las pendientes siguen alimentando la validación.** `p.vals` entra sin
   filtrar a `spec_validate_draft_internal_v1`: un campo B con
   `allowed_when A = x` donde A es una inferencia pendiente sigue publicándose
   mientras A queda oculto. El valor de B es su propia observación y ningún
   valor inferido se filtra; lo dejo documentado, no bloquea.
3. **Aplicación.** Por `scripts/db/deploy_migration.sh` con
   `verification.sql` (sólo md5) **más** una lectura pública real, antes y
   después, de un producto de `potential-impact.json` (por ejemplo el primero)
   esperando que desaparezcan exactamente `tube_has_sealant` y `tube_material`
   y todo lo demás sea idéntico; y de una cámara cuyo material sea
   `supplier_text`, esperando cero cambios. Recién entonces asignar la cámara
   con observaciones y leerla en público.
4. **Conservar `coalesce(confirmed,false)`.** Hoy es inerte; si la columna se
   vuelve nullable, «null = pendiente» es la lectura correcta.
5. **El archivo de migración debe ser el cuerpo revisado byte a byte** bajo
   `supabase/migrations/`, con la prueba pgTAP en el mismo cambio.

## 7. No afirmo

Ninguna lectura productiva mía; no rendericé los 227 campos; nada sobre
`name_reading`; nada sobre el comportamiento con perfiles de componente en
producción más allá de lo que dice el código; no autorizo llenado ni asignación
por esta revisión.
