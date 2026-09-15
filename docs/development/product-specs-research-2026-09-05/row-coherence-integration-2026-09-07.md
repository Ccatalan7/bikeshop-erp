# Coherencia interna de configuraciones — integración en curso

Estado 2026-09-07: `20260907020000` aplicado, verificado y registrado en
producción a las `09:51:35Z`; revisión independiente de Claude ejecutada.
El lector exacto 0100 permanece inmutable; los addenda A/B se integraron sólo
al catálogo local, con todos los gates de publicación y llenado cerrados.

## Invariante y límites

Una fila describe una configuración concreta; el enlace a otra fila debe
conservar esa identidad. Una lista de interfaces y una lista de medidas no
autorizan su producto cartesiano. La ausencia de una configuración no equivale
a una exclusión física. El guardado y todos los consumidores deben distinguir
contradicción interna de información incompleta.

Casos reproducidos por la revisión independiente de A:
- Un modo puede mencionar una luz no declarada y un reparto eléctrico puede
  mencionar un puerto no declarado.
- Una fila ANT+ admite una negación explícita del enlace ANT+ en el producto.
- Un Torx T25 admite otro tamaño en el campo adyacente.
- Los extremos escalares invertidos de soporte/dispositivo no se comprueban;
  los extremos dentro de filas ya tienen `ordered_pairs`.

La causa es que `rows_schema` v1 sólo valida la configuración local y el
contrato de campos v2 compara escalares con constantes. Ninguno expresa una
referencia interna ni la afirmación condicional de una fila sobre el producto.

## Diagnóstico y propuesta inicial de Codex

Mantener el esquema de valores de filas v1; ubicar las relaciones entre campos
en un bloque versionado del contrato de la plantilla. El esquema pertenece a
la definición reutilizable; sólo la plantilla conoce los campos vecinos.
No modificar el significado de una columna persistida para convertir su texto
libre en una referencia sin migración y revisión explícitas.

La capacidad mínima debe expresar:
1. Referencia desde una columna a la identidad estable de una fila en otro
   campo. El selector ofrece esas filas, con su resumen legible. Cambiar o
   retirar la fila objetivo no borra en silencio la observación dependiente.
2. Implicación entre datos tipados: condición sobre una fila y requisito sobre
   esa misma fila o sobre escalares del producto. Reutilizar la lógica ternaria
   y las comparaciones exactas; un requisito desconocido genera incompletitud,
   una negación conocida genera contradicción.
3. Orden entre dos escalares numéricos. No utilizar límites numéricos globales
   para deducir interfaces o compatibilidad de un modelo.

No extender esta entrega a suma automática de potencias. Dos máximos
individuales pueden compartir un presupuesto dinámico inferior a su suma.
Una asignación simultánea garantizada tiene otro significado y necesita su
propio contrato antes de comprobarla. Tampoco se incorporan búsqueda remota,
reglas mecánicas por marca, conversión nominal/medido ni inferencia de versiones.

La metadata debe resolver cada campo/columna/tipo y rechazar reglas extrañas,
referencias a campos legacy y ciclos que impidan la captura. SQL y Dart deben
consumir el mismo artefacto; el guardado agregado valida el estado completo
antes de persistir. Una forma inválida de filas nunca se convierte en lista vacía.

## Evidencia necesaria para cerrar

Fixtures positivas, contradictorias e incompletas para vínculo válido/ausente/
retirado; ANT+ verdadero/falso/desconocido; código Torx coherente/contradictorio;
rangos escalares exactos y valores fuera de precisión binaria. Añadir rechazo
de metadata con tipo/columna/campo ajeno o versión desconocida, preservación de
filas y fuentes, y prueba del mismo guardado atómico con revisión/tenant.

Verificar selección real en el editor reutilizando los controles canónicos,
sin depender sólo de la serialización del contrato. El catálogo ampliado se
ensaya en rollback local antes de una migración. Los gates de dominio,
asignación global y llenado permanecen cerrados.


## Contrato elegido e implementación local

`form_contract.row_coherence = {version: 1, links: [...]}` añade vínculos con
`id`, `field`, `column`, `target_field`, `label_columns`. La celda origen
almacena el `row.id` exacto del destino, con mayúsculas y ceros conservados.
Las etiquetas son presentación, nunca una clave ni una heurística para
reconciliar dos piezas parecidas. Editar/reordenar conserva los IDs; un importador
o el futuro fill debe conservarlos en su diff y proponer explícitamente los
reemplazos. Reacuñar destinos sin relink rechaza el guardado entero.

