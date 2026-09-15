# Rodamientos y límites hookless: integración residual

El compilador `compile_product_spec_wss_residual_addendum.py` integró ocho de
los diez cambios de la revisión congelada `239ab660…`. El ángulo interno del
rodamiento se distingue de los biseles de asiento; el SKU de un pedalier no
identifica automáticamente sus rodamientos sueltos. Un cartucho abierto no
admite una designación de sellado, y ni un sello ni la aplicación implican que
el rodamiento se pueda reengrasar. Se conservan desconocidos y códigos OEM.

En las declaraciones hookless pasan a ser pendientes explícitos la unidad de
presión y el ancho interior máximo. No se fabrican mínimos ni se impone un
límite universal. Se rechazaron los dos escalares nuevos para presión porque
perderían una de las cifras publicadas en bar y psi. El escalar anterior en
psi queda legacy; la tabla que lo sustituye se integra en la etapa siguiente.

| Artefacto local congelado | Resultado |
| --- | --- |
| all-family-wss-residual-integrated-2026-09-07.json | SHA `00041bb82cbddec1278a4d310d26747601518356abce5af4138da9bab7aa4b06` |
| all-family-wss-residual-cases-integrated-2026-09-07.json | SHA `da0b43e638820fce0fafcf93b53431c96d4be174e4bc180038e20e2d5ab851d9` |
| Cobertura de representación | 105 plantillas, 710 definiciones, 57 tablas de filas, 1.217 usos, 287 casos |
| Dart | 396 pruebas, `.tmp/product-spec-catalog/all-family-wss-residual-dart.log` |
| SQL local | 287 casos, guards y preservación exacta de facts/identidad, ROLLBACK; `.tmp/db/spec-all-family-wss-residual-trial.log` |

Quince fixtures de WRFP se integraron y cuatro se difirieron porque usaban
los escalares rechazados. Las preimágenes y cambios exactos se registran en
`wss-residual-root-decisions-2026-09-07.json` y
`wss-residual-root-fixture-overrides-2026-09-07.json`. El ensayo detectó que una
fila con forma inválida corta la evaluación de celdas: se preservó su bloqueo
`row_shape`, sin exigir pendientes que ese camino no emite. También se corrigió
el orden esperado de los diagnósticos. No se rebajó un conflicto a válido.

La revisión de Claude y sus fuentes están en
[wss-residual-field-packet-2026-09-07.md](wss-residual-field-packet-2026-09-07.md).
La representación posterior de cifras por documento está en
[tire-pressure-dual-unit-proposal-2026-09-07.md](tire-pressure-dual-unit-proposal-2026-09-07.md).
Los originales permanecen congelados; sus correcciones se adjudican sin
reescribir la evidencia anterior. Publicación y llenado permanecen cerrados.
