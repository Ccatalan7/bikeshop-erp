# Mazas y llantas: adjudicación de Root, candidato sin aplicar

El compilador del candidato actual es
`scripts/inventory/compile_existing_hub_rim_root.py`, que aplica estas decisiones
sobre la propuesta independiente. Ejecutar sólo el compilador de Claude
reconstruye el candidato anterior. Las 27 definiciones publicadas se conservan
exactamente; los cambios afectan sus usos y agregan 30 definiciones nuevas.
Resultado: dos plantillas, 57 definiciones, 60 usos y 63 casos, con 65 pruebas
Dart superadas. Pasaron avance, repetición exacta y los 63 casos SQL locales
con rollback. No se publican metadatos ni productos.

## Decisiones y causas

La corrección de Claude para los juegos resolvía ancho y perforación, pero
dejaba un solo eje, anclaje de rayo, rodamiento, disco y geometría de bridas
para dos piezas. Ahora esas propiedades pertenecen a cada maza identificada.
El juego no puede declarar los escalares de una maza suelta. Cada fila tiene
fuente e identidad, y sus booleanos controlan su propio receptor, disco y eje
incluido. La cantidad documentada de este alcance (delantera más trasera) se
compara con sus filas; una sola pieza deja el juego incompleto y repetir un
extremo bloquea. No se toma un título comercial como prueba del contenido.

El campo antiguo de rosca de eje pasante se retira a legacy. [Park Tool](https://www.parktool.com/en-us/product/thru-axle-tap-tap-20-2)
ubica la rosca en la puntera; no es el diámetro del paso por la maza. La ficha
puede identificar un eje pasante realmente incluido, cuyas cotas pertenecen
a esa pieza y al montaje en cuadro/horquilla. La nueva sujeción y el diámetro
con datum también representan ejes de 14 mm sin modificar el vocabulario
compartido. [Profile Racing](https://www.profileracing.com/profiles-tech-tip-29-mind-the-gap-converting-your-axle-from-14mm-to-38/)
documenta ejes de 14 mm, ejes hembra y kits de conversión concretos. Que el
vocabulario antiguo no los alcance es una carencia de representación, no una
razón para abandonar dos productos ni convertir números de sus títulos en hechos.

«Contrapedal» no identifica por sí solo la retención del piñón. Se separan
construcción y referencia del receptor, preservando como legacy la etiqueta
antigua. Las conversiones entre configuraciones y los receptores con varios
puertos (por ejemplo, ambos lados de una maza) todavía necesitan una
representación por montaje/puerto documentado. Esta entrega no los certifica.

La revisión independiente encontró que la presencia del receptor se trataba
distinto en una maza suelta y en una pieza de un juego. Ambas rutas exigen ahora
una declaración explícita de presencia, que controla tipo y referencia. La
posición no sustituye esa declaración ni la compatibilidad OEM. El caso
sintético de una pieza delantera sólo comprueba paridad de representación;
no certifica un montaje ni un modelo comercial.

El perfil de una llanta precede a los datos de talón. Una llanta tubular no
recibe las medidas internas ni la declaración tubeless de una interfaz
clincher; [TUFO](https://www.tufo.com/en/tubular/) describe el tubular y su
montaje pegado. Coincidir en BSD es necesario para un talón, pero no demuestra
compatibilidad de ancho, perfil, presión o montaje. El agujero de válvula pasa
a medida propia, sin reducirlo a dos nombres de válvula. Los rangos de ancho
conservan su configuración y documento; cambiar de URL no crea otro alcance.

Se rechaza excluir cotas OEM porque aún no las use otro módulo. La ficha
técnica es también consumidora de esa información. [DT Swiss R 470](https://www.dtswiss.com/en/components/rims-road/endurance/r-470)
publica altura de perfil y ERD; [Weinmann](https://www.weinmanntek.com/technology/6/6)
describe métodos de unión y agujeros. Esas propiedades conservan su fuente.
El ERD exige el datum OEM: [Ryde Andra 29 R](https://www.ryde.nl/andra-29-r/)
lo rotula respecto de ID −2 mm y diferencia agujeros en el asiento de niple y
en el fondo del neumático. No se intercambian sus cifras.
La observación F-2 de la revisión quedó corregida: el agujero del fondo del
neumático tiene una cota propia. El taladrado conserva por patrón OEM sus
ángulos radial y axial, desplazamiento zigzag, datum y documento. Sus valores
no se copian entre variantes ni se mezclan con el agujero del asiento del niple.

La tensión máxima de una llanta es un límite del componente, distinto de la
tensión medida al armar una rueda. [Park](https://www.parktool.com/en-us/blog/repair-help/wheel-tension-measurement)
remite al fabricante de la llanta y explicita condiciones de medición;
[Ryde](https://www.ryde.nl/andra-29-r/) publica un límite en N. Se conserva por
configuración, unidad y documento; no se convierte una lectura del tensiómetro
en fuerza ni se aplica ese límite a todas las llantas.

## Adopción y límites de la evidencia

Se capturaron 89 fichas por API autenticada, sin errores ni escrituras.
Adopción del candidato: 48 mazas y 41 llantas, cero bloqueantes, 22 observaciones
legacy preservadas (7 y 15) y ninguna activa sin proyección. Las 89 están
pendientes de datos. Es conservación de información, no llenado ni aprobación
de montajes. Las identidades individuales permanecen en `.tmp`.

La preimagen se capturó a `2026-09-08T10:27:24.441689Z`. El avance SQL está
sólo en `.tmp/db/existing-hub-rim-forward-candidate.sql`. El ensayo de adopción
está en `.tmp/product-spec-catalog/existing-hub-rim-final-delta-adoption-20260908.json`,
sobre `existing-hub-rim-snapshots-20260908/manifest-20260908T100239843699Z.json`.
Dos nombres de error SQL se explicitan como `field_constraint` en las fixtures
tras comprobar el mismo campo, bloqueo y mensaje de forma en ambos motores.
Las incidencias SQL sin atributo `blocking` son bloqueantes; un diagnóstico
auxiliar no debe convertir su ausencia en falso. El verificador final conserva
esa semántica y pasó sin cambios del motor.

La [revisión independiente del delta anterior](existing-hub-rim-independent-delta-review-2026-09-08.md)
confirmó las cinco adjudicaciones y la conservación de las 27 definiciones.
Sus observaciones F-1 y F-2 se corrigieron después; las 65 pruebas Dart,
63 SQL y la nueva adopción corresponden a ese resultado final. Claude no
verificó SQL. La [revisión final posterior](final-dimensional-delta-review-2026-09-08.md)
comprobó F-1 y F-2 mediante ejecución Dart y confirmó ambas sin defectos.

Pendientes antes de activar: representaciones
de conversión/puertos y relaciones OEM, validación del editor real y distribución
del cliente. La prosa ISO no se compara aún automáticamente con las cifras,
ni se valida aritmética entre cotas de brida. El ejemplo Novatec de Claude
procede de un distribuidor, no de una lectura de un plano OEM: no autoriza
convertir cotas ni rellenar una variante comercial.

Catálogo SHA-256 `7585bdb1f1b5365e7474324b37e6d20a287d92cbce74319ed53af3ffb663b1a3`;
casos `bab19fbb361c1823c01c373704298013ba6ff3c56027bb44f01eb972552f774c`;
preimagen `247c106d4aab8d342931739dc4acb964ddbe6184fd18f0c9a4d8357e653f5b78`.