La plantilla conoce sus vecinos; una definición reutilizable no. Ambos extremos
son filas activas, la celda es texto/token sin vocabulario cerrado, las etiquetas
son columnas propias y no otros vínculos. El grafo incorpora prerrequisitos y
visibilidad existentes. No hay cascada destructiva. Destino desconocido produce
pendiente no bloqueante; un ID inexistente en destino conocido bloquea; un
destino mal formado conserva su error y no se trata como vacío. Marcadores de
unknown se reconocen al nivel del campo, no dentro de una celda de identidad.

`form_contract.scalar_ordered_pairs` compara límites numéricos de igual unidad,
con decimales exactos, igualdad permitida y ciclos rechazados. Los cuatro pares
heredados se mantienen en un único evaluador como fallback hasta su migración
de metadatos. Un par invertido afecta ambos campos en la publicación pública.
No evalúa ajuste físico ni suma de máximos de puertos.

Los helpers privados se integran en el validador central ya usado por RPCs y
constraints diferidos. La lectura por nombre rechazada revierte su intento en
subtransacción antes de devolver `rejected`, conservando hecho y cita previos.
El guard protege inserción/actualización de plantillas sobre definiciones ya
pobladas, también referencias OEM; cambiar sólo rótulos sigue siendo reversible.
Las unidades y el esquema de fila también disparan validación de metadatos.

El editor usa S-06 para elegir el destino, conserva un enlace huérfano y permite
corregirlo. Los lectores tipados conservan IDs y añaden `row_labels`; el display
público resuelve rótulos. Los errores de servidor se muestran con campo y posición
de fila, sin imprimir el UUID como dato de producto.

## Reconciliación con Claude

- La propuesta de clave natural se reemplazó por ID estable: renombrar o cambiar
  dimensiones no demuestra una identidad nueva; igualdad dimensional tampoco
  demuestra que dos piezas sean la misma. La conservación de IDs es contrato del
  futuro autor de diffs, no una inferencia automática del escritor.
- No se creó otro escritor ni otro mecanismo de integridad: los triggers
  diferidos existentes alcanzan todas las escrituras de hechos.
- R1/R2 se reprodujeron: inserción sobre definiciones pobladas y pares inversos.
  Ambos recibieron corrección. R3 permitió sólo cambios de rótulo sin migrar
  observaciones. Los tests de frontera siguen siendo de Claude; root ejecuta SQL.
- E4/E5 se corrigieron en su revisión: los parsers no rechazan keys desconocidas
  de nivel superior, y SQL 200 ya lee números en texto. Los bloques reconocidos
  nuevos sí tienen forma cerrada y versión validada.
- R5 (pérdida del mensaje de aplicabilidad) no coincide con SQL 200 actual:
  tiene `field_applicability` propio, distinto del `field_constraint` de forma.
  No se modifica una ruta basándose sólo en esa hipótesis.

## Evidencia actual

- 170 pruebas Dart de root, incluidas cuatro celdas de widget 390/1280 y claro/
  oscuro: renombrar, borrar destino, conservar observación y revincular.
- 282 pgTAP de regresión antes de sumar el benchmark y la suite independiente;
  la suite central de coherencia tiene 70 aserciones. Los totales se superponen.
- Fixture canónica compartida: `test/fixtures/product_spec_coherence.json`;
  la prueba Dart verifica que el documento embebido en SQL sea idéntico.
- Benchmark local de guardado de 32 campos + 20 filas, incluyendo constraints
  diferidos: **155.288 ms**, `.tmp/db/spec-coherence-performance.log`.
- Lectura guardada de producción, `product-spec-coherence-legacy-impact.sql`:
  **169 pares observados, cero invertidos y cero discrepancias de unidad**.
  Las cinco vinculaciones de plantilla existentes usan mm/mm, T/T o in/in.
- Ningún hecho de producto, asignación ni referencia se llenó con esta entrega.
  La prueba visual real de las nuevas filas en el editor del catálogo definitivo
  sigue al saneamiento y publicación de sus metadatos; el widget no sustituye
  esa evidencia de runtime.

## Addenda A/B integrados sólo localmente

El compilador reproducible es `scripts/inventory/compile_product_spec_field_addenda.py`.
Originales, dictámenes independientes, decisiones de root y 21 correcciones de
integración tienen archivos/hashes separados. Resultado
`all-family-reviewed-fields-2026-09-07.json`: **105 plantillas, 663 definiciones,
39 estructuras de filas y 1.141 usos de campo**. SHA-256
`cf8ebeb1e4e7dd32853b8618657a3f25e3f5428158702ef2e0adeb5b89978577`.

