# Consumidor del taller: identidad, interfaz y alcance — 2026-09-07

Se corrigen comparaciones que emitían incompatibilidad desde un dato de otro
objeto o de alcance insuficiente. Esto no certifica el montaje: los resultados
incompletos continúan en precaución. La integración del catálogo ampliado y el
llenado siguen bloqueados por los pendientes globales.

La revisión independiente de Claude está congelada en
`consumer-drivetrain-brakes-independent-review-2026-09-07.json`, SHA-256
`f24afa06e3517172fab92d00589e7544c981d8897e5a7bdac81ae3c9076484e3`.
Sus fuentes mecánicas estaban referenciadas sin releer; Root volvió a consultar
las fuentes siguientes y adjudicó sus conclusiones, sin adoptar todas sus reglas.

| Problema | Implementación y límite |
| --- | --- |
| Una clave compartida como rotor_mount_type enviaba una maza al evaluador de frenos | Primero se despacha por la identidad técnica. La comprobación del ancho de maza conserva su prioridad aunque existan atributos de freno. |
| Pastilla implicaba disco; contrapedal rechazaba toda manilla; el tipo de freno agregado se aplicaba a ambas ruedas | La familia no rechaza por ese dato. El producto conserva su superficie; hace falta la rueda, el sistema instalado y el alcance de reemplazo/conversión. No se inventaron campos de bicicleta sin un productor real. |
| Bielas comparadas como caja del cuadro | El evaluador de crankset separa la interfaz de eje y no llama al comparador de caja de pedalier. Una coincidencia parcial conserva pendientes de línea de cadena, longitud y montaje. |
| Desigualdad escalar de ancho convertida en prohibición universal | Se pide configuración exacta y modelo. No se autoriza un espaciador ni se presume que todos los modelos roscados o a presión cubran varios anchos. El conflicto conocido Mid/BSA sigue impidiendo montaje directo. |
| Interfaz de eje múltiple tratada como token único | Se leen alternativas tipadas de spindle_interface_accepted; GXP no se convierte en eje Shimano 24 mm. La pertenencia a una lista sigue sin acreditar configuración, adaptador ni ensamblaje completo. |
| Mando sin lado comparado contra ambos extremos | Sin lado o con Universal se requiere elegir instalación. Sólo derecho/par compara el indexado trasero; izquierdo no se compara contra esa familia trasera. |
| Diferencia de platos tratada como imposibilidad permanente del cuadro | Se exige conversión explícita o cobertura OEM del modelo. No se recomienda dejar una posición sin usar. Un conflicto trasero conocido de un par conserva prioridad. |
| Cantidad de platos extraída de cualquier dígito de un texto | Se aceptan únicamente cantidades canónicas; el desviador lee compatible_chainring_counts. Notas de modelo no fabrican cantidades. |

Fuentes releídas por Root:

- [Park Tool: estándares de pedalier](https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-standards-and-terminology)
  y [selección de herramienta para presión](https://www.parktool.com/en-us/blog/repair-help/bottom-bracket-tool-selection-press-fit):
  caja y eje son interfaces distintas; un adaptador es otra pieza con condiciones.
- [Shimano DM-MAFC002-11, pp. 12 y 14](https://si.shimano.com/en/pdfs/dm/MAFC002/DM-MAFC002-11-ENG.pdf):
  configuraciones 68/73 roscadas y 89,5/92 a presión, con espaciadores específicos.
  Esto refuta la propuesta D3 de conservar toda desigualdad pressfit como
  incompatibilidad. No demuestra cobertura de cualquier otro pedalier.
- [Sheldon Brown: contrapedal](https://www.sheldonbrown.com/coaster-brakes.html):
  describe el freno en la maza trasera y su coexistencia con freno delantero.
- [Shimano SI-5N20A-002](https://si.shimano.com/en/pdfs/si/5N20A/SI-5N20A-002-ENG.pdf)
  y [DM-SL0001-11](https://si.shimano.com/en/pdfs/dm/SL0001/DM-SL0001-11-ENG.pdf):
  hay modelos con selector 2x/3x y otros sin él. No se acepta la regla general
  de D7 de usar cualquier mando triple omitiendo una posición.
- [Park Tool: desviador delantero](https://www.parktool.com/en-us/blog/repair-help/front-derailleur-advanced-troubleshooting):
  un cambio de platos exige volver a comprobar la combinación delantera.

Pasan **82 pruebas del consumidor**, incluidas 25 regresiones nuevas. Dos
expectativas previas de rechazo por superficie agregada se corrigen porque no
tenían rueda confirmada; Universal deja de equipararse a un par. El analizador
de los dos archivos no encuentra problemas. Evidencia:
`.tmp/product-spec-catalog/consumer-scope-tests.log` y
`.tmp/product-spec-catalog/consumer-scope-analyze.log`.

El revisor adicional reprodujo los 82 tests y no encontró una regresión en
los límites encargados; su [dictamen final](consumer-scope-boundary-review-2026-09-07.md)
está congelado: JSON SHA `d3d3a667f6584af057894e3e4cdde72276a96b938ed1fe41ca445243ebc9e7ca`,
MD SHA `1694fe85972ccfe04ee0716633644bd85bf3f70ab09f6dce3541d7c7dfccf99b`.
La segunda tanda se recargó en `payroll`: 43/5.383 bibliotecas, 5,026 s,
PID 90499 sin reinicio. El texto semántico del borrador HV408 permaneció
idéntico y Root inspeccionó el frame real
`.tmp/product-spec-catalog/consumer-scope-runtime-after.png`. No hubo guardado
ni cambio de producto. Esto acredita carga del código y preservación del
borrador, no el ejercicio del autocomplete del taller. Los 82 tests no
certifican nuevos modelos OEM ni el flujo completo
del taller. Quedan abiertos la representación por rueda y alcance del trabajo,
los controles combinados, la integración de las configuraciones nuevas y AG01
(cantidad de platos físicos incluidos frente a capacidad/configuración de un
juego de bielas). La cantidad nueva de crankset no se infiere del viejo campo.
