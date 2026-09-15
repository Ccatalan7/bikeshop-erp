# Revisión independiente · roundtrip legacy tipado (C3) — 2026-09-14

Ronda 210. Sólo lectura; sin SQL ejecutado, sin runtime, sin producción.
Valores de este documento: fixture sintética del repo.

## Alcance y hashes leídos

- `supabase/migrations/20260914222500_product_spec_legacy_typed_roundtrip.sql`
  `a4c15f52…` (coincide con el SHA congelado), verify
  `supabase/manual_checks/verification/20260914222500_…sql` `802d33be…`.
- `scripts/inventory/sql/product_spec_legacy_roundtrip_candidate.sql`
  `63c3d3e3…`, `…_predecessor.json` `ce750209…`,
  `scripts/inventory/prepare_product_spec_legacy_roundtrip.py` `907c6bc6…`,
  `supabase/tests/product_spec_legacy_roundtrip.sql` `067a65d4…`.
- Dependencias leídas: `spec_rule_number_internal_v1` y
  `spec_rule_normalize_internal_v1` (20260906180000 / 20260906070000),
  `spec_rows_validate_internal_v1` (20260908185800 y su candidato),
  `spec_product_scope_payload_internal_v1` (20260914213000), fixtures
  `product_spec_member_graph.sql` y `product_spec_reading_receipt_contract.sql`.

## Veredicto

**Sin defecto causal en el forward.** La corrección compara número y filas por
el tipo de la definición con `numeric` exacto (sin `double`), no escribe ni
reescribe ninguna observación legacy, rechaza datos nuevos y cambios, y no toca
seguridad ni ACL. Queda un residual acotado (H1) que no abre aceptación
indebida: sólo cambia qué error recibe un roundtrip cuando las filas físicas
ya no satisfacen el esquema actual. Recomiendo aplicar; H1 puede ir en un
forward posterior o corregirse antes si Root prefiere un solo cambio.

## Cadena de evidencia verificada

- El forward embebe el candidato byte a byte (líneas 8-149 = candidato 1-142).
  El md5 del cuerpo empaquetado por el script (`CREATE…end $function$` + `\n`)
  es `cf4c6204…`; el del `definition` del predecesor es `1ec9a61a…` y coincide
  con el escritor del candidato de perfiles y con la migración aplicada
  `20260914213000` (mismo md5 calculado aquí). La pgTAP carga ese escritor,
  demuestra primero el falso rechazo del predecesor (`throws_ok` :43-45) y
  luego carga el candidato dos veces (replay del guard, :46-48).
- Diferencia real predecesor → candidato: sólo la declaración `v_preserved` y
  el bloque tipado dentro del bucle legacy (candidato :44-66). Todo lo demás
  —tenant/`auth.uid()`, unión con la referencia, pertenencia a plantilla,
  borrado de activos excluyendo legacy, escritura activa— es idéntico.
- `spec_rule_number_internal_v1` devuelve `numeric` (regex estricto tras
  normalizar; `numeric_value_out_of_range` → `null`). `jsonb_build_object`
  con `numeric` compara por valor: `7.10 = 7.1` sí; `9007199254740993.2 ≠
  …993.3` sí. La prueba :61-63 lo demuestra más allá de 2^53.
- `spec_rows_validate_internal_v1` del candidato cargado en la pgTAP es igual
  al cuerpo aplicado en `20260908185800` (comparado por cuerpo, 5458 bytes).
  Canoniza decimales con `trim_scale`, conserva el orden dado, rechaza claves
  extra en el payload y dentro de cada fila, fuentes inválidas o duplicadas,
  columnas ajenas, `schema_version` distinto del esquema.
- Filas físicas: el bucle legacy quita la clave del payload en todos los
  casos (:68) y el borrado de hechos excluye `legacy` (:70-74): ninguna rama
  escribe un hecho retirado. La aserción :79-82 prueba byte a byte que
  `updated_at`, `source`, valores y lecturas quedan iguales tras aceptar.
- Propiedades extra: número exige objeto con única clave `number` (:49-50);
  filas exige única clave `rows` (:55-57) y el validador rechaza claves extra
  por fila. Sin normalización cae a la comparación cruda y rechaza (:64-66;
  prueba :64-66).