El ensayo SQL local de **55 casos de representación** pasó metadatos, condiciones,
filas y preservación de hechos/identidad y terminó en ROLLBACK. Casos SHA-256
`bd9bf655e3d0162e2bcb804dc43a963929e4af81d84ac84dc641da87fb3ede5f`.
Las correcciones incorporan relaciones modo→luz y reparto→puerto, 16 parejas de
límites en 14 familias, códigos Torx con un solo dueño y presentaciones de puños
por lado. No certifican los productos usados como ejemplos ni abren fill.

**Corrección del simulador, 2026-09-07:** el servidor omite `blocking` en varios
issues que por contrato son bloqueantes. Filtrar sólo `blocking='true'` podía
omitirlos y dar una aprobación falsa. El ensayo ahora usa
`coalesce((blocking)::boolean,true)` y los 55 casos volvieron a pasar. El mismo
criterio debe usarse en todo futuro simulador/aplicador; los totales de pruebas
anteriores a esta corrección no bastan por sí solos.

Siguen abiertos AG/GB, A01–A29/W01–W11 y las asignaciones por producto. En
particular: posición/miembros y duplicados de luces individuales, semántica
eléctrica y perfiles por puerto, KSA/roscas/contajes de kits, obligatoriedad
condicional dentro de filas, conflictos de fuentes frente a campos escalares
y los consumidores mecánicos. Esos pendientes pertenecen a Codex/Claude, no a
entrada manual del dueño.

## Cierre productivo 0200 y defecto numérico encontrado (2026-09-07)

0200 SHA `358a847c57086c4c9f27390c4dffee8398d3312b8e447f7e115db2024ed154ea`.
Receipt `.tmp/db/migration-receipts/20260907020000.receipt`. El verificador falló
antes del deploy por división por cero y pasó después: 12 funciones exactas,
ACL, triggers, rangos; también pasaron preservación legacy y lector 0100.
La revisión de Claude citaba el forward anterior a regenerarlo; el desplegado
sí contiene INSERT/UPDATE y la comparación funcional sin id/rótulos.

- 19 pruebas Dart independientes ejecutadas por root; 170 de la integración.
- 127 pgTAP de coherencia (70 root + 57 Claude); pruebas `like/unlike` adaptadas
  al pgTAP disponible mediante `ok(... like ...)`, sin cambiar su expectativa.
- 666 pgTAP, 15 archivos, en regresión completa. La aserción legacy ahora espera
  `rejected` y demuestra preservación exacta de hecho/cita al rechazar, en vez
  de esperar una excepción: es el contrato nuevo de la misma RPC.
- Las 1.664 lecturas del consumidor tipado autenticado pasaron. Evidencia
  `.tmp/product-spec-catalog/authenticated-coherence-typed-verification.json`.
- La sesión canónica recargó 143/5382 bibliotecas en 7,031 s. Frame y semántica
  `runtime-coherence-baseline.*`; no guardado. La UI de los campos ampliados
  sigue pendiente de publicar ese catálogo; el frame sólo verifica la base.
- El ensayo negativo del catálogo con número fuera de dominio realmente falló:
  `spec-catalog-negative-guard.log`. Una issue sin `blocking` es bloqueante;
  el simulador no puede filtrar sólo `blocking=true` explícito.

La primera prueba de Claude con lectura «10» encontró un defecto anterior en
`spec_reading_rejection_internal_v1`: recortaba ceros de enteros (`10→1`) y
convertía cero en patrón vacío. 2100 corrige sólo esa comparación numérica,
preservando signos y precisión y rechazando null/NaN; 41 casos pasan local.
El fixture histórico local tenía además una versión vieja del lector completo:
se alineó en local desde el preimage leído en producción, sin aceptar ese hash
viejo como preimage productivo. 2100 recibió revisión independiente acotada y quedó aplicado/verificado en
producción a las `2026-09-07T10:01:06Z`. Receipt:
`.tmp/db/migration-receipts/20260907021000.receipt`. SHA
`b2d900f93ef09036be4b73adfa77b8f620a3b4ccb0b1f56d3e69f351252b7e85`.
El verificador numérico falló antes y pasó después; también volvieron a pasar
0200 y la preservación completa. La comprobación literal no demuestra por sí
sola qué campo/modelo describe una cifra; no reemplaza investigación OEM.

No se llenaron ni reasignaron productos, no se sembró el catálogo de 105/663.
Siguientes paquetes independientes: frenos (consumidor confunde fluido con
accionamiento) y luces/electrónica/sensores (dueños duplicados y completitud).

Lectura autenticada del editor posterior a 0200: 38 productos/35 familias,
17 números exactos, cero errores (`authenticated-coherence-editor-verification.json`).
Frenos: 47 pruebas y recarga canónica 43/5382 en 4,966 s;
[alcance de la corrección](brake-consumer-integration-2026-09-07.md).
