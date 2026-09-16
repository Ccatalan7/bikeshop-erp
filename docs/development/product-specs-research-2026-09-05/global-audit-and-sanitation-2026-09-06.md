# Auditoría completa y saneamiento previo al llenado

**Saneamiento aplicado, 15-09 04:02 UTC:** 720 asignaciones de clase en once
tandas, con 720 recibos y snapshots autenticados posteriores. Conservación de
identidad, inventario, precios y observaciones comprobada por producto. Quedan
26 registros marcados producto/no servicio sin ficha: nueve operaciones/costos
no requieren ficha de componente y diecisiete siguen en resolución. No se alteraron
flags comerciales ni se contaron esas nueve adjudicaciones como asignaciones.
Llenado cero. El filtro público de inferencias pendientes está publicado y
verificado (`20260915034000`); la cámara retenida conserva sus siete hechos y
publica únicamente las cinco observaciones de proveedor.
[Checkpoint con evidencia y límites](assignment-sanitation-checkpoint-2026-09-14.md).

**Primer reemplazo original publicado:** `drivetrain_kit` v3→v16, migración
`20260915023000`, revisión Claude 220 y seis lecturas autenticadas intactas.
La app real abrió una ficha por pieza y descartó el borrador sin cambios,
verificados a las 02:29 UTC. Se preservan once campos reales como legacy y se
usa `kit_members`; los tres prototipos nunca publicados no se crean.
[Adjudicación y pruebas](drivetrain-kit-members-adjudication-2026-09-15.md).
**Tres reemplazos adicionales publicados, 15-09 04:35 UTC:** pinza, pastilla y
rotor (`20260915043000`), revisión Claude 227, 82 lecturas autenticadas intactas
y 14 anónimas: sólo los 17 valores legacy salen de la vista pública, los siete
restantes permanecen. Los tres recorridos reales de escritorio se descartaron
sin guardar y se verificaron intactos a las 04:43 UTC.
[Cierre y límites](brake-pieces-adjudication-2026-09-15.md).
**Manetas publicadas, 15-09 05:41 UTC:** `brake_lever` v2→28 mediante
`20260915054000`, SHA `ded86efb…`, revisión Claude 229. Dieciocho lecturas
autenticadas y anónimas confirman conservación íntegra, cero hechos/perfiles y
cero valores públicos antes/después. La app real comprobó montaje por expansor,
rango invertido, transición a abrazadera con valores conservados para retirarlos
explícitamente, y exclusión de cable en la rama hidráulica auxiliar. Borrador
descartado y lectura intacta a las 05:53 UTC.
[Cierre y límites](brake-lever-adjudication-2026-09-15.md).
Son 73/105 entregas de plantilla (68 nuevas y cinco reemplazos adaptados); quedan
32 reemplazos originales. Este indicador no mide el avance global ni el llenado.
Además, `component_set` está publicado (`20260915035000`) y asignado a dos
conjuntos mixtos. Sus ocho familias se resuelven autenticadas; en NNV71 se abrió
un borrador de tornillería y se descartó, con datos intactos a las 04:02:35 UTC.
Es una familia adicional fuera del plan de 105, no otro original reemplazado.
[Cierre y límites](component-set-adjudication-2026-09-15.md).
Las cifras posteriores son checkpoints históricos fechados.

Checkpoint de distribución: [macOS 177 + Android 65 y auditoría de adopción](release-checkpoint-2026-09-07.md). Ambos publicados y verificados; el saneamiento global y el llenado continúan abiertos.

