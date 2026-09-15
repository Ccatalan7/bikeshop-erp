# Rendimiento del binding: diagnóstico y corrección acotada

Fecha: 2026-09-06. Responsable: Codex, subagente `spec_boundary_review`.

**Resultado:** se reprodujo un timeout de `assistant_search_inventory_v7` ejecutada sola. Una proyección por conjuntos conserva la membresía de los 1.653 hechos técnicos observados. Root desplegó la corrección `20260906191000_product_spec_binding_read_performance.sql` con receipt APPLIED a las **2026-09-07 03:40:31 UTC**; el lector v7 con los mismos argumentos terminó en **4.953 s** de servidor después del despliegue. Este revisor implementó y aplicó sólo en local, y leyó el receipt y las mediciones posteriores de root. No se editaron las migraciones aplicadas 160000/170000/180000 ni las funciones que integra root en 190000.

La medición candidata de aproximadamente 0,8 s fue una consulta SQL directa con los mismos datos productivos; se distingue de los 4,953 s del lector productivo completo después del despliegue. Ambas mediciones usaron el wrapper SQL con contexto del principal; no constituyen una interacción del ERP ni un benchmark HTTP autenticado.

## Reproducción y medidas

Todas las consultas productivas pasaron por `scripts/db/query.sh production --file …`, en la transacción de sólo lectura y con timeout de 30 s del wrapper. Se reutilizó el contexto de principal del smoke existente: permite medir funciones con contexto de tenant, pero no constituye una sesión PostgREST autenticada real. No se imprimieron tokens.

Las seis entradas del smoke se ejecutaron **individualmente**, con los mismos argumentos originales y `EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)` sobre el lector. Tiempos de ejecución del servidor; el timeout incluye el viaje observado por `\timing`:

| Consulta | Resultado | Tiempo |
|---|---|---:|
| `assistant_search_inventory_v4('KMC', …)` | Objeto JSON | 1.571 s |
| `assistant_search_inventory_v5('KMC', …)` | Objeto JSON | 1.477 s |
| `assistant_search_inventory_v6('KMC', …)` | Objeto JSON | 1.522 s |
| `assistant_search_inventory_v7('KMC', …)` | Timeout dentro de inferencia | 30.197 s |
| La misma v7 después de 191000 | Ejecuta | 4.953 s |
| `assistant_inspect_inventory_schema_v1('cadenas', null)` | Objeto JSON | 1.483 s |
| `assistant_inspect_inventory_schema_v3('cadenas', null)` | Objeto JSON | 0.983 s |
| Helper escalar de actividad, 20 hechos | Ejecuta | 0.408 s |
| Proyección candidata de todos los hechos activos | 1.644 hechos / 460 productos | 0.450 s |
| Inferencia candidata SQL, `KMC` | Objeto de inferencia | 0.837 s |
| Inferencia candidata SQL, `cadena 8 velocidades` | `chain_speeds in ["8"]` y categorías | 0.817 s |

Los lectores conservan `statement_timeout=4500ms` en `pg_proc.proconfig`; el timeout observado en esta ejecución de v7 fue el de 30 s de la sentencia exterior. No se usó ese atributo como evidencia de que el lector se interrumpiera a 4,5 s.

El catálogo observado contiene 1.653 hechos sin scope de productos de este tenant, correspondientes a 461 productos y 57 definiciones. Hay 280 campos de plantilla y 37 plantillas. El fallo no requiere un catálogo de millones de filas.

## Causa sustentada y límites de atribución

La definición desplegada de inferencia usa `spec_product_definition_is_active_internal_v1` al calcular cobertura, rango numérico y coincidencia numérica con hechos. Cada llamada vuelve a resolver la identidad del campo, la plantilla efectiva y la pertenencia a ella. La resolución de plantilla también está dentro de la vista de bindings. Los helpers SQL tienen configuración de búsqueda propia y aparecen como llamadas opacas en el plan exterior.

La ruta del timeout y el coste de 20 hechos respaldan que repetir esa proyección por observación es el cuello de botella relevante. **No se midió el número exacto de llamadas anidadas ni se atribuye todo el tiempo a una función concreta:** el usuario productivo del wrapper no tiene permiso para `track_functions`. La tentativa fue sólo un cambio de configuración de la transacción de lectura; se detuvo ante el rechazo, sin elevar privilegios. Tampoco existe en esta revisión un benchmark anterior al despliegue de 160000 que permita afirmar su delta histórico exacto.

## Cambio mínimo

La migración cambia exclusivamente `assistant_infer_technical_predicates_internal_v1(uuid,text)`:

1. `active_definitions` resuelve una vez por plantilla y tenant las identidades permitidas, agrupando por clave y conservando sólo claves con un único ID. Incluye en la comprobación de ambigüedad también definiciones no filtrables.
2. `active_facts` une por tenant, ID de producto, ID de definición y plantilla efectiva. El `CASE` conserva la precedencia del binding explícito; si no está disponible, no cae al valor de categoría. Sólo entran sujetos `product` sin scope y definiciones activas en el contrato.
3. Los tres consumidores de inferencia reutilizan ese conjunto. Tokenización, resolución de vocabulario, categorías, orden, límites y forma del resultado no cambian.