- Nulidad: sin observación previa, `v_preserved` es `null` → número no
  normaliza (`null->'number'` → `null`) y filas exige `v_preserved is not
  null` → ambos rechazan como dato nuevo (prueba :76-78 para filas; número por
  lectura de código). `{"number":null}` en cualquier lado no normaliza y
  compara crudo. `v_contract` nulo → no hay legacy → conducta previa.
- Seguridad/ACL: `CREATE OR REPLACE` conserva dueño y privilegios; el guard
  previo (:9-17) y el postimage (:145-149) exigen `postgres`, definer,
  volátil, `search_path` fijo y ACL exacto `postgres`/`service_role`; el
  verify repite el mismo predicado con `1/0` en caso de desvío. El guard
  acepta predecesor o postimagen, así que el reintento es idempotente y una
  imagen desconocida aborta.
- Forward: `lock_timeout 5s`, `statement_timeout 120s`, `share row
  exclusive` sobre las ocho tablas (bloquea escrituras, no lecturas; un
  bloqueo ocupado aborta limpio). La huella antes/después (:7, :151-155) es
  tautológica bajo el lock salvo para detectar escrituras del propio forward,
  que es su objetivo. `notify pgrst` innecesario (misma firma) e inocuo.
  Rollback: no hay script; el `definition` del predecesor con su md5 basta
  para un `CREATE OR REPLACE` de vuelta, y el guard del forward acepta esa
  imagen para volver a aplicar.

## Hallazgos

### H1 — Filas preservadas se revalidan contra el esquema actual (residual, no bloqueante)

- **Causa.** Candidato :61-62 canoniza `v_preserved->'rows'` con
  `v_def.validation_rules->'rows_schema'` **de hoy**. Sólo se llega ahí cuando
  el JSON crudo difiere (:43). Si las filas físicas ya no satisfacen el
  esquema vigente —`version` subida (el validador exige `schema_version` igual,
  20260908185800:132), `unique_by`/`strict_ordered_pairs` añadidos después,
  fuentes que la regla actual rechaza— el validador lanza su propio 23514
  («Configuraciones inválidas», «Dos filas repiten posición…») en vez de «El
  campo retirado se conserva…», y el roundtrip igual-pero-distinto-en-texto
  sigue rechazado.
- **Riesgo.** Ninguno de aceptación ni de escritura: la rama sólo compara. Es
  un mensaje equivocado y un C3 no cerrado para ese subconjunto (si existe;
  el escritor de 20260906190000 ya usaba `trim_scale`, así que las filas
  legacy más probables sí revalidan).
- **Mínimo.** Envolver la canonización del lado preservado en
  `begin … exception when others then v_preserved := v_old->v_entry.key; end`
  (o comparar con el esquema que las filas declaran), de modo que el fallo del
  lado preservado degrade a la comparación cruda y al mensaje legacy.
- **Prueba faltante.** pgTAP con `rows_schema` cuya `version` pasa de 2 a un
  esquema nuevo tras retirar el campo, y roundtrip de las filas antiguas.

### H2 — La normalización acepta grafías equivalentes (nota, sin riesgo)

`spec_rule_normalize_internal_v1` admite coma decimal, exponente y ceros a la
izquierda (`"7,1"`, `"1e1"`, `"007.1"`) antes del regex estricto. Un cliente
que mande esas formas para un legacy igual en valor es aceptado **sin
escribir**. Correcto para la invariante «igual no se rechaza»; lo dejo escrito
para que nadie lo lea como bypass: nada llega a `spec_facts`.

### H3 — Fuera del alcance de este forward (sin cambio, ya conocido)

- Otros tipos legacy siguen comparando JSON crudo: `multi_select` es sensible
  al orden de `value_ids`; `text` es sensible a espacios. Si el cliente los
  reordena o recorta, el falso rechazo de C3 reaparece ahí.
- La rol-legacy se resuelve por `d.key` mientras el payload va por `id`
  (:41-42, :74): la ambigüedad clave/id de ronda 208 sigue igual; el guard de
  perfiles (20260914213000:88-98) cubre sólo plantillas de miembro.

### H4 — Huecos de prueba (todos rechazan por lectura de código)

Sin caso pgTAP para: número legacy nuevo sin hecho previo; clave extra dentro
de una fila; filas reordenadas; `schema_version` distinto. Dos casos (número
nuevo y fila con clave extra) cerrarían la lectura de código con evidencia.

## Qué no toqué

Ningún archivo revisado, SQL, test ni fixture. Sólo este documento.
