# Contenido documentado y máximos por fuente

Etapa local sobre WSS residual `00041bb8…`, sin reescribirlo. El compilador
`compile_product_spec_evidence_scopes_addendum.py` adjudica la revisión de
[contenido](package-contents-boundary-review-2026-09-07.md) y la propuesta de
[Claude sobre presiones](tire-pressure-dual-unit-proposal-2026-09-07.md).

La tabla de platos conserva una ocurrencia por corona incluida. La posición
OEM es opcional y puede repetirse entre piezas suministradas; dos coronas
integradas en una pieza siguen contando como dos. La validación de cantidad
frente a filas se implementa por separado; esta etapa no afirma que funcione.

`tire_general_max_pressures` conserva cifras impresas, unidad, alcance y
documento. Root verificó [Schwalbe Europa](https://www.schwalbe.com/en/Marathon-Plus-11100769)
y [Schwalbe EE. UU.](https://www.schwalbetires.com/Marathon-Plus-11100769): el
artículo 11100769, 37-622, publica máximos de 6 bar y 85 psi. Se conservan
ambas declaraciones sin convertirlas. El año 2014 del título de una página no
prueba una edición documental: se retiró esa atribución de los fixtures con
preimágenes exactas, manteniendo la fecha de consulta.

El máximo condicionado a un montaje permanece en otra tabla. Root verificó
la [tabla Continental](https://www.continental-tires.com/us/en/tire-knowledge/hookless-vs-hooked-rims/):
GP5000 S TR 700×28c declara 5 bar, 72 psi y ancho interno máximo 23 mm para
hookless. La [página del modelo](https://www.continental-tires.com/products/bicycle/tires/grand-prix-5000-s-tr/)
remite al envase y distingue aplicaciones hooked/hookless. No se promueve
ninguna de esas cifras a un máximo general para todo montaje.

TPDU-02 traía preimagen anterior a R6: se rebasó explícitamente para añadir
únicamente las condiciones de la tabla nueva, conservando los requisitos
hookless integrados. La retirada del escalar psi se rechazó como duplicada
porque ya estaba aplicada en la base. No se eliminaron observaciones legacy.

| Artefacto | Resultado |
| --- | --- |
| all-family-evidence-scopes-integrated-2026-09-07.json | SHA `e709158d0ac49603ab01dfde19326d1f9f2fd0d0ce50723cb5d0076390226d9d`; 105 plantillas, 711 definiciones, 58 tablas, 1.218 usos |
| all-family-evidence-scopes-cases-integrated-2026-09-07.json | SHA `456946a2bb7b2ca23bb9decc77a729a5f157eec7ce983f27d8f0aaaeab5b884e`; 302 casos |
| Dart | 411 pruebas pasan; se verifica también que validar conserve valores, IDs y fuentes sin mutarlos |
| SQL | 302 casos pasan tras 2500, con rollback y preservación. Log `.tmp/db/spec-all-family-evidence-scopes-trial-after-2500.log`; fallo previo conservado sin rebajar expectativas |

El ensayo SQL encontró un defecto real: una celda requerida que contiene el
token `Desconocido / sin confirmar` se considera incompleta en Dart, pero el
servidor miraba únicamente si la clave existía. Se conserva la expectativa
de pendiente y 2500 corrigió el servidor; no se rebajó la prueba. `false` y cero
siguen siendo valores conocidos, sin convertir desconocido en incompatibilidad.

Siguen abiertos el alcance de documentos en `tire_rim_configurations`, los
conflictos entre fuentes y los gates globales. La [etapa posterior de
cardinalidad](cardinality-integration-2026-09-07.md) añade la relación explícita
entre total y ocurrencias de coronas, con límites documentados. Una declaración
representable no aprueba un montaje. No hubo publicación ni llenado.
