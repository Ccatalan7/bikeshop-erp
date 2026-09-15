# Revisión independiente · observaciones sin confirmar en el consumidor de compatibilidad — 2026-09-14

Ronda 216. Diagnóstico acotado sobre el caso de
`unconfirmed-fact-consumer-evidence-2026-09-14.md` (`46463edb…`): asignar la
cámara SKU 6927116185398 a `tube` conservando sus siete observaciones de
agosto (`confirmed = false`, dos `inferred`, cinco `supplier_text`). Sin SQL,
runtime ni cambios de datos; sin política global de `confirmed`; sin
auditoría de familias. No se asignó la cámara.

## Método

1. Proyección real, no un booleano aislado: leí `get_product_spec_contexts_v1`
   (`20260906160000:…`), que entrega al cliente `spec_active_product_values_internal_v1(producto, plantilla)`
   fusionado con `__reference_claims`, `__technical_family`, `__template_key`,
   `__template_id`, `__binding_source`, `__unassigned_facts` y `__spec_issues`
   (= `spec_validate_draft_internal_v1` sobre esos mismos valores). Esa
   proyección **no lleva `confirmed` ni `source` por hecho**: el consumidor
   recibe valores, no procedencia.
2. Tomé como entrada exactamente los `target_values` de la sonda productiva de
   Root (`.tmp/product-spec-catalog/assignment-existing-tube-20260914/target-probe.json`,
   tube v6, 0 incidencias, 0 hechos fuera) más el sobre anterior con
   `__spec_issues: []`, y el estado previo a la asignación
   (`__binding_source: none`, `__spec_issues: [{code: unmapped}]`, sin
   valores).
3. Fixture Dart propia en
   `.tmp/product-spec-catalog/unconfirmed_tube_consumer_probe_test.dart`
   (gitignored) que llama al servicio real
   `BikeProductCompatibilityService.buildAutocompleteAssessments` con el mismo
   armado de `Bike`/`BikeProfile` que su test existente, en seis bicis
   sintéticas: coincidencia de aro y válvula (700c/Presta), desacuerdo de aro
   (26"), 29" (mismo BSD que 700c), desacuerdo de válvula (Schrader), bici sin
   datos, y sólo aro. Dos casos más: hechos no usados por la regla alterados
   (anchos 1–100, largo 999) con una marca `__confirmed` artificial, y un aro
   contradictorio (20") en la cámara.

## Resultado observado (14 casos, todos PASS)

| Bici sintética | Antes de asignar | Después de asignar (7 observaciones sin confirmar) |
|---|---|---|
| 700c / Presta (coincide) | sin veredicto (`null`) | **caution** · «coincide en aro 700c · válvula Presta; confirma el rango de aplicación completo del fabricante y la longitud de válvula» |
| 26" / Presta | sin veredicto | **caution** · «rotulada 700c y bici 26": compara el BSD y el intervalo de ancho…» |
| 29" / Presta | sin veredicto | **caution** · igual que 26" (no asimila 29" a 700c) |
| 700c / Schrader | sin veredicto | **caution** · «Presta y válvula actual Schrader: confirma agujero de llanta…; el tipo actual no mide el agujero» |
| sin datos | sin veredicto | **caution** · «falta confirmar rodado…, tipo de válvula…» |
| sólo aro 700c | sin veredicto | **caution** · «coincide aro 700c; falta confirmar tipo de válvula» |
| anchos/largo alterados + `__confirmed` | — | idéntico al caso coincidente (nivel y texto) |
| cámara 20" vs bici 700c | — | **caution**, no `incompatible` |

**Ningún camino produce `compatible` ni `incompatible`.** Causa en código, no
en un booleano: `_assessDetailedTubeCompatibility` (:1769-1836) devuelve
`caution` o `null` en todas sus ramas; `_assessTubeFamilyCompatibility`
(:2008-2032) también; `_mergeAssessments` (:315-324) sólo deja pasar un
`incompatible` de familia, que para `tube` no existe. La regla lee únicamente
`wheel_size` y `valve_type`; anchos, largo de válvula, material y sellante no
entran en el veredicto. Antes de asignar, sin `__technical_family` no hay
mapeo y el producto queda sin veredicto.

Conclusión para el caso: **la asignación deja la cámara en cautela en todos los
escenarios probados**; no hay aprobación ni rechazo mecánico injustificado
atribuible a que las observaciones estén sin confirmar. Lo que cambia es que
el consumidor pasa de «sin veredicto» a «cautela con detalle», y ese detalle
cita el aro y la válvula tomados de texto de proveedor sin marcarlos como no
confirmados.

## Hipótesis e impacto

- Hecho: el contrato de proyección no distingue origen; `confirmed` y
  `source` viven en `spec_facts`/`unassigned_facts`, no en `values`.
- Hipótesis: para `tube` (y por la misma estructura `rim_strip`, cuyo cuerpo
  es paralelo) la ausencia de una guardia de confianza es inofensiva hoy
  porque la familia nunca certifica. **No generalizo** a familias con ramas
  `compatible`/`incompatible` (rotor, hub, cadena…): eso requiere su propia
  fixture y no forma parte de esta ronda.
- Impacto de la asignación: sólo palabras. El texto «Cámara coincide en aro
  700c · válvula Presta» afirma una coincidencia leída de texto de proveedor;
  el operador no ve que ambos datos siguen sin confirmar.

## Limitaciones

- Fixture con bici sintética; la proyección de la cámara es la real de la
  sonda, pero no ejecuté `get_product_spec_contexts_v1` ni asigné el producto.
- No probé la proyección de fichas públicas ni los criterios de compras
  (nombrados en la evidencia): otro consumidor, otra ronda.
- La sonda de Root cubre la plantilla `tube` v6; un cambio de contrato
  posterior cambiaría `__spec_issues` y esta lectura.

## Corrección mínima (opcional; no hay defecto reproducible de veredicto)

No propongo regla sobre `confirmed`. Si se quiere que el detalle no afirme
una coincidencia leída de proveedor, el cambio mínimo es de palabras y local a
la rama coincidente de `_assessDetailedTubeCompatibility` (:1808-1813): usar
«rotulada» en vez de «coincide» cuando el dato venga sin confirmar —lo que
exige que la proyección exponga esa marca (p. ej. `__unconfirmed_keys`, lista
de claves), decisión de contrato que corresponde a Root, no a este diagnóstico.

## Qué no toqué

Ningún código, test, SQL, dato ni archivo de Root. Sólo este documento y la
fixture temporal en `.tmp/`.