No se añade caché persistente, invalidación, índice ni función pública; no se eliminan hechos legacy. La optimización evita ejecutar el resolver escalar por cada observación en esta ruta. Otros consumidores siguen usando sus helpers actuales.

## Paridad y validación local

Se comparó la pertenencia del helper desplegado con la nueva proyección, hecho por hecho, en 34 sentencias de hasta 50 observaciones. Cada comparación empleó ambas expresiones en la misma sentencia/snapshot:

| Comprobación | Resultado |
|---|---:|
| Hechos comparados | 1.653 |
| Activos según helper desplegado | 1.644 |
| Activos según proyección por conjuntos | 1.644 |
| Diferencias | 0 |
| Tiempo acumulado que reportó `\timing`, incluido cierre | 36.714 s |

Esto prueba paridad de membresía en los datos observados; no prueba todos los posibles tenants/contratos ni la identidad byte a byte de todos los resultados de búsqueda. Las regresiones sintéticas complementarias cubren esos límites de semántica, sin pretender evidencia OEM:

- `product_spec_binding_read_performance.sql`: **17 pgTAP pasan**. Incluye inferencia numérica por pista y categoría, override de categoría, legacy, producto sin binding, otro tenant, shadow fuera de plantilla, scope no nulo, plantilla explícita no disponible, ambigüedad global/tenant y shadow no filtrable; también preservación de observaciones y ACL privada.
- `product_spec_template_identity.sql`: **18 pgTAP pasan** tras el cambio.
- `product_spec_template_binding.sql`: **73 pgTAP pasan** tras el cambio; se ejercita también v7 con las fixtures de binding.
- La definición nueva se aplicó y reaplicó con guardias de preimage/postimage; el postimage coincide con el calculado. El verify de MD5, autoridad y ACL efectiva pasa en local.
- El fixture local tenía una concesión PUBLIC heredada que producción no tiene. Antes del apply se retiró exclusivamente esa concesión de esta función mediante un prerequisito local con MD5 y ACL exactos. No se amplió la guardia productiva para aceptar ACLs distintas.

## Preimage, autoridad y archivos reproducibles

Función: `public.assistant_infer_technical_predicates_internal_v1(uuid,text)`.

| Propiedad | Valor |
|---|---|
| MD5 productivo antes | `81c8b719dd1045f2a9c5344a47920ea4` |
| MD5 después, verificado por el deploy | `aa5c3a35b1a76c3b280a34838b6b63f9` |
| Owner | `postgres` |
| ACL productiva antes/después esperado | `{postgres=X/postgres,service_role=X/postgres}` |
| Seguridad / volatilidad | `SECURITY DEFINER`, `STABLE` |

Evidencia bajo `.tmp/db/`, con prefijo exclusivo `performance-review-`:

- `preimage-production.json`, `preimage-local.json`: definición, MD5 y ACL capturados antes.
- `v4.sql/.log`, `v5.sql/.log`, `v6.sql/.log`, `v7.sql/.log`, `schema-v1.sql/.log`, `schema-v3.sql/.log`: consultas aisladas.
- `helper20.sql/.log`, `setbased.sql/.log`, `candidate-infer-kmc.sql/.log`, `candidate-infer-chain8.sql/.log`: planes y coste de la propuesta.
- `parity.sql/.log`: comparación completa en bloques, cero diferencias.
- `local-acl-prerequisite.sql/.log`, `local-apply.log`, `local-pgtap.log`: aplicación y pruebas locales.
- `verify.sql`: read-back de postimage y autoridad para que root despliegue mediante el wrapper de migraciones.

## Despliegue revisado y gates residuales

Se leyó `.tmp/db/migration-receipts/20260906191000.receipt`: APPLIED, verificación a las 03:40:31 UTC y SHA256 de migración `4e110f4f86d081c5b1ab14f2d0dc3f20636af0406dc6cce278e5e500872143ea`. El receipt vincula `product-spec-binding-performance-verify.sql` y `product-spec-preserved-data-2026-09-06.sql`. Desde ese despliegue 191000 y su test quedaron congelados.

`.tmp/db/spec-performance-post-deploy-v7.log` muestra ejecución individual de v7 en **4952.647 ms** de servidor / 5191.160 ms con viaje. `.tmp/db/spec-binding-post-performance-smoke.log` confirma ejecución de los seis lectores combinados, del scope de predicados técnicos y de tres necesidades de compras. **Ese archivo no es un smoke completamente verde:** la sentencia posterior que agrega fichas de tienda se interrumpe a los 30.213 s, dentro de `get_public_product_technical_specs` → `spec_active_product_values_internal_v1` → `spec_payload_display_internal_v1`. No se midió aquí esa llamada pública individual ni se atribuye su timeout a esta función de inferencia.

La recuperación de v7 está respaldada por la lectura productiva. Quedan la comprobación HTTP/ERP que lleva root y los límites de consultas agregadas; el éxito de v7 no se presenta como solución general del rendimiento de todas las fichas.

El timeout de `get_product_spec_contexts_v1` con los 1.664 IDs de una vez permanece fuera de esta corrección prioritaria. Los bloques de 50 observados por root son un modo de lectura viable, no prueba de que la llamada de catálogo completo ya esté optimizada. No se propone elevar timeouts como solución.
