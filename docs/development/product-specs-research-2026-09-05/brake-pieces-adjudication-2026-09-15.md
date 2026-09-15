# Sucesores de cáliper, pastilla y rotor: publicación verificada

Tres familias originales publicadas con `20260915043000`, sello y read-back
productivo a las 04:35:06 UTC. Parte del catálogo integrado
`e0cccea8…` y sus casos `3d8f9a4d…`; el congelado no se modifica. La captura viva
a 2026-09-15T03:36:12Z registra 11 cáliperes, 53 pastillas y 18 rotores (82
productos). Los snapshots autenticados de las 03:47 UTC se evaluaron con el
catálogo corregido: 82 pendientes, cero bloqueantes, 17 observaciones legacy
conservadas y ninguna observación activa sin proyectar. No se rellenaron datos.

Se conserva la identidad de las plantillas y cada campo real. No se crea como
legacy el uso nunca publicado de `hose_system_code` en cáliper. Los campos
retirados mantienen sus etiquetas, ayudas, valores predeterminados y observaciones
reales; el espesor antiguo del rotor no se rotula retrospectivamente como nuevo
nominal. La ayuda del compuesto ya permite conocer el nombre OEM sin inventar
su clase técnica. Las definiciones compartidas permanecen inmutables.

Pieza dueña del dato: tiro exigido por cáliper; puerto físico/fluido admitido
por modelo de pieza; interfaz de pastilla; montaje/espesor nuevo/límite de
desgaste del rotor. No se crean conjuntos ni se habilita recursión. Las manetas,
pares y frenos completos siguen fuera de este paquete y D2 sigue abierto. La
futura ubicación de herramientas por fijación/extremo no se resuelve con un
tamaño global del conjunto.

La revisión independiente 225 rechazó el primer SHA. La versión corregida
resuelve H1–H4: interfaz de montaje intrínseca única en la pinza; receta OEM
opcional que no puede cambiar su modelo ni su montaje; convertidor externo
fuera de la ficha de esta pieza; y fijación de la zapata perteneciente al cuerpo
o porta-goma, nunca al inserto. Se exige primero la construcción de la zapata.
La pinza de llanta declara la fijación que acepta. Sus puertos hidráulicos
declaran sólo entradas; los purgadores permanecen en su tabla propia. Las
restricciones de columnas son locales a esta plantilla y no modifican el
esquema compartido de recetas para futuros conjuntos.

