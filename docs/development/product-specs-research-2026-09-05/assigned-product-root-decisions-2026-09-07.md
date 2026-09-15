# Asignaciones cuestionadas: decisión de integración

Root adjudicó los 20 IDs de la revisión independiente congelada
`852577ba…`. El [resultado estructurado](assigned-product-root-decisions-2026-09-07.json)
tiene SHA `9e33fd5d08e69c8e54c5228ecc387e1f0abe234f400855916b7eb829d0abe8ac`
y se reproduce con `scripts/inventory/adjudicate_product_spec_assignments.py`.

| Decisión | Cantidad | Alcance |
| --- | ---: | --- |
| Cambio de plantilla adjudicado | 10 | AP02, AP04, AP05, AP08, AP09, AP11, AP13, AP15, AP19, AP20; espera publicación verificada y gates globales |
| Conservar plantilla | 7 | AP01, AP03, AP06, AP12, AP14, AP16, AP18; no confirma modelo ni facts |
| Cambio condicionado | 1 | AP07/J253: espera contrato de contenido/cardinalidad y consumo |
| Investigación de identidad pendiente | 2 | AP10/GZ0009 y AP17/GZ0010; no inventar familia por categoría o nombre genérico |

Root inspeccionó también las imágenes de NNV55, C494, J253, PMA7-15T, rotor
BMX y 1062. Las observaciones restantes conservan atribución al revisor; no se
presentan como inspección física ni identificación OEM de las unidades.
Cada registro retiene su siguiente investigación bajo responsabilidad de
Codex/Claude, sus dudas, preimagen y exigencias de conservación.

Se rechaza la especialización opcional de C494: `bearing` ya representa un
canastillo con aplicación Pedalier. No hay razón técnica para cambiar su
familia sólo por normalización editorial. Thompson no se transforma en
Americano ni en una medida deducida.

AG02 se resuelve **para representación local**: el conjunto de freno puede
tener contenido parcial sin que el rótulo presuma manillas. La discrepancia
Logan/Ozono continúa sin resolver y no autoriza modificar marca/modelo. El
JSON independiente usaba `proposed_family`/`family_after` para la clave de
plantilla. Se distingue explícitamente `mechanical_disc_brake` (plantilla) de
`complete_brake` (familia técnica canónica); el cambio de rótulo no altera
ninguna de esas identidades.

Las diez decisiones y el cambio condicionado sólo proponen
`products.spec_template_id`. No cambian categorías compartidas, nombres,
marcas, modelos, facts, opciones, lecturas, inventario, comerciales ni sets.
Las siete observaciones de cámara y tres de C1087 permanecen conservadas con
su procedencia y sus ambigüedades. La preimagen de producción es histórica,
del `2026-09-07T14:05:53Z`: debe releerse mediante el snapshot autenticado antes
de cualquier aplicación y abortar si cambió. El hash de plantilla también es
local; no demuestra que esté publicada.

**Aplicaciones: 0. Llenado: 0.** Sigue faltando el aplicador acotado y su prueba
de preservación/recuperación; estas decisiones no cierran los otros productos
asignados ni los 742 sin ficha, ni adelantan el llenado al saneamiento global.
