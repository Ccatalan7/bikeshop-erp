# Mandos y desviadores: adjudicación y adopción local

El sucesor de tres plantillas conserva las 21 definiciones publicadas y propone
19 nuevas, 53 usos y 33 cambios de metadatos. **Sin activar, reasignar ni llenar
productos.** La propuesta de Claude se conserva en sus archivos originales;
`compile_existing_shifting_root.py` produce los archivos `adjudicated`.

## Cambios con dueño y fuente

Cada mando de un par es dueño de su declaración. Las declaraciones globales del
par quedan prohibidas, el enlace identifica una fila real y un miembro ajeno
bloquea. Un par contiene exactamente dos mandos. Las tablas de declaraciones
distinguen destino y resultado (admitido, excluido o condicional); una condición
ausente no se presenta como compatibilidad confirmada.

Los selectores globales de ecosistema, plataforma y actuación pasan a legacy.
Las velocidades y límites de los cambios pertenecen a configuraciones completas,
sin listas independientes que formen cruces. La página oficial de
[RD-U6000](https://bike.shimano.com/en-NA/products/components/pdp.P-RD-U6000.html)
documenta límites distintos de piñón grande para 1x10 y 1x11. Se representan en
filas distintas. El retorno inverso del resorte describe el sentido de acción;
no se conserva la afirmación infundada de que demuestra incompatibilidad.

En desviadores delanteros, el mínimo de «top gear» es el límite inferior del
**plato grande**, no los dientes del plato pequeño. Se separan capacidad total,
diferencia grande–medio (sólo triple), ángulo y línea de cadena con datum. La
tabla Claris de [Shimano, handbook v3.2 2024–2025, p. 140](https://productinfo.shimano.com/pdfs/product/archive/2024-2025_Specifications_v032_en.pdf)
se leyó en texto y en el frame de la página 142 del PDF. Directo y reducción de
abrazadera ocupan celdas distintas. El reductor sólo admite un tubo nominal
menor que la abrazadera nominal receptora; no se interpretan esas designaciones
como cotas mecanizadas. [El despiece FD-R2000](https://dassets.shimano.com/content/dam/global/cg1SHICCycling/final/ev/ev/EV-FD-R2000-4160.pdf)
identifica los casquillos, pero no acredita su inclusión en cada envase.

## Evidencia ejecutada

- 51 pruebas Dart: tres plantillas y 48 casos, con valores y fuentes inmutables.
- 48 casos SQL con avance, repetición exacta, preservación y rollback. La
  extensión estricta se instala sólo dentro de esa transacción local.
- Captura autenticada de 82 productos, cero errores y cero escrituras:
  32 mandos, 35 cambios traseros y 15 desviadores delanteros.
- Adopción: 82 evaluados, cero bloqueantes, cero observaciones activas fuera de
  proyección y los 82 pendientes de datos. No demuestra corrección mecánica de
  los valores ausentes ni adopción publicada.

Catálogo `924a77009aff0db778c3e909c8e286edf9d80037c94f0739a0d800d89d145c39`;
casos `ca7feac7c5b72fb41b4fe495368e611aec1d40ad1a96ed05436186440bd3630a`;
preimagen `7cee2317b653acf176d48e4bbed3f3afdca54dafae6535de52262a415c40f655`,
capturada a `2026-09-08T19:18:13.338096Z`. Publicador:
`compile_existing_shifting_publication.py`. Los alias SQL se fijaron tras leer
el código, campo y gravedad reales; no cambian las reglas ni los veredictos.

Evidencia privada en `.tmp/db/existing-shifting-candidate/` y
`.tmp/product-spec-catalog/existing-shifting-{root-tests,adoption-tests,snapshot}.log`,
`existing-shifting-adoption-20260908.json` y el manifiesto
`existing-shifting-snapshots-20260908/manifest-20260908T192137237366Z.json`.

## Pendientes concretos

Claude recibió la revisión del delta en el mensaje 187 del chat «Diagnóstico
fichas técnicas Viñabike», Code / Opus 5 / repositorio correcto, sin subagentes.
La revisión independiente llegó en el mensaje 188: confirmó las reglas y
las fuentes; sus observaciones H1–H4 precisaron los casos. La columna conjunta
11/10 conserva su mínimo48T en conditions, sin inferir un mínimo por variante.
Las filas indican su origen en una misma declaración, y los casos de claims
completan destino/veredicto. El caso FD incluye cadena y línea nominal43.5, con
pendencia explícita de datum no publicado; no se inventa ese dato (H5). Faltan adjudicar su respuesta,
referencias OEM con identidad exacta, integración de evaluación de montaje,
validación/distribución del cliente y activación guardada. Los mandos combinados
detectados deben pasar por la cola de asignación con evidencia; no se reasignan
por el título. El motor de orden estricto ya fue publicado como
`20260908185800`; eso no publica estas definiciones v2 ni distribuye el cliente.