**Framework por componente publicado, 2026-09-14 21:43 UTC:**
`20260914213000_product_spec_member_profiles` quedó aplicado y verificado:
identidad inmutable por pieza, observaciones separadas, historial protegido,
guardado atómico y conflictos de revisión/categoría. Lecturas autenticadas
v3/snapshot v2 verificadas con productos reales, sin guardar productos de prueba.
En ese primer despliegue había cero perfiles y cero plantillas habilitadas.
El 15-09 a las 00:37 UTC se habilitaron nueve plantillas mediante
`20260915004000`, con verificación de metadatos, revisiones y 18 casos. Sus 68
productos se releen autenticados sin cambios de datos; siguen cero perfiles
persistidos. Esto no activa los 37 sucesores ni certifica compatibilidad mecánica.
El editor está integrado y sus correcciones E1–E4 fueron revisadas; la batería
ampliada pasa 95 casos. La app real ya leyó una cubierta con datos y un aceite
sin ficha, sin guardar. R1 quedó aplicado (`20260914225500`) con errores por
pieza estructurados. La prueba real a 430 px conservó el borrador al actualizar
y, tras descartarlo, confirmó el valor original; R5 no es una transición
expuesta porque los cinco llamadores bloquean el tipo de producto. Queda la
interacción de perfiles en las superficies reales antes de cerrar F2.
El guardado legacy tipado `20260914222500` está aplicado y
verificado; no reescribió datos. [Estado y evidencia](member-profiles-integration-2026-09-14.md).
Respaldo formato 2 verificado con 1.673 productos:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260914T220049Z-pre-fill`;
el formato 1 anterior también fue reabierto y verificado sin modificarlo.
El framework y los nueve opt-ins por sí solos no aumentaron la métrica de
plantillas; los reemplazos del kit y de cuatro piezas de freno llevan la entrega a
73/105. No repetirla como respuesta al avance global ni inventar un
porcentaje total; informar los criterios entregados y pendientes.

**Auditoría estructural fresca, 2026-09-16 09:17 UTC** (releída después de las 724
asignaciones y de los 37 reemplazos originales, como pedía la primera compuerta del
llenado): 1.673 registros, 1.614 productos físicos, **1.594 con plantilla efectiva**
(726 explícitas y 868 por categoría) y **20 sin plantilla**, que son exactamente los
veinte ya adjudicados en [assignment-remaining-2026-09-16.md](assignment-remaining-2026-09-16.md)
(diez sin ficha aplicable, dos piñones inactivos sin identidad y ocho registros sin
descripción ni imagen). 197 físicos sin categoría, sin cambio. 461 físicos con
observaciones, la misma cifra del 14: cero llenado. 1.133 con plantilla y sin observaciones
(eran 408, por las asignaciones). Un solo producto conserva un hecho fuera de su plantilla
efectiva (C1087, `spindle_diameter_mm` en `bottom_bracket_cup`; eran dos). La evaluación por
56 lotes con el validador desplegado dio 1.584 productos con pendientes, diez sin incidencia,
**cero bloqueantes** y cero revisiones desfasadas: 3.876 incidencias, de ellas 3.553
`required_missing`, 218 `row_cardinality_pending`, 89 `prerequisite_missing` y 16
`field_applicability`. 107 plantillas activas en 106 familias; cinco sin productos
(`bicycle`, `fixed_cog`, `frame`, `hub_brake`, `wheel`) y sólo 19 familias con alguna
observación. Cero perfiles persistidos. Huella comercial y de stock `9d6827fa…`, sólo para
comparar. Estos resultados no certifican identidad, asignación ni cobertura mecánica:
[resumen](global-coverage-summary-2026-09-16.json) (sha256 `bcd6d2af0d446873…`; instantánea
`adddd7c1c86851a6…`, evaluación `e842cd2fef0b9571…`), producido por
`scripts/inventory/refresh_global_coverage_audit.py`, que deja el detalle privado en
`.tmp/product-spec-catalog/global-audit-20260916/`. Llenado por esta tarea: cero productos.
**Auditoría estructural fresca, 2026-09-14 22:45 UTC:** 1.673 registros,
1.614 productos físicos, 868 con plantilla efectiva y 746 sin plantilla;
197 físicos sin categoría. Hay 461 físicos con observaciones y 408 con
plantilla pero sin observaciones. Dos productos conservan campos fuera de su
plantilla efectiva. La evaluación por lotes produjo 47 pendientes, cero
bloqueantes y cero revisiones desfasadas. Estos resultados no certifican
asignación ni cobertura mecánica: [resumen](global-coverage-summary-2026-09-14.json).
Llenado por esta tarea: cero productos.
**Precisión de clasificación:** «físico» en los conteos anteriores significa
marcado como producto/no servicio en la base. La revisión individual halló
costos, diagnósticos, trabajos y una nota de crédito dentro de esa población.
Deben adjudicarse como registros no materiales antes de presentar ese conteo
como número de piezas físicas que necesitan ficha; no se les asigna una familia
por coincidencias como «cámara» o «rayo» en el nombre de la operación.

**Nueve plantillas habilitadas el 15 de septiembre:** accesorios/reparación
con 29 checks Dart y 18 casos SQL (avance/repetición/rollback). Claude completó
la revisión 215 sin bloqueantes. La app real abrió la ficha propia de un soporte
incluido en una luz; se descartó el borrador y la lectura autenticada de las
01:10 UTC confirmó todos los datos originales. Después se verificaron las
etiquetas y la ficha del soporte a 430×940, con descarte y lectura intacta.
La interacción embebida sigue pendiente. [Adjudicación y evidencia](member-profile-enablement-adjudication-2026-09-14.md).
**54 asignaciones aplicadas y verificadas a las 23:51 UTC:** 31 candados,
16 luces y siete cintas de manillar. La RPC existente pasó 73 casos, el ensayo
cuatro recorridos SQL y el preparador ocho. Los 54 recibos persistidos y las
lecturas autenticadas posteriores confirmaron conservación de todos los datos
ajenos a la asignación. Conteo productivo a las 23:53 UTC: 922 físicos con
plantilla y 692 sin ella. Cero productos rellenados. Revisión final de esta
operación por Root; Claude no completó revisión por cuota.
[Aplicación y recuperación](assignment-slice-readiness-2026-09-14.md).
Segunda tanda verificada a las 00:01 UTC del 15 de septiembre: **149 asignaciones
adicionales en 19 familias**, con 149 lecturas autenticadas y recibos. Total: 203
asignaciones; 1.071 físicos con ficha y 543 sin ella; llenado cero. Guantes de
taller/moto excluidos y bolsos resueltos individualmente por clase, sin modificar
categorías comerciales. [Resultado](assignment-accessories-result-2026-09-14.md).

**Integración 2026-09-14:** [los 37 sucesores originales juntos](original-successors-integration-2026-09-08.md)
incluyen H1–H5 de bielas/platos y no presentan conflictos entre sus 376
definiciones compartidas. Pasaron 599 pruebas Dart (37 plantillas + 562 casos)
y 562 casos SQL con avance, repetición exacta y rollback, preservando datos.
Esto no activa las plantillas ni cierra las 40 pendencias documentadas.
La preimagen productiva del 14 de septiembre confirma que las 37 originales
siguen sin cambios de plantilla/campos/definiciones desde el checkpoint previo;
sus asignaciones efectivas crecieron de 863 a 868 productos.
Las 868 capturas autenticadas actuales se evaluaron contra el catálogo nuevo:
cero bloqueantes, cero observaciones activas fuera de proyección, 1.056
observaciones legacy conservadas y 863 productos pendientes de datos.
[Resumen por familia](original-successors-adoption-summary-2026-09-14.json).
Esta adopción no sanea las asignaciones ni completa la investigación mecánica.

Avance local posterior: [cinco originales de rodamientos/motor](existing-bearing-bb-root-decisions-2026-09-07.md)
con 81 pruebas Dart, avance/replay y 76 casos SQL en rollback. Auditoría de los
57 productos efectivos: cero conflictos bloqueantes, 132 observaciones legacy
preservadas y 52 productos pendientes de datos. Candidato sin aplicar, SQL fuera
de las migraciones desplegables. **Las 37 originales siguen pendientes de
activación.** Las siete originales de frenos tienen un
[candidato con 91 pruebas Dart y 84 casos SQL locales](existing-brakes-root-decisions-2026-09-07.md);
con ensayo de adopción de 124 productos: cero conflictos bloqueantes,
21 observaciones legacy preservadas y los 124 con datos pendientes. La revisión
mecánica sigue abierta. Cassette, freewheel, fixed_cog
y cassette_spacer tienen candidato corregido: variantes OEM fuera de facts del
SKU. [La revisión de Root](existing-rear-cogs-root-decisions-2026-09-07.md)
distingue integración pendiente de un evaluador que ya existe.
[Las cinco de neumáticos/cámaras](existing-tires-tubes-root-decisions-2026-09-08.md)
tienen 55 pruebas Dart, 50 casos SQL de avance/repetición en rollback y ocho
declaraciones de alcance ejecutadas en ambos motores. Adopción de 264 productos:
cero bloqueantes, 808 observaciones legacy preservadas y todos pendientes.
[Rayos con secciones físicas y contenido identificado](existing-spoke-readiness-2026-09-08.md)
tiene 32 pruebas Dart y 31 casos SQL de avance/repetición en rollback; 48 productos
evaluados, cero bloqueantes, 19 observaciones legacy preservadas y todos pendientes.
La revisión del delta confirmó las correcciones; su observación menor sobre
una designación de rosca no publicada también está corregida.
Neumáticos y rayos siguen sin aplicar.
[Direcciones](existing-headset-readiness-2026-09-08.md) tiene un candidato por
extremo con 23 pruebas Dart y 22 casos SQL de avance/repetición en rollback,
bajo la extensión local de orden estricto.
Adopción de sus 15 productos: cero bloqueantes, cuatro observaciones legacy
preservadas y todos pendientes. Sin activar; faltan los cruces mecánicos
documentados y la validación/distribución del cliente. La revisión independiente
confirmó el reparto por extremo; la inversión ID/OD encontrada se corrigió
sin otro motor. El [orden estricto compartido](strict-row-order-readiness-2026-09-08.md)
también rechaza la igualdad entre ID y OD del mismo cuerpo; su revisión final
está cerrada; el motor fue aplicado y verificado con migración `20260908185800`,
sin reinterpretar los rangos inclusivos existentes ni activar nuevas fichas.
[Mazas y llantas](existing-hub-rim-root-decisions-2026-09-08.md) tienen un
candidato adjudicado con 65 pruebas Dart y 63 SQL en rollback. Sus 89 productos
se evaluaron sin bloqueantes, con 22 observaciones legacy preservadas y todos
pendientes. La revisión independiente confirmó las cinco adjudicaciones; sus
dos observaciones sobre presencia del receptor y cotas de taladrado ya están
corregidas y verificadas localmente. Claude confirmó esas correcciones finales;
no se ha activado.

**Medición al 14 de septiembre:** 68 nuevas plantillas publicadas de las 105
entregas del plan = 64,8 % de esa etapa, no del encargo completo. La lectura
de metadatos a `2026-09-14T19:12:44.384968+00:00` confirmó las 68 nuevas activas y
las 37 originales aún presentes; ese conteo no demuestra que sus correcciones
hayan sido activadas. De las 37 originales ya existen 37 candidatos
(5 rodamientos, 7 frenos, 4 piñonería, 5 neumáticos/cámaras, rayos, direcciones,
mazas, llantas, tres de servicio de transmisión, cadenas/conectores/kits,
mandos/desviadores y bielas/platos). Los 37 tienen candidato de Root integrado
con SQL local; los últimos tres incorporan ya la revisión independiente H1–H5.
La adopción de datos ya se renovó sobre 868 productos. Eso no cierra los
pendientes de referencias, consumidores, editor ni activación.
Son candidatos con distintos pendientes, no familias terminadas.
Las tres de servicio de transmisión ya tienen propuesta de Claude y correcciones
de Root sobre dueño del peso del conjunto y declaraciones por roldana:
[52 pruebas Dart, 49 casos SQL y adopción de 33 productos](existing-drivetrain-service-parts-root-decisions-2026-09-08.md),
sin bloqueantes, sin observaciones activas fuera de proyección y todos pendientes.
La [entrada de fuentes y preimagen](existing-drivetrain-service-parts-source-notes-2026-09-08.md)
se conserva; Claude aceptó el delta final sin defectos vigentes. No se han activado.
[Cadenas, conectores y kits](existing-chain-drive-readiness-2026-09-08.md)
conservan la base aplicada y añaden declaraciones por destino y miembro: 37
pruebas Dart, 34 casos SQL con avance/repetición/rollback y adopción de 41
productos, sin bloqueantes, una observación legacy y todos pendientes.
Revisión independiente recibida: F1/F3/F4 corregidos y reproducidos;
F2 (perfil técnico tipado por miembro de kit) e integración siguen abiertos.
[Mandos y desviadores](existing-shifting-root-decisions-2026-09-08.md):
51 Dart, 48 SQL y adopción de 82 productos sin bloqueantes, todos pendientes.
[Bielas y platos](existing-crank-drive-root-decisions-2026-09-08.md):
H1–H5 entregados y devueltos a Root en el mensaje 192; sus 69 casos pasan en la
integración Dart y SQL de las 37. La adopción actual incluye 51 productos de
estas tres familias (28 volantes, siete brazos, 16 platos), sin bloqueantes ni
observaciones activas fuera de proyección; los 51 pendientes de datos.
Sin activar ni llenar.
Ninguna original ha sido activada. El
saneamiento transversal, las asignaciones faltantes y el llenado siguen
abiertos; llenado aplicado = 0 %. No se sustituye esto por un porcentaje global
sin denominador estable ni se suman pruebas como si fueran productos terminados.

Ya existe un [candidato local de aplicador de investigación](research-application-readiness-2026-09-07.md),
con backup/recibo por producto y procedencia separada. Tiene pruebas locales;
no está publicado ni habilita el llenado. Preparador, registrador, aplicador y
recuperación pasaron un recorrido SQL/Python local, además de tres sondas de
contención entre dos sesiones. Revisión final, despliegue y smoke autenticado
publicado, más saneamiento global, continúan pendientes.

Compras: 89 regresiones y analizador sin incidencias para separar límites de
valores exactos y usar aplicabilidad/opciones v2. La revisión independiente
confirmó ese comportamiento y descubrió un fallo al agregar campos a una
plantilla abierta con el mismo ID; se corrigió con siembra por campo que conserva
lo escrito. Falta runtime y distribución de ese cliente antes de activar las
originales. No se atribuye el arreglo a macOS177/Android65.

Checkpoint actual: [mando combinado aplicado y verificado](combined-control-integration-2026-09-07.md),
migración `20260908032000`, a las 04:14:54Z del 8 de septiembre UTC (7 LA).
56 pruebas Dart, 55 casos SQL y cinco regresiones del publicador; lectura
API autenticada y fingerprints preservados. **68 nuevas activadas; ninguna
nueva pendiente.** Las correcciones de las 37 originales y el saneamiento
transversal siguen abiertos. Llenado y asignaciones nuevas: cero.

Checkpoint previo: [bicicleta, cuadro y rueda aplicadas](complete-assembly-integration-2026-09-07.md),
migración `20260908030000`; antes, [hidráulica](hydraulic-parts-integration-2026-09-07.md)
y [frenos/adaptadores](brake-adapter-parts-integration-2026-09-07.md).

Checkpoint anterior: [4 plantillas de cables de mando](control-cable-parts-integration-2026-09-07.md)
y [4 de transmisión pequeña](drivetrain-small-parts-integration-2026-09-07.md)
aplicadas y verificadas a las 02:08:51Z y 02:05:27Z del 8 de septiembre UTC
(7 de septiembre en Los Ángeles). Lecturas autenticadas, 82 casos SQL,
90 pruebas Dart y diez regresiones del publicador. Son **57 nuevas activadas**;
faltan 11 nuevas, las correcciones de las 37 iniciales y el saneamiento
transversal. Productos, facts y asignaciones preservados. Llenado nuevo: cero.

Checkpoint anterior: [4 plantillas de suspensión y dirección aplicadas](suspension-headset-parts-integration-2026-09-07.md)
a las 2026-09-08T01:24:32Z, migración `20260908011000`: 35 definiciones nuevas,
45 opciones y 53 usos; diez compartidas intactas. Son 49 plantillas nuevas
activadas. 39 casos SQL en producción y lectura autenticada comprobados.
Asignaciones y llenado nuevos siguen en cero; quedan 19 nuevas, las correcciones
de las 37 iniciales y el saneamiento transversal.

Checkpoint anterior: [9 plantillas de piezas de rueda aplicadas](wheel-small-parts-integration-2026-09-07.md)
a las 2026-09-08T00:43:49Z, migración `20260908001000`: 42 definiciones nuevas,
49 opciones y 74 usos; siete compartidas intactas. Son 45 plantillas nuevas
activadas. 35 casos SQL en producción, lectura autenticada y preservación de
datos comprobados. Asignaciones y llenado nuevos siguen en cero; quedan 23
plantillas nuevas, las correcciones de las 37 iniciales y el saneamiento transversal.

Checkpoint anterior: [10 plantillas de puntos de contacto aplicadas](contact-points-integration-2026-09-07.md)
a las 23:49:20Z, migración `20260907235000`: 99 definiciones nuevas,
114 opciones y 133 usos; 10 compartidas intactas. Son 36 plantillas nuevas
activadas. SQL, lectura autenticada y preservación de datos comprobados.
Asignaciones y llenado nuevos siguen en cero; faltan 32 plantillas nuevas,
las correcciones de las 37 iniciales y el saneamiento transversal.

Checkpoint anterior: [14 plantillas de movilidad aplicadas](mobility-accessories-integration-2026-09-07.md)
a las 23:24:21Z, migración `20260907233000`: 113 definiciones nuevas,
224 opciones y 163 usos; 9 definiciones compartidas sin cambios. Con las
anteriores son 26 plantillas nuevas publicadas, sin nuevas asignaciones ni
llenado. Casos SQL reales y lectura autenticada comprobados. La corrección del
consumidor de compras está en código probado y requiere próxima distribución.

Checkpoint anterior: [12 plantillas no motrices aplicadas](non-drivetrain-publication-integration-2026-09-07.md)
a las 22:34:13Z, migración `20260907222000`: 93 definiciones nuevas,
186 opciones y 132 usos de campo. Lectura autenticada, 37 casos sobre
producción y preservación de productos/facts/mapeos comprobadas. No hay nuevas
asignaciones ni llenado. El origen `new` de esas definiciones en los catálogos
congelados es histórico; ahora son compartidas y no se deben recrear.

Estado de esta ronda: auditoría nominal/estructural terminada; saneamiento en
curso. Ningún producto fue rellenado ni reasignado en producción. La revisión
de los campos no equivale a haber implementado sus correcciones ni certificado
todas las interfaces de las familias.

## Continuación 2026-09-07: coherencia y addenda

Checkpoint posterior: [puertos y aplicabilidad 2600](port-cardinality-integration-2026-09-07.md)
aplicado/verificado a las `18:58:08Z`, 1.265 pruebas SQL y preservación real de
datos. Catálogo propuesto de 105 plantillas/711 definiciones, 323 casos SQL;
llenado y asignaciones aplicadas siguen en cero. La captura autenticada de 1.664 preimágenes y el ensayo de adopción ya están
terminados: 863 fichas evaluadas sin conflictos bloqueantes, 813 observaciones
legacy retenidas y 801 productos sin ficha; ver el checkpoint de distribución.

**Corrección de seguimiento del 7 de septiembre:** se retiran los porcentajes
intuitivos 35–40 % y 30–35 %. No tenían un denominador estable ni cierres
comprobables y no sirven para medir el costo del trabajo. El avance se informa
por entregas activadas, productos/familias revisados con su alcance y pendientes
concretos. El saneamiento global sigue siendo requisito antes del llenado;
publicar un bloque de saneamiento revisado no equivale a dar por terminado el
catálogo entero ni autoriza rellenar sus productos por adelantado.

[Estado ejecutable y pendientes](row-coherence-integration-2026-09-07.md).
El catálogo local conserva 105 plantillas. El último checkpoint completo,
[cardinalidad](cardinality-integration-2026-09-07.md), tiene 711 definiciones,
1.218 usos, 313 casos SQL en rollback y 422 Dart. La etapa previa de
[contenido y fuentes](evidence-scopes-integration-2026-09-07.md) pasó sus 302
casos SQL después de corregir en 2500 las celdas requeridas desconocidas.
A/B (663 definiciones, 55 casos) y el
artefacto base de 558 definiciones permanecen congelados como evidencia de revisión.
Ninguno de esos conteos equivale a una familia mecánicamente terminada. El
forward 0200 está aplicado/verificado (`2026-09-07T09:51:35Z`), con 1.664
lecturas autenticadas del consumidor. 2100 (citas numéricas) también está aplicado/verificado (`2026-09-07T10:01:06Z`);
fill=0. Frenos tiene dos correcciones del consumidor y un paquete de campos
integrado localmente. [Luces/electrónica/sensores](light-power-sensor-integration-2026-09-07.md)
ya pasó adjudicación e integración local. [Ruedas/dirección/rodamientos/suspensión](wss-integration-2026-09-07.md)
pasó integración local con 35 casos nuevos; su revisión independiente sigue
abierta y no equivale a compatibilidad mecánica completa. La base mecánica
`f3178bd3…` permanece congelada con sus 84 casos.
Las [condiciones dentro de una fila (2200)](row-condition-integration-2026-09-07.md)
quedaron aplicadas/verificadas a las `2026-09-07T11:22:41Z`, con 767 pruebas SQL,
385 Dart y concurrencia en ambos órdenes. No se confunden con compatibilidad
OEM resuelta ni con habilitación de llenado. Los 48 campos de configuraciones
ya pasaron revisión de prerrequisitos: 14 cambios de metadatos integrados en
`all-family-row-conditions-integrated-2026-09-07.json` (`c12204e4…`), con 132
casos SQL y 241 comprobaciones Dart. La auditoría también identifica 18 campos
con carencias que requieren más capacidad del motor o relaciones OEM.

El [simulador de investigación](research-simulator-integration-2026-09-07.md)
tiene 73 pruebas Python y 107 específicas SQL (36 + 71 independientes); la
suite SQL completa llega a 874. Es lectura y simulación sin escritor de
productos. El [consumidor de ruedas](spoke-wheel-consumer-integration-2026-09-07.md)
separó el conteo agregado de la bicicleta de los dos lados; 57 pruebas pasan.
La infraestructura está aplicada hasta 2500 (`2026-09-07T15:44:15Z`), con 1.255
pruebas pgTAP, 210 Python y smoke autenticado posterior de 38 productos y 35
familias. La comprobación global posterior leyó además los 1.664 productos en
24,886 s, sin errores, escrituras ni diferencias de IDs. No convierte en
cobertura mecánica completa los diagnósticos de las reglas vigentes.
El borrador abierto sobrevivió la recarga real sin cambios semánticos.
La preimagen del 7 de septiembre conserva una actualización externa de fuente
en un hecho HV408; no se reemplazó el respaldo ni se restauró ese cambio.
Los [20 productos cuestionados](assigned-product-root-decisions-2026-09-07.md)
tienen adjudicación de Root: 10 cambios sustentados pendientes de gates,
7 conservar, 1 condicionado por contenido y 2 con identidad pendiente.
El [consumidor de transmisión/frenos](consumer-scope-integration-2026-09-07.md)
pasó 82 pruebas y recarga conservando el borrador, sin ejercicio completo del
autocomplete de taller. Cardinalidad genérica y su activación local en coronas
pasaron concurrencia en ambos órdenes; AG01 de contenido/consumidores sigue
abierto. Continúan ambigüedades documentales y los otros pendientes globales.
La revisión de los 33 registros sin ficha (22 ambiguos y 11 de negocio) recibió
[lectura actual de 26 por Root](unmapped-26-root-evidence-2026-09-07.md): dos
familias respaldadas, una con conflicto de marca, dos intervenciones de
servicio documentadas y 21 pendientes. La [adjudicación conjunta posterior de
los 33](unmapped-33-root-adjudication-2026-09-07.md) suma seis familias
respaldadas, una con conflicto comercial, dos intervenciones documentadas y
24 identidades/clasificaciones todavía pendientes. Root releyó los siete de
Claude y abrió sus cuatro imágenes disponibles; las inferencias de ausencia
por tablas parciales quedaron retiradas. Ningún inactivo sale del alcance. El [seguimiento
Garozzo](garozzo-identity-document-readback-2026-09-07.md) leyó tres compras sin
encontrar identidad/etiqueta suficiente para GZ0009/GZ0010.
El aplicador de llenado autenticado aún falta;
no se abren gates por aprobar pruebas.

## Alcance y resultados comprobados

Se incluyeron **1.664 registros: 1.605 productos físicos y 59 servicios**,
activos e inactivos. Los servicios conservan su contrato de trabajo; cafetería,
electrónica, scooter, ropa, accesorios y herramientas sí necesitan atributos
de producto adecuados a su objeto. No se excluyen por no ser transmisión.

| Comprobación en la instantánea legacy | Resultado |
|---|---:|
| Productos físicos con plantilla / sin plantilla | 863 / 742 |
| Productos físicos con alguna observación | 461 |
| Productos con plantilla sin observaciones | 403 |
| Productos físicos sin categoría | 197 |
| Productos con hechos fuera de su plantilla | 2 |
| Plantillas / familias actuales | 37 / 36 |
| Definiciones revisadas / usos en plantilla | 136 / 280 |
| Productos con avisos de requisitos existentes | 47 |
| Conflictos bloqueantes detectados por reglas existentes | 0 |
| Familias aprobadas como completas para llenar | **0** |

Que las reglas existentes no encuentren conflictos no prueba que cubran los
casos mecánicos necesarios. La auditoría semántica encontró campos con ejes
mezclados, cardinalidad ambigua, opciones cerradas por el stock, medidas sin
alcance, kits sin composición y relaciones de compatibilidad pendientes.

El [registro consolidado de los 1.664 IDs](all-product-review-register-2026-09-06.json) vincula asignación, diagnóstico nominal, evidencia de imagen y pendientes; valida que no falte ni se repita ningún producto.

Evidencia por registro:

- [863 productos con ficha, revisión de Claude](assigned-product-ficha-claude-review-2026-09-06.json).
- [742 productos sin ficha, revisión de Codex](unmapped-product-ficha-codex-review-2026-09-06.json),
  con [revisión independiente](unmapped-and-template-binding-claude-review-2026-09-06.md).
- [136 definiciones revisadas](all-fields-semantic-review-2026-09-06.json).
- [21 imágenes del catálogo inspeccionadas](product-identity-image-review-2026-09-06.json).
- `.tmp/product-spec-catalog/all-products-audit.json`: evaluación estructural
  exhaustiva generada por `scripts/inventory/audit_product_spec_coverage.py`.

Las 108 clases candidatas del inventario sin ficha son hipótesis de identidad,
no 108 plantillas nuevas obligatorias. Reutilizar una interfaz no autoriza a
tratar una extensión de pata como pata, un peg como pedal o una goma protectora
de cable V-Brake como pastilla. Categorías comerciales mixtas requieren
asignación de plantilla por producto.

## Correcciones a la revisión nominal

Los 36 `fact_issues` iniciales de Claude son **observaciones por verificar**,
no 36 contradicciones demostradas. HV408 sin fuente no es por ello incompatible;
24 declaraciones BSA sin evidencia no se vuelven falsas automáticamente;
un diámetro nominal 24 no se convierte automáticamente en BSD 507. La Cámara
«NO ES EXACTAMENTE LA MISMA» conserva su ambigüedad de variante aunque la foto
demuestre que es una cámara. El kit Logan fotografiado trae dos cálipers y dos
discos, sin manillas: no se presume un sistema completo. La imagen de Neco no
convierte la marca comercial Andes en un error confirmado.

## Estado legacy recuperable

Carpeta independiente del checkout:
`/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260906T222802Z-pre-fill`.
Contiene copia cifrada AES-256-GCM, manifiesto, verificación, herramienta
autónoma y `Abrir estado legacy.command`. La clave está en el Llavero del Mac;
no se imprimió ni se guardó en el repositorio.

- Instantánea MVCC: `2026-09-06T22:27:50.089535Z`.
- SHA-256 de la instantánea:
  `52d083195dd3d5d7ac25d6f3e1f361941e088d9678bc3dac629d8251681e0dd7`.
- SHA-256 cifrado:
  `f15a92a5dc07b1a7a1cf8e97f3881c4ec20085019a872fb276a1ae2e0d357bfb`.
- 1.664 productos, 1.653 hechos, 904 enlaces de opciones, 14 lecturas,
  37 plantillas, 136 definiciones, 280 campos y 11 referencias; incluye código
  HEAD y overlay sucio exacto sin alterar el checkout.
- Descifrado autenticado, hashes, identidades, referencias y recuperación por
  campo verificados; seis pruebas del recuperador. **No se ensayó restauración
  PostgreSQL.** Es anterior al llenado y posterior a las dos primeras
  migraciones de arquitectura, no una copia previa al rediseño.
- El proveedor también tenía copia `2026-09-05T10:07:25.926Z`, anterior al
  rediseño; PITR deshabilitado. Su retención es independiente de esta carpeta.

La reversión debe preservar cambios posteriores y operaciones comerciales.
El [runbook](../../runbooks/DATABASE_BACKUP_AND_RESTORE.md) distingue consulta
legacy, recuperación local y reversión selectiva de producción.

## Corrección numérica desplegada

`20260906150000_product_spec_numeric_domains.sql` se aplicó y registró en
producción el `2026-09-06T23:22:47Z`, SHA-256
`56d09fc554ed4d4c00a0428e6312014201ab1d18f9a5ae6091e1a1f2825c40db`.
Corrige 35 definiciones usadas por 22 plantillas: medidas positivas finitas,
conteos enteros, cero donde corresponde y offset con signo. Conserva la
semántica de cantidades; no convierte límites de catálogo en leyes mecánicas.
No modificó valores, referencias, categorías, stock ni precios de productos.

Las pruebas reprodujeron 21 fallos antes del cambio; luego pasaron 36 pruebas
SQL nuevas (135 con contratos anteriores) y 47 Flutter. El verificador falló
antes del despliegue y después comprobó 35 reglas, cero hechos fuera del nuevo
dominio, versiones de las 37 plantillas y función evaluadora intacta. Recibo:
`.tmp/db/migration-receipts/20260906150000.receipt`.

La base local histórica carecía de 12 definiciones presentes en producción;
se añadieron como fixture mínimo, sin clonar producción. Esta diferencia de
catálogo debe resolverse en la reproducibilidad global; no se oculta tras las
pruebas focalizadas.

## Base común desplegada y verificada

Las migraciones 160000, 170000 y 180000 están aplicadas, verificadas y
registradas en producción. No escribieron fichas ni asignaciones de productos.

| Migración | Verificada UTC | SHA-256 |
|---|---|---|
| 20260906160000 · vínculo por producto | 2026-09-07 02:58:33 | bf46ca8592500abdbcb6435740a3657653ec97450fdc9364c9d193f2cf179694 |
| 20260906170000 · frontera legacy | 2026-09-07 02:59:49 | 7aac4171546c39ba5ff66c3c3add3776bb67a52b4b7d0ef5e1e2567f44d3b53b |
| 20260906180000 · relaciones con alcance | 2026-09-07 03:01:21 | 8fcecbf5f43f1f99bcfe25f9a6c9c02dd5d1ce8e3cfc820a4f6070e77076b54f |

Recibos y hashes de verificadores:
`.tmp/db/migration-receipts/202609061{60000,70000,80000}.receipt`.
Los tres despliegues comprobaron conservación exacta de hechos, opciones,
lecturas, recibos, definiciones de plantilla, mappings e identidad técnica.
Las migraciones aplicadas son inmutables; sus generadores temporales no deben
volver a escribirlas. 170000 reemplaza intencionalmente el escritor legado
cuyo preimage verificaba 160000: ejecutar después el verificador antiguo
completo no es una comprobación válida del conjunto final.

El producto posee su vínculo de ficha y la categoría sirve de respaldo. La
retirada concurrente está protegida por FK. Los escritores filtran por ID de
definición dentro de la ficha; una clave global/tenant homónima no es un
override. Los datos retirados o ajenos conservan procedencia y no participan
como criterios técnicos. El lector automático real también exige el ID
activo y valida dependencias antes de responder que guardó. El DELETE del
mirror distingue producto, bici y job_bike incluso cuando comparten UUID.

Las relaciones v2 separan alternativas AND/OR y exclusiones, con fuente por
fila y tipos decimal/token/boolean. Los decimales viajan como cadenas exactas;
una configuración que ya llegó como número JSON no sirve de evidencia sin
pérdida para ese evaluador. Una exclusión desconocida impide aprobación; estar
fuera de la cobertura declarada no significa incompatible. No se sembraron
relaciones OEM nuevas ni se conectó aún a aprobación completa de taller.

Revisiones: `product-template-binding-claude-review-2026-09-06.md` A0–A5 y
`spec-boundary-independent-review-2026-09-06.md`. Se integraron sus correcciones
de identidad, ACL, concurrencia, decimal y URL. No se retiró
`getTemplateForCategory`: sí tiene llamador en compras. Los hechos fuera de
ficha ya no aparecen como respuesta técnica en edición masiva.

## Verificación observada y regresión de rendimiento

- 361 pgTAP de ocho archivos y 138 Flutter de cinco archivos pasaron antes del
  despliegue; seis pruebas del cliente autenticado y seis del backup también.
- El análisis completo tiene cero errores y 583 issues del checkout compartido;
  no equivale a cero advertencias. El análisis focalizado de relaciones tenía
  cero errores/advertencias y una info de llaves, ya corregida.
- Con la sesión real Debug, `/auth/v1/user` confirmó el actor y se leyeron por
  HTTP autenticado los **1.664 contexts y 1.664 bindings**, en bloques de 50.
  Evidencia: `.tmp/product-spec-catalog/authenticated-global-binding-verification.json`.
  El transporte no imprime credenciales, no refresca sesión y rechaza rutas
  ajenas y redirects. El futuro aplicador necesita otro comando revisado.
- Los **1.605 editores/snapshots físicos** pasaron el smoke SQL de lectura en
  bloques de 50. El contexto SQL de principal no se presenta como HTTP real.
- Hot reload de la sesión `payroll`, PID90499, y `Actualizar ficha` consultaron
  el nuevo editor preservando el borrador HV408, 6/7/8, 11/128 y 7.1. No se
  guardó, cerró ni reinició el formulario. Evidencia semántica:
  `.tmp/product-spec-catalog/runtime-fresh-binding-context.txt`.
- El smoke global descubrió un defecto real pendiente: la búsqueda v7 de KMC
  aislada agota 30 s en inferencia → resolución activa por hecho. La lectura
  monolítica de 1.664 contextos también agota 30 s. No se da por cerrado el
  despliegue funcional; se prepara una optimización por conjuntos en 191000,
  conservando ID/tenant/legacy/ambigüedad. Dictamen:
  `spec-binding-performance-review-2026-09-06.md`.

Las correcciones del taller de esta ronda bajan ocho aprobaciones incompletas
y siete rechazos sin alcance a revisión: tamaño nominal de rueda no basta para
comparar BSD; tipo de válvula montada no prueba diámetro del agujero; cambiar
rotor necesita conocer adaptador y límites. Esto tampoco certifica todas las
reglas negativas históricas.

## Saneamiento de todas las familias: implementación en curso

Claude entregó el blueprint de 37 plantillas existentes y 68 nuevas, con
cobertura nominal de las 108 clases y todos los IDs del registro. SHA JSON:
`250a32e47592aec332d39bb7672197510848f1c9ce78ba53580a4888aedac1a3`.
El contrato compilado posterior (`all-family-compiled-contract-2026-09-06.json`)
contiene 539 definiciones, 105 plantillas, 15 esquemas de filas y 140 interfaces;
SHA `785cd11a39011b643e4bcb1422ab805c242f8a7aae0108b399c6aff0c0d78175`.
Ambos entregables están congelados. Que 476 fixtures validen la compilación no
verifica los hechos mecánicos; el flag `verified` de ese JSON no es aprobación
para convertir una URL general en ley.

La revisión de ruedas/dirección/suspensión documenta 11 fallos y 14
contraejemplos primarios: hookless y presión por variante, interferencia de
amortiguador por cuadro/año/talla, función de rodamientos, los dos biseles,
puertos SHIS y stack, horquillas y envolvente, OLD132.5 y alternativas 130/135,
roscas pasantes incompletas, calibre frente a rosca de radios y recetas de
radiado. Archivos `wheels-steering-suspension-source-review-2026-09-06.md/.json`.
Claude revisa por separado frenos y transmisión; su entrega de correcciones
mecánicas todavía debe integrarse y verificarse.

Se implementa un borrador **local 190000** para hechos estructurados y editor
de filas: cada configuración retiene sus celdas, identidad y fuentes; números
exactos, rangos ordenados y posiciones únicas. Una lista de componentes técnicos
no cambia `is_set`, no crea productos hijos ni altera inventario comercial.
Todavía no están sembradas las nuevas familias, corregidas todas las reglas,
asignadas las fichas faltantes, ni preparado el aplicador de llenado.

## Orden de trabajo vinculante

1. Auditar los 1.664 registros con ficha y sin ella y conservar legacy.
2. Sanear asignación e interfaces/campos de todas las familias presentes, con
   evidencia y casos válidos/inválidos/desconocidos; cerrar consumidores reales.
3. Repetir auditoría global y verificar recuperación/concurrencia/procedencia.
4. Aplicar el llenado investigado por producto y campo con fuente, comparación
   anterior/posterior y conservación de observaciones ajenas.

Ninguna familia está aprobada todavía para llenado. No se adelanta un piloto de
cadenas. La investigación preparatoria continúa mientras se implementa la base.


### Configuraciones por fila y lectura técnica (2026-09-06, actualización)

`20260906191000` ya está aplicada/verificada (receipt UTC 2026-09-07T03:40:31Z;
SHA `4e110f4f86d081c5b1ab14f2d0dc3f20636af0406dc6cce278e5e500872143ea`).
La búsqueda v7 KMC completa pasó de exceder 30 s a 4,953 s en la misma consulta
de producción. Pasan v4/v5/v6/v7 y ambos inspectores, tres necesidades de compras,
y el lector público por una muestra de 35 plantillas publicadas (29 campos).
La consulta sintética que agrega toda la tienda en una sola llamada excede 30 s;
la superficie pública lee un producto. No es evidencia de aprobación global.

`20260906190000` está aplicada/verificada (2026-09-07T03:59:44Z, SHA
`53e0ac8b6313ae226ecba9d6b69aebf16f359223f78698434653836055866483`): 17 funciones
con postimagen, ACL, autoridad y almacenamiento verificados; nueve preimágenes
productivas coinciden. Mantiene `value_json` separado de escalares, filas con
identidad/celdas/fuentes, decimales exactos y esquema versionado. Una configuración
incompleta avisa; un rango invertido, tipo falso o posición repetida bloquea.
Las referencias protegen el esquema incluso sin productos asociados y no pueden
perderlo por DELETE. Esquemas poblados requieren migración explícita.

Pruebas: 285 pgTAP integradas (filas, relaciones, identidades, asignación,
frontera legacy y rendimiento); 107 Dart/widget (incluyen lectura de referencia
sin editar en 390/768/1280 y ambos temas). El analizador global no reporta errores;
conserva avisos/info preexistentes del checkout compartido. Los fixtures prueban
serialización, autoridad y estado, no compatibilidad física OEM.

El formulario muestra filas por configuración con los controles canónicos y
reutiliza el mismo lector para referencia, legado e historia sin ficha. Quita la
acción engañosa que pretendía retirar datos legacy protegidos. Estos cambios no
se han demostrado todavía en una ficha nueva de la app real: se verificarán al
publicar los esquemas de las familias, preservando el borrador actual.

Claude llegó al límite de sesión en Fable 5.1/Ultracode (reinicio visible 23:20).
Su generador falló en un JSON Pointer de fixture: Codex recuperó la propuesta de
67 parches en `all-family-mechanical-corrections-2026-09-06.json/.md`, explicitando
su autoría y que las hipótesis no son instrucciones del dueño. Sigue pendiente
la adjudicación mecánica; no se aplican por existir una URL o un flag verified.


Read-back adicional: los **1.664 productos** pasaron el RPC autenticado
`get_product_spec_typed_configurations_v1` por bloques de 50. Se verificaron IDs,
plantillas, tipos y transporte decimal; evidencia privada
`.tmp/product-spec-catalog/authenticated-typed-configurations-verification.json`.
La sesión Debug existente (screen payroll, PID 90499) recibió hot reload en 6,661 s,
sin excepciones nuevas. La ficha abierta KMC HV408 conservó el borrador manual;
no se guardó. Los nuevos esquemas por familia y sus filas aún no están sembrados,
así que esta comprobación no demuestra todavía la edición real de esas filas.


## Condiciones de campo y compilación global — actualización 22:08 PDT

`20260906200000_product_spec_field_conditions.sql` está **APPLIED** y verificada
a `2026-09-07T05:02:10Z` (SHA-256
`643f526a7dbb2a794373c3a90a169806906abf116a144efdd187832eabe1ecda`).
Su recibo está en `.tmp/db/migration-receipts/20260906200000.receipt`.

- `rules_version:2` define `allowed_when`, `required_when`, opciones locales y
  prerrequisitos. Alternativas son OR; condiciones de una alternativa son AND.
- UI y SQL conjugan visibilidad nueva y heredada. Dato faltante es pendiente;
  dato presente contrario al requisito es bloqueante y no se borra solo.
- El guard de metadatos impide referencias a claves ajenas/retiradas, ciclos
  incluso con visibilidad heredada, tipos incompatibles, opciones fuera de
  dominio y versiones de tipo incorrecto. Cambios de clave/unidad invalidan
  editores; bloqueos de filas serializan cambios de definición/plantilla.
- Los códigos `01` y `1` se conservan literales. Los números ordinarios de la
  ficha se proyectan a texto para evaluar condiciones decimales; esto no
  convierte el editor numérico antiguo en transporte de precisión arbitraria.
- **379 pgTAP**, incluidos los 54 casos independientes; **135 Dart/widget**,
  incluidos 26 independientes. Analyzer completo: cero errores, 587 avisos/info
  del checkout (tres sugerencias const nuevas en tests). Ver
  [dictamen](field-conditions-independent-review-2026-09-06.md).
- Read-back remoto pasó pines de funciones/triggers/ACL y conservación de
  hechos, lecturas, referencias, opciones, asignaciones e identidad técnica.
- Hot reload canónico: 142/5380 bibliotecas, 6.788 s. Ficha HV408 y borrador
  6/7/8, 11/128, 7.1 conservados; imagen y lectura semántica en
  `.tmp/product-spec-catalog/runtime-after-conditions-reload.*`. No se guardó
  ese borrador. Las 105 propuestas aún no están sembradas en producción.

La compilación [all-family-reviewed-fields-2026-09-06.json](all-family-reviewed-fields-2026-09-06.json)
contiene **105 plantillas, 547 definiciones (419 nuevas), 16 campos de filas y
1012 usos de campo** en este checkpoint. Conserva por ID las definiciones del
[read-back de metadatos productivos](all-family-existing-metadata-2026-09-06.json),
recupera dos campos legacy de pistones omitidos por el borrador, aplica sólo
17 parches aceptados de Claude y separa sus propuestas mecánicas no resueltas.
El compilador y el ensayo son `scripts/inventory/compile_product_spec_catalog.py`
y `scripts/inventory/product_spec_catalog_trial.py`.

El ensayo completo pasó los guards SQL para las 105 plantillas y terminó en
**ROLLBACK**: `.tmp/db/all-family-catalog-trial.log`. Usa un tenant sintético
con claves, tipos y condiciones idénticas, e IDs aislados: el catálogo local
carece de `rim_etrto` y tiene claves históricas que no están en producción,
por lo que no se lo presenta como clon o prueba de despliegue productivo.
La comprobación de identidad/tipo contra producción es independiente y utiliza
el snapshot guardado antes citado. No se cambiaron hechos de productos.

Correcciones nuevas de campos incluyen ángulos interior/exterior de rodamiento,
neumático/cámara incluidos separados, sistema rotacional con nombre declarado,
cámaras con varias combinaciones BSD/ancho, alcance superior/inferior de dirección,
configuraciones por posición en juegos de ruedas y BSD delantero/trasero en
bicicletas. Trek Slash Gen 6 demuestra por qué una sola medida de rueda no
representa todas las bicicletas; no se presume que ese modelo esté en inventario.
Los gates globales y `fill_allowed` **siguen en falso**: falta adjudicar todas las
interfaces, completar asignaciones dudosas y construir el aplicador de llenado
con evidencia por valor y control de revisión.


## Checkpoint de continuidad — 2026-09-06, 22:30 LA

El avance global se comunicó como **estimación 35–40%**, no como métrica
calculada desde tests, URLs o número de plantillas. Los 1.664 registros están
inventariados y revisados nominalmente; las decisiones dudosas de asignación
siguen abiertas. **Llenado aplicado: 0 productos.** El backup legacy accesible
sigue en `/Users/Claudio/Vinabike Backups/Product Specs Legacy/20260906T222802Z-pre-fill`.

La revisión independiente de 37 plantillas fuera de transmisión/frenos/ruedas
entregó 24 hallazgos y 32 fuentes, con 81 targets comprobados. El integrador
incorporó partes de nueve hallazgos como C13–C18: pedales con apoyos mixtos y
calas incluidas, interfaces distintas de potencia/adaptador, rieles y kits de
tija, suplemento sin atributos de tija completa, componentes de candado,
propiedades ópticas por lente y manga/talla OEM. El estado preciso por hallazgo
está en [non-drivetrain-integration-status-2026-09-06.json](non-drivetrain-integration-status-2026-09-06.json).
No se presentan los 24 hallazgos como resueltos ni estas familias como aprobadas.

Compilación actual: **105 plantillas, 558 definiciones (430 nuevas), 19 campos
estructurados y 1.024 usos de campo**; SHA-256
`7ebf2b5b5e69784e3d146b81ad2bec8b7581113565cef022e8da70ba4c7a66fa`.
Se incorporó el dictamen independiente a las huellas de entrada del compilador.
El ensayo SQL de todas las plantillas y **11 casos de representación** pasó,
conservó hechos/identidad y terminó en **ROLLBACK**. Casos y límites están en
[all-family-representation-cases-2026-09-06.json](all-family-representation-cases-2026-09-06.json),
SHA-256 `3398c6ab51e393a96edfa483cbacf57930feabb370e5fd6e246121926096c60e`.
Log: `.tmp/db/all-family-catalog-trial.log`. Son casos de regresión de campos;
las medidas sintéticas no se presentan como mediciones OEM o productos en stock.

Revisión del log de la última recarga: hubo timeouts y fallos DNS en tareas,
notificaciones y correo, seguidos de recuperación de realtime. No hubo markers
`EXCEPTION CAUGHT`, `Unhandled Exception` o `Reload rejected` en el segmento
inspeccionado. No se atribuyen los fallos de red a los campos ni se afirma que
la sesión completa estuvo libre de errores. Se preservó el borrador KMC.

Para continuar: resolver el resto de A01–A29, W01–W11 y ND01–ND24; cerrar
transporte decimal del editor; probar los contratos de las familias en todos
sus consumidores y superficies; preparar la migración de metadata con preimagen
productiva y sin inventar hechos; resolver las asignaciones pendientes; construir
el aplicador autenticado de cambios sólo de ficha con backup/revisión/evidencia;
recién después ejecutar investigación y llenado por productos. Todos los gates
globales de publicación y llenado permanecen en falso. No volver a desplegar ni
regenerar las migraciones ya aplicadas hasta 200. Serializar wrappers de DB local.

Claude quedó limitado en el mismo chat de colaboración; su propuesta congelada
y los dictámenes permiten continuar sin repetirla. Durante este checkpoint el API de
cuota Codex informaba 93% consumido y dos reinicios disponibles; no se usaron.
Esta lectura de cuota es histórica, no un pronóstico de consumo restante.


## Continuidad 2026-09-07 — lector exacto aplicado, addenda ND en revisión

Se cerró el lector escalar de ficha con `20260907010000` APPLIED+verified a
07:45:05Z; funciones v1 y datos preservados. El [checkpoint exacto](exact-numeric-transport-checkpoint-2026-09-07.md)
es el dueño de pruebas, hashes, smoke autenticado y frames de la app real.
No hubo guardado del producto abierto, asignación de fichas ni llenado.

Claude entregó addendumA:82 parches/48 definiciones para8 plantillas, todavía
pendiente de adjudicar e integrar. AddendumB en curso y revisión independiente
de A; la copia base7ebf2b5b queda congelada para ambos. Un dato con fuente OEM
no queda aprobado si mezcla revisiones: el revisor ya detectó esa posibilidad
en el caso Cateye. El compilado105/558/1024 permanece sin modificaciones hasta
aplicar sólo los cambios aceptados con sus correcciones. Todos los gates de
publicación/compatibilidad/fill siguen cerrados. El dueño usó su reset y pidió
continuar; no cerrar la tarea ni consumir el restante por cuenta del agente.

## Preimagen de las 37 originales — 7 de septiembre, 20:15 LA

Lectura guardada actual: 37 plantillas, 280 usos y 128 definiciones. [Delta contra la propuesta congelada](existing-37-template-delta-2026-09-07.json): 37 contratos difieren y se proponen201 usos adicionales; esto no adjudica ni aplica esos cambios. La consulta de products.spec_template_id dio cero referencias explícitas, **no cero productos con ficha**: el audit autenticado de19:10 identificó863 asignaciones efectivas vía categoría/referencia. La huella de productos/defaults sigue preservada. Antes de modificar estas plantillas se debe evaluar el binding efectivo y sus observaciones, no sólo contar el FK nullable. Ninguna de las37 se considera saneada por esta comparación.

## Publicador para las37 existentes — 7 de septiembre,20:50 LA

[Infraestructura local verificada](existing-template-publication-readiness-2026-09-07.md): siete pruebas de compilador y siete transacciones SQL con rollback. La nueva lectura confirma863bindings efectivos. Hay21 diferencias compartidas respecto del congelado que se preservarán/adjudicarán por uso. Sin publicación de esas37, sin asignaciones y sin llenado.