Base consultada por Root: [Park Tool, sustitución de zapatas](https://www.parktool.com/en-us/blog/repair-help/brake-pad-replacement-rim-brakes)
distingue unidad completa, porta-goma e inserto retenido por tornillo o clip;
la fijación al brazo pertenece a la unidad, no a la goma de recambio.
[Park Tool, freno de disco mecánico](https://www.parktool.com/en-us/blog/repair-help/mechanical-disc-brake-alignment)
separa cable, brazo accionado, pinza y fijación a cuadro/horquilla. El contrato
representa esas piezas y sus interfaces; no deduce un montaje por marca.

Versión corregida: 61 pruebas Dart (tres plantillas y 58 casos), 58 casos SQL
y repetición exacta con rollback. Revisiones propuestas 2→30 (pinza), 2→23
(pastilla), 3→17 (rotor), 23 definiciones nuevas. Se conservan los cinco casos
antiguos de convertidor en `reviewed-v1`; al retirar su definición del dueño,
el escritor prueba el rechazo del ID ajeno en vez de fingir que el validador
de campos asignados es responsable de ese ID. La entrada y purga de un caso
anterior ahora se guardan en sus tablas correctas. El caso de puerto duplicado
conserva entrada y rechazo; con reglas de puerto la validación lo reporta antes
como `row_shape`. Correcciones de nombres esperados de error no cambian valores
ni relajan restricciones.

`test_brake_piece_profiles.py` prueba los tres sucesores con sus campos reales
en un grafo de colección sintético: tres perfiles conservan sus medidas,
rechaza el ID del convertidor externo, el montaje contradictorio en receta,
el espárrago falso del inserto, una plantilla ajena y la medida en la raíz.
La colección de prueba puede contener piezas que no se montan juntas; guardarla
no afirma compatibilidad. Las 20 aserciones pasan, incluyendo guardado independiente, salida pública
y criterios: el diámetro nuevo se muestra y permite distinguir 160 de 180;
el importado legacy queda fuera de esos consumidores.

Revisión 226: ningún consumidor vivo de estas familias convierte legacy en
dato nuevo. Se corrigen los dos consumidores Dart del diámetro: mapa del portal
y taller. Taller lee sólo el sucesor numérico y mantiene cautela; no extrae el
primer número de `180/160` ni redondea `180.5` para hacerlo coincidir. Las 91
pruebas del consumidor de taller pasaron; las 15 del portal pasan tras ajustar
la expectativa al texto numérico exacto. Analizador sin incidencias.

Once definiciones escalares nuevas tienen visibilidad pública y filtros,
seleccionadas explícitamente en `SURFACE_FIELDS`; fuentes y recetas no se
convierten en filtros simples. Ninguna definición ya publicada cambia sus
flags. Las observaciones retiradas son 13 importaciones y cuatro lecturas de
nombre, todas sin confirmar: están en **10 rotores y cuatro pastillas**, no en
13 rotores. Se conservan internamente como legacy y no se convierten
automáticamente a diámetro o espesor nuevo. La consulta productiva encontró
49 revisiones de necesidades y ninguna con las claves retiradas de freno;
no se reescribieron criterios guardados.

Compilador `scripts/inventory/compile_brake_piece_successors.py`; salidas
`brake-pieces-2026-09-15-{catalog,cases,packet}.json`; evidencia privada en
`.tmp/product-spec-catalog/brake-pieces-20260915/`. SHA del candidato SQL
`440d1cbbe0c0418d54fde6493d7e189a9db422a30ddac1c3ae975c5e04e37f3a`.
El SHA inicial rechazado queda en `reviewed-v1`. Claude 227 aprobó el SHA
exacto, sin bloqueantes. La publicación verificó metadatos exactos y los 58
casos de representación contra el validador productivo antes de registrar el
sello. Las revisiones efectivas son 30/23/17.

Lectura posterior autenticada de los 82 productos: identidad, datos comerciales,
revisión, 33 observaciones, referencias, valores del editor e historial intactos;
cero perfiles. Sólo cambió la metadata de las tres plantillas. Las 14 lecturas
anónimas bajaron de 24 a siete filas: desaparecieron únicamente las 17 claves
legacy previstas y los demás valores públicos se conservaron exactamente.
Evidencia: `publication-readback.json`, `public-before.json`, `public-after.json`
y ambos directorios `snapshots-*-publication` en la carpeta privada.

La app macOS real, editor enrutado y tema claro, comprobó tres borradores:
AE0269 mantiene 203 y 2,3 como datos anteriores y deja vacíos los sucesores;
nominal 2,3 y desgaste 2,4 producen conflicto visible. BB008 cambia los
requisitos de montaje/tiro con Disco/Mecánico y exige fijación de zapata al
elegir Llanta. En 2000000143019, el porta-goma requiere fijación; al elegir
Recambio de cartucho desaparecen la fijación y su requisito. Salida mediante
Atrás sin Guardar en los tres casos; read-back 04:43:03 UTC conserva todos los
datos retornados (`ui-discard-readback.json`). No se afirma prueba de esos
recorridos en teléfono, editor embebido ni binarios distribuidos.

Hallazgo para saneamiento de asignaciones existentes: entre los once productos
heredados con ficha de cáliper aparecen NNV55 («Freno Balata Genérico 90 mm»)
y 1062 («JUEGO FRENO DISCO LOGAN MECANICO C/ROTOR 160MM»). Sus nombres señalan
posible freno de maza y conjunto, respectivamente; requieren adjudicación con
evidencia antes del llenado. No se corrigieron por nombre ni se declara que
los once productos son piezas individuales. La adopción sin bloqueos demuestra
conservación de datos, no clasificación correcta.

Ningún llenado ni compatibilidad mecánica certificada. Las manetas y D2 siguen
abiertos; los consumidores Dart corregidos están recargados en debug, pendientes
de la próxima distribución autorizada.
